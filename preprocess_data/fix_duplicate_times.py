"""Remove duplicate time steps from iso-rcp85_r5 daily 2006 files.

Keeps only the first occurrence of each time value and overwrites in place.
"""

import sys
from pathlib import Path

import numpy as np
import xarray as xr

BASE_DIR = Path(
    "/glade/u/home/kheyblom/scratch/icesm_data/processed/day/iso-rcp85_r5"
)
PATTERN = "iso-rcp85_r5.{var}.day.2006.nc"


def first_unique_time_indices(time_values):
    """Return indices of the first occurrence of each unique time value."""
    seen = set()
    indices = []
    for i, t in enumerate(time_values):
        if t not in seen:
            seen.add(t)
            indices.append(i)
    return np.array(indices)


def fix_file(filepath: Path) -> None:
    ds = xr.open_dataset(filepath)
    n_total = ds.sizes["time"]
    keep = first_unique_time_indices(ds.time.values)
    n_unique = len(keep)

    if n_unique == n_total:
        print(f"  SKIP  {filepath.name} — no duplicates ({n_total} times)")
        ds.close()
        return

    print(
        f"  FIX   {filepath.name} — {n_total} → {n_unique} times "
        f"(dropping {n_total - n_unique} duplicates)"
    )

    ds_fixed = ds.isel(time=keep)
    tmp = filepath.with_suffix(".tmp.nc")
    ds_fixed.to_netcdf(tmp, unlimited_dims=["time"])
    ds.close()
    ds_fixed.close()
    tmp.rename(filepath)


def main():
    var_dirs = sorted(p for p in BASE_DIR.iterdir() if p.is_dir())
    print(f"Found {len(var_dirs)} variable directories under {BASE_DIR}\n")

    failed = []
    for var_dir in var_dirs:
        var = var_dir.name
        filepath = var_dir / PATTERN.format(var=var)
        if not filepath.exists():
            print(f"  MISS  {filepath.name} — file not found")
            continue
        try:
            fix_file(filepath)
        except Exception as e:
            print(f"  ERR   {filepath.name} — {e}", file=sys.stderr)
            failed.append(var)

    if failed:
        print(f"\nFailed variables: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)
    else:
        print("\nDone — all files processed successfully.")


if __name__ == "__main__":
    main()
