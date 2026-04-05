set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

shellcheck:
    git ls-files -z '*.sh' '*.bash' | xargs -0 shellcheck

justfmt:
    just --unstable --fmt

justfmt-check:
    just --unstable --fmt --check

lint: shellcheck justfmt-check
    ruff check gmail_genie.py
    ruff format gmail_genie.py
