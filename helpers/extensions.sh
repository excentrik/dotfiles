#!/usr/bin/env bash

# Generic extension identity, discovery, integrity, runtime, and execution helpers.
# helpers/extensions.sh and helpers/hosts.sh are co-required before
# extensions_initialize; hosts.sh uses this module's arrays and primitives,
# while extensions_initialize calls host-model functions.

if [ "${DOTFILES_PYTHON_RESOLVER_LOADED:-0}" -ne 1 ]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/python_resolver.sh"
  DOTFILES_PYTHON_RESOLVER_LOADED=1
fi

if [ -z "${BASE_DIR:-}" ]; then
  BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
BASE_DIR="$(cd "${BASE_DIR}" && pwd -P)"

EXTENSIONS_ENABLED=1
EXTENSIONS_DEVELOPMENT=0
EXTENSION_IDS=()
EXTENSION_ROOTS=()
EXTENSION_HOST_NAMES=()
EXTENSION_HOST_OWNER_IDS=()
EXTENSION_HOST_FAMILIES=()
EXTENSION_DETECTED_HOST=""
EXTENSION_SELECTED_ID=""
EXTENSION_SELECTED_ROOT=""
EXTENSION_SELECTED_FAMILY=""
EXTENSION_SELECTED_IS_EXTENSION=0
EXTENSIONS_RUNTIME_DIRS=()
EXTENSIONS_RUNTIME_DIR=""
EXTENSIONS_RUNTIME_TRAPS_INSTALLED=0
EXTENSIONS_RUNTIME_PREVIOUS_EXIT_TRAP=""
EXTENSIONS_RUNTIME_PREVIOUS_INT_TRAP=""
EXTENSIONS_RUNTIME_PREVIOUS_TERM_TRAP=""

extensions_restore_saved_trap() {
  local signal="$1"
  local previous="$2"

  if [ -n "${previous}" ]; then
    eval "${previous}"
  else
    trap - "${signal}"
  fi
}

extensions_cleanup_runtime_dirs() {
  local runtime_dir
  local cleanup_status=0

  for runtime_dir in "${EXTENSIONS_RUNTIME_DIRS[@]+"${EXTENSIONS_RUNTIME_DIRS[@]}"}"; do
    [ -e "${runtime_dir}" ] || continue
    if ! rm -rf -- "${runtime_dir}" || [ -e "${runtime_dir}" ]; then
      cleanup_status=1
    fi
  done
  if [ "${cleanup_status}" -eq 0 ]; then
    EXTENSIONS_RUNTIME_DIRS=()
  else
    extensions_restore_runtime_traps
  fi
  return "${cleanup_status}"
}

extensions_restore_runtime_traps() {
  [ "${EXTENSIONS_RUNTIME_TRAPS_INSTALLED}" -eq 1 ] || return 0
  extensions_restore_saved_trap EXIT "${EXTENSIONS_RUNTIME_PREVIOUS_EXIT_TRAP}"
  extensions_restore_saved_trap INT "${EXTENSIONS_RUNTIME_PREVIOUS_INT_TRAP}"
  extensions_restore_saved_trap TERM "${EXTENSIONS_RUNTIME_PREVIOUS_TERM_TRAP}"
  EXTENSIONS_RUNTIME_TRAPS_INSTALLED=0
}

extensions_cleanup_runtime_dirs_and_restore() {
  local cleanup_status=0

  extensions_cleanup_runtime_dirs || cleanup_status=$?
  extensions_restore_runtime_traps
  return "${cleanup_status}"
}

extensions_execute_saved_exit_trap() {
  local status="$1"
  local previous="$2"

  [ -n "${previous}" ] || return 0
  (
    set +e
    eval "${previous}"
    exit "${status}"
  ) || true
}

extensions_runtime_exit_trap() {
  local status="$1"

  extensions_cleanup_runtime_dirs || true
  extensions_restore_runtime_traps
  extensions_execute_saved_exit_trap "${status}" "${EXTENSIONS_RUNTIME_PREVIOUS_EXIT_TRAP}"
  exit "${status}"
}

