from pathlib import Path

import mysql.connector
import numpy as np
import pandas as pd
import yaml
#from openmeteo_sdk.Variable import Variable

import openmeteo_requests
import requests_cache
import retry_requests

from common import USERNAME, PASSWORD


ROOT_PATH = Path("/home/wwcs/wwcs/WWCS")
#ROOT_PATH = Path("/home/boris/wwcs/WWCS_repo/wwcs/WWCS")
#ROOT_PATH = Path("/home/jdavid/sandboxes/Caritas/wwcs/WWCS")

DATA_PATH = ROOT_PATH / "dashboard" / "ifsdata"


def enum_code_to_name(enum_cls, code: int):
    # enum members are stored as class attributes; reverse-lookup by value
    for name, value in enum_cls.__dict__.items():
        if value == code:
            return name
    return None

def get_config():
    CONFIG_PATH = ROOT_PATH / "config.yaml"
    with CONFIG_PATH.open('r') as file:
        return yaml.safe_load(file)

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

class Client:

    def __init__(self):
        cache_session = requests_cache.CachedSession('.cache', expire_after=3600)
        retry_session = retry_requests.retry(cache_session, retries=5, backoff_factor=0.2)
        self.client = openmeteo_requests.Client(session=retry_session)

    def _ensemble_response_to_dataframe(
        self,
        response,
        output_config: dict = None
    ):
        """
        Convert ensemble response to DataFrame with configurable outputs.
        """
        hourly = response.Hourly()

        # Time extraction
        time_values = pd.date_range(
            start=pd.to_datetime(hourly.Time(), unit="s", utc=True),
            end=pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
            freq=pd.Timedelta(seconds=hourly.Interval()),
            inclusive="left"
        )

        # Group variables by output key
        data_arrays = {key: [] for key in output_config}

        for i in range(hourly.VariablesLength()):
            var = hourly.Variables(i)

            for key, config in output_config.items():
                # Check variable type
                if var.Variable() != config['variable']:
                    continue

                # Apply filter if provided
                if 'filter' in config and not config['filter'](var):
                    continue

                data_arrays[key].append(var.ValuesAsNumpy())
                break  # One variable matches one key

        # Build DataFrame
        result_data = {
            'time': time_values,
            'latitude': response.Latitude(),
            'longitude': response.Longitude(),
        }

        for key, config in output_config.items():
            members = np.stack(data_arrays[key])  # Shape: (members, time)

            for agg in config['aggregations']:
                if isinstance(agg, str):
                    # Standard aggregation
                    f = getattr(np, agg)
                    result_data[f"{key}_{agg}"] = f(members, axis=0)

                elif isinstance(agg, tuple):
                    # Custom aggregation: (name, function)
                    agg_name, agg_func = agg
                    result_data[f"{key}_{agg_name}"] = agg_func(members)
                else:
                    raise TypeError()

        return pd.DataFrame(result_data)

    def ensemble(self, params: dict):
        url = "https://ensemble-api.open-meteo.com/v1/ensemble"
        responses = self.client.weather_api(url, params=params)
        assert len(responses) == 1
        response = responses[0] # ! this is correct since we use only one model/ensemble !
        return response

    def ensemble_df(self, params: dict, aggrs: dict):
        response = self.ensemble(params)
        return self._ensemble_response_to_dataframe(response, aggrs)

#    def _response_to_dataframe(self, response):
#        """Convert openmeteo-requests response to pandas DataFrame."""
#        hourly = response.Hourly()
#
#        time_values = pd.date_range(
#            start=pd.to_datetime(hourly.Time(), unit="s", utc=True),
#            end=pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
#            freq=pd.Timedelta(seconds=hourly.Interval()),
#            inclusive="left"
#        )
#
#        data = {
#            'time': time_values,
#            'latitude': response.Latitude(),
#            'longitude': response.Longitude(),
#        }
#
#        for i in range(hourly.VariablesLength()):
#            var = hourly.Variables(i)
#            var_name = enum_code_to_name(Variable, var.Variable())
#            print(var_name)
#            data[var_name] = var.ValuesAsNumpy()
#
#        return pd.DataFrame(data)
#
#    def forecast(self, params: dict):
#        url = "https://api.open-meteo.com/v1/forecast"
#        responses = self.client.weather_api(url, params=params)
#        assert len(responses) == 1
#        response = responses[0] # ! this is correct since we use only one model/ensemble !
#        return response
#
#    def forecast_df(self, params: dict):
#        response = self.forecast(params)
#        return self._response_to_dataframe(response)
