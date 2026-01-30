from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import netCDF4
import numpy as np
import openmeteo_requests
from openmeteo_sdk.Variable import Variable

import requests_cache
import retry_requests


class Client:

    def __init__(self):
        cache_session = requests_cache.CachedSession('.cache', expire_after=3600)
        retry_session = retry_requests.retry(cache_session, retries=5, backoff_factor=0.2)
        self.client = openmeteo_requests.Client(session=retry_session)

    def ensemble(self, params: dict):
        url = "https://ensemble-api.open-meteo.com/v1/ensemble"
        responses = self.client.weather_api(url, params=params)
        assert len(responses) == 1
        response = responses[0]
        return response

    def forecast(self, params: dict):
        url = "https://api.open-meteo.com/v1/forecast"
        responses = self.client.weather_api(url, params=params)
        assert len(responses) == 1
        response = responses[0]
        return response

    def ensemble_df(self, params: dict) -> pd.DataFrame:
        """Get ensemble data and return DataFrame with mean and std."""
        response = self.ensemble(params)
        return self._ensemble_response_to_dataframe(response)

    def forecast_df(self, params: dict) -> pd.DataFrame:
        response = self.forecast(params)
        return self._response_to_dataframe(response)

    def _ensemble_response_to_dataframe(self, response) -> pd.DataFrame:
        """Convert ensemble response to DataFrame with mean and std."""
        hourly = response.Hourly()

        # Get time values
        time_values = pd.date_range(
            start=pd.to_datetime(hourly.Time(), unit="s", utc=True),
            end=pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
            freq=pd.Timedelta(seconds=hourly.Interval()),
            inclusive="left"
        )

        # Extract all temperature members
        hourly_variables = [hourly.Variables(i) for i in range(hourly.VariablesLength())]
        temp_vars = [v for v in hourly_variables
                     if v.Variable() == Variable.temperature and v.Altitude() == 2]

        # Stack all member values
        member_values = []
        for var in temp_vars:
            #member = var.EnsembleMember()
            values = var.ValuesAsNumpy()
            member_values.append(values)

        # Calculate mean and std across ensemble members
        ensemble_array = np.stack(member_values)  # Shape: (members, time)
        mean_values = np.mean(ensemble_array, axis=0)
        std_values = np.std(ensemble_array, axis=0)

        # Build DataFrame
        df = pd.DataFrame({
            'time': time_values,
            'latitude': response.Latitude(),
            'longitude': response.Longitude(),
            'temperature_2m_mean': mean_values,
            'temperature_2m_std': std_values,
        })

        return df

    def _response_to_dataframe(self, response) -> pd.DataFrame:
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
            var_name = f"variable_{i}"
            if i == 0:
                var_name = 'temperature_2m'
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
    client = Client()

    train_period = 30
    forecast_days = 10
    total_days = train_period + forecast_days

    today = datetime.today().date()
    dates = [d.strftime("%Y-%m-%d") for d in pd.date_range(today - timedelta(days=total_days), today)]

    coordinates = [
        ('ZAF001', 40.179901123046875, 68.85289764404297),
    ]

    outdir = Path('ifsdata')
    outdir.mkdir(exist_ok=True)

    forecast_delta = timedelta(days=forecast_days)
    for date_str in dates:
        for site_id, lat, lon in coordinates:
            filename = outdir / f"ifs_{site_id}_{date_str}.nc"

            if filename.exists():
                print(f"Skipping {filename}, already exists")
                continue

            # Use ensemble API instead of forecast
            df = client.ensemble_df({
                'latitude': lat,
                'longitude': lon,
                'start_date': date_str,
                'end_date': (datetime.strptime(date_str, '%Y-%m-%d') + forecast_delta).strftime('%Y-%m-%d'),
                'hourly': 'temperature_2m',
                'models': 'ecmwf_ifs025',  # ECMWF IFS 0.25° ensemble
            })

            dataframe_to_netcdf(df, str(filename), date_str)
