#!/usr/bin/env bash
#-------------------
# Standard Aliases
#-------------------

# Tailoring 'less'
export PAGER=less
export LESSCHARSET='latin1'
export LESSOPEN='|/usr/bin/lesspipe.sh %s 2>&-'
                # Use this if lesspipe.sh exists.
export LESS='-i -N -w  -z-4 -g -e -M -F -R -P%t?f%f \
:stdin .?pb%pb\%:?lbLine %lb:?bbByte %bb:-...'
# More is less
alias more='less'

# Don’t clear the screen after quitting a manual page.
export MANPAGER='less -X';

# mkdir alias to prevent accidentally clobbering files.
alias mkdir='mkdir -p'

# Prints location and type of command
alias which='type -a'

if [ ! -x "$(command -v ncdu)" ]; then
  # Makes a more readable output for disk usage
  alias du='du -kh'
else
  # ncdu offers an interactive interface and allows for quick scans/navigation
  function du() {
    ncdu -e --color dark -x --exclude .git "${@//-*/}"
  }
fi

# Shows the file system free space (excluding certain filesystems and showing human readable values)
if ! command df -x tmpfs > /dev/null 2>&1; then
    # OS X `ls`
    alias df='command df -kh -T notmpfs,nosquashfs,nodevtmpfs,nullfs'
else
    # GNU `ls`
    alias df='command df -khT -x tmpfs -x squashfs -x devtmpfs'
fi



# Enable aliases to be sudo’ed
alias sudo='sudo '

# Always enable colored `grep` output
alias grep='grep --color=auto'
# Always enable colored `fgrep` output
alias fgrep='fgrep --color=auto'
# Always enable colored `egrep` output
alias egrep='egrep --color=auto'

#-------------------------------------------------------------
# The 'ls' family (this assumes you use a recent GNU ls).
#-------------------------------------------------------------
# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then # GNU `ls`
    colorflag="--color"
    export LS_COLORS='no=00:fi=00:di=01;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'
else # OS X `ls`
    # shellcheck disable=SC2034
    colorflag="-G"
    export LSCOLORS='BxBxhxDxfxhxhxhxhxcxcx'
fi

# Always use color output for `ls` and human-readable sizes by default on 'ls'
alias ls='command ls -pFh ${colorflag}'
export CLICOLOR=1

if ls --group-directories-first > /dev/null 2>&1; then # GNU `ls`
    # Alias to use GNU ls and print directories first, with alphanumeric sorting
    alias ll="ls -lv --group-directories-first"
else # OS X `ls`
    if type gls  > /dev/null 2>&1; then # GNU `ls` on OSX
        # Alias to use GNU ls and print directories first, with color alphanumeric sorting
        alias ll="command gls -pFh -lv --group-directories-first --color"
    else # OS X `ls`
        # Alias to use BSD ls
        alias ll="ls -lv"
    fi
fi

# List all files colorized in long format, including dot files
alias la='command ls -laF ${colorflag}'
#  Nice alternative to 'recursive ls' ...
#alias tree='tree -Csuh'
unalias l > /dev/null 2>&1 || true

if [ -x "$(command -v bat)" ]; then
  # Replace cat with bat which has highlighting, paging, line numbers and git integration
  alias cat='bat'
fi

if [ -x "$(command -v prettyping)" ]; then
  # prettyping gives ping a really nice output and makes the command line a bit more welcoming
  alias ping='prettyping --nolegend'
fi

# Kill all process that match a pattern (`kill_processes ssh` kills all processes that contain ssh in their CMD string
kill_processes() {
    pattern="${*}"
    if [ ! "$(pgrep -c -f -- "${pattern}")" -eq 0 ]; then
        pkill -f -- "$pattern"
        sleep 0.1
    fi
}
