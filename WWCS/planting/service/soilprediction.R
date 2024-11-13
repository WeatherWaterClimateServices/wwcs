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
source('/opt/shiny-server/WWCS/.Rprofile')
source('/opt/shiny-server/WWCS/planting/R/complete_criteria.R')

# READ AND ALLOCATE DATA
# ----------------------

curr_date <- Sys.Date() 

criteria <-
  read_csv("/srv/shiny-server/planting/appdata/criteria_planting.csv")

# Read administrative areas

bd <-
  sf::st_read(
    paste0(
      "/opt/shiny-server/WWCS/boundaries/gadm41_",
      gadm0,
      "_2.shp"
    ),
    as_tibble = TRUE
  ) %>%
  dplyr::rename(district = GID_2, name = NAME_2) %>%
  dplyr::select(c(district, name, geometry))

# Read stations which have the value 1 in the planting column in the Sites table

sites <- sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::filter(planting == 1)  %>%
  dplyr::select(c(siteID, latitude, longitude, district))


pnts_sf <-
  st_as_sf(sites,
           coords = c('longitude', 'latitude'),
           crs = st_crs(bd))

pnts_sf <- pnts_sf %>% mutate(intersection = as.integer(st_intersects(geometry, bd)),
                              area = if_else(is.na(intersection), '', bd$name[intersection]))

complete_criteria(criteria, pnts_sf)

sites <- sites %>%
  left_join(pnts_sf)

# PREDICT SOIL TEMPERATURE BASED ON PAST 2M TEMPERATURE OBSERVATIONS
# ------------------------------------------------------------------

nstat <- nrow(sites)
alldata <- tibble()

# Soil Proxy Formula - Prediction with past T2M

for (i in 1:nstat) {
  s <- sites$siteID[i]
  rs <-
    sqlQuery(
      query = paste0("SELECT * FROM v_machineobs WHERE siteID = '", s, "';"),
      dbname = "Machines"
    )
  
  newdata <- rs %>%
    dplyr::select(c(siteID, timestamp, ta, ts10cm, rh)) %>%
    dplyr::mutate(day = lubridate::date(timestamp)) %>%
    dplyr::mutate(across(ta, ~ ifelse(. < -100, NA, .))) %>%
    dplyr::group_by(siteID, day) %>%
    dplyr::summarise(
      Temperature = mean(ts10cm, na.rm = TRUE),
      TemperatureAir = mean(ta, na.rm = TRUE),
      RH = mean(rh, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      T2_lag3 = zoo::rollmean(
        TemperatureAir,
        k = lag3,
        align = "right",
        fill = NA
      ),
      T2_lag2 = zoo::rollmean(
        TemperatureAir,
        k = lag2,
        align = "right",
        fill = NA
      ),
      T2_lag1 = zoo::rollmean(
        TemperatureAir,
        k = lag1,
        align = "right",
        fill = NA
      )
    )
  
  
  out <- try({
    emosfit <-  crch(
      formula = proxy_formula,
      dat     = newdata,
      dist    = "gaussian",
      type    = "crps"
    )
    
    predres <- predict(object = emosfit,
                       newdata  = newdata,
                       type = "parameter")
    
    newdata <- predres %>%
      dplyr::rename(TemperatureProxy = location) %>%
      dplyr::select(-c(scale)) %>%
      dplyr::bind_cols(newdata, .)
    
    error <- (newdata$Temperature - predres$location)
    print(paste("Standard Error of proxy equal to =", sd(error, na.rm = TRUE)))
  }
  , silent = TRUE)
  
  selsite <- sites  %>%
    dplyr::select(c(siteID, latitude, longitude, area)) %>%
    dplyr::rename(district = area)  %>%
    dplyr::filter(siteID == s)
  
  newdata <- newdata %>%
    dplyr::mutate(
      latitude = selsite$latitude,
      longitude = selsite$longitude,
      district = selsite$district
    )
  
  alldata <- alldata %>%
    bind_rows(newdata)
  
}

alldata <- alldata %>%
  dplyr::filter(day < curr_date)

fst::write_fst(alldata, path = "/srv/shiny-server/planting/appdata/soildata.fst", compress = 0)


# PREDICT SOIL TEMPERATURE BASED ON FORECASTED TEMPERATURE SUMS
# ------------------------------------------------------------------

emos_formula   <-
  as.character("Temperature ~ IFS_T_sum + lastobs")

dmo <- data.frame()
emos <- data.frame()
emos_merged <- data.frame()

emosmod <-
  fst::read_fst("/srv/shiny-server/dashboard/appdata/emos.fst") %>%
  dplyr::as_tibble()

crps <- array(NA, soil_fcst_days)

for (i in 1:nstat) {
  s <- sites$siteID[i]
  
  # READ IFS DATA
  print(paste0("Reading IFS data for station ", s))
  ifs <- data.frame()
  dmo <- data.frame()
  ifs <- emosmod %>%
    dplyr::filter(siteID == s) %>%
    dplyr::mutate(
      day = lubridate::date(time),
      reftime = as.Date(reftime),
      lead = day - reftime
    ) %>%
    dplyr::group_by(siteID, reftime, day, lead) %>%
    dplyr::summarize(IFS_Temperature = mean(WWCS), .groups = "drop")
  
  soildata <- alldata %>%
    dplyr::filter(siteID == s) %>%
    dplyr::select(c(Temperature, day, siteID))
  
  dmo <- left_join(ifs, soildata)
  
  print(paste0("Training IFS data for station ", s))
  for (j in 1:soil_fcst_days) {
    l = days(j)
    
    train <- dmo %>%
      filter(siteID == s & lead <= l) %>%
      dplyr::group_by(reftime) %>%
      dplyr::reframe(
        lastobs = Temperature[1],
        IFS_T_sum = sum(IFS_Temperature - Temperature[1], na.rm = T),
        Temperature = last(Temperature)
      )
    out <- try({
      emosfit <-  crch(
        formula = emos_formula,
        dat     = train,
        dist    = "gaussian",
        type    = "crps"
      )
      
      crps[j] <- summary(emosfit)$crps
      
      predres <- predict(object = emosfit,
                         newdata  = train,
                         type = "parameter")
      
      emos <- predres %>%
        bind_cols(train) %>%
        dplyr::mutate(lead = j,
                      time = reftime + days(lead),
                      siteID = s) %>%
        dplyr::rename(IFS_Temperature = location,
                      IFS_Temperature_std = scale) %>%
        dplyr::select(-c(IFS_T_sum)) %>%
        as_tibble() %>%
        arrange(reftime, lead) %>%
        bind_rows(emos)
    }, silent = TRUE)
  }
  
  lastobs <- emos %>%
    dplyr::filter(siteID == s) %>%
    group_by(reftime) %>%
    reframe(lastobs) %>%
    distinct() %>%
    dplyr::mutate(
      lead = 0,
      time = reftime,
      siteID = s,
      IFS_Temperature_std = 0
    ) %>%
    dplyr::rename(IFS_Temperature = lastobs)
  
  emos_merged <- bind_rows(emos, lastobs) %>%
    bind_rows(emos_merged)
  
}

fst::write_fst(emos_merged, path = "/srv/shiny-server/planting/appdata/emosdata.fst", compress = 0)

# ---------------------------------------
# WRITE SERVICE DATA INTO THE SERVICE DATABASE
# ---------------------------------------

pool_service <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'WWCServices',
    host = 'localhost'
  )

