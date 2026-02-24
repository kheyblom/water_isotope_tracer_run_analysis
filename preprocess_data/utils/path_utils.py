"""Path and variable-list utilities matching pulldata.sh logic."""

from __future__ import annotations

import re
from pathlib import Path
import yaml # type: ignore

from typing import TypedDict

def _normalize_tag_padded(tag: str) -> str:
    """
    Convert a LAT/LON tag to zero-padded form: 2 digits for LAT, 3 for LON.

    E.g. LAT5S -> LAT05S, LAT85S unchanged; LON05E -> LON005E, LON355E unchanged.
    Non-matching strings are returned unchanged.
    """
    match = re.match(r"^(LAT|LON)(\d+)([SNEW])$", tag, re.IGNORECASE)
    if not match:
        return tag
    prefix, num, direction = match.groups()
    width = 2 if prefix.upper() == "LAT" else 3
    return f"{prefix.upper()}{int(num):0{width}d}{direction.upper()}"


def get_variables_for_experiment(
    experiment: str,
    frequency: str,
    *,
    assets_dir: Path | None = None,
) -> tuple[list[str], dict[str, str]]:
    """
    Return a list of variable names and a mapping to their normalized names.

    Uses the same logic as pulldata.sh build_vars_for_experiment():
    - Vanilla CSV is chosen by frequency (mon -> vanilla_month, day -> vanilla_day).
    - Classification (both / tag / no_tag) and experiment type (use_tags = 'tag' in experiment)
      determine which vanilla variables are included.
    - If use_tags, tag-derived variables are added from variables_to_preprocess_tag.csv
      with prefix/suffix combinations.

    The second list is like the first except tag-derived names use zero-padded format
    for the LAT/LON part: 2 digits for LAT (e.g. LAT5S -> LAT05S), 3 for LON
    (e.g. LON05E -> LON005E).

    Parameters
    ----------
    experiment : str
        Experiment name (e.g. 'iso-piControl-tag'). If it contains 'tag', tag variables are included.
    frequency : str
        'mon' or 'day'.
    assets_dir : Path, optional
        Directory containing the variable CSV files. Defaults to preprocess_data/assets
        relative to this module.

    Returns
    -------
    tuple[list[str], dict[str, str]]
        (variables, variable_to_normalized): list of original variable names (sorted by
        normalized name), and a dict mapping each variable to its normalized form (LAT
        {N:02d}, LON {N:03d} for tag-derived names).
    """
    if assets_dir is None:
        assets_dir = Path(__file__).resolve().parent.parent / "assets"

    if frequency == "mon":
        variable_csv_vanilla = assets_dir / "variables_to_preprocess_vanilla_month.csv"
    elif frequency == "day":
        variable_csv_vanilla = assets_dir / "variables_to_preprocess_vanilla_day.csv"
    else:
        raise ValueError(f"Invalid frequency: {frequency}")

    use_tags = "tag" in experiment
    variable_csv_tag = assets_dir / "variables_to_preprocess_tag.csv"

    variables: list[str] = []
    variables_normalized: list[str] = []

    # 1. Parse vanilla CSV: variable_name, classification (both | tag | no_tag)
    with open(variable_csv_vanilla) as f:
        for line in f:
            line = line.strip().rstrip("\r")
            if not line:
                continue
            parts = line.split(",", 1)
            var_name = parts[0].strip()
            classification = (parts[1].strip() if len(parts) > 1 else "").rstrip("\r")
            if classification == "both":
                variables.append(var_name)
                variables_normalized.append(var_name)
            elif use_tags and classification == "tag":
                variables.append(var_name)
                variables_normalized.append(var_name)
            elif not use_tags and classification == "no_tag":
                variables.append(var_name)
                variables_normalized.append(var_name)

    # 2. Add tag-derived variables if use_tags (prefix/suffix combos from pulldata.sh)
    if use_tags:
        tags = []
        with open(variable_csv_tag) as f:
            for line in f:
                tag = line.strip().rstrip("\r")
                if tag:
                    tags.append(tag)
        tags_pref = ["", "PRECRC_", "PRECRL_", "PRECSC_", "PRECSL_"]
        tags_suff = ["V", "r", "R", "s", "S"]
        for pref, suff in zip(tags_pref, tags_suff):
            for tag in tags:
                variables.append(f"{pref}{tag}{suff}")
                tag_norm = _normalize_tag_padded(tag)
                variables_normalized.append(f"{pref}{tag_norm}{suff}")

    # Sort by variables_normalized and apply same order to variables
    pairs = sorted(zip(variables_normalized, variables))
    variables = [p[1] for p in pairs]
    variables_normalized = [p[0] for p in pairs]
    variable_to_normalized = dict(zip(variables, variables_normalized))

    return variables, variable_to_normalized

def load_config(file_path: str) -> ConfigDict:
    """Load YAML configuration from a file.

    Args:
        file_path (str): Path to the YAML configuration file.

    Returns:
        dict: The loaded configuration.
    """
    with open(file_path, 'r', encoding='utf-8') as file:
        config = yaml.safe_load(file)
    return config
