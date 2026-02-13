import re
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import xarray as xr
import yaml
from openmeteo_sdk.Variable import Variable

import client

<<<<<<< HEAD
=======

ROOT_PATH = Path("/home/wwcs/wwcs/WWCS")
#ROOT_PATH = Path("/home/boris/wwcs/WWCS_repo/wwcs/WWCS")
#ROOT_PATH = Path("/home/jdavid/sandboxes/Caritas/wwcs/WWCS")
CONFIG_PATH = ROOT_PATH / "config.yaml"
DATA_PATH = ROOT_PATH / "dashboard" / "ifsdata"

>>>>>>> d4869d0 (open-meteo-grid ready for testing, proper lat/lon grid cells and a few corrections.)
om_client = client.Client()

# ================
# helper functions
# ================
def _normalize_time(t):
    """
    Make time NetCDF-friendly: timezone-naive datetime64[ns].
    Accepts strings, datetime64, pandas datetime, tz-aware, etc.
    """
    t = pd.to_datetime(t)
    if getattr(t, "tz", None) is not None:
        t = t.tz_convert("UTC").tz_localize(None)
    return t.to_numpy(dtype="datetime64[ns]")


def _insert_point(ds, lat_i, lon_j, t_raw, v1, v2):
    i = lat_to_i[float(lat_i)]
    j = lon_to_j[float(lon_j)]

    t = _normalize_time(t_raw)

    # Align to ds.time in case of minor mismatches/missing stamps
    v1a = xr.DataArray(v1, coords={"time": t}, dims=("time",)).reindex(time=ds.time)
    v2a = xr.DataArray(v2, coords={"time": t}, dims=("time",)).reindex(time=ds.time)

    ds["IFS_T_mea"][:, i, j] = v1a.values
    ds["IFS_T_std"][:, i, j] = v2a.values


# the big download function
def download_point(lat, lon, date_string):
    """
    Request ensemble forecast for one location and write NetCDF file.
    """

    # Create a fresh session every time (no caching)
    response = om_client.ensemble({
        "latitude":  lat,
        "longitude": lon,
        "hourly": ["temperature_2m", "precipitation"],
        "models": "ecmwf_ifs025",
        "start_date": date_string,
        "end_date": (datetime.strptime(date_string, '%Y-%m-%d') + forecast_delta).strftime('%Y-%m-%d'),
    })

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
    return times, temp_mean, temp_std


# ============================================================
# Load configuration
# ============================================================

with client.CONFIG_PATH.open('r') as file:
    config = yaml.safe_load(file)

train_period   = config["train_period"]
forecast_days  = config["forecast_days"]

minlat = config["minlat"]
maxlat = config["maxlat"]
minlon = config["minlon"]
maxlon = config["maxlon"]

total_days = train_period + forecast_days
forecast_delta = timedelta(days=forecast_days - 1)


# ============================================================
# Remove old files (like original script)
# ============================================================
date_pattern = r'(\d{4})-(\d{2})-(\d{2})'
two_months_ago = datetime.now() - timedelta(days=60)

for filepath in client.DATA_PATH.iterdir():
    filename = filepath.name
    match = re.search(date_pattern, filename)
    if match:
        year, month, day = map(int, match.groups())
        try:
            file_date = datetime(year, month, day)
            if file_date < two_months_ago:
                filepath.unlink()
                print(f"Deleted: {filename}")
        except ValueError:
            pass


# ============================================================
# Define date list
# ============================================================

today = datetime.today().date()
# from 3 days before to today - this is what open-meteo provides for ensemble downloads
dates = [d.strftime("%Y-%m-%d") for d in pd.date_range(today - timedelta(days=3), today)]

# ============================================================
# lon/lat
# ============================================================
lats = np.arange(np.floor(minlat * 4) / 4, np.ceil(maxlat * 4) / 4, .25)
lons = np.arange(np.floor(minlon * 4) / 4, np.floor(maxlon * 4) / 4, .25)
# Fast lookup (avoid np.where in the loop)
lat_to_i = {float(v): i for i, v in enumerate(lats)}
lon_to_j = {float(v): j for j, v in enumerate(lons)}

## time dimension
t_raw0, tmean0, tstd0 = download_point(lats[0], lons[0], dates[0])

## preallocate dataset
fill = np.nan
ds = xr.Dataset(
    data_vars={
        "IFS_T_mea": (
            ("time", "lat", "lon"),
            np.full((len(t_raw0), len(lats), len(lons)), fill, dtype="float32"),
        ),
        "IFS_T_std": (
            ("time", "lat", "lon"),
            np.full((len(t_raw0), len(lats), len(lons)), fill, dtype="float32"),
        ),
    },
    coords={"time": t_raw0, "lat": lats, "lon": lons},
)


# ------------------------
# full loop over all dates - one file per each date
# ------------------------
for date_string in dates:
    fout = DATA_PATH / f"tj_area_{date_string}.nc"
    # skip if file exists already
    if fout.exists():
        print(f"Skipping {fout}, already exists")
        continue
    
    # now loop over all points and fill ds
    for lat_i in lats:
        for lon_j in lons:
            print(lat_i, lon_j)
            t_raw, v1, v2 = download_point(float(lat_i), float(lon_j), date_string)        
            _insert_point(ds, lat_i, lon_j, t_raw, v1, v2)

    # CF attributes of ds
    ds.attrs = {
        "Conventions": "CF-1.6",
        "institution": "European Centre for Medium-Range Weather Forecasts",
        "history": f"Open-Meteo retrieval for area on {date_string}",
    }
    ds["lat"].attrs.update({
        "standard_name": "latitude",
        "long_name": "latitude",
        "units": "degrees_north",
        "axis": "Y",
    })
    ds["lon"].attrs.update({
        "standard_name": "longitude",
        "long_name": "longitude",
        "units": "degrees_east",
        "axis": "X",
    })
    ds["IFS_T_mea"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})
    ds["IFS_T_std"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})
    ds["time"].attrs.update({"axis": "T", "standard_name": "time"})

<<<<<<< HEAD
ds["IFS_T_mea"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})
ds["IFS_T_std"].attrs.update({"long_name":"2 metre temperature", "units":"K", "code":167, "table":128})


ds["time"].attrs.update({"axis": "T", "standard_name": "time"})

# Write to file    
# Output filename
fout = client.DATA_PATH / f"tj_area_{date_string}.nc"
ds.to_netcdf(fout, engine="netcdf4", unlimited_dims=["time"])
print(f"Created NetCDF: {fout}")


# ============================================================
# 7. Final cleanup
# ============================================================

print("Open-Meteo IFS retrieval complete.")
=======
    # Write to file, print filename    
    ds.to_netcdf(fout, engine="netcdf4", unlimited_dims=["time"])
    print(f"Created NetCDF: {fout}")
## end loop over dates
print("Open-Meteo IFS for the temperature grid - retrieval complete.")
>>>>>>> d4869d0 (open-meteo-grid ready for testing, proper lat/lon grid cells and a few corrections.)
