library(tidyr)
library(tidyverse)
library(dplyr)
library(lubridate)
library(pool)
library(sf)
library(RMySQL)

source('/home/wwcs/wwcs/WWCS/.Rprofile')

# ------------------------------------------------
# DEFINE AND LOAD GENERAL VARIABLES
# ------------------------------------------------

currdate = Sys.Date() 
warning_window <- seq(currdate, currdate + days(warning_days - 1), by = "days")


bd <- sf::st_read(
  paste0(
    "/home/wwcs/wwcs/WWCS/boundaries/gadm41_",
    gadm0,
    "_2.shp"
  ),
  as_tibble = TRUE
) %>%
  dplyr::rename(name = NAME_2) %>%
  dplyr::select(c(name, geometry))

# Strangely there is two Rudaki in the GADM41 data, to be clarified

if (gadm0 == "TJK") {
  bd$name[14] = "Rudaki2"  
}

ndis <- length(sf::st_geometry(bd))
warn_levels <- array(NA, dim = c(ndis))

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


sites <- dbReadTable(pool, "Sites")  %>%
  dplyr::as_tibble() %>%
  dplyr::select(c(
    siteID,
    siteName,
    altitude,
    district,
    latitude,
    longitude,
    coldwave,
    heatwave
  ))

pnts_sf <-
  sf::st_as_sf(sites,
               coords = c('longitude', 'latitude'),
               crs = st_crs(bd))

pnts_sf <- pnts_sf %>%
  #na.omit() %>%
  dplyr::mutate(
    intersection = as.integer(sf::st_intersects(geometry, bd)),
    area = if_else(is.na(intersection), '', bd$name[intersection])
  )

sites <- sites %>%
  dplyr::left_join(pnts_sf) %>%
  dplyr::select(-c(geometry, intersection, district, siteName, altitude))  %>%
  dplyr::rename(district = area, siteID = siteID)

thresholds <- dbReadTable(pool_service, "Warnings")

# Read post-processed forecast data

emos <-
  fst::read_fst("/srv/shiny-server/dashboard/appdata/emos.fst") %>%
  dplyr::select(c(WWCS, IFS_T_std, reftime, time, siteID, IFS_T_min)) %>%
  dplyr::left_join(sites) %>%
  left_join(thresholds, by = "district") %>%
  na.omit() %>%
  as_tibble()

# DEFINE WARNING FUNCTION
# ------------------------------------------------

prob_threshold <- setNames(c(0.9, 0.6), c("red", "yellow"))
ewscolor <-
  function(x)
    ifelse((x > prob_threshold["red"]),
           "red",
           ifelse(x > prob_threshold["yellow"], "yellow", "green"))

warning_level <- function(threshold, mean, sd, lower) {
  out <- ewscolor(pnorm(q = threshold, mean, sd, lower.tail = lower))
  return(out)
}

ews_probability_frost <- function(ifs, threshold) {
  out <- sum(ifs < threshold, na.rm = T) / length(ifs)
  return(out)
}

ews_probability_heat <- function(ifs, threshold) {
  out <- sum(ifs > threshold, na.rm = T) / length(ifs)
  return(out)
}

# -------------------------------------------
# Compute warning levels
# -------------------------------------------

# -------------------------------------------
# EWS AT STATIONS
# -------------------------------------------

ews_station_frost <- emos %>%
  dplyr::rename(IFS_T_mea = WWCS) %>%
  dplyr::filter(as.Date(reftime) == currdate) %>%
  dplyr::mutate(date = date(time)) %>%
  dplyr::filter(date < currdate + warning_days) %>%
  dplyr::group_by(siteID, reftime, date, Cold1, Cold2, Cold3, district, altitude) %>%
  dplyr::reframe(
    IFS_T_mea_d = mean(IFS_T_mea),
    IFS_T_std_d = mean(IFS_T_std),
    IFS_T_min_d = min(IFS_T_mea),
    IFS_T_std_min = IFS_T_std[which(IFS_T_mea == min(IFS_T_mea))]
  ) %>%
  rowwise() %>%
  dplyr::mutate(ColdWarn1 = warning_level(
    threshold = Cold1,
    mean = IFS_T_min_d,
    sd = IFS_T_std_min,
    lower = TRUE
  )) %>%
  dplyr::mutate(ColdWarn2 = warning_level(
    threshold = Cold2,
    mean = IFS_T_min_d,
    sd = IFS_T_std_min,
    lower = TRUE
  )) %>%
  dplyr::mutate(ColdWarn3 = warning_level(
    threshold = Cold3,
    mean = IFS_T_min_d,
    sd = IFS_T_std_min,
    lower = TRUE
  )) %>%
  dplyr::distinct()

