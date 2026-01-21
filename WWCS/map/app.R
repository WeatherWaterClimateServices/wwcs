# Load required libraries
library(shiny)
library(leaflet)
library(httr)
library(jsonlite)
library(RMySQL)
library(DBI)
library(tidyverse)
library(shiny.i18n)
library(lubridate)
library(plotly)
library(shinydashboard)
library(shinymanager)

source('/home/wwcs/wwcs/WWCS/.Rprofile')

# Load the credentials

credentials <- data.frame(
  user = c("caritas", "tjhm", "coes"),
  # mandatory
  password = c(servicepass, servicepass, servicepass),
  # mandatory
  start = c("2019-04-15"),
  # optinal (all others)
  expire = c(NA, NA, NA),
  admin = c(FALSE, FALSE, FALSE),
  comment = "Simple and secure authentification mechanism
  for single ‘Shiny’ applications.",
  stringsAsFactors = FALSE
)

# Load global parameters

# Read administrative areas
bd <- sf::st_read(
  paste0(
    "/home/wwcs/wwcs/WWCS/boundaries/gadm41_",
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

mask <- readRDS("/home/wwcs/wwcs/WWCS/boundaries/mask.rds")

# Load data from database

sites <-
  sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
  distinct(siteID, .keep_all = TRUE)  %>%
  as_tibble() # Do not include soil moisture measurements

deployments <-
  sqlQuery(query = "select * from MachineAtSite", dbname = "Machines") %>%
  as_tibble() # Do not include soil moisture measurements


lastobs <-
  sqlQuery(
    query = "
  SELECT dt.*
  FROM MachineObs dt
  INNER JOIN (
  SELECT loggerID, MAX(timestamp) AS max_timestamp
  FROM MachineObs
  GROUP BY loggerID
  ) dt_max ON dt.loggerID = dt_max.loggerID AND dt.timestamp = dt_max.max_timestamp;"
    ,
    dbname = "Machines"
  ) %>%
  as_tibble()


# Join all elements and create new columns status that checks if timestamp is within the last hour

mapdata <-
  sites %>%
  dplyr::left_join(deployments, by = c("siteID"), multiple = "all") %>%
  dplyr::left_join(lastobs, by = c("loggerID")) %>%
  dplyr::mutate(status = ifelse(
    timestamp > Sys.time() - hours(1),
    "green",
    ifelse(timestamp > Sys.time() - hours(24), "yellow", "red")
  )) %>%
  dplyr::mutate(status = ifelse(is.na(timestamp), "red", status)) %>%
  dplyr::mutate(status = ifelse(is.na(ta) | ta < -100, "red", status)) %>%
  dplyr::mutate(time_diff = ifelse(
    is.na(timestamp),
    NA,
    difftime(Sys.time(), timestamp, units = "hours")
  )) %>%
  dplyr::mutate(time_lastobs = ifelse(time_diff < 24, floor(time_diff), round(time_diff / 24, 0))) %>%
  dplyr::group_by(siteID) %>%
  dplyr::filter(timestamp == max(timestamp)) %>%
  dplyr::ungroup()

# Count total number of stations and number of stations with status green, yellow and red

total <- nrow(mapdata %>% dplyr::filter(type == "WWCS"))
green <- nrow(filter(mapdata, status == "green" & type == "WWCS"))
yellow <- nrow(filter(mapdata, status == "yellow" & type == "WWCS"))
red <- nrow(filter(mapdata, status == "red" & type == "WWCS"))

ready <- which(mapdata$status == "green" & mapdata$type == "WWCS")
hold <- which(mapdata$status == "yellow" & mapdata$type == "WWCS")
late <- which(mapdata$status == "red" & mapdata$type == "WWCS")

ready_hydromet <- which(mapdata$status == "green" & mapdata$type == "TJHM")
hold_hydromet <- which(mapdata$status != "green" & mapdata$type == "TJHM")

bounds <- 5

# Define icons of the map

icons_green <- awesomeIcons(
  markerColor = "green",
  iconColor = "white",
  squareMarker = F,
  icon = NULL,
  text = paste0(round(unlist(mapdata[ready, "ta"])), " \n ", "°C"),
  fontFamily = "Helvetica"
)

icons_hold <- awesomeIcons(
  markerColor = "beige",
  iconColor = "white",
  squareMarker = F,
  icon = NULL,
  text = paste0(round(unlist(mapdata[hold, "ta"])), " \n ", "°C"),
  fontFamily = "Helvetica"
)

icons_late <- awesomeIcons(
  markerColor = "red",
  iconColor = "white",
  squareMarker = F,
  icon = NULL,
  #text = paste0(round(unlist(mapdata[late,"ta"]))," \n ","°C"),
  text = paste0(NA),
  fontFamily = "Helvetica"
)

icons_hydromet_ready <- awesomeIcons(
  markerColor = "blue",
  iconColor = "white",
  squareMarker = F,
  icon = NULL,
  text = paste0(round(unlist(mapdata[ready_hydromet,"ta"])), " \n ", "°C"),
  fontFamily = "Helvetica"
)

icons_hydromet_hold <- awesomeIcons(
  markerColor = "lightblue",
  iconColor = "white",
  squareMarker = F,
  icon = NULL,
  text = paste0(NA),
  fontFamily = "Helvetica"
)

# Function to align element in the center

alignCenter <- function(el) {
  htmltools::tagAppendAttributes(el, style = "margin-left:auto;margin-right:auto;")
}

# Define UI
ui <- fluidPage(
  # Add favicon
  tags$head(
    tags$link(rel = "shortcut icon", href = "dashboard_favicon.ico")
  ),
  shinybrowser::detect(),
  tags$style(type = "text/css", "#map {height: calc(90vh) !important;}; "),
  tags$style(type = 'text/css', '.modal-dialog { width: fit-content !important};'),
  tags$style(
    HTML(
      ".modal-content {
              max-height: calc(100vh); /* Adjust 150px to accommodate header/footer if necessary */
              overflow-y: auto; /* Enable vertical scrolling if content overflows */
            }"
    )
  ),
  tags$head(tags$style(
    HTML(
      "/* Custom CSS styles */
            .awesome-marker i {
	          font-size: 11px !important;
            }"
    )
  )),
  leafletOutput("map"),
  # Add a text output from "status"
  verbatimTextOutput("status")
)

if (exists("use_pass")) {
  # Second layer: existing logic
  if (use_pass == FALSE) {
    ui
  } else {
    ui <- secure_app(ui)
  }
} else {
  ui
}

# Define Server
server <- function(input, output, session) {
  
  # ------------------------------- Login Security
  
  # call the server part
  # check_credentials returns a function to authenticate users
  res_auth <- secure_server(check_credentials = check_credentials(credentials))
  
  output$auth_output <- renderPrint({
    reactiveValuesToList(res_auth)
    updateTabItems(session, "sidebar", "overview")
  })
  
  
  # Initialize reactive values
  
  selected <- reactiveValues(
    id = NA,
    name = NA,
    logger = NA,
    altitude = NA,
    startdate = NA,
    lat = NA,
    lon = NA,
    status = NA,
    lastobs = NA,
    title = NA,
    type = NA
  )
  
  station_data <- reactiveValues(# Get the data for the selected station
    data = sqlQuery(
      query = paste0(
        "select * from MachineObs where loggerID = \"3c:71:bf:e1:4b:9c\" and timestamp >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)"
      ),
      dbname = "Machines"
    ) %>%
      as_data_frame())
  
  
  
  
  # Render the leaflet map
  output$map <- renderLeaflet({
    leaflet("map", data = mapdata,
            options = leafletOptions(minZoom = 6, maxZoom = 17)) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 8) %>%
      setMaxBounds(
        lng1 = setlon - bounds,
        lat1 = setlat - bounds,
        lng2 = setlon + bounds,
        lat2 = setlat + bounds
      ) %>%
      addTiles(group = "Street View") %>%
      addPolygons(
        data = mask,
        color = "black",
        fillColor = "white",
        fillOpacity = 1,
        weight = 2
      ) %>%
      addPolygons(
        layerId = as.character(bd$district),
        label = as.character(bd$district),
        data = bd$geometry,
        fillOpacity = 0,
        color = "black",
        weight = 2
      ) %>%
      addLayersControl(
        position = c("bottomright"),
        overlayGroups = c("WWCS", "WWCS (hold)", "WWCS (down)", "TJHM"),
        options = layersControlOptions(collapsed = TRUE)
      ) 
  })
  
  
  # Update the visibility of markers based on user input
  observe({
    if (length(ready) > 0) {
      proxy <- leafletProxy("map")
      proxy %>%
        addAwesomeMarkers(
          lng = mapdata$longitude[ready],
          lat = mapdata$latitude[ready],
          label = mapdata$siteID[ready],
          layerId = mapdata$siteID[ready],
          icon = icons_green,
          group = "WWCS",
          labelOptions = labelOptions(
            style = list(
              "color" = "white",
              "font-size" = "14px",
              "background-color" = "#404040",
              "border-color" = "#404040",
              "font-weight" = "bold"
            )
          )
        )
    }
    
    if (length(ready_hydromet) > 0) {
      proxy <- leafletProxy("map") 
      proxy %>%
        addAwesomeMarkers(
          lng = mapdata$longitude[ready_hydromet],
          lat = mapdata$latitude[ready_hydromet],
          label = mapdata$siteID[ready_hydromet],
          layerId = mapdata$siteID[ready_hydromet],
          icon = icons_hydromet_ready,
          group = "TJHM",
          labelOptions = labelOptions(
            style = list(
              "color" = "white",
              "font-size" = "14px",
              "background-color" = "#404040",
              "border-color" = "#404040",
              "font-weight" = "bold"
            )
          )
        )
    }
    
    if (length(hold_hydromet) > 0) {
      proxy <- leafletProxy("map") 
      proxy %>%
        addAwesomeMarkers(
          lng = mapdata$longitude[hold_hydromet],
          lat = mapdata$latitude[hold_hydromet],
          label = mapdata$siteID[hold_hydromet],
          layerId = mapdata$siteID[hold_hydromet],
          icon = icons_hydromet_hold,
          group = "TJHM",
          labelOptions = labelOptions(
            style = list(
              "color" = "white",
              "font-size" = "14px",
              "background-color" = "#404040",
              "border-color" = "#404040",
              "font-weight" = "bold"
            )
          )
        )
    }
  })
  
  output$status <- renderText({
    paste0(
      total,
      " WWCS stations - ",
      green,
      " on time stations - ",
      yellow,
      " late stations - ",
      red,
      " very late stations"
    )
  })
  
  
  # Create a reactive value to store the selected siteID
  
  observeEvent(input$range, {
    
    station_data$data <- sqlQuery(
      query = paste0(
        "select * from MachineObs where loggerID = \'",
        selected$logger,
        "\' and timestamp between \'",
        input$range[1],
        "\' and \'",
        input$range[2] + 1,
        "\';"
      ),
      dbname = "Machines"
    ) %>%
      as_data_frame()
    
  })
  
  
  # -------------------------------  Map Marker Click Event
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    selected$name <- mapdata[mapdata$siteID == input$map_marker_click$id, "siteName"]
    selected$logger <- mapdata[mapdata$siteID == input$map_marker_click$id, "loggerID"]
    selected$altitude <- mapdata[mapdata$siteID == input$map_marker_click$id, "altitude"]
    selected$startdate <- mapdata[mapdata$siteID == input$map_marker_click$id, "startDate"]
    selected$lat <- mapdata[mapdata$siteID == input$map_marker_click$id, "latitude"]
    selected$lon <- mapdata[mapdata$siteID == input$map_marker_click$id, "longitude"]
    selected$status <- mapdata[mapdata$siteID == input$map_marker_click$id, "status"]
    selected$lastobs <- mapdata[mapdata$siteID == input$map_marker_click$id, "time_lastobs"]
    selected$type <- mapdata[mapdata$siteID == input$map_marker_click$id, "type"]
    
    if (selected$status == "green") {
      selected$title = paste0(selected$id, " (running)")
    } else if (selected$status == "yellow") {
      selected$title = paste0(selected$id, " (late since ", selected$lastobs, " hours)")
    } else {
      selected$title = paste0(selected$id, " (down since ", selected$lastobs, " days)")
    }
    
    
    station_data$data <- sqlQuery(
      query = paste0(
        "select * from MachineObs where loggerID = \"",
        selected$logger,
        "\" ORDER BY timestamp DESC LIMIT 400"
      ),
      dbname = "Machines"
    ) %>%
      as_data_frame()
    
    print(station_data$data)
    showModal(modalDialog(style = "text-align:center;", tabsetPanel(
      if (any(!is.na(station_data$data$Charge_Battery))) {
        tabPanel(
          "Graph",
          checkboxGroupInput(
            "var",
            label = h3(paste0(selected$title)),
            inline = TRUE,
            choices = list(
              "Temperature" = "ta",
              "Relative Humidity" = "rh",
              "Pressure" = "p",
              "Solar" = "U_Solar",
              "Signal" = "signalStrength",
              "Voltage Battery" = "U_Battery",
              "Box Temperature" = "logger_ta",
              "Box Relative Humidity" = "logger_rh",
              "Charge Battery" = "Charge_Battery",
              "Temperature Battery" = "Temp_Battery",
              "Voltage Battery 1" = "U_Battery1",
              "Compass" = "compass",
              "Lightning Count" = "lightning_count",
              "Lightning Distance" = "lightning_dist",
              "Precipitation" = "pr",
              "Radiation" = "rad",
              "Wind Speed" = "wind_speed",
              "Wind Direction" = "wind_dir",
              "Wind Gust" = "wind_gust",
              "Wind Speed East" = "wind_speed_E",
              "Wind Speed North" = "wind_speed_N",
              "Vapour Pressure" = "vapour_press",
              "Temperature Soil 10 cm" = "ts10cm",
              "Tilt X" = "tilt_x",
              "Tilt Y" = "tilt_y",
              "Temperature Humidity Sensor" = "Temp_Humisens"
            ),
            selected = c("ta")
          ),
          alignCenter(
            dateRangeInput(
              "range",
              "Date range:",
              start = Sys.Date() - lubridate::days(4),
              end = Sys.Date(),
              min = Sys.Date() - lubridate::days(50),
              max = Sys.Date()
            )
          ),
          plotlyOutput("plot", height = "35vh")
        )
      } else if (selected$type == "TJHM") {
        tabPanel(
          "Graph",
          checkboxGroupInput(
            "var",
            label = h3(paste0(selected$title)),
            inline = TRUE,
            choices = list(
              "Temperature" = "ta",
              "Relative Humidity" = "rh",
              "Pressure" = "p",
              "Precipitation" = "pr",
              "Wind Speed" = "wind_speed",
              "Wind Direction" = "wind_dir",
              "Battery" = "U_Battery",
              "Radiation" = "rad"
            ),
            selected = c("ta")
          ),
          alignCenter(
            dateRangeInput(
              "range",
              "Date range:",
              start = Sys.Date() - lubridate::days(4),
              end = Sys.Date(),
              min = Sys.Date() - lubridate::days(50),
              max = Sys.Date()
            )
          ),
          plotlyOutput("plot", height = "35vh")
        )
      } else {
        tabPanel(
          "Graph",
          checkboxGroupInput(
            "var",
            label = h3(paste0(selected$title)),
            inline = TRUE,
            choices = list(
              "Temperature" = "ta",
              "Relative Humidity" = "rh",
              "Pressure" = "p",
              "Solar" = "U_Solar",
              "Signal" = "signalStrength",
              "Battery" = "U_Battery",
              "Box Temperature" = "logger_ta",
              "Box Relative Humidity" = "logger_rh"
            ),
            selected = c("ta")
          ),
          alignCenter(
            dateRangeInput(
              "range",
              "Date range:",
              start = Sys.Date() - lubridate::days(4),
              end = Sys.Date(),
              min = Sys.Date() - lubridate::days(50),
              max = Sys.Date()
            )
          ),
          plotlyOutput("plot", height = "35vh")
        )
      },
      if (shinybrowser::get_all_info()$device == "Desktop") {
        tabPanel(
          "Data",
          br(),
          DT::dataTableOutput("table"),
          br(),
          downloadButton('downloadData', 'Download')
        )
      },
      tabPanel(
        "Metadata",
        valueBoxOutput("id"),
        valueBoxOutput("name"),
        valueBoxOutput("alt"),
        valueBoxOutput("logger"),
        valueBoxOutput("sdate"),
        valueBoxOutput("lat"),
        valueBoxOutput("lng")
      ),
      if (shinybrowser::get_all_info()$device == "Desktop") {
        tabPanel("Maintenance",
                 h3(paste0(selected$title)),
                 plotlyOutput("plot_maintenance", height = "50vh"))
      } else {
        tabPanel(
          "Maintenance",
          h3(paste0(selected$title)),
          plotlyOutput(
            "plot_maintenance",
            height = "50vh",
            width = "100%"
          )
        )
      }
    )))
  })
  
  
  # ------------------------------- Value Boxes
  
  output$id <- renderValueBox({
    valueBox(paste0(selected$id), paste('Station'), color = "teal")
  })
  
  output$name <- renderValueBox({
    valueBox(paste0(selected$name), paste('Location Name'), color = "teal")
  })
  output$alt <- renderValueBox({
    valueBox(paste0(selected$altitude, " m"), paste('Altitude'), color = "teal")
  })
  
  output$logger <- renderValueBox({
    valueBox(paste0(selected$logger), paste('loggerID'), color = "teal")
  })
  
  output$sdate <- renderValueBox({
    valueBox(paste0(selected$startdate), paste('Start Date'), color = "teal")
  })
  
  output$lat <- renderValueBox({
    valueBox(paste0(selected$lat), paste('Latitude'), color = "teal")
  })
  
  output$lng <- renderValueBox({
    valueBox(paste0(selected$lon), paste('Longitude'))
  })
  
  
  # ------------------------------- Plot of observations data
  
  output$plot <- renderPlotly({
    data <- station_data$data
    plot_observations(data, id = selected$id, var = input$var)
  })
  
  output$plot_maintenance <- renderPlotly({
    data <- station_data$data
    print(data)
    plot_maintenance(data,
                     id = selected$id,
                     desktop = shinybrowser::get_all_info()$device == "Desktop")
  })
  
  output$table <- DT::renderDataTable({
    table <- station_data$data  %>%
      dplyr::select(c(1:14)) %>%
      dplyr::select(tidyselect::where(~ sum(!is.na(.x)) > 0))
    
    DT::datatable(table)
  })
  
  
  output$downloadData <- downloadHandler(
    filename = function() {
      paste('data-', Sys.Date(), '.csv', sep = '')
    },
    content = function(file) {
      write.csv(station_data$data, file)
    }
  )
  
  
  # ------------------------------- Add markers and adjust zoom level depending on device
  
  reactive({
    if (shinybrowser::get_all_info()$device == "Desktop") {
      leafletProxy("map") %>%
        setView(lng = setlon,
                lat = setlat,
                zoom = 7) # Zoom level for larger devices
    } 
  })
  
  observe({
    if (length(hold) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = mapdata$longitude[hold],
          lat = mapdata$latitude[hold],
          label = mapdata$siteID[hold],
          layerId = mapdata$siteID[hold],
          icon = icons_hold,
          group = "WWCS (hold)",
          labelOptions = labelOptions(
            style = list(
              "color" = "white",
              "font-size" = "14px",
              "background-color" = "#404040",
              "border-color" = "#404040",
              "font-weight" = "bold"
            )
          )
        )
    }
    
    if (length(late) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = mapdata$longitude[late],
          lat = mapdata$latitude[late],
          label = mapdata$siteID[late],
          layerId = mapdata$siteID[late],
          icon = icons_late,
          group = "WWCS (down)",
          labelOptions = labelOptions(
            style = list(
              "color" = "white",
              "font-size" = "14px",
              "background-color" = "#404040",
              "border-color" = "#404040",
              "font-weight" = "bold"
            )
          )
        )
    }
  })
}

# Run the Shiny app
shinyApp(ui, server)
