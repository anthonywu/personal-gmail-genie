default:
    @just --list

lint:
    ruff check gmail_genie.py
    ruff format gmail_genie.py
