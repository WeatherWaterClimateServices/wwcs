library(RMariaDB)
library(pool)
library(dplyr)
library(lubridate)
library(tidyjson)

source('/home/wwcs/wwcs/WWCS/.Rprofile')
source("/srv/shiny-server/irrigation/R/calc_et0.R")
crop.parameters <- readr::read_csv(file = "/srv/shiny-server/irrigation/appdata/CropParameters.csv", show_col_types = FALSE)

yesterday <- Sys.Date() - 1

pool <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'SitesHumans',
    host = 'localhost'
  )

pool_service <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'WWCServices',
    host = 'localhost'
  )

pool_stations <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'Machines',
    host = 'localhost'
  )

sites <- dbReadTable(pool, "Sites")  %>%
  dplyr::as_tibble() %>%
  dplyr::select(c(siteID, siteName, altitude, latitude, longitude, irrigation))

irrigation_sites <- dbReadTable(pool, "Sites")   %>%
  dplyr::select(fieldproperties) %>%
  unlist() %>%
  spread_all %>%
  dplyr::bind_cols(sites) %>%
  dplyr::as_tibble() %>%
  dplyr::filter(irrigation == 1) %>%
  dplyr::select(c(
    siteID,
    siteName,
    latitude,
    longitude,
    irrigation,
    Station, ## siteID of where the relevant weather station sits
    FC, ## field capacity
    WP, ## wilting point
    MAD, ## to come from the Sites table! (was .4 in crop_parameters.R)
    PHIc, ## to come from the Sites table for first timestep; suggest a default value, e.g. avg(FC, WP)! (was 30.5 hardcoded in here at first timestep); c=content -> this varies
    Crop, 
    StartDate,
    area,
    type,
    humanID
  )) %>% dplyr::mutate( ##compute constants
    TAW = FC - WP,
    PHIt = FC - TAW * MAD ## was 21.8 hardcoded in here, but of different value in crop_parameters.R); t=threshold -> constant
  )

## give more useful names
irrigation <- dbReadTable(pool_service, "Irrigation") %>%
  as_tibble() %>%
  dplyr::rename(Ineed = irrigationNeed,
                Iapp = irrigationApp,
                Precipitation = precipitation)

## extract only entries for the current calendar year
if (nrow(irrigation) > 0) {
  irrigation <- irrigation %>% 
    dplyr::filter(lubridate::year(date) == lubridate::year(Sys.Date())) 
} 


