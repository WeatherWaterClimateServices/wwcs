library(tidyr)
library(plotly)
library(RMySQL)
library(RMariaDB)
library(pool)
library(dplyr)
library(readr)
library(sf)
library(lubridate)
library(crch)

# SET GLOBAL PARAMETERS - coming from .Rprofile and config.yaml
# -------------------------------------------------------------

# READ AND ALLOCATE DATA
# -------------------
noaa.file <- file.path(ROOT_DIR, "WWCS/harvest/appdata/noaa.fst")
if (!file.exists(noaa.file)) {
  noaadata <- data.frame()
} else {
  noaadata <- fst::read_fst(noaa.file) %>%
    dplyr::as_tibble()
}

dmo.file       <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/dmo.fst")
if (!file.exists(dmo.file)) {
  dmo <- data.frame()
} else {
  dmo <- fst::read_fst(dmo.file)
}

obs.file <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/obs.fst")
if (!file.exists(obs.file)) {
  obs <- data.frame()
} else {
  obs <- fst::read_fst(obs.file) %>%
  group_by(siteID, time = floor_date(time, unit = "hour")) %>%
    summarise(Precipitation = sum(Precipitation))
}

sites <- sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::filter(harvest == 1)  %>%
  dplyr::select(c(siteID, latitude, longitude, district))


# COMPUTE STATE OF THE HARVEST AND WRITE IT INTO DATABASE
# -------------------

pool_service <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = ifelse(ENV=="PROD", "WWCServices", "WWCServices_DEV"),
    host = 'localhost'
  )

for (s in 1:nrow(sites)) {
  
  id <- sites$siteID[s]
  
  print(paste("Processing site", id))
  
  obs_tmp <- obs %>% 
    dplyr::filter(siteID == id) %>%
    dplyr::mutate(date = as.Date(time)) %>%
    dplyr::group_by(siteID, date) %>%
    dplyr::summarize(
      PR = sum(Precipitation, na.rm = TRUE), .groups = "drop")
  
  fcst_tmp <- dmo %>% 
    dplyr::filter(siteID == id) %>%
    dplyr::mutate(date = as.Date(time)) %>%
    dplyr::group_by(siteID, date, reftime) %>%
    dplyr::summarize(
      PR = sum(IFS_PR_mea, na.rm = TRUE), .groups = "drop")
    
  
  if (nrow(fcst_tmp) > 0) {
    reftimes <- unique(fcst_tmp$reftime)
    for (d in seq_along(reftimes)){
      reft <- reftimes[d]
      reftdate <- as.Date(reft)
      
      PastRain <- obs_tmp %>%
        dplyr::filter(date > reftdate - days(past_rain_days) &
                        date <= reftdate) %>%
        dplyr::summarise(PR = sum(PR, na.rm = TRUE)) %>% 
        unlist()
      
      FutureRain <- fcst_tmp %>%
        dplyr::filter(reftime == reft & date > reftdate &
                        date <= reftdate + days(future_rain_days)) %>%
        dplyr::summarise(PR = sum(PR, na.rm = TRUE)) %>% 
        unlist()
      
      HarvestPotato <- ifelse(PastRain > past_rain_thrs | FutureRain > future_rain_thrs, 0, 1)
      
      tryCatch(
        expr = {
          pool::dbExecute(
            pool_service,
            sprintf(
              'REPLACE INTO Harvest (siteID, date, PastRain, FutureRain, HarvestPotato)
                            VALUES (?, ?, ?, ?, ?);'
              
            ),
            params = list(
              id,
              reftdate,
              PastRain,
              FutureRain,
              HarvestPotato
            )
          )
        },
        error = function(err) {
          print(err)
        }
      ) ## tryCatch
    } ## loop through reftime
  } ## fcst_tmp not empty
} ## loop through sites




