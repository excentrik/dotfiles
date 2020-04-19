#!/usr/bin/env bash

if hash man 2>/dev/null; then
  # Enable coloured manuals
  man() {
      if command -v vimmanpager >/dev/null 2>&1; then
          PAGER="vimmanpager" command man "$@"
      else
        env \
          LESS_TERMCAP_mb=$(printf "\e[1;31m") \
          LESS_TERMCAP_md=$(printf "\e[1;31m") \
          LESS_TERMCAP_me=$(printf "\e[0m") \
          LESS_TERMCAP_se=$(printf "\e[0m") \
          LESS_TERMCAP_so=$(printf "\e[1;44;33m") \
          LESS_TERMCAP_ue=$(printf "\e[0m") \
          LESS_TERMCAP_us=$(printf "\e[1;32m") \
          man "$@"
      fi
  }
fi

# Extra many types of compressed packages
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2)  tar -jxvf "$1"                        ;;
      *.tar.gz)   tar -zxvf "$1"                        ;;
      *.bz2)      bunzip2 "$1"                          ;;
      *.dmg)      hdiutil mount "$1"                    ;;
      *.gz)       gunzip "$1"                           ;;
      *.tar)      tar -xvf "$1"                         ;;
      *.tbz2)     tar -jxvf "$1"                        ;;
      *.tgz)      tar -zxvf "$1"                        ;;
      *.zip)      unzip "$1"                            ;;
      *.ZIP)      unzip "$1"                            ;;
      *.pax)      cat "$1" | pax -r                     ;;
      *.pax.Z)    uncompress "$1" --stdout | pax -r     ;;
      *.Z)        uncompress "$1"                       ;;
      *) echo "'$1' cannot be extracted/mounted via extract()" ;;
    esac
  else
     echo "'$1' is not a valid file to extract"
  fi
}


# Create a new directory and enter it
function mkd() {
    mkdir -p "$@" && cd "$_" || return;
}

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
function targz() {
    local tmpFile="${@%/}.tar";
    tar -cvf "${tmpFile}" --exclude=".DS_Store" "${@}" || return 1;

    size=$(
        stat -f"%z" "${tmpFile}" 2> /dev/null; # OS X `stat`
        stat -c"%s" "${tmpFile}" 2> /dev/null # GNU `stat`
    );

    local cmd="";
    if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
        # the .tar file is smaller than 50 MB and Zopfli is available; use it
        cmd="zopfli";
    else
        if hash pigz 2> /dev/null; then
            cmd="pigz";
        else
            cmd="gzip";
        fi;
    fi;

    echo "Compressing .tar using \`${cmd}\`…";
    "${cmd}" -v "${tmpFile}" || return 1;
    [ -f "${tmpFile}" ] && rm "${tmpFile}";
    echo "${tmpFile}.gz created successfully.";
}

# Determine size of a file or total size of a directory
function fs() {
    local arg
    if command du -b /dev/null > /dev/null 2>&1; then
        arg=-sbh;
    else
        arg=-sh;
    fi
    if [[ -n "$*" ]]; then
        command du ${arg} -- "$@";
    else
        command du ${arg} .[^.]* *;
    fi;
}


if hash git 2>/dev/null; then
# Use Git’s colored diff when available
  alias diff="git diff --no-index --color-words"
fi


# Fancy progress function from Landley's Aboriginal Linux. Usage: rm -rfv /foo | dot_progress
dot_progress() {
    local i='0'
    local line=''

    # shellcheck disable=SC2162
    while read line; do
        i="$((i+1))"
        if [ "${i}" = '25' ]; then
            printf '.'
            i='0'
        fi
    done
    printf '\n'
}

# Run $1 under session or attach if such session already exist. Example usage: run_under_tmux 'rtorrent' '/usr/local/rtorrent-git/bin/rtorrent';
run_under_tmux() {
    # $2 is optional path, if no specified, will use $1 from $PATH.
    # If you need to pass extra variables, use $2 for it as in example below..
    # More examples:
    #   mutt() { run_under_tmux 'mutt'; }
    #   irc() { run_under_tmux 'irssi' "TERM='screen' command irssi"; }
    command -v tmux >/dev/null 2>&1 || return 1

    if [ -z "$1" ]; then return 1; fi
    local name="$1"
    local execute="command ${name}"
    if [ -n "$2" ]; then
        execute="$2"
    fi

    if tmux has-session -t "${name}" 2>/dev/null; then
        tmux attach -d -t "${name}"
    else
        tmux new-session -s "${name}" "${execute}" \; set-option status \; set set-titles-string "${name} (tmux@localhost})"
    fi
}

# Reload the shel
reload() {
    exec "${SHELL}" "$@"
}

# Uber useful when you need to translate a weird path into single-argument string.
escape() {
    local escape_string_input
    echo -n "String to escape: "
    read escape_string_input
    printf '%q\n' "$escape_string_input"
}

# Confirmation wrapper. Usage: confirm rm -rf /tmp/folder
confirm() {
    if [ -z $BASH ]; then
      read -s -t 3 -q "_run?Are you sure you want to run '$*' [yN]? "
    else
      read -s -t 3 -n 1 -p "Are you sure you want to run '$*' [yN]? " _run
    fi
    echo ""
    case ${_run} in
        y|Y )
        command "${@}"
        ;;
        * )
        ;;
    esac
}


# Checks if shell is interactive
shell_is_interactive() {
    [[ $- == *i* ]] && echo 1 || echo 0
    #shopt -q login_shell && echo 'Login shell' || echo 'Not login shell'
}

_base_ssh_options() {
  DEFAULT_OPTIONS="hostbased,publickey,keyboard-interactive,password"
  local arg1=$1

  if [[ $arg1 != "" ]];
  then
      OPTIONS=$(ssh -G "$1" | grep preferredauthentications | cut -d ' ' -f2)
      if [ -z "$OPTIONS" ]; then
        OPTIONS=$DEFAULT_OPTIONS
      fi
  else
      OPTIONS=$DEFAULT_OPTIONS
  fi

  echo -e "-o PreferredAuthentications=${OPTIONS}"
}

# Open a tmux terminal inside an ssh session. Usage: tsh <hostname> {session_name}
function tsh() {
    local host=$1
    if [[ -z "$host" ]]; then
        echo "Need to provide the hostname to connect to. Usage: tsh <hostname>"
        return 1
    fi
    session_name=$2
    if [[ -z "$session_name" ]]; then
        session_name=${USER}
        echo "No session name provided. Defaulting to \"$session_name\""
    fi
    OPTIONS=""
    if [[ -n "$TERM_PROGRAM" && "$TERM_PROGRAM" = "iTerm.app" ]]; then
       OPTIONS="-CC"
    fi
    # shellcheck disable=SC2046
    ssh $(_base_ssh_options "${host}") "${host}" "${@:3}" -t "tmux $OPTIONS new-session -A -s $session_name \; set -g mouse on \;"
}


# Function to show all open ssh connections/tunnels
function list_open_tunnels() {
  if [ -x "$(command -v ss)" ]; then
    ss -tulpn | grep ssh
    return $?
  elif [ -x "$(command -v netstat)" ]; then
    netstat -tulpn 2>/dev/null | grep ssh
    return $?
  fi
  echo "In order to run this command you need either netstat or ss installed locally"
}
