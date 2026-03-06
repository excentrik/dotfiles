# Run $1 under session or attach if such session already exist. Example usage: run_under_tmux 'mutt' '/usr/local/bin/mutt';
run_under_tmux() {
    # $2 is optional path, if no specified, will use $1 from $PATH.
    # If you need to pass extra variables, use $2 for it as in example below..
    # More examples:
    #   mutt() { run_under_tmux 'mutt'; }
    #   irc() { run_under_tmux 'irssi' "TERM='screen' command irssi"; }
    command -v tmux >/dev/null 2>&1 || return 1

    if [ -z "$1" ]; then return 1; fi
    local name="$1"
    local execute="command ${name}"
    if [ -n "$2" ]; then
        execute="$2"
    fi

    if tmux has-session -t "${name}" 2>/dev/null; then
        tmux attach -d -t "${name}"
    else
        tmux new-session -s "${name}" "${execute}" \; set-option status \; set set-titles-string "${name} (tmux@localhost})"
    fi
}