# Check if temperature is in the range of the corresponding criteria of the district

for (i in 1:nrow(alldata)) {
  selcriteria <- criteria %>% filter(district == alldata$district[i])
  
  WinterWheat <- ifelse(
    alldata$Temperature[i] >= selcriteria$Threshold_low[1] &
      alldata$Temperature[i] <= selcriteria$Threshold_high[1] &
      alldata$day[i] >= as.Date(selcriteria$Window_low[1], format = "%d-%b") &
      alldata$day[i] <= as.Date(selcriteria$Window_high[1], format = "%d-%b"),
    1,
    0
  )
  
  SpringWheat <- ifelse(
    alldata$Temperature[i] >= selcriteria$Threshold_low[2] &
      alldata$Temperature[i] <= selcriteria$Threshold_high[2] &
      alldata$day[i] >= as.Date(selcriteria$Window_low[2], format = "%d-%b") &
      alldata$day[i] <= as.Date(selcriteria$Window_high[2], format = "%d-%b"),
    1,
    0
  )
  
  SpringPotato <- ifelse(
    alldata$Temperature[i] >= selcriteria$Threshold_low[3] &
      alldata$Temperature[i] <= selcriteria$Threshold_high[3] &
      alldata$day[i] >= as.Date(selcriteria$Window_low[3], format = "%d-%b") &
      alldata$day[i] <= as.Date(selcriteria$Window_high[3], format = "%d-%b"),
    1,
    0
  )
  
  SummerPotato <- ifelse(
    alldata$Temperature[i] >= selcriteria$Threshold_low[4] &
      alldata$Temperature[i] <= selcriteria$Threshold_high[4] &
      alldata$day[i] >= as.Date(selcriteria$Window_low[4], format = "%d-%b") &
      alldata$day[i] <= as.Date(selcriteria$Window_high[4], format = "%d-%b"),
    1,
    0
  )
  
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Planting (siteID, date, Winter_Wheat, Spring_Wheat, Spring_Potato, Summer_Potato, Soil_Temp)
                            VALUES (?, ?, ?, ?, ?, ?, ?);'
          
        ),
        params = list(
          alldata$siteID[i],
          alldata$day[i],
          WinterWheat,
          SpringWheat,
          SpringPotato,
          SummerPotato,
          alldata$Temperature[i]
        )
      )
    },
    error = function(err) {
      print(err)
    }
  )
}

