# Gmail Genie Development Guide

## Setup & Running

- Install: `brew install uv && uv venv && source .venv/bin/activate && uv pip install -r requirements.txt`
- Run: `python gmail_genie.py [--rules PATH] [--query QUERY] [--interval-seconds SECONDS]`
- macOS Launch Agent: `./gmail_genie_launcher.sh {install|start|stop|restart|status|logs|tail|uninstall}`
- View Launch Agent logs: `./gmail_genie_launcher.sh tail`

## Code Style Guidelines

- **Imports**: Standard library first, then third-party, then project-specific
- **Formatting**: PEP 8 with 4-space indentation
- **Types**: Use type hints with Pydantic models for structured data
- **Naming**: snake_case for functions/variables, PascalCase for classes
- **Error Handling**: Use try/except blocks with specific exception types
- **Documentation**: Use docstrings for functions and classes
- **Config Files**: Store user configuration in ~/.config/gmail-genie/

## Project Structure

- Single main Python file (`gmail_genie.py`)
- Configuration in JSON files
- Credentials handled via Google OAuth flow
- Rich console output for formatted display
- Launch Agent plist at `~/Library/LaunchAgents/com.gmail.genie.plist`
