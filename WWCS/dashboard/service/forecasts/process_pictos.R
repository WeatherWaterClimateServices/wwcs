rm(list = ls())

# Required Libraries
# ------------------------------------------------

library(tidyverse)
library(lubridate)
library(tidync)
library(zoo)
library(foreach)
library(doParallel)

numOfCores <- detectCores()
# Register all the cores
registerDoParallel(numOfCores)

# SET GLOBAL PARAMETERS
# ------------------------------------------------

setwd("/srv/shiny-server/dashboard/service")

source('/home/wwcs/wwcs/WWCS/.Rprofile')
maxlead <- forecast_days * 24


curr_date <- Sys.Date() 
read_start_date <- curr_date - lubridate::days(forecast_days + train_period)

dates <-
  as.character(seq(
    lubridate::ymd(read_start_date),
    lubridate::ymd(curr_date),
    by = 'days'
  ))

ifs_dir <- "/srv/shiny-server/dashboard/ifsdata/"
ifs_time <- c(0, 3, 6, 9, 12, 15, 18, 21)

# Conversion pictocodes to filename

picto_lookup <-
  readr::read_delim(
    "/srv/shiny-server/dashboard/appdata/weather_icons/look_up_tabel.csv",
    show_col_types = FALSE
  )


# Parameters for Opacity Calculations
aL = 1
aM = 0.91
aH = 0.4

vis_threshold = 1500
lightning_threshold = 1

# POS1 Parameters
fog_threshold = 0.4

pos1_hour <- function(VIS, fog_threshold) {
  if (VIS > fog_threshold) {
    code <- "2"
  } else {
    code <- "0"
  }
  
  return(code)
}

# POS2 Parameters
opacity_threshold = c(0.12, 0.4, 0.65, 0.9)

pos2_hour <- function(cloud_total_opacity, opacity_threshold) {
  if (cloud_total_opacity < opacity_threshold[1]) {
    code = "K"
  } else if (cloud_total_opacity <= opacity_threshold[2]) {
    code = "F"
  } else if (cloud_total_opacity <= opacity_threshold[3]) {
    code = "S"
  } else if (cloud_total_opacity <= opacity_threshold[4]) {
    code = "B"
  } else if (cloud_total_opacity > opacity_threshold[4]) {
    code = "O"
  }
  
  return(code)
}

# POS3 Parameters
prob_lightning = 0.28

pos3_hour <-
  function(## LT, ## BORIS here
           PR,
           HSURF,
           CLCH,
           CLCM,
           CLCL,
           prob_lightning,
           elevation,
           WWCS) {
    ## if (LT > prob_lightning) { ## BORIS here
    ##  if (WWCS < 2) {
    ##    code = "TN"
    ##  } else {
    ##    code = "TS"
    ##  }
    ## } else {
      if (PR > 0) {
        if (WWCS > 2) {
          code = "RA"
        } else if (1 <= WWCS &
                   WWCS <= 2) {
          code = "RS"
        } else if (WWCS < 1) {
          code = "SN"
        }
      } else {
        if (CLCH > 0.25 & CLCL < 0.1 & CLCM < 0.2) {
          code = "CI"
        } else {
          code = "NW"
        }
      }
    ## } ## BORIS here
    
    return(code)
  }


# POS4 Parameters

pr_threshold = c(0.07, 0.5, 2)

pos4_hour <- function(PR, pr_threshold) {
  if (PR == 0) {
    code = "N"
  } else if (PR < pr_threshold[1]) {
    code = "V"
  } else if (PR < pr_threshold[2]) {
    code = "W"
  } else if (PR < pr_threshold[3]) {
    code = "M"
  } else {
    code = "S"
  }
  return(code)
  
}


# Temporal aggregation POS3

pos3_temp <- function(POS3) {
  n = length(POS3)
  if (sum(POS3 == "TN" | POS3 == "TS") / n > 0.1) {
    if (sum(POS3 == "SN" |
            POS3 == "TN") > sum(POS3 == "RA" | POS3 == "TS")) {
      code = "TN"
    } else {
      code = "TS"
    }
    
  } else if ((sum(POS3 == "RA" |
                  POS3 == "RS" | POS3 == "SN") / n) > 0.1) {
    if (sum(POS3 == "RA") > 0.7 * sum(POS3 == "RA" |
                                      POS3 == "RS" |
                                      POS3 == "SN")) {
      code = "RA"
    } else if (sum(POS3 == "SN") > 0.7 * sum(POS3 == "RA" &
                                             POS3 == "RS" &
                                             POS3 == "SN")) {
      code = "SN"
    } else {
      code = "RS"
    }
  } else {
    if ((sum(POS3 == "CL") / n) > 0.6) {
      code = "CL"
    } else {
      code = "NW"
    }
  }
  return(code)
}

pos4_temp <- function(POS4) {
  return(names(which.max(table(POS4))))
}


# READ STATION DATA FROM get_wwcs.R
# ------------------------------------------------

