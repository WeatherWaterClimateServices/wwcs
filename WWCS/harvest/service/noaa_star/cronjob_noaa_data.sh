#!/bin/bash
echo "=== CRON JOB ==="

cd /srv/shiny-server/harvest/service/noaa_star

echo "=== RETRIEVE NOAA STAR DATA ==="

python3 get_noaa_star.py > get_noaa.out

echo "=== POSTPROCESS NOAA STAR ==="

R CMD BATCH process_noaa_star.R process_noaa.out

echo "___ DONE ___"
