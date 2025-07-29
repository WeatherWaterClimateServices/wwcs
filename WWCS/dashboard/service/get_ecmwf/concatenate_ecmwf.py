from datetime import datetime, timedelta
import os

from cdo import Cdo
from ecmwfapi import ECMWFService
import mysql.connector
import numpy as np
import pandas as pd
import xarray as xr
import yaml

from common import USERNAME, PASSWORD

cdo = Cdo()

# Define global variables
# --------------------------------

server = ECMWFService("mars")
outdir = "/srv/shiny-server/dashboard/ifsdata/"

with open("/home/wwcs/wwcs/WWCS/config.yaml", 'r') as file:
    config = yaml.safe_load(file)

train_period = config['train_period']
forecast_days = config['forecast_days']
total_days = train_period + forecast_days

# Get today's date
today = datetime.today().date()

# Delete files older than today that contain "merged" in the name
files = os.listdir(outdir)

# Filter files that include "merged" in their names
merged_files = [file for file in files if "merged" in file]

for file in merged_files:
    file_path = os.path.join(outdir, file)
    # Get the last modification time and convert to date
    file_mod_time = datetime.fromtimestamp(os.path.getmtime(file_path)).date()
    if file_mod_time < today:
        try:
            os.remove(file_path)
            print(f"Deleted file {file_path}")
        except Exception as e:
            print(f"Error deleting file {file_path}: {e}")

dates = [d.strftime("%Y-%m-%d") for d in pd.date_range(today - timedelta(days = total_days), today - timedelta(days=0))]
os.chdir(outdir)

# Read station names and locations
# --------------------------------

cnx = mysql.connector.connect(user=USERNAME, password=PASSWORD,
                              host='127.0.0.1',
                              database='SitesHumans')

cursor = cnx.cursor()
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")

coordinates = cursor.fetchall()

for coord in coordinates:
    site_id = coord[0].replace(" ", "")
    print(site_id)
    
    # Define file names
    file_names = ["ifs_" + site_id + "_" + date + ".nc" for date in dates]
    extended_file_names = ["ifs_" + site_id + "_" + date + "_extended.nc" for date in dates]
    
    # Create list for missing files
    missing_files = [file_name for file_name in file_names if not os.path.exists(os.path.join(outdir, file_name))]
    if missing_files:
        print(f"Missing files for {site_id}: {', '.join(missing_files)}")
    
    # Check for existing merged file
    merged_file_path = os.path.join(outdir, site_id + '_' + dates[-1] + '_merged.nc')
    if not os.path.exists(merged_file_path):
        datasets = []
        for date, file_name in zip(dates, file_names):
            file_path = os.path.join(outdir, file_name)
            if os.path.exists(file_path):
                ds = xr.open_dataset(file_path)
                reftime = np.datetime64(datetime.strptime(date, '%Y-%m-%d'))
                ds.coords['reftime'] = np.array([reftime])
                ds['time'] = (ds['time'].values.astype('datetime64[ns]') - reftime) / np.timedelta64(1, 'h')
                datasets.append(ds)

        if datasets:
            merged_ds = xr.concat(datasets, dim='reftime')
            merged_ds.to_netcdf(merged_file_path)
            print(f"Created merged file {merged_file_path}")
        else:
            print(f"No datasets to merge for {site_id}")

    # Check for existing extended merged file
        # Create list for missing files
    missing_files = [file_name for file_name in extended_file_names if not os.path.exists(os.path.join(outdir, file_name))]
    
    if missing_files:
        print(f"Missing files for {site_id}: {', '.join(missing_files)}")
    
    extended_merged_file_path = os.path.join(outdir, site_id + '_' + dates[-1] + '_extended_merged.nc')
    if not os.path.exists(extended_merged_file_path):
        datasets = []
        for date, file_name in zip(dates, extended_file_names):
            file_path = os.path.join(outdir, file_name)
            if os.path.exists(file_path):
                ds = xr.open_dataset(file_path, decode_times=True, use_cftime=True)
                reftime = np.datetime64(datetime.strptime(date, '%Y-%m-%d'))
                ds.coords['reftime'] = np.array([reftime])
                ds['time'] = (ds['time'].values.astype('datetime64[ns]') - reftime) / np.timedelta64(1, 'h')
                datasets.append(ds)
        
        if datasets:
            merged_ds = xr.concat(datasets, dim='reftime')
            merged_ds.to_netcdf(extended_merged_file_path)
            print(f"Created extended merged file {extended_merged_file_path}")
        else:
            print(f"No extended datasets to merge for {site_id}")
