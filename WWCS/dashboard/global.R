library(shiny)
library(shinydashboard)
library(tidyr)
library(dplyr)
library(leaflet)
library(plotly)
library(shiny.i18n)
library(RMySQL)
library(lubridate)
library(shinymanager)


rm(list = ls())
source('/opt/shiny-server/WWCS/.Rprofile')
setwd("/srv/shiny-server/dashboard/")
options(shiny.sanitize.errors = FALSE)

# Load the credentials

credentials <- data.frame(
  user = c("caritas", "tjhm"),
  # mandatory
  password = c(servicepass, servicepass),
  # mandatory
  start = c("2019-04-15"),
  # optinal (all others)
  expire = c(NA, NA),
  admin = c(FALSE, FALSE),
  comment = "Simple and secure authentification mechanism
  for single ‘Shiny’ applications.",
  stringsAsFactors = FALSE
)

# READ DATA
# ------------------------------------------------

# check if all the files are available in the appdata folder
# otherwise assign an empty data frame

if (!file.exists("appdata/obs.fst")) {
  obs <- data.frame()
} else {
  obs <- fst::read_fst("appdata/obs.fst")
}

if (!file.exists("appdata/dmo.fst")) {
  dmo <- data.frame()
} else {
  dmo <- fst::read_fst("appdata/dmo.fst")
}

if (!file.exists("appdata/emos.fst")) {
  emos <- data.frame()
} else {
  emos <- fst::read_fst("appdata/emos.fst")
}

if (!file.exists("appdata/pictocodes.fst")) {
  pictos <- data.frame()
} else {
  pictos <- fst::read_fst("appdata/pictocodes.fst")
}

# Read administrative areas
bd <- sf::st_read(
  paste0(
    "/opt/shiny-server/WWCS/boundaries/gadm41_",
    gadm0,
    "_2.shp"
  ),
  as_tibble = TRUE
) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))

if (gadm0 == "TJK") {
  bd$district[14] = "Rudaki2"
}

mask <- readRDS("/opt/shiny-server/WWCS/boundaries/mask.rds")

if (!file.exists("./appdata/gemos_raster/raster_plot_0.tif")) {
  ifsmap <- data.frame()
} else {
  ifsmap <- raster::raster("./appdata/gemos_raster/raster_plot_0.tif")
}

if (!file.exists("/srv/shiny-server/dashboard/appdata/gemos_raster/raster_merged.nc")) {
  gemos_mea <- data.frame()
  gemos_std <- data.frame()
} else {
  gemos_mea <-
    raster::brick("/srv/shiny-server/dashboard/appdata/gemos_raster/raster_merged.nc",
                  varname = "IFS_T_mea")
  gemos_std <-
    raster::brick("/srv/shiny-server/dashboard/appdata/gemos_raster/raster_merged.nc",
                  varname = "IFS_T_std")
}

sites <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  distinct(siteID, .keep_all = TRUE)  %>%
  filter(!stringr::str_detect(siteID, pattern = "-S")) %>%
  filter(!stringr::str_detect(siteID, pattern = "MS")) %>%
  filter(!stringr::str_detect(siteID, pattern = "GP")) %>%
  filter(!stringr::str_detect(siteID, pattern = "MC")) %>%
  as_tibble() # Do not include soil moisture measurements

deployments <-
  sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
  dplyr::distinct(siteID, .keep_all = TRUE)  %>%
  dplyr::filter(!stringr::str_detect(siteID, pattern = "-S")) # Do not include soil moisture measurements

# Add empty rows in obs with the siteID that are not in the sites dataframe
sites_not_in_obs <- sites %>%
  dplyr::filter(!siteID %in% obs$siteID) %>%
  dplyr::select(siteID, latitude, longitude, altitude)

# add loggerID and start date from deployments to sites_not_in_obs
sites_not_in_obs <- sites_not_in_obs %>%
  dplyr::left_join(deployments, by = "siteID")

# Add  rows in obs with sites not in obs and NA values for the rest of the data frame

if (nrow(obs) > 1) {
  obs <- dplyr::full_join(obs, sites_not_in_obs)
} else {
  obs <- sites_not_in_obs
}

# DEFINE GLOBAL VARIABLES
# ------------------------------------------------

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'SitesHumans',
    host = 'localhost'
  )

default_station <-
  DBI::dbReadTable(pool, "Sites") %>%
  dplyr::filter(siteID == dashboard_default_station) %>%
  dplyr::select(c(siteID, latitude, longitude, type))

# default_station <- c("CLIMDYU001", 38.5606, 68.8008, "WWCS")

offset_obs_forecast <- 0
view_obs_default <- 2

# SET LANGUAGE TRANSLATION
# ------------------------------------------------

i18n <-
  shiny.i18n::Translator$new(translation_json_path = 'www/translation.json')

i18n$set_translation_language('en')
shiny.i18n::usei18n(i18n)

# DEFINE DEFAULT TIME RANGES
# ------------------------------------------------

time_range_f <-
  list("min" = emos$reftime[1], "max" = tail(emos$reftime, 1))

