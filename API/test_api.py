import contextlib
import datetime
import hashlib

# Requirements
import httpx
import MySQLdb
import pytest


# The tests are run in the local environment, first run the application with:
# flask --app api run --debug
URL = 'http://localhost:8000'

# In the whole test suite we will use fake site and loggers
# TODO Instead we should create/destroy a test database
siteID = 'test-site'
loggerID = 'test-logger'


def connect():
    return MySQLdb.connect("localhost", "wwcs", "EnterMySQLPassword")


@contextlib.contextmanager
def get_cursor(commit=False):
    conn = connect()
    cursor = conn.cursor()
    yield cursor
    cursor.close()
    if commit:
        conn.commit()
    conn.close()


def execute(cursor, sql, args=None):
    if sql[-1] != ';':
        sql += ';'
    #print('DEBUG', sql, args)
    cursor.execute(sql, args)

def cleanup():
    tables = [
        'Machines.MachineAtSite',
        'Machines.Metadata',
        'Machines.MachineObs',
    ]
    with get_cursor(commit=True) as cursor:
        for table in tables:
            sql = f'DELETE FROM {table} WHERE loggerID = %s'
            execute(cursor, sql, [loggerID])

        assert get_siteID(cursor, loggerID) is None
        assert get_git_version(cursor, loggerID) is None

def count(cursor, table):
    sql = f"SELECT COUNT(*) FROM {table};"
    execute(cursor, sql)
    rows = cursor.fetchall()
    assert len(rows) == 1
    n, = rows[0]
    return n

def get_last_reject(cursor):
    sql = 'SELECT * FROM Machines.MachineObsRejected ORDER BY received DESC LIMIT 1;'
    execute(cursor, sql)
    rows = cursor.fetchall()
    if len(rows) == 0:
        return None

    return rows[0]

def get_siteID(cursor, loggerID, table='Machines.MachineAtSite'):
    rows = select(cursor, table, loggerID=loggerID)
    if len(rows) == 0:
        return None

    assert len(rows) == 1
    row = rows[0]
    return row[0] # siteID

def get_git_version(cursor, loggerID, table='Machines.Metadata'):
    rows = select(cursor, table, ['git_version'], loggerID=loggerID)
    if len(rows) == 0:
        return None

    assert len(rows) == 1
    row = rows[0]
    return row[0]


def select(cursor, table, columns=None, **kwargs):
    columns = ', '.join(columns) if columns else '*'
    where = []
    values = []
    for col, val in kwargs.items():
        where.append(f'{col} = %s')
        values.append(val)
    where = ' AND '.join(where)
    sql = f'SELECT {columns} FROM {table} WHERE {where};'
    execute(cursor, sql, values)
    return cursor.fetchall()

def test_register():
    # Start clean
    cleanup()

    with get_cursor() as cursor:
        d = count(cursor, 'Machines.MachineAtSite')
        m = count(cursor, 'Machines.Metadata')
        assert get_siteID(cursor, loggerID) is None
        assert get_git_version(cursor, loggerID) is None

    # Register
    git_version = 'test-git-version'
    json = {'siteID': siteID, 'loggerID': loggerID, 'git_version': git_version}
    response = httpx.post(f'{URL}/register', json=json)
    assert response.status_code in [200, 201]
    assert response.headers['content-type'] == 'application/json'
    with get_cursor() as cursor:
        assert count(cursor, 'Machines.MachineAtSite') == d + 1
        assert count(cursor, 'Machines.Metadata') == m + 1
        assert get_siteID(cursor, loggerID) == siteID
        assert get_git_version(cursor, loggerID) == git_version

    # Cleanup
    cleanup()


@pytest.fixture()
def logger():
    # Start clean
    cleanup()

    # Register
    json = {'siteID': siteID, 'loggerID': loggerID, 'git_version': ''}
    response = httpx.post(f'{URL}/register', json=json)
    assert response.status_code == 201

    # Yield nothing
    yield None
    cleanup()


