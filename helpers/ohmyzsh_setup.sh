#!/usr/bin/env bash

set -euo pipefail

#----------------------------
# Setup oh-my-zsh
#----------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OH_MY_ZSH_SOURCE="${BASE_DIR}/oh-my-zsh"
OH_MY_ZSH_TARGET="${HOME}/.oh-my-zsh"
TMP_OH_MY_ZSH_TARGET=""

copy_oh_my_zsh() {
  local item
  local tmp_target

  tmp_target="$(mktemp -d "${OH_MY_ZSH_TARGET}.tmp.XXXXXX")"
  TMP_OH_MY_ZSH_TARGET="${tmp_target}"
  trap 'rm -rf "${TMP_OH_MY_ZSH_TARGET}"' EXIT

  shopt -s dotglob nullglob
  for item in "${OH_MY_ZSH_SOURCE}"/*; do
    [ "$(basename "${item}")" = ".git" ] && continue
    cp -R "${item}" "${tmp_target}/"
  done
  shopt -u dotglob nullglob

  mv "${tmp_target}" "${OH_MY_ZSH_TARGET}"
  TMP_OH_MY_ZSH_TARGET=""
  trap - EXIT
}

if ! command -v zsh >/dev/null 2>&1; then
  echo "Zsh is not present in this system. Please install it before trying to install oh-my-zsh." >&2
  exit 1
fi

if [ ! -f "${OH_MY_ZSH_SOURCE}/oh-my-zsh.sh" ]; then
  echo "Oh My Zsh submodule is missing; initializing recorded submodule commit."
  if ! command -v git >/dev/null 2>&1; then
    echo "Git is required to initialize the oh-my-zsh submodule." >&2
    exit 1
  fi
  git -C "${BASE_DIR}" submodule update --init --recursive oh-my-zsh
fi

if [ ! -f "${OH_MY_ZSH_SOURCE}/oh-my-zsh.sh" ]; then
  echo "Oh My Zsh submodule is not available at ${OH_MY_ZSH_SOURCE}." >&2
  exit 1
fi

if [ -L "${OH_MY_ZSH_TARGET}" ]; then
  echo "Refusing to use symlinked ${OH_MY_ZSH_TARGET}; move it aside before installing the ohmyzsh role." >&2
  exit 1
fi

if [ -e "${OH_MY_ZSH_TARGET}" ]; then
  if [ -f "${OH_MY_ZSH_TARGET}/oh-my-zsh.sh" ]; then
    echo "Existing Oh My Zsh checkout found at ${OH_MY_ZSH_TARGET}; leaving it in place."
    exit 0
  fi

  # Move an unrelated ${OH_MY_ZSH_TARGET} aside so the role stays idempotent
  # instead of failing on every re-run. The original contents are preserved at
  # a timestamped sibling path so users can recover anything custom.
  BACKUP_TARGET="${OH_MY_ZSH_TARGET}.backup.$(date +%Y%m%d%H%M%S)"
  echo "Existing ${OH_MY_ZSH_TARGET} is not an Oh My Zsh checkout; moving it to ${BACKUP_TARGET}."
  mv "${OH_MY_ZSH_TARGET}" "${BACKUP_TARGET}"
fi

copy_oh_my_zsh
echo "Copied ${OH_MY_ZSH_TARGET} from the repo-managed Oh My Zsh submodule."