extensions_runtime_signal_trap() {
  local signal="$1"
  local status="$2"

  extensions_cleanup_runtime_dirs || true
  extensions_restore_runtime_traps
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

extensions_install_runtime_traps() {
  [ "${EXTENSIONS_RUNTIME_TRAPS_INSTALLED}" -eq 1 ] && return 0
  EXTENSIONS_RUNTIME_PREVIOUS_EXIT_TRAP="$(trap -p EXIT || true)"
  EXTENSIONS_RUNTIME_PREVIOUS_INT_TRAP="$(trap -p INT || true)"
  EXTENSIONS_RUNTIME_PREVIOUS_TERM_TRAP="$(trap -p TERM || true)"
  trap 'extensions_runtime_exit_trap "$?"' EXIT
  trap 'extensions_runtime_signal_trap INT "$?"' INT
  trap 'extensions_runtime_signal_trap TERM "$?"' TERM
  EXTENSIONS_RUNTIME_TRAPS_INSTALLED=1
}

extensions_create_runtime_dir() {
  local runtime_parent
  local runtime_dir

  runtime_parent="$(extensions_resolve_temp_parent)" || return 1
  extensions_install_runtime_traps
  runtime_dir="$(mktemp -d "${runtime_parent%/}/.extensions-runtime-XXXXXX")" || {
    echo "error: unable to create extension runtime temporary directory." >&2
    extensions_restore_runtime_traps
    return 1
  }
  if [ ! -d "${runtime_dir}" ]; then
    echo "error: extension runtime temporary directory was not created." >&2
    extensions_restore_runtime_traps
    return 1
  fi
  EXTENSIONS_RUNTIME_DIR="${runtime_dir}"
  EXTENSIONS_RUNTIME_DIRS+=("${runtime_dir}")
}

extensions_validate_identifier() {
  local value="$1"
  local description="${2:-value}"

  if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "error: invalid ${description}: '${value}'." >&2
    return 1
  fi
}

extensions_validate_mode() {
  case "${DOTFILES_EXTENSIONS:-1}" in
    0)
      EXTENSIONS_ENABLED=0
      ;;
    1)
      EXTENSIONS_ENABLED=1
      ;;
    *)
      echo "error: DOTFILES_EXTENSIONS must be 0 or 1." >&2
      return 1
      ;;
  esac

  case "${DOTFILES_EXTENSIONS_MODE:-normal}" in
    normal|"")
      EXTENSIONS_DEVELOPMENT=0
      ;;
    development)
      EXTENSIONS_DEVELOPMENT=1
      ;;
    *)
      echo "error: DOTFILES_EXTENSIONS_MODE must be normal or development." >&2
      return 1
      ;;
  esac
}

extensions_canonical_path() {
  local path="$1"
  local canonical_path
  local python

  [ -e "${path}" ] || return 1
  if command -v realpath >/dev/null 2>&1; then
    if canonical_path="$(realpath -e -- "${path}" 2>/dev/null)"; then
      printf '%s\n' "${canonical_path}"
      return 0
    fi
  fi
  if command -v readlink >/dev/null 2>&1 && readlink -f -- "${path}" >/dev/null 2>&1; then
    readlink -f -- "${path}"
    return
  fi
  if python="$(dotfiles_find_python3 2>/dev/null)"; then
    "${python}" - "${path}" <<'PY'
import os
import sys

if not os.path.exists(sys.argv[1]):
    raise SystemExit(1)
print(os.path.realpath(sys.argv[1]))
PY
    return
  fi
  echo "error: unable to canonicalize active path '${path}'." >&2
  return 1
}

extensions_resolve_temp_parent() {
  local runtime_parent="${TMPDIR:-/tmp}"
  local canonical_parent
  local canonical_root

  if [ ! -d "${runtime_parent}" ]; then
    echo "error: temporary directory is unavailable: '${runtime_parent}'." >&2
    return 1
  fi
  canonical_parent="$(extensions_canonical_path "${runtime_parent}")" || return 1
  canonical_root="$(extensions_canonical_path "${BASE_DIR}")" || return 1
  if extensions_path_is_within "${canonical_parent}" "${canonical_root}"; then
    echo "error: temporary directory must be outside the repository: '${runtime_parent}'." >&2
    return 1
  fi
  printf '%s\n' "${canonical_parent}"
}

