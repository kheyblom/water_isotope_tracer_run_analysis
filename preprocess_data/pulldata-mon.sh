#!/bin/bash 

input_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/raw
output_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/processed/mon

variable_csv_vanilla=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla.csv
variable_csv_tag=/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_tag.csv

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
        in_dir=${input_directory_root}/${exps_in[i-1]}/cam/mon
        cd $in_dir
        for var in "${vars[@]}"; do
                output_file="${out_dir}/${exps_out[i-1]}.${var}.mon.nc"
                if [[ -f "$output_file" ]]; then
                        echo "  SKIPPING: $var (file already exists)"
                else
                        echo "  EXTRACTING: $var"
                        ncrcat -O -v $var ${exps_in[i-1]}.cam.h0.*.nc $output_file
                fi
        done
done
echo "COMPLETE"
echo
