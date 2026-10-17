#!/bin/bash
# Script to kill any running instances of the Fidget app

echo "Searching for Fidget processes..."

# The Swift app runs as a process named "Fidget" (dist/Fidget.app, an installed copy, or a swift build binary)
APP_PIDS=$(pgrep -x Fidget)

if [ -z "$APP_PIDS" ]; then
    echo "No Fidget processes were found or killed."
    exit 0
fi

echo "Found Fidget processes with PIDs: $(echo $APP_PIDS)"

# SIGTERM first so the app can stop its caffeinate process and exit cleanly
for PID in $APP_PIDS; do
    echo "Stopping process with PID $PID..."
    kill -TERM "$PID" 2>/dev/null
done

# Wait up to 3 seconds, then force-kill anything still running
REMAINING=""
for _ in $(seq 1 30); do
    REMAINING=""
    for PID in $APP_PIDS; do
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
