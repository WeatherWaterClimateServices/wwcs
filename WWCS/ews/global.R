library(shiny)
library(shinydashboard)
library(tidyr)
library(leaflet)
library(plotly)
library(shiny.i18n)  
library(shinyWidgets)
library(pool)
library(dplyr)
library(RMySQL)

rm(list = ls())

setwd("/srv/shiny-server/ews/")
options(shiny.sanitize.errors = FALSE)
source('/home/wwcs/wwcs/WWCS/.Rprofile')

# READ AND ALLOCATE DATA
# -------------------

pool <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'SitesHumans',
    host = 'localhost'
  )

pool_service <-
  pool::dbPool(
    RMariaDB::MariaDB(),
    user = 'wwcs',
    password = db_password,
    dbname = 'WWCServices',
    host = 'localhost'
  )

# Read administrative areas
bd <- sf::st_read(paste0("/home/wwcs/wwcs/WWCS/boundaries/gadm41_", gadm0, "_2.shp"), as_tibble = TRUE) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))

if (gadm0 == "TJK") {
  bd$district[14] = "Rudaki2"  
}

mask <- readRDS("/home/wwcs/wwcs/WWCS/boundaries/mask.rds")

sites <- dbReadTable(pool, "Sites") %>%
         dplyr::filter(heatwave == 1 | coldwave == 1) %>%
         dplyr::select(siteID, latitude, longitude) 
          

cold <- dbReadTable(pool_service, "Coldwave") %>%
    dplyr::rename(Coldthres1 = Threshold1, Coldthres2 = Threshold2, Coldthres3 = Threshold3)
  
heat <- dbReadTable(pool_service, "Heatwave") %>%
    dplyr::rename(Heatthres1 = Threshold1, Heatthres2 = Threshold2, Heatthres3 = Threshold3)
  
warning_data <- dplyr::full_join(cold, heat) %>%   
    as_tibble()

ews_district  <- warning_data %>%
                 dplyr::filter(Type == "District") %>%
                 dplyr::rename(district = Name) %>% 
                 dplyr::left_join(bd) 


ews_station  <- warning_data %>%
                dplyr::filter(Type == "Station") %>%
                dplyr::rename(siteID = Name) %>%
                left_join(sites) %>%
                dplyr::rename(lat = latitude, lon = longitude)

humans <- dbReadTable(pool, "Humans") %>%
          dplyr::filter(project == "WWCS")


humans_at_site <-
  sqlQuery(query = "select * from HumanAtSite", dbname = "Humans") %>%
  filter(!stringr::str_detect(siteID, pattern = "-S")) %>% 
  as_tibble() # Do not include soil moisture measurements


format_date <- function(date) {
  format(date, "%A %d/%m/%Y")
}

default_message <- "[Date] [Level] chance for [Heat/Cold]"

# DEFINE DEFAULT TIME RANGES
# ------------------------------------------------

seltime <- as.Date(tail(ews_district$reftime,1))
reftimes <- unique(ews_district$reftime)


# Prepare map data
ews_district_map <- ews_district %>% 
  dplyr::filter(reftime == as.Date(seltime)) %>% 
  dplyr::filter(date == as.Date(seltime)) %>% 
  dplyr::mutate(level = Cold1)

ews_station_index <- ews_station %>% 
                      dplyr::filter(date == seltime) %>% 
                      dplyr::select(c(lat, lon, siteID)) %>%
                      dplyr::distinct() 

# SET LANGUAGE TRANSLATION
# ------------------------------------------------

i18n <- shiny.i18n::Translator$new(translation_json_path = 'www/translation.json')
i18n$set_translation_language('en')
shiny.i18n::usei18n(i18n)


# GLOBAL PLOTTING VARIABLES
# ------------------------------------------------

font <- list(
  size = 15,
  color = "white"
)

label <- list(
  bordercolor = "transparent",
  font = font
)

colgreen <- "#8dd3c7"
colyellow <- "#ffffb3"
colred <- "#fb8072"
ews_colors <- setNames(c(colred, colyellow, colgreen), c("red", "yellow", "green"))

ewspal <- colorBin(palette = c(colgreen,colyellow,colred), domain = seq(0,3),bins = 3)


icon_neutral <- makeAwesomeIcon(
  icon = "dot-circle",
  markerColor =  "lightgray",
  iconColor = "#FFFFFF",
  library = "fa"
)

icon_cold <-  awesomeIcons(
  icon = "temperature-arrow-down",
  markerColor =  "red",
  iconColor = "#FFFFFF", 
  library = "fa"
)

icon_heat <-  awesomeIcons(
  icon = "temperature-arrow-up",
  markerColor =  "red",
  iconColor = "#FFFFFF", 
  library = "fa"
)