extensions_path_is_within() {
  local path="$1"
  local root="$2"

  if [ "${path}" = "${root}" ]; then
    return 0
  fi
  case "${path}" in
    "${root}"/*) return 0 ;;
  esac
  return 1
}

extensions_relative_path() {
  local path="$1"
  local relative

  case "${path}" in
    "${BASE_DIR}"/*)
      relative="${path#"${BASE_DIR}"/}"
      ;;
    *)
      echo "error: active path is outside the repository: '${path}'." >&2
      return 1
      ;;
  esac
  printf '%s\n' "${relative}"
}

extensions_validate_git_integrity() {
  local path="$1"
  local relative

  relative="$(extensions_relative_path "${path}")" || return 1
  if [ "${EXTENSIONS_DEVELOPMENT}" -eq 1 ]; then
    if ! git ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1 ||
      ! git cat-file -e ":${relative}" >/dev/null 2>&1 ||
      ! git diff --quiet -- "${relative}"; then
      echo "error: active extension path is not clean in the index: '${relative}'." >&2
      return 1
    fi
  else
    if ! git cat-file -e "HEAD:${relative}" >/dev/null 2>&1 ||
      ! git ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1 ||
      ! git diff --quiet HEAD -- "${relative}"; then
      echo "error: active extension path does not exactly match HEAD: '${relative}'." >&2
      return 1
    fi
  fi
}

extensions_validate_active_path() {
  local path="$1"
  local root="$2"
  local label="${3:-active extension path}"
  local canonical_path
  local canonical_root

  if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
    echo "error: missing ${label}: '${path}'." >&2
    return 1
  fi
  if [ -L "${path}" ]; then
    echo "error: ${label} must be a regular contained file: '${path}'." >&2
    return 1
  fi
  if [ ! -f "${path}" ]; then
    echo "error: ${label} must be a regular file: '${path}'." >&2
    return 1
  fi

  canonical_path="$(extensions_canonical_path "${path}")" || return 1
  canonical_root="$(extensions_canonical_path "${root}")" || return 1
  if ! extensions_path_is_within "${canonical_path}" "${canonical_root}"; then
    echo "error: ${label} escapes its extension root: '${path}'." >&2
    return 1
  fi
  extensions_validate_git_integrity "${path}"
}

extensions_validate_active_tree() {
  local root="$1"
  local path
  local active_dir

  for active_dir in "${root}/meta" "${root}/helpers"; do
    if [ ! -e "${active_dir}" ] && [ ! -L "${active_dir}" ]; then
      continue
    fi
    if [ -L "${active_dir}" ] || [ ! -d "${active_dir}" ]; then
      echo "error: extension active directory must be a real directory: '${active_dir}'." >&2
      return 1
    fi
    while IFS= read -r path; do
      if [ -L "${path}" ]; then
        echo "error: extension active path must not be a symlink: '${path}'." >&2
        return 1
      fi
      if [ -d "${path}" ]; then
        continue
      fi
      extensions_validate_active_path "${path}" "${root}" || return 1
    done < <(find -P "${active_dir}" -mindepth 1 -print | LC_ALL=C sort)
  done
}

extensions_validate_passive_tree() {
  local root="$1"
  local passive_dir="${root}/home_files"
  local path
  local canonical_path
  local canonical_root

  if [ ! -e "${passive_dir}" ] && [ ! -L "${passive_dir}" ]; then
    return 0
  fi
  if [ -L "${passive_dir}" ] || [ ! -d "${passive_dir}" ]; then
    echo "error: extension home_files must be a real directory." >&2
    return 1
  fi
  canonical_root="$(extensions_canonical_path "${root}")" || return 1
  while IFS= read -r path; do
    canonical_path="$(extensions_canonical_path "${path}")" || {
      echo "error: extension home_files contains an unresolved path: '${path}'." >&2
      return 1
    }
    if ! extensions_path_is_within "${canonical_path}" "${canonical_root}"; then
      echo "error: extension home_files path escapes its extension root: '${path}'." >&2
      return 1
    fi
  done < <(find -P "${passive_dir}" -mindepth 1 -print | LC_ALL=C sort)
}

extensions_array_contains() {
  local needle="$1"
  shift
  local item

  for item in "$@"; do
    [ "${item}" = "${needle}" ] && return 0
  done
  return 1
}

extensions_find_extension_index() {
  local id="$1"
  local index

  if [ "${#EXTENSION_IDS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_IDS[@]}"; do
      [ "${EXTENSION_IDS[index]}" = "${id}" ] && {
        printf '%s\n' "${index}"
        return 0
      }
    done
  fi
  return 1
}

extensions_initialize() {
  local extension_entry
  local extension_root
  local extension_id
  local manifest
  local index
  local host_index
  local host
  local family_index
  local extension_parent
  local validator
  local detector
  local copilot_hook

  extensions_validate_mode || return 1
  extensions_validate_core_metadata || return 1
  EXTENSION_IDS=()
  EXTENSION_ROOTS=()
  EXTENSION_HOST_NAMES=()
  EXTENSION_HOST_OWNER_IDS=()
  EXTENSION_HOST_FAMILIES=()
  EXTENSION_DETECTED_HOST=""
  if [ "${EXTENSIONS_ENABLED}" -eq 0 ]; then
    return 0
  fi
  if [ ! -e "${BASE_DIR}/extensions" ] && [ ! -L "${BASE_DIR}/extensions" ]; then
    return 0
  fi
  if [ -L "${BASE_DIR}/extensions" ] || [ ! -d "${BASE_DIR}/extensions" ]; then
    echo "error: extensions must be a real directory." >&2
    return 1
  fi
  extension_parent="$(extensions_canonical_path "${BASE_DIR}/extensions")" || return 1
  while IFS= read -r extension_entry; do
    [ -n "${extension_entry}" ] || continue
    if [ -L "${extension_entry}" ] || [ ! -d "${extension_entry}" ]; then
      echo "error: extension entries must be real directories: '${extension_entry}'." >&2
      return 1
    fi
    extension_root="$(extensions_canonical_path "${extension_entry}")" || return 1
    if ! extensions_path_is_within "${extension_root}" "${extension_parent}"; then
      echo "error: extension root escapes the extensions directory: '${extension_entry}'." >&2
      return 1
    fi
    extension_id="${extension_entry##*/}"
    extensions_validate_identifier "${extension_id}" "extension directory id" || return 1
    manifest="${extension_root}/extension.conf"
    extensions_validate_active_path "${manifest}" "${extension_root}" "extension manifest" || return 1
    extensions_parse_manifest "${manifest}" || return 1
    if extensions_array_contains "${MANIFEST_ID}" "${EXTENSION_IDS[@]+"${EXTENSION_IDS[@]}"}"; then
      echo "error: duplicate extension id: '${MANIFEST_ID}'." >&2
      return 1
    fi
    if [ "${MANIFEST_ID}" != "${extension_id}" ]; then
      echo "error: extension manifest id '${MANIFEST_ID}' does not match directory '${extension_id}'." >&2
      return 1
    fi
    EXTENSION_IDS+=("${MANIFEST_ID}")
    EXTENSION_ROOTS+=("${extension_root}")
    EXTENSION_PENDING_HOST_FAMILIES=()
    extensions_validate_active_tree "${extension_root}" || return 1
    extensions_validate_passive_tree "${extension_root}" || return 1
    detector="${extension_root}/detect-host"
    if [ -e "${detector}" ] || [ -L "${detector}" ]; then
      extensions_validate_active_path "${detector}" "${extension_root}" "host detector" || return 1
      [ -x "${detector}" ] || {
        echo "error: host detector must be executable: '${detector}'." >&2
        return 1
      }
    fi
    validator="${extension_root}/validate.sh"
    if [ -e "${validator}" ] || [ -L "${validator}" ]; then
      extensions_validate_active_path "${validator}" "${extension_root}" "extension validator" || return 1
      [ -x "${validator}" ] || {
        echo "error: extension validator must be executable: '${validator}'." >&2
        return 1
      }
    fi
    # Optional Copilot prerequisite policy hook. The fixed path is
    # extensions/<id>/helpers/copilot-prerequisite. It runs only when the
    # core copilot role is selected, with the extension ID and root exported;
    # silent zero exit or `permit` allows the role, `skip` omits it, and
    # `fail` or any malformed output fails closed.
    copilot_hook="${extension_root}/helpers/copilot-prerequisite"
    if [ -e "${copilot_hook}" ] || [ -L "${copilot_hook}" ]; then
      extensions_validate_active_path \
        "${copilot_hook}" "${extension_root}" "Copilot prerequisite hook" || return 1
      [ -x "${copilot_hook}" ] || {
        echo "error: Copilot prerequisite hook must be executable: '${copilot_hook}'." >&2
        return 1
      }
    fi
    extensions_validate_extension_profiles "${extension_root}" || return 1
    extensions_validate_host_addons "${extension_root}" || return 1
    extensions_validate_host_env_directory "${extension_root}" || return 1
    if [ "${#MANIFEST_HOSTS[@]}" -gt 0 ]; then
      for index in "${!MANIFEST_HOSTS[@]}"; do
        host="${MANIFEST_HOSTS[index]}"
        if extensions_find_host_index "${host}" >/dev/null; then
          echo "error: duplicate primary host profile: '${host}'." >&2
          return 1
        fi
        if [ -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
          echo "error: extension host duplicates core host profile: '${host}'." >&2
          return 1
        fi
        family_index="${index}"
        EXTENSION_HOST_NAMES+=("${host}")
        EXTENSION_HOST_OWNER_IDS+=("${MANIFEST_ID}")
        EXTENSION_HOST_FAMILIES+=("${EXTENSION_PENDING_HOST_FAMILIES[family_index]}")
      done
    fi
  done < <(find -P "${BASE_DIR}/extensions" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)

  extensions_validate_role_roots || return 1
  extensions_validate_role_addons || return 1
}