def test_insert(logger):
    now = datetime.datetime.now().replace(microsecond=0)

    with get_cursor() as cursor:
        n = count(cursor, 'Machines.MachineObs')
        m = count(cursor, 'Machines.MachineObsRejected')

    # Insert
    timestamp = "2023-04-21 23:12:08"
    key = f"{siteID}; {loggerID}; {timestamp}"
    sign = hashlib.sha256(key.encode('utf-8')).hexdigest()
    json = {
      "sign": sign,
      "timestamp": timestamp,
      "ta": -999.9899902,
      "rh": -999.9899902,
      "p": 963.1785889,
      "ts10cm": -999.9899902,
      "logger_ta": 24.53011513,
      "U_Battery1": 4.165347099,
      "Temp_Battery1": 27.00457764,
      "Charge_Battery1": 2013.512451,
      "U_Battery2": 4.18915081,
      "Temp_Battery2": 24.6607914,
      "Charge_Battery2": 2016.806274,
      "U_Solar": 0,
      "loggerID": loggerID,
      "git_version": "FlashGIT",
      "signalStrength": 20
    }
    response = httpx.post(f'{URL}/insert', json=json)
    assert response.status_code == 200 # TODO Change to 201 next year
    # Should be 'application/json'
    assert response.headers['content-type'] == 'application/json'

    # Verify inserted data
    with get_cursor() as cursor:
        assert count(cursor, 'Machines.MachineObs') == n + 1
        assert count(cursor, 'Machines.MachineObsRejected') == m

        exclude = {'sign', 'git_version'}
        expected = {k: v for k, v in json.items() if k not in exclude}
        cols = ', '.join(expected.keys())
        sql = f'SELECT {cols}, received FROM Machines.MachineObs WHERE loggerID = %s;'
        execute(cursor, sql, [loggerID])
        rows = cursor.fetchall()
        row = rows[-1]
        assert str(row[-1]) >= str(now) # Check received column
        for col, exp in zip(row, expected.values()):
            if type(col) is float:
                assert f'{col:0.2f}' == f'{exp:0.2f}'
            else:
                assert str(col) == str(exp)


def test_insert_dup(logger):
    with get_cursor() as cursor:
        n = count(cursor, 'Machines.MachineObs')
        m = count(cursor, 'Machines.MachineObsRejected')

    # Insert
    timestamp = "2023-04-21 23:12:08"
    key = f"{siteID}; {loggerID}; {timestamp}"
    sign = hashlib.sha256(key.encode('utf-8')).hexdigest()
    json = {
      "sign": sign,
      "timestamp": timestamp,
      "ta": -999.9899902,
      "rh": -999.9899902,
      "p": 963.1785889,
      "ts10cm": -999.9899902,
      "logger_ta": 24.53011513,
      "U_Battery1": 4.165347099,
      "Temp_Battery1": 27.00457764,
      "Charge_Battery1": 2013.512451,
      "U_Battery2": 4.18915081,
      "Temp_Battery2": 24.6607914,
      "Charge_Battery2": 2016.806274,
      "U_Solar": 0,
      "loggerID": loggerID,
      "git_version": "FlashGIT",
      "signalStrength": 20
    }
    response = httpx.post(f'{URL}/insert', json=json)
    assert response.status_code == 200 # TODO Change to 201 next year
    # Should be 'application/json'
    assert response.headers['content-type'] == 'application/json'

    # Post again (dup)
    response = httpx.post(f'{URL}/insert', json=json)
    assert response.status_code == 200
    assert response.headers['content-type'] == 'application/json'
    assert response.json() == 'Duplicate data NOT inserted'

    # Verify inserted data
    with get_cursor() as cursor:
        assert count(cursor, 'Machines.MachineObs') == n + 1
        assert count(cursor, 'Machines.MachineObsRejected') == m


def test_insert_fail(logger):
    with get_cursor() as cursor:
        n = count(cursor, 'Machines.MachineObs')
        m = count(cursor, 'Machines.MachineObsRejected')

    response = httpx.post(f'{URL}/insert', json={})
    assert response.status_code == 200
    with get_cursor() as cursor:
        assert count(cursor, 'Machines.MachineObs') == n
        assert count(cursor, 'Machines.MachineObsRejected') == m + 1

        domain, received, data, comment = get_last_reject(cursor)
        assert comment == 'Incorrect JSON body'

@pytest.mark.parametrize("timestamp", [
    '1960-01-01 00:00:00',
    '1970-01-01 00:00:00',
    '1970-01-01 00:00:01',
    '1995-03-23 12:15:00',
    '2099-12-21 19:33:33',
])
def test_insert_fail_timestamp(logger, timestamp):
    with get_cursor() as cursor:
        n = count(cursor, 'Machines.MachineObs')
        m = count(cursor, 'Machines.MachineObsRejected')

    data = {'timestamp': timestamp, 'loggerID': loggerID, 'sign': 'fake-sign'}
    response = httpx.post(f'{URL}/insert', json=data)
    assert response.status_code == 200
    with get_cursor() as cursor:
        assert count(cursor, 'Machines.MachineObs') == n
        assert count(cursor, 'Machines.MachineObsRejected') == m + 1

        domain, received, data, comment = get_last_reject(cursor)
        assert comment == 'Invalid timestamp'
