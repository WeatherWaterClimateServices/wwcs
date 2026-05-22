#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

# cd to the directory of this script
my_dir="$(dirname "$(readlink -f "$0")")"
cd $my_dir
pwd
# Ensure the cronout folder exists
mkdir -p cronout

echo "=== RETRIEVE EMCWF FORECASTS ==="

# use the venv in  venv - this will usually be ~/venv, but may not in dev setups
# ../../../../venv/bin/python3 get_open_meteo/get_open_meteo.py > cronout/open-meteo.out

#../../../../venv/bin/python3 get_open_meteo/get_open_meteo_grid.py > cronout/open-meteo-grd.out

#../../../../venv/bin/python3 get_open_meteo/concatenate_open-meteo.py > cronout/open-meteo-concat.out

echo "=== GET OBSERVATIONS AND POSTPROCESS FORECASTS ==="
# cd to the wwcs/WWCS (usually ~/wwcs/WWCS), where .Rprofile lives
cd ../..
pwd

R CMD BATCH --no-save ${my_dir}/forecasts/EMOS.R ${my_dir}/cronout/emos.out

echo "=== PROCESS WEATHER PICTOGRAMS FROM FORECASTS ==="

R CMD BATCH --no-save ${my_dir}/forecasts/process_pictos.R  ${my_dir}/cronout/pictos.out

R CMD BATCH --no-save ${my_dir}/forecasts/prepare_api_data.R  ${my_dir}/cronout/api.out
