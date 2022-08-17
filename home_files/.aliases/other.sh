#!/usr/bin/env bash
#-------------------
# Other aliases
#-------------------

# Stopwatch to count execution time for a command. Usage example: timer ls -la
timer() {
    cleanup() {
        rc=$?;
        if [ "${rc}" != "0" ]; then
            echo 'Interrupted'; exit ${rc}
        fi
    }
    trap cleanup EXIT
    echo 'Timer started.'
    startTime=$(date)
    s=$(date +%s)
    $@
    rc=$?
    if [ "${rc}" == "0" ]; then
        echo "took $[$(date +%s)-$s] seconds" >&2
        echo "Start time: ${startTime}"
        echo "End time: "$(date)""
    fi
    return ${rc}
}

if hash dig 2>/dev/null; then
  # Get external IP address
  alias external_ip="dig +short myip.opendns.com @resolver1.opendns.com"
fi

# Pretty print json. Usage: echo '{"foo": "lorem", "bar": "ipsum"}' | prettyjson
alias prettyjson='python -m json.tool'


_list_dotfiles_functions_options()
{
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"prev
    opts="--help -h --full -f"

    if [[ ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi
}

_contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# List all function available in a shell
list_dotfiles_functions() {
  usage="$(basename "$0") [-h] [-f|--full] -- program to display available aliases and functions

  where:
      -h           show this help text
      -f|--full    expand aliases
      -s|--system  show also aliases of system commands (e.g. ls)"

  if [ $# -ge 2 ]; then
     echo "$usage"
     return
  fi

  local FULL_DESCRIPTION=false
  local SHOW_SYSTEM_COMMANDS=false
  if [ $# -eq 1 ]; then
    case $1 in
      -f|--full)
      FULL_DESCRIPTION=true
      ;;
      -s|--system)
      SHOW_SYSTEM_COMMANDS=true
      ;;

      *)    # unknown option or help
      echo "$usage"
      return
      ;;
    esac
  fi

  local OUTPUT=""
  local COMMENT
  OUTPUT="$(while read -r CMD; do
      COMMENT=$(find -L ${HOME}/.aliases/* -exec readlink -f {} \; | xargs grep -h -B 1 "${CMD}() {" | grep --colour='never' "# ")
      # remove leading whitespace characters
      COMMENT="${COMMENT#"${COMMENT%%[![:space:]]*}"}"
      [[ -z $COMMENT ]] && continue
      printf "%-65s %s\n" "${CMD}" "${COMMENT}"
  done <<< "$(declare -f | egrep "^[a-zA-Z].*" | cut -d' ' -f1 | grep -v "^declare")")"

  OUTPUT+=$'\n'

  local EXCLUDED_ALIASES="($(type get_ssh_hosts >/dev/null 2>/dev/null && get_ssh_hosts | cut -d'=' -f1))"

  local ALIAS
  OUTPUT+="$(while read -r CMD; do
    if [ ${SHOW_SYSTEM_COMMANDS} = false ] ; then
      if [[ -n $(type -a $CMD 2>/dev/null | grep -v alias) ]]; then
        continue
      fi
    fi
    _contains_element "${CMD}" "${EXCLUDED_ALIASES[@]}" && continue
    ALIAS=$(alias "${CMD}" | sed -e "s/^alias //")

    COMMENT=$(find -L ${HOME}/.aliases/* ${HOME}/.profile ${HOME}/.extra -exec readlink -f {} \; | xargs grep -h -B 1 "alias ${CMD}=" | grep --colour='never' "# " | head -1 | xargs)

    # remove leading whitespace characters
    COMMENT="${COMMENT#"${COMMENT%%[![:space:]]*}"}"
    [[ -z $COMMENT ]] && continue
    if [ ${FULL_DESCRIPTION} = true ] ; then
      printf "%-65s %s\n" "${ALIAS}" "${COMMENT}"
    else
      printf "%-65s %s\n" "${CMD}" "${COMMENT}"
    fi
  done <<< "$(alias | cut -d"=" -f1 | cut -d' ' -f2)")"

  echo "${OUTPUT}" | sort

} && type complete >/dev/null 2>/dev/null && complete -F _list_dotfiles_functions_options list_dotfiles_functions


# Update and install latest dotfiles version
update_dotfiles() {
  local DOTFILES_PATH
  DOTFILES_PATH=$(readlink ~/.profile | sed 's/home_files\/.profile//')
  cd "${DOTFILES_PATH}" || return
  git stash
  git pull
  git stash pop
  ./install
  cd - || return
}
