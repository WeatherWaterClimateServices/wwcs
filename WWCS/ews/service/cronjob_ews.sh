#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/ews/service

today=$(date +%Y-%m-%d)

if [ -f "/srv/shiny-server/dashboard/ifsdata/tj_area_$today.nc" ]; then

  echo "=== POSTPROCESS FORECASTS GLOBALLY (gEMOS) ==="
  
  R CMD BATCH --no-save /srv/shiny-server/ews/service/gEMOS/gEMOS.R /srv/shiny-server/ews/service/cronout/gemos.out
  
  echo "=== CALCULATE WARNING LEVELS ==="
  
  R CMD BATCH --no-save /srv/shiny-server/ews/service/calculate_ews.R /srv/shiny-server/ews/service/cronout/ews.out

else
  echo "New forecast not yet available"
fi



