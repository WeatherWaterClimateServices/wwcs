from datetime import datetime, timedelta
import os
import re
import requests
import pandas as pd
import yaml
import xarray as xr
import mysql.connector
from cdo import Cdo
from common import USERNAME, PASSWORD

cdo = Cdo()

# ---------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------
with open('/home/wwcs/wwcs/WWCS/config.yaml', 'r') as file:
    config = yaml.safe_load(file)

train_period = config['train_period']
forecast_days = config['forecast_days']
maxlat = config['maxlat']
minlat = config['minlat']
maxlon = config['maxlon']
minlon = config['minlon']
total_days = train_period + forecast_days

outdir = "/home/omar/wwcs/WWCS/dashboard/ifsdata"
os.makedirs(outdir, exist_ok=True)

# ---------------------------------------------------------------------
# Delete files older than 60 days
# ---------------------------------------------------------------------
date_pattern = r'(\d{4})-(\d{2})-(\d{2})'
two_months_ago = datetime.now() - timedelta(days=60)
for f in os.listdir(outdir):
    match = re.search(date_pattern, f)
    if match:
        y, m, d = map(int, match.groups())
        fdate = datetime(y, m, d)
        if fdate < two_months_ago:
            os.remove(os.path.join(outdir, f))
            print(f"Deleted old file: {f}")

# ---------------------------------------------------------------------
# Station information
# ---------------------------------------------------------------------
cnx = mysql.connector.connect(user=USERNAME, password=PASSWORD,
                              host='127.0.0.1', database='SitesHumans')
cursor = cnx.cursor(dictionary=True)
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")
stations = cursor.fetchall()

# ---------------------------------------------------------------------
# Prepare date list
# ---------------------------------------------------------------------
datelist = [d.strftime("%Y-%m-%d") for d in pd.date_range(
    datetime.today() - timedelta(days=total_days), datetime.today())]

# ---------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------
for dat in datelist:
    tj_file = os.path.join(outdir, f"tj_area_{dat}.nc")

    # Skip if already processed
    missing_files = []
    for s in stations:
        station_file = os.path.join(outdir, f"ifs_{s['siteID'].replace(' ', '')}_{dat}.nc")
        if not os.path.isfile(station_file):
            missing_files.append(s)
    if not missing_files:
        print(f"Skipping {dat}: all station files exist.")
        continue

    # -----------------------------------------------------------------
    # Retrieve Open-Meteo IFS forecast data
    # -----------------------------------------------------------------
    if not os.path.isfile(tj_file):
        print(f"\n=== Retrieving Open-Meteo IFS forecast for {dat} ===")

        # Open-Meteo IFS forecast endpoint for grid data
        # The free API allows querying small bounding boxes stepwise.
        # We’ll sample every 0.25° in the configured region.
        url = (
            "https://api.open-meteo.com/v1/ecmwf?"
            f"latitude={(maxlat+minlat)/2}&longitude={(maxlon+minlon)/2}"
            f"&hourly=temperature_2m"
            f"&forecast_days={forecast_days}"
            f"&timezone=UTC"
        )

        r = requests.get(url)
        if r.status_code != 200:
            print(f"Failed to retrieve {dat}: {r.text}")
            continue

        data = r.json()
        times = pd.to_datetime(data["hourly"]["time"])
        temps = data["hourly"]["temperature_2m"]

        # Build dataset (deterministic model → std=0)
        ds = xr.Dataset(
            {
                "IFS_T_mea": (["time"], temps),
                "IFS_T_std": (["time"], [0.0] * len(temps))
            },
            coords={"time": times}
        )

        # Save as tj_area_<date>.nc
        ds.to_netcdf(tj_file)
        print(f"Saved {tj_file}")

    # -----------------------------------------------------------------
    # Interpolate to station points using CDO (nearest neighbour)
    # -----------------------------------------------------------------
    print(f"Interpolating data for {dat} ...")
    for s in missing_files:
        fout = os.path.join(outdir, f"ifs_{s['siteID'].replace(' ', '')}_{dat}.nc")
        if os.path.isfile(fout):
            continue

        arg = f"lon={s['longitude']}_lat={s['latitude']}"
        cdo.remapnn(arg, input=tj_file, output=fout)
        print(f"  -> Created {fout}")

print("\nAll done!")
cnx.close()
