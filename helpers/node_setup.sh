#!/usr/bin/env bash

set -o errexit
#----------------------------
# Node setup
#----------------------------

# Add common node settings
TEXT=$(cat <<-END
\n
# Enable persistent REPL history for \`node\`.
export NODE_REPL_HISTORY=~/.node_history;
# Allow 32³ entries; the default is 1000.
export NODE_REPL_HISTORY_SIZE='32768';
# Use sloppy mode by default, matching web browsers.
export NODE_REPL_MODE='sloppy';

END
)
if [ ! -f ~/.extra ]; then
    touch ~/.extra
fi
grep -q -F "$TEXT" ~/.extra || printf "$TEXT" >> ~/.extra

