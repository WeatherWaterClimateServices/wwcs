rm(list = ls())

# Required Libraries
# ------------------------------------------------

library(raster)
library(sf)
library(tidyr)
library(dplyr)
library(httr)
library(jsonlite)
library(RMySQL)

options(pillar.sigfig = 7)

# READ STATION SITES FOR TRAINING
# --------------------------------

source('/home/wwcs/wwcs/WWCS/.Rprofile')

train_points <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::distinct(siteID, .keep_all = TRUE)  %>%
  dplyr::filter(!stringr::str_detect(siteID, pattern = "-S")) %>% 
  dplyr::mutate(lat = as.numeric(latitude), lon = as.numeric(longitude)) %>%
  tibble::as_tibble() # Do not include soil moisture measurements


# CREATE SPATIAL GRID FOR SPATIAL MODEL
# --------------------------------

gadm <- sf::st_read(paste0("/home/wwcs/wwcs/WWCS/boundaries/gadm41_", gadm0, "_0.shp"))

boundary <- sf::st_as_sf(gadm)

grid_spacing <- resolution_gEMOS # In Lon / Lat
polygony <-
  sf::st_make_grid(boundary, square = T, cellsize = grid_spacing) %>% # the grid, covering bounding box
  sf::st_sf() # not really required, but makes the grid nicer to work with later

grid_points <- polygony %>%
  sf::st_coordinates() %>%
  tibble::as_tibble() %>%
  dplyr::rename(lon = X, lat = Y) %>%
  dplyr::select(lon, lat) %>%
  tibble::rowid_to_column("poi")

poi <- nrow(grid_points)
grid <- polygony[boundary, ]


# PREPROCESS TOPOGRAPHIC FEATURES
# --------------------------------

bounds = sf::st_bbox(boundary)
ntiles = ceiling(max((maxlat - minlat), (maxlon - minlon)))
steps = ntiles + 1
rlon = seq(bounds$xmin, bounds$xmax, length.out = steps)
rlat = seq(bounds$ymin, bounds$ymax, length.out = steps)
dir_tiles = "/srv/shiny-server/dashboard/appdata/topotiles/"

#BORIS# hsurf <- raster::brick(paste0(dir_tiles, "hsurf_ecmwf.nc"))
preproc_grid <- data.frame()
preproc_train <- data.frame()

for (x in 1:ntiles) {
  for (y in 1:ntiles) {
    print(paste0("Reading tiles x=", x, " y=", y))
    ele <-
      raster::brick(paste0(dir_tiles, 'DEM-30m-x=', x - 1, '-y=', y - 1, '.tif'))
    tpi5 <-
      raster::brick(paste0(dir_tiles, 'TPI-5--x=', x - 1, '-y=', y - 1, '.nc'))
    tpi20 <-
      raster::brick(paste0(dir_tiles, 'TPI-20--x=', x - 1, '-y=', y - 1, '.nc'))
    tpi100 <-
      raster::brick(paste0(dir_tiles, 'TPI-100--x=', x - 1, '-y=', y - 1, '.nc'))
    
    poi <- grid_points %>%
      dplyr::select(c(lon, lat)) %>%
      dplyr::filter(lon >= rlon[x] &
               lon <= rlon[x + 1] & lat >= rlat[y] & lat <= rlat[y + 1])
    
    train <- train_points %>%
      dplyr::select(c(lon, lat)) %>%
      dplyr::filter(lon >= rlon[x] &
               lon <= rlon[x + 1] & lat >= rlat[y] & lat <= rlat[y + 1])
    
    if (nrow(poi) > 0) {
      ele_poi <- raster::extract(ele, poi) %>% as.vector()
      tpi5_poi <- raster::extract(tpi5, poi) %>% as.vector()
      tpi20_poi <- raster::extract(tpi20, poi) %>% as.vector()
      tpi100_poi <- raster::extract(tpi100, poi) %>% as.vector()
#BORIS#       hsurf_poi <-
#BORIS#         raster::extract(hsurf, poi) %>% as.vector() - ele_poi
      
      preproc_grid <- grid_points %>%
        dplyr::filter(lon >= rlon[x] &
                 lon <= rlon[x + 1] & lat >= rlat[y] & lat <= rlat[y + 1])  %>%
        dplyr::mutate(ELEV = ele_poi) %>%
        dplyr::mutate(TPI5 = tpi5_poi) %>%
        dplyr::mutate(TPI20 = tpi20_poi) %>%
        dplyr::mutate(TPI100 = tpi100_poi) %>%
#BORIS#         dplyr::mutate(HSURF = hsurf_poi) %>%
        dplyr::bind_rows(preproc_grid)
    }
    
    if (nrow(train) > 0) {
      ele_train <- raster::extract(ele, train) %>% as.vector()
      tpi5_train <- raster::extract(tpi5, train) %>% as.vector()
      tpi20_train <- raster::extract(tpi20, train) %>% as.vector()
      tpi100_train <- raster::extract(tpi100, train) %>% as.vector()
#BORIS#       hsurf_train <-
#BORIS#         raster::extract(hsurf, train) %>% as.vector() - ele_train
      
      preproc_train <- train_points %>%
        dplyr::filter(lon >= rlon[x] &
                 lon <= rlon[x + 1] & lat >= rlat[y] & lat <= rlat[y + 1])  %>%
        dplyr::mutate(ELEV = ele_train) %>%
        dplyr::mutate(TPI5 = tpi5_train) %>%
        dplyr::mutate(TPI20 = tpi20_train) %>%
        dplyr::mutate(TPI100 = tpi100_train) %>%
#BORIS#         dplyr::mutate(HSURF = hsurf_train) %>%
        dplyr::bind_rows(preproc_train)
    }
  }
}

bbox <- sf::st_bbox(boundary)
xsize = length(seq(bbox$xmin, bbox$xmax, by = grid_spacing))
ysize = length(seq(bbox$ymin, bbox$ymax, by = grid_spacing))
gridsize = xsize * ysize

# CREATE GRID FOR CDO
# --------------------------------

sink("gemos_grid.txt")
cat("gridtype  = lonlat")
cat("\n")
cat(paste0("gridsize = ", gridsize))
cat("\n")
cat(paste0("xsize = ", xsize))
cat("\n")
cat(paste0("ysize = ", ysize))
cat("\n")
cat(paste0("xfirst = ", bbox$xmin))
cat("\n")
cat(paste0("xinc = ", grid_spacing))
cat("\n")
cat(paste0("yfirst = ", bbox$ymin))
cat("\n")
cat(paste0("yinc = ", grid_spacing))
sink()

preproc_grid <- preproc_grid %>% 
                dplyr::distinct(poi, .keep_all = TRUE)

gemos_folder <- "/srv/shiny-server/dashboard/appdata/topotiles/"

if (!file.exists(gemos_folder)) {
  # If the folder does not exist, create it
  dir.create(gemos_folder, recursive = TRUE)
}

saveRDS(preproc_grid, "preproc_grid.rds")
saveRDS(preproc_train, "preproc_train.rds")
