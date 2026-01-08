import collections
import contextlib
import datetime
import hashlib
import random
import string
import time

# Requirements
import httpx
import MySQLdb
import pytest

from common import USERNAME, PASSWORD


URL = 'http://localhost:8000'

# In the whole test suite we will use fake site and loggers
# TODO Instead we should create/destroy a test database
siteID = 'test-site'
loggerID = 'test-logger'


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

        assert get_machine_at_site(cursor, loggerID) == []
        assert get_metadata(cursor, loggerID) == []

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

def get_machine_at_site(cursor, loggerID):
    return select(cursor, 'Machines.MachineAtSite', loggerID=loggerID, order_by='startDate')

def get_metadata(cursor, loggerID):
    return select(cursor, 'Machines.Metadata', loggerID=loggerID)


def select(cursor, table, columns=None, order_by=None, **kwargs):
    columns = ', '.join(columns) if columns else '*'
    where = []
    values = []
    for col, val in kwargs.items():
        where.append(f'{col} = %s')
        values.append(val)
    where = ' AND '.join(where)
    sql = f'SELECT {columns} FROM {table} WHERE {where}'
    if order_by:
        sql += f' ORDER BY {order_by}'
    sql += ';'
    execute(cursor, sql, values)
    rows = cursor.fetchall()

    # Return list of namedtuples
    column_names = [col[0] for col in cursor.description]
    Result = collections.namedtuple('Result', column_names)
    return [Result(*row) for row in rows]


def cmp_machine_at_site(row, siteID, startDate, endDate):
    assert row.siteID == siteID
    assert abs(row.startDate - startDate) < datetime.timedelta(seconds=1)
    assert abs(row.endDate - endDate) < datetime.timedelta(seconds=1)

def cmp_metadata(row, startDate, endDate, git_version):
    assert abs(row.startDate - startDate) < datetime.timedelta(seconds=1)
    assert abs(row.endDate - endDate) < datetime.timedelta(seconds=1)
    assert row.git_version == git_version


def test_register():
    # Start clean
    cleanup()

    with get_cursor() as cursor:
        assert get_machine_at_site(cursor, loggerID) == []
        assert get_metadata(cursor, loggerID) == []

    # Register
    git_version = 'test-git-version'
    json = {'loggerID': loggerID, 'siteID': siteID, 'git_version': git_version}
    t0 = datetime.datetime.now()
    response = httpx.post(f'{URL}/register', json=json)
    assert response.status_code in [200, 201]
    assert response.headers['content-type'] == 'application/json'
    with get_cursor() as cursor:
        rows = get_machine_at_site(cursor, loggerID)
        assert len(rows) == 1
        cmp_machine_at_site(rows[0], siteID, t0, datetime.datetime(2100, 1, 1))

        rows = get_metadata(cursor, loggerID)
        assert len(rows) == 1
        cmp_metadata(rows[0], t0, datetime.datetime(2100, 1, 1), git_version)

    # Register again (n times)
    n = 2
    expected = [(t0, siteID, git_version)]
    for i in range(n):
        time.sleep(2)
        site_id = f'test-site-{i}'
        commit_id = ''.join(random.sample(string.hexdigits, 8))
        expected.append((datetime.datetime.now(), site_id, commit_id))

        json = {'loggerID': loggerID, 'siteID': site_id, 'git_version': commit_id}
        response = httpx.post(f'{URL}/register', json=json)
        assert response.status_code in [200, 201]
        assert response.headers['content-type'] == 'application/json'

    n = len(expected)
    with get_cursor() as cursor:
        rows = get_machine_at_site(cursor, loggerID)
        assert len(rows) == n
        for i in range(n):
            tstart, site_id, commit_id = expected[i]
            tend = expected[i+1][0] if (i + 1) < n else datetime.datetime(2100, 1, 1)
            cmp_machine_at_site(rows[i], site_id, tstart, tend)

        rows = get_metadata(cursor, loggerID)
        assert len(rows) == n
        for i in range(n):
            tstart, site_id, commit_id = expected[i]
            tend = expected[i+1][0] if (i + 1) < n else datetime.datetime(2100, 1, 1)
            cmp_metadata(rows[i], tstart, tend, commit_id)

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
        "signalStrength": 20,
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
        exclude = 'sign git_version U_Battery2 Temp_Battery2 Charge_Battery2'.split()
        expected = {
            k.replace('Charge_Battery1', 'Charge_Battery').replace('Temp_Battery1', 'Temp_Battery'): v
            for k, v in json.items()
            if k not in exclude
        }
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
