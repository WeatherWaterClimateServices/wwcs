rm(list = ls())

# Required Libraries
# ------------------------------------------------

library(httr)
library(jsonlite)
library(tidyverse)
library(deeplr)

source('/opt/shiny-server/WWCS/.Rprofile')
setwd("/srv/shiny-server/dashboard/service/get_hydromet_data")


# ------------------------------------------------
# Prepare Metadata and Selection of Variables
# ------------------------------------------------

res <- httr::GET("http://217.11.176.105:8000/select/?query=%2A%20from%20meas&dbn=main.dblite")

data <- tibble::as_tibble(fromJSON(rawToChar(res$content)))

sel_param <- c(7, 31, 13, 14, 59, 85, 119, 120)

param_ids <- as.numeric(data$V4[sel_param])
param_names <- c("ta",
                 "rh",
                 "wind_dir",
                 "wind_speed",
                 "p",
                 "pr",
                 "U_Battery",
                 "rad")

# Function to convert due point temperature to relative humidity

rh <- function(Td, T) {
  RH <- 100 * (exp(17.625 * Td / (243.04 + Td)) / exp(17.625 * T / (243.04 + T)))
  return(RH)
}

res = httr::GET(
  "http://217.11.176.105:8000/select/?query=%2A%20from%20station&dbn=main.dblite"
)

data = tibble::as_tibble(fromJSON(rawToChar(res$content)))

station_meta <- data %>%
  dplyr::select(V1, V2, V3, V4, V6) %>%
  dplyr::rename(
    loggerID = V1,
    siteID = V2,
    lat = V3,
    lon = V4,
    altitude = V6
  ) %>%
  dplyr::mutate(siteID = gsub('"', '', siteID))

write.table(station_meta$siteID,
            "stations_tjhm.txt",
            row.names = FALSE,
            quote = FALSE)

# Translate file with deepl into RU

station_meta$siteID <- readr::read_lines("stations_tjhm_en.txt")

station_meta <- station_meta %>%
  dplyr::filter(lat != 0) %>%
  dplyr::mutate(
    loggerID = as.numeric(loggerID),
    lat = as.numeric(lat),
    lon = as.numeric(lon)
  )

station_meta$altitude <- ifelse(is.na(station_meta$altitude), 0, station_meta$altitude)


# ------------------------------------------------
# Write station_meta into the MySQL database SitesHumans.Sites
# ------------------------------------------------

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'SitesHumans',
    host = 'localhost'
  )

for (i in 1:length(station_meta$siteID)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool,
        sprintf(
          'REPLACE INTO Sites (siteID, siteName, latitude, longitude, altitude, fieldproperties, type)
                            VALUES (?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          station_meta$siteID[i],
          station_meta$siteID[i],
          station_meta$lat[i],
          station_meta$lon[i],
          station_meta$altitude[i],
          '{"StartDate": "2023-06-1", "FC": 38, "WP": 18, "Crop": "Potato", "area": 0, "type": "channel", "humanID": 10001}',
          "TJHM"
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

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'Machines',
    host = 'localhost'
  )

for (i in 1:length(station_meta$siteID)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool,
        sprintf(
          'INSERT INTO MachineAtSite (siteID, loggerID, startDate, endDate)
                            VALUES (?, ?, ?, ?);'
        ),
        params = list(
          station_meta$siteID[i],
          station_meta$loggerID[i],
          as.Date("2100-01-01"),
          as.Date("2100-01-01")
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


# ------------------------------------------------
# Read Data for Each Station
# ------------------------------------------------

station_data <- tibble::tibble()

dbn <- "data_2024.dblite"
url <- "http://217.11.176.105:8000/select"

data_tjhm <- tibble::tibble()

for (i in 1:length(station_meta$siteID)) {
  param_data <- data.frame()
  procdata <- data.frame()
  
  for (j in 1:length(param_ids)) {
    print(paste0(
      "Reading station ",
      station_meta$siteID[i],
      " and parameter ",
      param_names[j]
    ))
    
    query <- paste0(
      "* from taking where station = ",
      station_meta$loggerID[i],
      " and acode = ",
      param_ids[j],
      " order by moment_utc DESC",
      sep = ""
    )
    
    res <- httr::GET(url, query = list(query = query, dbn = dbn))
    resdata <- tibble::as_tibble(fromJSON(rawToChar(res$content)))
    
    
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
    data_tjhm <- param_data %>%
      dplyr::mutate(ta = if ("ta" %in% names(.))
        ta - 273.13
        else
          NA)  %>%
      dplyr::mutate(pr = if ("pr" %in% names(.))
        ifelse(pr < 0, 0, pr)
        else
          NA) %>%
      dplyr::mutate(p = if ("p" %in% names(.))
        p / 100
        else
          NA) %>%
      dplyr::bind_rows(data_tjhm) %>%
      dplyr::arrange(desc(time))
  }
}


# Keep only datapoints where at least one of the following parameter is present ta, rh, p, pr, wind_dir, wind_speed, rad

data_tjhm <- data_tjhm %>%
  dplyr::filter(!is.na(ta)) %>%
  dplyr::arrange(desc(time))

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'Machines',
    host = 'localhost'
  )


for (i in 1:nrow(data_tjhm)) {
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
