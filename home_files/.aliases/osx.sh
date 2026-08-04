#!/usr/bin/env bash

# Set terminal titles in OSX
alias title='printf "\033]0;%s\007"'

# Recursively delete `.DS_Store` files under the current path
alias cleanup_ds="find . -type f -name '*.DS_Store' -ls -delete"

# Open man page as PDF
function manpdf() {
 man -t "${1}" | open -f -a /Applications/Preview.app/
}

# Attach to the default tmux session using iTerm2 native tmux integration.
alias txiterm='tmux -CC new -As main'

# Attach to a named tmux session using iTerm2 native tmux integration.
alias txa='tmux -CC attach -t'
