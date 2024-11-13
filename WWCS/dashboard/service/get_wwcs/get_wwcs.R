library(tidyverse)
library(lubridate)
library(httr)
library(jsonlite)
library(RMySQL)
library(zoo)
library(callr)
library(stringr)

rm(list = ls())

setwd("/srv/shiny-server/dashboard/service/get_wwcs/")
source('/opt/shiny-server/WWCS/.Rprofile')

# SET GLOBAL PARAMETERS
# ------------------------------------------------

read_start_date <-
  as.POSIXct(as.Date(Sys.Date() - days(60)), tz = timezone_country)

kmean <- 12 # Number of records used for rolling mean (12 = 2h)

deployments <-
  sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
  distinct(siteID, .keep_all = TRUE)  %>%
  filter(!stringr::str_detect(siteID, pattern = "-S")) # Do not include soil moisture measurements

sites <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::distinct(siteID, .keep_all = TRUE)  %>%
  dplyr::filter(!stringr::str_detect(siteID, pattern = "-S")) %>% 
  as_tibble() # Do not include soil moisture measurements

nstat <- nrow(sites)

# READ STATION AND IFS DATA
# ------------------------------------------------

obs <- data.frame()

for (i in 1:nstat) {
  # READ STATION DATA
  
  lowcost <- sqlQuery(
    query = paste0("SELECT * FROM v_machineobs WHERE siteID = '", sites$siteID[i], "';"),
    dbname = "Machines"
  )
  
  if (nrow(lowcost) > 0) {
    # Round Minutes, Use Celsius, Omit unnecessary variables, Remove duplicates
    station <- lowcost %>%
      as_tibble() %>%
      dplyr::rename(time = timestamp) %>%
      dplyr::mutate(time = floor_date(as.POSIXct(time, tz = timezone_country), "minute")) %>%
      dplyr::rename(
        Temperature = ta,
        Pressure = p,
        RH = rh,
        Solar = U_Solar,
        Battery = U_Battery,
        Signal = signalStrength,
        Precipitation = pr,
        WindSpeed = wind_speed,
        Radiation = rad
      ) %>%
      filter(time >= read_start_date) %>%
      distinct(time, .keep_all = TRUE)
    
    # Remove outliers that are smaller than -100 or larger than 100
  
    if (nrow(station) > 0) {
      station <- station %>%
        mutate(
          Temperature = ifelse(Temperature < -100, NA, Temperature),
          RH = ifelse(RH < -100, NA, RH),
          Pressure = ifelse(Pressure < -100, NA, Pressure),
          Solar = ifelse(Solar < -100, NA, Solar),
          Battery = ifelse(Battery < -100, NA, Battery),
          Signal = ifelse(Signal < -100, NA, Signal), 
          time = as.POSIXct(ifelse(time < as.POSIXct("2021-01-01", tz = timezone_country), as.POSIXct("2021-01-01", tz = timezone_country), time)), 
          time = as.POSIXct(ifelse(time > Sys.time() + days(1), as.POSIXct("2021-01-01", tz = timezone_country), time))
        )
    }
    
    meta_deploy <- deployments %>%
      filter(siteID == sites$siteID[i])
    meta_site <- sites %>%
      filter(siteID == meta_deploy$siteID)
    
    station_meta <- station %>%
      left_join(meta_deploy) %>%
      left_join(meta_site) %>%
      dplyr::select(
        -c(
          received,
          logger_ta,
          logger_rh,
          siteName,
          district,
          jamoat,
          village,
          slope,
          azimuth
        )
      ) %>%
      # Correct pressure to sea-level height
      mutate(Pressure = Pressure * (1 - (
        0.0065 * altitude / (Temperature + 0.0065 * altitude + 273.15)
      )) ^ -5.257) 
    
    
    if (meta_site$type == "WWCS") {
      # Compute rolling average of variables to reduce noise only for WWCS stations
      station_meta <- station_meta %>% 
        mutate(
        Temperature_mean = zoo::rollmean(Temperature, k = kmean, fill = NA),
        RH_mean = zoo::rollmean(RH, k = kmean, fill = NA),
        Pressure_mean = zoo::rollmean(Pressure, k = kmean, fill = NA),
        Battery_mean = zoo::rollmean(Battery, k = kmean, fill = NA),
        Solar_mean = zoo::rollmean(Solar, k = kmean, fill = NA),
        Signal_mean = zoo::rollmean(Signal, k = kmean, fill = NA),
        Precipitation_mean = zoo::rollmean(Precipitation, k = kmean, fill = NA),
        WindSpeed_mean = zoo::rollmean(WindSpeed, k = kmean, fill = NA),
        Radiation_mean = zoo::rollmean(Radiation, k = kmean, fill = NA)
      ) %>%
      as_tibble()
    } else {
      station_meta <- station_meta %>%
        mutate(
          Temperature_mean = Temperature,
          RH_mean = RH,
          Pressure_mean = Pressure,
          Battery_mean = Battery,
          Solar_mean = Solar,
          Signal_mean = Signal,
          Precipitation_mean = Precipitation,
          WindSpeed_mean = WindSpeed,
          Radiation_mean = Radiation
        ) %>%
        as_tibble()
    }
    
    # Compute Evapotranspiration
    et0_input <- station_meta %>%
      group_by(date = date(time)) %>%
      summarize(
        Tmax = max(Temperature, na.rm = T),
        Tmin = min(Temperature, na.rm = T),
        DOY = yday(time)[1],
        DOM = day(time)[1],
        Month = month(time)[1],
        Year = year(time)[1],
        lat = latitude[1] * pi / 180,
        lon = longitude[1]
      )
    
    et0 <- calc_et0(et0_input)
    
    station_et0 <-
      station_meta %>% left_join(et0) %>% fill(Evapotranspiration)
    
    # MERGE STATION DATA IN DATAFRAME
    obs <- obs %>%
      bind_rows(station_et0) %>%
      as_tibble()
  }
}


# STORE DATA 
# ------------------------------------------------

fst::write_fst(obs, path = "/srv/shiny-server/dashboard/appdata/obs.fst", compress = 0)
