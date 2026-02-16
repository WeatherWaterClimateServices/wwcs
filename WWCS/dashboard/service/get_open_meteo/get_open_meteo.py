from datetime import date, datetime, timedelta

import netCDF4
import numpy as np
import pandas as pd
from openmeteo_sdk.Variable import Variable

import client

om_client = client.Client()


def dataframe_to_netcdf(df: pd.DataFrame, filename: str, ref_date: date, lat: float, lon: float):
    """
    Convert ensemble DataFrame to NetCDF with ensemble statistics.
    lat and lon are stored as global attributes and single-value coordinate variables.
    """
    nc = netCDF4.Dataset(filename, 'w', format='NETCDF4')

    times = pd.to_datetime(df['time']).values

    nc.createDimension('time', None)
    nc.createDimension('lat', 1)  # Single value dimension
    nc.createDimension('lon', 1)

    time_var = nc.createVariable('time', 'f8', ('time',), fill_value=np.nan)
    time_var.units = f'hours since {ref_date} 00:00:00'
    time_var.calendar = 'gregorian'

    time_hours = [(pd.Timestamp(t) - ref_date).total_seconds() / 3600 for t in times]
    time_var[:] = time_hours

    # Single-value coordinate variables for lat/lon
    lat_var = nc.createVariable('lat', 'f8', ('lat',), fill_value=np.nan)
    lat_var.standard_name = 'latitude'
    lat_var.long_name = 'latitude'
    lat_var.units = 'degrees_north'
    lat_var.axis = 'Y'
    lat_var[:] = [lat]  # Single value

    lon_var = nc.createVariable('lon', 'f8', ('lon',), fill_value=np.nan)
    lon_var.standard_name = 'longitude'
    lon_var.long_name = 'longitude'
    lon_var.units = 'degrees_east'
    lon_var.axis = 'X'
    lon_var[:] = [lon]  # Single value

    # IFS_T_mea (ensemble mean)
    temp_mean = nc.createVariable('IFS_T_mea', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    temp_mean.long_name = '2 metre temperature'
    temp_mean.units = 'K'
    temp_mean.code = 167
    temp_mean.table = 128
    mean_values = df['temperature_2m_mean'].values + 273.15  # Convert to Kelvin
    temp_mean[:, 0, 0] = mean_values  # Index into single lat/lon position

    # IFS_T_std (ensemble spread)
    temp_std = nc.createVariable('IFS_T_std', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    temp_std.long_name = '2 metre temperature'
    temp_std.units = 'K'
    temp_std.code = 167
    temp_std.table = 128
    std_values = df['temperature_2m_std'].values
    temp_std[:, 0, 0] = std_values

    # Total precipitation (mean)
    total_precip = nc.createVariable('tp', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    total_precip.long_name = 'Total precipitation'
    total_precip.units = 'm'
    total_precip_val = df['precipitation_mean'].values / 1000  # convert mm to m
    total_precip[:, 0, 0] = total_precip_val

    # Total precipitation (std)
    total_precip_std = nc.createVariable('tp_std', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    total_precip_std.long_name = 'Total precipitation standard deviation'
    total_precip_std.units = 'm'
    total_precip_std_val = df['precipitation_std'].values / 1000  # convert mm to m
    total_precip_std[:, 0, 0] = total_precip_std_val

    # Geopotential height (mean)
    geop_height = nc.createVariable('z', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    geop_height.long_name = 'Geopotential'
    geop_height.standard_name = 'geopotential'
    geop_height.units = 'm**2 s**-2'
    geop_height[:, 0, 0] = df['geopotential_height_1000hPa_mean'].values

    # Low cloud cover (mean)
    low_cc = nc.createVariable('lcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    low_cc.long_name = 'Low cloud cover'
    low_cc.units = '(0 - 1)'
    low_cc_val = df['cloud_cover_low_mean'].values / 100  # from % to 0-1
    low_cc[:, 0, 0] = low_cc_val

    # Mid cloud cover (mean)
    mid_cc = nc.createVariable('mcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    mid_cc.long_name = 'Mid cloud cover'
    mid_cc.units = '(0 - 1)'
    mid_cc_val = df['cloud_cover_mid_mean'].values / 100  # from % to 0-1
    mid_cc[:, 0, 0] = mid_cc_val

    # High cloud cover (mean)
    high_cc = nc.createVariable('hcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    high_cc.long_name = 'High cloud cover'
    high_cc.units = '(0 - 1)'
    high_cc_val = df['cloud_cover_high_mean'].values / 100  # from % to 0-1
    high_cc[:, 0, 0] = high_cc_val

    # Total cloud cover (mean)
    total_cc = nc.createVariable('tcc', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    total_cc.long_name = 'Total cloud cover'
    total_cc.units = '(0 - 1)'
    total_cc_val = df['cloud_cover_mean'].values / 100  # from % to 0-1
    total_cc[:, 0, 0] = total_cc_val

    # Visibility - fog count (ensemble members < 1500m)
    visibility = nc.createVariable('p3020', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    visibility.long_name = 'Visibility fog count (members < 1500m)'
    visibility.units = 'count'
    visibility[:, 0, 0] = df['visibility_fog_count'].values

    # Lightning - we don't get this from open-meteo, so we leave it at nan
    lightning = nc.createVariable('litoti', 'f4', ('time', 'lat', 'lon'), fill_value=np.nan)
    lightning.long_name = 'Instantaneous total lightning flash density'
    lightning.units = 'km**-2 day**-1'

    # Global attributes for lat/lon (redundant but useful for quick lookup)
    nc.latitude = lat
    nc.longitude = lon

    nc.Conventions = 'CF-1.6'
    nc.institution = 'Open-Meteo (ECMWF IFS approximation)'
    nc.history = f'Created {datetime.now().isoformat()} from Open-Meteo Ensemble API'

    nc.close()
    print(f"Created: {filename}")


if __name__ == '__main__':
    train_period = 30
    forecast_days = 10

    # from 3 days before to today - this is what open-meteo provides for ensemble downloads
    today = date.today()
    dates = pd.date_range(today - timedelta(days=3), today)

    sites = client.get_sites()

    outdir = client.DATA_PATH
    outdir.mkdir(exist_ok=True)

    output_config = {
        'temperature_2m': {
            'variable': Variable.temperature,
            'filter': lambda v: v.Altitude() == 2,
            'aggregations': ['mean', 'std']
        },
        'cloud_cover_low': {
            'variable': Variable.cloud_cover_low,
            'aggregations': ['mean']
        },
        'cloud_cover_mid': {
            'variable': Variable.cloud_cover_mid,
            'aggregations': ['mean']
        },
        'cloud_cover_high': {
            'variable': Variable.cloud_cover_high,
            'aggregations': ['mean']
        },
        'cloud_cover': {
            'variable': Variable.cloud_cover,
            'aggregations': ['mean']
        },
        'precipitation': {
            'variable': Variable.precipitation,
            'aggregations': ['mean', 'std']
        },
        'visibility': {
            'variable': Variable.visibility,
            'aggregations': [('fog_count', lambda m: np.sum(m < 1500, axis=0))],
        },
        'geopotential_height_1000hPa': {
            'variable': Variable.geopotential_height,
            'filter': lambda v: v.PressureLevel() == 1000,
            'aggregations': ['mean']
        }
    }
    hourly = sorted(output_config.keys())

    forecast_delta = timedelta(days=forecast_days - 1)
    for date in dates:
        date_str = date.strftime("%Y-%m-%d")
        for site_id, lat, lon in sites:

            # TODO Remove this test
            # if site_id != 'ZAF001':
            #     continue

            filename = outdir / f"ifs_{site_id}_{date_str}.nc"
            if filename.exists():
                print(f"Skipping {filename}, already exists")
                continue

            # Use ensemble API
            df = om_client.ensemble_df(
                {
                    'latitude': lat,
                    'longitude': lon,
                    'start_date': date_str,
                    'end_date': (date + forecast_delta).strftime('%Y-%m-%d'),
                    'hourly': hourly,
                    'models': 'ecmwf_ifs025',  # ECMWF IFS 0.25° ensemble
                },
                output_config,
            )

            # Drop lat/lon columns since they're constant per file
            df = df.drop(columns=['latitude', 'longitude'])

            # Pass lat/lon explicitly to netcdf function
            dataframe_to_netcdf(df, str(filename), date, lat, lon)
