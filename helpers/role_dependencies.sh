#!/usr/bin/env bash

ROLE_DEPS_META_DIR="${ROLE_DEPS_META_DIR:-meta}"
ROLE_DEPS_CONFIG_DIR="${ROLE_DEPS_CONFIG_DIR:-roles}"
ROLE_DEPS_CONFIG_SUFFIX="${ROLE_DEPS_CONFIG_SUFFIX:-.yaml}"
ROLE_DEPS_ROOTS=()

if [ "${DOTFILES_PYTHON_RESOLVER_LOADED:-0}" -ne 1 ]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/python_resolver.sh"
  DOTFILES_PYTHON_RESOLVER_LOADED=1
fi

role_deps_validate_identifier() {
  local value="$1"
  local description="${2:-role}"

  if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "error: invalid ${description}: '${value}'." >&2
    return 1
  fi
}

role_deps_initialize_roots() {
  if ! declare -p ROLE_DEPS_ROOTS >/dev/null 2>&1; then
    ROLE_DEPS_ROOTS=()
  fi
}

role_deps_find_role_file() {
  local role="$1"
  local root
  local candidate

  role_deps_initialize_roots
  role_deps_validate_identifier "${role}" "role" || return 1
  if [ "${#ROLE_DEPS_ROOTS[@]}" -eq 0 ]; then
    candidate="${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}/${role}${ROLE_DEPS_CONFIG_SUFFIX}"
    [ -f "${candidate}" ] && [ ! -L "${candidate}" ] || return 1
    printf '%s\n' "${candidate}"
    return 0
  fi
  for root in "${ROLE_DEPS_ROOTS[@]+"${ROLE_DEPS_ROOTS[@]}"}"; do
    candidate="${root}/${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}/${role}${ROLE_DEPS_CONFIG_SUFFIX}"
    if [ -f "${candidate}" ] && [ ! -L "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

role_deps_read_dependencies() {
  local role="$1"
  local role_file
  local python
  local output

  role_deps_validate_identifier "${role}" "role" || return 1
  role_file="$(role_deps_find_role_file "${role}")" || return 0
  python="$(dotfiles_find_python3)" || return 1
  if ! output="$(
    PYTHONPATH="${BASE_DIR:-.}/dotbot/lib/pyyaml/lib${PYTHONPATH:+:${PYTHONPATH}}" \
      "${python}" - "${role_file}" 2>&1 <<'PY'
import re
import sys

import yaml

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as role_file:
        document = yaml.safe_load(role_file)
except (OSError, yaml.YAMLError) as error:
    print("unable to parse role YAML: {}".format(error), file=sys.stderr)
    raise SystemExit(1)

if document is None:
    raise SystemExit(0)
if not isinstance(document, list):
    print("configuration file must be a list of tasks", file=sys.stderr)
    raise SystemExit(1)

identifier = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
for task_index, task in enumerate(document):
    if not isinstance(task, dict) or "depends" not in task:
        continue
    dependencies = task["depends"]
    if not isinstance(dependencies, list) or not all(
        isinstance(item, str) for item in dependencies
    ):
        print(
            "depends directive must be a list of role names "
            "(task {})".format(task_index),
            file=sys.stderr,
        )
        raise SystemExit(1)
    for dependency in dependencies:
        if not identifier.fullmatch(dependency):
            print(
                "invalid dependency role name: '{}'".format(dependency),
                file=sys.stderr,
            )
            raise SystemExit(1)
        print(dependency)
PY
  )"; then
    printf '%s\n' "${output}" >&2
    return 1
  fi
  printf '%s\n' "${output}"
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
  role_deps_validate_identifier "${role}" "role" || return 1
  if ! role_deps_find_role_file "${role}" >/dev/null; then
    echo "Role ${role} is not supported." >&2
    return 1
  fi
}

role_deps_expand_role() {
  local role="$1"
  local dependency
  local stack_index
  local dependency_output

  role_deps_validate_identifier "${role}" "role" || return 1
  role_deps_validate_role_exists "${role}" || return 1
  if role_deps_in_array "${role}" "${EXPANDED_ROLES[@]+"${EXPANDED_ROLES[@]}"}"; then
    return 0
  fi
  if role_deps_in_array "${role}" "${ROLE_EXPANSION_STACK[@]+"${ROLE_EXPANSION_STACK[@]}"}"; then
    echo "error: cyclic role dependency involving '${role}'." >&2
    return 1
  fi

  ROLE_EXPANSION_STACK+=("${role}")
  dependency_output="$(role_deps_read_dependencies "${role}")" || return 1
  while IFS= read -r dependency; do
    [ -n "${dependency}" ] || continue
    role_deps_expand_role "${dependency}" || return 1
  done <<EOF
${dependency_output}
EOF
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
  local root
  local failures=0

  role_deps_initialize_roots
  if [ "${#ROLE_DEPS_ROOTS[@]}" -gt 0 ]; then
    for root in "${ROLE_DEPS_ROOTS[@]+"${ROLE_DEPS_ROOTS[@]}"}"; do
      while IFS= read -r role_file; do
        role="${role_file##*/}"
        role="${role%"${ROLE_DEPS_CONFIG_SUFFIX}"}"
        if ! role_deps_expand_roles "${role}"; then
          failures=$((failures + 1))
        fi
      done < <(find -P "${root}/${ROLE_DEPS_META_DIR}/${ROLE_DEPS_CONFIG_DIR}" \
        -mindepth 1 -maxdepth 1 -type f -name "*${ROLE_DEPS_CONFIG_SUFFIX}" \
        -print 2>/dev/null | LC_ALL=C sort)
    done
    if [ "${failures}" -ne 0 ]; then
      return 1
    fi
    return 0
  fi

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
  return 0
}
