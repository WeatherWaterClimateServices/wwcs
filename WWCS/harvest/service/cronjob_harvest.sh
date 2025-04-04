#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/harvest/service/

echo "=== CALCULATE IRRIGATION ADVICE ==="

R CMD BATCH --no-save harvest.R harvest.out
