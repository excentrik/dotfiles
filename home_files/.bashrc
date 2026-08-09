#!/usr/bin/env bash

# shellcheck source=.
source "$HOME/.exports"
source "$HOME/.profile"

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Raise the soft open-file-descriptor limit, capped at the hard limit
__nofile_hard=$(ulimit -Hn)
if [ "$__nofile_hard" = "unlimited" ] || { [ "$__nofile_hard" -ge 65536 ] 2>/dev/null; }; then
    ulimit -Sn 65536
elif [ -n "$__nofile_hard" ]; then
    ulimit -Sn "$__nofile_hard"
fi
unset __nofile_hard

# Case-insensitive globbing (used in pathname expansion)
shopt -s nocaseglob;

# Append to the Bash history file, rather than overwriting it
shopt -s histappend;

# Autocorrect typos in path names when using `cd`
shopt -s cdspell;

# Enable some Bash 4 features when possible:
# * `autocd`, e.g. `**/qux` will enter `./foo/bar/baz/qux`
# * Recursive globbing, e.g. `echo **/*.txt`
for option in autocd globstar; do
    shopt -s "$option" 2> /dev/null;
done;

# Add tab completion for many Bash commands
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  fi
  if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring wildcards
[ -e "$HOME/.ssh/config" ] && type complete >/dev/null 2>/dev/null && complete -o "default" -o "nospace" -W "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2- | tr ' ' '\n')" scp sftp ssh tsh;

# Load bash dotfiles
# * ~/.extra can be used for other settings you don't want to commit.
load_aliases
for file in ~/.bash_prompt ~/.startup ~/.extra; do
       [ -r "$file" ] && [ -f "$file" ] && source "$file";
       BASH_FILES+=" ${file}";
done
[[ -z ${HUSH} && ! -f ${HOME}/.hushlogin ]] && echo "Sourced files ${BASH_FILES}"
unset BASH_FILES;
unset file;

test -e "${HOME}/.iterm2_shell_integration.bash" && export ITERM2_SQUELCH_MARK=1 && source "${HOME}/.iterm2_shell_integration.bash"

if [ -d "${HOME}/.volta" ]; then
  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"
fi

# Keep shared PATH composition in ~/.path as the final PATH mutator.
source "$HOME/.path"

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

. "$HOME/.atuin/bin/env"

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash --disable-up-arrow)"
fi
