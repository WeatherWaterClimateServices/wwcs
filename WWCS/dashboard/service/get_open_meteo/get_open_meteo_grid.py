import re
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import xarray as xr
import yaml
from openmeteo_sdk.Variable import Variable

import client

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
        "hourly": "temperature_2m",
        "models": "ecmwf_ifs025"
        #"start_date": date_string,
        #"end_date": date_string,
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

minlat = 47 #config["minlat"]
maxlat = 48 # config["maxlat"]
minlon = 9 # config["minlon"]
maxlon = 10 # config["maxlon"]

total_days = train_period + forecast_days


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

# Boris: the date range does not really make sense for me. Check
dat = [
    d.strftime("%Y-%m-%d")
    for d in pd.date_range(datetime.today() - timedelta(days=total_days), datetime.today())
]
date_string = dat[0] ## here - this is still weird.


# ============================================================
# 4. lon/lat
# ============================================================
lats = np.arange(minlat, maxlat, .25)
lons = np.arange(minlon, maxlon, .25)
# Fast lookup (avoid np.where in the loop)
lat_to_i = {float(v): i for i, v in enumerate(lats)}
lon_to_j = {float(v): j for j, v in enumerate(lons)}

## time dimension
t_raw0, tmean0, tstd0 = download_point(lats[0], lons[0], date_string)

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
# full loop over all points
# ------------------------
# fill ds
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

# Write to file    
# Output filename
fout = client.DATA_PATH / f"tj_area_{date_string}.nc"
ds.to_netcdf(fout, engine="netcdf4", unlimited_dims=["time"])
print(f"Created NetCDF: {fout}")


# ============================================================
# 7. Final cleanup
# ============================================================

print("Open-Meteo IFS retrieval complete.")
