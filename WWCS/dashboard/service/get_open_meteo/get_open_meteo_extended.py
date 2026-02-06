from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import mysql.connector
import netCDF4
import numpy as np
from openmeteo_sdk.Variable import Variable

from client import Client
from common import USERNAME, PASSWORD


client = Client()

def get_sites():
    with mysql.connector.connect(
        user=USERNAME,
        password=PASSWORD,
        host='127.0.0.1',
        database='SitesHumans',
    ) as cnx:
        with cnx.cursor() as cursor:
            cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")
            return cursor.fetchall()

def forecast_df(params: dict) -> pd.DataFrame:
    response = client.forecast(params)
    return _response_to_dataframe(response)

def enum_code_to_name(enum_cls, code: int):
    # enum members are stored as class attributes; reverse-lookup by value
    for name, value in enum_cls.__dict__.items():
        if value == code:
            return name
    return None

def _response_to_dataframe(response) -> pd.DataFrame:
    """Convert openmeteo-requests response to pandas DataFrame."""
    hourly = response.Hourly()

    time_values = pd.date_range(
        start=pd.to_datetime(hourly.Time(), unit="s", utc=True),
        end=pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
        freq=pd.Timedelta(seconds=hourly.Interval()),
        inclusive="left"
    )

    data = {
        'time': time_values,
        'latitude': response.Latitude(),
        'longitude': response.Longitude(),
    }

    for i in range(hourly.VariablesLength()):
        var = hourly.Variables(i)
        var_name = enum_code_to_name(Variable, var.Variable())
        print(var_name)       
        data[var_name] = var.ValuesAsNumpy()

    return pd.DataFrame(data)


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

    # Total precipitation
    total_precip = nc.createVariable('tp', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    total_precip.long_name = 'Total precipitation'
    total_precip.units = 'm'    
    total_precip_val = df['precipitation'].values / 1000 # convert mm to m
    total_precip[:] = total_precip_val.reshape(len(times), len(lats), len(lons))
    
    # Geopotential height
    geop_height = nc.createVariable('z', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    geop_height.long_name = 'Geopotential'
    geop_height.standard_name = 'geopotential'
    geop_height.units = 'm**2 s**-2'
    geop_height[:] = df['geopotential_height'].values.reshape(len(times), len(lats), len(lons))        

    # cloud cover low
    low_cc = nc.createVariable('lcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    low_cc.long_name = 'Low cloud cover'    
    low_cc.units = '(0 - 1)'
    low_cc_val = df['cloud_cover_low'].values / 100 # from % to 0-1
    low_cc [:] = low_cc_val.reshape(len(times), len(lats), len(lons))

    # middle cloud cover
    mid_cc = nc.createVariable('mcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    mid_cc.long_name = 'Mid cloud cover'    
    mid_cc.units = '(0 - 1)'
    mid_cc_val = df['cloud_cover_mid'].values / 100 # from % to 0-1
    mid_cc [:] = mid_cc_val.reshape(len(times), len(lats), len(lons))

    # high cloud cover
    high_cc = nc.createVariable('hcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    high_cc.long_name = 'High cloud cover'    
    high_cc.units = '(0 - 1)'
    high_cc_val = df['cloud_cover_high'].values / 100 # from % to 0-1
    high_cc [:] = high_cc_val.reshape(len(times), len(lats), len(lons))

    # total cloud cover
    total_cc = nc.createVariable('tcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    total_cc.long_name = 'Total cloud cover'    
    total_cc.units = '(0 - 1)'
    total_cc_val = df['cloud_cover'].values / 100 # from % to 0-1
    total_cc [:] = total_cc_val.reshape(len(times), len(lats), len(lons))

    # visibility
    visibility = nc.createVariable('p3020', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    visibility.long_name = 'Visibility'    
    visibility.units = 'm'    
    visibility [:] = df['visibility'].values.reshape(len(times), len(lats), len(lons))
    
    # lightning - we don't get this from open-meteo, so we leave it at nan
    lightning = nc.createVariable('litoti', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    lightning.long_name = 'Instantaneous total lightning flash density'    
    lightning.units = 'km**-2 day**-1'    
    
    # conventions
    nc.Conventions = 'CF-1.6'
    nc.institution = 'Open-Meteo (ECMWF IFS approximation)'
    nc.history = f'Created {datetime.now().isoformat()} from Open-Meteo Forecast API'

    nc.close()
    print(f"Created: {filename}")


if __name__ == '__main__':
    train_period = 30
    forecast_days = 10
    total_days = train_period + forecast_days

    today = datetime.today().date()
    dates = [d.strftime("%Y-%m-%d") for d in pd.date_range(today - timedelta(days=total_days), today)]

    sites = get_sites()

    outdir = Path('ifsdata')
    outdir.mkdir(exist_ok=True)

    forecast_delta = timedelta(days=forecast_days)
    for date_str in dates:
        for site_id, lat, lon in sites:

            # TODO Remove this test
            if site_id != 'ZAF001':
                continue

            filename = outdir / f"ifs_{site_id}_{date_str}_extended.nc"

            if filename.exists():
                print(f"Skipping {filename}, already exists")
                continue

            # Use forecast API
            df = forecast_df({
                'latitude': lat,
                'longitude': lon,
                'start_date': date_str,
                'end_date': (datetime.strptime(date_str, '%Y-%m-%d') + forecast_delta).strftime('%Y-%m-%d'),
                'hourly': ["precipitation", "geopotential_height_1000hPa", "cloud_cover_low", "cloud_cover_mid", 
                    "cloud_cover_high", "cloud_cover", "visibility"],
                'models': 'ecmwf_ifs',  # 
            })

            dataframe_to_netcdf(df, str(filename), date_str)
