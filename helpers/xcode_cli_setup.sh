#!/usr/bin/env bash

set -euo pipefail

CLT_DIR="/Library/Developer/CommandLineTools"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Xcode Command Line Tools setup only applies to macOS. Skipping."
  exit 0
fi

clt_is_selected() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ "${developer_dir}" == "${CLT_DIR}" ]]
}

clt_is_installed() {
  [[ -d "${CLT_DIR}" ]] && [[ -x "${CLT_DIR}/usr/bin/git" ]]
}

configure_clt() {
  if clt_is_selected; then
    echo "Xcode Command Line Tools are already selected."
    return
  fi

  if [[ -n "${DOTFILES_NO_INTERACTIVE:-}" ]] || [ ! -t 0 ]; then
    echo "Xcode Command Line Tools are installed but not selected. Skipping xcode-select because this is non-interactive."
    echo "Run manually: sudo xcode-select --switch ${CLT_DIR}"
    return
  fi

  echo "Selecting Xcode Command Line Tools at ${CLT_DIR}."
  sudo xcode-select --switch "${CLT_DIR}"
}

if clt_is_installed; then
  configure_clt
  exit 0
fi

if [[ -n "${DOTFILES_NO_INTERACTIVE:-}" ]] || [ ! -t 0 ]; then
  echo "Xcode Command Line Tools are not installed. Skipping installer because this is non-interactive."
  echo "Run manually: xcode-select --install"
  exit 0
fi

echo "Installing Xcode Command Line Tools only; full Xcode is not installed by this role."
xcode-select --install || {
  status=$?
  if [ "${status}" -eq 1 ]; then
    echo "Xcode Command Line Tools installer may already be running."
  else
    exit "${status}"
  fi
}

echo "Complete the Apple installer, then press Enter to continue."
read -r

if ! clt_is_installed; then
  echo "Xcode Command Line Tools are still not installed. Re-run this role after completing the installer." >&2
  exit 1
fi

configure_clt