extensions_run_validators() {
  local index
  local validator
  local runtime_dir
  local stdout_file
  local stderr_file
  local validator_status

  if [ "${#EXTENSION_IDS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_IDS[@]}"; do
      validator="${EXTENSION_ROOTS[index]}/validate.sh"
      [ -e "${validator}" ] || continue
      extensions_validate_active_path \
        "${validator}" "${EXTENSION_ROOTS[index]}" "extension validator" || return 1
      [ -x "${validator}" ] || {
        echo "error: extension validator must be executable: '${validator}'." >&2
        return 1
      }

      extensions_create_runtime_dir || return 1
      runtime_dir="${EXTENSIONS_RUNTIME_DIR}"
      stdout_file="${runtime_dir}/stdout"
      stderr_file="${runtime_dir}/stderr"
      if (
        cd "${EXTENSION_ROOTS[index]}" &&
        DOTFILES_EXTENSION_ID="${EXTENSION_IDS[index]}" \
        DOTFILES_EXTENSION_ROOT="${EXTENSION_ROOTS[index]}" \
        "${validator}" > "${stdout_file}" 2> "${stderr_file}"
      ); then
        validator_status=0
      else
        validator_status=$?
      fi
      if [ -s "${stdout_file}" ]; then
        cat "${stdout_file}"
      fi
      if [ "${validator_status}" -ne 0 ]; then
        echo "error: extension validator failed: '${validator}' (exit ${validator_status})." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 1
      fi
      if [ -s "${stderr_file}" ]; then
        echo "error: extension validator wrote to stderr: '${validator}'." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 1
      fi
      extensions_cleanup_runtime_dirs_and_restore || return 1
    done
  fi
}

extensions_run_copilot_prerequisite_hooks() {
  local index
  local hook
  local runtime_dir
  local stdout_file
  local stderr_file
  local status
  local line
  local decision_line
  local decision
  local line_count

  EXTENSIONS_COPILOT_SKIP=0
  if ! extensions_array_contains copilot "${EXPANDED_ROLES[@]+"${EXPANDED_ROLES[@]}"}"; then
    return 0
  fi

  if [ "${#EXTENSION_IDS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_IDS[@]}"; do
      hook="${EXTENSION_ROOTS[index]}/helpers/copilot-prerequisite"
      [ -e "${hook}" ] || [ -L "${hook}" ] || continue
      extensions_validate_active_path \
        "${hook}" "${EXTENSION_ROOTS[index]}" "Copilot prerequisite hook" || return 1
      [ -x "${hook}" ] || {
        echo "error: Copilot prerequisite hook must be executable: '${hook}'." >&2
        return 1
      }

      extensions_create_runtime_dir || return 1
      runtime_dir="${EXTENSIONS_RUNTIME_DIR}"
      stdout_file="${runtime_dir}/stdout"
      stderr_file="${runtime_dir}/stderr"
      if (
        cd "${EXTENSION_ROOTS[index]}" &&
        DOTFILES_EXTENSION_ID="${EXTENSION_IDS[index]}" \
        DOTFILES_EXTENSION_ROOT="${EXTENSION_ROOTS[index]}" \
        "${hook}" > "${stdout_file}" 2> "${stderr_file}"
      ); then
        status=0
      else
        status=$?
      fi
      if [ "${status}" -ne 0 ]; then
        echo "error: Copilot prerequisite hook failed: '${hook}' (exit ${status})." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 1
      fi
      if [ -s "${stderr_file}" ]; then
        echo "error: Copilot prerequisite hook wrote to stderr: '${hook}'." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 1
      fi

      decision="permit"
      if [ -s "${stdout_file}" ]; then
        line_count=0
        line=""
        decision_line=""
        while IFS= read -r line || [ -n "${line}" ]; do
          line_count=$((line_count + 1))
          decision_line="${line}"
        done < "${stdout_file}"
        if [ "${line_count}" -ne 1 ]; then
          echo "error: malformed Copilot prerequisite hook decision: '${hook}'." >&2
          extensions_cleanup_runtime_dirs || true
          extensions_restore_runtime_traps
          return 1
        fi
        case "${decision_line}" in
          permit)
            decision="permit"
            ;;
          skip)
            decision="skip"
            ;;
          fail)
            echo "error: Copilot prerequisite hook returned fail decision: '${hook}'." >&2
            extensions_cleanup_runtime_dirs || true
            extensions_restore_runtime_traps
            return 1
            ;;
          *)
            echo "error: malformed Copilot prerequisite hook decision: '${hook}'." >&2
            extensions_cleanup_runtime_dirs || true
            extensions_restore_runtime_traps
            return 1
            ;;
        esac
      fi
      extensions_cleanup_runtime_dirs_and_restore || return 1
      if [ "${decision}" = "skip" ]; then
        EXTENSIONS_COPILOT_SKIP=1
      fi
    done
  fi
}

