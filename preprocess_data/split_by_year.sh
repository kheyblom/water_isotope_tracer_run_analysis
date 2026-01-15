#!/bin/bash

# Allow config file to be specified as command-line argument
CONFIG_FILE="${1:-split_by_year.conf}"

# Load configuration first (before setting up logging)
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: $CONFIG_FILE not found!"
    echo "Usage: $0 [config_file]"
    echo "  Default config: split_by_year.conf"
    echo "  Test config:    split_by_year.test.conf"
    exit 1
fi

# Set defaults if not specified in config
OVERWRITE_YEARLY_FILES="${OVERWRITE_YEARLY_FILES:-false}"
MAX_PARALLEL_SPLIT="${MAX_PARALLEL_SPLIT:-4}"
TEST_VARIABLE="${TEST_VARIABLE:-}"
DELETE_ORIGINAL_AFTER_SPLIT="${DELETE_ORIGINAL_AFTER_SPLIT:-false}"

# Set up output redirection to log file (append mode)
# Default to split_by_year.log if output_file is not set in config
OUTPUT_LOG="${output_file:-split_by_year.log}"
exec >> "$OUTPUT_LOG" 2>&1

echo
echo
echo
echo "--------------------------------"
echo "Starting split_by_year.sh"
echo "--------------------------------"
echo

echo "Script started at $(date)"
echo "Hostname: $(hostname)"
echo $(hostname) > split_by_year.hostname
echo "Main script PID: $$"
echo $$ > split_by_year.pid
module load nco
echo "NCO module loaded"
echo "Loading configuration from $CONFIG_FILE"

# Simple cleanup function to remove PID file and hostname file on exit
cleanup() {
    rm -f split_by_year.pid
    rm -f split_by_year.hostname
}

# Set up signal handlers
trap cleanup EXIT

# Function to get time information from a NetCDF file
get_time_info() {
    local nc_file=$1
    # Get time units
    local time_units=$(ncdump -h "$nc_file" | grep 'time:units' | sed 's/.*time:units = "\([^"]*\)".*/\1/')
    
    # Get calendar type (default to "standard" if not found)
    local calendar=$(ncdump -h "$nc_file" | grep 'time:calendar' | sed 's/.*time:calendar = "\([^"]*\)".*/\1/')
    if [ -z "$calendar" ]; then
        calendar="standard"
    fi
    
    # Get time dimension size - handle both fixed and UNLIMITED dimensions
    # Format can be: "time = 365 ;" or "time = UNLIMITED ; // (56941 currently)"
    local time_size=$(ncdump -h "$nc_file" | grep -E "^\s*time = " | sed -E 's/.*time = (UNLIMITED ; \/\/ \()?([0-9]+).*/\2/')
    
    # Get first and last time values
    local first_time=$(ncks -H -s '%f\n' -C -v time -d time,0 "$nc_file" 2>/dev/null | head -1)
    local last_time=$(ncks -H -s '%f\n' -C -v time -d time,$((time_size-1)) "$nc_file" 2>/dev/null | head -1)
    
    echo "$time_units|$time_size|$first_time|$last_time|$calendar"
}

