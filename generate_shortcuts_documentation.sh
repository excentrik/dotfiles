#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README_PATH="${BASE_DIR}/README.md"
COMMANDS_HEADING="## Commands available"
CHECK_ONLY=0

usage() {
  cat <<'USAGE'
Usage: ./generate_shortcuts_documentation.sh [--check]

Regenerates the README "Commands available" section from documented aliases
and functions. Use --check to fail when the generated section is out of date
without modifying README.md.
USAGE
}

for arg in "$@"; do
  case "${arg}" in
    --check)
      CHECK_ONLY=1
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

link_if_available() {
  local bin_dir="$1"
  local name="$2"
  local target

  target="$(type -P "${name}" 2>/dev/null || true)"
  if [ -n "${target}" ]; then
    ln -s "${target}" "${bin_dir}/${name}"
  fi
}

create_command_doc_path() {
  local bin_dir="$1"
  local name
  local real_commands=(
    awk
    basename
    cut
    echo
    egrep
    fgrep
    find
    grep
    head
    readlink
    sed
    sort
    tr
    xargs
  )
  local system_command_stubs=(
    cat
    df
    diff
    du
    less
    man
    mkdir
    more
    ping
    sudo
    which
    ls
  )

  mkdir -p "${bin_dir}"

  for name in "${real_commands[@]}"; do
    link_if_available "${bin_dir}" "${name}"
  done

  local true_path
  true_path="$(type -P true)"
  for name in "${system_command_stubs[@]}"; do
    ln -s "${true_path}" "${bin_dir}/${name}"
  done
}

read_readme_prelude() {
  awk -v heading="${COMMANDS_HEADING}" '
    $0 == heading { found = 1; exit }
    { print }
    END { if (!found) exit 1 }
  ' "${README_PATH}"
}

generate_command_list() {
  local tmp_home
  local tmp_bin
  local rc=0
  tmp_home="$(mktemp -d)"
  tmp_bin="${tmp_home}/bin"

  mkdir -p "${tmp_home}/.aliases"
  ln -s "${BASE_DIR}"/home_files/.aliases/*.sh "${tmp_home}/.aliases/"
  touch "${tmp_home}/.profile" "${tmp_home}/.extra"
  create_command_doc_path "${tmp_bin}"

  (
    export HOME="${tmp_home}"
    export HUSH=1
    export PATH="${tmp_bin}"
    shopt -s expand_aliases
    # shellcheck disable=SC1091
    source "${BASE_DIR}/home_files/.bash_aliases" >/dev/null
    list_dotfiles_functions
  ) || rc=$?

  rm -rf "${tmp_home}"
  return "${rc}"
}

render_readme() {
  local prelude
  local commands

  if ! prelude="$(read_readme_prelude)"; then
    echo "Could not find '${COMMANDS_HEADING}' in ${README_PATH}" >&2
    return 1
  fi

  commands="$(generate_command_list)"

  printf '%s\n\n' "${prelude}"
  printf '%s\n\n' "${COMMANDS_HEADING}"
  printf 'Run `list_dotfiles_functions` to get a list of available commands:\n\n'
  printf '```bash\n'
  printf '%s\n' "${commands}"
  printf '```\n'
}

write_generated_readme() {
  local output
  output="$(mktemp)"
  if ! render_readme | tr -cd '\11\12\15\40-\176' | tr -d '\r' | sed 's/(B\[m//g' > "${output}"; then
    rm -f "${output}"
    return 1
  fi
  mv "${output}" "${README_PATH}"
}

check_generated_readme() {
  local output
  output="$(mktemp)"
  if ! render_readme | tr -cd '\11\12\15\40-\176' | tr -d '\r' | sed 's/(B\[m//g' > "${output}"; then
    rm -f "${output}"
    return 1
  fi

  if ! cmp -s "${README_PATH}" "${output}"; then
    echo "README command documentation is out of date. Run ./generate_shortcuts_documentation.sh" >&2
    diff -u "${README_PATH}" "${output}" >&2 || true
    rm -f "${output}"
    return 1
  fi

  rm -f "${output}"
}

if [ "${CHECK_ONLY}" -eq 1 ]; then
  check_generated_readme
else
  echo "Compiling list of commands available. Please wait ..."
  write_generated_readme
fi
