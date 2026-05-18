# Load historical ANAM data through WIS2 box API 
# Documentation https://docs.wis2box.wis.wmo.int/en/1.2.0/reference/data-access/r-api.html

library(RMySQL)
library(DBI)
library(httr)
library(jsonlite)
library(dplyr)
library(tidyr)

source('/home/wwcs/wwcs/WWCS/.Rprofile')

## READ stations from DB - type WMO
sites <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  dplyr::distinct(siteID, .keep_all = TRUE)  %>%
  dplyr::filter(type == "WMO") %>% 
  as_tibble() 

deployments <-
  sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
  dplyr::distinct(siteID, .keep_all = TRUE) %>%  
  as_tibble() 

sites <- left_join(sites, deployments)

## Definitions
# Time window (ISO 8601 UTC). Set either bound to NULL for open-ended.
DATETIME_FROM <- format(Sys.time() - 3 * 24 * 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
DATETIME_TO   <- NULL

OBS_VARS_TO_KEEP <- c("air_temperature", "relative_humidity", "wind_speed", "wind_direction", 
  "total_precipitation_or_total_water_equivalent", "non_coordinate_pressure")

## tchad
base_url <- wis2wmo_url ## from config.yaml
collection <- wis2wmo_collection ## from config.yaml
items_url <- paste0(base_url, "/collections/", collection, "/items")

LIMIT <- 10000
BATCH_SIZE <-  1000
# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b

safe_get <- function(url, query = list(), max_tries = 3, pause = 5) {
  for (attempt in seq_len(max_tries)) {
    resp <- tryCatch(
      httr::GET(url, query = query, httr::timeout(60)),
      error = function(e) NULL
    )
    if (!is.null(resp) && httr::status_code(resp) == 200) return(resp)
    message(sprintf("  Attempt %d failed (%s) — retrying in %ds...",
                    attempt,
                    if (!is.null(resp)) httr::status_code(resp) else "no response",
                    pause))
    Sys.sleep(pause)
  }
  stop(sprintf("Failed to GET %s after %d attempts", url, max_tries))
}

# Helper to ensure connection is valid, reconnect if needed
connect_db <- function(){
  con <- dbConnect(
    RMySQL::MySQL(),
    host     = "localhost",  
    dbname   = "Machines",
    user     = "wwcs",
    password = db_password
  )  
  return(con)
}

## try to specify timerange for download
datetime_param <- NULL
if (!is.null(DATETIME_FROM) || !is.null(DATETIME_TO)) {
  from <- DATETIME_FROM %||% ".."
  to   <- DATETIME_TO   %||% ".."
  datetime_param <- paste0(from, "/", to)
}

## loop over stations, get data
for (station_id in sites$loggerID){
  cat("\nFetching station", station_id, "\n")
     
  all_features <- data.frame()  
  offset <- 0
  repeat {     
    query <- list(f = "json", wigos_station_identifier = station_id,
              limit = LIMIT, offset = offset)
    if (!is.null(datetime_param)) query$datetime <- datetime_param
    res <- safe_get(items_url, query)
       
    if (!is.null(res) && status_code(res) == 200) {
      data <- jsonlite::fromJSON(httr::content(res, as="text", encoding = "UTF-8"))
      success <- TRUE      
    }
    
    if (!success) {
      if (length(all_features) > 0) {
        cat(" Partial data retrieved. Stopping.\n")
        break
      } else {
        cat(" No data retrieved.\n")
        break
      }
    }
    
    features <- data$features     
    if (length(features) == 0) {
      cat(" No features available in last download. Stopping.\n")
      break
    }
    
    all_features <- dplyr::bind_rows(all_features, features)
    
    cat("Retrieved", nrow(all_features), "records...\n")
    
    if (nrow(features) < LIMIT) { ## this would be the last chunk
      break
    }    
    offset <- offset + LIMIT
    Sys.sleep(1)
  } ## end repeat loop - downloading data for station_id in chunks  
  
  ## extract data and prepare/filter/clean, first in long table format
  df_long <- all_features$properties %>% tibble() %>%
    mutate(siteID = wigos_station_identifier,
          time = as.POSIXct(sub(".*/", "", phenomenonTime),
                                    format="%Y-%m-%dT%H:%M:%SZ", tz="UTC")        
        )

  ## filter for required parameters
  if (!is.null(OBS_VARS_TO_KEEP)) {
    df_long <- df_long[df_long$name %in% OBS_VARS_TO_KEEP, ]
    message(sprintf("After variable filter: %d rows", nrow(df_long)))
  }  

  ## pivoting to wide format
  df_wide <- df_long %>%
    select(siteID, time, name, value) %>%
    # Keep first value if there are duplicates for the same report × variable
    group_by(siteID, time, name) %>%
    slice(1) %>%
    ungroup() %>%
    pivot_wider(
      id_cols     = c(siteID, time),
      names_from  = name,
      values_from = value
    )

  ## rename to match with DB (siteID becomes loggerID)
  renames <- c(ta="air_temperature",
      rh="relative_humidity", p="non_coordinate_pressure",
      pr="total_precipitation_or_total_water_equivalent", 
      wind_dir="wind_direction", loggerID="siteID")
  df_wide <- df_wide %>%
    rename(any_of(renames)) %>%
    mutate(received = Sys.time(),
      timestamp=lubridate::with_tz(as.POSIXct(time, tz = "UTC"), tz = timezone_country))
    
  # Validate columns against DB table and keep only jointly common cols
  con <- connect_db()
  db_cols <- dbListFields(con, "MachineObs")
  DBI::dbDisconnect(con)
  df_cols <- colnames(df_wide)
  rownames(df_wide) <- NULL
  df_wide <- df_wide[, intersect(db_cols, df_cols)]
  
  ## now insert into DB
  n_rows    <- nrow(df_wide)
  n_batches <- ceiling(n_rows / BATCH_SIZE)
  message(sprintf("\nInserting %d rows in %d batches...", n_rows, n_batches))
  for (i in seq_len(n_batches)) { 
    start_row <- (i - 1) * BATCH_SIZE + 1
    end_row   <- min(i * BATCH_SIZE, n_rows)
    print(c(start_row, end_row))
    batch     <- df_wide[start_row:end_row, ] 
    ## remove existing records
    existing <- sqlQuery(query = sprintf("SELECT loggerID, timestamp FROM MachineObs WHERE loggerID = '%s'", station_id),
        dbname = "Machines") %>%
      mutate(timestamp = as.POSIXct(timestamp, tz=timezone_country))
    batch <- anti_join(batch, existing, by = c("loggerID", "timestamp"))

    ## write to DB
    tryCatch({ 
      con <- connect_db()
      dbWriteTable(con, name = "MachineObs", value = batch,
                  append = TRUE, row.names = FALSE, overwrite = FALSE)
      dbDisconnect(con)
      message(sprintf("  Batch %d/%d inserted (rows %d-%d of download; records inserted w/o duplicates: %d)", 
      i, n_batches, start_row, end_row, nrow(batch)))      
    }, error = function(e) {
      message(sprintf("  ERROR on batch %d: %s", i, conditionMessage(e)))
      stop(e)
    })
  }
}  ## end loop over stations