ews_station_heat <- emos %>%
  dplyr::rename(IFS_T_mea = WWCS) %>%
  dplyr::filter(as.Date(reftime) == currdate) %>%
  dplyr::mutate(date = date(time)) %>%
  dplyr::filter(date < currdate + warning_days) %>%
  dplyr::group_by(siteID, reftime, date, Heat1, Heat2, Heat3, district, altitude) %>%
  dplyr::reframe(
    IFS_T_mea_d = mean(IFS_T_mea),
    IFS_T_std_d = mean(IFS_T_std),
    IFS_T_min_d = min(IFS_T_mea),
    IFS_T_std_min = IFS_T_std[which(IFS_T_mea == min(IFS_T_mea))]
  ) %>%
  rowwise() %>%
  dplyr::mutate(HeatWarn1 = warning_level(
    threshold = Heat1,
    mean = IFS_T_mea_d,
    sd = IFS_T_std_d,
    lower = FALSE
  )) %>%
  dplyr::mutate(HeatWarn2 = warning_level(
    threshold = Heat2,
    mean = IFS_T_mea_d,
    sd = IFS_T_std_d,
    lower = FALSE
  )) %>%
  dplyr::mutate(HeatWarn3 = warning_level(
    threshold = Heat3,
    mean = IFS_T_mea_d,
    sd = IFS_T_std_d,
    lower = FALSE
  )) %>%
  dplyr::distinct()


ews_station <-
  dplyr::full_join(ews_station_frost, ews_station_heat) %>%
  dplyr::arrange(date) %>%
  na.omit() %>%
  distinct()


# -------------------------------------------
# EWS AT ADMINISTRATIVE REGIONS
# -------------------------------------------

file <-
  "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_merged.nc"
filesub <-
  "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_sub.nc"
filemin <-
  "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_daymin.nc"
filemean <-
  "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_daymean.nc"
fileelev <- 
  "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_elevation.nc"


system(paste0(
  "cdo -O select,date=",
  paste(warning_window, collapse = ","),
  " ",
  file,
  " ",
  filesub
))

system(paste0("cdo -O -daymean ", filesub, " ", filemean))
system(paste0("cdo -O -daymin ", filesub, " ", filemin))


# COMPUTE WARNING LEVELS
# ---------------------------------------------------------

ifs_heat_mea <- raster::brick(filemean, varname = "IFS_T_mea")
ifs_heat_std <- raster::brick(filemean, varname = "IFS_T_std")
elev <-  raster::brick(fileelev, varname = "ELEV")
ifs_frost_mea <- raster::brick(filemin, varname = "IFS_T_mea")
ifs_frost_std <- raster::brick(filemean, varname = "IFS_T_std")

ifs_heat_mea_districts <-
  exactextractr::exact_extract(ifs_heat_mea, bd)

ifs_heat_std_districts <-
  exactextractr::exact_extract(ifs_heat_std, bd)

ifs_frost_mea_districts <-
  exactextractr::exact_extract(ifs_frost_mea, bd)

ifs_frost_std_districts <-
  exactextractr::exact_extract(ifs_frost_std, bd)

# Read elevation parameters for grid
# Check if file elev_districts.Rdata exists, if yes read it from there
# otherwise from the raster file

if (file.exists("/srv/shiny-server/dashboard/appdata/poi/elev_districts.Rdata")) {
  elev_districts <-
    readRDS("/srv/shiny-server/dashboard/appdata/poi/elev_districts.Rdata")
} else {
  elev_districts <-
    exactextractr::exact_extract(elev, bd)
  saveRDS(elev_districts, "/srv/shiny-server/dashboard/appdata/poi/elev_districts.Rdata")
}

ews_district <- data.frame()

