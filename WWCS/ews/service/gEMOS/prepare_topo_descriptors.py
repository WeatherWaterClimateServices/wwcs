from itertools import product
import xarray as xr
import elevation as ele
import numpy as np
import os.path
from topo_descriptors import topo, helpers
import yaml

# Read YAML file
with open("/opt/shiny-server/WWCS/config.yaml", 'r') as file:
    config = yaml.safe_load(file)

# Access parameters
minlat = config.get("minlat")
maxlat = config.get("maxlat")
minlon = config.get("minlon")
maxlon = config.get("maxlon")

bounds = [minlon, minlat, maxlon, maxlat]

ntiles = int(np.ceil(max((maxlat - minlat), (maxlon - minlon))))
steps = ntiles + 1
margin = 0.5
margin2 = 1 # To compute meaningful values TPI values at boundaries
rlon = np.linspace(bounds[0], bounds[2], steps)
rlat = np.linspace(bounds[1], bounds[3], steps)

outdir = '/srv/shiny-server/dashboard/appdata/topotiles/'

if not os.path.exists(outdir):
   os.makedirs(outdir)
   
for x in range(ntiles):
    for y in range(ntiles): 
        file = outdir + 'DEM-30m' + '-x=' + str(x) + '-y=' + str(y) + '.tif'
        file2 = outdir + 'DEM-90m' + '-x=' + str(x) + '-y=' + str(y) + '.tif'
        if not os.path.isfile(file):
            print("Preparing file " + file)
            ele.clip(bounds=[rlon[x]-margin,rlat[y]-margin,rlon[x+1]+margin,rlat[y+1]+margin], output = file)
        if not os.path.isfile(file2):
            ele.clip(bounds=[rlon[x]-margin2,rlat[y]-margin2,rlon[x+1]+margin2,rlat[y+1]+margin2], product = "SRTM3", output = file2)


for x in range(ntiles):
    for y in range(ntiles): 
        filein = outdir + 'DEM-30m' + '-x=' + str(x) + '-y=' + str(y) + '.tif'
        filein2 = outdir + 'DEM-90m' + '-x=' + str(x) + '-y=' + str(y) + '.tif'
        fileout5 = outdir + 'TPI-5-' + '-x=' + str(x) + '-y=' + str(y) + '.nc'
        fileout20 = outdir + 'TPI-20-' + '-x=' + str(x) + '-y=' + str(y) + '.nc'
        fileout100 = outdir + 'TPI-100-' + '-x=' + str(x) + '-y=' + str(y) + '.nc'

        if not os.path.isfile(fileout5):
            dem = xr.open_rasterio(filein)
            dem = dem.isel(band=0, drop=True)

            scale_meters = 500
            scale_pixel, __ = helpers.scale_to_pixel(scale_meters, dem)
            tpi = topo.tpi(dem, scale_pixel).rename("tpi")
            tpi5 = tpi.rename({'x': 'lon','y': 'lat'})
            tpi5.to_netcdf(fileout5)
            
        if not os.path.isfile(fileout100):
            dem = xr.open_rasterio(filein2)
            dem = dem.isel(band=0, drop=True)

            scale_meters = 20000
            scale_pixel, __ = helpers.scale_to_pixel(scale_meters, dem)
            tpi = topo.tpi(dem, scale_pixel).rename("tpi")
            tpi20 = tpi.rename({'x': 'lon','y': 'lat'})
            tpi20.to_netcdf(fileout20)

            scale_meters = 100000
            scale_pixel, __ = helpers.scale_to_pixel(scale_meters, dem)
            tpi = topo.tpi(dem, scale_pixel).rename("tpi")
            tpi100 = tpi.rename({'x': 'lon','y': 'lat'})
            tpi100.to_netcdf(fileout100)            
