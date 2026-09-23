import contextlib
import datetime

import MySQLdb
import pytest
from fastapi.testclient import TestClient

from api_wwcs import app
from common import DATABASE_URL_SERVICES, ENV, SERVICES_SCHEMA, USERNAME, PASSWORD

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


class TestEnvSwitch:
    def test_services_schema_follows_env(self):
        expected = "WWCServices" if ENV == "PROD" else "WWCServices_DEV"
        assert SERVICES_SCHEMA == expected
        assert DATABASE_URL_SERVICES.endswith(f"/{expected}")


class TestParamValidation:
    @pytest.mark.parametrize("endpoint", ["/planting", "/harvest"])
    def test_missing_date_returns_400(self, client, endpoint):
        r = client.get(f"{endpoint}?stationID=nonexistent")
        assert r.status_code == 400
        assert "stationID and date are required" in r.json()["detail"]

    @pytest.mark.parametrize("endpoint", ["/planting", "/harvest"])
    def test_valid_params_empty_result(self, client, endpoint):
        r = client.get(f"{endpoint}?stationID=nonexistent&date=2024-01-01")
        assert r.status_code == 200
        assert r.json() == []


# ── Air Quality ──────────────────────────────────────────────────────────────

airq_siteID = "TEST001_ECO"
airq_loggerID = "test-logger-airq"


def airq_cleanup():
    with get_cursor(commit=True) as cursor:
        cursor.execute(
            "DELETE FROM Machines.MachineObs WHERE loggerID = %s", [airq_loggerID]
        )
        cursor.execute(
            "DELETE FROM Machines.MachineAtSite WHERE loggerID = %s", [airq_loggerID]
        )
        cursor.execute(
            "DELETE FROM SitesHumans.Sites WHERE siteID = %s", [airq_siteID]
        )


def insert_airq_observation(timestamp, pm25=None, pm10=None):
    with get_cursor(commit=True) as cursor:
        # `received` has no default on every deployment, so set it explicitly
        cursor.execute(
            "INSERT INTO Machines.MachineObs (loggerID, timestamp, received, PM25, PM10, ta, rh) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s)",
            [airq_loggerID, timestamp, timestamp, pm25, pm10, 25.0, 40.0],
        )


@pytest.fixture
def airq_data():
    airq_cleanup()
    with get_cursor(commit=True) as cursor:
        cursor.execute(
            "INSERT INTO SitesHumans.Sites (siteID, siteName, latitude, longitude, altitude, type) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            [airq_siteID, "Test Air Quality Site", 38.5, 68.8, 800.0, "WWCS"],
        )
        cursor.execute(
            "INSERT INTO Machines.MachineAtSite (siteID, loggerID, startDate, endDate) "
            "VALUES (%s, %s, %s, %s)",
            [airq_siteID, airq_loggerID, "2000-01-01 00:00:00", "2100-01-01 00:00:00"],
        )
    yield
    airq_cleanup()


def minutes_ago(minutes):
    return (datetime.datetime.now() - datetime.timedelta(minutes=minutes)).strftime(
        "%Y-%m-%d %H:%M:%S"
    )


def find_station(payload, station_id):
    return next((row for row in payload if row["stationID"] == station_id), None)


class TestAirQualityStations:
    endpoint = "/airquality/stations"

    def test_returns_site_metadata_and_no_loggerid(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=20.0, pm10=40.0)

        r = client.get(self.endpoint)
        assert r.status_code == 200
        station = find_station(r.json(), airq_siteID)
        assert station is not None
        assert "loggerID" not in station
        assert station["siteName"] == "Test Air Quality Site"
        assert station["latitude"] == pytest.approx(38.5)
        assert station["longitude"] == pytest.approx(68.8)
        assert station["altitude"] == pytest.approx(800.0)
        assert station["PM25"] == pytest.approx(20.0)
        assert station["PM10"] == pytest.approx(40.0)

    def test_returns_only_latest_observation(self, client, airq_data):
        insert_airq_observation(minutes_ago(60), pm25=10.0)
        insert_airq_observation(minutes_ago(5), pm25=30.0)

        r = client.get(self.endpoint)
        assert r.status_code == 200
        rows = [row for row in r.json() if row["stationID"] == airq_siteID]
        assert len(rows) == 1
        assert rows[0]["PM25"] == pytest.approx(30.0)

    def test_aqi_is_computed_from_pm25(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=12.0)

        station = find_station(client.get(self.endpoint).json(), airq_siteID)
        assert station["aqi"] == 50

    def test_aqi_is_null_without_pm25(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=None, pm10=40.0)

        station = find_station(client.get(self.endpoint).json(), airq_siteID)
        assert station["aqi"] is None

    def test_non_eco_sites_are_excluded(self, client, test_data):
        insert_observation(minutes_ago(5))

        r = client.get(self.endpoint)
        assert r.status_code == 200
        assert find_station(r.json(), siteID) is None


class TestAirQualityHistory:
    endpoint = "/airquality/history"

    def test_returns_stationid_and_no_loggerid(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=20.0, pm10=40.0)

        r = client.get(self.endpoint)
        assert r.status_code == 200
        rows = [row for row in r.json() if row["stationID"] == airq_siteID]
        assert len(rows) == 1
        assert "loggerID" not in rows[0]
        assert rows[0]["PM25"] == pytest.approx(20.0)

    def test_hours_limits_the_window(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=20.0)
        insert_airq_observation(minutes_ago(300), pm25=10.0)

        rows = [
            row
            for row in client.get(f"{self.endpoint}?hours=1").json()
            if row["stationID"] == airq_siteID
        ]
        assert len(rows) == 1
        assert rows[0]["PM25"] == pytest.approx(20.0)

    def test_filters_by_station(self, client, airq_data):
        insert_airq_observation(minutes_ago(5), pm25=20.0)

        r = client.get(f"{self.endpoint}?stationID={airq_siteID}")
        assert r.status_code == 200
        assert {row["stationID"] for row in r.json()} == {airq_siteID}

    def test_unknown_station_returns_empty(self, client, airq_data):
        r = client.get(f"{self.endpoint}?stationID=nonexistent")
        assert r.status_code == 200
        assert r.json() == []

    def test_non_eco_sites_are_excluded(self, client, test_data):
        insert_observation(minutes_ago(5))

        rows = client.get(self.endpoint).json()
        assert find_station(rows, siteID) is None

    @pytest.mark.parametrize("hours", [0, -1, 169, 100000])
    def test_out_of_range_hours_rejected(self, client, hours):
        r = client.get(f"{self.endpoint}?hours={hours}")
        assert r.status_code == 400
        assert "hours must be between" in r.json()["detail"]


class TestAqiFromPm25:
    @pytest.mark.parametrize(
        "pm25,expected",
        [
            (0.0, 0),
            (12.0, 50),
            (35.4, 100),
            (55.4, 150),
            (150.4, 200),
            (250.4, 300),
            (500.4, 500),
            (600.0, 500),
        ],
    )
    def test_breakpoints(self, pm25, expected):
        from api_wwcs import _aqi_from_pm25

        assert _aqi_from_pm25(pm25) == expected
