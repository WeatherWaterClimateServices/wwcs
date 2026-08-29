# Required Libraries
# ------------------------------------------------
library(tidyverse)
library(lubridate)
library(tidync)
library(zoo)

# SET GLOBAL PARAMETERS - coming from .Rprofile and config.yaml
# ------------------------------------------------
maxlead <- forecast_days * 24

curr_date <- Sys.Date() 
read_start_date <- curr_date - lubridate::days(forecast_days + train_period)

dates <-
  as.character(seq(
    lubridate::ymd(read_start_date),
    lubridate::ymd(curr_date),
    by = 'days'
  ))

ifs_dir <- file.path(ROOT_DIR, "WWCS/dashboard/ifsdata/")

# Conversion pictocodes to filename
pictolookup_file <- file.path(ROOT_DIR, "WWCS/dashboard/www/weather_icons/look_up_table.csv")
picto_lookup <- readr::read_delim(pictolookup_file, show_col_types = FALSE)


station_id <- emos %>%
  dplyr::select(siteID) %>%
  unique() %>%
  unlist()

# READ STATION DATA
# ------------------------------------------------
pictocodes_daily <- data.frame()
pictocodes_6hourly <- data.frame()
ifs_combined <- data.frame()

print(paste0("---READING IFS DATA---"))

# READ IFS DATA FOR ALL STATIONS

for (i in station_id) {
  # READ IFS DATA
  print(paste0("Reading IFS data for station ", i))
  pictocodes_hourly <- data.frame()
  
  file <- stringr::str_replace_all(paste0(ifs_dir, i, "_", curr_date, "_merged.nc"),
                                   " ",
                                   "")
  
  if (file.exists(file)) {
    # PROCESS PARAMETER PIPELINES
    # ------------------------------------------------
      
    ## Get metadata information
    nc <- tidync::tidync(file)
    ifs <- nc %>%
      tidync::hyper_tibble() %>%
      dplyr::mutate(time = as.numeric(time)) %>%
      dplyr::rename(lead = time) %>%
      dplyr::mutate(
               reftime = lubridate::with_tz(as.POSIXct(reftime, tz = "UTC"), tz = timezone_country),
               time = as.POSIXct(reftime + as.difftime(as.numeric(lead), units = 'hours'), tz = timezone_country),
               siteID = i
             )
      
      ## ifs_combined - used for the precip.fst. this contains weather code
      ifs_combined <- ifs %>%
         dplyr::bind_rows(ifs_combined)

  } ## ifs...nc exists
} ## loop over sites

## COMPUTE DAILY PICTOCODES
## ------------------------------------------------
pictocodes_hourly <- ifs_combined %>%
  mutate(hour = hour(time), date = date(time))
    
# Temporal aggregation for daytime weather codes
pictocodes_daily <- pictocodes_hourly %>%
  dplyr::filter(hour >= 6 & hour <= 18) %>% ## since I converted to timezone_country
  dplyr::group_by(reftime, date, siteID) %>%
  dplyr::summarise(
           ## Method A: Maximum Severity (Open-Meteo operational standard)
           daily_wmo_severity = max(weather_code, na.rm = TRUE),
           
           ## Method B: Statistical Mode (Prevailing condition fallback)
           daily_wmo_mode = as.integer(names(sort(table(weather_code), decreasing = TRUE)[1]))
         ) %>%
  dplyr::ungroup()
    
## Temporal aggregation for every 0 am - 6 am, 7 am - 12 am, 1 pm - 6 pm, 7 pm - 12 pm
for (j in 1:4){
  pictocodes_6hourly <- pictocodes_hourly %>%
    dplyr::filter(hour > (j - 1) * 6 & hour <= j * 6) %>%
    dplyr::group_by(reftime, date, siteID) %>%
    dplyr::summarise(
             ## Method A: Maximum Severity (Open-Meteo operational standard)
             daily_wmo_severity = max(weather_code, na.rm = TRUE),
             
             ## Method B: Statistical Mode (Prevailing condition fallback)
             daily_wmo_mode = as.integer(names(sort(table(weather_code), decreasing = TRUE)[1]))
           ) %>%
    dplyr::ungroup() %>%
    dplyr::bind_rows(pictocodes_6hourly)
}

ifsprecip <- ifs_combined %>%
  dplyr::select(c(time, reftime, lead, siteID, PR))

pictocodes <- pictocodes_daily %>%
  dplyr::inner_join(., picto_lookup)

pictocodes_daynight <- pictocodes_6hourly %>%
  dplyr::inner_join(., picto_lookup)


setwd(file.path(ROOT_DIR, "WWCS/dashboard/appdata"))
fst::write_fst(pictocodes, path = "pictocodes.fst", compress = 0)
fst::write_fst(pictocodes_daynight, path = "pictocodes_daynight.fst", compress = 0)
fst::write_fst(ifsprecip, path = "ifsprecip.fst", compress = 0)

