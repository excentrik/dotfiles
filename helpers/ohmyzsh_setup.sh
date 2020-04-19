#!/usr/bin/env bash

set -o errexit

#----------------------------
# Setup oh-my-zsh
#----------------------------

# Detect if zsh is present
if type zsh >/dev/null 2>/dev/null; then
   echo "Going to install oh-my-zsh. If it goes sucessfully, you need to exit the zsh shell to continue"
  # Actually install oh-my-zsh
  sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
  # TODO figure out how to detect if installation failed and how to exit from zsh
  exit $?
else
  echo "Zsh is not present in this system. Please install it before trying to install oh-my-zsh"
  exit 1
fi



