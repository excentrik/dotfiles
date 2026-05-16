#!/usr/bin/env python3
"""Report or install role package dependencies."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
PACKAGE_DIR = BASE_DIR / "meta" / "packages"
SUPPORTED_PACKAGE_MANAGERS = {"apt"}


def unique(items):
    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def load_metadata(role):
    metadata_path = PACKAGE_DIR / f"{role}.json"
    if not metadata_path.exists():
        return None

    with metadata_path.open(encoding="utf-8") as metadata_file:
        return json.load(metadata_file)


def detect_package_manager(host):
    if host not in {"unix", "wsl", "docker"}:
        return None
    if shutil.which("apt-get") and shutil.which("dpkg-query"):
        return "apt"
    return None


def apt_package_installed(package):
    result = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}", package],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return result.returncode == 0 and "install ok installed" in result.stdout


def missing_for_role(metadata, package_manager):
    missing_commands = []
    manual_commands = []
    packages = []

    for command in metadata.get("commands", []):
        name = command["name"]
        if shutil.which(name):
            continue

        command_packages = command.get(package_manager, [])
        missing_commands.append((name, command_packages, command.get("message")))
        if command_packages:
            packages.extend(command_packages)
        else:
            manual_commands.append((name, command.get("message")))

    for package in metadata.get("packages", {}).get(package_manager, []):
        if package_manager == "apt" and not apt_package_installed(package):
            packages.append(package)

    return missing_commands, manual_commands, unique(packages)


def print_missing(role, package_manager, missing_commands, manual_commands, packages):
    print(f"Package dependencies missing for role '{role}':")
    for name, command_packages, message in missing_commands:
        package_hint = ""
        if command_packages:
            package_hint = f" (apt package: {', '.join(command_packages)})"
        print(f"  - command '{name}' not found{package_hint}")
        if message:
            print(f"    {message}")

    if packages and package_manager == "apt":
        print(f"Install with: sudo apt-get update && sudo apt-get install -y {' '.join(packages)}")
        print("Or rerun dotfiles with: DOTFILES_BOOTSTRAP=1 ./install <host>")

    for name, message in manual_commands:
        if not message:
            print(f"  Manual action needed for '{name}'; no apt package is declared.")


def confirm_install(role, package_manager, packages):
    if os.environ.get("DOTFILES_NO_INTERACTIVE") or not sys.stdin.isatty():
        return True

    response = input(
        f"Install {package_manager} packages for role '{role}': {', '.join(packages)}? [y/N] "
    )
    return response.lower().startswith("y")


def run_apt_install(packages, dry_run):
    sudo = [] if os.geteuid() == 0 else ["sudo"]
    commands = [
        sudo + ["apt-get", "update"],
        sudo + ["apt-get", "install", "-y", *packages],
    ]

    if dry_run:
        for command in commands:
            print("Would run: " + " ".join(command))
        return 0

    if sudo and not shutil.which("sudo"):
        print("sudo is required to install apt packages as a non-root user.", file=sys.stderr)
        return 1

    env = os.environ.copy()
    if os.environ.get("DOTFILES_NO_INTERACTIVE") or not sys.stdin.isatty():
        env["DEBIAN_FRONTEND"] = "noninteractive"

    for command in commands:
        subprocess.run(command, check=True, env=env)
    return 0


def validate_metadata():
    failures = 0
    role_dir = BASE_DIR / "meta" / "roles"
    role_names = {path.stem for path in role_dir.glob("*.yaml")}

    if not PACKAGE_DIR.exists():
        return 0

    for metadata_path in sorted(PACKAGE_DIR.glob("*.json")):
        role = metadata_path.stem
        if role not in role_names:
            print(f"{metadata_path} has no matching role config.", file=sys.stderr)
            failures += 1

        try:
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            print(f"{metadata_path}: invalid JSON: {error}", file=sys.stderr)
            failures += 1
            continue

        commands = metadata.get("commands", [])
        if not isinstance(commands, list):
            print(f"{metadata_path}: commands must be a list.", file=sys.stderr)
            failures += 1
            continue

        for command in commands:
            if not isinstance(command, dict) or not isinstance(command.get("name"), str):
                print(f"{metadata_path}: each command needs a string name.", file=sys.stderr)
                failures += 1
                continue
            if "message" in command and not isinstance(command["message"], str):
                print(f"{metadata_path}: command {command['name']} message must be a string.", file=sys.stderr)
                failures += 1
            for manager in SUPPORTED_PACKAGE_MANAGERS:
                if manager in command and (
                    not isinstance(command[manager], list)
                    or not all(isinstance(item, str) for item in command[manager])
                ):
                    print(f"{metadata_path}: command {command['name']} has invalid {manager} packages.", file=sys.stderr)
                    failures += 1

        packages = metadata.get("packages", {})
        if not isinstance(packages, dict):
            print(f"{metadata_path}: packages must be an object.", file=sys.stderr)
            failures += 1
            continue

        for manager, package_names in packages.items():
            if manager not in SUPPORTED_PACKAGE_MANAGERS:
                print(f"{metadata_path}: unsupported package manager '{manager}'.", file=sys.stderr)
                failures += 1
            if not isinstance(package_names, list) or not all(isinstance(item, str) for item in package_names):
                print(f"{metadata_path}: packages.{manager} must be a string list.", file=sys.stderr)
                failures += 1

    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", help="Dotfiles host profile name")
    parser.add_argument("--role", help="Role name to check")
    parser.add_argument("--bootstrap", action="store_true", help="Install missing packages")
    parser.add_argument("--dry-run", action="store_true", help="Print install commands without running them")
    parser.add_argument("--validate", action="store_true", help="Validate package metadata")
    args = parser.parse_args()

    if args.validate:
        return validate_metadata()

    if not args.host or not args.role:
        parser.error("--host and --role are required unless --validate is used")

    metadata = load_metadata(args.role)
    if metadata is None:
        return 0

    package_manager = detect_package_manager(args.host)
    if package_manager is None:
        if args.bootstrap and args.host in {"osx"}:
            print("macOS/Homebrew package bootstrap is tracked separately; skipping package bootstrap.")
        return 0

    missing_commands, manual_commands, packages = missing_for_role(metadata, package_manager)
    if not missing_commands and not packages:
        return 0

    print_missing(args.role, package_manager, missing_commands, manual_commands, packages)
    if not args.bootstrap:
        return 0

    if not packages:
        print(f"No installable {package_manager} packages declared for missing role '{args.role}' dependencies.")
        return 1

    if not args.dry_run and not confirm_install(args.role, package_manager, packages):
        print("Skipping package installation.")
        return 0

    if package_manager == "apt":
        return run_apt_install(packages, args.dry_run)

    print(f"Unsupported package manager: {package_manager}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
