#!/bin/bash
echo "=== CRON JOB ==="

cd /srv/shiny-server/irrigation/service/

echo "=== CALCULATE IRRIGATION ADVICE ==="

R CMD BATCH irrigation_calculation.R irrigation.out
