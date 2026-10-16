#!/bin/bash

# Fidget wrapper script
# Builds Fidget from source (incrementally) and runs it in the background.
# Any arguments are passed through, e.g. ./fidget_wrapper.sh --verbose --interval 30

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

echo "Building Fidget..."
swift build --product Fidget || exit 1
FIDGET_BIN="$(swift build --show-bin-path)/Fidget"

# Run the app (from the repository root, so Resources/fidget.png is found)
echo "Starting Fidget..."
"$FIDGET_BIN" "$@" &
FIDGET_PID=$!

# Wait a moment to ensure the app has started
sleep 1

if ! kill -0 "$FIDGET_PID" 2>/dev/null; then
    wait "$FIDGET_PID"
    STATUS=$?
    echo "Fidget exited immediately (status $STATUS)."
    exit "$STATUS"
fi

echo "Fidget is running in the background (PID $FIDGET_PID)."
echo "Look for the Fidget icon in your menu bar."
