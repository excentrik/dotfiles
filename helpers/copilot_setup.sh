#!/usr/bin/env bash
set -euo pipefail

# Install GitHub Copilot CLI if not already installed
if command -v copilot >/dev/null 2>&1; then
    echo "GitHub Copilot CLI is already installed: $(copilot --version 2>/dev/null || which copilot)"
elif ! command -v npm >/dev/null 2>&1; then
    echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing GitHub Copilot CLI." >&2
else
    echo "Installing GitHub Copilot CLI..."
    npm install -g @github/copilot
fi

# Verify copilot is in PATH
if command -v copilot >/dev/null 2>&1; then
    echo "GitHub Copilot CLI is in PATH: $(which copilot)"
else
    echo "warning: 'copilot' not found in PATH after install. You may need to restart your shell." >&2
fi
