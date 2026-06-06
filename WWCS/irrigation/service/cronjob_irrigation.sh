#!/bin/bash
echo "=== CRON JOB ==="

# cd to the directory of this script
my_dir="$(dirname "$(readlink -f "$0")")"
cd $my_dir
pwd

# Ensure the cronout folder exists
mkdir -p cronout
echo "=== CALCULATE IRRIGATION ADVICE ==="

# cd to the wwcs/WWCS (usually ~/wwcs/WWCS), where .Rprofile lives
cd ../..
pwd
R CMD BATCH ${my_dir}/irrigation_calculation.R ${my_dir}/cronout/irrigation.out
