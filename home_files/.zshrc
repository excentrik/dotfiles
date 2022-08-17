#!/usr/bin/env zsh

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

#------------------------------
# Zsh stuff
#------------------------------

# extended globbing, awesome!
setopt extendedGlob

# Turn on command substitution in the prompt (and parameter expansion and arithmetic expansion).
setopt promptsubst

# Disable auto-correct
unsetopt correct

# Ignore lines prefixed with '#'.
setopt interactivecomments

# Ignore duplicate in history.
setopt hist_ignore_dups

# Prevent record in history entry if preceding them with at least one space
setopt hist_ignore_space

# Nobody need flow control anymore. Troublesome feature.
setopt noflowcontrol

# Many programs change the terminal state, and often do not restore terminal settings on exiting abnormally.
# To avoid the need to manually reset the terminal, use the following
ttyctl -f

#------------------------------
# Completion stuff
#------------------------------
autoload -Uz compinit bashcompinit
typeset -i updated_at=$(date +'%j' -r ~/.zcompdump 2>/dev/null || stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)
if [ "$(date +'%j')" != "${updated_at}" ]; then
  compinit -i
else
  compinit -C -i
fi
bashcompinit

zmodload -i zsh/complist


zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' menu select=2
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
zstyle ':completion::complete:*' use-cache 1

#- buggy
zstyle ':completion:*:descriptions' format '%U%B%d%b%u'
zstyle ':completion:*:warnings' format '%BSorry, no matches for: %d%b'
#-/buggy

zstyle ':completion:*:pacman:*' force-list always
zstyle ':completion:*:*:pacman:*' menu yes select

zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"

zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:kill:*'   force-list always

zstyle ':completion:*:*:killall:*' menu yes select
zstyle ':completion:*:killall:*'   force-list always

# autocompletion of command line switches for aliases
setopt COMPLETE_ALIASES

# Include new executables in path
zstyle ':completion:*' rehash true

#------------------------------
# Keybindings
#------------------------------

# Helper method to figure out the actual keyboard keys
#key=(
#   BackSpace  "${terminfo[kbs]}"
#    Home       "${terminfo[khome]}"
#    End        "${terminfo[kend]}"
#    Insert     "${terminfo[kich1]}"
#    Delete     "${terminfo[kdch1]}"
#    Up         "${terminfo[kcuu1]}"
#    Down       "${terminfo[kcud1]}"
#    Left       "${terminfo[kcub1]}"
#    Right      "${terminfo[kcuf1]}"
#    PageUp     "${terminfo[kpp]}"
#    PageDown   "${terminfo[knp]}"
#)

# Enable history search
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search down-line-or-beginning-search

# Use vi keybindings
#bindkey -v
# typeset -g -A key
# bindkey '^?' backward-delete-char
# bindkey '^[[5~' up-line-or-history

# bindkey '^[3;5~' delete-char
# bindkey '^[[6~' down-line-or-history
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search
#bindkey '^[[D' backward-char
#bindkey '^[[C' forward-char
# bindkey "^R" history-incremental-pattern-search-backward
# bindkey "^S" history-incremental-pattern-search-forward
bindkey "^X^_" redo

#bindkey "^U" backward-kill-line # command + backspace
bindkey "^X\\x7f" backward-kill-line
bindkey "^[[H" beginning-of-line # Home (up left arrow)
bindkey "^[[F" end-of-line # End (down right arrow)
bindkey "^[^[[D" beginning-of-line # command + left arrow
bindkey "^[^[[C" end-of-line # command + right arrow
#bindkey "^[f" forward-word # alt + right arrow
#bindkey "^[b" backward-word # alt + left arrow
bindkey "^[^?" kill-word # command + backspace
#bindkey "^[D" backward-kill-word # command + delete


# start typing + [Up-Arrow] - fuzzy find history forward
if [[ "${terminfo[kcuu1]}" != "" ]]; then
  autoload -U up-line-or-beginning-search
  zle -N up-line-or-beginning-search
  bindkey "${terminfo[kcuu1]}" up-line-or-beginning-search
