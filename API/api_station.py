import datetime
import hashlib
import json
import os
import socket
import time
import traceback

# Requirements
from asyncmy.errors import IntegrityError
from databases import Database
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, Response, status


# Configuration
load_dotenv()
ENV = os.environ.get('ENV')
USERNAME = os.environ.get('USERNAME', 'wwcs')
PASSWORD = os.environ.get('PASSWORD')

# Database connection settings
DATABASE_URL = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/Machines'
database = Database(DATABASE_URL)

root_path = "/post" if ENV else None
app = FastAPI(root_path=root_path)

@app.on_event("startup")
async def startup():
    await database.connect()

@app.on_event("shutdown")
async def shutdown():
    await database.disconnect()


#testing API via browser
@app.get("/test")
async def route_test():
    return 'OK'

#main API script
@app.post("/insert")
async def addData(request: Request):
    domain = get_domain(request)

    #json parsing
    data = await request.json()
    myjson = json.dumps(data)
    try:
        data = data.copy()

        # Check required fields
        loggerID = data.get('loggerID')
        timestamp = data.get('timestamp')
        sign = data.pop('sign', None)
        if not (loggerID and timestamp and sign):
            return await submitRejectedJSON("Incorrect JSON body", myjson, domain)

        # Check timestamp
        now = datetime.datetime.now() + datetime.timedelta(minutes=1000)
        if not ('2010-01-01 00:00:01' < timestamp < str(now)):
            return await submitRejectedJSON("Invalid timestamp", myjson, domain)

        # Get siteID
        sql = f"SELECT siteID FROM Machines.MachineAtSite WHERE loggerID = '{loggerID}' ORDER BY startDate DESC;"
        rows = await database.fetch_all(sql)
        if len(rows) == 0:
            return await submitRejectedJSON("Station ID not registered", myjson, domain)

        row = rows[0]
        siteID = row.siteID

        # Check signature
        key = f"{siteID}; {loggerID}; {timestamp}"
        hash = hashlib.sha256(key.encode('utf-8')).hexdigest()
        if hash != sign:
            return await submitRejectedJSON("Incorrect hash", myjson, domain)

    #catch error while parsing json
    except Exception:
        traceback.print_exc()
        return await submitRejectedJSON("Incorrect JSON body", myjson, domain)

    data.pop('git_version', None) # No column in the table for this one
    try:
        async with database.transaction():
            await insert(database, 'Machines.MachineObs', received='NOW()', **data)
        # TODO Change to 201 once the stations are updated
        return "New record inserted"
    except IntegrityError as exc:
        errcode = exc.args[0]
        if errcode == 1062:
            return "Duplicate data NOT inserted"
        else:
            raise
    except Exception:
        #catch error with mysql insert
        traceback.print_exc()
        return await submitRejectedJSON("Hashcheck ok, but insertion failed.", myjson, domain)

#insert rejected functions
async def submitRejectedJSON(text, json, domain):
    # XXX Should be 202 Accepted
    async with database.transaction():
        await insert(database, 'Machines.MachineObsRejected',
               domain=domain,
               comment=text,
               received='NOW(6)',
               data=json,
        )

    return text

def get_domain(request):
    """Client domain extraction."""
    host = request.client.host  # Client's hostname or IP address
    try:
        hostname, aliaslist, ipaddrlist = socket.gethostbyaddr(host)
    except OSError:
        # In the server ip is ::ffff:127.0.0.1 and it fails with
        # OSError: [Errno 97] Address family not supported by protocol
        host = host.rsplit(':', 1)[-1]
        hostname, aliaslist, ipaddrlist = socket.gethostbyaddr(host)

    return hostname

async def insert(database, table, **kwargs):
    columns = []
    values = []
    args = {}
    for col, val in kwargs.items():
        columns.append(col)
        if type(val) is str and val.startswith('NOW('):
            values.append(val)
        else:
            values.append(f':{col}')
            args[col] = val

    columns = ', '.join(columns)
    values = ', '.join(values)
    sql = f"INSERT INTO {table} ({columns}) VALUES ({values});"
    return await database.execute(sql, args)

@app.post("/register")
async def register(request: Request, response: Response):
    domain = get_domain(request)

    # Input data
    data = await request.json()
    siteID = data.get('siteID')     # station_id
    loggerID = data.get('loggerID') # MAC
    git_version = data.get('git_version')

    # Check required arguments
    if siteID is None or loggerID is None or git_version is None:
        raise HTTPException(status_code=400, detail='Missing required data')

    # Insert
    startDate = time.strftime("%Y-%m-%d %H:%M:%S")
    endDate = "2100-01-01 00:00:00"
    try:
        async with database.transaction():
            await insert(database, 'Machines.MachineAtSite',
                   siteID=siteID,
                   loggerID=loggerID,
                   startDate=startDate,
                   endDate=endDate)
            await insert(database, 'Machines.Metadata',
                   loggerID=loggerID,
                   startDate=startDate,
                   endDate=endDate,
                   git_version=git_version,
                   domain=domain)
    except IntegrityError as exc:
        errcode = exc.args[0]
        if errcode == 1062:
            status_code = status.HTTP_200_OK
        else:
            raise
    else:
        status_code = status.HTTP_201_CREATED

    # Return
    response.status_code = status_code
    return 'OK'
