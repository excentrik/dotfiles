# Function that loads aliases from ~/.aliases. Can be used in non-interactive mode.
function load_aliases() {
    if [ -d "$HOME/.aliases" ]; then
      for file in "$HOME/.aliases"/*.sh; do
          if [ -r "$file" ] && [ -f "$file" ]; then
            # Use sh emulation when running under zsh so bash-oriented alias files
            # still load without zsh-specific builtin/option differences.
            if [ -n "${ZSH_VERSION:-}" ]; then
              emulate sh -c ". \"$file\"" && ALIASES_FILES+=" ${file}";
            else
              # shellcheck disable=SC1090
              source "$file" && ALIASES_FILES+=" ${file}";
            fi
          fi
      done;
      [[ -z ${HUSH} && ! -f ${HOME}/.hushlogin ]] && echo "Sourced aliases files ${ALIASES_FILES}"
      unset ALIASES_FILES
      unset file;
    fi
}
