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

# ---- Auth & credentials ----
ROOT_DIR <- normalizePath(getwd(), mustWork = TRUE)
while (!file.exists(file.path(ROOT_DIR, ".git"))) {
  parent <- dirname(ROOT_DIR)
  if (parent == ROOT_DIR) break
  ROOT_DIR <- parent
}
source(file.path(ROOT_DIR, "WWCS/.Rprofile"))
options(shiny.sanitize.errors = FALSE)

credentials <- data.frame(
  user     = auth_users,
  password = servicepass,
  start    = c("2019-04-15"),
  stringsAsFactors = FALSE
)

# ---- Static resources (loaded once at startup) ----
bd <- sf::st_read(
  paste0(ROOT_DIR, "/WWCS/boundaries/gadm41_", gadm0, "_2.shp"),
  as_tibble = TRUE
) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))
if (gadm0 == "TJK") bd$district[14] <- "Rudaki2"

mask <- readRDS(file.path(ROOT_DIR, "WWCS/boundaries/mask.rds"))

pool <- pool::dbPool(
  RMariaDB::MariaDB(),
  user     = "wwcs",
  password = db_password,
  dbname   = "SitesHumans",
  host     = "localhost"
)

offset_obs_forecast <- 0
view_obs_default    <- 2
time_range_raster   <- seq(0, 90, by = 3)
format              <- "%Y-%m-%d %H"

json.path <- file.path(ROOT_DIR, "WWCS/dashboard/www/translation.json")
i18n      <- shiny.i18n::Translator$new(translation_json_path = json.path)
i18n$set_translation_language("en")
shiny.i18n::usei18n(i18n)

raster_colors <- colorBin(rev(RColorBrewer::brewer.pal(11, "RdBu")), c(-35, 35), bins = 11)
pdf(NULL)

colors <- setNames(
  c("#c92118", "lightblue", "cadetblue", "orange", "darkgreen", "purple", "darkblue", "darkblue",
    "#c92118", "lightblue", "cadetblue", "orange", "darkgreen", "purple", "darkblue", "darkblue"),
  c("Temperature", "RH", "Pressure", "Solar", "Signal", "Battery", "Precipitation", "Evapotranspiration",
    "Temperature_mean", "RH_mean", "Pressure_mean", "Solar_mean", "Signal_mean", "Battery_mean",
    "Precipitation_mean", "Evapotranspiration_mean")
)

colors_marker <- setNames(
  c("red", "blue", "cadetblue", "orange", "darkgreen", "purple", "darkblue", "darkblue"),
  c("Temperature", "RH", "Pressure", "Solar", "Signal", "Battery", "Precipitation", "Evapotranspiration")
)

labels <- setNames(
  c("°C", "%", "mb", "mV", "db", "mV", "mm", "mm"),
  c("Temperature", "RH", "Pressure", "Solar", "Signal", "Battery", "Precipitation", "Evapotranspiration")
)

font  <- list(size = 15, color = "white")
label <- list(bordercolor = "transparent", font = font)

icons_ready <- awesomeIcons(markerColor = "red",       iconColor = "white", squareMarker = FALSE, fontFamily = "Helvetica")
icons_hold  <- awesomeIcons(markerColor = "lightgray", iconColor = "black", squareMarker = FALSE, fontFamily = "Helvetica")
icons_down  <- awesomeIcons(icon = "bug", library = "fa", markerColor = "gray", iconColor = "#FFFFFF")
icon_sel    <- makeAwesomeIcon(iconColor = "#FFFFFF", library = "fa")

# ---- File paths ----
.obs_file       <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/obs.fst")
.dmo_file       <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/dmo.fst")
.emos_file      <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/emos.fst")
.picto_file     <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/pictocodes.fst")
.raster0_file   <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/gemos_raster/raster_plot_0.tif")
.rastermgd_file <- file.path(ROOT_DIR, "WWCS/dashboard/appdata/gemos_raster/raster_merged.nc")
.daily_files    <- c(.dmo_file, .emos_file, .picto_file, .raster0_file, .rastermgd_file)