for (i in 1:length(warning_window)) {
  seldate <- warning_window[i]
  print(seldate)
  
  ews_heat <- data.frame(matrix(NA, nrow = ndis, ncol = 3)) %>%
    setNames(c("HeatWarn1", "HeatWarn2", "HeatWarn3")) %>%
    bind_cols(tibble("district" = bd$name)) %>%
    dplyr::mutate(date = seldate) %>%
    dplyr::mutate(reftime = currdate)
  
  for (j in 1:ndis) {
    height_ews <-
      thresholds %>% filter(district == bd$name[j]) %>% dplyr::select(altitude) %>% unlist()
    
    topo_select <- elev_districts[[j]]$value < height_ews
    
    if (!purrr::is_empty(topo_select)) {
      heat_mea_select <- ifs_heat_mea_districts[[j]][topo_select, i]
      heat_std_select <- ifs_heat_std_districts[[j]][topo_select, i]
      
      
      if (!purrr::is_empty(heat_mea_select)) {
        ifs_red <- qnorm(p = prob_threshold[1],
                         mean = heat_mea_select,
                         sd = heat_std_select)
        
        ifs_yellow <- qnorm(p = prob_threshold[2],
                            mean = heat_mea_select,
                            sd = heat_std_select)
        
        for (k in 1:3) {
          if (k == 1) {
            thresholds_heat = thresholds %>% filter(district == bd$name[1]) %>% dplyr::select(Heat1) %>% unlist()
          } else if (k == 2) {
            thresholds_heat = thresholds %>% filter(district == bd$name[1]) %>% dplyr::select(Heat2) %>% unlist()
          } else {
            thresholds_heat = thresholds %>% filter(district == bd$name[1]) %>% dplyr::select(Heat3) %>% unlist()
          }
          
          red <- ews_probability_heat(ifs_red, thresholds_heat)
          yellow <-
            ews_probability_heat(ifs_yellow, thresholds_heat)
          
          if (red > spatial_threshold) {
            ews_heat[j, k] <- "red"
          } else if (yellow > spatial_threshold) {
            ews_heat[j, k] <- "yellow"
          } else {
            ews_heat[j, k] <- "green"
          }
        }
      }
    }
  }
  
  
  ews_frost <- data.frame(matrix(NA, nrow = ndis, ncol = 3)) %>%
    setNames(c("ColdWarn1", "ColdWarn2", "ColdWarn3")) %>%
    bind_cols(tibble("district" = bd$name)) %>%
    dplyr::mutate("date" = seldate) %>%
    dplyr::mutate("reftime" = currdate)
  
  for (j in 1:ndis) {
    height_ews <-
      thresholds %>% filter(district == bd$name[j]) %>% dplyr::select(altitude) %>% unlist()
    
    topo_select <- elev_districts[[j]]$value < height_ews
    
    if (!purrr::is_empty(topo_select)) {
      frost_mea_select <- ifs_frost_mea_districts[[j]][topo_select, i]
      frost_std_select <-
        ifs_frost_std_districts[[j]][topo_select, i]
      
      
      if (!purrr::is_empty(frost_mea_select)) {
        ifs_red <- qnorm(p = prob_threshold[1],
                         mean = frost_mea_select,
                         sd = frost_std_select)
        
        ifs_yellow <- qnorm(p = prob_threshold[2],
                            mean = frost_mea_select,
                            sd = frost_std_select)
        
        
        
        for (k in 1:3) {
          if (k == 1) {
            thresholds_frost = thresholds %>% filter(district == bd$name[j]) %>% dplyr::select(Cold1) %>% unlist()
          } else if (k == 2) {
            thresholds_frost = thresholds %>% filter(district == bd$name[j]) %>% dplyr::select(Cold2) %>% unlist()
          } else {
            thresholds_frost = thresholds %>% filter(district == bd$name[j]) %>% dplyr::select(Cold3) %>% unlist()
          }
          
          red <- ews_probability_frost(ifs_red, thresholds_frost)
          yellow <-
            ews_probability_frost(ifs_yellow, thresholds_frost)
          
          if (red > spatial_threshold) {
            ews_frost[j, k] <- "red"
          } else if (yellow > spatial_threshold) {
            ews_frost[j, k] <- "yellow"
          } else {
            ews_frost[j, k] <- "green"
          }
        }
      }
    }
  }
  
  ews_district <- ews_frost %>%
    right_join(ews_heat) %>%
    na.omit() %>%
    left_join(thresholds) %>%
    arrange(reftime) %>%
    bind_rows(ews_district) %>%
    as_tibble()
}

# ------------------------------------------------
# STORE WARNING DATA IN DATA BASE
# ------------------------------------------------

# COLDWAVES
# ------------------------------------------------

for (i in 1:nrow(ews_district)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Coldwave (reftime, date, Type, Name, altitude, Cold1, Cold2, Cold3, Threshold1, Threshold2, Threshold3)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          ews_district$reftime[i],
          ews_district$date[i],
          "District",
          ews_district$district[i],
          ews_district$altitude[i],
          ews_district$ColdWarn1[i],
          ews_district$ColdWarn2[i],
          ews_district$ColdWarn3[i],
          ews_district$Cold1[i],
          ews_district$Cold2[i],
          ews_district$Cold3[i]
        )
      )
    },
    
    error = function(err) {
      out <-
        paste0(
          "Entry of ",
          ews_district$district[i],
          " on ",
          ews_district$reftime[i],
          " already exists"
        )
      return(out)
    }
  )
}

