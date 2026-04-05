# Gmail Genie

[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](LICENSE)
[![Python 3.13+](https://img.shields.io/badge/python-%3E%3D3.13-blue.svg)](https://www.python.org/downloads/)
[![GitHub last commit](https://img.shields.io/github/last-commit/anthonywu/personal-gmail-genie)](https://github.com/anthonywu/personal-gmail-genie)

A Gmail assistant that automates email management based on user-defined
rules.

Goal: Give Gmail users personal agency, security, and privacy to add
agentic assistants to their email.

## Usage

### One-time Setup

1. Get your `credentials.json` file and save it to
   `~/.config/gmail-genie/credentials.json`.
   - Go to [Google Cloud Console](https://console.cloud.google.com) and
     create a project
   - Enable the Gmail API
   - Navigate to credentials: `https://console.cloud.google.com/apis/api/gmail.googleapis.com/credentials?project=<project-name>`
   - Create OAuth 2.0 credentials (Desktop application)
   - Download the credentials JSON file and save as
     `~/.config/gmail-genie/credentials.json`

2. Install dependencies:

   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh # or `brew install uv`
   uv sync
   uv run gmail_genie.py --help
   ```

3. Create your rules file.
   - Copy `rules.example.json` to `~/.config/gmail-genie/rules.json`, or
   - Let Gmail Genie create a starter file the first time you run
     `uv run gmail_genie.py run --dry-run --once` or
     `uv run gmail_genie.py interactive`

### Running the Script

Run manually:

```bash
uv run gmail_genie.py run [--rules PATH] [--query QUERY]
  [--interval-seconds SECONDS] [--dry-run] [--once]
```

Dependencies are tracked in `pyproject.toml` and `uv.lock`.

Use `--once` to process a single pass and exit instead of polling forever.
Use `--dry-run` to preview archive, trash, and unsubscribe decisions without
changing Gmail.

For Cloud Run, `gcloud-scheduled-jobs/.env.local` also supports optional
`NTFY_BASE_URL` and `NTFY_TOPIC` settings. When configured, the job only sends
an `ntfy` push if it actually archives, deletes, or unsubscribes something.

Run the container locally with your existing Gmail config mounted in:

```bash
just --justfile gcloud-scheduled-jobs/justfile run-local
```

### Launch Agent (macOS)

For automatic startup and management:

```bash
# Make the launcher script executable
chmod +x macOS-scheduler/gmail_genie_launcher.sh

# Install the Launch Agent (creates plist in ~/Library/LaunchAgents/)
./macOS-scheduler/gmail_genie_launcher.sh install

# Start the service
./macOS-scheduler/gmail_genie_launcher.sh start

# Other commands
./macOS-scheduler/gmail_genie_launcher.sh status    # Check if running
./macOS-scheduler/gmail_genie_launcher.sh logs      # View recent logs
./macOS-scheduler/gmail_genie_launcher.sh tail      # Follow logs in real-time
                                                  # (Ctrl+C to exit)
./macOS-scheduler/gmail_genie_launcher.sh stop      # Stop the service
./macOS-scheduler/gmail_genie_launcher.sh restart   # Restart the service
./macOS-scheduler/gmail_genie_launcher.sh uninstall # Remove the Launch Agent
```

The Launch Agent configuration is stored at: `~/Library/LaunchAgents/com.gmail.genie.plist`
Logs are stored at: `~/.local/share/gmail_genie/daemon.log`

## Rules Engine

### Rule Schema

The current rules file is a single JSON object:

```json
{
  "rule_version": "1",
  "from_domain_auto_delete": [
    "promo.example"
  ],
  "from_address_auto_archive": [
    "receipts@example.com"
  ],
  "from_address_auto_unsubscribe": [
    "newsletter@example.com"
  ]
}
```

- `rule_version` is a schema marker. The current value is `"1"`.
- `from_domain_auto_delete` matches the sender domain parsed from the `From`
  header, case-insensitively.
- `from_address_auto_archive` matches the full sender email address parsed from
  the `From` header, case-insensitively.
- `from_address_auto_unsubscribe` matches the full sender email address,
  case-insensitively, but only when the message includes the
  `List-Unsubscribe-Post` header required for one-click unsubscribe.

### Evaluation Order

The rules engine uses a fixed first-match order:

1. Domain delete
2. Exact-address archive
3. Exact-address one-click unsubscribe
4. No-op

That order matters. A sender domain in `from_domain_auto_delete` overrides the
address-based rules for the same message. Likewise, an address in
`from_address_auto_archive` wins before `from_address_auto_unsubscribe` is
considered.

### Action Semantics

- `DELETE` currently calls Gmail's trash API. Messages are moved to Trash, not
  permanently deleted.
- `ARCHIVE` removes the `INBOX` and `UNREAD` labels from the message.
- `UNSUBSCRIBE` extracts the first HTTPS URL from the `List-Unsubscribe`
  header, sends an RFC 8058 style POST with
  `List-Unsubscribe=One-Click`, and then archives the message if the POST
  succeeds.
- `NO_OP` leaves the message untouched.

If the unsubscribe headers are incomplete or the POST fails, Gmail Genie does
not fall back to another action for that message during the same run.

### Message Selection

- `run` and `interactive` default to unread messages.
- Passing `--query` switches to a normal Gmail search query instead.
- Query-based runs currently inspect up to 50 messages per pass.

### Building Rules Interactively

`uv run gmail_genie.py interactive` walks matching messages one by one and lets
you add:

- a delete-by-domain rule
- an archive-by-address rule
- an unsubscribe-by-address rule when the message advertises one-click support

New rules are only written after you confirm the proposed changes.

## Features

- Gmail automation with rules-based filtering
- Actions: archive, move to trash, one-click unsubscribe, or no-op based on sender rules
- Interval-based polling for new messages
- Formatted console output with Rich

## Progress

- ✅ List emails by query
- ✅ Working demo of basic archive / trash actions
- ✅ Mapping label internal ID to humanized label names
- ✅ Background daemon support
- ✅ macOS Launch Agent support

## Todo

- Improve the rules schema
- Connect to local LLM models for:
  - Summarization
  - Suggested auto-reply
  - Auto-forward capabilities
  - Intelligent sorting and rule suggestions
- GUI for configurations
- System notifications
- History server to track agent actions

## Related Projects

Many related attempts on PyPI and GitHub throughout the years, but few were
built with 2024 LLM capabilities in mind.
