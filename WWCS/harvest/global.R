library(shiny)
library(shinydashboard)
library(tidyr)
library(leaflet)
library(plotly)
library(shiny.i18n)
library(shinyWidgets)
library(dplyr)
library(readr)
library(sf)
library(lubridate)
library(RMySQL)

rm(list = ls())

source('/home/wwcs/wwcs/WWCS/.Rprofile')
options(shiny.sanitize.errors = FALSE)
setwd("/srv/shiny-server/harvest/")

# READ AND ALLOCATE DATA
# -------------------

if (!file.exists("/srv/shiny-server/harvest/appdata/noaa.fst")) {
  noaadata <- data.frame()
} else {
  noaadata <- fst::read_fst("/srv/shiny-server/harvest/appdata/noaa.fst") %>%
    dplyr::as_tibble()
}

if (!file.exists("/srv/shiny-server/dashboard/appdata/dmo.fst")) {
  dmo <- data.frame()
} else {
  dmo <- fst::read_fst("/srv/shiny-server/dashboard/appdata/dmo.fst")
}

if (!file.exists("/srv/shiny-server/dashboard/appdata/obs.fst")) {
  obs <- data.frame()
} else {
  obs <- fst::read_fst("/srv/shiny-server/dashboard/appdata/obs.fst") %>%
  group_by(siteID, time = floor_date(time, unit = "hour")) %>%
    summarise(Precipitation = sum(Precipitation))
}

time_noaa_min <- as.Date(min(noaadata$time))
time_noaa_max <- as.Date(max(noaadata$time))
start_date_noaa <- time_noaa_max

time_obs_min <- as.Date(min(obs$time))
time_obs_max <- as.Date(max(obs$time))
start_date_o <- time_obs_max - days(10)

time_ifs_min <- as.Date(min(dmo$reftime))
time_ifs_max <- as.Date(max(dmo$reftime))
start_date_f <- time_ifs_max - days(1)

sites <- sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::filter(harvest == 1)  %>%
  dplyr::select(c(siteID, latitude, longitude, district))

# Read administrative areas
bd <- sf::st_read(paste0("/home/wwcs/wwcs/WWCS/boundaries/gadm41_", gadm0, "_2.shp"), as_tibble = TRUE) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))

if (gadm0 == "TJK") {
  bd$district[14] = "Rudaki2"  
}

mask <- readRDS("/home/wwcs/wwcs/WWCS/boundaries/mask.rds")

pool_service <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'WWCServices',
    host = 'localhost'
  )


# Take the last cold wave warning (day before today)
ews_station  <- dbReadTable(pool_service, "Coldwave")  %>%
  dplyr::filter(Type == "Station") %>%
  dplyr::rename(siteID = Name) %>%
  dplyr::filter(as.Date(reftime) == Sys.Date() - lubridate::days(1)) %>%
  right_join(sites) %>%
  as_tibble()


# DEFINE DEFAULT TIME RANGES
# ------------------------------------------------

seldate <- Sys.Date() - days(1)


# SET LANGUAGE TRANSLATION
# ------------------------------------------------

i18n <-
  shiny.i18n::Translator$new(translation_json_path = '/srv/shiny-server/harvest/www/translation.json')
i18n$set_translation_language('en')
shiny.i18n::usei18n(i18n)


# GLOBAL PLOTTING VARIABLES
# ------------------------------------------------

font <- list(size = 15,
             color = "white")

label <- list(bordercolor = "transparent",
              font = font)

icon_sel <- makeAwesomeIcon(iconColor = "#FFFFFF",
                            library = "fa")

raster_colors <- colorBin(RColorBrewer::brewer.pal(9, "YlGnBu"),
                          bins = c(0, 1, 5, 10, 15, 20, 25, 30, 50, 100))

colgreen <- "#8dd3c7"
colyellow <- "#ffffb3"
colred <- "#fb8072"
ews_colors <- setNames(c(colred, colyellow, colgreen), c("red", "yellow", "green"))
