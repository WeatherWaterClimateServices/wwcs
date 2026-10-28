import os

import mysql.connector
import numpy as np
import pandas as pd
import yaml

import openmeteo_requests
import requests_cache
import retry_requests

from common import USERNAME, PASSWORD, ROOT_DIR


ROOT_PATH = ROOT_DIR / "WWCS"
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
            cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE forecast=1")
            return cursor.fetchall()

_BASE_URL = "https://ensemble-api.open-meteo.com/v1/ensemble"
_CUSTOMER_BASE_URL = "https://customer-ensemble-api.open-meteo.com/v1/ensemble"


class Client:

    def __init__(self):
        cache_session = requests_cache.CachedSession('.cache', expire_after=3600, backend='memory')
        retry_session = retry_requests.retry(cache_session, retries=5, backoff_factor=0.2)
        self.session = retry_session
        self.client = openmeteo_requests.Client(session=retry_session)
        self.api_key = os.getenv('OPENMETEO_API_KEY')

    def _url(self):
        return _CUSTOMER_BASE_URL if self.api_key else _BASE_URL

    def _auth(self):
        return {"apikey": self.api_key} if self.api_key else {}

    def ensemble_mean_df(self, lat, lon, start_date: str, end_date: str, hourly: list) -> pd.DataFrame:
        """Fetch variables from the ensemble mean API. Returns one column per requested variable.

        `lat` and `lon` may be scalars or sequences of coordinates. The returned
        DataFrame always has columns `time`, `latitude`, `longitude` plus one per
        requested `hourly` variable; multi-location calls yield more rows.
        """
        lats = [lat] if np.isscalar(lat) else list(lat)
        lons = [lon] if np.isscalar(lon) else list(lon)
        params = {
            "latitude": ",".join(map(str, lats)),
            "longitude": ",".join(map(str, lons)),
            "hourly": ",".join(hourly),
            "models": "ecmwf_ifs025_ensemble_mean",
            "start_date": start_date,
            "end_date": end_date,
            "elevation": ",".join(["nan"] * len(lats)),
            **self._auth(),
        }
        resp = self.session.get(self._url(), params=params)
        resp.raise_for_status()
        payload = resp.json()
        responses = payload if isinstance(payload, list) else [payload]
        dfs = []
        for r in responses:
            h = r["hourly"]
            data = {
                "time": pd.to_datetime(h["time"]),
                "latitude": r["latitude"],
                "longitude": r["longitude"],
            }
            for var in hourly:
                data[var] = np.array(h[var], dtype=np.float32)
            dfs.append(pd.DataFrame(data))
        return pd.concat(dfs, ignore_index=True)

    def precipitation_ensemble_df(self, lat: float, lon: float, start_date: str, end_date: str) -> pd.DataFrame:
        """Fetch full precipitation ensemble, returning one column per ensemble member."""
        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": "precipitation",
            "models": "ecmwf_ifs025_ensemble",
            "start_date": start_date,
            "end_date": end_date,
            'elevation': 'nan',
            **self._auth(),
        }
        resp = self.session.get(self._url(), params=params)
        resp.raise_for_status()
        hourly = resp.json()["hourly"]
        member_keys = sorted(k for k in hourly if k.startswith("precipitation_member"))
        data = {"time": pd.to_datetime(hourly["time"])}
        for k in member_keys:
            data[k] = np.array(hourly[k], dtype=np.float32)
        return pd.DataFrame(data)

    def _ensemble_response_to_dataframe(
        self,
        response,
        output_config: dict = None
    ):
        """
        Convert ensemble response to DataFrame with configurable outputs.
        """
        hourly = response.Hourly()

        # Time extraction - make timezone-naive for NetCDF compatibility
        time_values = pd.date_range(
            start=pd.to_datetime(hourly.Time(), unit="s", utc=True),
            end=pd.to_datetime(hourly.TimeEnd(), unit="s", utc=True),
            freq=pd.Timedelta(seconds=hourly.Interval()),
            inclusive="left"
        ).tz_convert(None)  # <-- Remove timezone

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
        if self.api_key:
            params["apikey"] = self.api_key
            url = "https://customer-ensemble-api.open-meteo.com/v1/ensemble"
        return self.client.weather_api(url, params=params)

    def ensemble_df(self, params: dict, aggrs: dict):
        responses = self.ensemble(params)
        dfs = [self._ensemble_response_to_dataframe(r, aggrs) for r in responses]
        result = pd.concat(dfs, ignore_index=True)
        return result


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
