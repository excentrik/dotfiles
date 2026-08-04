import os
import shutil
import subprocess
import sys

import dotbot


YUM_PACKAGE_ALIASES = {
    "iproute2": ["iproute2", "iproute"],
    "netcat-openbsd": ["netcat-openbsd", "nmap-ncat"],
    "nodejs": ["nodejs", "nodejs18"],
    "npm": ["npm", "nodejs18"],
    "openssh-client": ["openssh-client", "openssh-clients"],
}

YUM_INSTALL_PACKAGES = {
    "iproute2": "iproute",
    "netcat-openbsd": "nmap-ncat",
    "nodejs": "nodejs18",
    "npm": "nodejs18",
    "openssh-client": "openssh-clients",
}


class Apt(dotbot.Plugin):
    supports_dry_run = True
    _aptDirective = "apt"

    def can_handle(self, directive):
        return directive == self._aptDirective

    def handle(self, directive, data):
        if directive != self._aptDirective:
            raise ValueError(f"Apt cannot handle directive {directive}")

        packages = self._normalize_packages(data)
        if not packages:
            return True

        package_list = ", ".join(packages)
        source = self._source_label()

        if not sys.platform.startswith("linux"):
            self._log.info(f"apt directive for {source} is only supported on Linux-family hosts, skipping")
            return True

        package_manager = self._package_manager()
        if package_manager is None:
            self._log.warning(
                f"apt directive for {source} requires apt-get/dpkg-query or yum/rpm "
                f"to check packages ({package_list}), skipping"
            )
            return True

        missing = [
            package for package in packages if not self._package_installed(package_manager, package)
        ]
        if not missing:
            self._log.info(f"All packages are installed for {source} using {package_manager}")
            return True

        if self._context.dry_run():
            install_packages = self._install_packages(package_manager, missing)
            for command in self._package_commands(package_manager, install_packages):
                self._log.action("Would run: " + " ".join(command))
            return True

        if os.environ.get("DOTFILES_BOOTSTRAP") != "1":
            self._log.warning(
                f"Missing packages for {source} using {package_manager}: {', '.join(missing)}"
            )
            self._log.warning("Rerun with --bootstrap or DOTFILES_BOOTSTRAP=1 to install them.")
            return True

        return self._install(package_manager, self._install_packages(package_manager, missing))

    def _normalize_packages(self, data):
        if not isinstance(data, list):
            raise ValueError("apt directive must be a list of package names")

        packages = []
        for item in data:
            if not isinstance(item, str):
                raise ValueError("apt directive entries must be package-name strings")
            packages.append(item)
        return packages

    def _source_label(self):
        config_files = getattr(self._context.options(), "config_file", None) or []
        if not config_files:
            return "the current config"

        config_file = config_files[0]
        normalized = config_file.replace(os.sep, "/")
        if normalized.startswith("meta/roles/") and normalized.endswith(".yaml"):
            role = os.path.splitext(os.path.basename(config_file))[0]
            return f"role '{role}'"
        return config_file

    def _package_manager(self):
        if shutil.which("apt-get") and shutil.which("dpkg-query"):
            return "apt"
        if shutil.which("yum") and shutil.which("rpm"):
            return "yum"
        return None

    def _package_installed(self, package_manager, package):
        if package_manager == "apt":
            return self._apt_package_installed(package)
        if package_manager == "yum":
            return self._rpm_package_installed(package)
        raise ValueError(f"Unsupported package manager: {package_manager}")

    def _apt_package_installed(self, package):
        result = subprocess.run(
            ["dpkg-query", "-W", "-f=${Status}", package],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        return result.returncode == 0 and "install ok installed" in result.stdout

    def _rpm_package_installed(self, package):
        for candidate in YUM_PACKAGE_ALIASES.get(package, [package]):
            result = subprocess.run(
                ["rpm", "-q", candidate],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode == 0:
                return True
        return False

    def _install_packages(self, package_manager, packages):
        resolved = []
        for package in packages:
            install_package = package
            if package_manager == "yum":
                install_package = YUM_INSTALL_PACKAGES.get(package, package)
            if install_package not in resolved:
                resolved.append(install_package)
        return resolved

    def _package_commands(self, package_manager, packages):
        sudo = [] if os.geteuid() == 0 else ["sudo"]
        if package_manager == "apt":
            return [
                sudo + ["apt-get", "update"],
                sudo + ["apt-get", "install", "-y", *packages],
            ]
        if package_manager == "yum":
            return [sudo + ["yum", "install", "-y", *packages]]
        raise ValueError(f"Unsupported package manager: {package_manager}")

    def _install(self, package_manager, packages):
        commands = self._package_commands(package_manager, packages)
        sudo = [] if os.geteuid() == 0 else ["sudo"]
        if sudo and not shutil.which("sudo"):
            self._log.error("sudo is required to install packages as a non-root user.")
            return False

        env = os.environ.copy()
        if package_manager == "apt" and (
            os.environ.get("DOTFILES_NO_INTERACTIVE") or not sys.stdin.isatty()
        ):
            env["DEBIAN_FRONTEND"] = "noninteractive"

        for command in commands:
            self._log.info("Running: " + " ".join(command))
            result = subprocess.run(command, check=False, env=env)
            if result.returncode != 0:
                self._log.warning("Failed to run: " + " ".join(command))
                return False
        return True
