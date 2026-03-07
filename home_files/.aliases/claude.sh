# cd into a directory and launch claude
function clcd() {
    if ! command -v claude >/dev/null 2>&1; then
        echo "error: 'claude' command not found. See https://claude.ai/code to install." >&2
        return 1
    fi
    cd "$1" && claude
}
