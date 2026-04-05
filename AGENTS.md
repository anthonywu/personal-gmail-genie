# AGENTS.md

## Repo Shape

- `gmail_genie.py` is the whole app and the primary entrypoint. There is no
  `pyproject.toml`; Python `>=3.13` and dependencies are declared in the
  PEP 723 header, so use `uv run gmail_genie.py ...` instead of assuming a
  venv-managed package.
- `gmail_genie_launcher.sh` is the only other executable source file; it
  manages the macOS LaunchAgent wrapper around `gmail_genie.py`.

## Verified Commands

- Real CLI: `uv run gmail_genie.py {run,interactive,self-test}`. Bare
  `uv run gmail_genie.py` still works because the script falls back to `run`
  when no subcommand is provided.
- One-shot processing: `uv run gmail_genie.py run --once`.
- Lint: `just lint`. Today that only runs `ruff check gmail_genie.py` and
  `ruff format gmail_genie.py`.
- LaunchAgent management: `./gmail_genie_launcher.sh {install|start|stop|restart|status|logs|tail}`.
- For routine non-destructive verification, use CLI help plus lint:
  `uv run gmail_genie.py --help`, `uv run gmail_genie.py run --help`,
  `uv run gmail_genie.py interactive --help`, `just lint`.

## Live Gmail Safety

- Anything beyond `--help` uses a real Gmail account. `run` can archive or
  trash messages immediately based on the active rules.
- `interactive` reads live mail and updates the rules JSON only after
  confirmation; it does not modify mailbox contents.
- `self-test` is a live integration test, not a unit test. It creates and
  deletes a label, sends mail to the authenticated account, and
  trash/untrashes that message during cleanup.
- First authentication opens a browser OAuth flow via
  `InstalledAppFlow.run_local_server(...)` and writes
  `~/.config/gmail-genie/token.pickle`.

## Config And Schema

- Default paths: credentials `~/.config/gmail-genie/credentials.json`,
  rules `~/.config/gmail-genie/rules.json`, OAuth token
  `~/.config/gmail-genie/token.pickle`, LaunchAgent plist
  `~/Library/LaunchAgents/com.gmail.genie.plist`, daemon log
  `~/.local/share/gmail_genie/daemon.log`.
- Missing rules files are bootstrapped at runtime by `_load_or_init_rules()`,
  which prompts to create a starter JSON. The README mentions
  `rules_examples.json`, but that file is not present in this repo.
- The current rule schema is only `rule_version`,
  `from_domain_auto_delete`, and `from_address_auto_archive`. If rule
  behavior changes, update `MailRuleModel`, interactive rule building, and
  starter-file creation together.

## Gotchas

- `run --once` executes a single processing pass and exits. Without `--once`,
  `main()` still loops forever; `--interval-seconds 0` becomes a tight loop,
  not a single pass.
- The generated LaunchAgent plist hardcodes the executable to
  `~/.local/bin/uv` and also sets a minimal `PATH`. If `uv` is installed
  somewhere else (for example via Homebrew or Nix), the agent can fail even
  when `uv` works in your interactive shell.
