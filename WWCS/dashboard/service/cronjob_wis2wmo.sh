#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service

# Ensure the cronout folder exists
mkdir -p cronout

echo "=== RETRIEVE STATION DATA from WIS2WMO system ==="

R CMD BATCH --no-save get_wis2wmo/get_wis2wmo.R  cronout/wis2wmo.out

