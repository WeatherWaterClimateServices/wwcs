rm(list = ls())
gc()

# Required Libraries
# ------------------------------------------------

library(tidyverse)
library(lubridate)
library(tidync)
library(crch)
library(foreach)
library(doParallel)
library(RMySQL)
library(DBI)

# PARALLEL COMPUTING
# ------------------------------------------------

numOfCores <- parallel::detectCores() - 1
# Register all the cores
doParallel::registerDoParallel(numOfCores)

# SET GLOBAL PARAMETERS
# ------------------------------------------------
source('/opt/shiny-server/WWCS/.Rprofile')

setwd("/srv/shiny-server/dashboard/service")

maxlead <- forecast_days * 24

curr_date <- Sys.Date() 
read_start_date <- curr_date - lubridate::days(forecast_days + train_period)

dates <- as.character(seq(ymd(read_start_date), ymd(curr_date), by = 'days'))

ifs_dir <- "/srv/shiny-server/dashboard/ifsdata/"

# Define two times with different time zones
time1 <- ymd_hms("2023-10-18 12:00:00", tz = "UTC")
time2 <- ymd_hms("2023-10-18 12:00:00", tz = timezone_country)

# Calculate the time difference in hours
time_difference <- as.numeric(difftime(time1, time2, units = "hours"))

ifs_time <- c(0, 3, 6, 9, 12, 15, 18, 21) + time_difference

# For any ifs_time larger than 24, subtract 24
ifs_time <- ifelse(ifs_time > 24, ifs_time - 24, ifs_time) %>% sort()

# READ STATION DATA FROM get_wwcs.R
# ------------------------------------------------

obs <- fst::read_fst("/srv/shiny-server/dashboard/appdata/obs.fst")

station_id <- unique(obs$siteID)


# READ STATION DATA
# ------------------------------------------------

# Allocate Date for Direct Model Output (DMO)
dmo <- data.frame()

print(paste0("---READING IFS DATA---"))

for (i in station_id) {
  # Round Minutes, Select only IFS hours
  station <- obs %>%
    dplyr::select(c(siteID, time, Temperature, Temperature_mean, type)) %>%
    dplyr::filter(
      time >= as.POSIXct(read_start_date, tz = timezone_country) &
        siteID == i & lubridate::minute(time) == 0 &
        lubridate::hour(time) %in% ifs_time
    ) %>%
    tidyr::drop_na() %>%
    tibble::as_tibble()
  
  # Check if record length is enough for EMOS
  if (nrow(station) < ((length(dates) - 1) * length(ifs_time) * miss_val)) {
    rm(station)
    print(paste0("Ignoring station ", i, ", data incomplete"))
    
  } else {
    
    # Read IFS data
    # ----------------------------------------------
    
    print(paste0("Reading IFS data for station ", i))
    ifs <- data.frame()
    
    file <- stringr::str_replace_all(paste0(ifs_dir, i, "_", curr_date, "_merged.nc"), " ","")
    file_ext <- file_ext <- stringr::str_replace_all(paste0(ifs_dir, i, "_", curr_date, "_extended_merged.nc"), " ","")
    
    if (file.exists(file)) {
      nc <- tidync::tidync(file)
      ifs <- nc %>%
        tidync::hyper_tibble() %>%
        dplyr::select(-c(lat, lon)) %>%
        dplyr::rename(lead = time) %>%
        dplyr::mutate(
          reftime = lubridate::with_tz(as.POSIXct(read_start_date + days(reftime), tz = "UTC"), tz = timezone_country),
          time = as.POSIXct(reftime + as.difftime(lead, units = 'hours'), tz = timezone_country),
          siteID = i,
          IFS_T_mea = IFS_T_mea - 273.15
        )
      
      
      # Calculate Daily Temperature Range (DTR)
      # ----------------------------------------------
      
      dtr <- ifs %>%
        dplyr::mutate(day = day(time)) %>%
        dplyr::group_by(reftime, day) %>%
        dplyr::summarize(
          IFS_T_max = max(IFS_T_mea),
          IFS_T_min = min(IFS_T_mea),
          IFS_T_DTR = IFS_T_max - IFS_T_min,
          .groups = "keep"
        )
      
      ifs <- ifs %>%
        dplyr::mutate(day = day(time)) %>%
        dplyr::left_join(dtr, by = c("reftime", "day")) %>%
        dplyr::select(-c(day))
      
      # Add precipitation from extended parameter file
      # ----------------------------------------------
      
      if (file.exists(file_ext)) {
        nc <- tidync(file_ext)
        ifs_pr <- nc %>% 
          tidync::hyper_tibble() %>%
          dplyr::rename(lead = time) %>%
          dplyr::mutate(
            reftime = lubridate::with_tz(as.POSIXct(read_start_date + days(reftime), tz = "UTC"), tz = timezone_country),
            time = as.POSIXct(reftime + as.difftime(lead, units = 'hours'), tz = timezone_country),
            siteID = i
          ) %>%
          dplyr::group_by(reftime, siteID, number) %>%
          dplyr::mutate(tp = c(tp[1], diff(tp)) * 1000) %>%
          dplyr::ungroup() %>%
          dplyr::group_by(time, reftime, lead, siteID) %>%
          dplyr::summarize(IFS_PR_mea = mean(tp), IFS_PR_std = sd(tp), .groups = "keep") %>%
          dplyr::ungroup()
        
        
        ifs <- ifs %>%
          dplyr::left_join(ifs_pr, by = c("time", "siteID", "reftime", "lead"))
      }
    }
      
      # MERGE STATION AND IFS
      dmo <- ifs %>%
        dplyr::left_join(station, by = c("time", "siteID")) %>%
        dplyr::bind_rows(dmo) %>%
        dplyr::arrange(reftime, lead, time)
    }
}

