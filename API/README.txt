# api.py

Manages incoming data from stations (only the newer stations, older ones are
still using the .php scripts).

Listens port 5000.

In development run the program with:

    uvicorn api_station:app --reload

In production the program is started by a Systemd service file.

Routes:

    POST /post/insert
    GET  /post/test

The /post prefix is added by the Nginx configuration, when testing without
Nginx remove it.


# api_wwcs.py

Manages incoming and outgoing information for the services.

Listens port 5050.

In development run the program with:

    flask --app api_wwcs run --debug

In production the program is started by a Systemd service file.

Routes:

    GET  /services/forecast
    POST /services/irrigationApp
    GET  /services/irrigationNeed
    GET  /services/map
    GET  /services/warning

The /services prefix is added by the Nginx configuration, when testing without
Nginx remove it.


# Tests

To run the tests locally first setup a virtual environment:

    make install
    ./venv/bin/pip install -r requirements-test.txt

Then start the API in one terminal:

    source venv/bin/activate
    uvicorn api_station:app

And run the tests in another terminal:

    source venv/bin/activate
    pytest
