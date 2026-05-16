#!/usr/bin/env bash
set -euo pipefail

# Install Claude Code if not already installed
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code already installed: $(claude --version)"
elif ! command -v npm >/dev/null 2>&1; then
    echo "warning: 'npm' not found. Install npm or rerun with DOTFILES_BOOTSTRAP=1 before installing Claude Code." >&2
else
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi

# Verify claude is in PATH
if command -v claude >/dev/null 2>&1; then
    echo "Claude Code is in PATH: $(which claude)"
else
    echo "warning: 'claude' not found in PATH after install. You may need to restart your shell." >&2
fi
