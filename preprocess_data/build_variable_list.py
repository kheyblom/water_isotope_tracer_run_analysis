#!/usr/bin/env python3
"""
Script to build a CSV file with variable information including:
- Variable name
- Long name (from NetCDF metadata)
- CF convention (blank)
- Dimensions ([lat, lon] or [lat, lon, lev])
- Output frequency ([month], [day], or [month, day])
"""

import csv
import subprocess
import os
import sys

# File locations to check in order
FILE_LOCATIONS = [
    ("mon", "iso-piControl-tag"),
    ("day", "iso-piControl-tag"),
    ("mon", "iso-historical_r1"),
    ("day", "iso-historical_r1"),
]

def get_variable_file_path(var_name, frequency, experiment):
    """Get the full path to a variable file."""
    base_dir = f"/glade/u/home/kheyblom/scratch/icesm_data/processed/{frequency}/{experiment}"
    var_dir = os.path.join(base_dir, var_name)
    freq_str = 'mon' if frequency == 'mon' else 'day'
    return os.path.join(var_dir, f"{experiment}.{var_name}.{freq_str}.0030.nc")

def find_variable_file(var_name):
    """Find the first existing file for a variable in the specified order.
    Returns (file_path, frequency, experiment) or (None, None, None) if not found.
    """
    for frequency, experiment in FILE_LOCATIONS:
        file_path = get_variable_file_path(var_name, frequency, experiment)
        if os.path.exists(file_path):
            return file_path, frequency, experiment
    return None, None, None

def get_variable_metadata(file_path, var_name):
    """Extract long_name and dimensions from NetCDF file."""
    if not os.path.exists(file_path):
        return None, None, False
    
    try:
        # Use ncdump to get variable info
        cmd = ["ncdump", "-h", file_path]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        if result.returncode != 0:
            return None, None, False
        
        output = result.stdout
        long_name = None
        has_lev = False
        
        # Find the variable definition line (could be float or double)
        var_patterns = [f"float {var_name}(", f"double {var_name}("]
        var_found = False
        
        for line in output.split('\n'):
            if any(pattern in line for pattern in var_patterns):
                var_found = True
                # Check if lev is in dimensions
                if 'lev' in line:
                    has_lev = True
                continue
            
            if var_found and 'long_name' in line:
                # Extract long_name value
                if '=' in line:
                    # Get everything after the = sign
                    value_part = line.split('=', 1)[1].strip()
                    # Remove semicolon if present
                    value_part = value_part.rstrip(';').strip()
                    # Remove surrounding quotes if present
                    if value_part.startswith('"') and value_part.endswith('"'):
                        long_name = value_part[1:-1]
                    elif value_part.startswith("'") and value_part.endswith("'"):
                        long_name = value_part[1:-1]
                    else:
                        long_name = value_part
                    break
        
        dimensions = "[lat, lon, lev]" if has_lev else "[lat, lon]"
        return long_name, dimensions, True
    
    except Exception as e:
        print(f"Error processing {var_name}: {e}", file=sys.stderr)
        return None, None, False

def check_variable_files_exist(var_name):
    """Check which files exist for a variable and return frequencies found."""
    frequencies = set()
    for frequency, experiment in FILE_LOCATIONS:
        file_path = get_variable_file_path(var_name, frequency, experiment)
        if os.path.exists(file_path):
            freq_key = 'month' if frequency == 'mon' else 'day'
            frequencies.add(freq_key)
    return frequencies

