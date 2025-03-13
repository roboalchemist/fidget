#!/usr/bin/env python3
"""
Test script for using the caffeinate command to prevent sleep on macOS.
This approach doesn't move the mouse at all.
"""
import subprocess
import time
import signal
import sys

def run_caffeinate():
    print("Starting caffeinate to prevent sleep...")
    # -d prevents display sleep, -i prevents idle sleep
    process = subprocess.Popen(["caffeinate", "-d", "-i"], 
                            stdout=subprocess.PIPE, 
                            stderr=subprocess.PIPE)
    print(f"Caffeinate running with PID: {process.pid}")
    return process

def cleanup(signum, frame):
    if caffeinate_process:
        print("Terminating caffeinate process...")
        caffeinate_process.terminate()
    sys.exit(0)

# Set up signal handling for clean termination
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

# Start caffeinate
caffeinate_process = run_caffeinate()

# Keep the script running
try:
    while True:
        print("Sleep prevention active...")
        time.sleep(10)
except KeyboardInterrupt:
    cleanup(None, None) 