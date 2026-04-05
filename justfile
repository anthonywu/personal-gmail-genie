default:
    @just --list

shellcheck:
    git ls-files -z '*.sh' '*.bash' | xargs -0 shellcheck

lint: shellcheck
    ruff check gmail_genie.py
    ruff format gmail_genie.py
