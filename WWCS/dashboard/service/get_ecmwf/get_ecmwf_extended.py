import os
from ecmwfapi import *
from cdo import *
cdo = Cdo()
import csv
import urllib
import requests
import json
import pandas as pd
import datetime as datetime
import fnmatch
import mysql.connector
import yaml
from dotenv import load_dotenv

# Configuration
load_dotenv("/opt/shiny-server/WWCS/.env")
ENV = os.environ.get('ENV')
USERNAME = os.environ.get('USERNAME', 'wwcs')
PASSWORD = os.environ.get('PASSWORD')

# Define global variables
# --------------------------------

with open("/opt/shiny-server/WWCS/config.yaml", 'r') as file:
    config = yaml.safe_load(file)

train_period = config['train_period']
forecast_days = config['forecast_days']
total_days = train_period + forecast_days

server = ECMWFService("mars")
outdir = "/srv/shiny-server/dashboard/ifsdata"
dat = [d.strftime("%Y-%m-%d") for d in pd.date_range(datetime.datetime.today() - datetime.timedelta(days = 20), datetime.datetime.today())]
os.chdir(outdir)

# Read station names and locations
# --------------------------------

cnx = mysql.connector.connect(user='wwcs', password=PASSWORD,
                              host='127.0.0.1',
                              database='SitesHumans')

cursor = cnx.cursor()
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")

coordinates = cursor.fetchall()

# Retrieve ECMWF Data 
# --------------------------------
# Check if file output_' + i + '_extended.nc exists
# Otherwise download it

for i in dat:
    missing_files = []
    for t in coordinates:
        station_file = 'ifs_' + t[0].replace(" ", "") + '_' + i + '_extended.nc'
        if not os.path.isfile(station_file):
            missing_files.append(t)

    if not missing_files:
        print(f"Skipping date {i}, all files have already been retrieved and processed ...")
        continue

    if not os.path.isfile("output_" + i + "_extended.nc"):
        server.execute(
            {
                "class": "od",
                "date": i,
                "expver": "1",
                "levtype": "sfc",
                "param": "20.3/129.128/164.128/186.128/187.128/188.128/228.128/228050",
                "number": "1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30/31/32/33/34/35/36/37/38/39/40/41/42/43/44/45/46/47/48/49/50",
                "step": "0/3/6/9/12/15/18/21/24/27/30/33/36/39/42/45/48/51/54/57/60/63/66/69/72/75/78/81/84/87/90/93/96/99/102/105/108/111/114/117/120/123/126/129/132/135/138/141/144/150/156/162/168/174/180/186/192/198/204/210/216/222/228/234/240",
                "stream": "enfo",
                "time": "00:00:00",
                "type": "pf",
                "grid": "0.1/0.1",
                "area": "41.5/67/36.5/75.5",
            },
            "output_extended.grb")
        os.system('grib_to_netcdf output_extended.grb -o output_' + i + '_extended.nc')

    for t in missing_files:
        print(f"Preparing data for {t[0]} on date {i}")
        arg = 'lon=' + str(t[2]) + '_lat=' + str(t[1])
        fout = 'ifs_' + t[0].replace(" ", "") + '_' + i + '_extended.nc'
        cdo.remapnn(arg, input="output_" + i + "_extended.nc", output=fout)

# Go to parent directory again
os.chdir("/srv/shiny-server/dashboard")