#!/usr/bin/env bash

set -o errexit

if [[ -n "${DOTFILES_NO_INTERACTIVE:-}" ]]; then
  echo "DOTFILES_NO_INTERACTIVE is set; skipping Homebrew update, upgrade, and cleanup."
  exit 0
fi

if [ ! -t 0 ]; then
  echo "No interactive input available; skipping Homebrew update, upgrade, and cleanup."
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Brew not installed. Skipping setup."
  exit 0
fi

# On macOS, Homebrew requires the Xcode Command Line Tools. The xcode_cli role
# is intentionally ordered before brew in meta/hosts/osx.yaml so a normal
# `./install` provisions CLT first. Warn (but do not fail) when this helper is
# invoked in isolation (e.g. `./install-role brew`) on a host where CLT are
# missing, because most brew operations will then fail with cryptic linker
# errors deeper in the run.
case "$OSTYPE" in
  darwin*)
    if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
      echo "warning: Xcode Command Line Tools not found (xcode-select -p failed)." >&2
      echo "         Run the xcode_cli role first (or 'xcode-select --install') before using brew." >&2
    fi
    ;;
esac

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
# HOMEBREW_NO_AUTO_UPDATE prevents brew from silently auto-updating during the dry-run check.
while true; do
    read -r -p "Do you want to check for and upgrade packages? [y/N]?" yn
    case $yn in
        [Yy]* )
            UPDATES=$(HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --dry-run)
            if [[ -n $UPDATES ]]; then
                echo "Running brew upgrade for the following formulae:"
                echo "${UPDATES}"
                read -r -p "Do you wish to continue [y/N]?" yn2
                case $yn2 in
                    [Yy]* ) brew upgrade;;
                esac
            else
                echo "No packages to upgrade."
            fi
            break;;
        * ) break;;
    esac
done

# Remove outdated formulae
while true; do
    read -r -p "Do you want to clean up outdated formulae? [y/N]?" yn
    case $yn in
        [Yy]* )
            UPDATES=$(HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n)
            if [[ -n $UPDATES ]]; then
                echo "Running brew cleanup for the following formulae:"
                echo "${UPDATES}"
                read -r -p "Do you wish to continue [y/N]?" yn2
                case $yn2 in
                    [Yy]* ) brew cleanup;;
                esac
            else
                echo "Nothing to clean up."
            fi
            break;;
        * ) break;;
    esac
done
