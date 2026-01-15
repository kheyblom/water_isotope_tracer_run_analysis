#!/bin/bash

# Cleanup script for split_by_year temporary files
# This script reads the config file to determine the output directory
# and cleans up temporary files created during the splitting process

CONFIG_FILE="${1:-split_by_year.conf}"

echo "Cleaning up temporary files from split_by_year processing..."
echo "Reading config file: $CONFIG_FILE"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    echo "Usage: $0 [config_file]"
    echo "  Default config file: split_by_year.conf"
    exit 1
fi

# Source the config file to get variables
# Extract run_frequency and output_directory_root
RUN_FREQUENCY=$(grep "^run_frequency=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
OUTPUT_DIR_ROOT=$(grep "^output_directory_root=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')

if [ -z "$RUN_FREQUENCY" ] || [ -z "$OUTPUT_DIR_ROOT" ]; then
    echo "ERROR: Could not find 'run_frequency' or 'output_directory_root' in config file."
    exit 1
fi

# Replace ${run_frequency} with actual value
OUTPUT_DIR=$(echo "$OUTPUT_DIR_ROOT" | sed "s/\${run_frequency}/$RUN_FREQUENCY/g")

echo "Output directory: $OUTPUT_DIR"

# Check if output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "WARNING: Output directory does not exist: $OUTPUT_DIR"
    echo "Skipping cleanup of output directory files."
else
    # Clean up temporary files in output directory and subdirectories
    echo "Cleaning up temporary files in $OUTPUT_DIR..."
    
    # Find and remove .tmp files (created by NCO or other tools)
    TMP_COUNT=$(find "$OUTPUT_DIR" -type f -name "*.tmp" 2>/dev/null | wc -l)
    if [ "$TMP_COUNT" -gt 0 ]; then
        echo "  Found $TMP_COUNT .tmp file(s)"
        find "$OUTPUT_DIR" -type f -name "*.tmp" -delete 2>/dev/null
        echo "  Removed .tmp files"
    else
        echo "  No .tmp files found"
    fi
    
    # Find and remove other common temporary file patterns
    # NCO sometimes creates files with .nc.tmp or similar patterns
    TMP_NC_COUNT=$(find "$OUTPUT_DIR" -type f -name "*.nc.tmp" 2>/dev/null | wc -l)
    if [ "$TMP_NC_COUNT" -gt 0 ]; then
        echo "  Found $TMP_NC_COUNT .nc.tmp file(s)"
        find "$OUTPUT_DIR" -type f -name "*.nc.tmp" -delete 2>/dev/null
        echo "  Removed .nc.tmp files"
    fi
    
fi

echo "Cleanup completed."

