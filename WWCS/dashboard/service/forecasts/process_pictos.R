# Required Libraries
# ------------------------------------------------
library(tidyverse)
library(lubridate)
library(tidync)
library(fst)
#library(zoo)

# SET GLOBAL PARAMETERS - coming from .Rprofile and config.yaml
# ------------------------------------------------

# READ STATION DATA (and forecasts) from dmo
# ------------------------------------------------
dmo.file <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/dmo.fst")
dmo <- read_fst(dmo.file)

## COMPUTE daytime PICTOCODES
## ------------------------------------------------
pictocodes_hourly <- dmo %>%
  mutate(hour = hour(time), date = date(time))
    
# Temporal aggregation for daytime weather codes
pictocodes_daytime <- pictocodes_hourly %>%
  dplyr::filter(hour >= 6 & hour <= 18) %>% ## since I converted to timezone_country
  dplyr::group_by(reftime, date, siteID) %>%
  dplyr::summarise(
           ## Method A: Maximum Severity (Open-Meteo operational standard)
           icon = max(weather_code, na.rm = TRUE)
           
           ## Method B: Statistical Mode (Prevailing condition fallback)
           ## daily_wmo_mode = as.integer(names(sort(table(weather_code), decreasing = TRUE)[1]))
         ) %>%
  dplyr::ungroup()

##
## Temporal aggregation for every 0 am - 6 am, 7 am - 12 am, 1 pm - 6 pm, 7 pm - 12 pm
##
pictocodes_6hourly <- data.frame()
for (j in 1:4){
  pictocodes_6hourly <- pictocodes_hourly %>%
    dplyr::filter(hour > (j - 1) * 6 & hour <= j * 6) %>%
    dplyr::group_by(reftime, date, siteID) %>%
    dplyr::summarise(
             ## Method A: Maximum Severity (Open-Meteo operational standard)
             icon = max(weather_code, na.rm = TRUE)
             
             ## Method B: Statistical Mode (Prevailing condition fallback)
             # daily_wmo_mode = as.integer(names(sort(table(weather_code), decreasing = TRUE)[1]))
           ) %>%
    dplyr::ungroup() %>%
    dplyr::bind_rows(pictocodes_6hourly)
}

setwd(file.path(ROOT_DIR, "WWCS/dashboard/appdata"))
fst::write_fst(pictocodes_daytime, path = "pictocodes_daytime.fst", compress = 0)
fst::write_fst(pictocodes_6hourly, path = "pictocodes_6hourly.fst", compress = 0)