extensions_validate_role_roots() {
  local root
  local role_dir
  local role_file
  local role
  local role_owners=()

  for root in "${BASE_DIR}" "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}"; do
    role_dir="${root}/meta/roles"
    [ -d "${role_dir}" ] || continue
    while IFS= read -r role_file; do
      role="${role_file##*/}"
      role="${role%.yaml}"
      extensions_validate_identifier "${role}" "role" || return 1
      if extensions_array_contains "${role}" "${role_owners[@]+"${role_owners[@]}"}"; then
        echo "error: duplicate role name across roots: '${role}'." >&2
        return 1
      fi
      role_owners+=("${role}")
    done < <(find -P "${role_dir}" -mindepth 1 -maxdepth 1 -type f \
      -name '*.yaml' -print | LC_ALL=C sort)
  done
}

extensions_validate_role_addons() {
  local root
  local addon_dir
  local addon
  local role

  for root in "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}"; do
    addon_dir="${root}/meta/role-addons"
    [ -e "${addon_dir}" ] || [ -L "${addon_dir}" ] || continue
    [ -d "${addon_dir}" ] && [ ! -L "${addon_dir}" ] || {
      echo "error: extension role addon directory must be real: '${addon_dir}'." >&2
      return 1
    }
    while IFS= read -r addon; do
      if [ -L "${addon}" ] || [ ! -f "${addon}" ]; then
        echo "error: extension role addon must be a regular file: '${addon}'." >&2
        return 1
      fi
      case "${addon}" in
        *.yaml) ;;
        *)
          echo "error: extension role addon must use a .yaml filename: '${addon}'." >&2
          return 1
          ;;
      esac
      role="${addon##*/}"
      role="${role%.yaml}"
      extensions_validate_identifier "${role}" "role addon" || return 1
      extensions_validate_active_path "${addon}" "${root}" "role addon" || return 1
      extensions_validate_role_addon "${addon}" || return 1
    done < <(find -P "${addon_dir}" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
  done
}

