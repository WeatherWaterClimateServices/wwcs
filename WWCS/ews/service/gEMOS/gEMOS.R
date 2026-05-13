library(tidyverse)
library(lubridate)
library(tidync)
library(SpecsVerification)
library(crch)
library(sf)
library(RColorBrewer)
library(raster)
library(ncdf4)

rm(list = ls())

# SET GLOBAL PARAMETERS
# ------------------------------------------------
source('/home/wwcs/wwcs/WWCS/.Rprofile')

maxlead <- forecast_days * 24
setwd("/srv/shiny-server/ews/service")
curr_date <- Sys.Date()

ifs_dir <- "/srv/shiny-server/dashboard/ifsdata/"


# READ STATION DATA FROM get_wwcs.R
# ------------------------------------------------

obs <- fst::read_fst("/srv/shiny-server/dashboard/appdata/obs.fst")

station_id <- unique(obs$siteID)
rm(obs)
# READ GRID AND PREDICTOR DATA
# ------------------------------------------------

preproc_grid <-  readRDS('/home/wwcs/wwcs/WWCS/ews/service/gEMOS/preproc_grid.rds') %>%
  dplyr::select(-c(poi)) %>%
  dplyr::distinct()

preproc_train <-  readRDS('/home/wwcs/wwcs/WWCS/ews/service/gEMOS/preproc_train.rds')

poi <- preproc_grid %>% 
       dplyr::select(lon, lat)
npoi <- nrow(poi)

tj_gadm <- sf::st_read(paste0("/home/wwcs/wwcs/WWCS/boundaries/gadm41_", gadm0, "_0.shp")) 

# Define NetCDF parameters for writing output
# ------------------------------------------------

lon <-
  ncdf4::ncdim_def("lon", "degrees_east", sort(unique(preproc_grid$lon)))
lat <-
  ncdf4::ncdim_def("lat", "degrees_north", rev(sort(unique(preproc_grid$lat))))

# PREDICT USING TOPOGRAPHIC DATA
# ------------------------------------------------

print(paste0("---READING IFS DATA---"))

# ALLOCATE TRAINING DATA
dmo <- fst::read_fst("/srv/shiny-server/dashboard/appdata/dmo.fst") %>%
  dplyr::rename(IFS_T_mea = ECMWF) %>%
  dplyr::select(-c(Temperature, q05, q25, q75, q95)) %>%
  dplyr::left_join(preproc_train, by = "siteID")

ifs_lead <- distinct(dmo, lead) %>%
  dplyr::filter(lead <= maxlead)  %>%
  na.omit() %>%
  unlist()

## ltimes <- seq(0, maxlead) BORIS here (not needed)

# ALLOCATE PREDICTION DATA


gemos <- data.frame()

filermp <- paste0(ifs_dir, "tj_area_remap.nc")
file <- paste0(ifs_dir, "tj_area_", ymd(curr_date), ".nc")

## BORIS here - undo OM's smart downscaling                                         
extract_mean_temp_vec <- function(train_sites, ncfile, varname) {
  # open file                                                                       
  nc <- nc_open(ncfile)

  # read coordinate vectors                                                         
  lats <- ncvar_get(nc, "lat")
  lons <- ncvar_get(nc, "lon")

  # read full temperature array (lon × lat × time)                                  
  temp <- ncvar_get(nc, varname)

  nc_close(nc)

  # helper to find nearest index                                                    
  nearest_index <- function(coord_vec, target) {
    which.min(abs(coord_vec - target))
  }

  # iterate over all requested points                                               
  means <- sapply(1:nrow(train_sites), function(i) {
    lat_idx <- nearest_index(lats, train_sites$latitude[i])
    lon_idx <- nearest_index(lons, train_sites$longitude[i])

    # extract time series at that cell                                              
    ts <- temp[lon_idx, lat_idx, ]

    mean(ts, na.rm = TRUE) - 273.15
  }, simplify=TRUE)

    ## return                                                                       
    data.frame(siteID=train_sites$siteID, Tavg=means)
}
if (!file.exists(file)){
  ## 0. backup copy                                                                 
  ## dmo_back <- dmo %>%
  ##   filter(siteID == "DAR005")

  ## 1. get mean from tj_map for all siteIDs                                        
  map_temps <- preproc_train %>%
    dplyr::select(siteID, latitude, longitude) %>%
    extract_mean_temp_vec(file, "IFS_T_mea")

  ## 2. vector of means for all siteIDs and reftime = today                         
  dmo_temps <- dmo[, c("siteID", "reftime", "IFS_T_mea")] %>%
    filter(as.Date(reftime) == curr_date) %>%
    group_by(siteID) %>%
    summarize(Tavg = mean(IFS_T_mea))

  ## 3. dmo$IFS_T_mea += (1. - 2.)                                                  
  for (s in intersect(dmo_temps$siteID, preproc_train$siteID)){
    dmo[dmo$siteID == s, "IFS_T_mea"] <- dmo[dmo$siteID == s, "IFS_T_mea"] +
      as.numeric(map_temps[map_temps$siteID == s, "Tavg"] -
      dmo_temps[dmo_temps$siteID == s, "Tavg"])
  }

  ## ## 4a. test new means                                                          
  ## check_temps <- dmo %>%                                                         
  ##   dplyr::select(siteID, reftime, IFS_T_mea) %>%                                
  ##   filter(as.Date(reftime) == curr_date) %>%                                    
  ##   group_by(siteID) %>%                                                         
  ##   summarize(Tavg = mean(IFS_T_mea)) %>%                                        
  ##   left_join(map_temps, by = "siteID")                                          
  ## check_temps                                                                    

  ## ## 4b. test example timeseries                                                 
  ## my.reftime <- "2026-05-05"                                                     
  ## my.site <- "DAR005"                                                            
  ## n <- dmo %>%                                                                   
  ##   filter(siteID == my.site & as.Date(reftime) == my.reftime) %>%               
  ##   dplyr::select("IFS_T_mea")                                                   
  ## o <- dmo_back %>%                                                              
  ##   filter(as.Date(reftime) == my.reftime) %>%                                   
  ##   dplyr::select("IFS_T_mea")                                                   
}

