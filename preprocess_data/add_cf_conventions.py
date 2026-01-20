#!/usr/bin/env python3
"""
Script to add CF convention standard names to variable_list.csv
"""

import csv
import os

# Global variables for valid names and aliases
VALID_NAMES = set()
ALIAS_MAP = {}

# Mapping dictionary: variable name -> CF standard name
# Based on long names and CF conventions
# These are initial best guesses, but will be validated against the master list
CF_MAPPINGS = {
    # Aerosol
    'AEROD_v': 'atmosphere_optical_thickness_due_to_ambient_aerosol_particles',
    
    # Cloud microphysics
    'AREI': 'effective_radius_of_stratiform_cloud_ice_particle',
    'AREL': 'effective_radius_of_stratiform_cloud_liquid_water_particle',
    'AWNC': 'number_concentration_of_cloud_liquid_water_particles_in_air',
    'AWNI': 'number_concentration_of_ice_crystals_in_air',
    
    # Cloud fraction
    'CLDHGH': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDLOW': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDMED': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDTOT': 'cloud_area_fraction',
    'CLOUD': 'cloud_area_fraction_in_atmosphere_layer',
    
    # Longwave fluxes
    'FLDS': 'surface_downwelling_longwave_flux_in_air',
    'FLNS': 'surface_net_downward_longwave_flux',
    'FLNSC': 'surface_net_downward_longwave_flux_assuming_clear_sky',
    'FLNT': 'toa_net_upward_longwave_flux',
    'FLNTC': 'toa_net_upward_longwave_flux_assuming_clear_sky',
    'FLUT': 'toa_outgoing_longwave_flux',
    'FLUTC': 'toa_outgoing_longwave_flux_assuming_clear_sky',
    
    # Shortwave fluxes
    'FSDS': 'surface_downwelling_shortwave_flux_in_air',
    'FSDSC': 'surface_downwelling_shortwave_flux_in_air_assuming_clear_sky',
    'FSNS': 'surface_net_downward_shortwave_flux',
    'FSNSC': 'surface_net_downward_shortwave_flux_assuming_clear_sky',
    'FSNT': 'toa_net_upward_shortwave_flux',
    'FSNTC': 'toa_outgoing_shortwave_flux_assuming_clear_sky',
    'FSNTOA': 'toa_net_upward_shortwave_flux',
    'FSNTOAC': 'toa_outgoing_shortwave_flux_assuming_clear_sky',
    'FSUTOA': 'toa_outgoing_shortwave_flux',
    
    # Surface fractions
    'ICEFRAC': 'sea_ice_area_fraction',
    'LANDFRAC': 'land_area_fraction',
    
    # Heat fluxes
    'LHFLX': 'surface_upward_latent_heat_flux',
    'SHFLX': 'surface_upward_sensible_heat_flux',
    
    # Cloud forcing
    'LWCF': 'toa_longwave_cloud_radiative_effect',
    'SWCF': 'toa_shortwave_cloud_radiative_effect',
    
    # Vertical velocity
    'OMEGA': 'lagrangian_tendency_of_air_pressure',
    'WSUB': 'upward_air_velocity',
    
    # Boundary layer
    'PBLH': 'atmosphere_boundary_layer_thickness',
    
    # Precipitation
    'PRECC': 'convective_precipitation_flux',
    'PRECL': 'stratiform_precipitation_flux',
    'PRECSC': 'convective_snowfall_flux',
    'PRECSL': 'stratiform_snowfall_flux',
    
    # Pressure
    'PS': 'surface_air_pressure',
    'PSL': 'air_pressure_at_sea_level',
    
    # Humidity
    'Q': 'specific_humidity',
    'TMQ': 'atmosphere_mass_content_of_water_vapor',
    
    # Surface water flux
    'QFLX': 'water_evaporation_flux',
    
    # Heating rates
    'QRL': 'tendency_of_air_temperature_due_to_longwave_heating',
    'QRS': 'tendency_of_air_temperature_due_to_shortwave_heating',
    
    # Solar
    'SOLIN': 'toa_incoming_shortwave_flux',
    
    # Temperature
    'T': 'air_temperature',
    'TS': 'surface_temperature',
    'TREFHT': 'air_temperature',
    
    # Wind
    'U': 'eastward_wind',
    'V': 'northward_wind',
    
    # Geopotential
    'Z3': 'geopotential_height',
}