fi
# start typing + [Down-Arrow] - fuzzy find history backward
if [[ "${terminfo[kcud1]}" != "" ]]; then
  autoload -U down-line-or-beginning-search
  zle -N down-line-or-beginning-search
  bindkey "${terminfo[kcud1]}" down-line-or-beginning-search
fi

bindkey ' ' magic-space                               # [Space] - do history expansion

bindkey '^?' backward-delete-char                     # [Backspace] - delete backward
if [[ "${terminfo[kdch1]}" != "" ]]; then
  bindkey "${terminfo[kdch1]}" delete-char            # [Delete] - delete forward
else
  bindkey "^[[3~" delete-char
  bindkey "^[3;5~" delete-char
  bindkey "\e[3~" delete-char
fi

if [[ "${terminfo[khome]}" != "" ]]; then
  bindkey "${terminfo[khome]}" beginning-of-line      # [Home] - Go to beginning of line
fi
if [[ "${terminfo[kend]}" != "" ]]; then
  bindkey "${terminfo[kend]}"  end-of-line            # [End] - Go to end of line
fi

# case $TERM in
#     rxvt*|xterm*)
#         bindkey "^[[7~" beginning-of-line #Home key
#         bindkey "^[[8~" end-of-line #End key
#         bindkey "^[[A" history-beginning-search-backward #Up Arrow
#         bindkey "^[[B" history-beginning-search-forward #Down Arrow
#     ;;
#
#     linux)
#         bindkey "^[[1~" beginning-of-line #Home key
#         bindkey "^[[4~" end-of-line #End key
#         bindkey "^[[3~" delete-char #Del key
#         bindkey "^[[A" history-beginning-search-backward
#         bindkey "^[[B" history-beginning-search-forward
#     ;;
#
#     screen|screen-*)
#         bindkey "^[[1~" beginning-of-line #Home key
#         bindkey "^[[4~" end-of-line #End key
#         bindkey "^[[3~" delete-char #Del key
#         bindkey "^[[A" history-beginning-search-backward #Up Arrow
#         bindkey "^[[B" history-beginning-search-forward #Down Arrow
#         bindkey "^[Oc" forward-word # control + right arrow
#         bindkey "^[OC" forward-word # control + right arrow
#         bindkey "^[Od" backward-word # control + left arrow
#         bindkey "^[OD" backward-word # control + left arrow
#         bindkey "^H" backward-kill-word # control + backspace
#         bindkey "^[[3^" kill-word # control + delete
#     ;;
# esac


#[[ -n "$key[Up]"   ]] && bindkey -- "$key[Up]"   up-line-or-beginning-search
#[[ -n "$key[Down]" ]] && bindkey -- "$key[Down]" down-line-or-beginning-search

#------------------------------
# Zsh help
#------------------------------
autoload -Uz run-help
autoload -Uz run-help-git
autoload -Uz run-help-sudo
if [[ $(alias run-help > /dev/null) ]]; then
  unalias run-help
fi
alias help=run-help


# Load the shell dotfiles, and then some:
# * ~/.extra can be used for other settings you don't want to commit.
load_aliases
for file in ~/.zsh_prompt ~/.startup ~/.extra; do
       [ -r "$file" ] && [ -f "$file" ] && source "$file";
       ZSH_FILES+=" ${file}";
done;
test -e "${HOME}/.iterm2_shell_integration.zsh" && export ITERM2_SQUELCH_MARK=1 && source "${HOME}/.iterm2_shell_integration.zsh"
[[ -z ${HUSH} && ! -f ${HOME}/.hushlogin ]] && echo "Sourced files ${ZSH_FILES}"
unset ZSH_FILES;
unset file;

if [ -d "${HOME}/.volta" ]; then
  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"
fi
# Remove any duplicates from the path. It keeps the first element it finds
PATH=$(echo ${PATH} | /usr/bin/awk -v RS=: -v ORS=: '!($0 in a) {a[$0]; print}')
PATH="${PATH%:}"    # remove trailing colon
export PATH