for (i in 1:nrow(irrigation_sites)) {
  
  # READ STATION DATA
  
  id_station <- irrigation_sites$Station[i]
  
  start_year <- lubridate::year(as.Date(irrigation_sites$StartDate[i]))
  current_year <- lubridate::year(Sys.Date())
  
  if (start_year != current_year) {
    message <- paste("Station", irrigation_sites$siteID[i], 
                     "has StartDate in", start_year, 
                     "which is not the current year. Skipping.")
    print(message)
    next
  }
  
  # ------------------------------------------------
  # GET DATA FROM WWCS
  # ------------------------------------------------
  
  lowcost <-
    dbGetQuery(pool_stations,
               paste0("SELECT * FROM v_machineobs WHERE siteID = '", id_station , "';")) %>%
    mutate(across(siteID, ~ replace(., . ==  id_station,  irrigation_sites$siteID[i]))) %>%
    dplyr::filter(
      timestamp >= as.Date(irrigation_sites$StartDate[i]) &
        as.Date(timestamp) <= yesterday
    ) %>%
    as_tibble() 
  
  # ------------------------------------------------
  # CHECK IF CURRENTLY RUNNING
  # ------------------------------------------------  
  
  # Check if last date of data in the data frame station is from yesterday  
  if (nrow(lowcost) == 0) {
    print(paste("The station", irrigation_sites$siteID[i], "has no data"))
    next    
  } else {    
    if (as.Date(lowcost$timestamp[nrow(lowcost)]) == yesterday) {
      print(paste("The station", irrigation_sites$siteID[i], "was running yesterday"))
    } else {
      print(paste("The station", irrigation_sites$siteID[i], "was not running yesterday"))
      next
    }    
  }
  
  meta_site <- irrigation_sites %>%
    filter(siteID == irrigation_sites$siteID[i]) %>%
    dplyr::select(c(siteID, longitude, latitude))
  
  obs <- lowcost %>%
    dplyr::mutate(time = floor_date(as.POSIXct(timestamp), "minute")) %>%
    dplyr::mutate(pr = ifelse(is.na(pr), 0, pr)) %>%
    dplyr::mutate(ta = ifelse(ta < -100, NA, ta)) %>%
    dplyr::rename(Temperature = ta, PrecipitationStation = pr) %>%
    dplyr::select(c(Temperature, PrecipitationStation, time, siteID)) %>%
    dplyr::right_join(meta_site) %>%
    na.omit() %>%
    as_tibble()
  
  # ------------------------------------------------
  # PREPARE DATA FOR ET0
  # ------------------------------------------------
  
  station <- obs %>%
    group_by(date = date(time)) %>%
    summarize(
      Tmax = max(Temperature),
      Tmin = min(Temperature),
      DOY = yday(time)[1],
      DOM = day(time)[1],
      Month = month(time)[1],
      Year = year(time)[1],
      lat = latitude[1] * pi / 180,
      lon = longitude[1],
      PrecipitationStation = sum(PrecipitationStation),
    ) %>%
    dplyr::mutate(siteID = irrigation_sites$siteID[i])
  
  
  # ------------------------------------------------
  # CHECK IF DATES ARE MISSING IN THE STATION AND REPLACE WITH EMPTY VALUE
  # ------------------------------------------------  
  
  full_dates <- seq(as.Date(irrigation_sites$StartDate[i]), as.Date(yesterday), by = "1 day")
  
  missing_dates <- data.frame("date" = full_dates[!full_dates %in% as.Date(station$date)]) %>% as_tibble()
  
  missing_dates <- missing_dates %>%
    dplyr::mutate(
      Tmax = NA,
      Tmin = NA,
      DOY = yday(date),
      DOM = day(date),
      Month = month(date),
      Year = year(date),
      lat = station$lat[1],
      lon = station$lon[2],
      PrecipitationStation = NA
    ) %>%
    dplyr::mutate(siteID = irrigation_sites$siteID[i])
  
  station <- rbind(station, missing_dates) %>%
    dplyr::arrange(date) %>%
    dplyr::left_join(irrigation)
  
  # ------------------------------------------------
  # COMPUTE EVAPOTRANSPIRATION VALUES
  # ------------------------------------------------
  
  irrigation_temp <- calc_et0(station)
  
  # Replace values in ET0 with the ones from ET0new only where ET0new is not NA  
  irrigation_temp$ET0 <- ifelse(is.na(irrigation_temp$ET0new), irrigation_temp$ET0, irrigation_temp$ET0new)
  
  # Omit ET0new  
  irrigation_temp <- irrigation_temp %>%
    dplyr::select(-ET0new)
  
  # -----------------------------------------------------------
  
  irrigation_temp <- irrigation_temp %>%
    dplyr::mutate(ETc = zoo::na.approx(ET0 * crop.parameters[[paste0(irrigation_sites$Crop[i], "_Kc")]][1:nrow(irrigation_temp)], na.rm =
                                         FALSE),
                  ## if ever a trailing of heading value is NA, keep it; interpolate NA gaps
                  ETca = ETc)
  
  # Only compute values which are not yet in the data base
  # could be done also by recalculating the entire series
  # -----------------------------------------------------------
  
  nday <- nrow(irrigation_temp)
  
  for (j in 1:nday) {
    if (is.na(irrigation_temp$Iapp[j])) {
      irrigation_temp$Iapp[j] <-  0
    }
    
    ##if PrecipitationStation contains a valid value, use this one
    ##otherwise leave at NA or a manually set value (via webform/db)    
    if (!is.na(irrigation_temp$PrecipitationStation[j])) {
      irrigation_temp$Precipitation[j] <-  irrigation_temp$PrecipitationStation[j]
    } 

    ## store this RD here
    this.RD <- crop.parameters[[paste0(irrigation_sites$Crop[i], "_RD")]][j]

    if (j == 1) { ## if first day, assign starting value
      irrigation_temp$PHIc[j] = irrigation_sites$PHIc[i] ## start value from db
    } else { ## if not first day, go through the water balance
      phi_update <-
        irrigation_temp$PHIc[j - 1] - (irrigation_temp$ETca[j - 1] * 100 /
                                         (this.RD * 1000)) +
        (irrigation_temp$Iapp[j] + irrigation_temp$Precipitation[j]) *
        100 / (this.RD * 1000)

      ## assign moisture content PHIc
      if (is.na(phi_update)) {## catch an NA, e.g. if station temporarily down
        irrigation_temp$PHIc[j] <- irrigation_temp$PHIc[j-1]
      } else { ## otherwise, if all good
        if (phi_update > irrigation_sites$FC[i]){
          irrigation_temp$PHIc[j] <- irrigation_sites$FC[i]
        } else {
          irrigation_temp$PHIc[j] <- phi_update
        }
      }
    } ## end not first day

    ## check if mosture content causes stress (no stress: Ks=1)
    if (irrigation_temp$PHIc[j] > irrigation_sites$PHIt[i]) {
      irrigation_temp$Ks[j] <- 1
    } else {
      irrigation_temp$Ks[j] <-
        1 - (irrigation_sites$PHIt[i] - irrigation_temp$PHIc[j]) / 
 (irrigation_sites$PHIt[i] - irrigation_sites$WP[i])
    }
    
    # ------------------------------------------------
    # COMPUTE SOIL CONDITIONS
    # ------------------------------------------------
    
    # Irrigation + Precipitation
    irrigation_temp$ETca[j] <- 
      irrigation_temp$ETc[j] * irrigation_temp$Ks[j]
    
    # SOIL WATER DEFICIT
    # ------------------------------------------------    
    irrigation_temp$SWD[j] <- irrigation_sites$FC[i] - irrigation_temp$PHIc[j]
        
    # ------------------------------------------------
    # COMPUTE IRRIGATION NEED
    # ------------------------------------------------
    
    water_balance <-
      (irrigation_temp$SWD[j] / 100) * this.RD * 1000 - (irrigation_temp$Precipitation[j] + irrigation_temp$Iapp[j]) 
    
    if (water_balance > 0) {
      irrigation_temp$Ineed[j] <- water_balance
    } else {
      irrigation_temp$Ineed[j] <- 0
    }
    
    # Insert each recommendation invidually into database
    # -----------------------------------------------------------
    
    tryCatch(
      expr = {
        pool::dbExecute(
          pool_service,
          sprintf(
            'REPLACE INTO Irrigation (siteID, date, irrigationNeed, irrigationApp, WP, FC, SWD, ETca, Ks, PHIc, PHIt, precipitation, ET0, ETc)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
          ),
          params = list( ## some of them are fixed in time, these come from the sites directly 
            irrigation_temp$siteID[j],
            irrigation_temp$date[j],
            irrigation_temp$Ineed[j],
            irrigation_temp$Iapp[j],
            irrigation_sites$WP[i],
            irrigation_sites$FC[i],
            irrigation_temp$SWD[j],
            irrigation_temp$ETca[j],
            irrigation_temp$Ks[j],
            irrigation_temp$PHIc[j],
            irrigation_sites$PHIt[i],
            irrigation_temp$Precipitation[j],
            irrigation_temp$ET0[j],
            irrigation_temp$ETc[j]
          )
        )
      },
      
      error = function(err) {
        out <-
          paste0(
            "Entry of ",
            irrigation_temp$siteID[j],
            " on ",
            irrigation_temp$date[j],
            " already exists"
          )
        return(out)
      }
    ) ## end trycatch insert into WWCServices.Irrigation
  }
}
