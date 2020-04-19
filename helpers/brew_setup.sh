#!/usr/bin/env bash

set -o errexit

#if [ ! -x "$(command -v brew)" ]; then
#  echo "Brew not installed. Skipping setup"
#  exit
#fi

# Make sure we’re using the latest Homebrew.
while true; do
    read -r -p "Do you want to update homebrew? [y/N]?" yn
    case $yn in
        [Yy]* ) brew update; break;;
        [Nn]* ) break;;
        '' ) break;;
        * ) ;;
    esac
done

# Upgrade any already-installed formulae.
UPDATES=$(brew upgrade --dry-run)
if [[ -n $UPDATES ]]; then
  while true; do
      echo "Running brew upgrade for the following formulae:"
      echo "${UPDATES}"
      read -r -p "Do you wish to continue [y/N]?" yn
      case $yn in
          [Yy]* ) brew upgrade; break;;
          [Nn]* ) break;;
          '' ) break;;
          * ) exit;;
      esac
  done
fi

# Remove outdated formulae
UPDATES=$(brew cleanup -n)
if [[ -n $UPDATES ]]; then
  while true; do
      echo "Running brew cleanup for the following formulae:"
      echo "${UPDATES}"
      read -r -p "Do you wish to continue [y/N]?" yn
      case $yn in
          [Yy]* ) brew cleanup; break;;
          [Nn]* ) break;;
          '' ) break;;
          * ) exit;;
      esac
  done
fi
