#!/usr/bin/env bash

set -o errexit
#----------------------------
# Setup gitconfig
#----------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGED_GITCONFIG="${BASE_DIR}/home_files/git/gitconfig"
GITCONFIG="${HOME}/.gitconfig"
GITCONFIG_LOCAL="${HOME}/.gitconfig_local"
EXTRA="${HOME}/.extra"

is_managed_gitconfig_link() {
    [ -L "${GITCONFIG}" ] || return 1

    local target
    target="$(readlink "${GITCONFIG}")"
    case "${target}" in
        /*) ;;
        *) target="$(cd "$(dirname "${GITCONFIG}")" && cd "$(dirname "${target}")" && pwd)/$(basename "${target}")" ;;
    esac

    [ "${target}" = "${MANAGED_GITCONFIG}" ]
}

append_once() {
    local file="$1"
    local text="$2"

    touch "${file}"
    grep -q -F "${text}" "${file}" || printf "%s" "${text}" >> "${file}"
}

append_gitconfig_value_once() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local existing

    touch "${file}"
    existing="$(git config --file "${file}" --get-all "${section}.${key}" 2>/dev/null || true)"
    if printf '%s\n' "${existing}" | grep -Fx -- "${value}" >/dev/null; then
        return 0
    fi

    printf "\n[%s]\n\t%s = %s\n" "${section}" "${key}" "${value}" >> "${file}"
}

# Preserve an existing user gitconfig as the local include before Dotbot links
# the managed gitconfig. Do not copy the managed symlink back into local config
# on repeat installs because that duplicates the committed config.
if [ ! -e "${GITCONFIG_LOCAL}" ]; then
    if [ -e "${GITCONFIG}" ] && ! is_managed_gitconfig_link; then
        cp -L "${GITCONFIG}" "${GITCONFIG_LOCAL}"
    else
        touch "${GITCONFIG_LOCAL}"
    fi
fi

# Set ssh to use in git
TEXT=$(cat <<-END
\n
export GIT_SSH=/usr/bin/ssh
END
)
append_once "${EXTRA}" "${TEXT}"

# Use osxkeychain in OSX
case "$OSTYPE" in
  darwin*)  append_gitconfig_value_once "${GITCONFIG_LOCAL}" "credential" "helper" "osxkeychain";;

  *) ;;
esac

