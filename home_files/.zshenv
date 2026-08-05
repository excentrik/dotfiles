# Keep .zshenv minimal: zsh reads it for every invocation, including scripts.
# Otherwise changes to some variables (such as $PROMPT) may be overwritten
setopt NO_GLOBAL_RCS

# Non-interactive zsh still needs repo-managed wrappers and user-local tools.
[[ -r "$HOME/.path" ]] && source "$HOME/.path"