# Check if new forecast data is available already
if (file.exists(file)) {
  system(paste0("cdo remapbil,gEMOS/gemos_grid.txt ", file, " ", filermp))
  
  for (i in 1:length(ifs_lead)) {
    tryCatch(
      expr = {
        print(paste0("Training gEMOS IFS data for lead time ", ifs_lead[i]))
        
        ifs_T_mea <-
          raster::raster(filermp, varname = "IFS_T_mea", band = i)
        ifs_T_std <-
          raster::raster(filermp, varname = "IFS_T_std", band = i)
        
        poi_mea <- raster::extract(ifs_T_mea, poi)
        poi_std <- raster::extract(ifs_T_std, poi)

        train <- dmo %>%
          dplyr::filter(lead == ifs_lead[i]) %>%
          dplyr::filter(reftime > (ymd(curr_date) - days(train_period))) 
        
        emosfit <- crch(
          formula = stats::as.formula(gemos_formula),
          dat     = train,
          dist    = "gaussian",
          type    = "crps"
        )
        
        pred <- preproc_grid %>%
          dplyr::bind_cols(IFS_T_mea = poi_mea - 273.15) %>%
          dplyr::bind_cols(IFS_T_std = poi_std) %>%
          dplyr::mutate(lead = ifs_lead[i],
                        reftime =  as.POSIXct(date(curr_date) - hours(1) + hours(1), tz = timezone_country))
        
        
        predres <- predict(object = emosfit,
                           newdata  = pred,
                           type = "parameter")
        
        gemos <- pred %>%
          dplyr::select(-c(IFS_T_mea, IFS_T_std, TPI5, TPI20, TPI100)) %>% ## , HSURF)) %>% BORIS here 
          dplyr::bind_cols(predres) %>%
          tibble::as_tibble()  %>%
          dplyr::rename(IFS_T_mea = location, IFS_T_std = scale)  %>%
          dplyr::mutate(time = difftime(reftime + hours(lead), as.POSIXct("2023-01-01"), units =
                                          "hours"))
        
        raster_mea <- gemos %>% dplyr::select(lon, lat, IFS_T_mea) %>%
          raster::rasterFromXYZ(crs = "+proj=longlat +datum=WGS84") %>%
          raster::mask(tj_gadm)
        
        raster_std <- gemos %>% dplyr::select(lon, lat, IFS_T_std) %>%
          raster::rasterFromXYZ(crs = "+proj=longlat +datum=WGS84") %>%
          raster::mask(tj_gadm)
        
        raster_elev <- gemos %>% dplyr::select(lon, lat, ELEV) %>%
          raster::rasterFromXYZ(crs = "+proj=longlat +datum=WGS84") %>%
          raster::mask(tj_gadm)
        
        # Create a new netCDF file
        
        time <-
          ncdf4::ncdim_def("time", "hours since 2023-01-01", unique(gemos$time))
        
        # Define the variables and their attributes
        vars <- list(
          IFS_T_mea = ncdf4::ncvar_def("IFS_T_mea", "degrees Celsius", list(lon, lat, time), missval = NA),
          IFS_T_std = ncdf4::ncvar_def("IFS_T_std", "degrees Celsius", list(lon, lat, time), missval = NA),
          ELEV = ncdf4::ncvar_def("ELEV", "meters above sea level", list(lon, lat, time), missval = NA)
        )
        
        nc <-
          ncdf4::nc_create(
            paste0(
              "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_data_",
              ifs_lead[i],
              ".nc"
            ),
            vars
          )
        ncdf4::ncvar_put(nc, "IFS_T_mea", array(values(raster_mea), dim = c(
          length(unique(gemos$time)), length(unique(gemos$lat)), length(unique(gemos$lon))
        )))
        ncdf4::ncvar_put(nc, "IFS_T_std", array(values(raster_std), dim = c(
          length(unique(gemos$time)), length(unique(gemos$lat)), length(unique(gemos$lon))
        )))
        ncdf4::ncvar_put(nc, "ELEV", array(values(raster_elev), dim = c(
          length(unique(gemos$time)), length(unique(gemos$lat)), length(unique(gemos$lon))
        )))
        ncdf4::nc_close(nc)
        
        raster_plot <- raster::aggregate(raster_mea, fact = 4)
        raster::writeRaster(
          raster_plot,
          paste0(
            "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_plot_",
            ifs_lead[i],
            ".tif"
          ),
          overwrite = TRUE
        )
      }, error = function(e) {
        print(paste0("Error in training gEMOS IFS data for lead time ", ifs_lead[i]))
      }
    )
  }
  
  setwd("/srv/shiny-server/dashboard/appdata/gemos_raster/")
  system("cdo -O mergetime raster_data_*.nc raster_merged.nc")
  
} else {
  paste0("Forecast file ", file, " not yet available")
}