# Check if both min and max are NULL
if (is.null(time_range_f$min) && is.null(time_range_f$max)) {
  current_date <- Sys.Date()
  time_range_f <- list("min" = current_date, "max" = current_date)
}

time_range_o <-
  list("min" = as.Date(Sys.Date() - lubridate::days(60)),
       "max" = Sys.Date())

start_date_f <-
  as.Date(Sys.Date() - lubridate::days(offset_obs_forecast))
start_date_o <-
  as.Date(Sys.Date() - lubridate::days(view_obs_default))

time_range_raster <- seq(0, 90, by = 3)
format <- "%Y-%m-%d %H"

# PREPARE STATION DATA
# ------------------------------------------------

if ("Temperature" %in% colnames(obs)) {
  # If "Temperature" exists, proceed as planned
  last_obs <- obs %>%
    dplyr::group_by(siteID) %>%
    dplyr::filter(!is.na(Temperature)) %>%
    dplyr::summarize(last_obs = dplyr::last(Temperature), .groups = "drop")
  
  station_down <- obs %>%
    dplyr::group_by(siteID) %>%
    dplyr::arrange(time) %>%
    dplyr::summarize(last_time = dplyr::last(time),
                     last_obs = dplyr::last(Temperature)) %>%
    dplyr::filter(last_time < (as.Date(Sys.Date())  - lubridate::days(1)) |
                    is.na(last_obs))
} else {
  # If "Temperature" doesn't exist, return NA for each siteID
  last_obs <- obs %>%
    dplyr::distinct(siteID) %>%
    dplyr::mutate(last_obs = NA)
  
  station_down <- last_obs %>%
    dplyr::mutate(last_time = as.Date(Sys.Date()) - lubridate::days(1))
  
}

if ("siteID" %in% colnames(emos)) {
  station_emos <- dplyr::distinct(emos, siteID)
} else {
  station_emos <- data.frame()
}

if ("type" %in% colnames(obs)) {
  station_data <- obs %>%
    dplyr::group_by(siteID) %>%
    dplyr::filter(dplyr::row_number() == dplyr::n()) %>%
    dplyr::mutate(type = ifelse(is.na(type), "WWCS", type))
} else {
  station_data <- obs %>%
    dplyr::group_by(siteID) %>%
    dplyr::filter(dplyr::row_number() == dplyr::n())
}

rd <- which(station_data$siteID %in% station_emos$siteID)
hd <-
  which(
    !station_data$siteID %in% station_emos$siteID &
      !station_data$siteID %in% station_down$siteID
  )
dw <- which(station_data$siteID %in% station_down$siteID)

tjhm_hd <- which(station_data$type[hd] == "TJHM")
tjhm_rd <- which(station_data$type[rd] == "TJHM")

icons_ready <- awesomeIcons(
  markerColor = "red",
  iconColor = "white",
  squareMarker = F,
  fontFamily = "Helvetica"
)

icons_hold <- awesomeIcons(
  markerColor = "lightgray",
  iconColor = "black",
  squareMarker = F,
  fontFamily = "Helvetica"
)

icons_down <- awesomeIcons(
  icon = "bug",
  library = "fa",
  markerColor = "gray",
  iconColor = "#FFFFFF"
)

icon_sel <- makeAwesomeIcon(#icon = "thermometer",
  iconColor = "#FFFFFF", library = "fa")

# GLOBAL PLOTTING VARIABLES
# ------------------------------------------------

raster_colors <- colorBin(rev(RColorBrewer::brewer.pal(11, "RdBu")), c(-35, 35), bins = 11)

pdf(NULL) # Avoid creation of Rplots.pdf when converting ggplot to plotly

colors <-
  setNames(
    c(
      "#c92118",
      "lightblue",
      "cadetblue" ,
      "orange",
      "darkgreen",
      "purple",
      "darkblue",
      "darkblue",
      "#c92118",
      "lightblue",
      "cadetblue" ,
      "orange",
      "darkgreen",
      "purple",
      "darkblue",
      "darkblue"
    ),
    c(
      "Temperature",
      "RH",
      "Pressure",
      "Solar",
      "Signal",
      "Battery",
      "Precipitation",
      "Evapotranspiration",
      "Temperature_mean",
      "RH_mean",
      "Pressure_mean",
      "Solar_mean",
      "Signal_mean",
      "Battery_mean",
      "Precipitation_mean",
      "Evapotranspiration_mean"
    )
  )


colors_marker <-
  setNames(
    c(
      "red",
      "blue",
      "cadetblue" ,
      "orange",
      "darkgreen",
      "purple",
      "darkblue",
      "darkblue"
    ),
    c(
      "Temperature",
      "RH",
      "Pressure",
      "Solar",
      "Signal",
      "Battery",
      "Precipitation",
      "Evapotranspiration"
    )
  )

labels <- setNames(
  c("°C", "%", "mb", "mV", "db", "mV", "mm", "mm"),
  c(
    "Temperature",
    "RH",
    "Pressure",
    "Solar",
    "Signal",
    "Battery",
    "Precipitation",
    "Evapotranspiration"
  )
)

font <- list(size = 15, color = "white")

label <- list(bordercolor = "transparent", font = font)
