#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service

echo "=== RETRIEVE EMCWF FORECASTS ==="

./get_ecmwf/get_ecmwf.py > cronout/ecmwf.out

./get_ecmwf/get_ecmwf_extended.py > cronout/ecmwf_extended.out

./get_ecmwf/concatenate_ecmwf.py > cronout/ecmwf_concatenate.out

echo "=== GET OBSERVATIONS AND POSTPROCESS FORECASTS ==="

R CMD BATCH --no-save forecasts/EMOS.R cronout/emos.out

echo "=== PROCESS WEATHER PICTOGRAMS FROM FORECASTS ==="

R CMD BATCH --no-save forecasts/process_pictos.R  cronout/pictos.out

R CMD BATCH --no-save forecasts/prepare_api_data.R  cronout/api.out






