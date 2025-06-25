from ecmwf.opendata import Client
import glob
import re
import pandas as pd
import xarray as xr
import shutil
from cdo import *
cdo = Cdo()
import yaml


with open("/opt/shiny-server/WWCS/config.yaml", 'r') as file:
    config = yaml.safe_load(file)

maxlat = config['maxlat']
minlat = config['minlat']
maxlon = config['maxlon']
minlon = config['minlon']

# Retrieve ECMWF Data 
# --------------------------------

outdir = "/srv/shiny-server/dashboard/ifsdata/"
tmpdir = "/srv/shiny-server/dashboard/ifsdata/tmp/"

if not os.path.exists(tmpdir):
    os.mkdir(tmpdir)

client = Client(source="ecmwf")
dat = pd.datetime.today().strftime("%Y-%m-%d")

steps = [0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57,60,63,66,69,72,75,78,81,84,87,90,93,96,99,102,105,108,111,114,117,120,123,126,129,132,135,138,141,144,150,156,162,168,174,180,186,192,198,204,210,216,222,228,234,240]
files =  [tmpdir + "output_step_" + str(x) + ".grb" for x in steps]

check_files = glob.glob("{}{}".format(tmpdir,'*step*.grb'))
missing_files = [x for x in files if x not in check_files]

while len(missing_files) > 0: 
    for i in missing_files:
        print("Downloading file " + i)
        client.retrieve(
            stream = "enfo",
            levtype = "sfc",
            param = "2t",
            time = 0,
            step = re.split("_|.grb", i)[-2],
            target = i,
            date = -1,            
        )
    check_files = glob.glob("{}{}".format(tmpdir,'*step*.grb'))    
    missing_files = [x for x in check_files if x not in files]

print("All files downloaded")

# Convert to netcdf and merge time-steps
# --------------------------------

files_nc =  [tmpdir + "output_step_" + str(x) + ".nc" for x in steps]
files_nc_tj =  [tmpdir + "output_tj_step_" + str(x) + ".nc" for x in steps]

print("Converting files to netcdf ...")
for i in range(len(files)):
    if not glob.glob(files_nc_tj[i]):
        cdo.copy(input = files[i], output =  files_nc[i], options = '-t ecmwf -f nc')
        cdo.sellonlatbox(str(minlon) + "," + str(maxlon) + "," + str(minlat) + "," + str(maxlon), input = files_nc[i], output = files_nc_tj[i])

cdo.mergetime(input = tmpdir + "output_tj_step_*.nc", output = outdir + "tj_area_" + dat + ".nc")

shutil.rmtree(tmpdir)


# Interpolate to nearest neighbour
# --------------------------------

cnx = mysql.connector.connect(user='wwcs', password=config['dbpass'],
                              host='127.0.0.1',
                              database='SitesHumans')

cursor = cnx.cursor()
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")

coordinates = cursor.fetchall()

ds = xr.open_mfdataset(outdir + "tj_area_" + dat + ".nc", combine= "by_coords")

for c in coordinates: 
    tmp = ds.sel(lon=float(c["longitude"]), lat=float(c["latitude"]), method="nearest")
    mean = tmp.to_array(dim = 'new').mean('new')
    std = tmp.to_array(dim = 'new').std('new')
    tmp["IFS_T_std"] = std
    tmp["IFS_T_mea"] = mean
    tmp2 = tmp[["IFS_T_std","IFS_T_mea"]]
    tmp2.to_netcdf(outdir + "ifs_" + c["stationID"] + "_" + dat + ".nc")      

print("Finished!")

