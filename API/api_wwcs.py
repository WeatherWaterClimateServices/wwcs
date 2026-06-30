import contextlib
import datetime
import os
import traceback
import xarray as xr

# Requirements
from asyncmy.errors import IntegrityError
from databases import Database
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from common import USERNAME, PASSWORD


# Database connection settings
DATABASE_URL_MACHINES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/Machines'
database_machines = Database(DATABASE_URL_MACHINES)

DATABASE_URL_SERVICES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/WWCServices'
database_services = Database(DATABASE_URL_SERVICES)

ENV = os.environ.get('ENV')
root_path = "./" if ENV else None


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    await database_machines.connect()
    await database_services.connect()
    yield
    await database_machines.disconnect()
    await database_services.disconnect()


app = FastAPI(root_path=root_path, lifespan=lifespan)

origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def _parse_date_range(start: str | None, end: str | None) -> tuple[str, str] | None:
    """Validate start/end dates and return them as a tuple, or None if both are absent."""
    if start is None and end is None:
        return None
    if start is None or end is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Both start and end are required")
    try:
        start_dt = datetime.datetime.fromisoformat(start)
        end_dt = datetime.datetime.fromisoformat(end)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid date format. Use ISO 8601 (YYYY-MM-DD HH:MM:SS or YYYY-MM-DDTHH:MM:SS)")
    if start_dt > end_dt:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="start date must be before end date")
    return (start, end)


# ---------------------------------------
# GET OBSERVATION DATA
# ---------------------------------------

async def get_observation(stationID, start=None, end=None):
    if start and end:
        date_condition = "mo.timestamp BETWEEN :start AND :end"
        values = {"stationID": stationID, "start": start, "end": end}
    else:
        date_condition = "mo.timestamp > DATE_SUB(NOW(), INTERVAL 1 HOUR)"
        values = {"stationID": stationID}

    query = f"""
        SELECT
            mo.loggerID,
            CASE WHEN mo.p = -999 THEN NULL ELSE mo.p END AS p,
            CASE WHEN mo.pr = -999 THEN NULL ELSE mo.pr END AS pr,
            CASE WHEN mo.rh = -999 THEN NULL ELSE mo.rh END AS rh,
            mo.siteID as stationID,
            CASE WHEN mo.ta = -999 THEN NULL ELSE mo.ta END AS ta,
            mo.timestamp,
            CASE WHEN mo.ts10cm = -999 THEN NULL ELSE mo.ts10cm END AS ts10cm
        FROM v_machineobs mo
        JOIN SitesHumans.Sites sh ON mo.siteID = sh.siteID
        WHERE sh.type = 'WWCS'
        AND {date_condition}
        AND mo.siteID = :stationID
        ORDER BY timestamp DESC
    """

    rows = await database_machines.fetch_all(query=query, values=values)
    # Convert rows to a list of dictionaries with correct types
    result = [
        {
            "loggerID": row.loggerID,
            "p": None if row.p is None else float(row.p),
            "pr": None if row.pr is None else float(row.pr),
            "rh": None if row.rh is None else float(row.rh),
            "stationID": row.stationID,
            "ta": None if row.ta is None else float(row.ta),
            "timestamp": convert_timestamp(str(row.timestamp)),
            "ts10cm": None if row.ts10cm is None else float(row.ts10cm)
        }
        for row in rows
    ]
    return result


@app.get("/")
async def get_obs(response: Response, stationID: str, start: str | None = None, end: str | None = None):
    try:
        dates = _parse_date_range(start, end)
        response.headers['Access-Control-Allow-Origin'] = '*'
        return await get_observation(stationID, start=dates[0] if dates else None, end=dates[1] if dates else None)
    except HTTPException:
        raise
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Internal Server Error")


