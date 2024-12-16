#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service


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

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/get_ecmwf.py > cronout/ecmwf.out

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/get_ecmwf_extended.py > cronout/ecmwf_extended.out

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/concatenate_ecmwf.py > cronout/ecmwf_concatenate.out

echo "=== GET OBSERVATIONS AND POSTPROCESS FORECASTS ==="

R CMD BATCH --no-save forecasts/EMOS.R cronout/emos.out

echo "=== PROCESS WEATHER PICTOGRAMS FROM FORECASTS ==="

R CMD BATCH --no-save forecasts/process_pictos.R  cronout/pictos.out

R CMD BATCH --no-save forecasts/prepare_api_data.R  cronout/api.out







echo "=== RETRIEVE EMCWF FORECASTS ==="

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/get_ecmwf.py > cronout/ecmwf.out

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/get_ecmwf_extended.py > cronout/ecmwf_extended.out

/opt/shiny-server/WWCS/dashboard/service/get_ecmwf/venv/bin/python3 get_ecmwf/concatenate_ecmwf.py > cronout/ecmwf_concatenate.out

echo "=== GET OBSERVATIONS AND POSTPROCESS FORECASTS ==="

R CMD BATCH --no-save forecasts/EMOS.R cronout/emos.out

echo "=== PROCESS WEATHER PICTOGRAMS FROM FORECASTS ==="

R CMD BATCH --no-save forecasts/process_pictos.R  cronout/pictos.out

R CMD BATCH --no-save forecasts/prepare_api_data.R  cronout/api.out






