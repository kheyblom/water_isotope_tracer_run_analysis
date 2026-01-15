#!/bin/bash
# Script to find all netCDF files with less than 365 time steps
# Processes files in batches to avoid timeouts

BASE_DIR="/glade/u/home/kheyblom/scratch/icesm_data/processed/day"
OUTPUT_FILE="./files_with_less_than_365_timesteps.txt"
TEMP_DIR="/glade/u/home/kheyblom/scratch/timestep_check_$$"
BATCH_SIZE=100

# Create temp directory for batch processing
mkdir -p "$TEMP_DIR"

# Initialize output file
> "$OUTPUT_FILE"

echo "Starting check for files with < 365 time steps..."
echo "Output will be saved to: $OUTPUT_FILE"
echo ""

# Process each directory
for dir in iso-piControl-tag iso-historical_r1 iso-historical_r2; do
    dir_path="${BASE_DIR}/${dir}"
    
    if [ ! -d "$dir_path" ]; then
        echo "Warning: Directory $dir_path does not exist, skipping..."
        continue
    fi
    
    echo "=== Processing $dir ==="
    
    # Count total files first
    total_files=$(find "$dir_path" -name "*.nc" -type f | wc -l)
    echo "Found $total_files netCDF files in $dir"
    
    # Process files in batches
    batch_num=0
    processed=0
    
    find "$dir_path" -name "*.nc" -type f | while read -r file; do
        # Check time steps for this file
        n_steps=$(ncdump -h "$file" 2>/dev/null | grep -E "time = UNLIMITED" | sed 's/.*(\([0-9]*\) currently).*/\1/')
        
        if [ -n "$n_steps" ] && [ "$n_steps" -lt 365 ] 2>/dev/null; then
            # Get relative path from base directory
            rel_path="${file#${BASE_DIR}/}"
            echo "$rel_path: $n_steps" >> "$OUTPUT_FILE"
        fi
        
        processed=$((processed + 1))
        if [ $((processed % 100)) -eq 0 ]; then
            echo "  Processed $processed/$total_files files..." >&2
        fi
    done
    
    echo "Completed $dir"
    echo ""
done

# Generate summary
echo "=== Summary ==="
total_found=$(wc -l < "$OUTPUT_FILE")
echo "Total files with < 365 time steps: $total_found"
echo ""
echo "Breakdown by time step count:"
cut -d: -f2 "$OUTPUT_FILE" | sort -n | uniq -c | sort -rn | head -20

echo ""
echo "Results saved to: $OUTPUT_FILE"

# Cleanup
rm -rf "$TEMP_DIR"
