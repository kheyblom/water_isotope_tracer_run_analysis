#!/bin/bash

# Kill script for split_by_year processes
# This script will kill the main split_by_year script and all related processes

echo "Killing split_by_year processes..."

# Check if PID file exists
if [ ! -f "split_by_year.pid" ]; then
    echo "No split_by_year.pid file found. Script may not be running."
    exit 1
fi

# Check if hostname file exists
if [ ! -f "split_by_year.hostname" ]; then
    echo "No split_by_year.hostname file found. Cannot determine which node to connect to."
    exit 1
fi

# Read the main script PID and hostname
MAIN_PID=$(cat split_by_year.pid)
TARGET_HOSTNAME=$(cat split_by_year.hostname)
CURRENT_HOSTNAME=$(hostname)

echo "Main script PID: $MAIN_PID"
echo "Target hostname: $TARGET_HOSTNAME"
echo "Current hostname: $CURRENT_HOSTNAME"

# Check if we need to SSH to a different node
if [ "$TARGET_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    echo "Script is running on a different node. SSHing to $TARGET_HOSTNAME..."
    ssh "$TARGET_HOSTNAME" "cd $(pwd) && $0"
    exit $?
fi

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

# Kill any ncks processes (used for splitting)
echo "Killing ncks processes..."
pkill -u "$CURRENT_USER" -f "ncks.*-d time" 2>/dev/null

# Kill any xargs processes related to split_file_by_year
echo "Killing xargs processes..."
pkill -u "$CURRENT_USER" -f "xargs.*split_file_by_year" 2>/dev/null

# Kill any bash processes running our function
echo "Killing bash processes..."
pkill -u "$CURRENT_USER" -f "bash.*split_file_by_year" 2>/dev/null

# Force kill if needed
echo "Force killing any remaining processes..."
pkill -9 -u "$CURRENT_USER" -f "ncks.*-d time" 2>/dev/null
pkill -9 -u "$CURRENT_USER" -f "xargs.*split_file_by_year" 2>/dev/null
pkill -9 -u "$CURRENT_USER" -f "bash.*split_file_by_year" 2>/dev/null

# Remove PID and hostname files
rm -f split_by_year.pid
rm -f split_by_year.hostname

# Clean up any temporary files in output directories
echo "Cleaning up temporary files..."
# Clean up any ncks temporary files (if any)
find /glade/u/home/kheyblom/scratch/icesm_data/processed -name "*.tmp" -delete 2>/dev/null

echo "All split_by_year processes killed and temporary files cleaned up."