@app.get("/areas/{area}/{date}")
async def get_obs_by_area(response: Response, area: str, date: str):
    query = """
        SELECT
            :area as area_name,
            CASE
                WHEN :area = s.region THEN 'region'
                WHEN :area = s.district THEN 'district'
                WHEN :area = s.jamoat THEN 'jamoat'
                WHEN :area = s.village THEN 'village'
                ELSE 'unknown'
            END as area_type,
            AVG(wf.Tmax) AS avg_Tmax,
            AVG(wf.Tmin) AS avg_Tmin,
            AVG(wf.Tmean) AS avg_Tmean,
            wf.date,
            wf.timeofday,
            wf.day,
            COUNT(DISTINCT s.siteID) as stations_count,
            MIN(wf.icon) as icon
        FROM WWCServices.Forecasts wf
        JOIN SitesHumans.Sites s ON s.siteID = wf.siteID
        WHERE (:area = s.region OR :area = s.district OR :area = s.jamoat OR :area = s.village)
          AND wf.date = :date
          AND wf.timeofday != -1
        GROUP BY
            area_type,
            wf.date,
            wf.timeofday,
            wf.day
        ORDER BY wf.day, wf.timeofday
    """

    rows = await database_machines.fetch_all(query=query, values={"area": area, "date": date})
    if len(rows) == 0:
        raise HTTPException(status_code=404, detail="no site found for the given area")

    response.headers['Access-Control-Allow-Origin'] = '*'

    return rows


async def get_stations_metadata():
    query = """
        SELECT
            siteID,
            siteName,
            latitude,
            longitude,
            altitude
        FROM SitesHumans.Sites
        WHERE type = 'WWCS'
        ORDER BY siteName
    """

    rows = await database_machines.fetch_all(query=query)

    # Format the result
    results = []
    # If siteID starts with "CLIM" then use the sensor_type = ClimaVue, otherwise use Sensirion
    for row in rows:
        results.append({
            "siteID": row.siteID,
            "siteName": row.siteName,
            "latitude": row.latitude,
            "longitude": row.longitude,
            "altitude": row.altitude,
            "sensor_type": "ClimaVUE50" if row.siteID.startswith("CLIM") else "SensirionSHT30",
            "sensor_height": "2m"
        })

    return results

@app.get("/stations/")
async def get_stations(response: Response):
    try:
        response.headers['Access-Control-Allow-Origin'] = '*'
        return await get_stations_metadata()
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Internal Server Error")



