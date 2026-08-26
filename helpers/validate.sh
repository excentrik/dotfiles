#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${BASE_DIR}"
# Load both co-required extension and host modules before initialization.
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"
source "${BASE_DIR}/helpers/role_dependencies.sh"

if ! VALIDATION_TMP_PARENT="$(extensions_resolve_temp_parent)"; then
  exit 1
fi
VALIDATION_ROOT="$(mktemp -d "${VALIDATION_TMP_PARENT%/}/dotfiles-validation-XXXXXX")" || {
  echo "error: unable to create validation temporary directory." >&2
  exit 1
}
if [ ! -d "${VALIDATION_ROOT}" ]; then
  echo "error: validation temporary directory was not created." >&2
  exit 1
fi
VALIDATION_CLEANUP_REGISTRY_FILE="${VALIDATION_ROOT}/cleanup-registry"
: > "${VALIDATION_CLEANUP_REGISTRY_FILE}"
printf '%s\n' "${VALIDATION_ROOT}" >> "${VALIDATION_CLEANUP_REGISTRY_FILE}"
VALIDATION_CLEANUP_PREVIOUS_EXIT_TRAP="$(trap -p EXIT || true)"
VALIDATION_CLEANUP_PREVIOUS_INT_TRAP="$(trap -p INT || true)"
VALIDATION_CLEANUP_PREVIOUS_TERM_TRAP="$(trap -p TERM || true)"

validation_restore_cleanup_traps() {
  extensions_restore_saved_trap EXIT "${VALIDATION_CLEANUP_PREVIOUS_EXIT_TRAP}"
  extensions_restore_saved_trap INT "${VALIDATION_CLEANUP_PREVIOUS_INT_TRAP}"
  extensions_restore_saved_trap TERM "${VALIDATION_CLEANUP_PREVIOUS_TERM_TRAP}"
}

