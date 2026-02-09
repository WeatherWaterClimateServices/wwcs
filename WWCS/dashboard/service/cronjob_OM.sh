#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service

# Ensure the cronout folder exists
mkdir -p cronout

echo "=== RETRIEVE EMCWF FORECASTS ==="

/home/wwcs/venv/bin/python3 get_open_meteo/get_open_meteo.py > cronout/open-meteo.out

/home/wwcs/venv/bin/python3 get_open_meteo/get_open_meteo_extended.py > cronout/open-meteo-ext.out

/home/wwcs/venv/bin/python3 get_open_meteo/get_open_meteo_grid.py > cronout/open-meteo-grd.out

/home/wwcs/venv/bin/python3 get_open_meteo/concatenate_open-meteo.py > cronout/open-meteo-concat.out

echo "=== GET OBSERVATIONS AND POSTPROCESS FORECASTS ==="

R CMD BATCH --no-save forecasts/EMOS.R cronout/emos.out

echo "=== PROCESS WEATHER PICTOGRAMS FROM FORECASTS ==="

R CMD BATCH --no-save forecasts/process_pictos.R  cronout/pictos.out

R CMD BATCH --no-save forecasts/prepare_api_data.R  cronout/api.out
