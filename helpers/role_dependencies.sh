#!/usr/bin/env bash

ROLE_DEPS_META_DIR="${ROLE_DEPS_META_DIR:-meta}"
ROLE_DEPS_CONFIG_DIR="${ROLE_DEPS_CONFIG_DIR:-roles}"
ROLE_DEPS_CONFIG_SUFFIX="${ROLE_DEPS_CONFIG_SUFFIX:-.yaml}"

role_deps_read_dependencies() {
  local role="$1"
  local role_file="${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}/${role}${ROLE_DEPS_CONFIG_SUFFIX}"

  [ -f "${role_file}" ] || return 0
  awk '
    function trim(value) {
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      return value
    }
    function print_dependency(value) {
      value = trim(value)
      gsub(/^["'\'']|["'\'']$/, "", value)
      if (value != "") {
        print value
      }
    }
    function print_inline_dependencies(value, count, i, parts) {
      value = trim(value)
      if (value !~ /^\[/ || value !~ /\]$/) {
        return
      }
      sub(/^\[/, "", value)
      sub(/\]$/, "", value)
      count = split(value, parts, ",")
      for (i = 1; i <= count; i++) {
        print_dependency(parts[i])
      }
    }
    /^-[[:space:]]+depends:/ {
      inline = $0
      sub(/^-[[:space:]]+depends:[[:space:]]*/, "", inline)
      sub(/[[:space:]]*#.*$/, "", inline)
      print_inline_dependencies(inline)
      in_dep = 1
      next
    }
    in_dep && /^-[[:space:]]+/ {
      in_dep = 0
    }
    in_dep && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      print_dependency($0)
    }
  ' "${role_file}"
}

role_deps_in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [ "${item}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

role_deps_validate_role_exists() {
  local role="$1"
  if [ ! -f "${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}/${role}${ROLE_DEPS_CONFIG_SUFFIX}" ]; then
    echo "Role ${role} is not supported." >&2
    return 1
  fi
}

role_deps_expand_role() {
  local role="$1"
  local dependency
  local stack_index

  role_deps_validate_role_exists "${role}" || return 1
  if role_deps_in_array "${role}" ${EXPANDED_ROLES+"${EXPANDED_ROLES[@]}"}; then
    return 0
  fi
  if role_deps_in_array "${role}" ${ROLE_EXPANSION_STACK+"${ROLE_EXPANSION_STACK[@]}"}; then
    echo "error: cyclic role dependency involving '${role}'." >&2
    return 1
  fi

  ROLE_EXPANSION_STACK+=("${role}")
  while IFS= read -r dependency; do
    role_deps_expand_role "${dependency}" || return 1
  done < <(role_deps_read_dependencies "${role}")
  stack_index=$((${#ROLE_EXPANSION_STACK[@]} - 1))
  unset "ROLE_EXPANSION_STACK[${stack_index}]"

  EXPANDED_ROLES+=("${role}")
}

role_deps_expand_roles() {
  local role
  EXPANDED_ROLES=()
  ROLE_EXPANSION_STACK=()

  for role in "$@"; do
    role_deps_expand_role "${role}" || return 1
  done
}

role_deps_validate_graph() {
  local role
  local role_file
  local failures=0

  for role_file in "${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}"/*"${ROLE_DEPS_CONFIG_SUFFIX}"; do
    [ -e "${role_file}" ] || continue
    role="${role_file##*/}"
    role="${role%"${ROLE_DEPS_CONFIG_SUFFIX}"}"
    if ! role_deps_expand_roles "${role}"; then
      failures=$((failures + 1))
    fi
  done

  if [ "${failures}" -ne 0 ]; then
    return 1
  fi
}