async def get_smartmet(siteID, start=None, end=None):
    if start and end:
        date_condition = "mo.timestamp BETWEEN :start AND :end"
        values = {"siteID": siteID, "start": start, "end": end}
    else:
        date_condition = "mo.timestamp > DATE_SUB(NOW(), INTERVAL 1 HOUR)"
        values = {"siteID": siteID}

    query = f"""
        SELECT
            mo.loggerID,
            mo.timestamp,
            mo.ta,
            mo.rh,
            mo.p,
            mo.ts10cm,
            mo.pr,
            mo.wind_speed,
            mo.wind_dir,
            mo.wind_gust,
            mo.rad,
            mo.U_Battery1,
            mo.U_Solar,
            mo.signalStrength,
            mo.lightning_count,
            mo.lightning_dist,
            mo.vapour_press,
            sh.siteName,
            sh.latitude,
            sh.longitude
        FROM v_machineobs mo
        JOIN SitesHumans.Sites sh ON mo.siteID = sh.siteID
        WHERE {date_condition}
        AND mo.siteID = :siteID
        ORDER BY mo.timestamp DESC
    """

    rows = await database_machines.fetch_all(query=query, values=values)

    # Convert rows to a list of dictionaries with the correct structure
    results = []
    for row in rows:
        formatted_data = [
            {
                "label": "Air Temperature",
                "value": None if row.ta is None else float(row.ta),
                "unit": "°C",
                "machineName": "air_temperature"
            },
            {
                "label": "Relative Humidity",
                "value": None if row.rh is None else float(row.rh),
                "unit": "%",
                "machineName": "relative_humidity"
            },
            {
                "label": "Air Pressure",
                "value": None if row.p is None else float(row.p),
                "unit": "hPa",
                "machineName": "air_pressure"
            },
            {
                "label": "Precipitation",
                "value": None if row.pr is None else float(row.pr),
                "unit": "mm",
                "machineName": "precipitation"
            },
            {
                "label": "Wind Speed",
                "value": None if row.wind_speed is None else float(row.wind_speed),
                "unit": "m/s",
                "machineName": "wind_speed"
            },
            {
                "label": "Wind Direction",
                "value": None if row.wind_dir is None else float(row.wind_dir),
                "unit": "°",
                "machineName": "wind_direction"
            },
            {
                "label": "Wind Gust",
                "value": None if row.wind_gust is None else float(row.wind_gust),
                "unit": "m/s",
                "machineName": "wind_gust"
            },
            {
                "label": "Radiation",
                "value": None if row.rad is None else float(row.rad),
                "unit": "W/m²",
                "machineName": "radiation"
            },
            {
                "label": "Soil Temperature 10cm",
                "value": None if row.ts10cm is None else float(row.ts10cm),
                "unit": "°C",
                "machineName": "soil_temperature_10cm"
            },
            {
                "label": "Battery Voltage",
                "value": None if row.U_Battery1 is None else float(row.U_Battery1),
                "unit": "V",
                "machineName": "battery_voltage"
            },
            {
                "label": "Solar Voltage",
                "value": None if row.U_Solar is None else float(row.U_Solar),
                "unit": "V",
                "machineName": "solar_voltage"
            },
            {
                "label": "Signal Strength",
                "value": None if row.signalStrength is None else float(row.signalStrength),
                "unit": "dBm",
                "machineName": "signal_strength"
            },
            {
                "label": "Lightning Count",
                "value": None if row.lightning_count is None else float(row.lightning_count),
                "unit": "count",
                "machineName": "lightning_count"
            },
            {
                "label": "Lightning Distance",
                "value": None if row.lightning_dist is None else float(row.lightning_dist),
                "unit": "km",
                "machineName": "lightning_distance"
            },
            {
                "label": "Vapour Pressure",
                "value": None if row.vapour_press is None else float(row.vapour_press),
                "unit": "hPa",
                "machineName": "vapour_pressure"
            }
        ]

        results.append({
            "name": row.siteName,
            "siteID": siteID,
            "datetime": convert_timestamp(str(row.timestamp)),
            "latitude": row.latitude,
            "longitude": row.longitude,
            "data": formatted_data
        })

    return results

async def get_ecmwf(siteID, start=None, end=None):
    # get_ecmwf is functionally identical to get_smartmet
    return await get_smartmet(siteID, start=start, end=end)

@app.get("/ecmwf/")
async def app_ecmwf(response: Response, siteID: str, start: str | None = None, end: str | None = None):
    try:
        dates = _parse_date_range(start, end)
        response.headers['Access-Control-Allow-Origin'] = '*'
        return await get_ecmwf(siteID, start=dates[0] if dates else None, end=dates[1] if dates else None)
    except HTTPException:
        raise
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Internal Server Error")


@app.get("/smartmet/")
async def app_smartmet(response: Response, siteID: str, start: str | None = None, end: str | None = None):
    try:
        dates = _parse_date_range(start, end)
        response.headers['Access-Control-Allow-Origin'] = '*'
        return await get_smartmet(siteID, start=dates[0] if dates else None, end=dates[1] if dates else None)
    except HTTPException:
        raise
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Internal Server Error")


# ---------------------------------------
# GET FORECAST DATA
# ---------------------------------------

@app.get('/forecast6h')
async def get_frcst_data(request: Request, response: Response):
    date = request.query_params.get('date')
    stationID = request.query_params.get('stationID')

    if not stationID or not date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="stationID and date are required")

    query = """
        SELECT *
        FROM Forecasts
        WHERE siteID = :stationID
          AND date = :date
          AND timeofday != -1
    """

    try:
        rows = await database_services.fetch_all(query=query, values={"stationID": stationID, "date": date})
        response.headers['Access-Control-Allow-Origin'] = '*'
        return rows
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")


