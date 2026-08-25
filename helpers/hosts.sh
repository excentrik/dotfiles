#!/usr/bin/env bash

# Generic host model: family metadata, host profiles, detection, selection, env, and roles.
# helpers/extensions.sh and helpers/hosts.sh are co-required before
# extensions_initialize; this module uses the extension arrays and primitives.
# Host environment files accept blank lines, comments, and DOTFILES_NAME=value
# entries with declarative values; values are assigned without evaluation.

extensions_validate_family() {
  local family="$1"

  extensions_validate_identifier "${family}" "host family" || return 1
  case "${family}" in
    osx|unix|wsl|docker)
      return 0
      ;;
  esac
  echo "error: unsupported host family: '${family}'." >&2
  return 1
}

extensions_read_family() {
  local family_file="$1"
  local label="${2:-host family}"
  local line=""
  local value=""
  local current=""
  local line_count=0

  if [ ! -f "${family_file}" ] || [ -L "${family_file}" ]; then
    echo "error: missing or invalid ${label} metadata: '${family_file}'." >&2
    return 1
  fi
  while IFS= read -r current || [ -n "${current}" ]; do
    line_count=$((line_count + 1))
    if [ "${line_count}" -eq 1 ]; then
      line="${current}"
    fi
  done < "${family_file}"
  if [ "${line_count}" -ne 1 ] || [ -z "${line}" ] || [[ "${line}" == *$'\r'* ]]; then
    echo "error: malformed ${label} metadata: '${family_file}'." >&2
    return 1
  fi
  case "${line}" in
    family=*)
      value="${line#family=}"
      ;;
    family:*)
      value="${line#family:}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      ;;
    *)
      value="${line}"
      ;;
  esac
  extensions_validate_family "${value}" || return 1
  printf '%s\n' "${value}"
}

extensions_find_family_file() {
  local root="$1"
  local host="$2"
  local candidate="${root}/meta/host-families/${host}"

  if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  candidate="${root}/meta/host-families/${host}.yaml"
  if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  return 1
}

extensions_parse_manifest() {
  local manifest="$1"
  local line
  local key
  local value
  local host
  local saw_id=0
  local saw_hosts=0
  local host_values=()

  MANIFEST_ID=""
  MANIFEST_HOSTS=()
  while IFS= read -r line || [ -n "${line}" ]; do
    [[ "${line}" == \#* || -z "${line}" ]] && continue
    if [[ "${line}" != *=* ]]; then
      echo "error: malformed extension manifest line in '${manifest}'." >&2
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    case "${key}" in
      id)
        [ "${saw_id}" -eq 0 ] || {
          echo "error: duplicate id in extension manifest: '${manifest}'." >&2
          return 1
        }
        saw_id=1
        extensions_validate_identifier "${value}" "extension id" || return 1
        MANIFEST_ID="${value}"
        ;;
      hosts)
        [ "${saw_hosts}" -eq 0 ] || {
          echo "error: duplicate hosts in extension manifest: '${manifest}'." >&2
          return 1
        }
        saw_hosts=1
        [ -n "${value}" ] || {
          echo "error: extension manifest has no claimed hosts: '${manifest}'." >&2
          return 1
        }
        if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9_-]*(,[a-z0-9][a-z0-9_-]*)*$ ]]; then
          echo "error: malformed host list in extension manifest: '${manifest}'." >&2
          return 1
        fi
        IFS=, read -r -a host_values <<< "${value}"
        [ "${#host_values[@]}" -gt 0 ] || {
          echo "error: extension manifest has no claimed hosts: '${manifest}'." >&2
          return 1
        }
        for host in "${host_values[@]+"${host_values[@]}"}"; do
          extensions_validate_identifier "${host}" "claimed host" || return 1
          if extensions_array_contains "${host}" "${MANIFEST_HOSTS[@]+"${MANIFEST_HOSTS[@]}"}"; then
            echo "error: duplicate claimed host in extension manifest: '${host}'." >&2
            return 1
          fi
          MANIFEST_HOSTS+=("${host}")
        done
        ;;
      *)
        echo "error: unsupported extension manifest key '${key}' in '${manifest}'." >&2
        return 1
        ;;
    esac
  done < "${manifest}"

  [ "${saw_id}" -eq 1 ] || {
    echo "error: extension manifest is missing id: '${manifest}'." >&2
    return 1
  }
}

