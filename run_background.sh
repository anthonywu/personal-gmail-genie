#!/bin/bash

BG_LOG_FILE=~/.local/share/gmail_genie/background.log

cd $(dirname $0)

if ! /usr/bin/which -s pgrep; then
    echo "Please brew install pgrep (or use similar package manager)."
    exit 1
fi

if ! pgrep -f "python gmail_genie.py" > /dev/null; then
    nohup .venv/bin/python gmail_genie.py >> $BG_LOG_FILE 2>&1 &
    echo "Follow background activity with: tail -f $BG_LOG_FILE"
else
    echo "A copy of this program is already running. PID = $(pgrep -f 'python gmail_genie.py')"

    exit 1
fi
