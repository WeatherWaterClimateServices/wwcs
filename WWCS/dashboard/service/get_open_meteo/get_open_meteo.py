from pathlib import Path
import netCDF4

from datetime import datetime, timedelta
import pandas as pd
import numpy as np

import client

om_client = client.Client()

def dataframe_to_netcdf(df: pd.DataFrame, filename: str, date_str: str):
    """
    Convert ensemble DataFrame to NetCDF with IFS_T_mea and IFS_T_std.
    """
    nc = netCDF4.Dataset(filename, 'w', format='NETCDF4')

    times = pd.to_datetime(df['time']).values
    lats = df['latitude'].unique()
    lons = df['longitude'].unique()

    nc.createDimension('time', None)
    nc.createDimension('lat', len(lats))
    nc.createDimension('lon', len(lons))

    ref_date = datetime.strptime(date_str, '%Y-%m-%d')
    time_var = nc.createVariable('time', 'f8', ('time',), fill_value=np.nan)
    time_var.units = f'hours since {date_str} 00:00:00'
    time_var.calendar = 'gregorian'

    time_hours = [(pd.Timestamp(t) - ref_date).total_seconds() / 3600 for t in times]
    time_var[:] = time_hours

    lat_var = nc.createVariable('lat', 'f8', ('lat',), fill_value=np.nan)
    lat_var.standard_name = 'latitude'
    lat_var.long_name = 'latitude'
    lat_var.units = 'degrees_north'
    lat_var.axis = 'Y'
    lat_var[:] = lats

    lon_var = nc.createVariable('lon', 'f8', ('lon',), fill_value=np.nan)
    lon_var.standard_name = 'longitude'
    lon_var.long_name = 'longitude'
    lon_var.units = 'degrees_east'
    lon_var.axis = 'X'
    lon_var[:] = lons

    # IFS_T_mea (ensemble mean)
    temp_mean = nc.createVariable('IFS_T_mea', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    temp_mean.long_name = '2 metre temperature'
    temp_mean.units = 'K'
    temp_mean.code = 167
    temp_mean.table = 128
    mean_values = df['temperature_2m_mean'].values + 273.15  # Convert to Kelvin
    temp_mean[:] = mean_values.reshape(len(times), len(lats), len(lons))

    # IFS_T_std (ensemble spread)
    temp_std = nc.createVariable('IFS_T_std', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    temp_std.long_name = '2 metre temperature'
    temp_std.units = 'K'
    temp_std.code = 167
    temp_std.table = 128
    std_values = df['temperature_2m_std'].values  # Already in Kelvin if input was Celsius
    temp_std[:] = std_values.reshape(len(times), len(lats), len(lons))

    nc.Conventions = 'CF-1.6'
    nc.institution = 'Open-Meteo (ECMWF IFS approximation)'
    nc.history = f'Created {datetime.now().isoformat()} from Open-Meteo Ensemble API'

    nc.close()
    print(f"Created: {filename}")


if __name__ == '__main__':
    train_period = 30
    forecast_days = 10
    total_days = train_period + forecast_days

    today = datetime.today().date()
    # from 3 days before to today - this is what open-meteo provides for ensemble downloads
    dates = [d.strftime("%Y-%m-%d") for d in pd.date_range(today - timedelta(days=3), today)]

    sites = client.get_sites()

    outdir = Path('/home/wwcs/wwcs/WWCS/dashboard/ifsdata')
    outdir.mkdir(exist_ok=True)

    forecast_delta = timedelta(days=forecast_days)
    for date_str in dates:
        for site_id, lat, lon in sites:

            # TODO Remove this test
            # if site_id != 'ZAF001':
            #    continue

            filename = outdir / f"ifs_{site_id}_{date_str}.nc"

            if filename.exists():
                print(f"Skipping {filename}, already exists")
                continue

            # Use ensemble API instead of forecast
            df = om_client.ensemble_df({
                'latitude': lat,
                'longitude': lon,
                'start_date': date_str,
                'end_date': (datetime.strptime(date_str, '%Y-%m-%d') + forecast_delta - 1).strftime('%Y-%m-%d'),
                'hourly': 'temperature_2m',
                'models': 'ecmwf_ifs025',  # ECMWF IFS 0.25° ensemble
            })

            dataframe_to_netcdf(df, str(filename), date_str)
