#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== HARVEST CRON JOB ==="

# cd to the directory of this script
my_dir="$(dirname "$(readlink -f "$0")")"
echo $my_dir
cd $my_dir
pwd

# Ensure the cronout folder exists
mkdir -p cronout

# cd to the wwcs/WWCS (usually ~/wwcs/WWCS), where .Rprofile lives
cd ../..
pwd

# ensure all data directories exist
mkdir -p harvest/appdata harvest/appdata/noaa_star harvest/appdata/noaa_raster

echo "=== RETRIEVE NOAA STAR DATA ==="
../../venv/bin/python3 -u ${my_dir}/noaa_star/get_noaa_star.py > ${my_dir}/cronout/get_noaa.out

echo "=== POSTPROCESS NOAA STAR ==="
R CMD BATCH ${my_dir}/noaa_star/process_noaa_star.R ${my_dir}/cronout/process_noaa.out

echo "=== CALCULATE HARVEST ADVICE ==="
R CMD BATCH --no-save ${my_dir}/harvest.R ${my_dir}/cronout/harvest.out

echo "___ DONE ___"
