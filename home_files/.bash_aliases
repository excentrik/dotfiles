#!/usr/bin/env bash
#-------------------
# Load all aliases files in .aliases directory
#
# To add personal/custom aliases, just add them to a file inside .aliases directory
#-------------------
if [ -d "$HOME/.aliases" ]; then
  for file in "$HOME/.aliases"/*.sh; do
      # shellcheck disable=SC1090
      [ -r "$file" ] && [ -f "$file" ] && source "$file" && ALIASES_FILES+=" ${file}";
  done;
  [[ -z ${HUSH} && ! -f ${HOME}/.hushlogin ]] && echo "Sourced aliases files ${ALIASES_FILES}"
  unset ALIASES_FILES
  unset file;
fi


