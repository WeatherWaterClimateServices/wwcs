import datetime
import os
import traceback
import xarray as xr

# Requirements
from asyncmy.errors import IntegrityError
from databases import Database
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Configuration
load_dotenv()
ENV = os.environ.get('ENV')
USERNAME = os.environ.get('USERNAME', 'wwcs')
PASSWORD = os.environ.get('PASSWORD')

# Database connection settings

DATABASE_URL_MACHINES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/Machines'
database_machines = Database(DATABASE_URL_MACHINES)

DATABASE_URL_SERVICES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/WWCServices'
database_services = Database(DATABASE_URL_SERVICES)

root_path = "./" if ENV else None
app = FastAPI(root_path=root_path)

origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    await database_machines.connect()
    await database_services.connect()

@app.on_event("shutdown")
async def shutdown():
    await database_machines.disconnect()
    await database_services.disconnect()

# ---------------------------------------
# GET OBSERVATION DATA
# ---------------------------------------

async def get_observation(stationID):
    query = """
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
        AND mo.timestamp > DATE_SUB(NOW(), INTERVAL 1 HOUR) 
        AND mo.siteID = :stationID 
        ORDER BY timestamp DESC
    """

    rows = await database_machines.fetch_all(query=query, values={"stationID": stationID})
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
async def get_obs(response: Response, stationID: str):
    try:
        response.headers['Access-Control-Allow-Origin'] = '*'
        return await get_observation(stationID)
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Internal Server Error")


@app.get("/areas/{area}")
async def get_obs_by_area(response: Response, area: str):
    query = """
        SELECT siteId FROM SitesHumans.Sites
        WHERE district = :area OR jamoat = :area OR village = :area
    """

    rows = await database_machines.fetch_all(query=query, values={"area": area})
    if len(rows) == 0:
        raise HTTPException(status_code=404, detail="no site found for the given area")

    response.headers['Access-Control-Allow-Origin'] = '*'
    for row in rows:
        rows = await get_observation(row.siteId)
        if rows:
            return rows

    return []



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
async def app_irrgation(data_irrigation: data_irrigation):
  
    siteID = data_irrigation.siteID
    irrigationApp = data_irrigation.irrigationApp
    precip = data_irrigation.precip
    date = data_irrigation.date

    query = """
        REPLACE INTO Irrigation (date, siteID, irrigationApp, precipitation) VALUES (:date, :siteID, :irrigationApp, :precip)
    """
    
    try:
        await database_services.execute(query=query, values={"date": date, "siteID": siteID, "irrigationApp": irrigationApp, "precip": precip})
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
    return dt.strftime("%a, %d %b %Y %H:%M:%S GMT")
      