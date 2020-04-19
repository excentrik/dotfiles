#!/usr/bin/env bash

set -o errexit
#----------------------------
# Setup gitconfig
#----------------------------

# if gitconfig exists and is a regular file and gitconfig_local does not exist,
# then copy gitconfig to gitconfig_local
if [ -f ~/.gitconfig ] && [ ! -f ~/.gitconfig_local ]; then
    cp ~/.gitconfig ~/.gitconfig_local
fi

# Set ssh to use in git
TEXT=$(cat <<-END
\n
export GIT_SSH=/usr/bin/ssh
END
)
if [ ! -f ~/.extra ]; then
    touch ~/.extra
fi
grep -q -F "$TEXT" ~/.extra || printf "$TEXT" >> ~/.extra

TEXT=$(cat <<-END
\n
[credential]
	helper = osxkeychain
END
)

# Use osxkeychain in OSX
case "$OSTYPE" in
  darwin*)  grep -q -F "$TEXT" ~/.gitconfig_local || printf "$TEXT" >> ~/.gitconfig_local;;

  *) ;;
esac


