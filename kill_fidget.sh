#!/bin/bash
# Script to kill any running instances of the Fidget app

echo "Searching for Fidget processes..."

# Find and kill Python processes running fidget.py
PYTHON_PIDS=$(ps aux | grep -i "python.*fidget.py" | grep -v grep | awk '{print $2}')
if [ -n "$PYTHON_PIDS" ]; then
    echo "Found Python Fidget processes with PIDs: $PYTHON_PIDS"
    for PID in $PYTHON_PIDS; do
        echo "Killing Python process with PID $PID..."
        kill -9 $PID 2>/dev/null
    done
else
    echo "No Python Fidget processes found."
fi

# Find and kill Fidget.app processes
APP_PIDS=$(ps aux | grep -i "Fidget.app" | grep -v grep | awk '{print $2}')
if [ -n "$APP_PIDS" ]; then
    echo "Found Fidget.app processes with PIDs: $APP_PIDS"
    for PID in $APP_PIDS; do
        echo "Killing Fidget.app process with PID $PID..."
        kill -9 $PID 2>/dev/null
    done
else
    echo "No Fidget.app processes found."
fi

# Check if any processes were killed
if [ -z "$PYTHON_PIDS" ] && [ -z "$APP_PIDS" ]; then
    echo "No Fidget processes were found or killed."
    exit 0
else
    echo "All Fidget processes have been terminated."
    exit 0
fi 