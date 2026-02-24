#!/bin/bash
#PBS -A UMIC0112
#PBS -N build_zarr
#PBS -q main
#PBS -l walltime=11:59:00
#PBS -l select=1:ncpus=8:mpiprocs=8:mem=32GB
#PBS -m abe
#PBS -M kyle.heyblom@gmail.com

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate icesm_preprocess_data

python build_zarr.py --config config/config_build_zarr.yaml