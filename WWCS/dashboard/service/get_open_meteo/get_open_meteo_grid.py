import datetime
import re
from typing import List, Tuple

import numpy as np
import pandas as pd
import xarray as xr
from openmeteo_sdk.Variable import Variable

import client

om_client = client.Client()

MAX_POINTS = 200

def chunk_points(lats: np.ndarray, lons: np.ndarray) -> List[Tuple[List[float], List[float]]]:
    """
    Split grid into chunks that stay under Open-Meteo's data limit.
    50 points × 240 hours = 12,000 data points (close to limit)
    Adjust max_points based on your forecast_days.
    """
    all_points = [(float(lat), float(lon)) for lat in lats for lon in lons]

    chunks = []
    for i in range(0, len(all_points), MAX_POINTS):
        chunk = all_points[i:i + MAX_POINTS]
        chunk_lats = [p[0] for p in chunk]
        chunk_lons = [p[1] for p in chunk]
        chunks.append((chunk_lats, chunk_lons))

    return chunks


def download_chunk(latitudes: List[float], longitudes: List[float],
                   start_date: datetime.date, forecast_days: int) -> pd.DataFrame:
    """
    Download ensemble data for multiple points in one API call.
    Returns DataFrame with columns: time, latitude, longitude, temperature_2m_mean, temperature_2m_std
    """
    forecast_delta = datetime.timedelta(days=forecast_days - 1)
    end_date = start_date + forecast_delta

    params = {
        "latitude": latitudes,
        "longitude": longitudes,
        "hourly": ["temperature_2m"],
        "models": "ecmwf_ifs025",
        "start_date": start_date.strftime('%Y-%m-%d'),
        "end_date": end_date.strftime('%Y-%m-%d'),
    }

    aggrs = {
        'temperature_2m': {
            'variable': Variable.temperature,
            'filter': lambda v: v.Altitude() == 2,
            'aggregations': [
                ('mean', lambda x: np.mean(x, axis=0).astype("float32") + 273.15),
                ('std', lambda x: np.std(x, axis=0).astype("float32")),
            ]
        }
    }

    # ensemble_df handles single response with multiple locations
    return om_client.ensemble_df(params, aggrs)


def main():

    today = datetime.date.today()

    # Configuration
    config = client.get_config()
    forecast_days = config["forecast_days"]
    minlat = config["minlat"]
    maxlat = config["maxlat"]
    minlon = config["minlon"]
    maxlon = config["maxlon"]

    # Cleanup old files
    date_pattern = r'(\d{4})-(\d{2})-(\d{2})'
    two_months_ago = today - datetime.timedelta(days=60)

    for filepath in client.DATA_PATH.iterdir():
        filename = filepath.name
        match = re.search(date_pattern, filename)
        if match:
            year, month, day = map(int, match.groups())
            try:
                file_date = datetime.date(year, month, day)
                if file_date < two_months_ago:
                    filepath.unlink()
                    print(f"Deleted: {filename}")
            except ValueError:
                pass

    # Define grid and dates
    dates = list(pd.date_range(today - datetime.timedelta(days=3), today))
    lats = np.arange(np.floor(minlat * 4) / 4, np.ceil(maxlat * 4) / 4, .25)
    lons = np.arange(np.floor(minlon * 4) / 4, np.floor(maxlon * 4) / 4, .25)

    # Preallocate dataset using first call
    first_chunk = ([float(lats[0])], [float(lons[0])])
    df0 = download_chunk(*first_chunk, dates[0], forecast_days)
    times = df0['time'].unique()

    ds = xr.Dataset(
        data_vars={
            "IFS_T_mea": (
                ("time", "lat", "lon"),
                np.full((len(times), len(lats), len(lons)), np.nan, dtype="float32"),
            ),
            "IFS_T_std": (
                ("time", "lat", "lon"),
                np.full((len(times), len(lats), len(lons)), np.nan, dtype="float32"),
            ),
        },
        coords={"time": times, "lat": lats, "lon": lons},
    )

    # Create lookup for fast indexing
    lat_to_i = {float(lat): i for i, lat in enumerate(lats)}
    lon_to_j = {float(lon): j for j, lon in enumerate(lons)}

    # Main loop
    for date in dates:
        date_string = date.strftime("%Y-%m-%d")
        fout = client.DATA_PATH / f"tj_area_{date_string}.nc"
        if fout.exists():
            print(f"Skipping {fout}, already exists")
            continue

        # Reset dataset
        ds["IFS_T_mea"][:] = np.nan
        ds["IFS_T_std"][:] = np.nan

        # Process in chunks
        chunks = chunk_points(lats, lons)

        for chunk_lats, chunk_lons in chunks:
            print(f"Downloading chunk: {len(chunk_lats)} points")
            df_chunk = download_chunk(chunk_lats, chunk_lons, date, forecast_days)

            # Assign results to grid
            for (lat, lon), group in df_chunk.groupby(['latitude', 'longitude']):
                i = lat_to_i[float(lat)]
                j = lon_to_j[float(lon)]
                ds["IFS_T_mea"][:, i, j] = group['temperature_2m_mean'].values
                ds["IFS_T_std"][:, i, j] = group['temperature_2m_std'].values

        # CF attributes
        ds.attrs = {
            "Conventions": "CF-1.6",
            "institution": "European Centre for Medium-Range Weather Forecasts",
            "history": f"Open-Meteo retrieval for area on {date}",
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
        ds["IFS_T_mea"].attrs.update({
            "long_name": "2 metre temperature",
            "units": "K",
            "code": 167,
            "table": 128,
        })
        ds["IFS_T_std"].attrs.update({
            "long_name": "2 metre temperature",
            "units": "K",
            "code": 167,
            "table": 128,
        })
        ds["time"].attrs.update({"axis": "T", "standard_name": "time"})

        ds.to_netcdf(fout, engine="netcdf4", unlimited_dims=["time"])
        print(f"Created NetCDF: {fout}")

    print("Open-Meteo IFS for the temperature grid - retrieval complete.")


if __name__ == '__main__':
    main()