# ---- sql_rv: SQL tables — reload every hour (no mtime for DB) ----
load_sql <- function() {
  sites <- sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
    dplyr::distinct(siteID, .keep_all = TRUE) %>%
    dplyr::filter(forecast == 1) %>%
    as_tibble()

  deployments <- sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
    dplyr::distinct(siteID, .keep_all = TRUE)

  default_station <- DBI::dbReadTable(pool, "Sites") %>%
    dplyr::filter(siteID == dashboard_default_station) %>%
    dplyr::select(c(siteID, latitude, longitude, type))

  list(sites = sites, deployments = deployments, default_station = default_station)
}

sql_rv <- reactiveVal(load_sql())

sql_refresh <- function() {
  sql_rv(load_sql())
  later::later(sql_refresh, 3600)
}
later::later(sql_refresh, 3600)

# ---- obs_rv: obs.fst — check every 10 min, reload on mtime change ----
.obs_mtime <- if (file.exists(.obs_file)) file.mtime(.obs_file) else as.POSIXct(NA)

load_obs <- function() {
  if (!file.exists(.obs_file)) return(data.frame())
  fst::read_fst(.obs_file)
}

obs_rv <- reactiveVal(load_obs())

obs_refresh <- function() {
  current <- if (file.exists(.obs_file)) file.mtime(.obs_file) else as.POSIXct(NA)
  if (!is.na(current) && (is.na(.obs_mtime) || current > .obs_mtime)) {
    obs_rv(load_obs())
    .obs_mtime <<- current
  }
  later::later(obs_refresh, 600)
}
later::later(obs_refresh, 600)

# ---- daily_rv: dmo/emos/pictos/rasters — check every hour, reload on mtime change ----
.daily_mtime <- {
  mt <- file.mtime(.daily_files[file.exists(.daily_files)])
  if (length(mt) == 0) as.POSIXct(NA) else max(mt)
}

load_daily <- function() {
  dmo <- if (!file.exists(.dmo_file)) data.frame() else {
    fst::read_fst(.dmo_file) %>%
      dplyr::select(time, reftime, siteID, ECMWF, q05, q25, q75, q95)
  }

  emos <- if (!file.exists(.emos_file)) data.frame() else {
    fst::read_fst(.emos_file) %>%
      dplyr::select(time, reftime, siteID, WWCS, q05, q25, q75, q95, IFS_PR_mea, Observations)
  }

  pictos <- if (!file.exists(.picto_file)) data.frame() else {
    fst::read_fst(.picto_file) %>%
      dplyr::select(reftime, siteID, day, date)
  }

  ifsmap <- if (!file.exists(.raster0_file)) data.frame() else raster::raster(.raster0_file)

  if (!file.exists(.rastermgd_file)) {
    gemos_mea <- data.frame()
    gemos_std <- data.frame()
  } else {
    gemos_mea <- raster::brick(.rastermgd_file, varname = "IFS_T_mea")
    gemos_std <- raster::brick(.rastermgd_file, varname = "IFS_T_std")
  }

  time_range_f <- list("min" = emos$reftime[1], "max" = tail(emos$reftime, 1))
  if (is.null(time_range_f$min) && is.null(time_range_f$max)) {
    time_range_f <- list("min" = Sys.Date(), "max" = Sys.Date())
  }

  list(
    dmo = dmo, emos = emos, pictos = pictos,
    ifsmap = ifsmap, gemos_mea = gemos_mea, gemos_std = gemos_std,
    time_range_f = time_range_f
  )
}

daily_rv <- reactiveVal(load_daily())

daily_refresh <- function() {
  current <- {
    mt <- file.mtime(.daily_files[file.exists(.daily_files)])
    if (length(mt) == 0) as.POSIXct(NA) else max(mt)
  }
  if (!is.na(current) && (is.na(.daily_mtime) || current > .daily_mtime)) {
    daily_rv(load_daily())
    .daily_mtime <<- current
  }
  later::later(daily_refresh, 3600)
}
later::later(daily_refresh, 3600)

# ---- Static time ranges ----
# time_range_f is inside daily_rv(); expose a global copy for ui.R which reads it at parse time
time_range_f <- isolate(daily_rv())$time_range_f
time_range_o <- list(
  "min" = as.Date(Sys.Date() - lubridate::days(60)),
  "max" = Sys.Date()
)
start_date_f <- as.Date(Sys.Date() - lubridate::days(offset_obs_forecast))
start_date_o <- as.Date(Sys.Date() - lubridate::days(view_obs_default))
