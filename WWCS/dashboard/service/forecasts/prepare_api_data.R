# Required Libraries
# ------------------------------------------------

library(tidyr)
library(tidyverse)
library(lubridate)
library(pool)
library(RMySQL)

rm(list = ls())

setwd("/srv/shiny-server/dashboard/service/forecasts")
source('/opt/shiny-server/WWCS/.Rprofile')


pool_service <-
  dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'WWCServices',
    host = 'localhost'
  )

# READ DATA
# ------------------------------------------------

emos <-
  fst::read_fst("/srv/shiny-server/dashboard/appdata/emos.fst")
pictos <-
  fst::read_fst("/srv/shiny-server/dashboard/appdata/pictocodes.fst")

forecasts <- emos %>%
  dplyr::mutate(date = as.Date(date(time))) %>%
  dplyr::group_by(siteID, reftime, date) %>%
  dplyr::summarize(
    Tmax = round(max(WWCS), 2),
    Tmin = round(min(WWCS), 2),
    Tmean = round(mean(WWCS), 2),
    .groups = "drop"
  )

icons <- pictos %>%
  dplyr::mutate(icon = paste0(day, ".png")) %>%
  dplyr::select(reftime, date, siteID, icon)  %>%
  dplyr::as_tibble()

forecasts <- forecasts %>%
  dplyr::left_join(icons) %>%
  dplyr::mutate(day = as.numeric(difftime(date, reftime, units =
                                            "days"))) %>%
  dplyr::mutate(date = as.Date(reftime)) %>%
  dplyr::select(-c("reftime")) %>%
  dplyr::arrange(siteID, date, day, Tmax, Tmin, Tmean, icon) %>%
  dplyr::filter(day < 6)


readr::write_delim(forecasts, file = "/srv/shiny-server/dashboard/service/forecasts/forecasts_api.csv", delim = ",")

# --------------------------------
# Expand API for day and night
# --------------------------------

icons_daynight <- fst::read_fst("/srv/shiny-server/dashboard/appdata/pictocodes_daynight.fst") %>%
  dplyr::mutate(icon = paste0(ifelse(daynight == "night", night, day), ".png")) %>%
  dplyr::select(reftime, date, siteID, icon, timeofday)  %>%
  dplyr::as_tibble()


# Group by 0 am - 6 am, 7 am - 12 am, 1 pm - 6 pm, 7 pm - 12 pm
forecasts_daynight <- emos %>%
  dplyr::mutate(
    date = as.Date(date(time)),
    timeofday = ifelse(hour(time) <= 6, 1, ifelse(hour(time) < 12, 2, ifelse(hour(
      time
    ) < 18, 3, 4))),
    daynight = ifelse(timeofday == 1 |
                        timeofday == 4, "night", "day")
  ) %>%
  dplyr::group_by(siteID, reftime, date, timeofday) %>%
  dplyr::summarize(
    Tmax = round(max(WWCS), 2),
    Tmin = round(min(WWCS), 2),
    Tmean = round(mean(WWCS), 2),
    .groups = "drop"
  ) %>%
  dplyr::left_join(icons_daynight) %>%
  dplyr::mutate(day = as.numeric(difftime(date, reftime, units = "days"))) %>%
  dplyr::mutate(date = as.Date(reftime)) %>%
  dplyr::select(-c("reftime")) %>%
  dplyr::arrange(siteID, date, day, timeofday) %>%
  dplyr::filter(day < 6)


readr::write_delim(forecasts_daynight, file = "/srv/shiny-server/dashboard/service/forecasts/forecasts_daynight_api.csv", delim = ",")

forecasts <- forecasts %>%
  dplyr::mutate(timeofday = -1)

forecasts_all <- rbind(forecasts, forecasts_daynight) %>%
  dplyr::arrange(siteID, date, day) 


# Write Into Data Base
# ------------------------------------------------

forecasts_all <- forecasts_all %>% filter(date >= Sys.Date() - days(5))

for (i in 1:nrow(forecasts_all)) {
  tryCatch(
    expr = {
      pool::dbExecute(
        pool_service,
        sprintf(
          'REPLACE INTO Forecasts (siteID, date, Tmax, Tmin, Tmean, icon, day, timeofday)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?);'

        ),
        params = list(
          forecasts_all$siteID[i],
          forecasts_all$date[i],
          forecasts_all$Tmax[i],
          forecasts_all$Tmin[i],
          forecasts_all$Tmean[i],
          forecasts_all$icon[i],
          forecasts_all$day[i],
          forecasts_all$timeofday[i]
        )
      )
    },
    error = function(err) {
      print(err)
    }
  )
}

# Delete all entries in the table "Forecasts" which are older than two months

pool::dbExecute(
  pool_service,
  'DELETE FROM Forecasts WHERE date < DATE_SUB(NOW(), INTERVAL 2 MONTH);'
)
