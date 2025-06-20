# ------------------------------------------------
# SCRIPT TO DOWNLOAD AND PROCESS THE BOUNDARIES OF A COUNTRY
#
# Contact: omar.bellprat@meteoswiss.ch
# Date: 26.03.2024
#
# ------------------------------------------------

source('/home/wwcs/wwcs/WWCS/.Rprofile')
library(raster)

system(paste0('wget -P /home/wwcs/wwcs/WWCS/boundaries https://geodata.ucdavis.edu/gadm/gadm4.1/shp/gadm41_', gadm0 ,'_shp.zip'))
system(paste0('unzip -o /home/wwcs/wwcs/WWCS/boundaries/gadm41_', gadm0 ,'_shp.zip -d /home/wwcs/wwcs/WWCS/boundaries/'))

country <- raster::shapefile(paste0('/home/wwcs/wwcs/WWCS/boundaries/gadm41_', gadm0, '_0.shp'))
wld <- raster::rasterToPolygons(raster(ncol = 1, nrow = 1, crs = proj4string(country)))
mask <- raster::erase(wld, country)
mask_sf <- sf::st_as_sf(mask, crs = st_crs(4326))
saveRDS(mask_sf, '/home/wwcs/wwcs/WWCS/boundaries/mask.rds')
