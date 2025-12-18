import datetime
import hashlib
import json
import os
import socket
import time
import traceback

# Requirements
from fastapi import FastAPI, HTTPException, Request, Response, status
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
import sqlalchemy as sa

from common import USERNAME, PASSWORD
from models.Machines import MachineAtSite, MachineObs, t_MachineObsRejected, Metadata


# Database connection settings
# With one worker we may use 20+30 concurrent connections
DATABASE_URL = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/Machines'
engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,           # Default is 5
    max_overflow=30,        # Default is 10
    pool_timeout=30,        # Default is 30
    pool_recycle=7200,      # Default is -1
    pool_pre_ping=True,     # Default is False
)


ENV = os.environ.get('ENV')
root_path = "/post" if ENV else None
app = FastAPI(root_path=root_path)


#testing API via browser
@app.get("/test")
async def route_test():
    return 'OK'

#main API script
@app.post("/insert")
async def addData(request: Request):
    domain = get_domain(request)

    async with AsyncSession(engine) as session:
        # json parsing
        body = await request.body()
        try:
            text = body.decode('utf-8')
        except UnicodeDecodeError:
            return await submitRejectedJSON(session, "Invalid UTF-8 encoding", "", domain)

        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            return await submitRejectedJSON(session, "Incorrect JSON body", text, domain)

        try:
            # Check required fields
            loggerID = data.get('loggerID')
            timestamp = data.get('timestamp')
            sign = data.pop('sign', None)
            if not (loggerID and timestamp and sign):
                return await submitRejectedJSON(session, "Missing loggerID, timestamp or sign", text, domain)

            # Check timestamp
            now = datetime.datetime.now() + datetime.timedelta(minutes=1000)
            if not ('2010-01-01 00:00:01' < timestamp < str(now)):
                return await submitRejectedJSON(session, "Invalid timestamp", text, domain)

            # Get siteID
            result = await session.execute(
                sa.select(MachineAtSite)
                    .filter_by(loggerID=loggerID)
                    .order_by(MachineAtSite.startDate.desc())
                    .limit(1)
            )

            row = result.scalar()
            if row is None:
                return await submitRejectedJSON(session, "Station ID not registered", text, domain)

            siteID = row.siteID

            # Check signature
            key = f"{siteID}; {loggerID}; {timestamp}"
            hash = hashlib.sha256(key.encode('utf-8')).hexdigest()
            if hash != sign:
                return await submitRejectedJSON(session, "Incorrect hash", text, domain)

        except Exception:
            traceback.print_exc()
            return await submitRejectedJSON(session, "Unexpected error", text, domain)

        data.pop('git_version', None) # No column in the table for this one
        try:
            await insert(session, MachineObs, received=sa.func.now(), **data)

            # TODO Change to 201 once the stations are updated
            return "New record inserted"
        except sa.exc.IntegrityError as exc:
            errcode = exc.orig.args[0]
            if errcode == 1062:
                return "Duplicate data NOT inserted"
            else:
                raise
        except Exception:
            traceback.print_exc()
            return await submitRejectedJSON(session, "Hashcheck ok, but insertion failed.", text, domain)

#insert rejected functions
async def submitRejectedJSON(session, text, json, domain):
    # XXX Should be 202 Accepted
    await insert_t(session, t_MachineObsRejected,
       domain=domain,
       comment=text,
       received=sa.func.now(6),
       data=json,
    )

    return text

def get_domain(request):
    """Client domain extraction."""

    # socket.gethostbyaddr is I/O bound, ideally this should be async

    host = request.client.host  # Client's hostname or IP address
    try:
        hostname, aliaslist, ipaddrlist = socket.gethostbyaddr(host)
    except OSError:
        # In the server ip is ::ffff:127.0.0.1 and it fails with
        # OSError: [Errno 97] Address family not supported by protocol
        host = host.rsplit(':', 1)[-1]
        hostname, aliaslist, ipaddrlist = socket.gethostbyaddr(host)

    return hostname

async def insert(session: AsyncSession, model, **kwargs):
    """Insert a new record with the given values.

    Args:
        session: AsyncSession instance
        model: SQLAlchemy model class
        **kwargs: Column values for the new record
    Returns:
        The newly created model instance
    """
    # Filter kwargs to only include valid columns
    model_columns = {column.name for column in model.__table__.columns}
    kwargs = {k: v for k, v in kwargs.items() if k in model_columns}

    # Create model instance
    new_instance = model(**kwargs)

    # Add to session and commit
    session.add(new_instance)
    await session.commit()


async def insert_t(session: AsyncSession, table, **kwargs):
    """Insert a new record into a Core-style Table.

    Args:
        session: AsyncSession instance
        table: SQLAlchemy Table object (like t_MachineObsRejected)
        **kwargs: Column values for the new record
    Returns:
        Dictionary of the inserted values (including server-generated ones)
    """
    # Core-style insert operation
    stmt = sa.insert(table).values(**kwargs)

    # Execute and commit
    result = await session.execute(stmt)
    await session.commit()

    # For tables with auto-incrementing IDs, get the inserted ID
    if result.inserted_primary_key:
        if len(result.inserted_primary_key) == 1:
            kwargs['id'] = result.inserted_primary_key[0]

    # Return the data that was inserted (including any server-generated values)
    return kwargs

async def update(session: AsyncSession, model, where, **kwargs):
    """Update records matching the where clause with the given values.

    Args:
        session: AsyncSession instance
        model: SQLAlchemy model class
        where: BooleanClauseList for filtering
        **kwargs: Column values to update
    Returns:
        ResultProxy with number of rows affected
    """
    assert type(where) is sa.sql.elements.BooleanClauseList

    result = await session.execute(
        sa.update(model)
            .where(where)
            .values(**kwargs)
            .execution_options(synchronize_session="fetch")
    )
    await session.commit()  # Explicit commit
    return result.rowcount  # Returns number of rows updated

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
        async with AsyncSession(engine) as session:
            # Machines.MachineAtSite: Update latest row if any
            result = await session.execute(
                sa.select(MachineAtSite)
                    .filter_by(loggerID=loggerID)
                    .order_by(MachineAtSite.startDate.desc())
                    .limit(1)
            )
            row = result.scalar_one_or_none()
            if row:
                where = (MachineAtSite.loggerID == loggerID) & (MachineAtSite.startDate == row.startDate)
                await update(session, MachineAtSite, where, endDate=startDate)

            # Machines.MachineAtSite: Insert new row
            await insert(session, MachineAtSite, siteID=siteID, loggerID=loggerID,
                         startDate=startDate, endDate=endDate)

            # Machines.Metadata: Update latest row if any
            result = await session.execute(
                sa.select(Metadata)
                    .filter_by(loggerID=loggerID)
                    .order_by(Metadata.startDate.desc())
                    .limit(1)
            )
            row = result.scalar_one_or_none()
            if row:
                where = (Metadata.loggerID == loggerID) & (Metadata.startDate == row.startDate)
                await update(session, Metadata, where, endDate=startDate)

            # Machines.Metadata: Insert new row
            await insert(session, Metadata, loggerID=loggerID, startDate=startDate,
                         endDate=endDate, git_version=git_version, domain=domain)

    except sa.exc.IntegrityError as exc:
        errcode = exc.orig.args[0]
        if errcode == 1062:
            status_code = status.HTTP_200_OK
        else:
            raise
    else:
        status_code = status.HTTP_201_CREATED

    # Return
    response.status_code = status_code
    return 'OK'
