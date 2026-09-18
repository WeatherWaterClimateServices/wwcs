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

# ---- Auth & credentials ----
ROOT_DIR <- normalizePath(getwd(), mustWork = TRUE)
while (!file.exists(file.path(ROOT_DIR, ".git"))) {
  parent <- dirname(ROOT_DIR)
  if (parent == ROOT_DIR) break
  ROOT_DIR <- parent
}
source(file.path(ROOT_DIR, "WWCS/.Rprofile"))
options(shiny.sanitize.errors = FALSE)

# READ AND ALLOCATE DATA
# -------------------
noaa.file <- file.path(ROOT_DIR, "WWCS/harvest/appdata/noaa.fst")
if (!file.exists(noaa.file)) {
  noaadata <- data.frame()
} else {
  noaadata <- fst::read_fst(noaa.file) %>%
    dplyr::as_tibble()
}

dmo.file       <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/dmo.fst")
if (!file.exists(dmo.file)) {
  dmo <- data.frame()
} else {
  dmo <- fst::read_fst(dmo.file)
}

obs.file <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/obs.fst")
if (!file.exists(obs.file)) {
  obs <- data.frame()
} else {
  obs <- fst::read_fst(obs.file) %>%
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
if(!(harvest_default_station %in% sites$siteID))
  harvest_default_station <- sites$siteID[1]
print(harvest_default_station)
# Read administrative areas
bd <- sf::st_read(
  paste0(ROOT_DIR, "/WWCS/boundaries/gadm41_", gadm0, "_2.shp"),
  as_tibble = TRUE
) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))
if (gadm0 == "TJK") bd$district[14] <- "Rudaki2"

mask <- readRDS(file.path(ROOT_DIR, "WWCS/boundaries/mask.rds"))

pool_service <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = ifelse(ENV=="PROD", "WWCServices", "WWCServices_DEV"),
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
json.path <- file.path(ROOT_DIR, "WWCS/harvest/www/translation.json")
i18n      <- shiny.i18n::Translator$new(translation_json_path = json.path)
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
