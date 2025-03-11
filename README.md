# Gmail Genie

A Gmail assistant that automates email management based on user-defined rules.

Goal: Give Gmail users personal agency, security, and privacy to add agentic assistants to their email.

## Usage

### One-time Setup

1. Get your `credentials.json` file and save it in the project directory.
   - Go to Google Cloud Console and create a project
   - Enable the Gmail API
   - Create OAuth 2.0 credentials (Desktop application)
   - Download the credentials JSON file and save as `credentials.json`

2. Install dependencies:
   ```bash
   brew install uv
   uv venv && source .venv/bin/activate
   uv pip install -r requirements.txt
   ```

3. Create your rules file (see `rules_examples.json` for template)

### Running the Script

Run manually:
```bash
python gmail_genie.py [--rules PATH] [--query QUERY] [--interval-seconds SECONDS]
```

### Launch Agent (macOS)

For automatic startup and management:

```bash
# Make the launcher script executable
chmod +x gmail_genie_launcher.sh

# Install the Launch Agent (creates plist in ~/Library/LaunchAgents/)
./gmail_genie_launcher.sh install

# Start the service
./gmail_genie_launcher.sh start

# Other commands
./gmail_genie_launcher.sh status    # Check if running
./gmail_genie_launcher.sh logs      # View recent logs
./gmail_genie_launcher.sh tail      # Follow logs in real-time (Ctrl+C to exit)
./gmail_genie_launcher.sh stop      # Stop the service
./gmail_genie_launcher.sh restart   # Restart the service
./gmail_genie_launcher.sh uninstall # Remove the Launch Agent
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

Many related attempts on PyPI and GitHub throughout the years, but few were built with 2024 LLM capabilities in mind.
