#!/usr/bin/env bash

TEXT=$(cat <<-END
\n
# Disable bytecode files
export PYTHONDONTWRITEBYTECODE=1
# Use UTF-8 enconding for python
export PYTHONIOENCODING='UTF-8';
export LANG='C.UTF-8';
END
)

if [ ! -f ~/.extra ]; then
    touch ~/.extra
fi
grep -q -F "$TEXT" ~/.extra || printf "${TEXT}\n" >> ~/.extra

# Add support for jedi/default autocompletion in Python
TEXT=$(cat <<-END
try:
    from jedi.utils import setup_readline
    setup_readline()
except ImportError:
    # Fallback to the stdlib readline completer if it is installed.
    # Taken from http://docs.python.org/2/library/rlcompleter.html
    print("Jedi is not installed, falling back to readline")
    try:
        import readline
        import rlcompleter
        readline.parse_and_bind("tab: complete")
    except ImportError:
        print("Readline is not installed either. No tab completion is enabled.")
END
)

echo "${TEXT}" > ~/.pythonrc.py
grep -q -F "export PYTHONSTARTUP=$HOME/.pythonrc.py" ~/.extra || printf "export PYTHONSTARTUP=$HOME/.pythonrc.py\n" >> ~/.extra
