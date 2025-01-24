server <- function(input, output, session) {
  
  
  selected <- reactiveValues(id = harvest_default_station)
  rain <- reactiveValues(past = FALSE, future = FALSE, status = FALSE)
  

  
  # ------------------------------- Leaflet Map
  
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 7, maxZoom = 17)) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 8)  %>%
      addTiles(group = i18n$t("Street View")) %>%
      addProviderTiles("Esri.WorldImagery", group = i18n$t("Satellite")) %>%
      addLayersControl(
        baseGroups = c(i18n$t("Satellite"),i18n$t("Street View")),
        options = layersControlOptions(collapsed = FALSE)) %>%
      addPolygons(data = mask, color = "black", fillColor = "white", fillOpacity = 1, weight = 2) %>%
      addAwesomeMarkers(
        lng = sites$longitude,
        lat = sites$latitude,
        label = sites$siteID,
        layerId = sites$siteID,
        labelOptions = labelOptions(style = list(
          "color" = "white",
          "font-size" = "14px",
          "background-color" = "#404040",
          "border-color" = "#404040",
          "font-weight" = "bold"
        ))) %>%
      addLegend(position = c("bottomright"), raster_colors, values = seq(-25,25, length.out = 12), title = "Precipitation [mm / 6 hour]")
  })
  
  # ------------------------------- Language Translation
  
  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
    
  })
  
  # ------------------------------- Station Data
  
  observeEvent(input$map_marker_click, {
    click = input$map_marker_click
    selected$id = click$id
  })

  output$plot_rain <- renderPlotly({
    plot_meteogram_precip(selected$id, input$rangestat, input$reftime)
  })
  
  output$plot_frost <- renderPlotly({
    plot_frost(selected$id)
  })
  
  
  # ------------------------------- Satellite Image
  
  
  observeEvent(input$range, {

      date_map <- as.Date(input$range)
      hour_map <- lubridate::hour(input$range)
      
      raster_file <- paste0("/srv/shiny-server/harvest/appdata/noaa_raster/raster_", date_map, "-", hour_map,".tif")
      if (file.exists(raster_file)) {
        noaamap <- raster::raster(raster_file)
        
        proxy <- leafletProxy('map')
        proxy %>%
          addRasterImage(x = noaamap, layerId = "raster", opacity = 0.65, colors = raster_colors) %>%
          addPolygons(data = mask, color = "black", fillColor = "white", weight = 2)
      }
  })
  
  # ------------------------------- Value Boxes
  

  output$future_rain <- renderValueBox({
    future <- dmo %>% 
                 dplyr::filter(as.Date(reftime) == input$reftime & siteID == selected$id, lead <= 120) %>%
                 dplyr::summarize(rain = sum(IFS_PR_mea)) 
    
    
    if (nrow(future) == 0) {
      text <- paste0("No forecast data available for ", selected$id, "")
      color <- "red"
      rain$future = FALSE
    } else {
      condition <- future$rain > future_rain_thrs
      
      if (!condition) {
        text <- paste0("No significant rain expected in the next ",
                       future_rain_days,
                       " days")
        color <- "yellow"
        rain$future = FALSE
        
      } else {
        text <- paste0("Rain expected in the next ", future_rain_days, " days")
        color <- "blue"
        rain$future = TRUE
        
      }
    }
                 
    valueBox("Future rain",
             text, 
             color = color
             )
  })
  
  output$past_rain <- renderValueBox({
    
    past <- obs %>% 
      dplyr::filter(time >= seldate - days(past_rain_days) & siteID == selected$id) %>%
      dplyr::summarize(rain = sum(Precipitation)) 
    
    if (nrow(past) == 0) {
      text <- paste0("Station ", selected$id, " has no data available in the last " , past_rain_days, " days")
      color <- "red"
      rain$past = TRUE
    } else {
      condition <- past$rain > past_rain_thrs
      
      if (!condition) {
        text <- paste0("No rain has fallen in the last ",
                       past_rain_days,
                       " days")
        color <- "yellow"
        rain$past = FALSE
      } else {
        text <- paste0("Rain has fallen in the last ",
                       past_rain_days,
                       " days")
        color <- "blue"
        rain$past = TRUE
      }
    }
    
    valueBox("Past rain",
             text, 
             color = color,
             width = "12cm"
    )
  })
  
  
  output$frost <- renderValueBox({
    # check if any level is not "green"
    
    levels <- ews_station %>%
      dplyr::filter(siteID == selected$id) %>%
      dplyr::mutate(level = .data[["Cold2"]]) %>%
      dplyr::select(level) %>%
      na.omit() %>%
      dplyr::distinct()
    
    print(levels)
    
    if (nrow(levels) == 0) {
      text <- paste0("Station ", selected$id, " has no frost information aivalable")
      color <- "red"
      status = "No forecast" 
      
    } else {
      if (nrow(levels) == 1) {
        if (levels$level == "green") {
          status = "No Frost"
          text <- "No frost expected in the next days"
          color <- "green"
        } else {
          status = "Frost"
          text <- "Frost exptect in the next days"
          color <- "blue"
        }
      } else {
        status = "Frost"
        text <- "Frost exptect in the next days"
        color <- "blue"
      }
    }
    
    valueBox(status,
             text, 
             color = color)
  })
  
  output$status <- renderValueBox({
   
    if (rain$past == FALSE & rain$future == FALSE) {
      status = "Ready"
      text <- "Good timing for harvesting potatos"
      color <- "green"
    } else {
      status = "Not ready"
      text <- "Bad timing for harvesting potatos"
      color <- "red"
    }
    valueBox(status,
             text, 
             color = color)
  })
  
  # Ensure that always the whole station range is displayed
  
  observe({
    # Check if rangestat is greater than reftime
    if (input$rangestat > input$reftime) {
      # Update rangestat to reftime if the condition is met
      updateSliderInput(session, "rangestat", value = input$reftime)
    }
  })
}