def load_cf_master(master_file):
    """
    Load CF standard names and aliases from the master CSV file.
    Populates VALID_NAMES and ALIAS_MAP globals.
    """
    if not os.path.exists(master_file):
        print(f"Warning: CF master file not found at {master_file}")
        return

    print(f"Loading CF master list from {master_file}...")
    try:
        with open(master_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                raw_name = row.get('Standard Name', '').strip()
                primary_name = None
                
                # Parse Standard Name column which may contain multiple values or descriptions
                if raw_name:
                    # Split by newline or comma (some entries have synonyms separated by these)
                    parts = raw_name.replace('\n', ',').split(',')
                    
                    for part in parts:
                        clean_part = part.strip()
                        if not clean_part:
                            continue
                            
                        # Handle cases like: name"Description..."
                        if '"' in clean_part:
                            clean_part = clean_part.split('"')[0].strip()
                        
                        if clean_part:
                            VALID_NAMES.add(clean_part)
                            if primary_name is None:
                                primary_name = clean_part
                
                # Handle aliases
                alias = row.get('alias', '').strip()
                if alias and primary_name:
                    ALIAS_MAP[alias] = primary_name
                    
    except Exception as e:
        print(f"Error loading CF master file: {e}")

    print(f"Loaded {len(VALID_NAMES)} valid names and {len(ALIAS_MAP)} aliases.")

def get_cf_standard_name(var_name, long_name):
    """
    Get CF standard name for a variable based on its name and long name.
    Only returns names present in VALID_NAMES.
    """
    candidate = None

    # 1. Check direct mapping
    if var_name in CF_MAPPINGS:
        candidate = CF_MAPPINGS[var_name]
    
    # 2. Pattern matching for isotope variables
    elif 'isotope' in long_name.lower() or 'mmr' in long_name.lower():
        is_isotope = ('H216O' in var_name or 'H218O' in var_name or 'H2O' in var_name or 'HDO' in var_name or
                     'H216O' in long_name or 'H218O' in long_name or 'H2O' in long_name or 'HDO' in long_name or
                     var_name.startswith('LAT') or var_name.startswith('LON'))
        
        if is_isotope:
            if 'VAPOR' in long_name:
                candidate = 'specific_humidity' # Replaced mass_fraction_of_water_vapor_in_air
            elif 'ICE' in long_name:
                candidate = 'mass_fraction_of_cloud_ice_in_air'
            elif 'LIQUID' in long_name:
                candidate = 'mass_fraction_of_cloud_liquid_water_in_air'
            elif 'RAIN' in long_name or 'RAINC' in long_name or 'RAINS' in long_name:
                candidate = 'precipitation_flux'
            elif 'SNOW' in long_name or 'SNOWC' in long_name or 'SNOWS' in long_name:
                candidate = 'snowfall_flux'
    
    # 3. Pattern matching for specific prefixes
    elif var_name.startswith('PRECRC_') or var_name.startswith('PRECRL_'):
        candidate = 'precipitation_flux'
    elif var_name.startswith('PRECSC_') or var_name.startswith('PRECSL_'):
        candidate = 'snowfall_flux'
    elif var_name.startswith('PRECT_'):
        candidate = 'precipitation_flux'
    elif var_name.startswith('QFLX_'):
        candidate = 'water_evaporation_flux'
    
    # 4. Pattern matching for LAT/LON tracer variables
    elif var_name.startswith('LAT') or var_name.startswith('LON'):
        if 'VAPOR' in long_name:
            candidate = 'specific_humidity'
        elif 'RAIN' in long_name or 'RAINC' in long_name or 'RAINS' in long_name:
            candidate = 'precipitation_flux'
        elif 'SNOW' in long_name or 'SNOWC' in long_name or 'SNOWS' in long_name:
            candidate = 'snowfall_flux'
    
    # 5. Fallback: try to infer from long name keywords
    if not candidate:
        long_lower = long_name.lower()
        if 'temperature' in long_lower:
            if 'surface' in long_lower or 'sfc' in long_lower:
                candidate = 'surface_temperature'
            else:
                candidate = 'air_temperature'
        elif 'precipitation' in long_lower or 'precip' in long_lower:
            if 'convective' in long_lower:
                candidate = 'convective_precipitation_flux'
            elif 'large' in long_lower or 'stable' in long_lower:
                candidate = 'stratiform_precipitation_flux'
            else:
                candidate = 'precipitation_flux'
        elif 'snow' in long_lower:
            if 'convective' in long_lower:
                candidate = 'convective_snowfall_flux'
            elif 'large' in long_lower or 'stable' in long_lower:
                candidate = 'stratiform_snowfall_flux'
            else:
                candidate = 'snowfall_flux'
        elif 'humidity' in long_lower:
            candidate = 'specific_humidity'
        elif 'pressure' in long_lower:
            if 'sea level' in long_lower:
                candidate = 'air_pressure_at_sea_level'
            elif 'surface' in long_lower:
                candidate = 'surface_air_pressure'
            else:
                candidate = 'air_pressure'
        elif 'wind' in long_lower:
            if 'zonal' in long_lower or 'eastward' in long_lower:
                candidate = 'eastward_wind'
            elif 'meridional' in long_lower or 'northward' in long_lower:
                candidate = 'northward_wind'
        elif 'cloud' in long_lower:
            if 'fraction' in long_lower:
                candidate = 'cloud_area_fraction'

    # Validate and resolve aliases
    if candidate:
        # Check if it is a valid name directly
        if candidate in VALID_NAMES:
            return candidate
        
        # Check if it is an alias
        if candidate in ALIAS_MAP:
            return ALIAS_MAP[candidate]
            
        # Try best match via alias logic (e.g., if we mapped PRECL to large_scale_... which is an alias)
        # (This is handled by ALIAS_MAP check above)

        # If still not found, return empty string as per strict requirement
        # print(f"Warning: Proposed name '{candidate}' for '{var_name}' not found in CF master list.")
        return ''
        
    return ''


def process_csv(input_file, output_file, master_file):
    """
    Read input CSV, add CF convention column, and write to output CSV.
    """
    # Load master list first
    load_cf_master(master_file)

    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8', newline='') as outfile:
        
        reader = csv.DictReader(infile)
        fieldnames = reader.fieldnames
        
        # Ensure CF convention column exists
        if 'CF convention' not in fieldnames:
            fieldnames = list(fieldnames) + ['CF convention']
        
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        
        for row in reader:
            var_name = row.get('variable name', '').strip()
            long_name = row.get('long name', '').strip()
            
            # Get CF standard name
            cf_name = get_cf_standard_name(var_name, long_name)
            row['CF convention'] = cf_name
            
            writer.writerow(row)
    
    print(f"Processed {input_file}")
    print(f"Output written to {output_file}")


if __name__ == '__main__':
    base_dir = '/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data'
    input_file = os.path.join(base_dir, 'variable_list.csv')
    output_file = os.path.join(base_dir, 'variable_list_with_cf.csv')
    master_file = os.path.join(base_dir, 'cf_names_master.csv')
    
    process_csv(input_file, output_file, master_file)
    
    # Print summary
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        total = 0
        filled = 0
        for row in reader:
            total += 1
            if row.get('CF convention', '').strip():
                filled += 1
    
    print(f"\nSummary:")
    print(f"  Total variables: {total}")
    print(f"  Variables with CF standard names: {filled}")
    print(f"  Variables without CF standard names: {total - filled}")
