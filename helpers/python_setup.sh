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

# Lazy init for modern Python tooling: each block is a no-op until the
# corresponding tool is actually installed on PATH, so this is safe to
# append on hosts that don't use pyenv / pipx / uv yet.
PYENV_INIT=$(cat <<-'END'

# pyenv shim (activates only when pyenv is installed)
if command -v pyenv >/dev/null 2>&1; then
    export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    [ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - 2>/dev/null)"
fi
END
)
grep -q -F "pyenv shim (activates only when pyenv is installed)" ~/.extra || printf "${PYENV_INIT}\n" >> ~/.extra

PIPX_INIT=$(cat <<-'END'

# pipx user bin on PATH (activates only when pipx is installed)
if command -v pipx >/dev/null 2>&1; then
    export PIPX_HOME="${PIPX_HOME:-$HOME/.local/pipx}"
    export PIPX_BIN_DIR="${PIPX_BIN_DIR:-$HOME/.local/bin}"
    case ":$PATH:" in
        *":$PIPX_BIN_DIR:"*) ;;
        *) export PATH="$PIPX_BIN_DIR:$PATH" ;;
    esac
fi
END
)
grep -q -F "pipx user bin on PATH (activates only when pipx is installed)" ~/.extra || printf "${PIPX_INIT}\n" >> ~/.extra

UV_INIT=$(cat <<-'END'

# uv shell completion + cache hint (activates only when uv is installed)
if command -v uv >/dev/null 2>&1; then
    export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
fi
END
)
grep -q -F "uv shell completion + cache hint (activates only when uv is installed)" ~/.extra || printf "${UV_INIT}\n" >> ~/.extra

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
