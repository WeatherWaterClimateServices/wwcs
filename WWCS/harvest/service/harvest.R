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

rm(list = ls())

setwd("/srv/shiny-server/planting/")
options(shiny.sanitize.errors = FALSE)
source('/home/wwcs/wwcs/WWCS/.Rprofile')

# READ AND ALLOCATE DATA
# -------------------

if (!file.exists("/srv/shiny-server/harvest/appdata/noaa.fst")) {
  noaadata <- data.frame()
} else {
  noaadata <- fst::read_fst("/srv/shiny-server/harvest/appdata/noaa.fst") %>%
    dplyr::as_tibble()
}

if (!file.exists("/srv/shiny-server/dashboard/appdata/dmo.fst")) {
  dmo <- data.frame()
} else {
  dmo <- fst::read_fst("/srv/shiny-server/dashboard/appdata/dmo.fst")
}

if (!file.exists("/srv/shiny-server/dashboard/appdata/obs.fst")) {
  obs <- data.frame()
} else {
  obs <- fst::read_fst("/srv/shiny-server/dashboard/appdata/obs.fst") %>%
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
    dbname = 'WWCServices',
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
    dplyr::group_by(siteID, date) %>%
    dplyr::summarize(
      PR = sum(IFS_PR_mea, na.rm = TRUE), .groups = "drop")
    
  
  if (nrow(fcst_tmp) > 0) {
    for (d in 1:nrow(fcst_tmp)) {
      
      PastRain <- obs_tmp %>%
        dplyr::filter(date > fcst_tmp$date[d] - days(past_rain_days) &
                        date <= fcst_tmp$date[d]) %>%
        dplyr::summarise(PR = sum(PR, na.rm = TRUE)) %>% 
        unlist()
      
      FutureRain <- fcst_tmp %>%
        dplyr::filter(date > fcst_tmp$date[d] &
                        date <= fcst_tmp$date[d] + days(future_rain_days)) %>%
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
              fcst_tmp$siteID[d],
              fcst_tmp$date[d],
              PastRain,
              FutureRain,
              HarvestPotato
            )
          )
        },
        error = function(err) {
          print(err)
        }
      )
    }
  }
}