@app.get('/map')
async def get_map_data(request: Request, response: Response):
    filtered_data = []
    sellat = request.query_params.get('lat')
    sellon = request.query_params.get('lon')
    print(sellat)
    print(sellon)
    da = xr.open_dataset('/srv/shiny-server/dashboard/appdata/gemos_raster/raster_merged.nc')
    ds = da.sel(lon=sellon, lat=sellat, method="nearest")
    filtered_data = ds[["IFS_T_mea"]].round(1).rename({"IFS_T_mea": "Tmean"}).to_dict()["data_vars"]

    # Write coordinates to a dictionary
    coords_dict = ds.to_dict()["coords"]

    # Combine data variables and coordinates dictionaries
    result_dict = {**filtered_data, **coords_dict}
    response.headers['Access-Control-Allow-Origin'] = '*'
    return result_dict


# ---------------------------------------
# POST IRRIGATION DATA
# ---------------------------------------


@app.get('/irrigationNeed')
async def retrieve_irrgation(request: Request, response: Response):
    siteID = request.query_params.get('siteID')
    date = request.query_params.get('date')

    if not siteID or not date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="siteID and date are required")

    query = """
        SELECT date, irrigationNeed
        FROM Irrigation
        WHERE siteID = :siteID
          AND date = :date
    """

    try:
        rows = await database_services.fetch_all(query=query, values={"siteID": siteID, "date": date})

        result = [
            {
                "Date": convert_timestamp(str(row.date)),
                "Irrigation Need": None if row.irrigationNeed is None else float(row.irrigationNeed)
            }
            for row in rows
        ]
        response.headers['Access-Control-Allow-Origin'] = '*'
        return result
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")



class data_irrigation(BaseModel):
    siteID: str
    irrigationApp: int
    precip: float | None = None
    date: str | None = None

@app.post('/irrigationApp')
async def app_irrigation(data_irrigation: data_irrigation):

    siteID = data_irrigation.siteID
    irrigationApp = data_irrigation.irrigationApp
    precip = data_irrigation.precip
    date = data_irrigation.date

    query = """
        REPLACE INTO Irrigation (date, siteID, irrigationApp, precipitation) VALUES (:date, :siteID, :irrigationApp, :precip)
    """

    try:
        values = {"date": date, "siteID": siteID, "irrigationApp": irrigationApp, "precip": precip}
        await database_services.execute(query=query, values=values)
        return 'Data inserted successfully!'
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")


# ---------------------------------------
# GET WARNING DATA
# ---------------------------------------

@app.get('/warning')
async def get_data_warning(request: Request, response: Response):
    id = request.query_params.get('Name')
    date = request.query_params.get('date')
    type = request.query_params.get('type')

    if not id or not date or not type:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Name, date and type are required")

    if type == 'heat':
        query = """
        SELECT date, Name, Heat1, Heat2, Heat3, Threshold1, Threshold2, Threshold3
        FROM Heatwave
        WHERE Name = :id
          AND reftime = :date
    """

    elif type == 'cold':
        query = """
        SELECT date, Name, Cold1, Cold2, Cold3, Threshold1, Threshold2, Threshold3
        FROM Coldwave
        WHERE Name = :id
          AND reftime = :date
    """

    try:
        rows = await database_services.fetch_all(query=query, values={"id": id, "date": date})
        response.headers['Access-Control-Allow-Origin'] = '*'
        return rows
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")


# ---------------------------------------
# GET PLANTING DATA
# ---------------------------------------

@app.get('/planting')
async def get_data_warning_planting(request: Request, response: Response):
    date = request.query_params.get('date')
    stationID = request.query_params.get('stationID')

    if not id or not date or not type:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Name, date and type are required")

    query = """
        SELECT *
        FROM Planting
        WHERE siteID = :stationID
          AND date = :date
    """

    try:
        rows = await database_services.fetch_all(query=query, values={"stationID": stationID, "date": date})
        response.headers['Access-Control-Allow-Origin'] = '*'
        return rows
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")


@app.get("/planting/jamoat/{area}/{date}")
async def get_planting_by_area(response: Response, area: str, date: str):
    query = """
        SELECT  :area as area_name,
            'jamoat' as area_type,
            p.*, s.district, s.jamoat, s.region
        FROM WWCServices.Planting p
        JOIN SitesHumans.Sites s ON s.siteID = p.siteID
        WHERE s.jamoat = :area
        AND p.date = :date
    """

    rows = await database_machines.fetch_all(query=query, values={"area": area, "date": date})
    if len(rows) == 0:
        raise HTTPException(status_code=404, detail="no site found for the given area")

    response.headers['Access-Control-Allow-Origin'] = '*'
    return rows


