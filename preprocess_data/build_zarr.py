"""
Build Zarr stores from iCESM NetCDF outputs.

Reads experiment data by frequency and variable, merges with static coordinates,
and writes consolidated Zarr stores for downstream analysis.

Completion state is tracked in a JSON file (zarr_build_completion.json) in
./completion_checks/ so previously completed (frequency, experiment) pairs are skipped.
"""

import argparse
import json
import logging
import os

import xarray as xr  # type: ignore

from utils.path_utils import (
    get_variables_for_experiment,
    load_config,
)

COMPLETION_DIR = 'completion_checks'
COMPLETION_FILENAME = 'zarr_build_completion.json'
LOG = logging.getLogger(__name__)


def setup_logging(log_file):
    """
    Configure logging to write to the specified file under ./logs/.
    Creates the log directory if it does not exist.
    """
    log_path = log_file
    log_dir = os.path.dirname(log_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        handlers=[
            logging.FileHandler(log_path, mode='a'),
            logging.StreamHandler(),
        ],
        force=True,
    )


def completion_path():
    """Path to the JSON file tracking which (frequency, experiment) stores are complete."""
    return os.path.join(COMPLETION_DIR, COMPLETION_FILENAME)


def load_completion_state(frequencies=None, experiments=None):
    """
    Load completion state from JSON, with optional full set of (frequency, experiment) keys.

    If frequencies and experiments are provided, the returned dict has a key for every
    pair (value False by default), overlain with any True values from the file.
    Returns a dict mapping keys 'experiment|frequency' -> bool.
    """
    default = {}
    if frequencies is not None and experiments is not None:
        default = {
            completion_key(exp, freq): False
            for freq in frequencies
            for exp in experiments
        }
    path = completion_path()
    if not os.path.isfile(path):
        return default
    with open(path, 'r') as f:
        on_disk = json.load(f)
    default.update(on_disk)
    return default


def save_completion_state(state):
    """Write completion state to JSON in ./completion_checks/."""
    os.makedirs(COMPLETION_DIR, exist_ok=True)
    path = completion_path()
    with open(path, 'w') as f:
        json.dump(state, f, indent=2)


def completion_key(experiment, frequency):
    """Canonical key for a (frequency, experiment) pair in the completion state."""
    return f'{experiment}|{frequency}'


def is_store_complete(state, experiment, frequency):
    """Return True if the zarr store for this (experiment, frequency) is marked complete."""
    return state.get(completion_key(experiment, frequency), False)


def get_filepath_glob(dir_root, frequency, experiment, variable):
    """Return glob pattern for NetCDF files of a given experiment/variable/frequency."""
    # Path layout: dir_root/frequency/experiment/variable/*.nc
    dirname = os.path.join(dir_root, frequency, experiment, variable)
    fileglob = f'{experiment}.{variable}.{frequency}.????.nc'
    pathglob = os.path.join(dirname, fileglob)
    return pathglob


def get_static_variable_ds(
    dir_root,
    frequency='mon',
    experiment='iso-piControl-tag',
    variable_example='T',
):
    """
    Load static vertical/hybrid coordinate variables from an example variable.

    Returns a dataset with hyai, hyam, hybi, hybm, P0 at a single time step.
    """
    pathglob = get_filepath_glob(dir_root, frequency, experiment, variable_example)
    ds = xr.open_mfdataset(pathglob, data_vars='all')
    # Keep only hybrid level coords and surface pressure; one time step is enough
    return ds[['hyai', 'hyam', 'hybi', 'hybm', 'P0']].isel(time=0).drop_vars('time')


def set_attrs_ds(ds, experiment, frequency):
    """Set standard attributes on the dataset (conventions, experiment, frequency)."""
    # Retain only CF/conventions and source for final metadata
    ds.attrs = {
        k: ds.attrs[k]
        for k in ['Conventions', 'source']
        if k in ds.attrs
    }
    ds.attrs['experiment'] = experiment
    # Add extra metadata
    if frequency == 'mon':
        ds.attrs['output_frequency'] = 'monthly'
    elif frequency == 'day':
        ds.attrs['output_frequency'] = 'daily'
    ds.attrs['created_by'] = 'Kyle Heyblom'
    return ds


