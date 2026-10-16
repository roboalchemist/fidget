#!/bin/bash
# Script to kill any running instances of the Fidget app

echo "Searching for Fidget processes..."

# The Swift app runs as a process named "Fidget" (dist/Fidget.app, an installed copy, or a swift build binary)
APP_PIDS=$(pgrep -x Fidget)
# Instances of the old Python version
PYTHON_PIDS=$(pgrep -f "python.*fidget\.py")

if [ -z "$APP_PIDS" ] && [ -z "$PYTHON_PIDS" ]; then
    echo "No Fidget processes were found or killed."
    exit 0
fi

[ -n "$APP_PIDS" ] && echo "Found Fidget processes with PIDs: $(echo $APP_PIDS)"
[ -n "$PYTHON_PIDS" ] && echo "Found Python Fidget processes with PIDs: $(echo $PYTHON_PIDS)"

# SIGTERM first so the app can stop its caffeinate process and exit cleanly
for PID in $APP_PIDS $PYTHON_PIDS; do
    echo "Stopping process with PID $PID..."
    kill -TERM "$PID" 2>/dev/null
done

# Wait up to 3 seconds, then force-kill anything still running
for _ in $(seq 1 30); do
    REMAINING=""
    for PID in $APP_PIDS $PYTHON_PIDS; do
        kill -0 "$PID" 2>/dev/null && REMAINING="$REMAINING $PID"
    done
    [ -z "$REMAINING" ] && break
    sleep 0.1
done
for PID in $REMAINING; do
    echo "Process $PID did not exit, killing it..."
    kill -9 "$PID" 2>/dev/null
done

echo "All Fidget processes have been terminated."
exit 0
