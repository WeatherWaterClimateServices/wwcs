from datetime import date, datetime, timedelta

import netCDF4
import numpy as np
import pandas as pd

import client

om_client = client.Client()


HOURLY_VARS = ["temperature_2m", "temperature_2m_spread", "weather_code", "precipitation"]


def dataframe_to_netcdf(df: pd.DataFrame, filename: str, ref_date: date, lat: float, lon: float):
    """Write ensemble-mean DataFrame to NetCDF."""
    nc = netCDF4.Dataset(filename, 'w', format='NETCDF4')

    times = pd.to_datetime(df['time']).values

    nc.createDimension('time', None)
    nc.createDimension('lat', 1)
    nc.createDimension('lon', 1)

    time_var = nc.createVariable('time', 'f8', ('time',), fill_value=np.nan)
    time_var.units = f'hours since {ref_date} 00:00:00'
    time_var.calendar = 'gregorian'
    ref_ts = pd.Timestamp(ref_date)
    time_var[:] = [(pd.Timestamp(t) - ref_ts).total_seconds() / 3600 for t in times]

    lat_var = nc.createVariable('lat', 'f8', ('lat',), fill_value=np.nan)
    lat_var.standard_name = 'latitude'
    lat_var.long_name = 'latitude'
    lat_var.units = 'degrees_north'
    lat_var.axis = 'Y'
    lat_var[:] = [lat]

    lon_var = nc.createVariable('lon', 'f8', ('lon',), fill_value=np.nan)
    lon_var.standard_name = 'longitude'
    lon_var.long_name = 'longitude'
    lon_var.units = 'degrees_east'
    lon_var.axis = 'X'
    lon_var[:] = [lon]

    # IFS_T_mea: ensemble mean 2m temperature (°C → K)
    v = nc.createVariable('IFS_T_mea', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    v.long_name = '2 metre temperature'
    v.units = 'K'
    v.code = 167
    v.table = 128
    v[:, 0, 0] = df['temperature_2m'].values + 273.15

    # IFS_T_std: ensemble spread of 2m temperature (already in K)
    v = nc.createVariable('IFS_T_std', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    v.long_name = '2 metre temperature spread'
    v.units = 'K'
    v.code = 167
    v.table = 128
    v[:, 0, 0] = df['temperature_2m_spread'].values

    # weather_code: WMO weather interpretation code of ensemble mean
    v = nc.createVariable('weather_code', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    v.long_name = 'WMO Weather Interpretation Code'
    v.units = '1'
    v[:, 0, 0] = df['weather_code'].values

    # tp: ensemble mean precipitation
    v = nc.createVariable('tp', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    v.long_name = 'Total precipitation'
    v.units = 'mm'
    v[:, 0, 0] = df['precipitation'].values

    nc.latitude = lat
    nc.longitude = lon
    nc.Conventions = 'CF-1.6'
    nc.institution = 'Open-Meteo (ECMWF IFS approximation)'
    nc.history = f'Created {datetime.now().isoformat()} from Open-Meteo Ensemble API'

    nc.close()
    print(f"Created: {filename}")


if __name__ == '__main__':
    forecast_days = 10

    today = date.today()
    dates = pd.date_range(today - timedelta(days=3), today)

    sites = client.get_sites()

    outdir = client.DATA_PATH
    outdir.mkdir(exist_ok=True)

    forecast_delta = timedelta(days=forecast_days - 1)
    for run_date in dates:
        start_str = run_date.strftime("%Y-%m-%d")
        end_str = (run_date + forecast_delta).strftime("%Y-%m-%d")

        for site_id, lat, lon in sites:
            # TODO Remove this test
            if site_id != 'ZAF001':
                continue
            filename = outdir / f"ifs_{site_id}_{start_str}.nc"
            if filename.exists():
                print(f"Skipping {filename}, already exists")
                continue

            df = om_client.ensemble_mean_df(lat, lon, start_str, end_str, HOURLY_VARS)
            dataframe_to_netcdf(df, str(filename), run_date.date(), lat, lon)
