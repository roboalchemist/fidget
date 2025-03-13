#!/bin/bash

# Fidget wrapper script
# This script runs the Fidget app directly using Python

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if virtual environment exists
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$SCRIPT_DIR/venv"
    
    # Activate virtual environment
    source "$SCRIPT_DIR/venv/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    pip install PyQt6
else
    # Activate virtual environment
    source "$SCRIPT_DIR/venv/bin/activate"
fi

# Run the script
echo "Starting Fidget..."
python "$SCRIPT_DIR/fidget.py" "$@" &

# Wait a moment to ensure the app has started
sleep 1

echo "Fidget is running in the background."
echo "Look for the Fidget icon in your menu bar." 