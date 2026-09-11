library(shiny)
library(shinydashboard)
library(tidyr)
library(leaflet)
library(plotly)
library(shiny.i18n)
library(shinyWidgets)
library(RMySQL)
library(dplyr)
library(readr)
library(sf)
library(lubridate)

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

soildata <-
  fst::read_fst(paste0(ROOT_DIR, "/WWCS/planting/appdata/soildata.fst"))
emosdata <-
  fst::read_fst(paste0(ROOT_DIR, "/WWCS/planting/appdata/emosdata.fst"))


time_range_min <- min(emosdata$reftime)
time_range_max <- max(emosdata$reftime)
start_date_f <- max(emosdata$reftime) 


time_obs_min <- min(soildata$day)
time_obs_max <- max(soildata$day)
start_date_o <- time_obs_max - days(30)

sites <- soildata %>% distinct(siteID, .keep_all = TRUE)


## Read administrative areas
bd <- sf::st_read(
  paste0(ROOT_DIR, "/WWCS/boundaries/gadm41_", gadm0, "_2.shp"),
  as_tibble = TRUE
) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))
if (gadm0 == "TJK") bd$district[14] <- "Rudaki2"

mask <- readRDS(file.path(ROOT_DIR, "WWCS/boundaries/mask.rds"))


criteria <-
  read_csv(file.path(ROOT_DIR, "WWCS/planting/appdata/criteria_planting.csv"))


# DEFINE DEFAULT TIME RANGES
# ------------------------------------------------

seldate <- as.Date("2023-05-15")


# SET LANGUAGE TRANSLATION
# ------------------------------------------------
json.path <- file.path(ROOT_DIR, "WWCS/planting/www/translation.json")
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


