library(tidyverse)
library(lubridate)
library(tidync)
library(SpecsVerification)
library(crch)
library(sf)
library(RColorBrewer)
library(raster)
library(ncdf4)

## SET GLOBAL PARAMETERS - from .Rprofile/config.yaml
# --------------------------------------------------
maxlead <- forecast_days * 24
curr_date <- Sys.Date()

ifs_dir <- file.path(ROOT_DIR, "WWCS/dashboard/ifsdata/")


# READ STATION DATA FROM get_wwcs.R
# ------------------------------------------------

obs <- fst::read_fst(file.path(ROOT_DIR, "WWCS/dashboard/appdata/obs.fst"))

station_id <- unique(obs$siteID)
rm(obs)
# READ GRID AND PREDICTOR DATA
# ------------------------------------------------
ppg.file <- file.path(ROOT_DIR, "WWCS/dashboard/service/gEMOS/preproc_grid.rds")
preproc_grid <-  readRDS(ppg.file) %>%
  dplyr::select(-c(poi)) %>%
  dplyr::distinct()

preproc_train <- readRDS(file.path(ROOT_DIR, "WWCS/dashboard/service/gEMOS/preproc_train.rds"))

poi <- preproc_grid %>% 
       dplyr::select(lon, lat)
npoi <- nrow(poi)

tj_gadm <- sf::st_read(paste0(ROOT_DIR, "/WWCS/boundaries/gadm41_", gadm0, "_0.shp")) 

# Define NetCDF parameters for writing output
# ------------------------------------------------

lon <-
  ncdf4::ncdim_def("lon", "degrees_east", sort(unique(preproc_grid$lon)))
lat <-
  ncdf4::ncdim_def("lat", "degrees_north", rev(sort(unique(preproc_grid$lat))))

# PREDICT USING TOPOGRAPHIC DATA
# ------------------------------------------------

print(paste0("---READING IFS DATA---"))

## ALLOCATE TRAINING DATA
dmo.file <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/dmo.fst")
dmo <- fst::read_fst(dmo.file) %>%
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

# Check if new forecast data is available already
if (file.exists(file)) {
    system(paste0("cdo remapbil,",ROOT_DIR,"/WWCS/dashboard/service/gEMOS/gemos_grid.txt ",
                  file, " ", filermp))
  
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
            paste0(ROOT_DIR, 
              "/WWCS/dashboard/appdata/gemos_raster/raster_data_",
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
          paste0(ROOT_DIR,
            "/WWCS/dashboard/appdata/gemos_raster/raster_plot_",
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
  
  setwd(file.path(ROOT_DIR, "WWCS/dashboard/appdata/gemos_raster/"))
  system("cdo -O mergetime raster_data_*.nc raster_merged.nc")
  
} else {
  paste0("Forecast file ", file, " not yet available")
}

