library(shiny)
library(leaflet)
library(httr)
library(jsonlite)
library(RMySQL)
library(tidyverse)
library(shiny.i18n)
library(lubridate)

# PREPARE GLOBAL PARAMETERS
# ------------------------------------------------

source('/opt/shiny-server/WWCS/.Rprofile')
mask <- readRDS("/opt/shiny-server/WWCS/boundaries/mask.rds")

# Read administrative areas
bd <- sf::st_read(paste0("/opt/shiny-server/WWCS/boundaries/gadm41_", gadm0, "_2.shp"), as_tibble = TRUE) %>%
  dplyr::rename(district = NAME_2) %>%
  dplyr::select(c(district, geometry))

if (gadm0 == "TJK") {
  bd$district[14] = "Rudaki2"  
}

# PREPARE UI
# ------------------------------------------------

ui <- fluidPage(
  tags$style(type = "text/css", "#map {height: calc(60vh) !important;}; "),
  column(width = 7,
         titlePanel("Weather, Water, and Climate Service Data Retrieval"),
         h4("Select a point on the map"),
         leafletOutput("map"),
         textOutput("lat"),
         textOutput("lng"),
         selectInput("selected_api", label = "Select Service", choices = c("Weather Forecast Station", "Weather Forecast Map", 
                                                                           "Station Observation", "Early Warning", "Irrigation Advice",
                                                                           "Planting Advice", "Harvest Advice"), selected = "Weather Forecast Station"),
         dateInput("selected_date", label = "Select a date", value = Sys.Date() - days(1))
  ),
  column(width = 5,
         titlePanel("API Data"),
         h4("API GET Request"),
         mainPanel(width = 12,
                   verbatimTextOutput("api_request")
         ), 
         h4("API Response"),
         mainPanel(width = 12,
                   verbatimTextOutput("api_response")
         )
  )
)

# PREPARE SERVER
# ------------------------------------------------

server <- function(input, output, session) {
  
  # Initialize reactive values
  
  rv <- reactiveValues(
    clickLat = setlat,
    clickLng = setlon
  )
  
  selected <- reactiveValues(id = "TOJ004", 
                             name = "TOJ004")
  
  request <- reactiveValues(url = NULL)
  
  sites <- reactive({ 
    input$selected_api
    
    if (input$selected_api == "Weather Forecast Station") {
      sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
        dplyr::filter(forecast == 1)
    } else if (input$selected_api == "Weather Forecast Map") {
      sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
        dplyr::filter(forecast == 1)
      } else if (input$selected_api == "Station Observation") {
        sqlQuery(query = "select * from Sites", dbname = "SitesHumans")
    } else if (input$selected_api == "Early Warning") {
      sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
        dplyr::filter(coldwave == 1)
    } else if (input$selected_api == "Irrigation Advice") {
      sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
        dplyr::filter(irrigation == 1)
    } else if (input$selected_api == "Planting Advice") {
      sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
        dplyr::filter(planting == 1)
    } else if (input$selected_api == "Harvest Advice") {
        sqlQuery(query = "select * from Sites", dbname = "SitesHumans") %>%
          dplyr::filter(harvest == 1)
    }
  })

  # Render the leaflet map
  output$map <- renderLeaflet({
    leaflet(data = sites(), options = leafletOptions(minZoom = 7, maxZoom = 17)) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 7) %>%
      addTiles(group = "Street View") %>%
      addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
      addLayersControl(
        baseGroups = c("Satellite","Street View"),
        options = layersControlOptions(collapsed = FALSE)) %>%
      addPolygons(data = mask, color = "black", fillColor = "white", fillOpacity = 1, weight = 2) %>%
      addPolygons(layerId = as.character(bd$district), label = as.character(bd$district), data = bd$geometry, fillOpacity = 0, color = "black", weight = 2) %>%
      addAwesomeMarkers(
        lng = ~longitude,
        lat = ~latitude,
        label = ~siteID,
        layerId = ~siteID,
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
  })
  
  # Update the reactive values when a point is clicked on the map
  observeEvent(input$map_click, {
    click <- input$map_click
    rv$clickLat <- click$lat
    rv$clickLng <- click$lng
  })
  
  # Display the latitude and longitude values
  output$lat <- renderText({
    paste("Latitude: ", rv$clickLat)
  })
  output$lng <- renderText({
    paste("Longitude: ", rv$clickLng)
  })
  
  output$siteid <- renderText({
    paste("SiteID: ", selected$id)
  })
  
  # Create a reactive value to store the selected siteID
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    selected$name <- input$map_marker_click$id
  })
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    selected$name <- input$map_marker_click$id
  })
  
  observeEvent(input$map_shape_click, {
    selected$name <- input$map_shape_click$id
  })
  
  # Display the API request
  
  output$api_request <- renderText({
    if (input$selected_api == "Weather Forecast Station") {
      request$url <- paste("https://wwcs.tj/services/forecast6h?stationID=", selected$id, "&date=", input$selected_date, sep = "")
    } else if (input$selected_api == "Weather Forecast Map") {
      request$url <- paste("https://wwcs.tj/services/map?lat=", rv$clickLat, "&lon=", rv$clickLng, sep = "")
    } else if (input$selected_api == "Station Observation") {
      request$url <- paste("https://wwcs.tj/observations?stationID=", selected$id, sep = "")
    } else if (input$selected_api == "Early Warning") {
      request$url <- paste("https://wwcs.tj/services/warning?Name=", selected$name, "&date=", input$selected_date, "&type=heat", sep = "")
    } else if (input$selected_api == "Irrigation Advice") {
      request$url <- paste("https://wwcs.tj/services/irrigationNeed?siteID=", selected$id, "&date=", input$selected_date, sep = "")
    } else if (input$selected_api == "Planting Advice") {
      request$url <- paste("https://wwcs.tj/services/planting?stationID=", selected$id, "&date=", input$selected_date, sep = "")
    } else if (input$selected_api == "Harvest Advice") {
      request$url <- paste("https://wwcs.tj/services/harvest?stationID=", selected$id, "&date=", input$selected_date, sep = "")
    }

    print(request$url)
  })

  
  # Display the API data
  output$api_response <- renderPrint({
  
    response <- GET(request$url)

    if (http_status(response)$category == "Success") {
        data <- content(response, "text")
    } else {
        data <- print("Unable to retrieve data from the selected API.")
    }
    
    if (!is.null(data)) {
      pretty_json <- toJSON(fromJSON(data), pretty = TRUE)
      cat(pretty_json)
    } else {
      cat("Unable to retrieve data from the selected API.")
    }
  })
}

# Run the Shiny app
shinyApp(ui, server)
