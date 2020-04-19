# Function that loads all bash aliases. Can be used in non-interactive mode
function load_aliases() {
    if [ -d "$HOME/.aliases" ]; then
      for file in "$HOME/.aliases"/*.sh; do
          [ -r "$file" ] && [ -f "$file" ] && source "$file" && ALIASES_FILES+=" ${file}";
      done;
      [[ -z ${HUSH} && ! -f ${HOME}/.hushlogin ]] && echo "Sourced aliases files ${ALIASES_FILES}"
      unset ALIASES_FILES
      unset file;
    fi
}