extensions_parse_host_roles() {
  local profile="$1"
  local line
  local role

  while IFS= read -r line || [ -n "${line}" ]; do
    if [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]*([^:]+)[[:space:]]*:[[:space:]]*~([[:space:]]+#.*)?[[:space:]]*$ ]]; then
      role="${BASH_REMATCH[1]}"
      role="${role#"${role%%[![:space:]]*}"}"
      role="${role%"${role##*[![:space:]]}"}"
      extensions_validate_identifier "${role}" "role" || return 1
      printf '%s\n' "${role}"
      continue
    fi
    echo "error: malformed host profile entry in '${profile}'." >&2
    return 1
  done < "${profile}"
}

extensions_validate_host_addons() {
  local root="$1"
  local addon_dir="${root}/meta/host-addons"
  local addon
  local host

  [ -e "${addon_dir}" ] || [ -L "${addon_dir}" ] || return 0
  [ -d "${addon_dir}" ] && [ ! -L "${addon_dir}" ] || {
    echo "error: extension host addon directory must be real: '${addon_dir}'." >&2
    return 1
  }
  while IFS= read -r addon; do
    if [ -L "${addon}" ] || [ ! -f "${addon}" ]; then
      echo "error: extension host addon must be a regular file: '${addon}'." >&2
      return 1
    fi
    case "${addon}" in
      *.yaml) ;;
      *)
        echo "error: extension host addon must use a .yaml filename: '${addon}'." >&2
        return 1
        ;;
    esac
    host="${addon##*/}"
    host="${host%.yaml}"
    extensions_validate_identifier "${host}" "host addon host" || return 1
    if [ ! -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
      echo "error: extension host addon must target a core host: '${addon}'." >&2
      return 1
    fi
    extensions_validate_active_path "${addon}" "${root}" "host addon" || return 1
    extensions_parse_host_roles "${addon}" >/dev/null || return 1
  done < <(find -P "${addon_dir}" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
}

extensions_validate_host_env_file() {
  local env_file="$1"
  local root="$2"
  local line
  local name
  local value
  local names=()

  extensions_validate_active_path "${env_file}" "${root}" "host environment file" || return 1
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -z "${line}" ] && continue
    [[ "${line}" == \#* ]] && continue
    if [[ "${line}" != *"="* ]] || [ "${line}" = "=" ]; then
      echo "error: malformed host environment line in '${env_file}'." >&2
      return 1
    fi
    name="${line%%=*}"
    value="${line#*=}"
    if [[ ! "${name}" =~ ^DOTFILES_[A-Z0-9_]+$ ]]; then
      echo "error: invalid host environment name '${name}' in '${env_file}'." >&2
      return 1
    fi
    if [[ ! "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]*$ ]]; then
      echo "error: invalid host environment value for '${name}' in '${env_file}'." >&2
      return 1
    fi
    if extensions_array_contains "${name}" "${names[@]+"${names[@]}"}"; then
      echo "error: duplicate host environment name '${name}' in '${env_file}'." >&2
      return 1
    fi
    names+=("${name}")
  done < "${env_file}"
}

extensions_validate_host_env_directory() {
  local root="$1"
  local env_dir="${root}/meta/host-env"
  local env_file
  local host

  [ -e "${env_dir}" ] || [ -L "${env_dir}" ] || return 0
  [ -d "${env_dir}" ] && [ ! -L "${env_dir}" ] || {
    echo "error: extension host environment directory must be real: '${env_dir}'." >&2
    return 1
  }
  while IFS= read -r env_file; do
    if [ -L "${env_file}" ] || [ ! -f "${env_file}" ]; then
      echo "error: extension host environment file must be a regular file: '${env_file}'." >&2
      return 1
    fi
    case "${env_file}" in
      *.env) ;;
      *)
        echo "error: extension host environment file must use a .env filename: '${env_file}'." >&2
        return 1
        ;;
    esac
    host="${env_file##*/}"
    host="${host%.env}"
    extensions_validate_identifier "${host}" "host environment host" || return 1
    if ! extensions_array_contains "${host}" "${MANIFEST_HOSTS[@]+"${MANIFEST_HOSTS[@]}"}" &&
      [ ! -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
      echo "error: undeclared extension host environment file: '${env_file}'." >&2
      return 1
    fi
    extensions_validate_host_env_file "${env_file}" "${root}" || return 1
  done < <(find -P "${env_dir}" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
}

extensions_validate_extension_profiles() {
  local root="$1"
  local profile_dir="${root}/meta/hosts"
  local profile
  local host
  local family_file
  local profiles=()
  local profile_host

  if [ ! -e "${profile_dir}" ] && [ ! -L "${profile_dir}" ]; then
    if [ "${#MANIFEST_HOSTS[@]}" -eq 0 ]; then
      return 0
    fi
    echo "error: extension is missing its host profile directory: '${profile_dir}'." >&2
    return 1
  fi
  if [ -L "${profile_dir}" ] || [ ! -d "${profile_dir}" ]; then
    echo "error: extension host profile directory must be a real directory: '${profile_dir}'." >&2
    return 1
  fi
  while IFS= read -r profile; do
    profiles+=("${profile}")
  done < <(find -P "${profile_dir}" -mindepth 1 -maxdepth 1 -type f -name '*.yaml' -print | LC_ALL=C sort)
  if [ "${#profiles[@]}" -eq 0 ] && [ "${#MANIFEST_HOSTS[@]}" -eq 0 ]; then
    return 0
  fi
  [ "${#profiles[@]}" -gt 0 ] || {
    echo "error: extension has no host profiles: '${profile_dir}'." >&2
    return 1
  }
  for profile in "${profiles[@]+"${profiles[@]}"}"; do
    profile_host="${profile##*/}"
    profile_host="${profile_host%.yaml}"
    extensions_validate_identifier "${profile_host}" "host profile" || return 1
    if ! extensions_array_contains "${profile_host}" "${MANIFEST_HOSTS[@]+"${MANIFEST_HOSTS[@]}"}"; then
      echo "error: undeclared extension host profile: '${profile}'." >&2
      return 1
    fi
    extensions_validate_active_path "${profile}" "${root}" "host profile" || return 1
    extensions_parse_host_roles "${profile}" >/dev/null || return 1
  done
  for host in "${MANIFEST_HOSTS[@]+"${MANIFEST_HOSTS[@]}"}"; do
    profile="${profile_dir}/${host}.yaml"
    if [ ! -f "${profile}" ] || [ -L "${profile}" ]; then
      echo "error: missing extension host profile: '${profile}'." >&2
      return 1
    fi
    family_file="$(extensions_find_family_file "${root}" "${host}")" || {
      echo "error: missing host family metadata for extension host '${host}'." >&2
      return 1
    }
    extensions_validate_active_path "${family_file}" "${root}" "host family metadata" || return 1
    family="$(extensions_read_family "${family_file}" "host family")" || return 1
    EXTENSION_PENDING_HOST_FAMILIES+=("${family}")
  done
}

extensions_validate_core_metadata() {
  local profile
  local host
  local family_file
  local family

  [ -d "${BASE_DIR}/meta/hosts" ] || {
    echo "error: missing core host profile directory." >&2
    return 1
  }
  [ -d "${BASE_DIR}/meta/host-families" ] || {
    echo "error: missing core host family directory." >&2
    return 1
  }
  while IFS= read -r profile; do
    host="${profile##*/}"
    host="${host%.yaml}"
    extensions_validate_identifier "${host}" "core host profile" || return 1
    family_file="${BASE_DIR}/meta/host-families/${host}"
    extensions_read_family "${family_file}" "core host family" >/dev/null || return 1
    extensions_parse_host_roles "${profile}" >/dev/null || return 1
  done < <(find -P "${BASE_DIR}/meta/hosts" -mindepth 1 -maxdepth 1 -type f -name '*.yaml' -print | LC_ALL=C sort)
}

extensions_find_host_index() {
  local host="$1"
  local index

  if [ "${#EXTENSION_HOST_NAMES[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_HOST_NAMES[@]}"; do
      [ "${EXTENSION_HOST_NAMES[index]}" = "${host}" ] && {
        printf '%s\n' "${index}"
        return 0
      }
    done
  fi
  return 1
}

extensions_detect_host() {
  local index
  local detector
  local runtime_dir
  local stdout_file
  local stderr_file
  local status
  local line
  local claim=""
  local claim_count
  local detector_output=()
  local owner_index

  EXTENSION_DETECTED_HOST=""
  if [ "${#EXTENSION_IDS[@]}" -gt 0 ]; then
    for index in "${!EXTENSION_IDS[@]}"; do
      detector="${EXTENSION_ROOTS[index]}/detect-host"
      [ -e "${detector}" ] || continue
      extensions_create_runtime_dir || return 2
      runtime_dir="${EXTENSIONS_RUNTIME_DIR}"
      stdout_file="${runtime_dir}/stdout"
      stderr_file="${runtime_dir}/stderr"
      if (cd "${EXTENSION_ROOTS[index]}" &&
        DOTFILES_EXTENSION_ID="${EXTENSION_IDS[index]}" \
        DOTFILES_EXTENSION_ROOT="${EXTENSION_ROOTS[index]}" \
        "${detector}" > "${stdout_file}" 2> "${stderr_file}"); then
        status=0
      else
        status=$?
      fi
      if [ "${status}" -ne 0 ]; then
        echo "error: extension detector failed: '${detector}'." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 2
      fi
      if [ -s "${stderr_file}" ]; then
        echo "error: extension detector wrote to stderr: '${detector}'." >&2
        cat "${stderr_file}" >&2
        extensions_cleanup_runtime_dirs || true
        extensions_restore_runtime_traps
        return 2
      fi
      detector_output=()
      while IFS= read -r line || [ -n "${line}" ]; do
        detector_output+=("${line}")
      done < "${stdout_file}"
      extensions_cleanup_runtime_dirs_and_restore || return 2
      claim_count="${#detector_output[@]}"
      [ "${claim_count}" -eq 0 ] && continue
      if [ "${claim_count}" -ne 1 ]; then
        echo "error: extension detector produced multiple claims: '${detector}'." >&2
        return 2
      fi
      claim="${detector_output[0]}"
      extensions_validate_identifier "${claim}" "detector output" || return 2
      owner_index="$(extensions_find_host_index "${claim}")" || {
        echo "error: detector claimed an undeclared host: '${claim}'." >&2
        return 2
      }
      if [ "${EXTENSION_HOST_OWNER_IDS[owner_index]}" != "${EXTENSION_IDS[index]}" ]; then
        echo "error: detector claimed a host owned by another extension: '${claim}'." >&2
        return 2
      fi
      if [ -n "${EXTENSION_DETECTED_HOST}" ]; then
        echo "error: multiple extension detectors claimed hosts." >&2
        return 2
      fi
      EXTENSION_DETECTED_HOST="${claim}"
    done
  fi
  [ -n "${EXTENSION_DETECTED_HOST}" ] && return 0
  return 1
}

extensions_detect_core_host() {
  case "${OSTYPE}" in
    darwin*)
      printf '%s\n' osx
      ;;
    linux*)
      if grep docker /proc/1/cgroup -qa; then
        printf '%s\n' docker
      elif grep -qE "(Microsoft|WSL)" /proc/version >/dev/null 2>&1; then
        printf '%s\n' wsl
      else
        printf '%s\n' unix
      fi
      ;;
    *)
      echo "unknown platform: ${OSTYPE}. Aborting" >&2
      return 1
      ;;
  esac
}

extensions_host_directive_exclusions() {
  if [ "$#" -ne 1 ]; then
    echo "error: extensions_host_directive_exclusions requires exactly one host family argument." >&2
    return 1
  fi
  local family="$1"

  extensions_validate_family "${family}" || return 1

  case "${family}" in
    osx)
      printf '%s\n' apt
      ;;
    unix|wsl|docker)
      printf '%s\n' tap brew cask brewfile services
      ;;
  esac
}

extensions_resolve_host() {
  local host="$1"
  local family_file
  local index
  local owner_id
  local host_index

  extensions_validate_identifier "${host}" "host" || return 1
  if [ -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
    family_file="${BASE_DIR}/meta/host-families/${host}"
    EXTENSION_SELECTED_ID=""
    EXTENSION_SELECTED_ROOT="${BASE_DIR}"
    EXTENSION_SELECTED_FAMILY="$(extensions_read_family "${family_file}" "core host family")" || return 1
    EXTENSION_SELECTED_IS_EXTENSION=0
    return 0
  fi
  index="$(extensions_find_host_index "${host}")" || {
    echo "Host type ${host} is not supported." >&2
    return 1
  }
  host_index="${index}"
  owner_id="${EXTENSION_HOST_OWNER_IDS[index]}"
  index="$(extensions_find_extension_index "${owner_id}")" || return 1
  EXTENSION_SELECTED_ID="${owner_id}"
  EXTENSION_SELECTED_ROOT="${EXTENSION_ROOTS[index]}"
  EXTENSION_SELECTED_FAMILY="${EXTENSION_HOST_FAMILIES[host_index]}"
  EXTENSION_SELECTED_IS_EXTENSION=1
}

extensions_apply_host_env() {
  local host="$1"
  local root

  if [ -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
    for root in "${EXTENSION_ROOTS[@]+"${EXTENSION_ROOTS[@]}"}"; do
      extensions_apply_host_env_file \
        "${root}/meta/host-env/${host}.env" "${root}" || return 1
    done
    return 0
  fi
  extensions_apply_host_env_file \
    "${EXTENSION_SELECTED_ROOT}/meta/host-env/${host}.env" \
    "${EXTENSION_SELECTED_ROOT}"
}

extensions_apply_host_env_file() {
  local env_file="$1"
  local root="$2"
  local line
  local name
  local value

  if [ ! -e "${env_file}" ] && [ ! -L "${env_file}" ]; then
    return 0
  fi
  extensions_validate_host_env_file "${env_file}" "${root}" || return 1
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -z "${line}" ] && continue
    [[ "${line}" == \#* ]] && continue
    name="${line%%=*}"
    value="${line#*=}"
    if ! extensions_variable_is_set "${name}"; then
      printf -v "${name}" '%s' "${value}"
      export "${name}"
    fi
  done < "${env_file}"
}

extensions_variable_is_set() {
  local name="$1"

  declare -p "${name}" >/dev/null 2>&1
}

extensions_host_family() {
  local host="$1"
  local index

  if [ -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
    extensions_read_family "${BASE_DIR}/meta/host-families/${host}" "core host family"
    return
  fi
  index="$(extensions_find_host_index "${host}")" || return 1
  printf '%s\n' "${EXTENSION_HOST_FAMILIES[index]}"
}

extensions_parse_host_addons() {
  local root="$1"
  local host="$2"
  local addon="${root}/meta/host-addons/${host}.yaml"

  if [ ! -e "${addon}" ] && [ ! -L "${addon}" ]; then
    return 0
  fi
  extensions_validate_active_path "${addon}" "${root}" "host addon" || return 1
  extensions_parse_host_roles "${addon}"
}

extensions_collect_host_roles() {
  local host="$1"
  local index
  local profile

  extensions_validate_identifier "${host}" "host" || return 1
  if [ -f "${BASE_DIR}/meta/hosts/${host}.yaml" ]; then
    profile="${BASE_DIR}/meta/hosts/${host}.yaml"
    extensions_parse_host_roles "${profile}" || return 1
    if [ "${#EXTENSION_ROOTS[@]}" -gt 0 ]; then
      for index in "${!EXTENSION_ROOTS[@]}"; do
        extensions_parse_host_addons "${EXTENSION_ROOTS[index]}" "${host}" || return 1
      done
    fi
    return 0
  fi

  if [ "${EXTENSION_SELECTED_IS_EXTENSION}" -ne 1 ] ||
    [ "${EXTENSION_SELECTED_ROOT}" = "" ]; then
    echo "Host type ${host} is not supported." >&2
    return 1
  fi
  profile="${EXTENSION_SELECTED_ROOT}/meta/hosts/${host}.yaml"
  extensions_parse_host_roles "${profile}"
}
