#!/bin/bash
#PBS -A UMIC0112
#PBS -N split_by_year
#PBS -q main
#PBS -l walltime=11:59:00
#PBS -l select=1:ncpus=32:mpiprocs=32:mem=128GB
#PBS -m abe
#PBS -M kyle.heyblom@gmail.com

./split_by_year.sh
