#!/usr/bin/env python3
"""
Script to add CF convention standard names to variable_list.csv
"""

import csv
import re

# Mapping dictionary: variable name -> CF standard name
# Based on long names and CF conventions
CF_MAPPINGS = {
    # Aerosol
    'AEROD_v': 'atmosphere_optical_thickness_due_to_aerosol',
    
    # Cloud microphysics
    'ANRAIN': 'number_concentration_of_rain_particles_in_air',
    'ANSNOW': 'number_concentration_of_snow_particles_in_air',
    'AREI': 'effective_radius_of_cloud_ice_particles',
    'AREL': 'effective_radius_of_cloud_liquid_water_particles',
    'AWNC': 'number_concentration_of_cloud_liquid_water_particles_in_air',
    'AWNI': 'number_concentration_of_cloud_ice_particles_in_air',
    
    # Cloud fraction
    'CLDHGH': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDLOW': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDMED': 'cloud_area_fraction_in_atmosphere_layer',
    'CLDTOT': 'cloud_area_fraction',
    'CLOUD': 'cloud_area_fraction_in_atmosphere_layer',
    
    # Tendencies
    'DCQ': 'tendency_of_specific_humidity_due_to_moist_processes',
    'DTCOND': 'tendency_of_air_temperature_due_to_moist_processes',
    
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
    'FSNTC': 'toa_net_upward_shortwave_flux_assuming_clear_sky',
    'FSNTOA': 'toa_net_upward_shortwave_flux',
    'FSNTOAC': 'toa_net_upward_shortwave_flux_assuming_clear_sky',
    'FSUTOA': 'toa_outgoing_shortwave_flux',
    
    # Surface fractions
    'ICEFRAC': 'sea_ice_area_fraction',
    'LANDFRAC': 'land_area_fraction',
    
    # Heat fluxes
    'LHFLX': 'surface_upward_latent_heat_flux',
    'SHFLX': 'surface_upward_sensible_heat_flux',
    
    # Cloud forcing
    'LWCF': 'toa_longwave_cloud_forcing',
    'SWCF': 'toa_shortwave_cloud_forcing',
    
    # Vertical velocity
    'OMEGA': 'lagrangian_tendency_of_air_pressure',
    'WSUB': 'upward_air_velocity',  # Diagnostic sub-grid vertical velocity - using base vertical velocity
    
    # Boundary layer
    'PBLH': 'atmosphere_boundary_layer_thickness',
    
    # Precipitation
    'PRECC': 'convective_precipitation_flux',
    'PRECL': 'large_scale_precipitation_flux',
    'PRECSC': 'convective_snowfall_flux',
    'PRECSL': 'large_scale_snowfall_flux',
    
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

def get_cf_standard_name(var_name, long_name):
    """
    Get CF standard name for a variable based on its name and long name.
    """
    # First check direct mapping
    if var_name in CF_MAPPINGS:
        return CF_MAPPINGS[var_name]
    
    # Pattern matching for isotope variables
    # These typically don't have official CF standard names
    if 'isotope' in long_name.lower() or 'mmr' in long_name.lower():
        # For isotope mass mixing ratios, there's no official CF standard name
        # but we can use a pattern following CF conventions
        # Check both variable name and long name for isotope indicators
        is_isotope = ('H216O' in var_name or 'H218O' in var_name or 'H2O' in var_name or 'HDO' in var_name or
                     'H216O' in long_name or 'H218O' in long_name or 'H2O' in long_name or 'HDO' in long_name or
                     var_name.startswith('LAT') or var_name.startswith('LON'))
        
        if is_isotope:
            if 'VAPOR' in long_name:
                return 'mass_fraction_of_water_vapor_in_air'  # Base name, isotope-specific not in CF
            elif 'ICE' in long_name:
                return 'mass_fraction_of_cloud_ice_in_air'  # Base name
            elif 'LIQUID' in long_name:
                return 'mass_fraction_of_cloud_liquid_water_in_air'  # Base name
            elif 'RAIN' in long_name or 'RAINC' in long_name or 'RAINS' in long_name:
                return 'precipitation_flux'  # Base name
            elif 'SNOW' in long_name or 'SNOWC' in long_name or 'SNOWS' in long_name:
                return 'snowfall_flux'  # Base name
        return ''  # Leave blank for isotope-specific variables
    
    # Pattern matching for precipitation rate variables
    if var_name.startswith('PRECRC_') or var_name.startswith('PRECRL_'):
        return 'precipitation_flux'  # Base name, tracer-specific not in CF
    
    if var_name.startswith('PRECSC_') or var_name.startswith('PRECSL_'):
        return 'snowfall_flux'  # Base name, tracer-specific not in CF
    
    if var_name.startswith('PRECT_'):
        return 'precipitation_flux'  # Base name, tracer-specific not in CF
    
    # Pattern matching for QFLX (water flux)
    if var_name.startswith('QFLX_'):
        return 'water_evaporation_flux'  # Base name, tracer-specific not in CF
    
    # Pattern matching for LAT/LON tracer variables
    if var_name.startswith('LAT') or var_name.startswith('LON'):
        if 'VAPOR' in long_name:
            return 'mass_fraction_of_water_vapor_in_air'  # Base name
        elif 'RAIN' in long_name or 'RAINC' in long_name or 'RAINS' in long_name:
            return 'precipitation_flux'  # Base name
        elif 'SNOW' in long_name or 'SNOWC' in long_name or 'SNOWS' in long_name:
            return 'snowfall_flux'  # Base name
        return ''
    
    # Try to infer from long name
    long_lower = long_name.lower()
    
    if 'temperature' in long_lower:
        if 'surface' in long_lower or 'sfc' in long_lower:
            return 'surface_temperature'
        elif 'reference' in long_lower:
            return 'air_temperature'
        else:
            return 'air_temperature'
    
    if 'precipitation' in long_lower or 'precip' in long_lower:
        if 'convective' in long_lower:
            return 'convective_precipitation_flux'
        elif 'large' in long_lower or 'stable' in long_lower:
            return 'large_scale_precipitation_flux'
        else:
            return 'precipitation_flux'
    
    if 'snow' in long_lower:
        if 'convective' in long_lower:
            return 'convective_snowfall_flux'
        elif 'large' in long_lower or 'stable' in long_lower:
            return 'large_scale_snowfall_flux'
        else:
            return 'snowfall_flux'
    
    if 'humidity' in long_lower:
        return 'specific_humidity'
    
    if 'pressure' in long_lower:
        if 'sea level' in long_lower:
            return 'air_pressure_at_sea_level'
        elif 'surface' in long_lower:
            return 'surface_air_pressure'
        else:
            return 'air_pressure'
    
    if 'wind' in long_lower:
        if 'zonal' in long_lower or 'eastward' in long_lower:
            return 'eastward_wind'
        elif 'meridional' in long_lower or 'northward' in long_lower:
            return 'northward_wind'
    
    if 'cloud' in long_lower:
        if 'fraction' in long_lower:
            return 'cloud_area_fraction'
    
    if 'flux' in long_lower:
        if 'longwave' in long_lower:
            if 'downwelling' in long_lower and 'surface' in long_lower:
                return 'surface_downwelling_longwave_flux_in_air'
            elif 'net' in long_lower and 'surface' in long_lower:
                return 'surface_net_downward_longwave_flux'
            elif 'upwelling' in long_lower and 'top' in long_lower:
                return 'toa_outgoing_longwave_flux'
        elif 'shortwave' in long_lower or 'solar' in long_lower:
            if 'downwelling' in long_lower and 'surface' in long_lower:
                return 'surface_downwelling_shortwave_flux_in_air'
            elif 'net' in long_lower and 'surface' in long_lower:
                return 'surface_net_downward_shortwave_flux'
            elif 'upwelling' in long_lower and 'top' in long_lower:
                return 'toa_outgoing_shortwave_flux'
        elif 'latent' in long_lower:
            return 'surface_upward_latent_heat_flux'
        elif 'sensible' in long_lower:
            return 'surface_upward_sensible_heat_flux'
    
    return ''  # Return empty string if no match found


def process_csv(input_file, output_file):
    """
    Read input CSV, add CF convention column, and write to output CSV.
    """
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
    input_file = '/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/variable_list.csv'
    output_file = '/glade/u/home/kheyblom/work/projects/water_isotope_tracer_run_analysis/preprocess_data/variable_list_with_cf.csv'
    
    process_csv(input_file, output_file)
    
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

