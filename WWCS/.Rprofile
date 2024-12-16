# Read configuration from text file

config <- yaml::yaml.load_file("/opt/shiny-server/WWCS/config.yaml")
dotenv::load_dot_env("/opt/shiny-server/WWCS/.env")
db_password = Sys.getenv("PASSWORD")
wwcs_domain = config$wwcs_domain

minlat = config$minlat
maxlat = config$maxlat
minlon = config$minlon
maxlon = config$maxlon

setlon = config$setlon
setlat = config$setlat

gadm0 = config$gadm0

timezone_country = config$timezone_country

dashboard_default_station = config$dashboard_default_station

# Parameters for the EMOS model
train_period = config$train_period
forecast_days = config$forecast_days
miss_val = config$miss_val
emos_formula = config$emos_formula

resolution_gEMOS = config$resolution_gEMOS
gemos_formula = config$gemos_formula

# Parameters for the early warning service

spatial_threshold = config$spatial_threshold
warning_days = config$warning_days
warning_default_station = config$warning_default_station

# Irrigation parameters

irrigation_default_station = config$irrigation_default_station
servicepass = config$servicepass

# Planting parameters

planting_default_station = config$planting_default_station
soil_fcst_days = config$soil_fcst_days
proxy_formula = config$proxy_formula
lag3 = config$lag3
lag2 = config$lag2
lag1 = config$lag1

# Harvest parameters

harvest_default_station = config$harvest_default_station
past_rain_thrs = config$past_rain_thrs
future_rain_thrs = config$future_rain_thrs
past_rain_days = config$past_rain_days
future_rain_days = config$future_rain_days

# Function to query MySQL database

sqlQuery <- function(query, dbname) {
    # creating DB connection object with RMySQL package
    DB <-
      DBI::dbConnect(
        MySQL(),
        user = "wwcs",
        password = db_password,
        dbname = dbname,
        host = 'localhost'
      )
    
    # close db connection after function call exits
    on.exit(DBI::dbDisconnect(DB))
    
    # send Query to btain result set
    rs <- DBI::dbSendQuery(DB, query)
    
    # get elements from result sets and convert to dataframe
    result <- DBI::dbFetch(rs, n = -1)
    
    DBI::dbClearResult(rs)
    
    # return the dataframe
    return(result)
}

# Function to calculate ET0

calc_et0 <- function(et0_input) {
    dr <- 1 + 0.033 * cos((2 * 3.14 / 365) * et0_input$DOY)
    d <- 0.409 * sin(((2 * 3.14 / 365) * et0_input$DOY) - 1.39)
    ws <- acos(-tan(et0_input$lat) * tan(d))
    SinphiSind <- ws * sin(et0_input$lat) * sin(d)
    CosphiCosdCosw <- cos(et0_input$lat) * cos(d) * sin(ws)
    Term2 <- dr * (SinphiSind + CosphiCosdCosw)
    Term1 <- 0.082 * Term2
    Rs <- ((24 * 60) / 3.14) * Term1
    out <-
      data.frame("time" = et0_input$date,
                 "Evapotranspiration" = 0.0023 * ((et0_input$Tmax + et0_input$Tmin) / 2) *
                   ((et0_input$Tmax - et0_input$Tmin) ^ 0.5) * Rs)
    out$Evapotranspiration[out$Evapotranspiration < 0] = 0
    return(out)
}

division <- function(x, y) {
  x / y
}