# ---------------------------------------
# GET HARVEST DATA
# ---------------------------------------

@app.get('/harvest')
async def get_data_warning_harvest(request: Request, response: Response):
    date = request.query_params.get('date')
    stationID = request.query_params.get('stationID')

    if not id or not date or not type:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Name, date and type are required")

    query = """
        SELECT *
        FROM Harvest
        WHERE siteID = :stationID
          AND date = :date
    """

    try:
        rows = await database_services.fetch_all(query=query, values={"stationID": stationID, "date": date})
        response.headers['Access-Control-Allow-Origin'] = '*'
        return rows
    except IntegrityError as e:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")

def convert_timestamp(original_timestamp: str) -> str:
    """Convert ISO timestamp to RFC 1123 format."""
    dt = datetime.datetime.fromisoformat(original_timestamp)
    return dt.strftime("%a, %d %b %Y %H:%M:%S GMT+5")



# ── Air Quality ──────────────────────────────────────────────────────────────

STATION_IDS = (
    '70:b8:f6:02:ad:80',  # KULOB006_ECO  Kulyab
    '70:b8:f6:02:9c:38',  # DYU007_ECO    Park Ayni
    '70:b8:f6:02:9e:a0',  # DYU01_ECO     CaCH Dushanbe
    '70:b8:f6:02:aa:30',  # DYU006_ECO    Hydromet office
    '70:b8:f6:02:a9:68',  # DYU012_ECO    Physicotechnical Institute
    '70:b8:f6:02:9d:5c',  # DYU008_ECO    School No77
)


def _aqi_from_pm25(pm25: float) -> int:
    breakpoints = [
        (0.0,   12.0,   0,  50),
        (12.1,  35.4,  51, 100),
        (35.5,  55.4, 101, 150),
        (55.5, 150.4, 151, 200),
        (150.5, 250.4, 201, 300),
        (250.5, 500.4, 301, 500),
    ]
    for c_lo, c_hi, aqi_lo, aqi_hi in breakpoints:
        if c_lo <= pm25 <= c_hi:
            return round((aqi_hi - aqi_lo) / (c_hi - c_lo) * (pm25 - c_lo) + aqi_lo)
    return 500


@app.get("/airquality/stations")
async def get_airquality_stations(response: Response):
    ids = "', '".join(STATION_IDS)
    query = f"""
        SELECT mo.loggerID, mo.`timestamp`, mo.PM25, mo.PM10,
               mo.ta AS temperature, mo.rh AS humidity,
               mo.wind_speed, mo.wind_dir
        FROM Machines.MachineObs mo
        INNER JOIN (
            SELECT loggerID, MAX(`timestamp`) AS latest_ts
            FROM Machines.MachineObs
            WHERE loggerID IN ('{ids}')
            GROUP BY loggerID
        ) latest ON mo.loggerID = latest.loggerID
               AND mo.`timestamp` = latest.latest_ts
    """
    rows = await database_machines.fetch_all(query=query)
    result = []
    for row in rows:
        r = dict(row)
        r['aqi'] = _aqi_from_pm25(r.get('PM25') or 0)
        result.append(r)
    response.headers['Access-Control-Allow-Origin'] = '*'
    return result


@app.get("/airquality/history")
async def get_airquality_history(response: Response, hours: int = 24):
    ids = "', '".join(STATION_IDS)
    query = f"""
        SELECT mo.loggerID, mo.`timestamp`, mo.PM25, mo.PM10
        FROM Machines.MachineObs mo
        WHERE mo.loggerID IN ('{ids}')
          AND mo.`timestamp` >= NOW() - INTERVAL {hours} HOUR
        ORDER BY mo.loggerID, mo.`timestamp` ASC
    """
    rows = await database_machines.fetch_all(query=query)
    response.headers['Access-Control-Allow-Origin'] = '*'
    return [dict(row) for row in rows]
