#!/usr/bin/env bash

set -o errexit

if [[ -z "$DOTFILES_NO_INTERACTIVE" && {$EDITOR+x} == "VI" ]]; then
 vim -c "PluginInstall" +qall &>/dev/null
fi