validation_cleanup_registered() {
  local workspace
  local cleanup_status=0

  if [ -f "${VALIDATION_CLEANUP_REGISTRY_FILE}" ]; then
    while IFS= read -r workspace || [ -n "${workspace}" ]; do
      [ -n "${workspace}" ] || continue
      case "${workspace}" in
        "${VALIDATION_ROOT}"|"${VALIDATION_ROOT}"/*)
          if { [ -e "${workspace}" ] || [ -L "${workspace}" ]; } && {
            ! rm -rf -- "${workspace}" ||
              [ -e "${workspace}" ] || [ -L "${workspace}" ];
          }; then
            cleanup_status=1
          fi
          ;;
        *)
          cleanup_status=1
          ;;
      esac
    done < "${VALIDATION_CLEANUP_REGISTRY_FILE}"
  fi
  if ! rm -f -- "${VALIDATION_CLEANUP_REGISTRY_FILE}" || [ -e "${VALIDATION_CLEANUP_REGISTRY_FILE}" ]; then
    cleanup_status=1
  fi
  return "${cleanup_status}"
}

validation_cleanup_exit_trap() {
  local status="$1"

  validation_cleanup_registered || true
  validation_restore_cleanup_traps
  exit "${status}"
}

validation_cleanup_signal_trap() {
  local signal="$1"
  local status="$2"

  validation_cleanup_registered || true
  validation_restore_cleanup_traps
  kill "-${signal}" "$$" 2>/dev/null || true
  case "${signal}" in
    INT)
      exit 130
      ;;
    TERM)
      exit 143
      ;;
  esac
  exit "${status}"
}

trap 'validation_cleanup_exit_trap "$?"' EXIT
trap 'validation_cleanup_signal_trap INT "$?"' INT
trap 'validation_cleanup_signal_trap TERM "$?"' TERM

validation_register_cleanup() {
  case "$1" in
    "${VALIDATION_ROOT}"|"${VALIDATION_ROOT}"/*)
      printf '%s\n' "$1" >> "${VALIDATION_CLEANUP_REGISTRY_FILE}"
      ;;
    *)
      echo "error: refusing to register validation path outside its temporary root: '$1'." >&2
      return 1
      ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage: helpers/validate.sh [--all-roles|--extensions]

Runs non-mutating validation checks:
  - Bash syntax checks
  - Python syntax checks
  - Apt directive message checks
  - Optional zsh syntax checks when zsh is installed
  - Host role reference checks
  - Role dependency graph checks
  - Role dependency dry-run safety checks
  - Extension discovery, host selection, and active-code integrity checks
  - Dotbot link target checks
  - Direct Bun and Claude dependency dry-run checks
  - Copilot skill format and plugin setup checks
  - README generated command documentation drift checks
  - Dotbot dry-runs using a temporary HOME

By default, role checks are limited to Linux/WSL-oriented hosts: unix, wsl, docker.
Use --all-roles to include every role config, including optional Bun/Claude,
macOS, and zsh roles.
USAGE
}

ALL_ROLES=0
EXTENSIONS_ONLY=0
for arg in "$@"; do
  case "${arg}" in
    --all-roles)
      ALL_ROLES=1
      ;;
    --extensions)
      EXTENSIONS_ONLY=1
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

validation_workspace() {
  local label="$1"
  local workspace

  case "${label}" in
    ""|*[!A-Za-z0-9._-]*)
      echo "error: invalid validation workspace label: '${label}'." >&2
      return 1
      ;;
  esac
  if ! workspace="$(mktemp -d "${VALIDATION_ROOT}/${label}-XXXXXX")"; then
    echo "error: unable to create validation workspace for '${label}'." >&2
    return 1
  fi
  validation_register_cleanup "${workspace}" || {
    rm -rf -- "${workspace}"
    return 1
  }
  printf '%s\n' "${workspace}"
}

validation_cleanup_failure_probe() {
  local workspace

  workspace="$(validation_workspace cleanup-failure-probe)"
  printf '%s\n%s\n' "${workspace}" "${VALIDATION_CLEANUP_REGISTRY_FILE}" \
    > "${VALIDATE_CLEANUP_PROBE_LOG}"
  return 1
}

validation_cleanup_success_probe() {
  local workspace

  workspace="$(validation_workspace cleanup-success-probe)"
  printf '%s\n%s\n' "${workspace}" "${VALIDATION_CLEANUP_REGISTRY_FILE}" \
    > "${VALIDATE_CLEANUP_PROBE_LOG}"
  return 0
}

validation_cleanup_signal_probe() {
  local workspace

  workspace="$(validation_workspace cleanup-signal-probe)"
  printf '%s\n%s\n' "${workspace}" "${VALIDATION_CLEANUP_REGISTRY_FILE}" \
    > "${VALIDATE_CLEANUP_PROBE_LOG}"
  while :; do
    sleep 1
  done
}

check_validation_cleanup_registry() {
  status "Checking validation fixture cleanup on normal, failure, INT, and TERM runs"
  local controller
  local failure_log
  local signal_log
  local output
  local probe_pid
  local probe_status
  local failure_workspace
  local failure_registry
  local signal_workspace
  local signal_registry
  local normal_log
  local normal_workspace
  local normal_registry
  local int_log
  local int_workspace
  local int_registry
  local attempt
  local in_repo_parent
  local in_repo_root
  local in_repo_output

  controller="$(validation_workspace cleanup-controller)"
  in_repo_root="${BASE_DIR}/validation-state-probe"
  in_repo_parent="${in_repo_root}/deeper"
  mkdir -p "${in_repo_parent}"
  in_repo_output="${controller}/in-repository-output"
  if output="$(
    TMPDIR="${in_repo_parent}" \
    VALIDATE_VALIDATION_CLEANUP_SUCCESS_PROBE=1 \
    VALIDATE_CLEANUP_PROBE_LOG="${in_repo_output}" \
    ./helpers/validate.sh --extensions 2>&1
  )"; then
    echo "Expected validation to reject a temporary parent inside the repository: ${output}" >&2
    rm -rf "${in_repo_root}" "${controller}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "outside the repository"; then
    echo "Expected an explicit repository containment error for validation state: ${output}" >&2
    rm -rf "${in_repo_root}" "${controller}"
    return 1
  fi
  rm -rf "${in_repo_root}"

  normal_log="${controller}/normal.log"
  if ! output="$(
    VALIDATE_VALIDATION_CLEANUP_SUCCESS_PROBE=1 \
    VALIDATE_CLEANUP_PROBE_LOG="${normal_log}" \
    ./helpers/validate.sh --extensions 2>&1
  )"; then
    echo "Expected validation success probe to pass: ${output}" >&2
    rm -rf "${controller}"
    return 1
  fi
  normal_workspace="$(sed -n '1p' "${normal_log}")"
  normal_registry="$(sed -n '2p' "${normal_log}")"
  case "${normal_workspace}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected normal validation state outside the repository: ${normal_workspace}" >&2
      rm -rf "${controller}"
      return 1
      ;;
  esac
  case "${normal_registry}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected normal validation registry outside the repository: ${normal_registry}" >&2
      rm -rf "${controller}"
      return 1
      ;;
  esac
  if [ ! -s "${normal_log}" ] || [ -e "${normal_workspace}" ] ||
    [ -e "${normal_registry}" ]; then
    echo "Expected normal validation cleanup to remove its fixture root." >&2
    rm -rf "${normal_workspace}" "${normal_registry}" "${controller}"
    return 1
  fi

  failure_log="${controller}/failure.log"
  signal_log="${controller}/signal.log"
  if output="$(
    VALIDATE_VALIDATION_CLEANUP_FAILURE_PROBE=1 \
    VALIDATE_CLEANUP_PROBE_LOG="${failure_log}" \
    ./helpers/validate.sh --extensions 2>&1
  )"; then
    echo "Expected validation failure probe to fail." >&2
    rm -rf "${controller}"
    return 1
  fi
  failure_workspace="$(sed -n '1p' "${failure_log}")"
  failure_registry="$(sed -n '2p' "${failure_log}")"
  case "${failure_workspace}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected failing validation state outside the repository: ${failure_workspace}" >&2
      rm -rf "${controller}"
      return 1
      ;;
  esac
  case "${failure_registry}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected failing validation registry outside the repository: ${failure_registry}" >&2
      rm -rf "${controller}"
      return 1
      ;;
  esac
  if [ ! -s "${failure_log}" ] || [ -e "${failure_workspace}" ] ||
    [ -e "${failure_registry}" ]; then
    echo "Expected validation failure cleanup to remove its fixture root; got: ${output}" >&2
    rm -rf "${failure_workspace}" "${failure_registry}" "${controller}"
    return 1
  fi

  int_log="${controller}/int.log"
  setsid env \
    VALIDATE_VALIDATION_CLEANUP_INT_PROBE=1 \
    VALIDATE_CLEANUP_PROBE_LOG="${int_log}" \
    python3 -c \
      'import os, signal; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv("./helpers/validate.sh", ["./helpers/validate.sh", "--extensions"])' \
    > "${controller}/int-output" 2>&1 &
  probe_pid=$!
  attempt=0
  while [ ! -s "${int_log}" ] && [ "${attempt}" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done
  if [ ! -s "${int_log}" ]; then
    kill -TERM "${probe_pid}" 2>/dev/null || true
    wait "${probe_pid}" 2>/dev/null || true
    echo "Validation INT cleanup probe did not start." >&2
    rm -rf "${controller}"
    return 1
  fi
  int_workspace="$(sed -n '1p' "${int_log}")"
  int_registry="$(sed -n '2p' "${int_log}")"
  case "${int_workspace}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected INT validation state outside the repository: ${int_workspace}" >&2
      kill -TERM "${probe_pid}" 2>/dev/null || true
      wait "${probe_pid}" 2>/dev/null || true
      rm -rf "${controller}"
      return 1
      ;;
  esac
  case "${int_registry}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected INT validation registry outside the repository: ${int_registry}" >&2
      kill -TERM "${probe_pid}" 2>/dev/null || true
      wait "${probe_pid}" 2>/dev/null || true
      rm -rf "${controller}"
      return 1
      ;;
  esac
  kill -INT "${probe_pid}"
  probe_status=0
  wait "${probe_pid}" || probe_status=$?
  if [ "${probe_status}" -eq 0 ] || [ -e "${int_workspace}" ] ||
    [ -e "${int_registry}" ]; then
    echo "Expected INT to clean validation fixtures; status=${probe_status}, root=${int_workspace}" >&2
    rm -rf "${int_workspace}" "${int_registry}" "${controller}"
    return 1
  fi

  VALIDATE_VALIDATION_CLEANUP_SIGNAL_PROBE=1 \
  VALIDATE_CLEANUP_PROBE_LOG="${signal_log}" \
  ./helpers/validate.sh --extensions > "${controller}/signal-output" 2>&1 &
  probe_pid=$!
  attempt=0
  while [ ! -s "${signal_log}" ] && [ "${attempt}" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done
  if [ ! -s "${signal_log}" ]; then
    kill -TERM "${probe_pid}" 2>/dev/null || true
    wait "${probe_pid}" 2>/dev/null || true
    echo "Validation signal cleanup probe did not start." >&2
    rm -rf "${controller}"
    return 1
  fi
  signal_workspace="$(sed -n '1p' "${signal_log}")"
  signal_registry="$(sed -n '2p' "${signal_log}")"
  case "${signal_workspace}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected TERM validation state outside the repository: ${signal_workspace}" >&2
      kill -TERM "${probe_pid}" 2>/dev/null || true
      wait "${probe_pid}" 2>/dev/null || true
      rm -rf "${controller}"
      return 1
      ;;
  esac
  case "${signal_registry}" in
    "${BASE_DIR}"|"${BASE_DIR}"/*)
      echo "Expected TERM validation registry outside the repository: ${signal_registry}" >&2
      kill -TERM "${probe_pid}" 2>/dev/null || true
      wait "${probe_pid}" 2>/dev/null || true
      rm -rf "${controller}"
      return 1
      ;;
  esac
  kill -TERM "${probe_pid}"
  probe_status=0
  wait "${probe_pid}" || probe_status=$?
  if [ "${probe_status}" -eq 0 ] || [ -e "${signal_workspace}" ] ||
    [ -e "${signal_registry}" ]; then
    echo "Expected TERM to clean validation fixtures; status=${probe_status}, root=${signal_workspace}" >&2
    rm -rf "${signal_workspace}" "${signal_registry}" "${controller}"
    return 1
  fi
  rm -rf "${controller}"
}

check_bash_3_2_compatibility() {
  status "Checking Bash 3.2 compatibility for changed shell code"
  local files=(
    helpers/extensions.sh
    helpers/hosts.sh
    helpers/role_dependencies.sh
    helpers/python_resolver.sh
    helpers/submodules.sh
    helpers/validate.sh
    generate_shortcuts_documentation.sh
    install
    install-role
    home_files/.bash_prompt
  )
  local unsupported

  if command -v bash3.2 >/dev/null 2>&1; then
    bash3.2 -n "${files[@]+"${files[@]}"}"
    return
  fi

  unsupported="$(
    grep -nE \
      '(^|[[:space:]])declare[[:space:]]+-A|(^|[[:space:]])(mapfile|readarray)([[:space:]]|$)|\[\[[[:space:]]+-v([[:space:]]|$)|(^|[[:space:]])(local|declare)[[:space:]]+-n([[:space:]]|$)|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}' \
      "${files[@]+"${files[@]}"}" || true
  )"
  if [ -n "${unsupported}" ]; then
    echo "Bash 3.2 compatibility check found unsupported syntax:" >&2
    echo "${unsupported}" >&2
    return 1
  fi
  echo "bash3.2 not installed; static compatibility check passed"
}

check_bash_3_2_empty_array_compatibility() {
  status "Checking Bash 3.2 empty-array compatibility"
  local unsafe

  unsafe="$(
    awk '
      {
        line = $0
        while (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"/)) {
          prefix = substr(line, 1, RSTART - 1)
          if (prefix !~ /\+$/) {
            print FILENAME ":" FNR ":" $0
          }
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' \
      helpers/extensions.sh \
      helpers/hosts.sh \
      helpers/role_dependencies.sh \
      helpers/submodules.sh \
      helpers/validate.sh \
      install \
      install-role \
      generate_shortcuts_documentation.sh
  )"
  if [ -n "${unsafe}" ]; then
    echo "Found unguarded empty-array expansion under Bash 3.2 nounset:" >&2
    echo "${unsafe}" >&2
    return 1
  fi

  if ! (
    set -u
    source "${BASE_DIR}/helpers/extensions.sh"
    source "${BASE_DIR}/helpers/hosts.sh"
    EXTENSION_IDS=()
    EXTENSION_ROOTS=()
    EXTENSION_HOST_NAMES=()
    MANIFEST_HOSTS=()
    EXPANDED_ROLES=()
    extensions_find_extension_index missing >/dev/null || [ "$?" -eq 1 ]
    extensions_find_host_index missing >/dev/null || [ "$?" -eq 1 ]
    extensions_validate_role_roots
    extensions_validate_role_addons
    extensions_apply_host_env unix
    extensions_detect_host >/dev/null || [ "$?" -eq 1 ]
    extensions_run_validators
    extensions_run_copilot_prerequisite_hooks
    extensions_role_directories >/dev/null
    extensions_role_addon_directories >/dev/null
    extensions_configure_role_dependencies
  ); then
    echo "Extension role-root helpers must tolerate empty arrays under nounset." >&2
    return 1
  fi
}

check_extensions_disabled_requires_explicit_host() {
  status "Checking disabled extensions require an explicit core host"
  local tmp_home
  local explicit_home
  local output

  tmp_home="$(validation_workspace extension-home)"
  explicit_home="$(validation_workspace extension-explicit-home)"
  if output="$(
    HOME="${tmp_home}" \
    DOTFILES_EXTENSIONS=0 \
    ./install --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected disabled extensions to require an explicit core host." >&2
    echo "${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "explicit core host"; then
    echo "Expected an explicit-core-host error, got: ${output}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi
  if ! HOME="${explicit_home}" DOTFILES_EXTENSIONS=0 ./install unix --dry-run --exit-on-failure >/dev/null 2>&1; then
    echo "Expected explicit core host installation to work with extensions disabled." >&2
    rm -rf "${tmp_home}" "${explicit_home}"
    return 1
  fi

  rm -rf "${tmp_home}" "${explicit_home}"
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
  local command
  local candidate

  PYTHON_CANDIDATES=""

  for command in python3 python; do
    add_python_candidate "$(command -v "${command}" 2>/dev/null || true)"

    while IFS= read -r candidate; do
      add_python_candidate "${candidate}"
    done < <(type -a -P "${command}" 2>/dev/null || true)
  done

  for candidate in \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /opt/local/bin/python3 \
    /usr/bin/python3 \
    /opt/homebrew/bin/python \
    /usr/local/bin/python \
    /opt/local/bin/python \
    /usr/bin/python
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
    if dotfiles_python_is_v3 "${candidate}" && python_has_yaml "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done <<EOF
${PYTHON_CANDIDATES}
EOF

  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    if dotfiles_python_is_v3 "${candidate}" && python_has_vendored_yaml "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done <<EOF
${PYTHON_CANDIDATES}
EOF

  echo "Unable to find a Python 3 runtime that can import yaml." >&2
  echo "Checked PATH python3/python plus common Python 3 and Python locations." >&2
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

    role_deps_expand_roles "${roles[@]+"${roles[@]}"}"
    for role in "${EXPANDED_ROLES[@]+"${EXPANDED_ROLES[@]}"}"; do
      role_file="meta/roles/${role}.yaml"
      if add_unique "${role_file}" "${configs[@]+"${configs[@]}"}"; then
        configs+=("${role_file}")
      fi
    done
  fi

  printf '%s\n' "${configs[@]+"${configs[@]}"}"
}

check_bash_syntax() {
  status "Checking Bash syntax"
  local files=(
    install
    install-role
    generate_shortcuts_documentation.sh
    helpers/*.sh
    home_files/bin/copilot
    home_files/bin/mosh-tmux-session
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
  bash -n "${files[@]+"${files[@]}"}"
}

check_host_helper_layout() {
  status "Checking host helper layout"
  local function
  local entrypoint
  local extensions_source_line
  local hosts_source_line
  local host_drift
  local host_functions=(
    extensions_validate_family
    extensions_read_family
    extensions_find_family_file
    extensions_parse_manifest
    extensions_parse_host_roles
    extensions_validate_host_addons
    extensions_validate_host_env_file
    extensions_validate_host_env_directory
    extensions_validate_extension_profiles
    extensions_validate_core_metadata
    extensions_find_host_index
    extensions_detect_host
    extensions_detect_core_host
    extensions_host_directive_exclusions
    extensions_resolve_host
    extensions_apply_host_env
    extensions_apply_host_env_file
    extensions_variable_is_set
    extensions_host_family
    extensions_parse_host_addons
    extensions_collect_host_roles
  )

  [ -f helpers/hosts.sh ] || {
    echo "Host helper is missing: helpers/hosts.sh" >&2
    return 1
  }
  for function in "${host_functions[@]+"${host_functions[@]}"}"; do
    if ! grep -Eq "^[[:space:]]*(function[[:space:]]+)?${function}[[:space:]]*(\\(\\))?[[:space:]]*\\{" \
      helpers/hosts.sh; then
      echo "Host function is missing from helpers/hosts.sh: ${function}" >&2
      return 1
    fi
    if grep -Eq "^[[:space:]]*(function[[:space:]]+)?${function}[[:space:]]*(\\(\\))?[[:space:]]*\\{" \
      helpers/extensions.sh; then
      echo "Host function remains in helpers/extensions.sh: ${function}" >&2
      return 1
    fi
  done

  host_drift="$(
    grep -nE \
      '^[[:space:]]*(function[[:space:]]+)?extensions_[[:alnum:]_]*(host|family|detect|detector|manifest)[[:alnum:]_]*[[:space:]]*(\(\))?[[:space:]]*\{' \
      helpers/extensions.sh || true
  )"
  if [ -n "${host_drift}" ]; then
    echo "Host/family/detector/manifest function drifted into helpers/extensions.sh:" >&2
    echo "${host_drift}" >&2
    return 1
  fi

  for entrypoint in install install-role helpers/validate.sh; do
    extensions_source_line="$(
      grep -nE \
        '^[[:space:]]*source[[:space:]]+"\$\{BASE_DIR\}/helpers/extensions\.sh"' \
        "${entrypoint}" | head -1 | cut -d: -f1 || true
    )"
    hosts_source_line="$(
      grep -nE \
        '^[[:space:]]*source[[:space:]]+"\$\{BASE_DIR\}/helpers/hosts\.sh"' \
        "${entrypoint}" | head -1 | cut -d: -f1 || true
    )"
    if [ -z "${extensions_source_line}" ] || [ -z "${hosts_source_line}" ] ||
      [ "${extensions_source_line}" -ge "${hosts_source_line}" ]; then
      echo "Entrypoint must source helpers/extensions.sh before helpers/hosts.sh: ${entrypoint}" >&2
      return 1
    fi
  done
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

check_zsh_noninteractive_path() {
  status "Checking non-interactive zsh PATH"
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh not found; skipping non-interactive PATH check"
    return 0
  fi

  local tmp_home
  local resolved
  tmp_home="$(validation_workspace zsh-path)"
  mkdir -p "${tmp_home}/bin"
  ln -s "${BASE_DIR}/home_files/.zshenv" "${tmp_home}/.zshenv"
  ln -s "${BASE_DIR}/home_files/.path" "${tmp_home}/.path"
  printf '#!/usr/bin/env sh\n' > "${tmp_home}/bin/path-probe"
  chmod +x "${tmp_home}/bin/path-probe"

  resolved="$(HOME="${tmp_home}" ZDOTDIR="${tmp_home}" PATH="/usr/bin:/bin" zsh -c 'command -v path-probe')"
  if [ "${resolved}" != "${tmp_home}/bin/path-probe" ]; then
    echo "Expected non-interactive zsh to resolve ~/bin tools; resolved: ${resolved}" >&2
    rm -rf "${tmp_home}"
    return 1
  fi

  rm -rf "${tmp_home}"
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
    }' "${configs[@]+"${configs[@]}"}"
  )

  if [ "${failures}" -ne 0 ]; then
    return 1
  fi
}

check_role_dependencies() {
  status "Checking role dependencies"
  extensions_initialize || return 1
  extensions_configure_role_dependencies
  role_deps_validate_graph
}

check_role_dependency_failures() {
  status "Checking role dependency failure handling"
  local tmp_meta
  local output
  local expanded

  tmp_meta="$(validation_workspace role-deps)"
  mkdir -p "${tmp_meta}/roles"
  ROLE_DEPS_ROOTS=()
  printf -- '- depends:\n    - missing-role\n' > "${tmp_meta}/roles/parent.yaml"

  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
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

  for form in indented quoted; do
    case "${form}" in
      indented)
        printf '%s\n' '  - depends: [child, sibling]' > "${tmp_meta}/roles/parent.yaml"
        ;;
      quoted)
        printf '%s\n' '  - "depends": [child, sibling]' > "${tmp_meta}/roles/parent.yaml"
        ;;
    esac
    if ! output="$(
      ROLE_DEPS_META_DIR="${tmp_meta}"
      role_deps_expand_roles parent 2>&1
      printf '%s\n' "${EXPANDED_ROLES[*]}"
    )"; then
      echo "Expected ${form} dependencies to expand successfully." >&2
      echo "${output}" >&2
      rm -rf "${tmp_meta}"
      return 1
    fi
    expanded="$(printf '%s\n' "${output}" | tail -1)"
    if [ "${expanded}" != "child sibling parent" ]; then
      echo "Expected ${form} dependencies to expand before parent; got: ${expanded}" >&2
      rm -rf "${tmp_meta}"
      return 1
    fi
  done

  printf '%s\n' \
    '- shell: "echo depends: ordinary prose"' \
    '# depends: [missing-role]' \
    > "${tmp_meta}/roles/parent.yaml"
  if ! output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    role_deps_expand_roles parent 2>&1
    printf '%s\n' "${EXPANDED_ROLES[*]}"
  )"; then
    echo "Expected comments and prose to remain outside dependency parsing." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi
  expanded="$(printf '%s\n' "${output}" | tail -1)"
  if [ "${expanded}" != "parent" ]; then
    echo "Expected comments and prose not to create dependencies; got: ${expanded}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  printf '%s\n' '- depends: child' > "${tmp_meta}/roles/parent.yaml"
  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    role_deps_expand_roles parent 2>&1
  )"; then
    echo "Expected scalar dependency shape to fail role expansion." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "depends directive must be a list"; then
    echo "Expected malformed dependency shape error, got: ${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  printf -- '- depends: [bad.role]\n' > "${tmp_meta}/roles/parent.yaml"
  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    role_deps_expand_roles parent 2>&1
  )"; then
    echo "Expected malformed dependency names to fail role expansion." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    role_deps_expand_roles ../parent 2>&1
  )"; then
    echo "Expected option-like/path-like role names to fail role expansion." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi
  if output="$(
    ROLE_DEPS_META_DIR="${tmp_meta}" \
    role_deps_expand_roles --parent 2>&1
  )"; then
    echo "Expected option-like role names to fail role expansion." >&2
    echo "${output}" >&2
    rm -rf "${tmp_meta}"
    return 1
  fi

  rm -rf "${tmp_meta}"
}

check_submodule_bootstrap_precedes_yaml_parsing() {
  status "Checking submodule bootstrap precedes YAML parsing"
  local root
  local fake_bin
  local real_git
  local real_python
  local source_yaml
  local output
  local entrypoint
  local event_log

  real_git="$(command -v git)"
  real_python="$(command -v python3)"
  source_yaml="${BASE_DIR}/dotbot/lib/pyyaml/lib"

  for entrypoint in install install-role; do
    root="$(extension_fixture_new "submodule-bootstrap-${entrypoint}")"
    rm -rf "${root}/dotbot"
    printf '%s\n' \
      '[submodule "dotbot"]' \
      $'\tpath = dotbot' \
      $'\turl = https://example.invalid/dotbot' \
      > "${root}/.gitmodules"
    extension_fixture_commit "${root}"

    fake_bin="${root}/fake-bin"
    event_log="${root}/events.log"
    mkdir -p "${fake_bin}" "${root}/home"
    cat > "${fake_bin}/python3" <<PYTHON
#!/usr/bin/env bash
if [ "\${1:-}" = "-" ]; then
  printf '%s\n' yaml-parse >> "${event_log}"
fi
exec "${real_python}" -S "\$@"
PYTHON
    chmod +x "${fake_bin}/python3"
    cat > "${fake_bin}/git" <<GIT
#!/usr/bin/env bash
if [ "\${1:-}" = "submodule" ] && [ "\${2:-}" = "update" ]; then
  printf '%s\n' submodule-update >> "${event_log}"
  mkdir -p "${root}/dotbot/bin" "${root}/dotbot/lib/pyyaml"
  cp -R "${source_yaml}" "${root}/dotbot/lib/pyyaml/"
  cat > "${root}/dotbot/bin/dotbot" <<'DOTBOT'
#!/usr/bin/env bash
exit 0
DOTBOT
  chmod +x "${root}/dotbot/bin/dotbot"
  exit 0
fi
exec "${real_git}" "\$@"
GIT
    chmod +x "${fake_bin}/git"

    if [ "${entrypoint}" = "install" ]; then
      if ! output="$(
        cd "${root}"
        HOME="${root}/home" \
        PATH="${fake_bin}:${PATH}" \
        OSTYPE=linux-gnu \
          ./install unix --exit-on-failure 2>&1
      )"; then
        echo "${entrypoint} failed before submodule bootstrap: ${output}" >&2
        cat "${event_log}" >&2 2>/dev/null || true
        rm -rf "${root}"
        return 1
      fi
    else
      if ! output="$(
        cd "${root}"
        HOME="${root}/home" \
        PATH="${fake_bin}:${PATH}" \
        OSTYPE=linux-gnu \
          ./install-role core --exit-on-failure 2>&1
      )"; then
        echo "${entrypoint} failed before submodule bootstrap: ${output}" >&2
        cat "${event_log}" >&2 2>/dev/null || true
        rm -rf "${root}"
        return 1
      fi
    fi
    if [ ! -f "${event_log}" ] || [ "$(head -1 "${event_log}")" != "submodule-update" ]; then
      echo "Expected ${entrypoint} to bootstrap submodules before YAML parsing." >&2
      cat "${event_log}" >&2 2>/dev/null || true
      rm -rf "${root}"
      return 1
    fi
    if ! tail -n +2 "${event_log}" | grep -Fqx "yaml-parse"; then
      echo "Expected ${entrypoint} to parse YAML after the submodule update boundary." >&2
      cat "${event_log}" >&2
      rm -rf "${root}"
      return 1
    fi
    rm -rf "${root}"
  done

  for entrypoint in install install-role; do
    root="$(extension_fixture_new "dry-run-missing-${entrypoint}")"
    rm -rf "${root}/dotbot"
    extension_fixture_commit "${root}"
    fake_bin="${root}/fake-bin"
    event_log="${root}/events.log"
    mkdir -p "${fake_bin}" "${root}/home"
    cat > "${fake_bin}/git" <<GIT
#!/usr/bin/env bash
printf '%s\n' git-invoked >> "${event_log}"
exit 99
GIT
    chmod +x "${fake_bin}/git"

    if [ "${entrypoint}" = "install" ]; then
      if output="$(
        cd "${root}"
        HOME="${root}/home" \
        PATH="${fake_bin}:${PATH}" \
          ./install unix --dry-run --exit-on-failure 2>&1
      )"; then
        echo "Expected ${entrypoint} dry-run to reject missing submodules." >&2
        rm -rf "${root}"
        return 1
      fi
    else
      if output="$(
        cd "${root}"
        HOME="${root}/home" \
        PATH="${fake_bin}:${PATH}" \
          ./install-role core --dry-run --exit-on-failure 2>&1
      )"; then
        echo "Expected ${entrypoint} dry-run to reject missing submodules." >&2
        rm -rf "${root}"
        return 1
      fi
    fi
    if ! printf '%s\n' "${output}" | grep -Fq "dry-run requires initialized submodules"; then
      echo "Expected ${entrypoint} dry-run to fail clearly when submodules are absent; got: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    if [ -e "${event_log}" ]; then
      echo "Expected ${entrypoint} dry-run not to invoke git." >&2
      cat "${event_log}" >&2
      rm -rf "${root}"
      return 1
    fi
    rm -rf "${root}"
  done
}

extension_fixture_init() {
  local root="$1"

  mkdir -p \
    "${root}/helpers" \
    "${root}/dotbot/bin" \
    "${root}/meta/hosts" \
    "${root}/meta/host-families" \
    "${root}/meta/host-addons" \
    "${root}/meta/host-env" \
    "${root}/meta/role-addons" \
    "${root}/meta/roles"
  mkdir -p "${root}/home_files"
  mkdir -p "${root}/dotbot/lib/pyyaml"
  cp -R "${BASE_DIR}/dotbot/lib/pyyaml/lib" "${root}/dotbot/lib/pyyaml/"
  cp "${BASE_DIR}/generate_shortcuts_documentation.sh" "${root}/generate_shortcuts_documentation.sh"
  cp "${BASE_DIR}/meta/roles/bun.yaml" "${root}/meta/roles/bun.yaml"
  cp "${BASE_DIR}/meta/roles/claude.yaml" "${root}/meta/roles/claude.yaml"
  cp "${BASE_DIR}/helpers/extensions.sh" "${root}/helpers/extensions.sh"
  cp "${BASE_DIR}/helpers/hosts.sh" "${root}/helpers/hosts.sh"
  cp "${BASE_DIR}/helpers/python_resolver.sh" "${root}/helpers/python_resolver.sh"
  cp "${BASE_DIR}/helpers/role_dependencies.sh" "${root}/helpers/role_dependencies.sh"
  cp "${BASE_DIR}/helpers/submodules.sh" "${root}/helpers/submodules.sh"
  cp "${BASE_DIR}/helpers/validate.sh" "${root}/helpers/validate.sh"
  cp "${BASE_DIR}/install" "${root}/install"
  cp "${BASE_DIR}/install-role" "${root}/install-role"
  cp "${BASE_DIR}/home_files/.bash_prompt" "${root}/home_files/.bash_prompt"
  chmod +x "${root}/install" "${root}/install-role"
  printf '%s\n' '- shell: []' > "${root}/meta/base.yaml"
  printf '%s\n' '- shell: []' > "${root}/meta/roles/core.yaml"
  cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
base=""
config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d)
      base="$2"
      shift 2
      ;;
    -c)
      config="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'dotbot-base=%s config=%s\n' "${base}" "${config}"
SH
  chmod +x "${root}/dotbot/bin/dotbot"
  for host in osx unix wsl docker; do
    printf '%s\n' '- core: ~' > "${root}/meta/hosts/${host}.yaml"
  done
  for family in osx unix wsl docker; do
    printf '%s\n' "${family}" > "${root}/meta/host-families/${family}"
  done
}

extension_fixture_add() {
  local root="$1"
  local extension_id="$2"
  local host="$3"
  local family="$4"
  local detector_body="${5:-}"
  local extension_root="${root}/extensions/${extension_id}"

  mkdir -p \
    "${extension_root}/meta/hosts" \
    "${extension_root}/meta/host-families" \
    "${extension_root}/meta/roles"
  printf '%s\n' \
    "id=${extension_id}" \
    "hosts=${host}" \
    > "${extension_root}/extension.conf"
  printf '%s\n' "- ${extension_id}-addon: ~" > "${extension_root}/meta/hosts/${host}.yaml"
  printf '%s\n' "${family}" > "${extension_root}/meta/host-families/${host}"
  printf '%s\n' '- shell: []' > "${extension_root}/meta/roles/${extension_id}-addon.yaml"
  if [ -n "${detector_body}" ]; then
    printf '%s\n' '#!/usr/bin/env bash' "${detector_body}" > "${extension_root}/detect-host"
    chmod +x "${extension_root}/detect-host"
  fi
}

extension_fixture_commit() {
  local root="$1"

  git -C "${root}" init -q
  git -C "${root}" config user.email validation@example.invalid
  git -C "${root}" config user.name validation
  git -C "${root}" add .
  git -C "${root}" commit -qm baseline
}

extension_fixture_new() {
  local name="$1"
  local root

  root="$(validation_workspace "extension-${name}")" || return 1
  extension_fixture_init "${root}" || return 1
  printf '%s\n' "${root}"
}

extension_fixture_initialize() {
  local root="$1"
  local mode="${2:-normal}"

  (
    cd "${root}"
    BASE_DIR="${root}" \
    DOTFILES_EXTENSIONS_MODE="${mode}" \
    bash -c 'source "${BASE_DIR}/helpers/extensions.sh"; source "${BASE_DIR}/helpers/hosts.sh"; extensions_initialize'
  )
}

extension_fixture_detect() {
  local root="$1"
  local mode="${2:-normal}"

  (
    cd "${root}"
    BASE_DIR="${root}" \
    DOTFILES_EXTENSIONS_MODE="${mode}" \
    bash -c '
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      extensions_initialize || exit $?
      if extensions_detect_host; then
        printf "%s\n" "${EXTENSION_DETECTED_HOST}"
        exit 0
      else
        status=$?
        exit "${status}"
      fi
    '
  )
}

extension_fixture_run_validators() {
  local root="$1"

  (
    cd "${root}"
    BASE_DIR="${root}" \
    bash -c '
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      extensions_initialize || exit $?
      extensions_run_validators
    '
  )
}

check_extension_failure() {
  local root="$1"
  local expected="$2"
  local operation="${3:-initialize}"
  local mode="${4:-normal}"
  local output

  if [ "${operation}" = "detect" ]; then
    if output="$(extension_fixture_detect "${root}" "${mode}" 2>&1)"; then
      echo "Expected extension detector validation to fail." >&2
      rm -rf "${root}"
      return 1
    fi
  elif [ "${operation}" = "run-validators" ]; then
    if output="$(extension_fixture_run_validators "${root}" 2>&1)"; then
      echo "Expected extension validator validation to fail." >&2
      rm -rf "${root}"
      return 1
    fi
  elif output="$(extension_fixture_initialize "${root}" "${mode}" 2>&1)"; then
      echo "Expected extension fixture validation to fail." >&2
      rm -rf "${root}"
      return 1
  fi
  if [ -n "${expected}" ] && ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
    echo "Expected '${expected}' in extension failure, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_validators() {
  status "Checking extension validator execution"
  local root
  local output
  local marker
  local extension_id

  root="$(extension_fixture_new validator-install-skip)"
  extension_fixture_add "${root}" validator "validator-host" unix
  marker="${root}/validator-ran"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\n' ran > '${marker}'" \
    > "${root}/extensions/validator/validate.sh"
  chmod +x "${root}/extensions/validator/validate.sh"
  extension_fixture_commit "${root}"
  mkdir -p "${root}/install-home"
  if ! output="$(
    cd "${root}"
    HOME="${root}/install-home" \
    OSTYPE=linux-gnu \
      ./install validator-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected ordinary install to succeed without running the validator: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ -e "${marker}" ]; then
    echo "Ordinary install executed the extension validator." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new validator-stderr)"
  extension_fixture_add "${root}" validator "validator-host" unix
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\n' validator-diagnostic >&2" \
    > "${root}/extensions/validator/validate.sh"
  chmod +x "${root}/extensions/validator/validate.sh"
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_run_validators "${root}" 2>&1)"; then
    echo "Expected validator stderr to fail repository validation." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "validator-diagnostic"; then
    echo "Expected validator stderr to remain visible, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new validator-order)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  for extension_id in alpha zeta; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      "printf '%s\n' '${extension_id}' >> \"\${DOTFILES_EXTENSION_ROOT}/../validator-order\"" \
      > "${root}/extensions/${extension_id}/validate.sh"
    chmod +x "${root}/extensions/${extension_id}/validate.sh"
  done
  extension_fixture_commit "${root}"
  if ! extension_fixture_run_validators "${root}" >/dev/null; then
    echo "Expected silent successful validators to pass." >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(cat "${root}/extensions/validator-order")" != $'alpha\nzeta' ]; then
    echo "Expected validators to run in extension-ID order." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_role_dependency_graph() {
  status "Checking extension role dependency graph validation"
  local root
  local output

  root="$(extension_fixture_new role-dependency-graph)"
  extension_fixture_add "${root}" graph "graph-host" unix
  printf '%s\n' \
    '- depends: [missing-role]' \
    '- missing-parent: ~' \
    > "${root}/extensions/graph/meta/roles/missing-parent.yaml"
  printf '%s\n' \
    '- depends: [cycle-b]' \
    '- cycle-a: ~' \
    > "${root}/extensions/graph/meta/roles/cycle-a.yaml"
  printf '%s\n' \
    '- depends: [cycle-a]' \
    '- cycle-b: ~' \
    > "${root}/extensions/graph/meta/roles/cycle-b.yaml"
  extension_fixture_commit "${root}"

  if output="$(
    cd "${root}"
    VALIDATE_ROLE_GRAPH_ONLY=1 ./helpers/validate.sh --extensions 2>&1
  )"; then
    echo "Expected extension role dependency graph failures to reach validation; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "Role missing-role is not supported." ||
    ! printf '%s\n' "${output}" | grep -Fq "cyclic role dependency"; then
    echo "Expected missing and cyclic extension dependency errors, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_only_validates_repository_graph() {
  status "Checking extension-only validation covers the repository role graph"
  local root
  local output

  root="$(extension_fixture_new extension-only-repository-graph)"
  extension_fixture_add "${root}" graph "graph-host" unix
  printf '%s\n' \
    '- depends: [missing-role]' \
    '- graph-role: ~' \
    > "${root}/extensions/graph/meta/roles/graph-role.yaml"
  extension_fixture_commit "${root}"

  if output="$(
    cd "${root}"
    VALIDATE_SKIP_EXTENSION_GRAPH_REGRESSION=1 \
      ./helpers/validate.sh --extensions 2>&1
  )"; then
    echo "Expected extension-only validation to reject the repository graph." >&2
    echo "${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "Role missing-role is not supported."; then
    echo "Expected extension-only validation to report the repository graph error; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_repository_extension_validators() {
  status "Running repository extension validators"
  extensions_initialize || return 1
  extensions_run_validators
}

validation_snapshot_repository_paths() {
  local root="$1"
  local destination="$2"

  find -P "${root}" \
    \( -path "${root}/.git" -o -path "${root}/.git/*" \) -prune \
    -o -print | LC_ALL=C sort > "${destination}"
}

validation_assert_repository_unchanged() {
  local root="$1"
  local before="$2"
  local after="$3"
  local status_output

  validation_snapshot_repository_paths "${root}" "${after}"
  status_output="$(git -C "${root}" status --porcelain --untracked-files=all)"
  if ! cmp -s "${before}" "${after}" ||
    ! git -C "${root}" diff --quiet ||
    ! git -C "${root}" diff --cached --quiet ||
    [ -n "${status_output}" ]; then
    echo "Expected validation to leave repository paths and Git state unchanged." >&2
    printf '%s\n' "${status_output}" >&2
    return 1
  fi
}

check_extensions_foundation() {
  status "Checking extension discovery and host-selection foundation"
  local root
  local outside
  local output
  local detector_status

  root="$(extension_fixture_new malformed-id)"
  mkdir -p "${root}/extensions/bad.id"
  printf '%s\n' 'id=bad.id' 'hosts=bad-host' > "${root}/extensions/bad.id/extension.conf"
  check_extension_failure "${root}" "invalid extension directory id" || return 1

  root="$(extension_fixture_new no-primary-host)"
  mkdir -p "${root}/extensions/addons-only"
  printf '%s\n' 'id=addons-only' > "${root}/extensions/addons-only/extension.conf"
  extension_fixture_commit "${root}"
  if ! extension_fixture_initialize "${root}" >/dev/null; then
    echo "Expected an extension without primary hosts to validate." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new malformed-host)"
  extension_fixture_add "${root}" invalid-host "valid-host" unix
  printf '%s\n' 'id=invalid-host' 'hosts=bad/host' > "${root}/extensions/invalid-host/extension.conf"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "malformed host list" || return 1

  root="$(extension_fixture_new duplicate-id)"
  extension_fixture_add "${root}" first "first-host" unix
  extension_fixture_add "${root}" second "second-host" unix
  printf '%s\n' 'id=first' 'hosts=second-host' > "${root}/extensions/second/extension.conf"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "duplicate extension id" || return 1

  root="$(extension_fixture_new duplicate-host)"
  extension_fixture_add "${root}" first "shared-host" unix
  extension_fixture_add "${root}" second "shared-host" unix
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "duplicate primary host profile" || return 1

  root="$(extension_fixture_new duplicate-core-host)"
  extension_fixture_add "${root}" extension "unix" unix
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "duplicates core host profile" || return 1

  root="$(extension_fixture_new missing-family)"
  extension_fixture_add "${root}" missing "missing-family" unix
  rm -f "${root}/extensions/missing/meta/host-families/missing-family"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "missing host family metadata" || return 1

  root="$(extension_fixture_new malformed-family)"
  extension_fixture_add "${root}" malformed "malformed-family" unix
  printf '%s\n' 'not a family' > "${root}/extensions/malformed/meta/host-families/malformed-family"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid host family" || return 1

  root="$(extension_fixture_new malformed-role)"
  extension_fixture_add "${root}" malformed "malformed-role" unix
  printf '%s\n' '- bad role: ~' > "${root}/extensions/malformed/meta/hosts/malformed-role.yaml"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid role" || return 1

  root="$(extension_fixture_new malformed-host-addon)"
  extension_fixture_add "${root}" malformed "malformed-host-addon" unix
  mkdir -p "${root}/extensions/malformed/meta/host-addons"
  printf '%s\n' '- bad.role: ~' > "${root}/extensions/malformed/meta/host-addons/unix.yaml"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid role" || return 1

  root="$(extension_fixture_new containment)"
  extension_fixture_add "${root}" escape "escape-host" unix $'printf "%s\\n" escape-host'
  outside="${root}/outside-detector"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" escape-host' > "${outside}"
  chmod +x "${outside}"
  rm -f "${root}/extensions/escape/detect-host"
  ln -s "${outside}" "${root}/extensions/escape/detect-host"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "must be a regular contained file" || return 1

  root="$(extension_fixture_new validator-failure)"
  extension_fixture_add "${root}" validator "validator-failure-host" unix
  printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "${root}/extensions/validator/validate.sh"
  chmod +x "${root}/extensions/validator/validate.sh"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "extension validator failed" \
    run-validators || return 1

  root="$(extension_fixture_new passive-containment)"
  extension_fixture_add "${root}" passive "passive-host" unix
  outside="${root}/outside-home-file"
  printf '%s\n' 'passive data' > "${outside}"
  mkdir -p "${root}/extensions/passive/home_files"
  ln -s "${outside}" "${root}/extensions/passive/home_files/escape"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "home_files path escapes" || return 1

  root="$(extension_fixture_new untracked-active)"
  extension_fixture_add "${root}" untracked "untracked-host" unix
  extension_fixture_commit "${root}"
  mkdir -p "${root}/extensions/untracked/helpers"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${root}/extensions/untracked/helpers/untracked.sh"
  chmod +x "${root}/extensions/untracked/helpers/untracked.sh"
  check_extension_failure "${root}" "does not exactly match HEAD" || return 1

  root="$(extension_fixture_new validator-containment)"
  extension_fixture_add "${root}" validator "validator-host" unix
  outside="${root}/outside-validator"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${outside}"
  chmod +x "${outside}"
  ln -s "${outside}" "${root}/extensions/validator/validate.sh"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "must be a regular contained file" || return 1

  root="$(extension_fixture_new detector-no-match)"
  extension_fixture_add "${root}" no-match "no-match-host" unix 'exit 0'
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_detect "${root}" 2>&1)"; then
    detector_status=0
  else
    detector_status=$?
  fi
  if [ "${detector_status}" -ne 1 ] || [ -n "${output}" ]; then
    echo "Expected detector no-match to return 1 with no output; status=${detector_status}, output=${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new detector-failure)"
  extension_fixture_add "${root}" failure "failure-host" unix 'exit 7'
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "extension detector failed" detect || return 1

  root="$(extension_fixture_new detector-stderr)"
  extension_fixture_add "${root}" stderr "stderr-host" unix $'printf "%s\\n" noise >&2'
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "extension detector wrote to stderr" detect || return 1

  root="$(extension_fixture_new detector-malformed)"
  extension_fixture_add "${root}" malformed "malformed-host" unix 'printf "%s\n" bad.host'
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid detector output" detect || return 1

  root="$(extension_fixture_new detector-multiple)"
  extension_fixture_add "${root}" multiple "multiple-host" unix $'printf "%s\\n" multiple-host other-host'
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "multiple claims" detect || return 1

  root="$(extension_fixture_new detector-claim)"
  extension_fixture_add "${root}" claim "claim-host" unix 'printf "%s\n" claim-host'
  extension_fixture_commit "${root}"
  output="$(extension_fixture_detect "${root}")" || {
    echo "Expected a valid detector claim, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  }
  if [ "${output}" != "claim-host" ]; then
    echo "Expected detector to select claim-host, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new active-integrity)"
  extension_fixture_add "${root}" integrity "integrity-host" unix 'exit 0'
  extension_fixture_commit "${root}"
  mkdir -p "${root}/extensions/integrity/home_files"
  printf '%s\n' 'dirty passive data' > "${root}/extensions/integrity/home_files/local"
  if ! extension_fixture_initialize "${root}" >/dev/null; then
    echo "Expected dirty passive home_files content to remain allowed." >&2
    rm -rf "${root}"
    return 1
  fi
  printf '%s\n' '# changed' >> "${root}/extensions/integrity/detect-host"
  check_extension_failure "${root}" "does not exactly match HEAD" || return 1

  root="$(extension_fixture_new development-integrity)"
  extension_fixture_add "${root}" development "development-host" unix 'exit 0'
  extension_fixture_commit "${root}"
  printf '%s\n' '# staged change' >> "${root}/extensions/development/detect-host"
  if output="$(extension_fixture_initialize "${root}" development 2>&1)"; then
    echo "Expected unstaged active code to fail in development mode." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "not clean in the index"; then
    echo "Expected development-mode integrity failure, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  git -C "${root}" add extensions/development/detect-host
  if ! extension_fixture_initialize "${root}" development >/dev/null; then
    echo "Expected staged, index-matching active code in development mode to pass." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_symlinked_checkout_containment() {
  status "Checking extension containment through a symlinked checkout"
  local root
  local checkout_link
  local output

  root="$(extension_fixture_new symlinked-checkout)"
  extension_fixture_add "${root}" extension "extension-host" unix
  extension_fixture_commit "${root}"
  checkout_link="$(validation_workspace symlinked-checkout-link)"
  rmdir "${checkout_link}"
  ln -s "${root}" "${checkout_link}"

  if ! output="$(
    cd "${checkout_link}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected a symlinked checkout to accept contained extensions; got: ${output}" >&2
    rm -f "${checkout_link}"
    rm -rf "${root}"
    return 1
  fi
  rm -f "${checkout_link}"
  rm -rf "${root}"
}

check_extension_host_addon_order() {
  status "Checking deterministic core host addon ordering"
  local root
  local output

  root="$(extension_fixture_new host-addon-order)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  mkdir -p \
    "${root}/extensions/zeta/meta/host-addons" \
    "${root}/extensions/alpha/meta/host-addons"
  printf '%s\n' '- zeta-role: ~' > "${root}/extensions/zeta/meta/host-addons/unix.yaml"
  printf '%s\n' '- alpha-role: ~' > "${root}/extensions/alpha/meta/host-addons/unix.yaml"
  printf '%s\n' '- zeta-role: ~' > "${root}/extensions/zeta/meta/roles/zeta-role.yaml"
  printf '%s\n' '- alpha-role: ~' > "${root}/extensions/alpha/meta/roles/alpha-role.yaml"
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    BASE_DIR="${root}" bash -c '
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      extensions_initialize
      extensions_resolve_host unix
      extensions_collect_host_roles unix
    '
  )"; then
    echo "Expected core host addon collection to succeed; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "${output}" != $'core\nalpha-role\nzeta-role' ]; then
    echo "Expected core host addons in extension-ID order; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_host_addon_install_order() {
  status "Checking host addon execution order and source roots"
  local root
  local output
  local expected

  root="$(extension_fixture_new host-addon-install)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  printf '%s\n' '- core-role: ~' > "${root}/meta/hosts/unix.yaml"
  printf '%s\n' '- core-role: ~' > "${root}/meta/roles/core-role.yaml"
  mkdir -p \
    "${root}/extensions/zeta/meta/host-addons" \
    "${root}/extensions/alpha/meta/host-addons"
  printf '%s\n' '- zeta-role: ~' > "${root}/extensions/zeta/meta/host-addons/unix.yaml"
  printf '%s\n' '- alpha-role: ~' > "${root}/extensions/alpha/meta/host-addons/unix.yaml"
  printf '%s\n' '- zeta-role: ~' > "${root}/extensions/zeta/meta/roles/zeta-role.yaml"
  printf '%s\n' '- alpha-role: ~' > "${root}/extensions/alpha/meta/roles/alpha-role.yaml"
  extension_fixture_commit "${root}"

  output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install unix --dry-run --exit-on-failure |
      grep '^dotbot-base='
  )"
  expected="$(printf '%s\n' \
    "dotbot-base=${root} config=meta/base.yaml" \
    "dotbot-base=${root} config=${root}/meta/roles/core-role.yaml" \
    "dotbot-base=${root}/extensions/alpha config=${root}/extensions/alpha/meta/roles/alpha-role.yaml" \
    "dotbot-base=${root}/extensions/zeta config=${root}/extensions/zeta/meta/roles/zeta-role.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected host addons after the core profile in extension-ID order; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_cross_root_dependencies() {
  status "Checking cross-root role dependency resolution"
  local root
  local output

  root="$(extension_fixture_new cross-root-dependencies)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- depends: [core-child]' '- extension-parent: ~' \
    > "${root}/extensions/extension/meta/roles/extension-parent.yaml"
  printf '%s\n' '- core-child: ~' > "${root}/meta/roles/core-child.yaml"
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    BASE_DIR="${root}" bash -c '
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      source "${BASE_DIR}/helpers/role_dependencies.sh"
      extensions_initialize
      extensions_configure_role_dependencies
      role_deps_expand_roles extension-parent
      printf "%s\n" "${EXPANDED_ROLES[*]}"
    '
  )"; then
    echo "Expected cross-root dependency resolution to succeed; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "${output}" != "core-child extension-parent" ]; then
    echo "Expected core dependency before extension role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_install_role_source_root() {
  status "Checking explicit install-role resolves extension roles"
  local root
  local output

  root="$(extension_fixture_new install-role-extension)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- extension-role: ~' > "${root}/extensions/extension/meta/roles/extension-host.yaml"
  printf '%s\n' '- extension-role: ~' > "${root}/extensions/extension/meta/roles/extension-role.yaml"
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role extension-role --dry-run --exit-on-failure |
      grep '^dotbot-base='
  )"; then
    echo "Expected install-role to execute an extension role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "${output}" != "dotbot-base=${root}/extensions/extension config=${root}/extensions/extension/meta/roles/extension-role.yaml" ]; then
    echo "Expected extension role Dotbot source root; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_argument_parsing() {
  status "Checking installer argument parsing"
  local root
  local output
  local expected

  root="$(extension_fixture_new argument-parsing)"
  printf '%s\n' '- extra-role: ~' > "${root}/meta/roles/extra-role.yaml"
  cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
printf 'call'
for argument in "$@"; do
  printf '|%s' "${argument}"
done
printf '\n'
SH
  chmod +x "${root}/dotbot/bin/dotbot"
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install unix \
      --plugin custom-plugin \
      --except shell \
      --dry-run \
      extra-role \
      --exit-on-failure 2>&1 | grep '^call'
  )"; then
    echo "Expected install argument parsing to succeed; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  expected="$(printf '%s\n' \
    "call|-d|${root}|--plugin|dotbot-brew|--plugin|dotbot-apt|--plugin|dotbot-role-deps|-c|meta/base.yaml|--plugin|custom-plugin|--dry-run|--exit-on-failure|--except|shell|tap|brew|cask|brewfile|services" \
    "call|-d|${root}|--plugin|dotbot-brew|--plugin|dotbot-apt|--plugin|dotbot-role-deps|-c|${root}/meta/roles/core.yaml|--plugin|custom-plugin|--dry-run|--exit-on-failure|--except|shell|tap|brew|cask|brewfile|services" \
    "call|-d|${root}|--plugin|dotbot-brew|--plugin|dotbot-apt|--plugin|dotbot-role-deps|-c|${root}/meta/roles/extra-role.yaml|--plugin|custom-plugin|--dry-run|--exit-on-failure|--except|shell|tap|brew|cask|brewfile|services")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected one copy of each Dotbot argument and role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  if ! output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role core \
      --plugin custom-plugin \
      --except shell \
      --dry-run \
      --exit-on-failure 2>&1 | grep '^call'
  )"; then
    echo "Expected install-role argument parsing to succeed; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  expected="call|--plugin|dotbot-brew|--plugin|dotbot-apt|--plugin|dotbot-role-deps|-d|${root}|-c|${root}/meta/roles/core.yaml|--verbose|--plugin|custom-plugin|--dry-run|--exit-on-failure|--except|shell|tap|brew|cask|brewfile|services"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected install-role to parse arguments once; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_family_contract() {
  status "Checking extension host family vocabulary"
  local root
  local family
  local output

  if ! output="$(
    BASE_DIR="${BASE_DIR}" bash -c '
      set -u
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      unset EXTENSION_SELECTED_FAMILY
      extensions_host_directive_exclusions
      missing_status=$?
      extensions_host_directive_exclusions invalid-family
      invalid_status=$?
      printf "statuses=%s,%s\n" "${missing_status}" "${invalid_status}"
      [ "${missing_status}" -ne 0 ] && [ "${invalid_status}" -ne 0 ]
    ' _ "${BASE_DIR}" 2>&1
  )"; then
    echo "Expected missing and invalid host family arguments to return clear failures: ${output}" >&2
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "extensions_host_directive_exclusions requires exactly one host family argument"; then
    echo "Expected a clear missing host family argument error, got: ${output}" >&2
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "unsupported host family: 'invalid-family'"; then
    echo "Expected a clear invalid host family error, got: ${output}" >&2
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "statuses=1,1"; then
    echo "Expected both host family argument failures to return nonzero: ${output}" >&2
    return 1
  fi

  for family in typo-family linux; do
    root="$(extension_fixture_new "unknown-family-${family}")"
    if [ "${family}" = "linux" ]; then
      printf '%s\n' "${family}" > "${root}/meta/host-families/${family}"
    fi
    extension_fixture_add "${root}" extension "extension-host" "${family}"
    extension_fixture_commit "${root}"
    check_extension_failure "${root}" "unsupported host family"
  done

  for family in osx unix wsl docker; do
    root="$(extension_fixture_new "family-exclusions-${family}")"
    extension_fixture_add "${root}" extension "extension-host" "${family}"
    cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
printf 'call'
for argument in "$@"; do
  printf '|%s' "${argument}"
done
printf '\n'
SH
    chmod +x "${root}/dotbot/bin/dotbot"
    extension_fixture_commit "${root}"
    if ! output="$(
      cd "${root}"
      OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1 |
        grep '^call'
    )"; then
      echo "Expected ${family} extension host installation to succeed; got: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    case "${family}" in
      osx)
        if ! printf '%s\n' "${output}" | grep -Fq '|--except|apt'; then
          echo "Expected osx extension host to exclude apt; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
        if printf '%s\n' "${output}" | grep -Fq '|--except|tap|'; then
          echo "Expected osx extension host not to exclude Homebrew directives; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
        ;;
      unix|wsl|docker)
        if ! printf '%s\n' "${output}" | grep -Fq '|--except|tap|brew|cask|brewfile|services'; then
          echo "Expected unix extension host to exclude Homebrew directives; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
        if printf '%s\n' "${output}" | grep -Fq '|--except|apt'; then
          echo "Expected unix extension host not to exclude apt; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
        ;;
    esac
    rm -rf "${root}"
  done
}

check_host_profile_parser_contract() {
  status "Checking constrained host profile parsing"
  local root
  local output
  local form
  local body
  local case_index

  for form in primary addon; do
    case_index=0
    for body in '- extension-addon' '- extension-addon:' '- extension-addon: value' '- extension-addon: ~#comment' '- [extension-addon]'; do
      root="$(extension_fixture_new "malformed-host-${form}-${case_index}")"
      case_index=$((case_index + 1))
      extension_fixture_add "${root}" extension "extension-host" unix
      if [ "${form}" = "primary" ]; then
        printf '%s\n' "${body}" > "${root}/extensions/extension/meta/hosts/extension-host.yaml"
        extension_fixture_commit "${root}"
        if output="$(
          cd "${root}"
          OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
        )"; then
          echo "Expected malformed primary host entry to fail; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
      else
        mkdir -p "${root}/extensions/extension/meta/host-addons"
        printf '%s\n' "${body}" > "${root}/extensions/extension/meta/host-addons/unix.yaml"
        extension_fixture_commit "${root}"
        if output="$(
          cd "${root}"
          OSTYPE=linux-gnu ./install unix --dry-run --exit-on-failure 2>&1
        )"; then
          echo "Expected malformed host addon entry to fail; got: ${output}" >&2
          rm -rf "${root}"
          return 1
        fi
      fi
      if ! printf '%s\n' "${output}" | grep -Fq "malformed host profile entry"; then
        echo "Expected malformed host profile entry error, got: ${output}" >&2
        rm -rf "${root}"
        return 1
      fi
      if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
        echo "Malformed ${form} entry was accepted after Dotbot execution." >&2
        rm -rf "${root}"
        return 1
      fi
      rm -rf "${root}"
    done
  done

  root="$(extension_fixture_new valid-host-profile-comments)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '' '  # ordinary comment' '- extension-addon: ~' \
    > "${root}/extensions/extension/meta/hosts/extension-host.yaml"
  mkdir -p "${root}/extensions/extension/meta/host-addons"
  printf '%s\n' '' '# another comment' '- addon-role: ~' \
    > "${root}/extensions/extension/meta/host-addons/unix.yaml"
  printf '%s\n' '- addon-role: ~' \
    > "${root}/extensions/extension/meta/roles/addon-role.yaml"
  extension_fixture_commit "${root}"
  if ! output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected comments and blank lines in host metadata to pass; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_producer_failure_propagation() {
  status "Checking extension producer failure propagation"
  local root
  local output

  root="$(extension_fixture_new host-role-producer-failure)"
  cat >> "${root}/helpers/hosts.sh" <<'SH'
extensions_collect_host_roles() {
  printf '%s\n' core
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install unix --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected host role collection failure to stop install; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "host role collection failed"; then
    echo "Expected host role collection failure to be reported; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Host role producer partial output reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new host-directive-producer-failure)"
  cat >> "${root}/helpers/hosts.sh" <<'SH'
extensions_host_directive_exclusions() {
  printf '%s\n' tap
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install unix --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected host directive exclusion failure to stop install; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "host directive exclusion collection failed"; then
    echo "Expected host directive exclusion failure to be reported; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Host directive exclusion producer partial output reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new install-role-host-directive-producer-failure)"
  cat >> "${root}/helpers/hosts.sh" <<'SH'
extensions_host_directive_exclusions() {
  printf '%s\n' tap
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role core --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected install-role host directive exclusion failure to stop install; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "host directive exclusion collection failed"; then
    echo "Expected install-role host directive exclusion failure to be reported; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Install-role host directive exclusion producer partial output reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new install-addon-producer-failure)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/extension-addon.yaml"
  extension_fixture_commit "${root}"
  cat >> "${root}/helpers/extensions.sh" <<SH
extensions_resolve_role_addons() {
  printf '%s\n' "\${BASE_DIR}/extensions/extension/meta/role-addons/extension-addon.yaml"
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected install addon resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "role addon resolution failed"; then
    echo "Expected install addon resolution failure to be reported; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Install addon producer partial output reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new install-role-addon-producer-failure)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/core.yaml"
  extension_fixture_commit "${root}"
  cat >> "${root}/helpers/extensions.sh" <<SH
extensions_resolve_role_addons() {
  printf '%s\n' "\${BASE_DIR}/extensions/extension/meta/role-addons/core.yaml"
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role core --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected install-role addon resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "role addon resolution failed"; then
    echo "Expected install-role addon resolution failure to be reported; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Install-role addon producer partial output reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new role-config-resolution-failure)"
  extension_fixture_add "${root}" extension "extension-host" unix
  extension_fixture_commit "${root}"
  cat >> "${root}/helpers/extensions.sh" <<'SH'
extensions_resolve_role_config() {
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected role config resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "error: role config resolution failed for 'extension-addon'."; then
    echo "Expected stable role config resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Role config resolution failure reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new role-config-root-partial-execution)"
  extension_fixture_add "${root}" extension "extension-host" unix
  extension_fixture_commit "${root}"
  cat >> "${root}/helpers/extensions.sh" <<'SH'
extensions_role_config_root() {
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected role config root resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "error: role config root resolution failed for 'extension-addon'."; then
    echo "Expected stable role config root resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Role config root failure reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new role-addon-root-partial-execution)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/extension-addon.yaml"
  extension_fixture_commit "${root}"
  cat >> "${root}/helpers/extensions.sh" <<'SH'
extensions_role_addon_root() {
  return 7
}
SH
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install extension-host --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected role addon root resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "error: role addon root resolution failed for 'extension-addon'."; then
    echo "Expected stable role addon root resolution failure; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Role addon root failure reached Dotbot." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_path_containment() {
  status "Checking extension path containment"

  if ! extensions_path_is_within "/root/extension" "/root/extension"; then
    echo "Expected an extension root to contain itself." >&2
    return 1
  fi
  if ! extensions_path_is_within "/root/extension/file" "/root/extension"; then
    echo "Expected an extension descendant to remain contained." >&2
    return 1
  fi
  if extensions_path_is_within "/root/extension-escape" "/root/extension"; then
    echo "Expected an extension sibling path to be rejected." >&2
    return 1
  fi
}

check_extension_detector_ownership() {
  status "Checking extension detector host ownership"
  local root
  local output

  root="$(extension_fixture_new detector-cross-claim)"
  extension_fixture_add "${root}" alpha "alpha-host" unix \
    'printf "%s\n" beta-host'
  extension_fixture_add "${root}" beta "beta-host" unix
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_detect "${root}" 2>&1)"; then
    echo "Expected a cross-extension detector claim to fail; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "detector claimed a host owned by another extension"; then
    echo "Expected a detector ownership error, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_dangling_symlink_rejection() {
  status "Checking deterministic dangling symlink rejection"
  local root
  local fake_bin
  local branch
  local command
  local output

  root="$(extension_fixture_new dangling-passive-symlink)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/home_files"
  printf '%s\n' valid > "${root}/extensions/extension/home_files/target"
  ln -s target "${root}/extensions/extension/home_files/valid-link"
  ln -s missing "${root}/extensions/extension/home_files/dangling-link"
  extension_fixture_commit "${root}"

  for branch in realpath readlink python; do
    fake_bin="${root}/fake-bin-${branch}"
    mkdir -p "${fake_bin}"
    for command in dirname find git sort; do
      ln -s "$(command -v "${command}")" "${fake_bin}/${command}"
    done
    case "${branch}" in
      realpath)
        ln -s "$(command -v realpath)" "${fake_bin}/realpath"
        ;;
      readlink)
        ln -s "$(command -v readlink)" "${fake_bin}/readlink"
        ;;
      python)
        ln -s "$(command -v python3)" "${fake_bin}/python3"
        ;;
    esac
    if output="$(
      cd "${root}"
      PATH="${fake_bin}" BASE_DIR="${root}" /bin/bash -c '
        source "${BASE_DIR}/helpers/extensions.sh"
        source "${BASE_DIR}/helpers/hosts.sh"
        extensions_initialize
      ' 2>&1
    )"; then
      echo "Expected ${branch} canonicalization to reject dangling symlink: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    if ! printf '%s\n' "${output}" | grep -Fq "unresolved path"; then
      echo "Expected ${branch} dangling symlink failure to report an unresolved path: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    rm -rf "${fake_bin}"
  done

  rm "${root}/extensions/extension/home_files/dangling-link"
  if ! extension_fixture_initialize "${root}" >/dev/null 2>&1; then
    echo "Expected valid passive home_files symlink to remain accepted." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_role_addon_order() {
  status "Checking deterministic role addon ordering after base roles"
  local root
  local output
  local expected

  root="$(extension_fixture_new role-addon-order)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  printf '%s\n' '- base-role: ~' > "${root}/meta/roles/base-role.yaml"
  mkdir -p \
    "${root}/extensions/zeta/meta/role-addons" \
    "${root}/extensions/alpha/meta/role-addons"
  printf '%s\n' '- shell: []' > "${root}/extensions/zeta/meta/role-addons/base-role.yaml"
  printf '%s\n' '- shell: []' > "${root}/extensions/alpha/meta/role-addons/base-role.yaml"
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role base-role --dry-run --exit-on-failure |
      grep '^dotbot-base='
  )"; then
    echo "Expected role addons to execute after the base role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  expected="$(printf '%s\n' \
    "dotbot-base=${root} config=${root}/meta/roles/base-role.yaml" \
    "dotbot-base=${root}/extensions/alpha config=${root}/extensions/alpha/meta/role-addons/base-role.yaml" \
    "dotbot-base=${root}/extensions/zeta config=${root}/extensions/zeta/meta/role-addons/base-role.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected base role followed by extension-ID ordered addons; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_duplicate_role_rejection() {
  status "Checking duplicate role rejection before execution"
  local root
  local output

  root="$(extension_fixture_new duplicate-role)"
  extension_fixture_add "${root}" alpha "alpha-host" unix
  extension_fixture_add "${root}" beta "beta-host" unix
  printf '%s\n' '- shared-role: ~' > "${root}/extensions/alpha/meta/roles/shared-role.yaml"
  printf '%s\n' '- shared-role: ~' > "${root}/extensions/beta/meta/roles/shared-role.yaml"
  printf '%s\n' '- shared-role: ~' > "${root}/meta/hosts/unix.yaml"
  extension_fixture_commit "${root}"

  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install unix --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected duplicate roles to fail before execution; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "duplicate role name"; then
    echo "Expected duplicate-role error, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
    echo "Duplicate role rejection occurred after Dotbot execution." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_addon_dependency_rejection() {
  status "Checking addon dependency rejection before execution"
  local root
  local output
  local form
  local addon_body

  for form in block inline quoted; do
    root="$(extension_fixture_new "addon-dependency-${form}")"
    extension_fixture_add "${root}" extension "extension-host" unix
    printf '%s\n' '- base-role: ~' > "${root}/meta/roles/base-role.yaml"
    mkdir -p "${root}/extensions/extension/meta/role-addons"
    case "${form}" in
      block)
        addon_body="$(printf '%s\n' '- depends:' '    - prerequisite')"
        ;;
      inline)
        addon_body='- {depends: [prerequisite]}'
        ;;
      quoted)
        addon_body='- "depends": [prerequisite]'
        ;;
    esac
    printf '%s\n' "${addon_body}" \
      > "${root}/extensions/extension/meta/role-addons/base-role.yaml"
    extension_fixture_commit "${root}"

    if output="$(
      cd "${root}"
      OSTYPE=linux-gnu ./install-role base-role --dry-run --exit-on-failure 2>&1
    )"; then
      echo "Expected ${form} addon dependencies to fail before execution; got: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    if ! printf '%s\n' "${output}" | grep -Fq "role addon may not declare dependencies"; then
      echo "Expected ${form} addon dependency error, got: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    if printf '%s\n' "${output}" | grep -Fq "dotbot-base="; then
      echo "${form} addon dependency rejection occurred after Dotbot execution." >&2
      rm -rf "${root}"
      return 1
    fi
    rm -rf "${root}"
  done

  root="$(extension_fixture_new addon-dependency-prose)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- base-role: ~' > "${root}/meta/roles/base-role.yaml"
  mkdir -p "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: "echo depends: ordinary prose" # depends: comment' \
    > "${root}/extensions/extension/meta/role-addons/base-role.yaml"
  extension_fixture_commit "${root}"
  if output="$(
    cd "${root}"
    OSTYPE=linux-gnu ./install-role base-role --dry-run --exit-on-failure 2>&1
  )"; then
    :
  else
    echo "Expected ordinary prose and comments to remain allowed; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Fq "role addon may not declare dependencies"; then
    echo "Ordinary prose or comments were treated as addon dependencies." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_python_fallback_for_role_addons() {
  status "Checking Python 3 fallback for role addon validation"
  local root
  local fake_bin
  local real_python
  local command
  local output
  local python2

  root="$(extension_fixture_new python-fallback)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- base-role: ~' > "${root}/meta/roles/base-role.yaml"
  mkdir -p "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/base-role.yaml"
  extension_fixture_commit "${root}"

  fake_bin="${root}/python-only-bin"
  mkdir -p "${fake_bin}"
  real_python="$(command -v python3)"
  for command in dirname find git realpath sort; do
    ln -s "$(command -v "${command}")" "${fake_bin}/${command}"
  done
  cat > "${fake_bin}/python" <<SH
#!/bin/sh
exec "${real_python}" "\$@"
SH
  chmod +x "${fake_bin}/python"

  if ! output="$(
    cd "${root}"
    PATH="${fake_bin}" BASE_DIR="${root}" /bin/bash -c '
      source "${BASE_DIR}/helpers/extensions.sh"
      source "${BASE_DIR}/helpers/hosts.sh"
      extensions_initialize
    ' 2>&1
  )"; then
    echo "Expected role addon validation to use Python 3 from python; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new python2-rejected)"
  python2="${root}/python2"
  printf '%s\n' '#!/bin/sh' 'printf 2' > "${python2}"
  chmod +x "${python2}"
  if output="$(
    PYTHON2="${python2}" /bin/bash -c '
      source helpers/python_resolver.sh
      dotfiles_python_candidates() {
        printf "%s\n" "${PYTHON2}"
      }
      dotfiles_find_python3
    ' 2>&1
  )"; then
    echo "Expected Python 2 to be rejected by interpreter resolution." >&2
    echo "${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "Python 2 interpreter rejected"; then
    echo "Expected explicit Python 2 rejection, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new python-missing)"
  if output="$(
    /bin/bash -c '
      source helpers/python_resolver.sh
      dotfiles_python_candidates() {
        :
      }
      dotfiles_find_python3
    ' 2>&1
  )"; then
    echo "Expected missing Python 3 to fail interpreter resolution." >&2
    echo "${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "no Python 3 interpreter available"; then
    echo "Expected clear missing Python 3 error, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_python_resolver_portability() {
  status "Checking portable Python 3 resolution"
  local root
  local fake_bin
  local real_python
  local output
  local expected

  root="$(validation_workspace python-resolver)"
  fake_bin="${root}/bin"
  mkdir -p "${fake_bin}"
  real_python="$(command -v python3)"

  cat > "${fake_bin}/python3" <<'SH'
#!/bin/sh
printf '2'
SH
  chmod +x "${fake_bin}/python3"
  if output="$(
    PATH="${fake_bin}" \
    /bin/bash -c '
      source "'"${BASE_DIR}"'/helpers/python_resolver.sh"
      dotfiles_find_python3
    ' 2>&1
  )"; then
    echo "Python 2 must not fall through to an interpreter outside PATH." >&2
    echo "${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "Python 2 interpreter rejected"; then
    echo "Expected a clear Python 2 rejection, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  cat > "${fake_bin}/python" <<SH
#!/bin/sh
exec "${real_python}" "\$@"
SH
  chmod +x "${fake_bin}/python"
  expected="${fake_bin}/python"
  output="$(
    PATH="${fake_bin}" \
    /bin/bash -c '
      source "'"${BASE_DIR}"'/helpers/python_resolver.sh"
      dotfiles_find_python3
    '
  )"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected Python 3 python fallback after rejecting python3, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  cat > "${fake_bin}/python3" <<SH
#!/bin/sh
exec "${real_python}" "\$@"
SH
  chmod +x "${fake_bin}/python3"
  rm -f "${fake_bin}/python"
  ln -s python3 "${fake_bin}/python"

  expected="${fake_bin}/python3"
  output="$(
    PATH="${fake_bin}" \
    /bin/bash -c '
      source "'"${BASE_DIR}"'/helpers/python_resolver.sh"
      dotfiles_python_candidates
    '
  )"
  if [ "${output}" != "${expected}"$'\n'"${fake_bin}/python" ]; then
    echo "Expected one PATH candidate per command in priority order, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  output="$(
    PATH="${fake_bin}" \
    /bin/bash -c '
      source "'"${BASE_DIR}"'/helpers/python_resolver.sh"
      dotfiles_find_python3
    '
  )"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected python3 to win over python, got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  rm -rf "${root}"
}

check_extension_host_env_defaults_and_override() {
  status "Checking extension host environment defaults and overrides"
  local root
  local output
  local expected

  root="$(extension_fixture_new host-env)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/host-env"
  printf '%s\n' 'DOTFILES_BOOTSTRAP=1' \
    > "${root}/extensions/extension/meta/host-env/extension-host.env"
  extension_fixture_commit "${root}"
  cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'bootstrap=%s config=%s\n' "${DOTFILES_BOOTSTRAP:-unset}" "${config}"
SH
  chmod +x "${root}/dotbot/bin/dotbot"

  output="$(
    cd "${root}"
    env -u DOTFILES_BOOTSTRAP ./install extension-host --dry-run --exit-on-failure |
      grep '^bootstrap='
  )"
  expected="$(printf '%s\n' \
    "bootstrap=1 config=meta/base.yaml" \
    "bootstrap=1 config=${root}/extensions/extension/meta/roles/extension-addon.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected host env default to reach Dotbot; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  output="$(
    cd "${root}"
    DOTFILES_BOOTSTRAP=0 ./install extension-host --dry-run --exit-on-failure |
      grep '^bootstrap='
  )"
  expected="$(printf '%s\n' \
    "bootstrap=0 config=meta/base.yaml" \
    "bootstrap=0 config=${root}/extensions/extension/meta/roles/extension-addon.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected caller host env override to be preserved; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new host-env-invalid-name)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/host-env"
  printf '%s\n' 'DOTFILES_BAD-NAME=1' \
    > "${root}/extensions/extension/meta/host-env/extension-host.env"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid host environment name" || return 1

  root="$(extension_fixture_new host-env-invalid-value)"
  extension_fixture_add "${root}" extension "extension-host" unix
  mkdir -p "${root}/extensions/extension/meta/host-env"
  printf '%s\n' 'DOTFILES_BOOTSTRAP=$(command)' \
    > "${root}/extensions/extension/meta/host-env/extension-host.env"
  extension_fixture_commit "${root}"
  check_extension_failure "${root}" "invalid host environment value" || return 1

  root="$(extension_fixture_new host-env-core-order)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  printf '%s\n' '- core: ~' > "${root}/meta/hosts/unix.yaml"
  printf '%s\n' '- core: ~' > "${root}/meta/roles/core.yaml"
  mkdir -p \
    "${root}/extensions/alpha/meta/host-env" \
    "${root}/extensions/zeta/meta/host-env"
  printf '%s\n' 'DOTFILES_BOOTSTRAP=alpha' \
    > "${root}/extensions/alpha/meta/host-env/unix.env"
  printf '%s\n' \
    'DOTFILES_BOOTSTRAP=zeta' \
    'DOTFILES_PYTHON=zeta' \
    > "${root}/extensions/zeta/meta/host-env/unix.env"
  extension_fixture_commit "${root}"
  cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'env-probe=%s,%s config=%s\n' \
  "${DOTFILES_BOOTSTRAP:-unset}" \
  "${DOTFILES_PYTHON:-unset}" \
  "${config}"
SH
  chmod +x "${root}/dotbot/bin/dotbot"

  output="$(
    cd "${root}"
    env -u DOTFILES_BOOTSTRAP -u DOTFILES_PYTHON \
      OSTYPE=linux-gnu \
      ./install unix --dry-run --exit-on-failure |
      grep '^env-probe='
  )"
  expected="$(printf '%s\n' \
    "env-probe=alpha,zeta config=meta/base.yaml" \
    "env-probe=alpha,zeta config=${root}/meta/roles/core.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected core host environment defaults in extension-ID order; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  output="$(
    cd "${root}"
    env -u DOTFILES_PYTHON \
      DOTFILES_BOOTSTRAP=caller \
      OSTYPE=linux-gnu \
      ./install unix --dry-run --exit-on-failure |
      grep '^env-probe='
  )"
  expected="$(printf '%s\n' \
    "env-probe=caller,zeta config=meta/base.yaml" \
    "env-probe=caller,zeta config=${root}/meta/roles/core.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected explicit caller environment values to win; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new host-env-detector)"
  extension_fixture_add "${root}" extension "extension-host" unix \
    'printf "%s\n" extension-host'
  mkdir -p "${root}/extensions/extension/meta/host-env"
  printf '%s\n' 'DOTFILES_BOOTSTRAP=detected' \
    > "${root}/extensions/extension/meta/host-env/extension-host.env"
  extension_fixture_commit "${root}"
  cat > "${root}/dotbot/bin/dotbot" <<'SH'
#!/usr/bin/env bash
config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'detected-env=%s config=%s\n' "${DOTFILES_BOOTSTRAP:-unset}" "${config}"
SH
  chmod +x "${root}/dotbot/bin/dotbot"
  output="$(
    cd "${root}"
    env -u DOTFILES_BOOTSTRAP \
      OSTYPE=linux-gnu \
      ./install --dry-run --exit-on-failure |
      grep '^detected-env='
  )"
  expected="$(printf '%s\n' \
    "detected-env=detected config=meta/base.yaml" \
    "detected-env=detected config=${root}/extensions/extension/meta/roles/extension-addon.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected detector-selected host environment defaults to apply; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_prompt_host_override() {
  status "Checking sanitized Bash prompt host override"
  local prompt_root
  local output
  local expected_host

  prompt_root="$(validation_workspace prompt-host)"
  expected_host="$(hostname -s 2>/dev/null || hostname)"
  expected_host="${expected_host%%.*}"

  output="$(
    cd "${prompt_root}"
    printf 'cd /\nsource %q\nexit\n' "${BASE_DIR}/home_files/.bash_prompt" |
      HOME="${prompt_root}" TERM=dumb USER=prompt-user \
      DOTFILES_PROMPT_HOST="safe-host-token" \
      bash --noprofile --norc -i 2>&1
  )"
  if ! printf '%s\n' "${output}" | grep -Fq 'safe-host-token'; then
    echo "Expected a valid prompt host override in rendered output." >&2
    rm -rf "${prompt_root}"
    return 1
  fi

  output="$(
    cd "${prompt_root}"
    printf 'cd /\nsource %q\nexit\n' "${BASE_DIR}/home_files/.bash_prompt" |
      HOME="${prompt_root}" TERM=dumb USER=prompt-user \
      DOTFILES_PROMPT_HOST='$(touch prompt-injection-marker)' \
      bash --noprofile --norc -i 2>&1
  )"
  if ! printf '%s\n' "${output}" | grep -Fq "${expected_host}" ||
    [ -e "${prompt_root}/prompt-injection-marker" ]; then
    echo "Expected an invalid prompt host override to fall back safely." >&2
    rm -rf "${prompt_root}"
    return 1
  fi

  output="$(
    cd "${prompt_root}"
    printf 'cd /\nsource %q\nexit\n' "${BASE_DIR}/home_files/.bash_prompt" |
      HOME="${prompt_root}" TERM=dumb USER=prompt-user \
      env -u DOTFILES_PROMPT_HOST bash --noprofile --norc -i 2>&1
  )"
  if ! printf '%s\n' "${output}" | grep -Fq "${expected_host}"; then
    echo "Expected an unset prompt host override to use the hostname." >&2
    rm -rf "${prompt_root}"
    return 1
  fi

  rm -rf "${prompt_root}"
}

extension_fixture_add_copilot_hook() {
  local root="$1"
  local extension_id="$2"
  local body="$3"
  local executable="${4:-1}"
  local hook="${root}/extensions/${extension_id}/helpers/copilot-prerequisite"

  mkdir -p "${root}/extensions/${extension_id}/helpers"
  printf '%s\n' '#!/usr/bin/env bash' "${body}" > "${hook}"
  if [ "${executable}" -eq 1 ]; then
    chmod +x "${hook}"
  fi
}

extension_fixture_run_copilot_role() {
  local root="$1"
  local output

  mkdir -p "${root}/home"
  output="$(
    cd "${root}"
    HOME="${root}/home" \
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=development \
    DOTFILES_HOOK_LOG="${root}/hook.log" \
    ./install-role copilot --dry-run --exit-on-failure 2>&1
  )"
  local status=$?
  printf '%s\n' "${output}"
  return "${status}"
}

check_extension_copilot_skip_contract() {
  status "Checking Copilot skip contract and later-role execution"
  local root
  local output
  local expected

  root="$(extension_fixture_new copilot-skip-contract)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' \
    '- copilot: ~' \
    '- after-role: ~' \
    > "${root}/meta/hosts/unix.yaml"
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  printf '%s\n' '- shell: []' > "${root}/meta/roles/after-role.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" skip'
  extension_fixture_commit "${root}"

  if ! output="$(
    cd "${root}"
    HOME="${root}/home" \
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=development \
    ./install unix --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected an intentional Copilot skip to keep installation successful: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  expected="$(printf '%s\n' \
    "dotbot-base=${root} config=meta/base.yaml" \
    "dotbot-base=${root} config=${root}/meta/roles/after-role.yaml")"
  if ! printf '%s\n' "${output}" | grep -Fxq "Skipping copilot role per extension prerequisite policy"; then
    echo "Expected the documented Copilot skip message; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Eq "^dotbot-base=.*copilot\\.yaml$"; then
    echo "Expected the Copilot role to be omitted after a skip decision; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(printf '%s\n' "${output}" | grep '^dotbot-base=')" != "${expected}" ]; then
    echo "Expected later roles to continue after the skipped Copilot role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi

  if ! output="$(
    cd "${root}"
    HOME="${root}/home" \
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=development \
    ./install-role copilot after-role --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected an explicit Copilot skip to keep installation successful: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  expected="dotbot-base=${root} config=${root}/meta/roles/after-role.yaml"
  if ! printf '%s\n' "${output}" | grep -Fxq "Skipping copilot role per extension prerequisite policy"; then
    echo "Expected the documented explicit-install Copilot skip message; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if printf '%s\n' "${output}" | grep -Eq "^dotbot-base=.*copilot\\.yaml$"; then
    echo "Expected the explicit Copilot role to be omitted after a skip decision; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(printf '%s\n' "${output}" | grep '^dotbot-base=')" != "${expected}" ]; then
    echo "Expected the explicit install's later role to continue after Copilot; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_runtime_cleanup() {
  status "Checking extension runtime capture cleanup"
  local root
  local output
  local installer_pid
  local detector_pid
  local probe_status
  local trap_log
  local attempt
  local fixture_home
  local runtime_parent
  local runtime_dir
  local repository_before
  local repository_after
  local artifact_log
  local runtime_paths
  local snapshot_dir
  snapshot_dir="$(validation_workspace runtime-snapshot-controller)"

  root="$(extension_fixture_new runtime-no-repository-artifact)"
  fixture_home="$(validation_workspace runtime-detector-home)"
  runtime_parent="$(validation_workspace runtime-detector-tmp)"
  repository_before="${snapshot_dir}/repository-before"
  repository_after="${snapshot_dir}/repository-after"
  artifact_log="${runtime_parent}/artifacts.log"
  mkdir -p "${fixture_home}" "${runtime_parent}"
  extension_fixture_add "${root}" extension "extension-host" unix $'
repo_root="$(cd "${DOTFILES_EXTENSION_ROOT}/../.." && pwd)"
current_snapshot="${DOTFILES_RUNTIME_PROBE_DIR}/detector-current"
find -P "${repo_root}" \
  \( -path "${repo_root}/.git" -o -path "${repo_root}/.git/*" \) -prune \
  -o -print | LC_ALL=C sort > "${current_snapshot}"
if ! cmp -s "${DOTFILES_RUNTIME_PROBE_SNAPSHOT}" "${current_snapshot}"; then
  printf "%s\n" detector >> "${DOTFILES_RUNTIME_ARTIFACT_LOG}"
fi
printf "%s\n" extension-host'
  printf '%s\n' '- copilot: ~' > "${root}/extensions/extension/meta/hosts/extension-host.yaml"
  printf '%s\n' '- shell: []' > "${root}/extensions/extension/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension $'
repo_root="$(cd "${DOTFILES_EXTENSION_ROOT}/../.." && pwd)"
current_snapshot="${DOTFILES_RUNTIME_PROBE_DIR}/hook-current"
find -P "${repo_root}" \
  \( -path "${repo_root}/.git" -o -path "${repo_root}/.git/*" \) -prune \
  -o -print | LC_ALL=C sort > "${current_snapshot}"
if ! cmp -s "${DOTFILES_RUNTIME_PROBE_SNAPSHOT}" "${current_snapshot}"; then
  printf "%s\n" hook >> "${DOTFILES_RUNTIME_ARTIFACT_LOG}"
fi'
  extension_fixture_commit "${root}"
  validation_snapshot_repository_paths "${root}" "${repository_before}"
  if ! output="$(
    cd "${root}"
    HOME="${fixture_home}" \
    OSTYPE=linux-gnu \
    TMPDIR="${runtime_parent}" \
    DOTFILES_RUNTIME_PROBE_SNAPSHOT="${repository_before}" \
    DOTFILES_RUNTIME_PROBE_DIR="${runtime_parent}" \
    DOTFILES_RUNTIME_ARTIFACT_LOG="${artifact_log}" \
    DOTFILES_EXTENSIONS_MODE=development \
    ./install --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected detector and Copilot hook dry-run to succeed: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if [ -s "${artifact_log}" ]; then
    echo "Expected dry-run runtime capture to avoid repository artifacts: $(cat "${artifact_log}")" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! validation_assert_repository_unchanged \
    "${root}" "${repository_before}" "${repository_after}"; then
    rm -rf "${root}"
    return 1
  fi
  runtime_paths="$(find -P "${runtime_parent}" -mindepth 1 -maxdepth 1 -type d -print)"
  if [ -n "${runtime_paths}" ]; then
    echo "Expected successful runtime capture cleanup: ${runtime_paths}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-failure-cleanup)"
  fixture_home="$(validation_workspace runtime-failure-home)"
  runtime_parent="$(validation_workspace runtime-failure-tmp)"
  mkdir -p "${fixture_home}" "${runtime_parent}"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'exit 7'
  extension_fixture_commit "${root}"
  if output="$(
    cd "${root}"
    HOME="${fixture_home}" \
    OSTYPE=linux-gnu \
    TMPDIR="${runtime_parent}" \
    DOTFILES_EXTENSIONS_MODE=development \
    ./install-role copilot --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected failing Copilot prerequisite hook to fail." >&2
    rm -rf "${root}"
    return 1
  fi
  runtime_paths="$(find -P "${runtime_parent}" -mindepth 1 -maxdepth 1 -type d -print)"
  if [ -n "${runtime_paths}" ]; then
    echo "Expected failed hook cleanup to remove its runtime directory: ${runtime_paths}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-exit-chaining)"
  runtime_parent="$(validation_workspace runtime-exit-tmp)"
  trap_log="${root}/caller-exit.log"
  cat > "${root}/trap-probe.sh" <<'SH'
#!/usr/bin/env bash
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"

caller_log="$1"
trap 'printf "caller:%s\n" "$?" >> "$caller_log"' EXIT
extensions_create_runtime_dir
printf '%s\n' "${EXTENSIONS_RUNTIME_DIR}" > "$2"
exit 3
SH
  chmod +x "${root}/trap-probe.sh"
  if (
    cd "${root}"
    BASE_DIR="${root}" TMPDIR="${runtime_parent}" \
      bash "${root}/trap-probe.sh" "${trap_log}" "${root}/runtime-path"
  ); then
    probe_status=0
  else
    probe_status=$?
  fi
  if [ "${probe_status}" -ne 3 ] ||
    [ "$(cat "${trap_log}" 2>/dev/null || true)" != "caller:3" ]; then
    echo "Expected runtime EXIT cleanup and caller handler to preserve status 3; status=${probe_status}" >&2
    rm -rf "${root}"
    return 1
  fi
  runtime_dir="$(cat "${root}/runtime-path")"
  if [ -e "${runtime_dir}" ]; then
    echo "Expected runtime EXIT cleanup to remove its exact temporary directory: ${runtime_dir}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-mktemp-failure)"
  runtime_parent="$(validation_workspace runtime-mktemp-failure-tmp)"
  trap_log="${root}/caller-exit.log"
  cat > "${root}/trap-probe.sh" <<'SH'
#!/usr/bin/env bash
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"

caller_log="$1"
trap 'printf "%s\n" caller >> "$caller_log"' EXIT
before_exit="$(trap -p EXIT)"
mktemp() {
  return 91
}
if extensions_create_runtime_dir; then
  exit 1
fi
[ "${before_exit}" = "$(trap -p EXIT)" ] || exit 2
exit 0
SH
  chmod +x "${root}/trap-probe.sh"
  if ! output="$(
    cd "${root}"
    BASE_DIR="${root}" TMPDIR="${runtime_parent}" \
      bash "${root}/trap-probe.sh" "${trap_log}" 2>&1
  )"; then
    echo "Expected mktemp failure to restore the caller traps." >&2
    echo "${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" |
    grep -Fq "unable to create extension runtime temporary directory"; then
    echo "Expected mktemp failure to report the runtime directory error." >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(cat "${trap_log}" 2>/dev/null || true)" != "caller" ]; then
    echo "Expected caller EXIT handler after mktemp failure." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-cleanup-failure)"
  runtime_parent="$(validation_workspace runtime-cleanup-failure-tmp)"
  trap_log="${root}/caller-exit.log"
  cat > "${root}/trap-probe.sh" <<'SH'
#!/usr/bin/env bash
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"

caller_log="$1"
trap 'printf "%s\n" caller >> "$caller_log"' EXIT
before_exit="$(trap -p EXIT)"
extensions_create_runtime_dir
runtime_dir="${EXTENSIONS_RUNTIME_DIR}"
rm() {
  if [ "${3:-}" = "${runtime_dir}" ]; then
    return 92
  fi
  command rm "$@"
}
if extensions_cleanup_runtime_dirs; then
  exit 1
fi
[ "${before_exit}" = "$(trap -p EXIT)" ] || exit 2
command rm -rf -- "${runtime_dir}"
exit 0
SH
  chmod +x "${root}/trap-probe.sh"
  if ! (
    cd "${root}"
    BASE_DIR="${root}" TMPDIR="${runtime_parent}" \
      bash "${root}/trap-probe.sh" "${trap_log}"
  ); then
    echo "Expected cleanup failure to restore the caller traps." >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(cat "${trap_log}" 2>/dev/null || true)" != "caller" ]; then
    echo "Expected caller EXIT handler after cleanup failure." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-trap-preservation)"
  trap_log="${root}/trap-preserved"
  runtime_parent="$(validation_workspace runtime-trap-preservation-tmp)"
  cat > "${root}/trap-probe.sh" <<'SH'
#!/usr/bin/env bash
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"
trap 'printf "%s\n" preserved > "$1"' EXIT
extensions_create_runtime_dir
extensions_cleanup_runtime_dirs
extensions_restore_runtime_traps
SH
  chmod +x "${root}/trap-probe.sh"
  if ! (
    cd "${root}"
    BASE_DIR="${root}" TMPDIR="${runtime_parent}" \
      bash "${root}/trap-probe.sh" "${trap_log}"
  ); then
    echo "Expected runtime cleanup trap preservation probe to succeed." >&2
    rm -rf "${root}"
    return 1
  fi
  if [ "$(cat "${trap_log}" 2>/dev/null || true)" != "preserved" ]; then
    echo "Expected existing EXIT traps to remain installed after runtime cleanup." >&2
    rm -rf "${root}"
    return 1
  fi
  runtime_paths="$(find -P "${runtime_parent}" -mindepth 1 -maxdepth 1 -type d -print)"
  if [ -n "${runtime_paths}" ]; then
    echo "Expected runtime trap preservation probe to clean its capture directory." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-trap-restoration)"
  runtime_parent="$(validation_workspace runtime-trap-restoration-tmp)"
  cat > "${root}/trap-probe.sh" <<'SH'
#!/usr/bin/env bash
source "${BASE_DIR}/helpers/extensions.sh"
source "${BASE_DIR}/helpers/hosts.sh"

log="$1"
signal="$2"
case "${signal}" in
  INT) handler_log="${log}.int" ;;
  TERM) handler_log="${log}.term" ;;
  *) exit 1 ;;
esac
trap 'printf "%s\n" EXIT >> "${log}.exit"' EXIT
trap 'printf "%s\n" INT >> "${log}.int"' INT
trap 'printf "%s\n" TERM >> "${log}.term"' TERM

before_exit="$(trap -p EXIT)"
before_int="$(trap -p INT)"
before_term="$(trap -p TERM)"
extensions_create_runtime_dir
extensions_cleanup_runtime_dirs
extensions_restore_runtime_traps

[ "${before_exit}" = "$(trap -p EXIT)" ] || exit 1
[ "${before_int}" = "$(trap -p INT)" ] || exit 1
[ "${before_term}" = "$(trap -p TERM)" ] || exit 1

kill "-${signal}" "$$"
[ -s "${handler_log}" ] || exit 1
exit 0
SH
  chmod +x "${root}/trap-probe.sh"
  for signal in INT TERM; do
    if ! (
      cd "${root}"
      BASE_DIR="${root}" TMPDIR="${runtime_parent}" \
        bash "${root}/trap-probe.sh" "${root}/trap-${signal}" "${signal}"
    ); then
      echo "Expected ${signal} trap restoration and handler execution to succeed." >&2
      rm -rf "${root}"
      return 1
    fi
  done
  runtime_paths="$(find -P "${runtime_parent}" -mindepth 1 -maxdepth 1 -type d -print)"
  if [ -n "${runtime_paths}" ]; then
    echo "Expected trap restoration probes to clean their capture directories." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new runtime-signal-cleanup)"
  fixture_home="$(validation_workspace runtime-signal-home)"
  runtime_parent="$(validation_workspace runtime-signal-tmp)"
  mkdir -p "${fixture_home}" "${runtime_parent}"
  extension_fixture_add "${root}" extension "extension-host" unix $'
printf "%s\n" "$$" > "${DOTFILES_EXTENSION_ROOT}/detector.pid"
trap "exit 143" INT TERM
while :; do
  sleep 1
done'
  extension_fixture_commit "${root}"
  HOME="${fixture_home}" \
  OSTYPE=linux-gnu \
  TMPDIR="${runtime_parent}" \
  DOTFILES_EXTENSIONS_MODE=development \
  bash -c 'cd "$1" && exec ./install --dry-run --exit-on-failure' \
    signal-probe "${root}" > "${root}/signal-output" 2>&1 &
  installer_pid=$!
  attempt=0
  while [ ! -s "${root}/extensions/extension/detector.pid" ] && [ "${attempt}" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done
  if [ ! -s "${root}/extensions/extension/detector.pid" ]; then
    kill -TERM "${installer_pid}" 2>/dev/null || true
    wait "${installer_pid}" 2>/dev/null || true
    echo "Extension detector signal cleanup probe did not start." >&2
    rm -rf "${root}"
    return 1
  fi
  detector_pid="$(cat "${root}/extensions/extension/detector.pid")"
  kill -TERM "${installer_pid}" 2>/dev/null || true
  kill -TERM "${detector_pid}" 2>/dev/null || true
  probe_status=0
  wait "${installer_pid}" || probe_status=$?
  runtime_paths="$(find -P "${runtime_parent}" -mindepth 1 -maxdepth 1 -type d -print)"
  if [ "${probe_status}" -eq 0 ] || [ -n "${runtime_paths}" ]; then
    echo "Expected TERM to clean extension runtime state; status=${probe_status}, dirs=${runtime_paths}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_extension_copilot_prerequisite_hooks() {
  status "Checking Copilot prerequisite hook policy"
  local root
  local output
  local expected
  local outside

  root="$(extension_fixture_new copilot-hooks-order)"
  extension_fixture_add "${root}" zeta "zeta-host" unix
  extension_fixture_add "${root}" alpha "alpha-host" unix
  printf '%s\n' '- copilot: ~' > "${root}/meta/hosts/unix.yaml"
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" zeta \
    'printf "%s\n" zeta >> "${DOTFILES_HOOK_LOG}"'
  extension_fixture_add_copilot_hook "${root}" alpha \
    'printf "%s\n" alpha >> "${DOTFILES_HOOK_LOG}"'
  extension_fixture_commit "${root}"
  mkdir -p "${root}/home"

  output="$(
    cd "${root}"
    HOME="${root}/home" \
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=development \
    DOTFILES_HOOK_LOG="${root}/hook.log" \
    ./install unix --dry-run --exit-on-failure 2>&1 |
      grep '^dotbot-base='
  )"
  expected="$(printf '%s\n' \
    "dotbot-base=${root} config=meta/base.yaml" \
    "dotbot-base=${root} config=${root}/meta/roles/copilot.yaml")"
  if [ "${output}" != "${expected}" ] ||
    [ "$(cat "${root}/hook.log")" != $'alpha\nzeta' ]; then
    echo "Expected host-driven Copilot hooks in extension-ID order before execution." >&2
    rm -rf "${root}"
    return 1
  fi

  : > "${root}/hook.log"
  output="$(extension_fixture_run_copilot_role "${root}" | grep '^dotbot-base=')" || {
    echo "Expected explicit Copilot role installation to run hooks successfully." >&2
    rm -rf "${root}"
    return 1
  }
  expected="dotbot-base=${root} config=${root}/meta/roles/copilot.yaml"
  if [ "${output}" != "${expected}" ] ||
    [ "$(cat "${root}/hook.log")" != $'alpha\nzeta' ]; then
    echo "Expected explicit Copilot hooks in extension-ID order before execution." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-permit)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" permit'
  extension_fixture_commit "${root}"
  output="$(extension_fixture_run_copilot_role "${root}" | grep '^dotbot-base=')" || {
    echo "Expected an explicit permit decision to allow Copilot execution." >&2
    rm -rf "${root}"
    return 1
  }
  if [ "${output}" != "dotbot-base=${root} config=${root}/meta/roles/copilot.yaml" ]; then
    echo "Expected permit decision to execute the Copilot role." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-skip)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" skip'
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    if printf '%s\n' "${output}" | grep -q '^dotbot-base='; then
      echo "Expected skip decision to prevent Copilot execution." >&2
      rm -rf "${root}"
      return 1
    fi
  else
    echo "Expected intentional skip decision to succeed." >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  for scenario in nonzero stderr malformed; do
    root="$(extension_fixture_new "copilot-hooks-${scenario}")"
    extension_fixture_add "${root}" extension "extension-host" unix
    printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
    case "${scenario}" in
      nonzero)
        extension_fixture_add_copilot_hook "${root}" extension 'exit 7'
        expected="failed"
        ;;
      stderr)
        extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" noise >&2'
        expected="stderr"
        ;;
      malformed)
        extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" unknown'
        expected="malformed"
        ;;
    esac
    extension_fixture_commit "${root}"
    if output="$(extension_fixture_run_copilot_role "${root}")"; then
      echo "Expected ${scenario} Copilot hook output to fail closed." >&2
      rm -rf "${root}"
      return 1
    fi
    if ! printf '%s\n' "${output}" | grep -Fqi "${expected}" ||
      printf '%s\n' "${output}" | grep -q '^dotbot-base='; then
      echo "Expected ${scenario} hook failure before Dotbot execution; got: ${output}" >&2
      rm -rf "${root}"
      return 1
    fi
    rm -rf "${root}"
  done

  root="$(extension_fixture_new copilot-hooks-fail-decision)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'printf "%s\n" fail'
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    echo "Expected fail decision to fail closed." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "fail decision" ||
    printf '%s\n' "${output}" | grep -q '^dotbot-base='; then
    echo "Expected fail decision before Dotbot execution; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-nonexec)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'exit 0' 0
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    echo "Expected non-executable Copilot hook to fail closed." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "must be executable"; then
    echo "Expected non-executable hook error; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-symlink)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  outside="${root}/outside-hook"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${outside}"
  chmod +x "${outside}"
  mkdir -p "${root}/extensions/extension/helpers"
  ln -s "${outside}" "${root}/extensions/extension/helpers/copilot-prerequisite"
  extension_fixture_commit "${root}"
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    echo "Expected symlinked Copilot hook to fail closed." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "must not be a symlink"; then
    echo "Expected symlink hook error; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-untracked)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_commit "${root}"
  extension_fixture_add_copilot_hook "${root}" extension 'exit 0'
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    echo "Expected untracked Copilot hook to fail closed." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "not clean in the index"; then
    echo "Expected untracked hook integrity error; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"

  root="$(extension_fixture_new copilot-hooks-mismatch)"
  extension_fixture_add "${root}" extension "extension-host" unix
  printf '%s\n' '- shell: []' > "${root}/meta/roles/copilot.yaml"
  extension_fixture_add_copilot_hook "${root}" extension 'exit 0'
  extension_fixture_commit "${root}"
  printf '%s\n' '# changed after staging' >> \
    "${root}/extensions/extension/helpers/copilot-prerequisite"
  if output="$(extension_fixture_run_copilot_role "${root}")"; then
    echo "Expected integrity-mismatched Copilot hook to fail closed." >&2
    rm -rf "${root}"
    return 1
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "not clean in the index"; then
    echo "Expected mismatched hook integrity error; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_claude_bun_dependency_and_addons() {
  status "Checking Claude resolves Bun before its role addons"
  local root
  local output
  local expected

  root="$(extension_fixture_new claude-bun-dependency)"
  extension_fixture_add "${root}" extension "extension-host" unix
  cp "${BASE_DIR}/meta/roles/bun.yaml" "${root}/meta/roles/bun.yaml"
  cp "${BASE_DIR}/meta/roles/claude.yaml" "${root}/meta/roles/claude.yaml"
  mkdir -p \
    "${root}/extensions/extension/meta/role-addons"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/bun.yaml"
  printf '%s\n' '- shell: []' \
    > "${root}/extensions/extension/meta/role-addons/claude.yaml"
  extension_fixture_commit "${root}"

  output="$(
    cd "${root}"
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=development \
    ./install-role claude --dry-run --exit-on-failure 2>&1 |
      grep '^dotbot-base='
  )"
  expected="$(printf '%s\n' \
    "dotbot-base=${root} config=${root}/meta/roles/bun.yaml" \
    "dotbot-base=${root}/extensions/extension config=${root}/extensions/extension/meta/role-addons/bun.yaml" \
    "dotbot-base=${root} config=${root}/meta/roles/claude.yaml" \
    "dotbot-base=${root}/extensions/extension config=${root}/extensions/extension/meta/role-addons/claude.yaml")"
  if [ "${output}" != "${expected}" ]; then
    echo "Expected Bun before Claude and addons immediately after each base role; got: ${output}" >&2
    rm -rf "${root}"
    return 1
  fi
  rm -rf "${root}"
}

check_claude_bun_direct_dry_run() {
  status "Checking direct Claude dry-run resolves Bun first"
  local tmp_home
  local tmp_bin
  local operation_log
  local output
  local bun_line
  local claude_line
  local command

  tmp_home="$(validation_workspace claude-bun-direct-home)"
  tmp_bin="$(validation_workspace claude-bun-direct-bin)"
  operation_log="${tmp_bin}/operations.log"
  mkdir -p "${tmp_home}" "${tmp_bin}"

  for command in apt-get brew npm curl; do
    cat > "${tmp_bin}/${command}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  install|update)
    printf '%s\n' "${command} \$*" >> "${operation_log}"
    exit 99
    ;;
esac
exit 0
SH
    chmod +x "${tmp_bin}/${command}"
  done
  cat > "${tmp_bin}/dpkg-query" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "${tmp_bin}/dpkg-query"

  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    OSTYPE=linux-gnu \
    DOTFILES_EXTENSIONS_MODE=normal \
    ./install-role claude --dry-run --exit-on-failure 2>&1
  )"; then
    echo "Expected direct Claude dry-run to pass: ${output}" >&2
    return 1
  fi
  bun_line="$(printf '%s\n' "${output}" | grep -n 'Would run command helpers/bun_setup.sh' | head -1 | cut -d: -f1)"
  claude_line="$(printf '%s\n' "${output}" | grep -n 'Would run command helpers/claude_setup.sh' | head -1 | cut -d: -f1)"
  if [ -z "${bun_line}" ] || [ -z "${claude_line}" ] ||
    [ "${bun_line}" -ge "${claude_line}" ]; then
    echo "Expected Bun to precede Claude in direct dry-run output: ${output}" >&2
    return 1
  fi
  if [ -s "${operation_log}" ]; then
    echo "Expected direct dry-run not to execute package or network operations: $(cat "${operation_log}")" >&2
    return 1
  fi
}

check_all_roles_include_optional_configs() {
  [ "${ALL_ROLES}" -eq 1 ] || return 0
  status "Checking all-role validation includes optional Bun and Claude configs"
  local configs=("$@")
  local role

  for role in bun claude; do
    if ! printf '%s\n' "${configs[@]+"${configs[@]}"}" |
      grep -Fxq "meta/roles/${role}.yaml"; then
      echo "Expected --all-roles validation to include meta/roles/${role}.yaml." >&2
      return 1
    fi
  done
}

check_copilot_settings_enable_experimental() {
  status "Checking Copilot settings enable experimental mode"

  "${VALIDATE_PYTHON}" - "${BASE_DIR}/home_files/.copilot/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as settings_file:
    settings = json.load(settings_file)

if settings.get("experimental") is not True:
    raise SystemExit("Expected default Copilot settings to set experimental=true")
PY
}

check_copilot_skills() {
  status "Checking repository-managed Copilot skills"
  local skills=(
    evidence-research
    grill-with-docs
    handoff
    tdd
    teach
  )
  local skill
  local skill_dir
  local name
  local description

  for skill in "${skills[@]+"${skills[@]}"}"; do
    skill_dir="${BASE_DIR}/home_files/.copilot/skills/${skill}"
    if [ ! -f "${skill_dir}/SKILL.md" ]; then
      echo "Missing Copilot skill file: ${skill_dir}/SKILL.md" >&2
      return 1
    fi

    name="$(sed -n 's/^name: //p' "${skill_dir}/SKILL.md" | head -1)"
    description="$(sed -n 's/^description: //p' "${skill_dir}/SKILL.md" | head -1)"
    if [ "${name}" != "${skill}" ]; then
      echo "Copilot skill name does not match its directory: ${skill_dir}" >&2
      return 1
    fi
    if [ -z "${description}" ]; then
      echo "Copilot skill has no description: ${skill_dir}/SKILL.md" >&2
      return 1
    fi
    if ! grep -q '^## Workflow$' "${skill_dir}/SKILL.md"; then
      echo "Copilot skill is missing its workflow section: ${skill_dir}/SKILL.md" >&2
      return 1
    fi
    if ! grep -Eq '^## .*guardrails$' "${skill_dir}/SKILL.md"; then
      echo "Copilot skill is missing its guardrails section: ${skill_dir}/SKILL.md" >&2
      return 1
    fi
  done
}

check_copilot_setup_merges_experimental_default() {
  status "Checking Copilot setup merges experimental default"
  local tmp_home
  local tmp_bin
  local output

  tmp_home="$(validation_workspace copilot-settings-home)"
  tmp_bin="$(validation_workspace copilot-settings-bin)"
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

  if ! "${VALIDATE_PYTHON}" - "${tmp_home}/.copilot/settings.json" <<'PY'
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

  if ! "${VALIDATE_PYTHON}" - "${tmp_home}/.copilot/settings.json" <<'PY'
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

check_copilot_setup_links_skills() {
  status "Checking Copilot setup links discoverable skills"
  local tmp_home
  local tmp_bin
  local skill

  tmp_home="$(validation_workspace copilot-skills-home)"
  tmp_bin="$(validation_workspace copilot-skills-bin)"
  mkdir -p "${tmp_home}/.copilot/skills/local-skill"
  printf '%s\n' \
    '---' \
    'name: local-skill' \
    'description: A user-owned test skill.' \
    '---' \
    '# Local skill' \
    > "${tmp_home}/.copilot/skills/local-skill/SKILL.md"

  cat > "${tmp_bin}/copilot" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) printf '%s\n' 'GitHub Copilot CLI 1.0.60' ;;
  *) printf '%s\n' "$*" ;;
esac
SH
  chmod +x "${tmp_bin}/copilot"

  if ! HOME="${tmp_home}" PATH="${tmp_bin}:${PATH}" helpers/copilot_setup.sh >/dev/null 2>&1; then
    echo "Expected Copilot setup to install repository-managed skills." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  for skill in evidence-research grill-with-docs handoff tdd teach; do
    if [ ! -L "${tmp_home}/.copilot/skills/${skill}" ]; then
      echo "Expected ${skill} to be installed as a skill symlink." >&2
      rm -rf "${tmp_home}" "${tmp_bin}"
      return 1
    fi
    if [ "$(readlink "${tmp_home}/.copilot/skills/${skill}")" != \
      "${BASE_DIR}/home_files/.copilot/skills/${skill}" ]; then
      echo "Copilot skill symlink points to the wrong source: ${skill}" >&2
      rm -rf "${tmp_home}" "${tmp_bin}"
      return 1
    fi
  done

  if [ ! -f "${tmp_home}/.copilot/skills/local-skill/SKILL.md" ]; then
    echo "Copilot setup removed an unrelated personal skill." >&2
    rm -rf "${tmp_home}" "${tmp_bin}"
    return 1
  fi

  rm -rf "${tmp_home}" "${tmp_bin}"
}

check_copilot_setup_installs_default_plugin() {
  status "Checking Copilot setup installs default plugin"
  local tmp_home
  local tmp_bin
  local operation_log
  local output
  local install_count

  tmp_home="$(validation_workspace copilot-plugin-home)"
  tmp_bin="$(validation_workspace copilot-plugin-bin)"
  operation_log="${tmp_home}/.copilot/plugin-operations.log"
  mkdir -p "${tmp_home}/.copilot"

  cat > "${tmp_bin}/copilot" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

state="${HOME}/.copilot/impeccable-installed"
operation_log="${HOME}/.copilot/plugin-operations.log"

case "${1:-}" in
  --version)
    printf '%s\n' 'GitHub Copilot CLI 1.0.60'
    ;;
  plugin)
    case "${2:-}" in
      list)
        printf '%s\n' 'Installed plugins:'
        if [ -e "${state}" ]; then
          printf '%s\n' '  impeccable (v4.1.1)'
        fi
        ;;
      install)
        printf '%s\n' "$*" >> "${operation_log}"
        touch "${state}"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  *)
    exit 2
    ;;
esac
SH
  chmod +x "${tmp_bin}/copilot"

  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:${PATH}" \
    helpers/copilot_setup.sh 2>&1
  )"; then
    echo "${output}" >&2
    return 1
  fi

  if ! grep -Fxq 'plugin install pbakaus/impeccable' "${operation_log}"; then
    echo "Expected Copilot setup to install Impeccable: ${output}" >&2
    return 1
  fi

  if ! output="$(
    HOME="${tmp_home}" \
    PATH="${tmp_bin}:${PATH}" \
    helpers/copilot_setup.sh 2>&1
  )"; then
    echo "${output}" >&2
    return 1
  fi

  install_count="$(grep -Fc 'plugin install pbakaus/impeccable' "${operation_log}")"
  if [ "${install_count}" -ne 1 ]; then
    echo "Expected repeated Copilot setup not to reinstall Impeccable: ${output}" >&2
    return 1
  fi
}

check_copilot_wrapper_supports_experimental_opt_out() {
  status "Checking Copilot wrapper supports experimental opt-out"
  local tmp_home
  local fake_bin
  local output
  local resolved

  tmp_home="$(validation_workspace copilot-wrapper)"
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

  tmp_home="$(validation_workspace tmux-setup-home)"
  tmp_bin="$(validation_workspace tmux-setup-bin)"
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

check_mosh_tmux_session() {
  status "Checking managed Mosh tmux chooser"
  local tmp_bin
  local tmux_log
  local output

  tmp_bin="$(validation_workspace mosh-tmux-bin)"
  tmux_log="${tmp_bin}/tmux.log"
  cat > "${tmp_bin}/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list-sessions)
    printf '%s\n' alpha beta
    ;;
  new-session)
    printf '%s\n' "$*" > "${TMUX_TEST_LOG}"
    ;;
  *)
    echo "Unexpected tmux command: $*" >&2
    exit 2
    ;;
esac
SH
  cat > "${tmp_bin}/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "${tmp_bin}/stty" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '24 80'
SH
  chmod +x "${tmp_bin}/tmux" "${tmp_bin}/sleep" "${tmp_bin}/stty"

  : > "${tmux_log}"
  output="$(
    printf '%s\n' 2 |
    PATH="${tmp_bin}:/usr/bin:/bin" \
    TMUX_TEST_LOG="${tmux_log}" \
      home_files/bin/mosh-tmux-session 2>&1
  )"
  case "${output}" in
    *"Tmux: 1=alpha 2=beta "*)
      ;;
    *)
      echo "Expected Mosh chooser to list existing sessions; got: ${output}" >&2
      rm -rf "${tmp_bin}"
      return 1
      ;;
  esac
  if [ "$(cat "${tmux_log}")" != "new-session -A -s beta" ]; then
    echo "Expected selection 2 to attach session beta." >&2
    rm -rf "${tmp_bin}"
    return 1
  fi

  : > "${tmux_log}"
  output="$(
    printf '%s\n' ipad |
    PATH="${tmp_bin}:/usr/bin:/bin" \
    TMUX_TEST_LOG="${tmux_log}" \
      home_files/bin/mosh-tmux-session 2>&1
  )"
  if [ "$(cat "${tmux_log}")" != "new-session -A -s ipad" ]; then
    echo "Expected a valid name to create or attach that session; got: ${output}" >&2
    rm -rf "${tmp_bin}"
    return 1
  fi

  : > "${tmux_log}"
  printf '\n' |
    PATH="${tmp_bin}:/usr/bin:/bin" \
    TMUX_TEST_LOG="${tmux_log}" \
      home_files/bin/mosh-tmux-session >/dev/null 2>&1
  if [ -s "${tmux_log}" ]; then
    echo "Expected a blank chooser response to leave a plain shell." >&2
    rm -rf "${tmp_bin}"
    return 1
  fi

  if grep -q '\.local/bin/mosh-tmux-session' home_files/.bashrc; then
    echo "Bash startup must not execute an unmanaged Mosh helper." >&2
    rm -rf "${tmp_bin}"
    return 1
  fi
  if ! grep -q '"$HOME/bin/mosh-tmux-session"' home_files/.bashrc; then
    echo "Bash startup does not reference the managed Mosh helper." >&2
    rm -rf "${tmp_bin}"
    return 1
  fi

  rm -rf "${tmp_bin}"
}

check_claude_setup_merges_safe_defaults() {
  status "Checking Claude setup merges safe defaults"
  local tmp_home
  local tmp_bin
  local output

  tmp_home="$(validation_workspace claude-settings-home)"
  tmp_bin="$(validation_workspace claude-settings-bin)"
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

  if ! "${VALIDATE_PYTHON}" \
    - \
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

  tmp_home="$(validation_workspace dotbot-home)"

  for cfg in "${configs[@]+"${configs[@]}"}"; do
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

  check_bash_3_2_compatibility
  check_bash_3_2_empty_array_compatibility
  check_host_helper_layout

  if [ "${VALIDATE_EXTENSION_ARGUMENT_PARSING_ONLY:-0}" -eq 1 ]; then
    check_extension_argument_parsing
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_FAMILY_ONLY:-0}" -eq 1 ]; then
    check_extension_family_contract
    return 0
  fi

  if [ "${VALIDATE_HOST_PROFILE_PARSER_ONLY:-0}" -eq 1 ]; then
    check_host_profile_parser_contract
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_PRODUCER_FAILURE_ONLY:-0}" -eq 1 ]; then
    check_extension_producer_failure_propagation
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_CONTAINMENT_ONLY:-0}" -eq 1 ]; then
    check_extension_path_containment
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_DETECTOR_OWNERSHIP_ONLY:-0}" -eq 1 ]; then
    check_extension_detector_ownership
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_COPILOT_SKIP_ONLY:-0}" -eq 1 ]; then
    check_extension_copilot_skip_contract
    return 0
  fi

  if [ "${VALIDATE_CLAUDE_BUN_DIRECT_ONLY:-0}" -eq 1 ]; then
    check_claude_bun_direct_dry_run
    return 0
  fi

  if [ "${VALIDATE_VALIDATION_CLEANUP_FAILURE_PROBE:-0}" -eq 1 ]; then
    validation_cleanup_failure_probe
    return $?
  fi

  if [ "${VALIDATE_VALIDATION_CLEANUP_SIGNAL_PROBE:-0}" -eq 1 ]; then
    validation_cleanup_signal_probe
    return $?
  fi

  if [ "${VALIDATE_VALIDATION_CLEANUP_SUCCESS_PROBE:-0}" -eq 1 ]; then
    validation_cleanup_success_probe
    return $?
  fi

  if [ "${VALIDATE_VALIDATION_CLEANUP_INT_PROBE:-0}" -eq 1 ]; then
    validation_cleanup_signal_probe
    return $?
  fi

  if [ "${VALIDATE_VALIDATION_CLEANUP_ONLY:-0}" -eq 1 ]; then
    check_validation_cleanup_registry
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_RUNTIME_CLEANUP_ONLY:-0}" -eq 1 ]; then
    check_extension_runtime_cleanup
    return 0
  fi

  if [ "${VALIDATE_EXTENSION_DANGLING_SYMLINK_ONLY:-0}" -eq 1 ]; then
    check_extension_dangling_symlink_rejection
    return 0
  fi

  if [ "${VALIDATE_SUBMODULE_BOOTSTRAP_ONLY:-0}" -eq 1 ]; then
    check_submodule_bootstrap_precedes_yaml_parsing
    return 0
  fi

  if [ "${VALIDATE_ROLE_GRAPH_ONLY:-0}" -eq 1 ]; then
    check_role_dependencies
    return 0
  fi

  if [ "${EXTENSIONS_ONLY}" -eq 1 ]; then
    check_extensions_disabled_requires_explicit_host
    check_extensions_foundation
    check_extension_validators
    check_extension_role_dependency_graph
    check_role_dependency_failures
    if [ "${VALIDATE_SKIP_EXTENSION_GRAPH_REGRESSION:-0}" -eq 0 ]; then
      check_extension_only_validates_repository_graph
    fi
    check_repository_extension_validators
    check_role_dependencies
      check_submodule_bootstrap_precedes_yaml_parsing
        check_symlinked_checkout_containment
    check_extension_host_addon_order
    check_extension_host_addon_install_order
    check_extension_cross_root_dependencies
    check_extension_install_role_source_root
    check_extension_argument_parsing
    check_extension_family_contract
    check_host_profile_parser_contract
    check_extension_producer_failure_propagation
    check_extension_path_containment
    check_extension_detector_ownership
    check_extension_dangling_symlink_rejection
    check_validation_cleanup_registry
    check_extension_runtime_cleanup
    check_extension_role_addon_order
    check_extension_duplicate_role_rejection
    check_extension_addon_dependency_rejection
    check_python_fallback_for_role_addons
    check_python_resolver_portability
    check_extension_host_env_defaults_and_override
    check_prompt_host_override
    check_extension_copilot_skip_contract
    check_extension_copilot_prerequisite_hooks
    check_claude_bun_dependency_and_addons
    check_claude_bun_direct_dry_run
    status "Extension foundation validation passed"
    return 0
  fi

  check_extensions_disabled_requires_explicit_host
  check_extensions_foundation
  check_extension_validators
  check_repository_extension_validators
  check_validation_cleanup_registry
  check_extension_runtime_cleanup
  check_prompt_host_override
  check_extension_copilot_skip_contract
  check_extension_copilot_prerequisite_hooks
  check_claude_bun_dependency_and_addons
  check_claude_bun_direct_dry_run
  check_submodule_bootstrap_precedes_yaml_parsing
  VALIDATE_PYTHON="$(find_validate_python)"
  readonly VALIDATE_PYTHON

  check_bash_syntax
  check_python_syntax
  check_apt_messages
  check_zsh_syntax
  check_zsh_noninteractive_path
  check_role_dependencies
  check_role_dependency_failures
  check_copilot_settings_enable_experimental
  check_copilot_skills
  check_copilot_setup_merges_experimental_default
  check_copilot_setup_links_skills
  check_copilot_setup_installs_default_plugin
  check_copilot_wrapper_supports_experimental_opt_out
  check_tmux_setup_repairs_broken_tpm_link
  check_mosh_tmux_session
  check_claude_setup_merges_safe_defaults
  configs=()
  while IFS= read -r config; do
    configs+=("${config}")
  done < <(collect_role_configs)
  check_all_roles_include_optional_configs "${configs[@]+"${configs[@]}"}"
  check_link_targets "${configs[@]+"${configs[@]}"}"
  check_readme_command_docs
  check_dotbot_dry_runs "${configs[@]+"${configs[@]}"}"

  status "Validation passed"
}

main "$@"
