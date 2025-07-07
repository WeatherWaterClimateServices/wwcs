library(tidyverse)
library(lubridate)
library(ncdf4)
library(httr)
library(RMySQL)
library(jsonlite)
library(raster)
library(dplyr)

rm(list = ls())

# READ STATION DATA FROM WWCS.TJ
# ------------------------------------------------
source('/home/wwcs/wwcs/WWCS/.Rprofile')

sites <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::filter(harvest == 1) %>% 
  dplyr::distinct(siteID, .keep_all = TRUE) %>% 
  dplyr::as_tibble() 
  
# DEFINE GRID INDICES FOR STATION0S LOCATIONS
# ------------------------------------------------

# Grid of NOAA STAR data
lat_vector <- seq(-60, 70, by = 0.02)
lon_vector <- seq(-180, 179.98, by = 0.02)
nstat <- dim(sites)[1]

closest <- function(xv, sv) {
  min(which(abs(xv - sv) == min(abs(xv - sv))))
}

bd_gadm <- sf::st_read(paste0("/home/wwcs/wwcs/WWCS/boundaries/gadm41_", gadm0, "_0.shp"))

ind <- array(NA, dim = c(length(sites$longitude), 2))

for (i in 1:nstat) {
  ind[i, 1] <- closest(lon_vector, sites$longitude[i])
  ind[i, 2] <- closest(lat_vector, sites$latitude[i])
}

# Selection grid for selected country

bounds = c(minlon, minlat, maxlon, maxlat)

ind_bounds_lon <-
  seq(closest(lon_vector, bounds[1]), closest(lon_vector, bounds[3]))
ind_bounds_lat <-
  seq(closest(lat_vector, bounds[2]), closest(lat_vector, bounds[4]))

ind_bounds <-
  expand.grid("lon" = ind_bounds_lon, "lat" = ind_bounds_lat) %>%
  as_tibble()

# READ NOAA DATA AND INTERPOLATE TO STATION
# ------------------------------------------------

if (file.exists('/srv/shiny-server/harvest/appdata/noaa.fst')) {
  noaa <- fst::read_fst("/srv/shiny-server/harvest/appdata/noaa.fst")
  last_entry <- tail(noaa$time, 1)
  noaa <- noaa %>%
    filter(time != last_entry)
  
} else {
  noaa <- data.frame()
  last_entry <- 0
}

flist <-
  list.files(path = "/srv/shiny-server/harvest/appdata/noaa_star", full.names = TRUE) %>%
  as_tibble() %>%
  na.omit() %>%
  dplyr::rename(filename = value) %>%
  dplyr::mutate(filesize = file.size(filename),
                filelength = stringr::str_length(filename)) %>%
  dplyr::filter(filesize > 300000 & filelength > 70) %>%
  dplyr::mutate(time = as.POSIXct(
    stringr::str_sub(filename, -52, -39),
    format = "%Y%m%d%H%M%S",
    tz = "UTC"
  ))

datelist <- date(flist$time) %>%
  unique()

timesteps <- seq(0, 24, by = 6)

for (i in 1:length(datelist)) {
  flist_sel <- flist %>%
    dplyr::filter(date(time) == datelist[i])
  
  for (j in 1:(length(timesteps) - 1)) {
    flist_sel <- flist %>%
      dplyr::filter(date(time) == datelist[i] &
                      hour(time) >= timesteps[j] & hour(time) < timesteps[j + 1])
    
    noaa_map <- data.frame()
    
    if (nrow(flist_sel) > 0) {
      for (k in 1:nrow(flist_sel)) {
        time <- flist_sel$time[k]
        if (k < nrow(flist_sel)) {
          time_2 <- flist_sel$time[k + 1]
        }  else {
          time_2 <- time + days(1)
        }
        
        # Only use the latest analysis for the same time, only update new data files
        
        if (time_2 > time & time >= last_entry) {
          print(paste0("Reading satellite image of time = ", time))
          nc_file <- nc_open(paste0(flist_sel$filename[k]))
          Precipitation <- ncvar_get(nc_file, "RRQPE")[ind]
          
          noaa <- sites %>%
            dplyr::select(siteID) %>%
            cbind(Precipitation, time) %>%
            bind_rows(noaa)
          
          noaa_map <-
            ncvar_get(nc_file, "RRQPE")[as.matrix(ind_bounds)] %>%
            as_tibble() %>%
            dplyr::rename(Precipitation = value) %>%
            bind_cols(ind_bounds) %>%
            dplyr::mutate(time = time, lat = lat_vector[lat], lon = lon_vector[lon]) %>%
            bind_rows(noaa_map)
          
          nc_close(nc_file)
          
        } else {
          print(paste0("Skip satellite image of time = ", time))
        }
      }
    }
    
    if (nrow(noaa_map) > 0) {
      noaa_raster <- noaa_map %>%
        dplyr::mutate(Precipitation = ifelse(Precipitation < 0, NA, Precipitation)) %>%
        group_by(lon, lat) %>%
        summarise(Precipitation = sum(Precipitation, na.rm = T))  %>%
        rasterFromXYZ(crs = "+proj=longlat +datum=WGS84") %>%
        mask(bd_gadm)
      
      raster::writeRaster(
        noaa_raster,
        paste0(
          "/srv/shiny-server/harvest/appdata/noaa_raster/raster_",
          datelist[i] ,
          "-",
          timesteps[j],
          ".tif"
        ),
        overwrite = TRUE
      )
    }
  }
}

noaa$Precipitation[noaa$Precipitation < 0] <- NA

# Compute hourly data

noaa_hourly <- noaa %>%
  group_by(siteID, time = floor_date(time, unit = "hour")) %>%
  summarise(Precipitation = sum(Precipitation))

fst::write_fst(noaa_hourly, path = "/srv/shiny-server/harvest/appdata/noaa.fst", compress = 0)

