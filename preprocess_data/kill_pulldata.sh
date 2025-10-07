#!/bin/bash

# Kill script for pulldata processes
# This script will kill the main pulldata script and all related processes

echo "Killing pulldata processes..."

# Check if PID file exists
if [ ! -f "pulldata.pid" ]; then
    echo "No pulldata.pid file found. Script may not be running."
    exit 1
fi

# Read the main script PID
MAIN_PID=$(cat pulldata.pid)
echo "Main script PID: $MAIN_PID"

# Get current user
CURRENT_USER=$(whoami)

# Kill the main script first
echo "Killing main script (PID: $MAIN_PID)..."
kill -TERM $MAIN_PID 2>/dev/null

# Wait a moment for graceful shutdown
sleep 2

# Check if main script is still running
if kill -0 $MAIN_PID 2>/dev/null; then
    echo "Main script still running, force killing..."
    kill -9 $MAIN_PID 2>/dev/null
fi

# Kill any remaining ncrcat processes
echo "Killing ncrcat processes..."
pkill -u "$CURRENT_USER" -f "ncrcat.*cam\.h[01]\." 2>/dev/null

# Kill any xargs processes
echo "Killing xargs processes..."
pkill -u "$CURRENT_USER" -f "xargs.*process_variable" 2>/dev/null

# Kill any bash processes running our function
echo "Killing bash processes..."
pkill -u "$CURRENT_USER" -f "bash.*process_variable" 2>/dev/null

# Force kill if needed
echo "Force killing any remaining processes..."
pkill -9 -u "$CURRENT_USER" -f "ncrcat.*cam\.h[01]\." 2>/dev/null
pkill -9 -u "$CURRENT_USER" -f "xargs.*process_variable" 2>/dev/null
pkill -9 -u "$CURRENT_USER" -f "bash.*process_variable" 2>/dev/null

# Remove PID file
rm -f pulldata.pid

# Clean up any ncrcat temporary files in output directories
echo "Cleaning up temporary files..."
find /glade/u/home/kheyblom/scratch/icesm_data/processed -name "*.ncrcat.tmp" -delete 2>/dev/null

echo "All pulldata processes killed and temporary files cleaned up."
