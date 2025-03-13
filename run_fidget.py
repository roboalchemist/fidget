#!/usr/bin/env python3
"""
Simple wrapper to run the Fidget app directly.
This script helps test PyQt6 functionality without packaging issues.
"""

import sys
import subprocess
import os
import time

def main():
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Check if virtual environment exists
    venv_dir = os.path.join(script_dir, "venv")
    venv_python = os.path.join(venv_dir, "bin", "python")
    
    if not os.path.exists(venv_dir):
        print("Creating virtual environment...")
        subprocess.check_call([sys.executable, "-m", "venv", venv_dir])
        
        # Install dependencies
        print("Installing dependencies...")
        subprocess.check_call([venv_python, "-m", "pip", "install", "--upgrade", "pip"])
        subprocess.check_call([venv_python, "-m", "pip", "install", "PyQt6"])
    
    # Run the Fidget app
    print("Starting Fidget...")
    fidget_script = os.path.join(script_dir, "fidget.py")
    
    # Check PyQt6 installation
    try:
        subprocess.check_call([venv_python, "-c", "from PyQt6.QtWidgets import QApplication; print('PyQt6 is installed correctly')"])
        print("PyQt6 verification successful")
    except subprocess.CalledProcessError:
        print("Error: PyQt6 is not installed correctly")
        sys.exit(1)
    
    # Launch the app
    try:
        fidget_process = subprocess.Popen([venv_python, fidget_script])
        print("Fidget is running in the background.")
        print("Look for the Fidget icon in your menu bar.")
        
        # Wait a bit to see if there are any immediate crashes
        time.sleep(2)
        
        if fidget_process.poll() is not None:
            print(f"Error: Fidget process exited with code {fidget_process.returncode}")
            sys.exit(1)
        
    except Exception as e:
        print(f"Error starting Fidget: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 