# Set last DTR value to the day before if full-day is missing

dmo$IFS_T_DTR[dmo$lead == 240] = dmo$IFS_T_DTR[dmo$lead == 234]

# FIT EMOS AND STORE DATAFRAME
# ------------------------------------------------

print(paste0("---COMPUTE POSTPROCESSED FORECASTS---"))

emos <- list()
ltimes <- seq(0, maxlead)
ifs_lead <- unlist(distinct(dmo, lead))
station_id <- unique(dmo$siteID)

source('/srv/shiny-server/dashboard/R/interpolate_leadtime.R')

for (s in station_id) {
  print(paste0("Training IFS data for station ", s))
  emos_par <- foreach::foreach(l = ltimes) %dopar% {
    if (l %in% ifs_lead) {
      train <- dmo %>% dplyr::filter(siteID == s & lead == l)
      
    } else {
      # Interpolate between IFS hours
      train_i <- dmo %>% dplyr::filter(siteID == s)
      obs_i <- obs %>% dplyr::filter(siteID == s)
      train <- interpolate_leadtime(l, ifs_lead, train_i, obs_i)
      
    }
    
    # Check if record length is enough for EMOS
    if (sum(!is.na(train$Temperature_mean)) / nrow(train) > 0.5) {
      # Fit EMOS
      tryCatch({
        emos_formula <- as.formula(paste0("Temperature_mean ~ IFS_T_mea + IFS_T_std"))
        emosfit <- crch::crch(
          formula = emos_formula,
          dat     = train,
          dist    = "gaussian",
          type    = "crps"
        )
        
        # Predict EMOS
        predres <- predict(object = emosfit,
                           newdata  = train,
                           type = "parameter")
        
        predres %>%
          dplyr::bind_cols(train) %>%
          dplyr::select(-c("IFS_T_mea", "IFS_T_std")) %>%
          dplyr::rename(IFS_T_mea = location, IFS_T_std = scale) %>%
          tibble::as_tibble() %>%
          dplyr::arrange(reftime, lead)
      }, error = function(e) {
        print(paste0("Error in station ", s, " at lead ", l))
        return(NULL)
      })
    }
  }
  emos <- emos_par %>%
    dplyr::bind_rows(bind_rows(emos, .id = "column_label"))
}

# PREPARE DATA FOR METEOSERIES PLOTS

emos <- emos %>%
  dplyr::mutate(
    q05 = qnorm(0.05, mean = IFS_T_mea, sd = IFS_T_std),
    q25 = qnorm(0.25, mean = IFS_T_mea, sd = IFS_T_std),
    q75 = qnorm(0.75, mean = IFS_T_mea, sd = IFS_T_std),
    q95 = qnorm(0.95, mean = IFS_T_mea, sd = IFS_T_std)
  ) %>%
  dplyr::rename(WWCS = IFS_T_mea, Observations = Temperature_mean)

dmo <- dmo %>%
  dplyr::mutate(
    q05 = qnorm(0.05, mean = IFS_T_mea, sd = IFS_T_std),
    q25 = qnorm(0.25, mean = IFS_T_mea, sd = IFS_T_std),
    q75 = qnorm(0.75, mean = IFS_T_mea, sd = IFS_T_std),
    q95 = qnorm(0.95, mean = IFS_T_mea, sd = IFS_T_std)
  ) %>%
  dplyr::rename(ECMWF = IFS_T_mea, Observations = Temperature_mean)

fst::write_fst(dmo, path = "/srv/shiny-server/dashboard/appdata/dmo.fst", compress = 0)
fst::write_fst(emos, path = "/srv/shiny-server/dashboard/appdata/emos.fst", compress = 0)