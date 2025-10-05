#!/bin/bash 

module load nco

# run_frequency: mon or day
run_frequency=mon

input_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/raw
output_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/processed/${run_frequency}

variable_csv_vanilla=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla_month.csv
variable_csv_tag=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_tag_month.csv

OVERWRITE_PROCESSED_DATA=false

# raw experiment names
exps_in=("1850-iso-gridtags" \
         "historical-iso-r1" \
         "historical-iso-r2" \
         "historical-iso-r4" \
         "historical-iso-r4-tags" \
         "historical-iso-r4-tags_b" \
         "historical-iso-r5" \
         "historical-iso-r5-tags" \
         "historical-iso-r5-tags_b" \
         "rcp85_r1b" \
         "rcp85_r2" \
         "rcp85_r4" \
         "rcp85_r4-tags_b" \
         "rcp85_r4-tags_c" \
         "rcp85_r5" \
         "rcp85_r5-tags_b" \
         "rcp85_r5-tags_c")

# processed experiment names
exps_out=("iso-piControl-tag" \
          "iso-historical_r1" \
          "iso-historical_r2" \
          "iso-historical_r4" \
          "iso-historical_r4-tag-a" \
          "iso-historical_r4-tag-b" \
          "iso-historical_r5" \
          "iso-historical_r5-tag-a" \
          "iso-historical_r5-tag-b" \
          "iso-rcp85_r1" \
          "iso-rcp85_r2" \
          "iso-rcp85_r4" \
          "iso-rcp85_r4-tag-b" \
          "iso-rcp85_r4-tag-c" \
          "iso-rcp85_r5" \
          "iso-rcp85_r5-tag-b" \
          "iso-rcp85_r5-tag-c")

# define which experiments should use tag variables (true/false for each experiment)
exps_use_tags=(true \
               false \
               false \
               false \
               true \
               true \
               false \
               true \
               true \
               false \
               false \
               false \
               true \
               true \
               false \
               true \
               true)

# Function to check if output file should be processed
check_output_file() {
    local output_file=$1
    local var=$2
    
    if [[ -f "$output_file" && "$OVERWRITE_PROCESSED_DATA" == "false" ]]; then
        echo "  SKIPPING: $var (file already exists)"
        return 1
    else
        echo "  EXTRACTING: $var"
        return 0
    fi
}

# Function to extract unique years from raw files
extract_unique_years() {
    local exp_name=$1
    local years=()
    
    for file in ${exp_name}.cam.h1.*.nc; do
        if [[ -f "$file" ]]; then
            # Extract YYYY from filename pattern: exp.cam.h1.YYYY-MM-DD-00000.nc
            year=$(echo "$file" | sed -n 's/.*\.cam\.h1\.\([0-9]\{4\}\)-[0-9]\{2\}-[0-9]\{2\}-00000\.nc/\1/p')
            if [[ -n "$year" ]]; then
                years+=("$year")
            fi
        fi
    done
    
    # Get unique years and sort them
    unique_years=($(printf '%s\n' "${years[@]}" | sort -u))
    echo "${unique_years[@]}"
}

# Function to build variables array for an experiment
build_vars_for_experiment() {
    local use_tags=$1
    local vars=()
    
    # Always add vanilla variables
    while IFS= read -r var || [[ -n "$var" ]]; do
        # Skip empty lines
        [[ -z "$var" ]] && continue
        # Strip carriage return characters (Windows line endings)
        var="${var%$'\r'}"
        vars+=("$var")
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
        echo "  Using tag variables: ${exps_use_tags[i-1]}"
        
        # Build variables array for this experiment
        vars=($(build_vars_for_experiment ${exps_use_tags[i-1]}))
        echo "  Total variables: ${#vars[@]}"
        
        out_dir=${output_directory_root}/${exps_out[i-1]}
        mkdir -p $out_dir
        in_dir=${input_directory_root}/${exps_in[i-1]}/cam/${run_frequency}
        cd $in_dir
        for var in "${vars[@]}"; do
                if [ "$run_frequency" == "mon" ]; then
                        output_file="${out_dir}/${exps_out[i-1]}.${var}.${run_frequency}.nc"
                        if check_output_file "$output_file" "$var"; then
                                ncrcat -O -v $var ${exps_in[i-1]}.cam.h0.*.nc $output_file
                        fi
                elif [ "$run_frequency" == "day" ]; then
                        # Extract unique YYYY values from files in $in_dir
                        unique_years=($(extract_unique_years ${exps_in[i-1]}))
                        for year in "${unique_years[@]}"; do
                                output_file="${out_dir}/${exps_out[i-1]}.${var}.${run_frequency}.${year}.nc"
                                if check_output_file "$output_file" "$var"; then
                                        echo "ncrcat -O -v $var ${exps_in[i-1]}.cam.h1.${year}-*.nc $output_file"
                                        # ncrcat -O -v $var ${exps_in[i-1]}.cam.h1.${year}-*.nc $output_file
                                fi
                        done
                else
                        echo "  INVALID RUN FREQUENCY: $run_frequency"
                        exit 1
                fi
        done
done
echo "COMPLETE"
echo
