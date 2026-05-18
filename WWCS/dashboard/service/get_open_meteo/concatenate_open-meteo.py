"""
This script combines the forecast downloads of the past total_days into single nc files.
It adds another dimension to the arrays, which contains the starting date.
"""

from datetime import date, datetime, timedelta

import numpy as np
import pandas as pd
import xarray as xr

import client


#BORIS outdir = client.ROOT_PATH / "dashboard" / "service" / "get_open_meteo" / "ifsdata"
outdir = client.DATA_PATH


if __name__ == '__main__':
    config = client.get_config()
    train_period = config['train_period']
    forecast_days = config['forecast_days']
    total_days = train_period + forecast_days

    # Get today's date
    today = date.today()

    # Delete files older than today that contain "merged" in the name
    # Filter files that include "merged" in their names
    merged_files = [f for f in outdir.iterdir() if f.is_file() and "merged" in f.name]
    for file_path in merged_files:
        # Get the last modification time and convert to date
        file_mod_time = datetime.fromtimestamp(file_path.stat().st_mtime).date()
        if file_mod_time < today:
            try:
                file_path.unlink()
                print(f"Deleted file {file_path}")
            except Exception as e:
                print(f"Error deleting file {file_path}: {e}")

    dates = [
        d.strftime("%Y-%m-%d")
        for d in pd.date_range(today - timedelta(days=total_days), today)
    ]

    # Read station names and locations
    # --------------------------------

    for coord in client.get_sites():
        site_id = coord[0].replace(" ", "")
        print(site_id)

        # Define file names
        file_names = [f"ifs_{site_id}_{date}.nc" for date in dates]

        # Create list for missing files
        missing_files = [f for f in file_names if not (outdir / f).exists()]
        if missing_files:
            print(f"Missing files for {site_id}: {', '.join(missing_files)}")

        # Check for existing merged file
        merged_file_path = outdir / f"{site_id}_{dates[-1]}_merged.nc"
        if not merged_file_path.exists():
            datasets = []
            for date, file_name in zip(dates, file_names):
                file_path = outdir / file_name
                if file_path.exists():
                    ds = xr.open_dataset(file_path, decode_times=True)
                    reftime = np.datetime64(datetime.strptime(date, '%Y-%m-%d'))
                    ds.coords['reftime'] = np.array([reftime])
                    ds['time'] = (ds['time'].values.astype('datetime64[ns]') - reftime) / np.timedelta64(1, 'h')
                    datasets.append(ds)

            if datasets:
                merged_ds = xr.concat(datasets, dim='reftime', join="outer", data_vars="all")
                merged_ds.to_netcdf(merged_file_path)
                print(f"Created merged file {merged_file_path}")
            else:
                print(f"No datasets to merge for {site_id}")