def build_variable_list():
    """Build complete list of variables from CSV files."""
    variables = {}  # var_name -> {frequencies: set, long_name: str, dimensions: str}
    
    # Read vanilla day CSV
    day_csv = "/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla_day.csv"
    with open(day_csv, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 1 and row[0].strip():
                var_name = row[0].strip()
                if var_name not in variables:
                    variables[var_name] = {'frequencies': set(), 'long_name': None, 'dimensions': None}
                variables[var_name]['frequencies'].add('day')
    
    # Read vanilla month CSV
    month_csv = "/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_vanilla_month.csv"
    with open(month_csv, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 1 and row[0].strip():
                var_name = row[0].strip()
                if var_name not in variables:
                    variables[var_name] = {'frequencies': set(), 'long_name': None, 'dimensions': None}
                variables[var_name]['frequencies'].add('month')
    
    # Read tag CSV and build tag variables
    tag_csv = "/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/assets/variables_to_preprocess_tag.csv"
    tags = []
    with open(tag_csv, 'r') as f:
        for line in f:
            tag = line.strip()
            if tag:
                tags.append(tag)
    
    # Build tag variables with prefixes and suffixes
    tags_pref = ["", "PRECRC_", "PRECRL_", "PRECSC_", "PRECSL_"]
    tags_suff = ["V", "r", "R", "s", "S"]
    
    for prefix in tags_pref:
        for suffix in tags_suff:
            for tag in tags:
                var_name = f"{prefix}{tag}{suffix}"
                if var_name not in variables:
                    variables[var_name] = {'frequencies': set(), 'long_name': None, 'dimensions': None}
                # Tag variables frequency will be determined by checking actual files
    
    return variables

def main():
    # Build variable list
    print("Building variable list from CSV files...")
    all_variables = build_variable_list()
    print(f"Found {len(all_variables)} unique variables from CSV files")
    
    # Extract metadata and check frequencies for each variable
    print("Checking for existing files and extracting metadata...")
    variables_to_keep = {}
    skipped_count = 0
    
    for i, var_name in enumerate(sorted(all_variables.keys()), 1):
        print(f"Processing {i}/{len(all_variables)}: {var_name}")
        
        # Find the first existing file for this variable
        file_path, frequency, experiment = find_variable_file(var_name)
        
        if file_path is None:
            print(f"  Skipping {var_name}: no files found")
            skipped_count += 1
            continue
        
        var_info = all_variables[var_name].copy()
        
        # Check which frequencies exist for this variable
        existing_frequencies = check_variable_files_exist(var_name)
        
        # Update frequencies: use existing files, but also respect CSV frequencies if they exist
        if var_info['frequencies']:
            # Intersect CSV frequencies with existing files
            csv_freqs = var_info['frequencies']
            var_info['frequencies'] = existing_frequencies & csv_freqs
            # If intersection is empty, use existing files
            if not var_info['frequencies']:
                var_info['frequencies'] = existing_frequencies
        else:
            # For tag variables, use frequencies from existing files
            var_info['frequencies'] = existing_frequencies
        
        # Get metadata from the first available file
        long_name, dimensions, _ = get_variable_metadata(file_path, var_name)
        
        if long_name:
            var_info['long_name'] = long_name
        if dimensions:
            var_info['dimensions'] = dimensions
        
        # Only keep variables that have at least one file
        if var_info['frequencies']:
            variables_to_keep[var_name] = var_info
        else:
            print(f"  Skipping {var_name}: no valid frequencies")
            skipped_count += 1
    
    variables = variables_to_keep
    
    # Write CSV file
    output_file = "./variable_list.csv"
    print(f"\nWriting output to {output_file}...")
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['variable name', 'long name', 'CF convention', 'dimensions', 'output frequency'])
        
        for var_name in sorted(variables.keys()):
            var_info = variables[var_name]
            
            # Determine output frequency
            freq_set = var_info['frequencies']
            if 'month' in freq_set and 'day' in freq_set:
                output_freq = "[month, day]"
            elif 'month' in freq_set:
                output_freq = "[month]"
            elif 'day' in freq_set:
                output_freq = "[day]"
            else:
                # Default to month if no frequency found
                output_freq = "[month]"
            
            long_name = var_info['long_name'] or ""
            dimensions = var_info['dimensions'] or "[lat, lon]"  # Default assumption
            cf_convention = ""  # Leave blank as requested
            
            writer.writerow([var_name, long_name, cf_convention, dimensions, output_freq])
    
    print(f"Successfully created {output_file}")
    print(f"Total variables included: {len(variables)}")
    print(f"Variables excluded (no files): {skipped_count}")

if __name__ == "__main__":
    main()
