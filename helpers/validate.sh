#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${BASE_DIR}"
source helpers/role_dependencies.sh

usage() {
  cat <<'USAGE'
Usage: helpers/validate.sh [--all-roles]

Runs non-mutating validation checks:
  - Bash syntax checks
  - Python syntax checks
  - Apt directive message checks
  - Optional zsh syntax checks when zsh is installed
  - Host role reference checks
  - Role dependency graph checks
  - Role dependency dry-run safety checks
  - Dotbot link target checks
  - README generated command documentation drift checks
  - Dotbot dry-runs using a temporary HOME

By default, role checks are limited to Linux/WSL-oriented hosts: unix, wsl, docker.
Use --all-roles to include every role config, including macOS and zsh.
USAGE
}

ALL_ROLES=0
for arg in "$@"; do
  case "${arg}" in
    --all-roles)
      ALL_ROLES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

status() {
  printf '\n==> %s\n' "$1"
}

add_unique() {
  local item="$1"
  shift
  local existing
  for existing in "$@"; do
    if [ "${existing}" = "${item}" ]; then
      return 1
    fi
  done
  return 0
}

PYTHON_CANDIDATES=""

add_python_candidate() {
  local candidate="$1"

  [ -n "${candidate}" ] || return 0
  [ -x "${candidate}" ] || return 0

  if printf '%s\n' "${PYTHON_CANDIDATES}" | grep -Fxq -- "${candidate}"; then
    return 0
  fi

  PYTHON_CANDIDATES="${PYTHON_CANDIDATES}${PYTHON_CANDIDATES:+
}${candidate}"
}

collect_python_candidates() {
  local candidate

  PYTHON_CANDIDATES=""

  add_python_candidate "$(command -v python3 2>/dev/null || true)"

  while IFS= read -r candidate; do
    add_python_candidate "${candidate}"
  done < <(type -a -P python3 2>/dev/null || true)

  for candidate in \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /opt/local/bin/python3 \
    /usr/bin/python3
  do
    add_python_candidate "${candidate}"
  done
}

python_has_yaml() {
  "$1" - <<'PY' >/dev/null 2>&1
import yaml
PY
}

python_has_vendored_yaml() {
  PYTHONPATH="${BASE_DIR}/dotbot/lib/pyyaml/lib${PYTHONPATH:+:${PYTHONPATH}}" "$1" - <<'PY' >/dev/null 2>&1
import yaml
PY
}

find_validate_python() {
  local candidate

  collect_python_candidates

  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    if python_has_yaml "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done <<EOF
${PYTHON_CANDIDATES}
EOF

  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    if python_has_vendored_yaml "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done <<EOF
${PYTHON_CANDIDATES}
EOF

  echo "Unable to find a Python 3 runtime that can import yaml." >&2
  echo "Checked PATH python3 plus /opt/homebrew/bin/python3, /usr/local/bin/python3, /opt/local/bin/python3, and /usr/bin/python3." >&2
  return 1
}

collect_role_configs() {
  local configs=()
  local role
  local host
  local host_file
  local role_file
  local roles=()

  configs+=("meta/base.yaml")

  if [ "${ALL_ROLES}" -eq 1 ]; then
    for role_file in meta/roles/*.yaml; do
      configs+=("${role_file}")
    done
  else
    for host in unix wsl docker; do
      host_file="meta/hosts/${host}.yaml"
      if [ ! -f "${host_file}" ]; then
        echo "Missing host file: ${host_file}" >&2
        return 1
      fi

      while IFS= read -r role; do
        [ -n "${role}" ] && roles+=("${role}")
      done < <(sed -n 's/^[[:space:]]*-[[:space:]]*\([^:[:space:]]*\):.*/\1/p' "${host_file}")
    done

    role_deps_expand_roles "${roles[@]}"
    for role in "${EXPANDED_ROLES[@]}"; do
      role_file="meta/roles/${role}.yaml"
      if add_unique "${role_file}" "${configs[@]}"; then
        configs+=("${role_file}")
      fi
    done
  fi

  printf '%s\n' "${configs[@]}"
}

