import os
import re
from ecmwfapi import *
from cdo import *
cdo = Cdo()
import csv
import urllib
import requests
import json
import pandas as pd
from datetime import datetime, timedelta
import fnmatch
import mysql.connector
import yaml
from dotenv import load_dotenv

# Configuration
load_dotenv("/opt/shiny-server/WWCS/.env")
ENV = os.environ.get('ENV')
USERNAME = os.environ.get('USERNAME', 'wwcs')
PASSWORD = os.environ.get('PASSWORD')


# Load YAML data from a file
with open('/opt/shiny-server/WWCS/config.yaml', 'r') as file:
    config = yaml.safe_load(file)
    
train_period = config['train_period']
forecast_days = config['forecast_days']
total_days = train_period + forecast_days

# Delete all files which are old
# --------------------------------

directory_path = "/srv/shiny-server/dashboard/ifsdata"

date_pattern = r'(\d{4})-(\d{2})-(\d{2})'

two_months_ago = datetime.now() - timedelta(days=60)

# Iterate over all files in the directory.
for filename in os.listdir(directory_path):
    # Search for the date in the filename using regex.
    match = re.search(date_pattern, filename)
    
    if match:
        # Extract year, month, and day from the regex groups.
        year, month, day = map(int, match.groups())
        
        try:
            # Create a datetime object from the extracted date.
            file_date = datetime(year, month, day)
            
            # Compare the extracted date with the threshold date.
            if file_date < two_months_ago:
                # Build the full path of the file to delete.
                file_path = os.path.join(directory_path, filename)
                os.remove(file_path)
                print(f"Deleted: {file_path}")
        except ValueError:
            # Skip files with invalid dates.
            print(f"Invalid date in filename: {filename}")

# Define global variables
# --------------------------------

server = ECMWFService("mars")
outdir = "/srv/shiny-server/dashboard/ifsdata"
dat = [d.strftime("%Y-%m-%d") for d in pd.date_range(datetime.today() - timedelta(days = total_days), datetime.today())]
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

for i in dat:
    missing_files = []
    for t in coordinates:
        station_file = 'ifs_' + t[0].replace(" ", "") + '_' + i + '.nc'
        if not os.path.isfile(station_file):
            missing_files.append(t)

    if not missing_files:
        print(f"Skipping date {i}, all files have already been retrieved and processed ...")
        continue

    if not os.path.isfile("tj_area_" + str(i) + ".nc"):
        server.execute(
            {
                "class": "od",
                "date": i,
                "expver": "1",
                "levtype": "sfc",
                "param": "167.128",
                "step": "0/3/6/9/12/15/18/21/24/27/30/33/36/39/42/45/48/51/54/57/60/63/66/69/72/75/78/81/84/87/90/93/96/99/102/105/108/111/114/117/120/123/126/129/132/135/138/141/144/150/156/162/168/174/180/186/192/198/204/210/216/222/228/234/240",
                "stream": "enfo",
                "time": "00:00:00",
                "type": "em",
                "grid": "0.1/0.1",
                "area": "41.5/67/36.5/75.5",
            },
            "output_em.grb")
        server.execute(
            {
                "class": "od",
                "date": i,
                "expver": "1",
                "levtype": "sfc",
                "param": "167.128",
                "step": "0/3/6/9/12/15/18/21/24/27/30/33/36/39/42/45/48/51/54/57/60/63/66/69/72/75/78/81/84/87/90/93/96/99/102/105/108/111/114/117/120/123/126/129/132/135/138/141/144/150/156/162/168/174/180/186/192/198/204/210/216/222/228/234/240",
                "stream": "enfo",
                "time": "00:00:00",
                "type": "es",
                "grid": "0.1/0.1",
                "area": "41.5/67/36.5/75.5",
            },
            "output_es.grb")
        # Postprocess Data
        # --------------------------------
        cdo.copy(input="output_es.grb", output="output_es.nc", options='-t ecmwf -f nc')
        cdo.copy(input="output_em.grb", output="output_em.nc", options='-t ecmwf -f nc')
        cdo.chname("T2M,IFS_T_std", input="output_es.nc", output="output_es_rn.nc")
        cdo.chname("T2M,IFS_T_mea", input="output_em.nc", output="output_em_rn.nc")
        cdo.merge(input="output_es_rn.nc output_em_rn.nc", output="tj_area_" + str(i) + ".nc")

    # Interpolate Data to Stations
    # --------------------------------
    for t in missing_files:
        print(f"Preparing data for {t[0]} on date {i}")
        arg = 'lon=' + str(t[2]) + '_lat=' + str(t[1])
        fout = 'ifs_' + t[0].replace(" ", "") + '_' + i + '.nc'
        cdo.remapnn(arg, input="tj_area_" + str(i) + ".nc", output=fout)
        
# Go to parent directory again
os.chdir("/srv/shiny-server/dashboard")        