# Function to extract year from time units
extract_base_year() {
    local time_units=$1
    # Extract year from units like "days since 1850-01-01 00:00:00"
    if [[ "$time_units" =~ since\ ([0-9]{4})-01-01 ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to verify a NetCDF file is valid
verify_netcdf_file() {
    local nc_file=$1
    local expected_time_steps=$2
    
    # Check file exists and has non-zero size
    if [ ! -s "$nc_file" ]; then
        return 1
    fi
    
    # Check file is a valid NetCDF (ncdump should succeed)
    if ! ncdump -h "$nc_file" > /dev/null 2>&1; then
        return 1
    fi
    
    # If expected time steps provided, verify time dimension
    if [ -n "$expected_time_steps" ]; then
        local actual_time=$(ncdump -h "$nc_file" | grep -E "^\s*time = " | sed -E 's/.*time = (UNLIMITED ; \/\/ \()?([0-9]+).*/\2/')
        if [ "$actual_time" != "$expected_time_steps" ]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to split a single file by year
split_file_by_year() {
    local input_file=$1
    local script_dir=$2
    local variable_name=$3
    
    # Get file basename
    local file_basename=$(basename "$input_file" .nc)
    
    # Skip if file doesn't exist (already processed and deleted)
    if [ ! -f "$input_file" ]; then
        return 0
    fi
    
    echo "  PROCESSING: $variable_name"
    
    # Track created files for verification
    local -a created_files=()
    local -a expected_time_steps=()
    local all_successful=true
    
    # Get time information
    local time_info=$(get_time_info "$input_file")
    local time_units=$(echo "$time_info" | cut -d'|' -f1)
    local time_size=$(echo "$time_info" | cut -d'|' -f2)
    local first_time=$(echo "$time_info" | cut -d'|' -f3)
    local last_time=$(echo "$time_info" | cut -d'|' -f4)
    local calendar=$(echo "$time_info" | cut -d'|' -f5)
    
    if [ -z "$time_size" ] || [ "$time_size" -eq 0 ]; then
        echo "    WARNING: $variable_name - could not determine time dimension size"
        return 1
    fi
    
    # Extract base year from time units
    local base_year=$(extract_base_year "$time_units")
    if [ -z "$base_year" ]; then
        echo "    WARNING: $variable_name - could not extract base year, using 1850"
        base_year="1850"  # Default fallback
    fi
    
    # Determine if time is in days or months
    local time_unit_type="days"
    if [[ "$time_units" =~ "days since" ]]; then
        time_unit_type="days"
    elif [[ "$time_units" =~ "months since" ]]; then
        time_unit_type="months"
    fi
    
    # Determine days per year based on calendar
    local days_per_year=365
    if [[ "$calendar" == "standard" || "$calendar" == "gregorian" || "$calendar" == "proleptic_gregorian" ]]; then
        days_per_year=365.25
    fi
    
    # Get file directory
    local file_dir=$(dirname "$input_file")
    
    # Create output directory: {experiment_dir}/{variable}/
    local output_dir="${file_dir}/${variable_name}"
    mkdir -p "$output_dir"
    
    # Output filename pattern: {exp}.{variable}.{freq}.{year}.nc
    local output_basename="${file_basename}"
    
    # Extract all time values at once for efficiency
    # Use ncks with -s flag to get just the numeric values
    # Filter out empty lines and non-numeric values
    local temp_time_file=$(mktemp)
    ncks -H -s '%f\n' -C -v time "$input_file" 2>/dev/null | grep -E '^[0-9]' > "$temp_time_file"
    
    if [ ! -s "$temp_time_file" ]; then
        echo "    ERROR: $variable_name - could not extract time values"
        rm -f "$temp_time_file"
        return 1
    fi
    
    # Read time values into array
    mapfile -t time_values < "$temp_time_file"
    rm -f "$temp_time_file"
    
    # Find year boundaries
    local year_start_idx=0
    local prev_year=""
    local current_year=""
    
    for ((idx=0; idx<${#time_values[@]}; idx++)); do
        local time_val=${time_values[idx]}
        
        # Skip empty or invalid time values
        if [ -z "$time_val" ]; then
            continue
        fi
        
        # Calculate year from time value
        # For monthly data: use (time_val - 0.5) because time is at end of month
        #   e.g., day 365 = end of Dec 1850, should be year 1850
        # For daily data: no offset because time is at start of day
        #   e.g., day 365 = Jan 1 1851, should be year 1851
        if [ "$time_unit_type" == "days" ]; then
            if [ "$run_frequency" == "mon" ]; then
                current_year=$(echo "$time_val $base_year $days_per_year" | awk '{printf "%.0f", $2 + int(($1-0.5)/$3)}')
            else
                current_year=$(echo "$time_val $base_year $days_per_year" | awk '{printf "%.0f", $2 + int($1/$3)}')
            fi
        elif [ "$time_unit_type" == "months" ]; then
            current_year=$(echo "$time_val $base_year" | awk '{printf "%.0f", $2 + int($1/12)}')
        else
            current_year=$base_year
        fi
        
        # If year changed (or first iteration), process previous year
        if [ -n "$prev_year" ] && [ "$current_year" != "$prev_year" ]; then
            local year_end_idx=$((idx - 1))
            local num_time_steps=$((year_end_idx - year_start_idx + 1))
            local prev_year_padded=$(printf "%04d" "$prev_year")
            local output_file="${output_dir}/${output_basename}.${prev_year_padded}.nc"
            
            if [[ -f "$output_file" && "$OVERWRITE_YEARLY_FILES" == "false" ]]; then
                created_files+=("$output_file")
                expected_time_steps+=("$num_time_steps")
            else
                ncks -O -d time,$year_start_idx,$year_end_idx "$input_file" "$output_file" 2>>${script_dir}/nco_split_errors.log
                if [ $? -eq 0 ]; then
                    created_files+=("$output_file")
                    expected_time_steps+=("$num_time_steps")
                else
                    echo "    ERROR: $variable_name - failed to create year $prev_year"
                    all_successful=false
                fi
            fi
            
            year_start_idx=$idx
        fi
        
        prev_year=$current_year
    done
    
    # Process the last year (use time_size for the actual dimension size)
    if [ -n "$current_year" ] && [ $year_start_idx -lt $time_size ]; then
        local year_end_idx=$((time_size - 1))
        local num_time_steps=$((year_end_idx - year_start_idx + 1))
        local current_year_padded=$(printf "%04d" "$current_year")
        local output_file="${output_dir}/${output_basename}.${current_year_padded}.nc"
        
        if [[ -f "$output_file" && "$OVERWRITE_YEARLY_FILES" == "false" ]]; then
            created_files+=("$output_file")
            expected_time_steps+=("$num_time_steps")
        else
            ncks -O -d time,$year_start_idx,$year_end_idx "$input_file" "$output_file" 2>>${script_dir}/nco_split_errors.log
            if [ $? -eq 0 ]; then
                created_files+=("$output_file")
                expected_time_steps+=("$num_time_steps")
            else
                echo "    ERROR: $variable_name - failed to create year $current_year"
                all_successful=false
            fi
        fi
    fi
    
    echo "  COMPLETED: $variable_name (${#created_files[@]} years)"
    
    # Verify all created files
    local verification_passed=true
    for ((v=0; v<${#created_files[@]}; v++)); do
        local vfile="${created_files[v]}"
        local vexpected="${expected_time_steps[v]}"
        if ! verify_netcdf_file "$vfile" "$vexpected"; then
            echo "    ERROR: $variable_name - verification failed for $(basename "$vfile")"
            verification_passed=false
            all_successful=false
        fi
    done
    
    if $verification_passed; then
        echo "  VERIFIED: $variable_name"
    fi
    
    # Delete original file if configured and all operations successful
    if $all_successful && [ "$DELETE_ORIGINAL_AFTER_SPLIT" == "true" ]; then
        if [ ${#created_files[@]} -gt 0 ]; then
            rm -f "$input_file"
            if [ $? -eq 0 ]; then
                echo "  DELETED: $input_file (original file)"
            else
                echo "    ERROR: $variable_name - failed to delete original file ($input_file)"
            fi
        else
            echo "    WARNING: $variable_name - no files created, keeping original"
        fi
    elif ! $all_successful; then
        echo "    WARNING: $variable_name - errors occurred, keeping original file"
    fi
}

# Main processing
script_dir=$(pwd)
echo "Script directory: $script_dir"
echo "Output directory root: $output_directory_root"
echo "Run frequency: $run_frequency"
echo "Overwrite existing: $OVERWRITE_YEARLY_FILES"
echo "Delete original after split: $DELETE_ORIGINAL_AFTER_SPLIT"
echo "Parallel processes: $MAX_PARALLEL_SPLIT"
if [ -n "$TEST_VARIABLE" ]; then
    echo "TEST MODE: Processing only variable '$TEST_VARIABLE'"
fi
echo

# Initialize error log
> ${script_dir}/nco_split_errors.log

# Process each experiment
for ((i=1; i<=${#exps_out[@]}; i++)); do
    exp_out=${exps_out[i-1]}
    exp_dir="${output_directory_root}/${exp_out}"
    
    if [ ! -d "$exp_dir" ]; then
        echo "WARNING: Directory not found: $exp_dir"
        continue
    fi
    
    echo "EXPERIMENT: $exp_out"
    echo "  Processing directory: $exp_dir"
    
    # Find .nc files in this directory (excluding already split yearly files)
    # Exclude files that already have year pattern (4 digits before .nc)
    if [ -n "$TEST_VARIABLE" ]; then
        # Test mode: only process file for the specified variable
        # Construct pattern: {experiment}.{variable}.{frequency}.nc
        test_file_pattern="${exp_out}.${TEST_VARIABLE}.${run_frequency}.nc"
        mapfile -t nc_files < <(find "$exp_dir" -maxdepth 1 -name "$test_file_pattern" -type f)
        echo "  TEST MODE: Looking for variable '$TEST_VARIABLE' (file: $test_file_pattern)"
    else
        # Normal mode: process all .nc files
        mapfile -t nc_files < <(find "$exp_dir" -maxdepth 1 -name "*.nc" -type f ! -regex '.*\.[0-9]{4}\.nc$')
    fi
    
    if [ ${#nc_files[@]} -eq 0 ]; then
        echo "  No files to process (or all files already split)"
        echo
        continue
    fi
    
    echo "  Found ${#nc_files[@]} file(s) to process"
    echo
    
    # Export function and variables for parallel execution
    export -f split_file_by_year
    export -f get_time_info
    export -f extract_base_year
    export -f verify_netcdf_file
    export OVERWRITE_YEARLY_FILES
    export DELETE_ORIGINAL_AFTER_SPLIT
    export run_frequency
    export script_dir
    export OUTPUT_LOG
    
    # Process files in parallel
    # Extract variable name from filename pattern: {exp}.{variable}.{freq}.nc
    # Redirect output from parallel processes to the log file
    printf '%s\n' "${nc_files[@]}" | xargs -P $MAX_PARALLEL_SPLIT -I {} bash -c 'f="{}"; var=$(basename "$f" .nc | cut -d. -f2); split_file_by_year "$f" "'"$script_dir"'" "$var"' >> "$OUTPUT_LOG" 2>&1
    
    echo
    echo "COMPLETED: $exp_out"
    echo
done

echo "SCRIPT COMPLETED"
echo "Check nco_split_errors.log for any errors"
echo

