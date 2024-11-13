#!/bin/bash

# Exit immediately if any command exits with a non-zero status
# set -e

# Exit immediately if a pipeline returns a non-zero status
# set -o pipefail

echo "=== CRON JOB ==="

cd /srv/shiny-server/dashboard/service/

echo "=== GET LATEST OBSERVATIONS  ==="

R CMD BATCH get_hydromet_data/get_tjhm_data.R cronout/hydromet.out

echo "___ DONE ___"
