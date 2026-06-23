library(tidyverse)
library(lubridate)
library(httr)
library(jsonlite)
library(RMySQL)
library(zoo)
library(callr)
library(stringr)

# SET GLOBAL PARAMETERS - comes form .Rprofile / config.yaml
# ----------------------------------------------------------

read_start_date <-
  as.POSIXct(as.Date(Sys.Date() - days(60)), tz = timezone_country)

kmean <- 12 # Number of records used for rolling mean (12 = 2h)

deployments <-
  sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
  distinct(siteID, .keep_all = TRUE)

sites <-
  sqlQuery(query = "select * from Sites WHERE forecast=1", dbname = "SitesHumans") %>%
  dplyr::distinct(siteID, .keep_all = TRUE)  %>%
  as_tibble() 

nstat <- nrow(sites)

# READ STATION AND IFS DATA
# ------------------------------------------------

obs <- data.frame()

for (i in 1:nstat) {
  print(paste0("Working on site ", i, "/", nstat)) ## BORIS here
  # READ STATION DATA
  
  lowcost <- sqlQuery(
    query = paste0("SELECT * FROM v_machineobs WHERE siteID = '", sites$siteID[i], "';"),
    dbname = "Machines"
  )

  if (nrow(lowcost) == 0){
      print(paste("No data found for site", sites$siteID[i]))
      next
  }

  ## Round Minutes, adjust tz, Use Celsius, Omit unnecessary variables, Remove duplicates
  station <- lowcost %>%
      as_tibble() %>%
      dplyr::rename(time = timestamp) %>%
      dplyr::mutate(time = lubridate::with_tz(as.POSIXct(time, tz = timezone_stationdata), tz = timezone_country)) %>%
      dplyr::mutate(time = floor_date(time, "minute")) %>%
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

    ## compress station data to lower time resolution - not lower than hourly, though
    ## do it in 2 parts
    ## 1 - the direct data at 0, 30 mins
    station_raw <- station %>%
        dplyr::filter(minute(time) %in% c(0, 30))

    ## 2 - variables which need aggregation
    station_agg <- station %>%
      dplyr::mutate(time_30min = ceiling_date(time, "30 minutes")) %>%
      dplyr::group_by(time_30min) %>%
      dplyr::summarize(
        across(c(Precipitation, lightning_count), sum),
        across(c(lightning_dist, WindSpeed, wind_speed_E, wind_speed_N), mean),
        across(c(wind_gust), max))

    ## 3 - join the two
    station <- station_raw %>%
      dplyr::select(-c(setdiff(names(station_agg), "time_30min"))) %>%
      left_join(station_agg, by = c("time" = "time_30min"))          

    ## Remove outliers that are smaller than -100 or larger than 100
    station <- station %>%
      mutate(
        Temperature = ifelse(Temperature < -100, NA, Temperature),
        RH = ifelse(RH < -100, NA, RH),
        Pressure = ifelse(Pressure < -100, NA, Pressure),
        Solar = ifelse(Solar < -100, NA, Solar),
        Battery = ifelse(Battery < -100, NA, Battery),
        Signal = ifelse(Signal < -100, NA, Signal), 
        time = as.POSIXct(time, tz = timezone_country),
        time = if_else(time < as.POSIXct("2021-01-01", tz = timezone_country),
                       as.POSIXct("2021-01-01", tz = timezone_country),
                       time),
        time = if_else(time > Sys.time() + days(1),
                       as.POSIXct("2021-01-01", tz = timezone_country),
                       time)
      )
    
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
    } ## station not WWCS
    
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
} ## loop through all sites

# STORE DATA 
# ------------------------------------------------
outfile <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/obs.fst")
fst::write_fst(obs, path = outfile, compress = 0)