check_bash_syntax() {
  status "Checking Bash syntax"
  local files=(
    install
    install-role
    generate_shortcuts_documentation.sh
    helpers/*.sh
    home_files/bin/copilot
    home_files/.bash_profile
    home_files/.bashrc
    home_files/.bash_aliases
    home_files/.path
    home_files/.exports
    home_files/.profile
    home_files/.startup
    home_files/.bash_prompt
    home_files/.aliases/*.sh
  )
  bash -n "${files[@]}"
}

check_python_syntax() {
  status "Checking Python syntax"
  "${VALIDATE_PYTHON}" -m py_compile dotbot-apt/apt.py dotbot-role-deps/role_deps.py
}

check_apt_messages() {
  status "Checking apt directive messages"
  "${VALIDATE_PYTHON}" <<'PY'
import importlib.util
import os
import sys
from argparse import Namespace
from contextlib import redirect_stdout
from io import StringIO

sys.path.insert(0, "dotbot/lib/pyyaml/lib")
sys.path.insert(0, "dotbot/src")

from dotbot.context import Context  # noqa: E402

spec = importlib.util.spec_from_file_location("dotbot_apt", "dotbot-apt/apt.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

context = Context(
    os.getcwd(),
    Namespace(dry_run=False, config_file=["meta/roles/vim.yaml"]),
)
plugin = module.Apt(context)

original_platform = sys.platform
original_path = os.environ.get("PATH", "")
sys.platform = "linux"
os.environ["PATH"] = ""
try:
    output = StringIO()
    with redirect_stdout(output):
        plugin.handle("apt", ["vim"])
finally:
    sys.platform = original_platform
    os.environ["PATH"] = original_path

message = output.getvalue()
expected = "apt directive for role 'vim' requires apt-get/dpkg-query or yum/rpm to check packages (vim), skipping"
if expected not in message:
    raise SystemExit(f"Expected apt warning to include role and packages; got: {message!r}")

dry_run_context = Context(
    os.getcwd(),
    Namespace(dry_run=True, config_file=["meta/roles/tmux.yaml"]),
)
dry_run_plugin = module.Apt(dry_run_context)
original_which = module.shutil.which
original_run = module.subprocess.run
original_platform = sys.platform

def fake_which(command):
    if command in {"rpm", "yum"}:
        return f"/usr/bin/{command}"
    return None

class Result:
    returncode = 1

def fake_run(*args, **kwargs):
    return Result()

module.shutil.which = fake_which
module.subprocess.run = fake_run
sys.platform = "linux"
try:
    output = StringIO()
    with redirect_stdout(output):
        dry_run_plugin.handle("apt", ["tmux"])
    tmux_message = output.getvalue()

    output = StringIO()
    with redirect_stdout(output):
        dry_run_plugin.handle("apt", ["curl", "nodejs", "npm"])
    node_message = output.getvalue()

    output = StringIO()
    with redirect_stdout(output):
        dry_run_plugin.handle("apt", ["openssh-client", "netcat-openbsd", "iproute2"])
    mariner_message = output.getvalue()
finally:
    module.shutil.which = original_which
    module.subprocess.run = original_run
    sys.platform = original_platform

if "Would run: " not in tmux_message or "yum install -y tmux" not in tmux_message:
    raise SystemExit(f"Expected yum dry-run install command; got: {tmux_message!r}")
if "yum install -y curl nodejs18" not in node_message or "nodejs npm" in node_message:
    raise SystemExit(f"Expected yum dry-run to map nodejs/npm to nodejs18; got: {node_message!r}")
if "yum install -y openssh-clients nmap-ncat iproute" not in mariner_message:
    raise SystemExit(f"Expected yum dry-run to map Mariner package names; got: {mariner_message!r}")
PY
}

check_zsh_syntax() {
  status "Checking zsh syntax"
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh not found; skipping zsh syntax checks"
    return 0
  fi

  zsh -n \
    home_files/.zshrc \
    home_files/.ohmyzshrc \
    home_files/.zshenv \
    home_files/.zsh_aliases \
    home_files/.zsh_prompt
}

check_link_targets() {
  status "Checking Dotbot link targets"
  local configs=("$@")
  local failures=0
  local yaml
  local target

  while IFS=: read -r yaml target; do
    [ -n "${target}" ] || continue
    if [ ! -e "${target}" ]; then
      echo "${yaml} references missing target: ${target}" >&2
      failures=$((failures + 1))
    fi
  done < <(
    awk '{
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^home_files\//) {
          gsub(/[,"'\''"]/, "", $i)
          print FILENAME ":" $i
        }
      }
    }' "${configs[@]}"
  )

  if [ "${failures}" -ne 0 ]; then
    return 1
  fi
}

check_role_dependencies() {
  status "Checking role dependencies"
  role_deps_validate_graph
}

check_role_dependency_failures() {
  status "Checking role dependency failure handling"
  local tmp_meta
  local output
  local expanded

  tmp_meta="$(mktemp -d)"
  mkdir -p "${tmp_meta}/roles"
  printf -- '- depends:\n    - missing-role\n' > "${tmp_meta}/roles/parent.yaml"

  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    EXPANDED_ROLES=() \
    ROLE_EXPANSION_STACK=() \
    role_deps_expand_roles parent 2>&1
  )"; then
    echo "Expected missing dependency to fail role expansion." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  printf -- '- depends: [child, sibling] # inline dependencies with comment\n' > "${tmp_meta}/roles/parent.yaml"
  printf -- '- shell: []\n' > "${tmp_meta}/roles/child.yaml"
  printf -- '- shell: []\n' > "${tmp_meta}/roles/sibling.yaml"
  if ! output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}"
    EXPANDED_ROLES=()
    ROLE_EXPANSION_STACK=()
    role_deps_expand_roles parent 2>&1
    printf '%s\n' "${EXPANDED_ROLES[*]}"
  )"; then
    echo "Expected inline dependencies to expand successfully." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi
  expanded="$(printf '%s\n' "${output}" | tail -1)"
  if [ "${expanded}" != "child sibling parent" ]; then
    echo "Expected inline dependencies to expand before parent; got: ${expanded}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  rm -rf "${tmp_meta}"
}

check_copilot_settings_enable_experimental() {
  status "Checking Copilot settings enable experimental mode"

  python3 - "${BASE_DIR}/home_files/.copilot/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as settings_file:
    settings = json.load(settings_file)

if settings.get("experimental") is not True:
    raise SystemExit("Expected default Copilot settings to set experimental=true")
PY
}

check_copilot_setup_merges_experimental_default() {
  status "Checking Copilot setup merges experimental default"
  local tmp_home
  local tmp_bin
  local output

  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.copilot"

  cat > "${tmp_bin}/copilot" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) printf '%s\n' 'GitHub Copilot CLI 1.0.60' ;;
  *) printf '%s\n' "$*" ;;
esac
SH
  chmod +x "${tmp_bin}/copilot"

  printf '%s\n' '{"model":"gpt-5.3-codex"}' > "${tmp_home}/.copilot/settings.json"
  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:${PATH}" \
    helpers/copilot_setup.sh 2>&1
  )"; then
    echo "${output}" >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  if ! python3 - "${tmp_home}/.copilot/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as settings_file:
    settings = json.load(settings_file)

if settings.get("experimental") is not True:
    raise SystemExit(1)
PY
  then
    echo "Expected Copilot setup to add experimental=true when missing." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  printf '%s\n' '{"experimental":false}' > "${tmp_home}/.copilot/settings.json"
  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:${PATH}" \
    helpers/copilot_setup.sh 2>&1
  )"; then
    echo "${output}" >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  if ! python3 - "${tmp_home}/.copilot/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as settings_file:
    settings = json.load(settings_file)

if settings.get("experimental") is not False:
    raise SystemExit(1)
PY
  then
    echo "Expected Copilot setup to preserve explicit experimental=false." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  rm -rf "${tmp_home}" "${tmp_bin}"
}

check_copilot_wrapper_supports_experimental_opt_out() {
  status "Checking Copilot wrapper supports experimental opt-out"
  local tmp_home
  local fake_bin
  local output
  local resolved

  tmp_home="$(mktemp -d)"
  fake_bin="${tmp_home}/.local/bin"
  mkdir -p "${tmp_home}/bin" "${fake_bin}"
  ln -s "${BASE_DIR}/home_files/bin/copilot" "${tmp_home}/bin/copilot"

  cat > "${fake_bin}/copilot" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*"
SH
  chmod +x "${fake_bin}/copilot"

  resolved="$(HOME="${tmp_home}" PATH="/usr/bin:/bin" bash -c 'source "$1"; command -v copilot' _ "${BASE_DIR}/home_files/.path")"
  if [ "${resolved}" != "${tmp_home}/bin/copilot" ]; then
    echo "Expected ~/bin/copilot to precede ~/.local/bin/copilot; resolved: ${resolved}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  output="$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${fake_bin}:/usr/bin:/bin" "${tmp_home}/bin/copilot" status)"
  if [ "${output}" != "status" ]; then
    echo "Expected Copilot wrapper to rely on settings for experimental mode; got: ${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  output="$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${fake_bin}:/usr/bin:/bin" "${tmp_home}/bin/copilot" --no-experimental status)"
  if [ "${output}" != "--no-experimental status" ]; then
    echo "Expected Copilot wrapper to preserve --no-experimental opt-out; got: ${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  output="$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${fake_bin}:/usr/bin:/bin" DOTFILES_COPILOT_EXPERIMENTAL=0 "${tmp_home}/bin/copilot" status)"
  if [ "${output}" != "--no-experimental status" ]; then
    echo "Expected DOTFILES_COPILOT_EXPERIMENTAL=0 to pass --no-experimental; got: ${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  output="$(HOME="${tmp_home}" PATH="${tmp_home}/bin:${fake_bin}:/usr/bin:/bin" DOTFILES_COPILOT_EXPERIMENTAL=0 "${tmp_home}/bin/copilot" --experimental status)"
  if [ "${output}" != "--experimental status" ]; then
    echo "Expected explicit --experimental to override DOTFILES_COPILOT_EXPERIMENTAL=0; got: ${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  rm -rf "${tmp_home}"
}

check_tmux_setup_repairs_broken_tpm_link() {
  status "Checking tmux setup repairs broken TPM links"
  local tmp_home
  local tmp_bin
  local linked_tpm

  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p \
    "${tmp_home}/.tmux/plugins" \
    "${tmp_home}/.tmux/plugins/tmux-resurrect" \
    "${tmp_home}/.tmux/plugins/tmux-continuum"
  ln -s "${tmp_home}/missing-tpm" "${tmp_home}/.tmux/plugins/tpm"

  cat > "${tmp_bin}/tmux" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-V" ]; then
  echo "tmux 3.4"
fi
SH
  chmod +x "${tmp_bin}/tmux"

  if ! HOME="${tmp_home}" PATH="${tmp_bin}:/usr/bin:/bin" helpers/tmux_setup.sh >/dev/null; then
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  linked_tpm=$(readlink "${tmp_home}/.tmux/plugins/tpm")
  if [ "${linked_tpm}" != "${BASE_DIR}/tpm" ] || [ ! -x "${tmp_home}/.tmux/plugins/tpm/bin/install_plugins" ]; then
    echo "Expected broken TPM link to be repaired with the managed checkout." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  if [ "$("${VALIDATE_PYTHON}" -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "${tmp_home}/.tmux/resurrect")" != "0o700" ]; then
    echo "Expected tmux-resurrect storage to use mode 0700." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  rm -rf "${tmp_home}" "${tmp_bin}"
}

check_claude_setup_merges_safe_defaults() {
  status "Checking Claude setup merges safe defaults"
  local tmp_home
  local tmp_bin
  local output

  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.claude"

  cat > "${tmp_bin}/claude" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) printf '%s\n' '2.1.170' ;;
  *) exit 0 ;;
esac
SH
  chmod +x "${tmp_bin}/claude"

  cat > "${tmp_home}/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "existing-plugin@example-marketplace": true
  },
  "extraKnownMarketplaces": {
    "example-marketplace": {
      "source": {
        "source": "github",
        "repo": "example/plugins"
      }
    }
  },
  "model": "sonnet",
  "permissions": {
    "allow": [
      "Bash(git:*)"
    ],
    "defaultMode": "acceptEdits"
  },
  "skipAutoPermissionPrompt": false,
  "theme": "light"
}
JSON

  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:${PATH}" \
    helpers/claude_setup.sh 2>&1
  )"; then
    echo "${output}" >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  if ! python3 - \
    "${BASE_DIR}/home_files/.claude/settings.json" \
    "${tmp_home}/.claude/settings.json" <<'PY'
import json
import sys

source_path, target_path = sys.argv[1], sys.argv[2]

with open(source_path, "r", encoding="utf-8") as source_file:
    source = json.load(source_file)
with open(target_path, "r", encoding="utf-8") as target_file:
    target = json.load(target_file)

if target.get("enabledPlugins") != {"existing-plugin@example-marketplace": True}:
    raise SystemExit("expected existing enabledPlugins to be preserved")
if target.get("extraKnownMarketplaces", {}).get("example-marketplace", {}).get("source", {}).get("repo") != "example/plugins":
    raise SystemExit("expected existing extraKnownMarketplaces to be preserved")
if target.get("model") != "sonnet":
    raise SystemExit("expected existing model to be preserved")
if target.get("theme") != "light":
    raise SystemExit("expected existing theme to be preserved")
if target.get("skipAutoPermissionPrompt") is not False:
    raise SystemExit("expected existing skipAutoPermissionPrompt to be preserved")

permissions = target.get("permissions", {})
if permissions.get("allow") != ["Bash(git:*)"]:
    raise SystemExit("expected existing permissions.allow to be preserved")
if permissions.get("defaultMode") != "acceptEdits":
    raise SystemExit("expected existing permissions.defaultMode to be preserved")
for rule in source["permissions"]["deny"]:
    if rule not in permissions.get("deny", []):
        raise SystemExit(f"expected missing deny rule to be merged: {rule}")

for key, value in source["env"].items():
    if target.get("env", {}).get(key) != value:
        raise SystemExit(f"expected missing env key to be merged: {key}")
for key in ("cleanupPeriodDays", "effortLevel", "autoCompactEnabled", "useAutoModeDuringPlan"):
    if target.get(key) != source.get(key):
        raise SystemExit(f"expected missing default to be merged: {key}")
PY
  then
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  rm -rf "${tmp_home}" "${tmp_bin}"
}

check_dotbot_dry_runs() {
  status "Running Dotbot dry-runs"
  local configs=("$@")
  local tmp_home
  local cfg
  local output

  if [ ! -x "./dotbot/bin/dotbot" ]; then
    echo "Dotbot is missing. Run: git submodule update --init --recursive" >&2
    return 1
  fi

  tmp_home="$(mktemp -d)"

  for cfg in "${configs[@]}"; do
    printf 'Dry-run %s\n' "${cfg}"
    if ! output="$(HOME="${tmp_home}" ./dotbot/bin/dotbot -d "${BASE_DIR}" --plugin dotbot-brew --plugin dotbot-apt --plugin dotbot-role-deps -c "${cfg}" --dry-run --exit-on-failure 2>&1)"; then
      echo "${output}" >&2
      rm -rf "${tmp_home}"
      return 1
    fi
  done

  rm -rf "${tmp_home}"
}

check_readme_command_docs() {
  status "Checking README command documentation"
  ./generate_shortcuts_documentation.sh --check
}

main() {
  local configs
  local config

  VALIDATE_PYTHON="$(find_validate_python)"
  readonly VALIDATE_PYTHON

  check_bash_syntax
  check_python_syntax
  check_apt_messages
  check_zsh_syntax
  check_role_dependencies
  check_role_dependency_failures
  check_copilot_settings_enable_experimental
  check_copilot_setup_merges_experimental_default
  check_copilot_wrapper_supports_experimental_opt_out
  check_tmux_setup_repairs_broken_tpm_link
  check_claude_setup_merges_safe_defaults
  configs=()
  while IFS= read -r config; do
    configs+=("${config}")
  done < <(collect_role_configs)
  check_link_targets "${configs[@]}"
  check_readme_command_docs
  check_dotbot_dry_runs "${configs[@]}"

  status "Validation passed"
}

main "$@"
