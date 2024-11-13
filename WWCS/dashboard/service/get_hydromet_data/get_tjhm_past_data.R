
library(httr)
library(jsonlite)
library(tidyverse)
library(deeplr)

rm(list = ls())

source('/opt/shiny-server/WWCS/.Rprofile')

# Load the httr package
setwd("/srv/shiny-server/dashboard/service/get_hydromet_data")

# ------------------------------------------------
# Prepare Metadata and Selection of Variables
# ------------------------------------------------

res = GET("http://217.11.176.105:8000/select/?query=%2A%20from%20meas&dbn=main.dblite")

data = as_tibble(fromJSON(rawToChar(res$content)))

sel_param <- c(7,31,13,14,59,85,119,120)

param_ids <- as.numeric(data$V4[sel_param])
param_names <- c("ta", "rh", "wind_dir", "wind_speed", "p", "pr", "U_Battery", "rad")

# Function to convert due point temperature to relative humidity

rh <- function(Td, T) {
  RH <- 100 * (exp(17.625 * Td / (243.04 + Td)) / exp(17.625 * T / (243.04 + T)))
  return(RH)
}

res = GET("http://217.11.176.105:8000/select/?query=%2A%20from%20station&dbn=main.dblite")

data = as_tibble(fromJSON(rawToChar(res$content)))

station_meta <- data %>% 
  dplyr::select(V1, V2, V3, V4, V6) %>%
  dplyr::rename(loggerID = V1, siteID = V2, lat = V3, lon = V4, altitude = V6) %>%
  dplyr::mutate(siteID = gsub('"', '', siteID))

write.table(station_meta$siteID, "stations_tjhm.txt", row.names = FALSE, quote = FALSE)

# Translate file with deepl into RU

station_meta$siteID <- read_lines("stations_tjhm_en.txt") 

station_meta <- station_meta %>% 
  filter(lat != 0) %>% 
  dplyr::mutate(loggerID = as.numeric(loggerID), 
                lat = as.numeric(lat), 
                lon = as.numeric(lon))

station_meta$altitude <- ifelse(is.na(station_meta$altitude), 0, station_meta$altitude)

years <- c(seq(2024, 2024, 1))

url <- "http://217.11.176.105:8000/select"

# ------------------------------------------------
# Read Data for Each Station
# ------------------------------------------------

station_data <- tibble()

# Read one month at the time from the API for each year, station and parameter
# Store data in files containing data for each month 
# ------------------------------------------------


for (n in 1:length(years)) {
  dates <- seq(as.Date(paste0(years[n],"-05-01")), as.Date(paste0(years[n],"-06-27")), by = 1)    
  data <- data.frame()
  
  for (d in 1:length(dates)) {
    for (i in 1:length(station_meta$siteID)) {
      
       print(
          paste0(
            "Reading station ",
            station_meta$siteID[i],
            " for the day  ",
            dates[d]
          )
        )
        
        dbn <- paste0("data_", years[n], ".dblite")
        
        param_data <- data.frame()
        
        for (j in 1:length(param_ids)) {
          
          query <- paste0(
            "* from taking where station = ",
            station_meta$loggerID[i],
            " and acode = ",
            param_ids[j],
            " and moment_utc >= ",
            as.numeric(as.POSIXct(dates[d])),
            " and moment_utc < ",
            as.numeric(as.POSIXct(dates[d] + lubridate::days(1)))
          )
          
          res <- GET(url, query = list(query = query, dbn = dbn))
          resdata <- as_tibble(fromJSON(rawToChar(res$content)))
          
          
          # Read data and join parameters in a data frame in a loop
          # Keep data only for the minutes 0, 10, 20, 30, 40, 50 
          if (nrow(resdata) > 0) {
            procdata = resdata %>%
              dplyr::mutate(time = lubridate::with_tz(lubridate::as_datetime(as.numeric(V6)), tz = "Asia/Dushanbe")) %>%
              dplyr::mutate(!!param_names[j] := as.numeric(V10)) %>%
              dplyr::mutate("loggerID" = as.numeric(V2)) %>%
              dplyr::select(c("loggerID", "time", param_names[j])) %>%
              dplyr::distinct(time, .keep_all = TRUE) %>%
              dplyr::filter(lubridate::minute(time) %in% c(0, 10, 20, 30, 40, 50))
            
            if (nrow(procdata) > 0 & nrow(param_data) > 0) {
              param_data <- procdata %>%
                dplyr::full_join(param_data, by = c("loggerID", "time")) %>%
                dplyr::arrange(desc(time))
            } else if (nrow(procdata) > 0 & nrow(param_data) == 0) {
              param_data <- procdata
            }
          }
        }
        

        if (nrow(param_data) > 0) {
          
          data = param_data %>%
            dplyr::mutate(ta = if ("ta" %in% names(.)) ta - 273.13 else NA)  %>%
            dplyr::mutate(pr = if ("pr" %in% names(.)) ifelse(pr < 0, 0, pr) else NA) %>%
            dplyr::mutate(p = if ("p" %in% names(.)) p / 100 else NA) %>%
            dplyr::bind_rows(data) %>%
            dplyr::arrange(desc(time)) 
        }
    }
  }
  
  fst::write_fst(data, path = paste0("/srv/shiny-server/dashboard/appdata/hydromet_data/all_tjhm_", years[n] ,".fst"), compress = 0)
}


# --------------------------------------------------
# DELETE ALL OLD DATA OF THESE LOGGERS FROM DATABASE older than 3 days
# --------------------------------------------------

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'Machines',
    host = 'localhost'
  )

data_tjhm <- fst::read_fst(paste0("/srv/shiny-server/dashboard/appdata/hydromet_data/all_tjhm_", years[n] ,".fst")) %>% 
        as_tibble() %>%
        distinct()


for (i in 1:nrow(data_tjhm)) {
  print(i)
  tryCatch(
    expr = {
      pool::dbExecute(
        pool,
        sprintf(
          'INSERT INTO MachineObs (loggerID, timestamp, received, ta, rh, p, pr, wind_dir, wind_speed, rad, U_Battery)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          data_tjhm$loggerID[i],
          paste(data_tjhm$time[i]),
          paste(data_tjhm$time[i]),
          data_tjhm$ta[i],
          data_tjhm$rh[i],
          data_tjhm$p[i],
          data_tjhm$pr[i],
          data_tjhm$wind_dir[i],
          data_tjhm$wind_speed[i], 
          data_tjhm$rad[i],
          data_tjhm$U_Battery[i]
        )
      )
    },
    
    error = function(err) {
      out <-
        paste0(err$message, collapse = "\n")
      return(out)
    }
  )
}

