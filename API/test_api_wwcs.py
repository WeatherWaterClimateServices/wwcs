import contextlib

import MySQLdb
import pytest
from fastapi.testclient import TestClient

from api_wwcs import app
from common import USERNAME, PASSWORD

siteID = "test-site-wwcs"
loggerID = "test-logger-wwcs"


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def connect():
    return MySQLdb.connect("localhost", USERNAME, PASSWORD)


@contextlib.contextmanager
def get_cursor(commit=False):
    conn = connect()
    cursor = conn.cursor()
    yield cursor
    cursor.close()
    if commit:
        conn.commit()
    conn.close()


def cleanup():
    with get_cursor(commit=True) as cursor:
        cursor.execute(
            "DELETE FROM Machines.MachineObs WHERE loggerID = %s", [loggerID]
        )
        cursor.execute(
            "DELETE FROM Machines.MachineAtSite WHERE loggerID = %s", [loggerID]
        )
        cursor.execute(
            "DELETE FROM SitesHumans.Sites WHERE siteID = %s", [siteID]
        )


def setup_site_and_logger():
    with get_cursor(commit=True) as cursor:
        cursor.execute(
            "INSERT INTO SitesHumans.Sites (siteID, siteName, latitude, longitude, altitude, type) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            [siteID, "Test Site", 0.0, 0.0, 0.0, "WWCS"],
        )
        cursor.execute(
            "INSERT INTO Machines.MachineAtSite (siteID, loggerID, startDate, endDate) "
            "VALUES (%s, %s, %s, %s)",
            [siteID, loggerID, "2000-01-01 00:00:00", "2100-01-01 00:00:00"],
        )


def insert_observation(timestamp, ta=20.0):
    with get_cursor(commit=True) as cursor:
        cursor.execute(
            "INSERT INTO Machines.MachineObs (loggerID, timestamp, ta) VALUES (%s, %s, %s)",
            [loggerID, timestamp, ta],
        )


@pytest.fixture
def test_data():
    cleanup()
    setup_site_and_logger()
    yield
    cleanup()


class TestObservationsDateParams:
    endpoint = "/"
    id_param = "stationID"

    def test_default_no_dates(self, client):
        r = client.get(f"{self.endpoint}?{self.id_param}=nonexistent")
        assert r.status_code == 200
        assert r.json() == []

    def test_valid_date_range_empty(self, client):
        r = client.get(
            f"{self.endpoint}?{self.id_param}=nonexistent"
            f"&start=2024-01-01T00:00:00&end=2024-01-02T00:00:00"
        )
        assert r.status_code == 200
        assert r.json() == []

    def test_missing_end(self, client):
        r = client.get(
            f"{self.endpoint}?{self.id_param}=nonexistent&start=2024-01-01T00:00:00"
        )
        assert r.status_code == 400
        assert "Both start and end are required" in r.json()["detail"]

    def test_missing_start(self, client):
        r = client.get(
            f"{self.endpoint}?{self.id_param}=nonexistent&end=2024-01-01T00:00:00"
        )
        assert r.status_code == 400
        assert "Both start and end are required" in r.json()["detail"]

    def test_invalid_date_format(self, client):
        r = client.get(
            f"{self.endpoint}?{self.id_param}=nonexistent"
            f"&start=bad&end=2024-01-01T00:00:00"
        )
        assert r.status_code == 400
        assert "Invalid date format" in r.json()["detail"]

    def test_start_after_end(self, client):
        r = client.get(
            f"{self.endpoint}?{self.id_param}=nonexistent"
            f"&start=2024-01-02T00:00:00&end=2024-01-01T00:00:00"
        )
        assert r.status_code == 400
        assert "start date must be before end date" in r.json()["detail"]

    def test_date_range_filters_results(self, client, test_data):
        t1 = "2024-06-15 10:00:00"
        t2 = "2024-06-15 12:00:00"
        t3 = "2024-06-15 14:00:00"
        insert_observation(t1, ta=10.0)
        insert_observation(t2, ta=20.0)
        insert_observation(t3, ta=30.0)

        r = client.get(
            f"{self.endpoint}?{self.id_param}={siteID}"
            f"&start=2024-06-15T11:00:00&end=2024-06-15T13:00:00"
        )
        assert r.status_code == 200
        data = r.json()
        assert len(data) == 1
        if self.endpoint == "/":
            assert data[0]["ta"] == 20.0
        else:
            # smartmet / ecmwf wrap measurements in a 'data' array
            air_temp = next(
                (item for item in data[0]["data"] if item["machineName"] == "air_temperature"), None
            )
            assert air_temp is not None
            assert air_temp["value"] == 20.0


class TestSmartmetDateParams(TestObservationsDateParams):
    endpoint = "/smartmet/"
    id_param = "siteID"


class TestEcmwfDateParams(TestObservationsDateParams):
    endpoint = "/ecmwf/"
    id_param = "siteID"
