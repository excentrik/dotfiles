#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
managed_tpm="${BASE_DIR}/tpm"
tpm_dir="$HOME/.tmux/plugins/tpm"
resurrect_storage_dir="$HOME/.tmux/resurrect"

link_managed_tpm() {
  if [ ! -f "$managed_tpm/tpm" ] || [ ! -x "$managed_tpm/bin/install_plugins" ]; then
    echo "Managed TPM checkout is unavailable at $managed_tpm. Run: git submodule update --init --recursive" >&2
    return 1
  fi

  ln -s "$managed_tpm" "$tpm_dir"
}

ensure_tpm_available() {
  mkdir -p "$(dirname "$tpm_dir")"

  if [ -L "$tpm_dir" ]; then
    if [ -f "$tpm_dir/tpm" ] && [ -x "$tpm_dir/bin/install_plugins" ]; then
      return 0
    fi

    if [ ! -e "$tpm_dir" ]; then
      echo "Repairing broken TPM symlink at $tpm_dir." >&2
      rm "$tpm_dir"
      link_managed_tpm
      return
    fi

    echo "Existing TPM symlink at $tpm_dir does not point to a usable checkout; leaving it in place." >&2
    return 0
  fi

  if [ -d "$tpm_dir" ]; then
    if [ -f "$tpm_dir/tpm" ] && [ -x "$tpm_dir/bin/install_plugins" ]; then
      echo "Existing TPM checkout found at $tpm_dir; leaving it in place." >&2
      return 0
    fi

    echo "Existing $tpm_dir is not a usable TPM checkout; skipping managed TPM link." >&2
    return 0
  fi

  if [ -e "$tpm_dir" ]; then
    echo "Existing $tpm_dir is not a directory or symlink; skipping managed TPM link." >&2
    return 0
  fi

  link_managed_tpm
}

ensure_tpm_available
mkdir -p "$resurrect_storage_dir"
chmod 700 "$resurrect_storage_dir"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed; skipping tmux plugin setup." >&2
  exit 0
fi

tmux_version="$(tmux -V | awk '{print $2}')"
tmux_major="${tmux_version%%.*}"
tmux_minor="${tmux_version#*.}"
tmux_minor="${tmux_minor%%[^0-9]*}"

if [ "${tmux_major:-0}" -lt 3 ] || { [ "${tmux_major:-0}" -eq 3 ] && [ "${tmux_minor:-0}" -lt 2 ]; }; then
  echo "tmux ${tmux_version} detected. These dotfiles expect tmux >= 3.2; tmux >= 3.3 is recommended for passthrough support." >&2
fi

tpm_install="$tpm_dir/bin/install_plugins"
resurrect_dir="$HOME/.tmux/plugins/tmux-resurrect"
continuum_dir="$HOME/.tmux/plugins/tmux-continuum"
tmux_plugin_manager_path="$HOME/.tmux/plugins"

if [ ! -x "$tpm_install" ]; then
  echo "TPM install script not found at $tpm_install; skipping tmux plugin install." >&2
  exit 0
fi

if [ -d "$resurrect_dir" ] && [ -d "$continuum_dir" ]; then
  exit 0
fi

tmux start-server \; set-environment -g TMUX_PLUGIN_MANAGER_PATH "$tmux_plugin_manager_path"
"$tpm_install"
