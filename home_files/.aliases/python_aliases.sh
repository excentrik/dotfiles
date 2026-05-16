#!/usr/bin/env bash
#-------------------
# Python aliases
#-------------------

# Clean all python cache files (works for both py2 and py3)
pyclean() {
    find . -type f -name '*.py[co]' -delete -o -type d -name __pycache__ -delete
}

# URL-encode strings
alias urlencode='python3 -c "import sys; from urllib.parse import quote_plus; print(quote_plus(sys.argv[1]))"'
