#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status

set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service/

# Ensure the cronout folder exists
mkdir -p cronout

echo "=== GET LATEST OBSERVATIONS  ==="

R CMD BATCH --no-save get_wwcs/get_wwcs.R cronout/wwcs.out

echo "___ DONE ___"
