from pathlib import Path

import mysql.connector
import numpy as np
import pandas as pd
from openmeteo_sdk.Variable import Variable

import openmeteo_requests
import requests_cache
import retry_requests

from common import USERNAME, PASSWORD


#ROOT_PATH = Path("/home/wwcs/wwcs/WWCS")
ROOT_PATH = Path("/home/boris/wwcs/WWCS_repo/wwcs/WWCS")
#ROOT_PATH = Path("/home/jdavid/sandboxes/Caritas/wwcs/WWCS")

CONFIG_PATH = ROOT_PATH / "config.yaml"
DATA_PATH = ROOT_PATH / "dashboard" / "ifsdata"


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

def enum_code_to_name(enum_cls, code: int):
    # enum members are stored as class attributes; reverse-lookup by value
    for name, value in enum_cls.__dict__.items():
        if value == code:
            return name
    return None

class Client:

    def __init__(self):
        cache_session = requests_cache.CachedSession('.cache', expire_after=3600)
        retry_session = retry_requests.retry(cache_session, retries=5, backoff_factor=0.2)
        self.client = openmeteo_requests.Client(session=retry_session)

    def _ensemble_response_to_dataframe(self, response):
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

    def _response_to_dataframe(self, response):
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

    def ensemble(self, params: dict):
        url = "https://ensemble-api.open-meteo.com/v1/ensemble"
        responses = self.client.weather_api(url, params=params)
        assert len(responses) == 1
        response = responses[0] # ! this is correct since we use only one model/ensemble !
        return response

    def forecast(self, params: dict):
        url = "https://api.open-meteo.com/v1/forecast"
        responses = self.client.weather_api(url, params=params)
        assert len(responses) == 1
        response = responses[0] # ! this is correct since we use only one model/ensemble !
        return response

    def ensemble_df(self, params: dict):
        response = self.ensemble(params)
        return self._ensemble_response_to_dataframe(response)

    def forecast_df(self, params: dict):
        response = self.forecast(params)
        return self._response_to_dataframe(response)
