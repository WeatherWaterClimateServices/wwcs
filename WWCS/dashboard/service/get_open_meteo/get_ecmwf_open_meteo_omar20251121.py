from datetime import datetime, timedelta
import os
import re
import yaml
import mysql.connector
import pandas as pd
import numpy as np
import openmeteo_requests

from openmeteo_sdk.Variable import Variable

from common import USERNAME, PASSWORD


# ============================================================
# 1. Load configuration
# ============================================================

#with open('/home/wwcs/wwcs/WWCS/config.yaml', 'r') as file:
#    config = yaml.safe_load(file)
with open('/home/boris/Documents/PV_Taj/wwcs/WWCS_repo/wwcs/WWCS/config.yaml', 'r') as file:
    config = yaml.safe_load(file)

train_period   = config["train_period"]
forecast_days  = config["forecast_days"]

minlat = config["minlat"]
maxlat = config["maxlat"]
minlon = config["minlon"]
maxlon = config["maxlon"]

total_days = train_period + forecast_days


# ============================================================
# 2. Remove old files (like original script)
# ============================================================

# directory_path = "/srv/shiny-server/dashboard/ifsdata"
directory_path = "/home/boris/Documents/PV_Taj/wwcs/WWCS_repo/wwcs/WWCS/dashboard/ifsdata"
date_pattern = r'(\d{4})-(\d{2})-(\d{2})'

two_months_ago = datetime.now() - timedelta(days=60)

for filename in os.listdir(directory_path):
    match = re.search(date_pattern, filename)
    if match:
        year, month, day = map(int, match.groups())
        try:
            file_date = datetime(year, month, day)
            if file_date < two_months_ago:
                os.remove(os.path.join(directory_path, filename))
        except ValueError:
            pass


# ============================================================
# 3. Define date list
# ============================================================

dat = [
    d.strftime("%Y-%m-%d")
    for d in pd.date_range(datetime.today() - timedelta(days=total_days), datetime.today())
]

outdir = "/home/boris/Documents/PV_Taj/wwcs/WWCS_repo/wwcs/WWCS/dashboard/ifsdata"
os.chdir(outdir)


# ============================================================
# 4. Read site coordinates from MySQL
# ============================================================

cnx = mysql.connector.connect(
    user=USERNAME, password=PASSWORD,
    host="127.0.0.1", database="SitesHumans"
)
cursor = cnx.cursor()
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")
coordinates = cursor.fetchall()


# ============================================================
# 5. Function: Retrieve Open-Meteo ensemble and convert to NetCDF
# ============================================================

def retrieve_and_save_netcdf(lat, lon, station_id, date_string):
    """
    Request ensemble forecast for one location and write NetCDF file.
    """

    # Create a fresh session every time (no caching)
    openmeteo = openmeteo_requests.Client()

    url = "https://ensemble-api.open-meteo.com/v1/ensemble"
    params = {
        "latitude":  lat,
        "longitude": lon,
        "hourly": "temperature_2m",
        "models": "ecmwf_ifs025"
        #"start_date": date_string,
        #"end_date": date_string,
    }

    responses = openmeteo.weather_api(url, params=params)

    if len(responses) == 0:
        print(f"No data returned for {station_id} on {date_string}")
        return

    response = responses[0]
    hourly = response.Hourly()

    # Extract hours
    times = pd.date_range(
        start = pd.to_datetime(hourly.Time(), unit="s", utc=True),
        end   = pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
        freq  = pd.Timedelta(seconds=hourly.Interval()),
        inclusive="left",
    ).tz_convert("UTC").tz_localize(None)

    # Retrieve all ensemble members
    variables = [
        hourly.Variables(i)
        for i in range(hourly.VariablesLength())
    ]
    temp_members = [
        v for v in variables if v.Variable() == Variable.temperature and v.Altitude() == 2
    ]

    if len(temp_members) == 0:
        print("No ensemble members found!")
        return

    # Build temperature matrix: time × members
    temp_matrix = np.column_stack([v.ValuesAsNumpy() for v in temp_members])

    # Compute ensemble statistics
    temp_mean = np.mean(temp_matrix, axis=1).astype("float32")
    temp_std  = np.std(temp_matrix, axis=1).astype("float32")

    # Convert °C → Kelvin (ECMWF standard)
    temp_mean += 273.15
    temp_std  += 273.15

    # Prepare NetCDF output
    import xarray as xr

    ds = xr.Dataset(
        data_vars = {
            "IFS_T_mea": (("time", "lat", "lon"), temp_mean.reshape(-1,1,1)),
            "IFS_T_std": (("time", "lat", "lon"), temp_std.reshape(-1,1,1)),
        },
        coords = {
            "time": times,
            "lat": [lat],
            "lon": [lon],
        },
        attrs = {
            "Conventions": "CF-1.6",
            "institution": "European Centre for Medium-Range Weather Forecasts",
            "history": f"Open-Meteo retrieval for {station_id} on {date_string}",
        }
    )

    # CF attributes
    # ds["time"].attrs["standard_name"] = "time"
    # ds["time"].attrs["calendar"] = "proleptic_gregorian"
    # ds["time"].attrs["axis"] = "T"
    # ds["time"].attrs["units"] = f"hours since {date_string} 00:00:00"

    ds["lat"].attrs.update({"standard_name":"latitude", "units":"degrees_north", "axis":"Y"})
    ds["lon"].attrs.update({"standard_name":"longitude","units":"degrees_east","axis":"X"})

    ds["IFS_T_mea"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})
    ds["IFS_T_std"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})

    # Output filename
    fout = f"ifs_{station_id.replace(' ', '')}_{date_string}.nc"
    ds.to_netcdf(fout, engine="netcdf4")
    print(f"Created NetCDF: {fout}")


# ============================================================
# 6. Main Loop: Download per station per date
# ============================================================

for date_string in dat:

    for siteID, lat, lon in coordinates:
        fout = f"ifs_{siteID.replace(' ', '')}_{date_string}.nc"

        if os.path.isfile(fout):
            continue  # already created

        print(f"Retrieving Open-Meteo forecast for {siteID} on {date_string}")
        retrieve_and_save_netcdf(lat, lon, siteID, date_string)


# ============================================================
# 7. Final cleanup
# ============================================================

os.chdir("/srv/shiny-server/dashboard")
print("Open-Meteo IFS retrieval complete.")