obs <-
  fst::read_fst("/srv/shiny-server/dashboard/appdata/obs.fst")

emos <- fst::read_fst("/srv/shiny-server/dashboard/appdata/emos.fst") %>%
  dplyr::select(WWCS, reftime, time, siteID, lead) %>%
  dplyr::as_tibble()

station_id <- emos %>%
  dplyr::select(siteID) %>%
  dplyr::filter(!stringr::str_detect(siteID, pattern = "-S")) %>% # Do not include soil moisture measurements
  unique() %>%
  unlist()

# READ STATION DATA
# ------------------------------------------------

# Allocate Date for Direct Model Output (DMO)

pictocodes_daily <- data.frame()
pictocodes_6hourly <- data.frame()
ifs_extended <- data.frame()

print(paste0("---READING IFS DATA---"))

# READ IFS DATA FOR ALL STATIONS

for (i in station_id) {
  # READ IFS DATA
  print(paste0("Reading IFS data for station ", i))
  pictocodes_hourly <- data.frame()
  
  file <- stringr::str_replace_all(paste0(ifs_dir, i, "_", curr_date, "_extended_merged.nc"),
                                   " ",
                                   "")
  
  if (file.exists(file)) {
    # PROCESS PARAMETER PIPELINES
    # ------------------------------------------------
    
    # Try catch an error in the loop
    
    tryCatch({
      altitude_station <- obs %>%
        dplyr::filter(siteID == i) %>%
        dplyr::summarize(altitude = altitude[1]) %>%
        unlist()
      
      nc <- RNetCDF::open.nc(file)
      
      # Extract reftime unit string
      reftime_units <- RNetCDF::att.get.nc(nc, "reftime", "units")
      RNetCDF::close.nc(nc)
      
      # Extract the reference date from the unit string
      # Format is typically "days since YYYY-MM-DD HH:MM:SS"
      ref_date_str <- sub("days since ", "", reftime_units)  # Remove "days since "
      reference_time <- as.POSIXct(ref_date_str, tz = "UTC") # Convert to POSIXct
      
      # Get metadata information
      nc <- tidync::tidync(file)
      ifs <- nc %>%
        tidync::hyper_tibble() %>%
        dplyr::mutate(time = as.numeric(time)) %>%
        dplyr::rename(lead = time) %>%
        dplyr::mutate(
          reftime = lubridate::with_tz(as.POSIXct(reftime, tz = "UTC"), tz = timezone_country),
          time = as.POSIXct(reftime + as.difftime(as.numeric(lead), units = 'hours'), tz = timezone_country),
          z = as.numeric(z) / 9.807,            
          siteID = i,          
          CLCT = tcc,
          CLCL = lcc,
          CLCM = mcc,
          CLCH = hcc,
          PR = tp * 1000,            # from m to mm
          VIS =  ifelse(p3020 < vis_threshold, 0, 1), ## BORIS - this needs work
          LT = NA, ## BORIS - this parameter is not available in OM
          HSURF = z[1], ## BORIS - possibly remove this parameter
          elevation = altitude_station,
          .groups = "keep"
        ) %>%
        dplyr::arrange(siteID, reftime)        
      
      reftimes <- unique(ifs$reftime)
      ifs_hourly <- data.frame()
      
      for (j in 1:length(reftimes)) {
        time = as.POSIXct(reftimes[j], tz = timezone_country) + as.difftime(seq(0, maxlead), units = 'hours')
        ifs_hourly <- data.frame("time" = time) %>%
          tibble::as_tibble() %>%
          dplyr::mutate(
            reftime = as.POSIXct(reftimes[j], tz = timezone_country),
            lead = as.numeric(time - reftime, units = 'hours'),
            siteID = i
          ) %>%
          dplyr::bind_rows(ifs_hourly)
      }
      
      emos_site <- emos %>%
        dplyr::filter(siteID == i)
      
      # Add lead 0 and set the same values as lead 1 in emos_site 
      emos_site_0 <- emos_site %>% 
        dplyr::filter(lead == 1) %>% 
        dplyr::mutate(time = time - hours(1)) %>%
        dplyr::mutate(lead = 0) 
      
      emos_site <- dplyr::bind_rows(emos_site, emos_site_0) %>% arrange(lead)
      
      
      
      ifs_hourly <- ifs_hourly %>%
        dplyr::left_join(ifs, by = c("reftime", "time", "lead", "siteID")) %>%
        dplyr::mutate(
          ## LT = zoo::na.approx(LT) * 24 * 100, ## BORIS here
          # number of flashes per 100 km2 and hour
          CLCT = zoo::na.approx(CLCT),
          CLCM = zoo::na.approx(CLCM),
          CLCH = zoo::na.approx(CLCH),
          CLCL = zoo::na.approx(CLCL),
          ## HSURF = zoo::na.approx(HSURF), ## BORIS here
          elevation = zoo::na.approx(elevation),
          pCLCL = aL * CLCL,
          pCLCM = aM * CLCM,
          pCLCH = aH * CLCH,
          cloud_upper_opacity =  pCLCM + pCLCH - pCLCM * pCLCH,
          cloud_total_opacity = pCLCL + cloud_upper_opacity - pCLCL * pCLCM - pCLCL * pCLCH + pCLCL * pCLCM * pCLCH,
          VIS = na.approx(VIS),
          PR = na.approx(PR),
        ) %>%
        dplyr::right_join(emos_site, by = c("reftime", "time", "lead", "siteID")) %>%
        dplyr::select(-c(pCLCL, pCLCM, pCLCH))
      
      
      ifs_extended <- ifs_hourly %>%
        dplyr::bind_rows(ifs_extended)
      
      # COMPUTE HOURLY PICTOCODES
      # ------------------------------------------------
      
      pictocodes_hourly <- ifs_hourly %>%
        ## na.omit() %>% ## BORIS here - unclear whether this is necessary
        dplyr::rowwise()  %>% 
        dplyr::mutate(POS1 = pos1_hour(VIS, fog_threshold)) %>%
        dplyr::mutate(POS2 = pos2_hour(cloud_total_opacity, opacity_threshold)) %>%
        dplyr::mutate(POS3 = pos3_hour(
          ## LT, ## BORIS here
          PR,
          HSURF,
          CLCH,
          CLCM,
          CLCL,
          prob_lightning,
          elevation,
          WWCS
        )) %>%
        dplyr::mutate(POS4 = pos4_hour(PR, pr_threshold))  %>%
        dplyr::mutate(CODE = paste0(POS1, POS2, POS3, POS4)) %>%
        dplyr::bind_rows(pictocodes_hourly)
      
    } , error = function(e) {
      pictocodes_hourly <- data.frame()
    })
  }
  
  # COMPUTE DAILY PICTOCODES
  # ------------------------------------------------
  
  if (nrow(pictocodes_hourly) > 1) {
    pictocodes_hourly <- pictocodes_hourly %>%
      mutate(hour = hour(time), date = date(time))
    
    # Temporal aggregation for daily values
    
    temp_pict <-  pictocodes_hourly %>%
      dplyr::filter(hour >= 6 & hour <= 18)
    
    if (nrow(temp_pict) > 0) {
      pictocodes_daily <- temp_pict %>%
        dplyr::group_by(reftime, date, siteID) %>%
        dplyr::summarise(
          POS1 = ifelse(mean(as.numeric(POS1)) > 1, 2, 0),
          cloud_total_opacity = mean(cloud_total_opacity),
          POS3 = pos3_temp(POS3),
          POS4 = pos4_temp(POS4),
          .groups = "keep"
        ) %>%
        dplyr::rowwise()  %>%
        dplyr::mutate(
          POS2 = pos2_hour(cloud_total_opacity, opacity_threshold),
          CODE = paste0(POS1, POS2, POS3, POS4)
        ) %>%
        dplyr::bind_rows(pictocodes_daily)
    }
    
    # Temporal aggregation for every 0 am - 6 am, 7 am - 12 am, 1 pm - 6 pm, 7 pm - 12 pm
    
    for (j in 1:4) {
      temp_pict <- pictocodes_hourly %>%
        dplyr::filter(hour > (j - 1) * 6 & hour <= j * 6)
      
      if (nrow(temp_pict) > 0) {
        pictocodes_6hourly <- temp_pict %>%
          dplyr::group_by(reftime, date, siteID) %>%
          dplyr::summarise(
            POS1 = ifelse(mean(as.numeric(POS1)) > 1, 2, 0),
            cloud_total_opacity = mean(cloud_total_opacity),
            POS3 = pos3_temp(POS3),
            POS4 = pos4_temp(POS4),
            .groups = "keep"
          ) %>%
          dplyr::rowwise()  %>%
          dplyr::mutate(
            POS2 = pos2_hour(cloud_total_opacity, opacity_threshold),
            CODE = paste0(POS1, POS2, POS3, POS4)
          ) %>%
          dplyr::mutate(timeofday = j ,
                        daynight = ifelse(j == 1 |
                                            j == 4, "night", "day")) %>%
          dplyr::bind_rows(pictocodes_6hourly)
      }
    }
  }
}

ifsprecip <- ifs_extended %>%
  dplyr::select(c(time, reftime, lead, siteID, PR))

pictocodes <- pictocodes_daily %>%
  dplyr::inner_join(., picto_lookup)

pictocodes_daynight <- pictocodes_6hourly %>%
  dplyr::inner_join(., picto_lookup)


fst::write_fst(pictocodes, path = "/srv/shiny-server/dashboard/appdata/pictocodes.fst", compress = 0)
fst::write_fst(pictocodes_daynight, path = "/srv/shiny-server/dashboard/appdata/pictocodes_daynight.fst", compress = 0)
fst::write_fst(ifsprecip, path = "/srv/shiny-server/dashboard/appdata/ifsprecip.fst", compress = 0)

