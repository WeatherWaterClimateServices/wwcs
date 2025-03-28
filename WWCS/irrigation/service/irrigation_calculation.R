library(RMariaDB)
library(pool)
library(dplyr)
library(lubridate)
library(tidyjson)

window <- 350 ## BORIS HACK

source('/opt/shiny-server/WWCS/.Rprofile')
source("/srv/shiny-server/irrigation/R/crop_parameters.R")
source("/srv/shiny-server/irrigation/R/calc_et0.R")

yesterday <- Sys.Date()

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
    FC,
    WP,
    StartDate,
    area,
    type,
    humanID
  )) %>% dplyr::mutate( ##BORIS HACK; compute constants
    MAD = 0.4, 
    TAW = FC - WP,
    PHIt = FC - TAW*MAD
  )

irrigation <- dbReadTable(pool_service, "Irrigation") 

if (nrow(irrigation) > 0) {
  irrigation <- irrigation %>% 
    dplyr::filter(lubridate::year(date) == lubridate::year(Sys.Date())) %>%
    as_tibble() %>%
    dplyr::rename(Ineed = irrigationNeed,
                  Iapp = irrigationApp,
                  Precipitation = precipitation)
} 


for (i in 1:nrow(irrigation_sites)) {
  # READ STATION DATA
  id <- irrigation_sites$siteID[i]
 
  # ------------------------------------------------
  # GET DATA FROM WWCS
  # ------------------------------------------------
  
  lowcost <-
    dbGetQuery(pool_stations,
               paste0("SELECT * FROM v_machineobs WHERE siteID = '", id , "';")) %>%
    mutate(across(siteID, ~ replace(., . ==  id,  irrigation_sites$siteID[i]))) %>%
    dplyr::filter(
      timestamp >= as.Date(irrigation_sites$StartDate[i]) &
        as.Date(timestamp) <= yesterday
    ) %>%
    as_tibble() 
  
  # ------------------------------------------------
  # CHECK IF CURRENTLY RUNNING
  # ------------------------------------------------  
  
  # Check if last date of data in the data frame station is today
  
  if (nrow(lowcost) == 0) {
    print(paste("The station", irrigation_sites$siteID[i], "has no data"))
    next
    
  } else {
    
    if (as.Date(lowcost$timestamp[nrow(lowcost)]) == today()) {
      print(paste("The station", irrigation_sites$siteID[i], "is currently running"))
    } else {
      print(paste("The station", irrigation_sites$siteID[i], "is not currently running"))
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
    dplyr::mutate(
      ETc = ET0 * Kc$value[1:nrow(irrigation_temp)],
      ETca = zoo::na.approx(ETc),
      FC = zoo::na.approx(irrigation_sites$FC[i]),##BORIS HACK - use value from db
      WP = zoo::na.approx(irrigation_sites$WP[i]),##BORIS HACK - use value from db
      PHIt = zoo::na.approx(FC - (FC-WP)*MAD)## BORIS HACK use formula
    )

  # Only compute values which are not yet in the data base
  # could be done also by recalculating the entire series
  # -----------------------------------------------------------
  
  nday <- nrow(irrigation_temp)
  
  for (j in 1:nday) {
    if (!"Iapp" %in% names(irrigation_temp) || is.na(irrigation_temp$Iapp[j])) { ## BORIS HACK
      irrigation_temp$Iapp[j] = 0
    }
    
    
    if (!"Precipitation" %in% names(irrigation_temp) || is.na(irrigation_temp$Precipitation[j])) { ## BORIS HACK
      irrigation_temp$Precipitation[j] = irrigation_temp$PrecipitationStation[j]
    } 
    
    if (is.na(irrigation_temp$Precipitation[j])) {
      irrigation_temp$Precipitation[j] = 0
    } 
    
    
    if (j == 1) {
      irrigation_temp$PHIc[j] = irrigation_sites$FC[i] ## BORIS HACK; was 30.5
      irrigation_temp$Ks[j] = 0 ##BORIS HACK; was 1; assume saturated soil
    } else {
      phi_update <-
        irrigation_temp$PHIc[j - 1] - (irrigation_temp$ETca[j - 1] * 100 /
                                         (RD[j] * 1000)) +
        (irrigation_temp$Iapp[j] + irrigation_temp$Precipitation[j]) *
        100 / (RD[j] * 1000)
      
      if (phi_update > irrigation_sites$FC[i]) { ##BORIS HACK; FC from db
        irrigation_temp$PHIc[j] <- irrigation_sites$FC[i] ##BORIS HACK; FC from db
      } else {
        irrigation_temp$PHIc[j] <- phi_update
      }
      
      if (irrigation_temp$PHIc[j] > irrigation_sites$PHIt[i]) {##BORIS HACK db val
        irrigation_temp$Ks[j] <- 1
      } else {
        irrigation_temp$Ks[j] <-
          1 - (irrigation_sites$PHIt[i] - irrigation_temp$PHIc[j]) / 
	  (irrigation_sites$PHIt[i] - irrigation_sites$WP[i])##BORIS HACK db val
      }
    }
    
    # ------------------------------------------------
    # COMPUTE SOIL CONDITIONS
    # ------------------------------------------------
    
    # Irrigation + Precipitation
    
##    irrigation_temp$ETca[j] <- ## BORIS HACK - comment out
##      irrigation_temp$ETc[j] * irrigation_temp$Ks[j]
    
    # SOIL WATER DEFICIT
    # ------------------------------------------------
    
    irrigation_temp$SWD[j] <- FC - irrigation_temp$PHIc[j]
    
    
    # ------------------------------------------------
    # COMPUTE IRRIGATION NEED
    # ------------------------------------------------
    
    water_balance <-
      (irrigation_temp$SWD[j] / 100) * RD[j] * 1000 - (irrigation_temp$Precipitation[j] + irrigation_temp$Iapp[j])
    
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
          params = list(
            irrigation_temp$siteID[j],
            irrigation_temp$date[j],
            irrigation_temp$Ineed[j],
            irrigation_temp$Iapp[j],
            irrigation_temp$WP[j],
            irrigation_temp$FC[j],
            irrigation_temp$SWD[j],
            irrigation_temp$ETca[j],
            irrigation_temp$Ks[j],
            irrigation_temp$PHIc[j],
            irrigation_temp$PHIt[j],
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
    )
  }
}