def set_ds_base(dir_root, experiment, frequency):
    """Build base dataset with static coordinates and global attributes."""
    # Use 'T' as a representative variable that has hybrid coords in all runs
    ds = get_static_variable_ds(
        dir_root, frequency, experiment, variable_example='T'
    )
    ds = set_attrs_ds(ds, experiment, frequency)
    return ds


def main(settings):
    """
    Build Zarr stores for each (frequency, experiment) from NetCDF variables.

    Reads variables per experiment/frequency, merges with static coords,
    chunks by time, and writes to directory_root/{experiment}.{frequency}.zarr.
    Previously completed (frequency, experiment) pairs are skipped using
    zarr_build_completion.json in directory_root.
    """
    frequencies = settings['frequencies']
    experiments = settings['experiments']
    directory_root = settings['directory_root']
    log_file = settings.get('log_file', 'logs/build_zarr.log')

    setup_logging(log_file)
    LOG.info('Starting Zarr build: directory_root=%s', directory_root)

    completion_state = load_completion_state(
        frequencies=frequencies,
        experiments=experiments,
    )

    for frequency in frequencies:
        for experiment in experiments:

            if is_store_complete(completion_state, experiment, frequency):
                LOG.info('Skipping %s.%s.zarr (already complete)', experiment, frequency)
                continue

            LOG.info('Building %s.%s.zarr', experiment, frequency)

            variables, variables_output_map = get_variables_for_experiment(
                experiment, frequency
            )
            # Start with static coords and global attrs
            ds = set_ds_base(directory_root, experiment, frequency)

            for variable in variables:
                LOG.info('  processing variable: %s', variable)

                # Get pathglob for input NetCDF files
                pathglob = get_filepath_glob(
                    directory_root, frequency, experiment, variable
                )
                # Load all variables and sort by time
                ds_var = xr.open_mfdataset(pathglob, data_vars='all')
                ds_var = ds_var.sortby('time')
                time_bnds = ds_var['time_bnds'].load()

                # For monthly, use interval start (first bound) as canonical time
                if frequency == 'mon':
                    ds_var['time'] = time_bnds[:, 0]

                # Keep only this variable and map to desired output name
                ds_var = ds_var[variable]
                ds_var = ds_var.rename(variables_output_map[variable])

                # Chunk by time for efficient I/O (~15–38 MB per chunk)
                if frequency == 'day':
                    if 'lev' in ds_var.dims or 'ilev' in ds_var.dims:
                        ds_var = ds_var.chunk({'time': 5})   # ~32 MB
                    else:
                        ds_var = ds_var.chunk({'time': 73})  # ~15 MB
                elif frequency == 'mon':
                    if 'lev' in ds_var.dims or 'ilev' in ds_var.dims:
                        ds_var = ds_var.chunk({'time': 6})   # ~38 MB
                    else:
                        ds_var = ds_var.chunk({'time': 120})  # ~25 MB
                else:
                    raise ValueError(f'Invalid frequency: {frequency}')

                # Merge this variable with the base dataset
                ds = xr.merge([ds, ds_var])

            # One Zarr store per (experiment, frequency) in directory_root
            pathname_out = os.path.join(
                directory_root,
                experiment,
                f'{experiment}.{frequency}.zarr',
            )
            # Write Zarr store
            LOG.info('Writing %s', pathname_out)
            ds.to_zarr(store=pathname_out, mode='w')
            LOG.info('Wrote %s', pathname_out)

            # Mark this (frequency, experiment) as complete
            completion_state[completion_key(experiment, frequency)] = True
            save_completion_state(completion_state)

    LOG.info('Zarr building finished')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Build Zarr stores from experiment NetCDF outputs.'
    )
    parser.add_argument(
        '--config',
        type=str,
        required=True,
        help='Path to YAML configuration file.',
    )
    args = parser.parse_args()
    settings = load_config(args.config)
    main(settings)
