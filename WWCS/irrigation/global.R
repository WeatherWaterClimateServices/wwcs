library(shiny)
library(shinydashboard)
library(tidyr)
library(leaflet)
library(plotly)
library(shiny.i18n)
library(shinyWidgets)
library(lubridate)
library(readr)
library(tidyjson)
library(DT)
library(RMariaDB)
library(pool)
library(dplyr)
library(shinyjs)
library(shinymanager)

# Load the credentials - to come from .Rprofile and config.yaml
ROOT_DIR <- normalizePath(getwd(), mustWork=TRUE)
while (!file.exists(file.path(ROOT_DIR, ".git"))) {
  parent <- dirname(ROOT_DIR)
  if (parent == ROOT_DIR) break
  ROOT_DIR <- parent
}
source(file.path(ROOT_DIR, 'WWCS/.Rprofile'))
source(file.path(ROOT_DIR, "WWCS/irrigation/R/calc_et0.R"))
options(shiny.sanitize.errors = FALSE)

## ------------------------------------------------
# DB CONNECTIONS
# ------------------------------------------------

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

# Get the default location from data base

default_station <-
  dbReadTable(pool, "Sites") %>%
  filter(siteID == irrigation_default_station) %>%
  dplyr::select(c(siteID, latitude, longitude))

sites_map_ui <- dbReadTable(pool, "Sites")  %>%
    filter(irrigation == 1) %>%
    dplyr::select(c(siteID))

# Check if it empty, otherwise use the default_station

if (nrow(sites_map_ui) == 0) {
  sites_map_ui <- default_station %>% select(siteID)
}

mask <- readRDS(file.path(ROOT_DIR, "WWCS/boundaries/mask.rds"))

# SET LANGUAGE TRANSLATION
# ------------------------------------------------
translat.file <- file.path(ROOT_DIR, "WWCS/irrigation/www/translation.json")
i18n <-
  shiny.i18n::Translator$new(translation_json_path = translat.file)
i18n$set_translation_language('en')
shiny.i18n::usei18n(i18n)

#Label mandatory fields
labelMandatory <- function(label) {
  tagList(label,
          span("*", class = "mandatory_star"))
}

# GLOBAL PLOTTING VARIABLES
# ------------------------------------------------

font <- list(size = 15,
             color = "white")

label <- list(bordercolor = "transparent",
              font = font)

icon <- awesomeIcons(
  icon = "circle",
  markerColor =  "blue",
  iconColor = "#FFFFFF",
  library = "fa"
)

irrigation_colors <-
  setNames(c("#3182bd", "#9ecae1", "#feb24c"),
           c("Precipitation", "Irrigation", "Need"))



# READ SPATIAL FEATURES OF PLOT POLYGONS
# ------------------------------------------------

# Read shapefiles in the folder /srv/shiny-server/irrigation/appdata/Shapefiles with the sf package
# Read all shape files in the folder and concatenate them into one sf object with the name plot_polygons

shape.path <- file.path(ROOT_DIR, "WWCS/irrigation/appdata/Shapefiles")
for (file in list.files(shape.path, pattern = ".shp", full.names = TRUE)) {  
  try({
    plot_polygons <- plot_polygons %>%
      rbind(
        sf::st_read(file) %>%
          dplyr::select(plot_id, geometry) %>%
          dplyr::rename(id = plot_id)
      )
  }, silent = TRUE)
  
  if (!exists("plot_polygons")) {
    plot_polygons <- sf::st_read(file) %>%
      dplyr::select(plot_id, geometry) %>%
      dplyr::rename(id = plot_id)
  }
}

if (!exists("plot_polygons")) {
  plot_polygons <- sf::st_sf(id = character(0), geometry = sf::st_sfc())
}


# ------------------------------- Login page
credentials <- data.frame(
  user = auth_users,
  password = servicepass,
  start = c("2019-04-15"),
  stringsAsFactors = FALSE
)
