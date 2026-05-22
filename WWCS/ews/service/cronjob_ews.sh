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

# cd to the wwcs/WWCS (usually ~/wwcs/WWCS), where .Rprofile lives
cd ../..
pwd

today=$(date +%Y-%m-%d)

if [ -f "dashboard/ifsdata/tj_area_$today.nc" ]; then

  echo "=== POSTPROCESS FORECASTS GLOBALLY (gEMOS) ==="
  
  R CMD BATCH --no-save ${my_dir}/gEMOS/gEMOS.R ${my_dir}/cronout/gemos.out
  
  echo "=== CALCULATE WARNING LEVELS ==="
  
  R CMD BATCH --no-save ${my_dir}/calculate_ews.R ${my_dir}/cronout/ews.out

  # touch restart.txt to force reload of the data in the dashboard
  touch dashboard/restart.txt

else
  echo "New forecast not yet available"
fi