# @ STATIONS

for (i in 1:nrow(ews_station)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Coldwave (reftime, date, Type, Name, altitude, Cold1, Cold2, Cold3, Threshold1, Threshold2, Threshold3)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          ews_station$reftime[i],
          ews_station$date[i],
          "Station",
          ews_station$siteID[i],
          ews_station$altitude[i],
          ews_station$ColdWarn1[i],
          ews_station$ColdWarn2[i],
          ews_station$ColdWarn3[i],
          ews_station$Cold1[i],
          ews_station$Cold2[i],
          ews_station$Cold3[i]
        )
      )
    },
    
    error = function(err) {
      out <-
        paste0(
          "Entry of ",
          ews_district$district[i],
          " on ",
          ews_district$reftime[i],
          " already exists"
        )
      return(out)
    }
  )
}


# HEATWAVES
# ------------------------------------------------

for (i in 1:nrow(ews_district)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Heatwave (reftime, date, Type, Name, altitude, Heat1, Heat2, Heat3, Threshold1, Threshold2, Threshold3)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          ews_district$reftime[i],
          ews_district$date[i],
          "District",
          ews_district$district[i],
          ews_district$altitude[i],
          ews_district$HeatWarn1[i],
          ews_district$HeatWarn2[i],
          ews_district$HeatWarn3[i],
          ews_district$Heat1[i],
          ews_district$Heat2[i],
          ews_district$Heat3[i]
        )
      )
    },
    
    error = function(err) {
      out <-
        paste0(
          "Entry of ",
          ews_district$district[i],
          " on ",
          ews_district$reftime[i],
          " already exists"
        )
      return(out)
    }
  )
}

# @ STATIONS

for (i in 1:nrow(ews_station)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Heatwave (reftime, date, Type, Name, altitude, Heat1, Heat2, Heat3, Threshold1, Threshold2, Threshold3)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);'
        ),
        params = list(
          ews_station$reftime[i],
          ews_station$date[i],
          "Station",
          ews_station$siteID[i],
          ews_station$altitude[i],
          ews_station$HeatWarn1[i],
          ews_station$HeatWarn2[i],
          ews_station$HeatWarn3[i],
          ews_station$Heat1[i],
          ews_station$Heat2[i],
          ews_station$Heat3[i]
        )
      )
    },
    
    error = function(err) {
      out <-
        paste0(
          "Entry of ",
          ews_district$district[i],
          " on ",
          ews_district$reftime[i],
          " already exists"
        )
      return(out)
    }
  )
}


# ------------------------------------------------
# Send automatic SMS through telerivet
# ------------------------------------------------

phone_numbers <- c("+992938706696", "+992888800509", "+992947777770", "+992901109332")
default_message <- "[Date] [Level] chance for [Heat/Cold]"
warn_days <- 3
warn_type <- "frost"
siteID <- "DYU02"
warn_thres <- "Cold2"

warning <-
  sqlQuery(query = paste0("select * from Coldwave where Name = '", siteID, "' and reftime = CURDATE()"), dbname = "WWCServices")

warning_verbose <- warning %>% 
  dplyr::mutate_all(stringr::str_replace_all, "green", "low") %>%
  dplyr::mutate_all(stringr::str_replace_all, "yellow", "moderate")  %>%
  dplyr::mutate_all(stringr::str_replace_all, "red", "high") %>%
  dplyr::select(warn_thres) %>%
  unlist()


format_date <- function(date) {
  format(date, "%A %d/%m/%Y")
}


message <- paste(format_date(Sys.Date()), warning_verbose[1],"chance for frost in Dushanbe +",
                 format_date(Sys.Date() + 1), warning_verbose[2], "chance for frost in Dushanbe +",
                 format_date(Sys.Date() + 2), warning_verbose[3], "chance for frost in Dushanbe")

API <- "wWuZK_npGbYyvqQLO7vzZNNfwvz9oaHYBNXg"
project_id <- "PJa0f94bd02787dbfe"

send_sms <- function(phone_number, message) {
  print(phone_number)

  cmd <- paste0(
      'curl -s -u ',
      API,
      ': ',
      '"https://api.telerivet.com/v1/projects/',
      project_id,
      '/messages/send\" -H "Content-Type: application/json" -d ',
      '\'{"content": "',
      message,
      '",',
      '"to_number": "',
      phone_number,
      '"}\''
    )
  
  system(cmd)
  
}

for (i in phone_numbers) {
  # send_sms(i, message)
}
