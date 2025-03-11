#!/bin/bash
# Gmail Genie Launch Agent Management Script

set -e

# Config
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_LABEL="com.gmail.genie"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
LOG_FILE="${HOME}/.local/share/gmail_genie/daemon.log"
CONFIG_DIR="${HOME}/.config/gmail-genie"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$CONFIG_DIR"

# Create plist file content
create_plist() {
    cat > "$AGENT_PLIST" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${REPO_DIR}/.venv/bin/python</string>
        <string>${REPO_DIR}/gmail_genie.py</string>
        <string>--interval-seconds</string>
        <string>600</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
    <key>WorkingDirectory</key>
    <string>${REPO_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOL
    echo "Created Launch Agent plist at: $AGENT_PLIST"
}

# Check if prerequisites are met
check_prereqs() {
    if [ ! -f "${REPO_DIR}/gmail_genie.py" ]; then
        echo "Error: gmail_genie.py not found in $REPO_DIR"
        exit 1
    fi
    
    if [ ! -d "${REPO_DIR}/.venv" ]; then
        echo "Error: Python virtual environment not found. Please run setup first:"
        echo "  brew install uv && uv venv && source .venv/bin/activate && uv pip install -r requirements.txt"
        exit 1
    fi
}

install() {
    check_prereqs
    
    # Create plist file
    create_plist
    
    echo "Gmail Genie Launch Agent installed successfully."
    echo "Use 'start' command to start the service."
}

uninstall() {
    stop
    if [ -f "$AGENT_PLIST" ]; then
        rm "$AGENT_PLIST"
        echo "Gmail Genie Launch Agent uninstalled successfully."
    else
        echo "Gmail Genie Launch Agent is not installed."
    fi
}

start() {
    if [ ! -f "$AGENT_PLIST" ]; then
        echo "Gmail Genie Launch Agent not installed. Installing..."
        install
    fi
    
    launchctl load -w "$AGENT_PLIST"
    echo "Gmail Genie Launch Agent started."
    echo "Logs available at: $LOG_FILE"
}

stop() {
    if [ -f "$AGENT_PLIST" ]; then
        launchctl unload -w "$AGENT_PLIST" 2>/dev/null || true
        echo "Gmail Genie Launch Agent stopped."
    else
        echo "Gmail Genie Launch Agent is not installed."
    fi
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if launchctl list | grep -q "${AGENT_LABEL}"; then
        echo "Gmail Genie Launch Agent is running."
        echo "Launch Agent plist: $AGENT_PLIST"
        echo "Log file: $LOG_FILE"
    else
        echo "Gmail Genie Launch Agent is not running."
    fi
}

logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "Showing last 20 log lines:"
        tail -n 20 "$LOG_FILE"
        echo ""
        echo "For continuous monitoring: tail -f $LOG_FILE"
    else
        echo "Log file not found at: $LOG_FILE"
    fi
}

tail_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "Following log file in real-time. Press Ctrl+C to exit."
        tail -f "$LOG_FILE"
    else
        echo "Log file not found at: $LOG_FILE"
    fi
}

case "$1" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    tail)
        tail_logs
        ;;
    *)
        echo "Usage: $0 {install|uninstall|start|stop|restart|status|logs|tail}"
        echo ""
        echo "Gmail Genie Launch Agent Management"
        echo ""
        echo "Commands:"
        echo "  install    Create and install the Launch Agent plist"
        echo "  uninstall  Remove the Launch Agent"
        echo "  start      Start the Gmail Genie service"
        echo "  stop       Stop the Gmail Genie service" 
        echo "  restart    Restart the Gmail Genie service"
        echo "  status     Show the current status"
        echo "  logs       Show recent log entries"
        echo "  tail       Follow log file in real-time (Ctrl+C to exit)"
        echo ""
        echo "Launch Agent configuration will be placed in:"
        echo "  $AGENT_PLIST"
        echo ""
        echo "Logs will be written to:"
        echo "  $LOG_FILE"
        ;;
esac