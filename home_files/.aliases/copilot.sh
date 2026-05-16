# cd into a directory and launch copilot
function cpcd() {
    if ! command -v copilot >/dev/null 2>&1; then
        echo "error: 'copilot' command not found. See https://docs.github.com/copilot/concepts/agents/about-copilot-cli to install." >&2
        return 1
    fi
    cd "$1" && copilot
}
