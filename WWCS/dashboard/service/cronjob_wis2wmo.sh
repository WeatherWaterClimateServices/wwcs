#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e

# Exit immediately if a pipeline returns a non-zero status
set -o pipefail

echo "=== CRON JOB ==="
# cd to the directory of this script
my_dir="$(dirname "$(readlink -f "$0")")"
cd $my_dir
pwd

# Ensure the cronout folder exists
mkdir -p cronout

echo "=== RETRIEVE STATION DATA from WIS2WMO system ==="
# cd to the wwcs/WWCS (usually ~/wwcs/WWCS), where .Rprofile lives
cd ../..
pwd

R CMD BATCH --no-save ${my_dir}/get_wis2wmo/get_wis2wmo.R  ${my_dir}/cronout/wis2wmo.out

