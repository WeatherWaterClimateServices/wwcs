import openmeteo_requests
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

