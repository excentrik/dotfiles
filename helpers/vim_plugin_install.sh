#!/usr/bin/env bash

set -o errexit

if [[ -z "${DOTFILES_NO_INTERACTIVE:-}" && "${EDITOR:-vi}" == vi* ]] && command -v vim >/dev/null 2>&1; then
  if ! grep -Eq '^[[:space:]]*call vundle#begin\(' "${HOME}/.vimrc" 2>/dev/null; then
    echo "Vundle is not enabled in ~/.vimrc. Skipping plugin installation."
    exit 0
  fi

  vim -c "PluginInstall" +qall &>/dev/null
fi