extensions_configure_role_dependencies() {
  ROLE_DEPS_ROOTS=("${BASE_DIR}" "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}")
}

extensions_role_directories() {
  local index

  printf '%s\n' "${BASE_DIR}/meta/roles"
  if [ "${#EXTENSION_ROOTS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_ROOTS[@]}"; do
      printf '%s\n' "${EXTENSION_ROOTS[index]}/meta/roles"
    done
  fi
}

extensions_role_addon_directories() {
  local index

  printf '%s\n' "${BASE_DIR}/meta/role-addons"
  if [ "${#EXTENSION_ROOTS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_ROOTS[@]}"; do
      printf '%s\n' "${EXTENSION_ROOTS[index]}/meta/role-addons"
    done
  fi
}

extensions_validate_role_addon() {
  local addon="$1"
  local python
  local output
  local parser_status

  python="$(dotfiles_find_python3)" || {
    echo "error: unable to validate role addon YAML: '${addon}'." >&2
    return 1
  }

  if output="$(
    PYTHONPATH="${BASE_DIR}/dotbot/lib/pyyaml/lib${PYTHONPATH:+:${PYTHONPATH}}" \
      "${python}" - "${addon}" 2>&1 <<'PY'
import sys

import yaml

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as addon_file:
        document = yaml.safe_load(addon_file)
except (OSError, yaml.YAMLError) as error:
    print("unable to parse role addon YAML: {}".format(error), file=sys.stderr)
    raise SystemExit(1)


def contains_depends(value):
    if isinstance(value, dict):
        if "depends" in value:
            return True
        return any(contains_depends(item) for item in value.values())
    if isinstance(value, list):
        return any(contains_depends(item) for item in value)
    return False


if contains_depends(document):
    raise SystemExit(10)
PY
  )"; then
    return 0
  else
    parser_status=$?
  fi
  if [ "${parser_status}" -eq 10 ]; then
    echo "error: role addon may not declare dependencies: '${addon}'." >&2
  else
    echo "error: ${output}: '${addon}'." >&2
  fi
  if [ "${parser_status}" -ne 10 ]; then
    return 1
  fi
  return 1
}

extensions_resolve_role_addons() {
  local role="$1"
  local root
  local addon

  extensions_validate_identifier "${role}" "role" || return 1
  for root in "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}"; do
    addon="${root}/meta/role-addons/${role}.yaml"
    [ -e "${addon}" ] || [ -L "${addon}" ] || continue
    extensions_validate_active_path "${addon}" "${root}" "role addon" || return 1
    extensions_validate_role_addon "${addon}" || return 1
    printf '%s\n' "${addon}"
  done
}

extensions_resolve_role_config() {
  local role="$1"
  local root
  local candidate
  local resolved=""

  extensions_validate_identifier "${role}" "role" || return 1
  for root in "${BASE_DIR}" "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}"; do
    candidate="${root}/meta/roles/${role}.yaml"
    if [ -f "${candidate}" ] && [ ! -L "${candidate}" ]; then
      if [ -n "${resolved}" ]; then
        echo "error: duplicate role name across roots: '${role}'." >&2
        return 1
      fi
      resolved="${candidate}"
    fi
  done
  if [ -n "${resolved}" ]; then
    printf '%s\n' "${resolved}"
    return 0
  fi
  echo "Role ${role} is not supported." >&2
  return 1
}

extensions_role_config_root() {
  local config="$1"
  local index

  case "${config}" in
    "${BASE_DIR}/meta/roles/"*.yaml)
      printf '%s\n' "${BASE_DIR}"
      return 0
      ;;
  esac
  if [ "${#EXTENSION_ROOTS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_ROOTS[@]}"; do
      case "${config}" in
        "${EXTENSION_ROOTS[index]}/meta/roles/"*.yaml)
          printf '%s\n' "${EXTENSION_ROOTS[index]}"
          return 0
          ;;
      esac
    done
  fi
  echo "error: role config is outside known role roots: '${config}'." >&2
  return 1
}

extensions_role_addon_root() {
  local addon="$1"
  local index

  if [ "${#EXTENSION_ROOTS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_ROOTS[@]}"; do
      case "${addon}" in
        "${EXTENSION_ROOTS[index]}/meta/role-addons/"*.yaml)
          printf '%s\n' "${EXTENSION_ROOTS[index]}"
          return 0
          ;;
      esac
    done
  fi
  echo "error: role addon is outside known extension roots: '${addon}'." >&2
  return 1
}
