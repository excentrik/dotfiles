#!/usr/bin/env bash

set -o errexit

if [[ -z "${DOTFILES_NO_INTERACTIVE:-}" && "${EDITOR:-vi}" == vi* ]] && command -v vim >/dev/null 2>&1; then
  vim -c "PluginInstall" +qall &>/dev/null
fi
