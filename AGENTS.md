# AGENTS.md

## Repo Shape

- `gmail_genie.py` is the whole app and the primary entrypoint.
- `pyproject.toml` and `uv.lock` are the source of truth for Python
  dependencies. The project is pinned to Python `>=3.13,<3.14` with
  `.python-version` set to `3.13`.
- `gmail_genie_launcher.sh` is the only other executable source file; it
  manages the macOS LaunchAgent wrapper around `gmail_genie.py`. It lives in
  `macOS-scheduler/`.
- `Dockerfile` packages the app for Cloud Run Jobs using
  `ghcr.io/astral-sh/uv:python3.13-trixie-slim`, pre-syncs the locked project
  environment during build, and keeps the `uv run` execution model inside the
  container.
- `gcloud-scheduled-jobs/` contains the Cloud Run Job + Cloud Scheduler ops
  scaffold. Treat `gcloud-scheduled-jobs/.env.local` as local-only config;
  the tracked template is `gcloud-scheduled-jobs/.env.local.example`.

## Verified Commands

- Real CLI: `uv run gmail_genie.py {run,interactive,self-test}`. Bare
  `uv run gmail_genie.py` still works because the script falls back to `run`
  when no subcommand is provided.
- One-shot processing: `uv run gmail_genie.py run --once`.
- Safe preview: `uv run gmail_genie.py run --dry-run --once`.
- Lockfile refresh: `uv lock`.
- Lint: `just lint`. Today that runs `shellcheck` on tracked shell files,
  `just --unstable --fmt --check`, `ruff check gmail_genie.py`, and
  `ruff format gmail_genie.py`.
- Cloud ops: `just --justfile gcloud-scheduled-jobs/justfile provision`.
- Cloud ops local build: `just --justfile gcloud-scheduled-jobs/justfile build`.
- Cloud ops local run: `just --justfile gcloud-scheduled-jobs/justfile run-local`.
- Cloud ops logs: `just --justfile gcloud-scheduled-jobs/justfile logs`.
- Shell lint for the Cloud ops scripts:
  `shellcheck -x -P gcloud-scheduled-jobs/scripts gcloud-scheduled-jobs/scripts/*.sh`.
- LaunchAgent management:
  `macOS-scheduler/gmail_genie_launcher.sh {install|start|stop|restart|status|logs|tail|uninstall}`.
- For routine non-destructive verification, use CLI help plus lint:
  `uv run gmail_genie.py --help`, `uv run gmail_genie.py run --help`,
  `uv run gmail_genie.py interactive --help`, `just lint`.

## Live Gmail Safety

- Anything beyond `--help` uses a real Gmail account. `run` can archive or
  trash messages immediately based on the active rules.
- `run --dry-run` still reads the live mailbox and authenticates, but it does
  not archive or trash messages.
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
- The Cloud Run Job scaffold mounts Secret Manager secrets back onto those same
  config file paths inside the container under `/root/.config/gmail-genie/` to
  avoid changing the app's auth/config code.
- Those mounted secret files are read-only. `authenticate()` now tolerates a
  read-only `token.pickle` by refreshing in memory and continuing without
  persisting the refreshed token.
- Missing rules files are bootstrapped at runtime by `_load_or_init_rules()`,
  which prompts to create a starter JSON. The README mentions
  `rules_examples.json`, but that file is not present in this repo.
- The current rule schema is `rule_version`, `from_domain_auto_delete`,
  `from_address_auto_archive`, and `from_address_auto_unsubscribe` (RFC 8058
  one-click POST). If rule behavior changes, update `MailRuleModel`,
  interactive rule building, and starter-file creation together.

## Gotchas

- `run --once` executes a single processing pass and exits. Without `--once`,
  `main()` still loops forever; `--interval-seconds 0` becomes a tight loop,
  not a single pass.
- The generated LaunchAgent plist hardcodes the executable to
  `~/.local/bin/uv` and also sets a minimal `PATH`. If `uv` is installed
  somewhere else (for example via Homebrew or Nix), the agent can fail even
  when `uv` works in your interactive shell.
- `gcloud-scheduled-jobs/scripts/lib.sh` falls back to the active `gcloud`
  config project when `GCP_PROJECT_ID` is blank in `.env.local`, so keep the
  current `gcloud config set project ...` value in mind before running ops
  recipes.
