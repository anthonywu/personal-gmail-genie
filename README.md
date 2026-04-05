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
   # the script is a 'uv run' script with all dependencies defined in the
   # comment header
   uv run gmail_genie.py
   ```

3. Create your rules file (see `rules_examples.json` for template)

### Running the Script

Run manually:

```bash
uv run gmail_genie.py run [--rules PATH] [--query QUERY]
  [--interval-seconds SECONDS] [--dry-run] [--once]
```

Use `--once` to process a single pass and exit instead of polling forever.
Use `--dry-run` to preview archive/delete decisions without changing Gmail.

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
./macOS-scheduler/gmail_genie_launcher.sh tail      # Follow logs in real-time (Ctrl+C to exit)
./macOS-scheduler/gmail_genie_launcher.sh stop      # Stop the service
./macOS-scheduler/gmail_genie_launcher.sh restart   # Restart the service
./macOS-scheduler/gmail_genie_launcher.sh uninstall # Remove the Launch Agent
```

The Launch Agent configuration is stored at: `~/Library/LaunchAgents/com.gmail.genie.plist`
Logs are stored at: `~/.local/share/gmail_genie/daemon.log`

## Features

- Gmail automation with rules-based filtering
- Actions: archive, delete, or no-op based on email patterns
- Interval-based polling for new messages
- Formatted console output with Rich

## Progress

- ✅ List emails by query
- ✅ Working demo of basic archive / delete actions
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
