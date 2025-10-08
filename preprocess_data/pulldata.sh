#!/bin/bash 

echo "Script started at $(date)"
echo "Hostname: $(hostname)"
echo $(hostname) > pulldata.hostname
echo "Main script PID: $$"
echo $$ > pulldata.pid
module load nco
echo "NCO module loaded"

# Load configuration
if [ -f "pulldata.conf" ]; then
    echo "Loading configuration from pulldata.conf"
    source pulldata.conf
else
    echo "ERROR: pulldata.conf not found!"
    exit 1
fi

# Set up variable CSV file based on run frequency
if [ "$run_frequency" == "mon" ]; then
        variable_csv_vanilla=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla_month.csv
elif [ "$run_frequency" == "day" ]; then
        variable_csv_vanilla=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla_day.csv
else
        echo "INVALID RUN FREQUENCY: $run_frequency"
        exit 1
fi

# Simple cleanup function to remove PID file and temp files on exit
cleanup() {
    rm -f pulldata.pid
    rm -f pulldata.hostname
    
    # Clean up any ncrcat temporary files in the output directory
    if [ -n "$output_directory_root" ]; then
        find "$output_directory_root" -name "*.ncrcat.tmp" -delete 2>/dev/null
    fi
}

# Set up signal handlers
trap cleanup EXIT

# Function to check if output file should be processed
check_output_file() {
    local output_file=$1
    local var=$2
    
    if [[ -f "$output_file" && "$OVERWRITE_PROCESSED_DATA" == "false" ]]; then
        return 1
    else
        return 0
    fi
}

# Function to process a single variable
process_variable() {
    local var=$1
    local exp_in=$2
    local exp_out=$3
    local freq=$4
    local out_dir=$5
    local script_dir=$6
    
    output_file="${out_dir}/${exp_out}.${var}.${freq}.nc"
    if check_output_file "$output_file" "$var"; then
        echo "  EXTRACTING: $var"
        if [ "$freq" == "mon" ]; then
            ncrcat -O -v $var ${exp_in}.cam.h0.*.nc $output_file 2>${script_dir}/nco_errors.log
        elif [ "$freq" == "day" ]; then
            ncrcat -O -v $var ${exp_in}.cam.h1.*.nc $output_file 2>${script_dir}/nco_errors.log
        fi
        echo "  COMPLETED: $var"
    else
        echo "  SKIPPING: $var (file already exists)"
    fi
}

# Function to build variables array for an experiment
build_vars_for_experiment() {
    local use_tags=$1
    local vars=()
    
    # Parse vanilla CSV file with two columns: variable_name,classification
    while IFS=',' read -r var_name classification || [[ -n "$var_name" ]]; do
        # Skip empty lines
        [[ -z "$var_name" ]] && continue
        # Strip carriage return characters (Windows line endings)
        var_name="${var_name%$'\r'}"
        classification="${classification%$'\r'}"
        
        # Always add variables with "both" classification
        if [[ "$classification" == "both" ]]; then
            vars+=("$var_name")
        # Add variables with "tag" classification if use_tags is true
        elif $use_tags && [[ "$classification" == "tag" ]]; then
            vars+=("$var_name")
        # Add variables with "no_tag" classification if use_tags is false
        elif ! $use_tags && [[ "$classification" == "no_tag" ]]; then
            vars+=("$var_name")
        fi
    done < $variable_csv_vanilla
    
    # Add tag variables if requested
    if $use_tags; then
        # Read all tags from CSV (one tag per line, no header)
        local tags=()
        while IFS= read -r tag || [[ -n "$tag" ]]; do
            # Skip empty lines
            [[ -z "$tag" ]] && continue
            # Strip carriage return characters (Windows line endings)
            tag="${tag%$'\r'}"
            tags+=("$tag")
        done < $variable_csv_tag
        
        # Define prefix and suffix combinations (matching original logic)
        local tags_pref=(""  "PRECRC_" "PRECRL_" "PRECSC_" "PRECSL_")
        local tags_suff=("V" "r"       "R"       "s"       "S")
        
        # Apply each prefix/suffix combination to all tags
        for ((i=0; i<${#tags_pref[@]}; i++)); do
            for tag in ${tags[*]}; do
                vars+=(${tags_pref[i]}${tag}${tags_suff[i]})
            done
        done
    fi
    
    # Return the variables array
    echo "${vars[@]}"
}

echo
for ((i=1; i<=${#exps_out[@]}; i++)); do
        echo "EXPERIMENT: "${exps_in[i-1]}
        echo
        echo "  Using tag variables: ${exps_use_tags[i-1]}"
        
        # Build variables array for this experiment
        vars=($(build_vars_for_experiment ${exps_use_tags[i-1]}))
        echo "  Total variables: ${#vars[@]}"
        
        in_dir=${input_directory_root}/${exps_in[i-1]}/cam/${run_frequency}
        script_dir=$(pwd)
        cd $in_dir

        out_dir=${output_directory_root}/${exps_out[i-1]}
        mkdir -p $out_dir
        
        # Export the function and variables for parallel execution
        export -f process_variable
        export -f check_output_file
        export OVERWRITE_PROCESSED_DATA
        export run_frequency
        export script_dir
        export exps_in
        export exps_out
        export out_dir
        export i
        
        # Run variables in parallel with job control
        echo "  Starting parallel processing with $MAX_PARALLEL_PROCESSES processes..."
        echo "  Output directory: $out_dir"
        echo
        printf '%s\n' "${vars[@]}" | xargs -P $MAX_PARALLEL_PROCESSES -I {} bash -c "process_variable '{}' '${exps_in[i-1]}' '${exps_out[i-1]}' '$run_frequency' '$out_dir' '$script_dir'"
        echo "  Completed processing for experiment: ${exps_in[i-1]}"
        echo
done
echo "COMPLETE"
echo
