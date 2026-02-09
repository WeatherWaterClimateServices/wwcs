server <- function(input, output, session) {
  selected <- reactiveValues(id = planting_default_station)
  
  district <- reactiveValues(id = "Muminobod")
  
  
  # ------------------------------- Leaflet Map
  
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 7, maxZoom = 17)) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 8)  %>%
      addTiles(group = i18n$t("Street View")) %>%
      addProviderTiles("Esri.WorldImagery", group = i18n$t("Satellite")) %>%
      addLayersControl(baseGroups = c(i18n$t("Satellite"), i18n$t("Street View")),
                       options = layersControlOptions(collapsed = FALSE)) %>%
      addPolygons(
        data = mask,
        color = "black",
        fillColor = "white",
        fillOpacity = 1,
        weight = 2
      ) %>%
      addAwesomeMarkers(
        lng = sites$longitude,
        lat = sites$latitude,
        label = sites$siteID,
        layerId = sites$siteID,
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
  
  # ------------------------------- Language Translation
  
  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
    
  })
  
  # ------------------------------- Plot Soil Data
  
  
  output$plot_soil <- renderPlotly({
    tmpdist <- district$id
    thrs <- criteria %>%
      dplyr::filter(district == tmpdist &
                      Croptype == input$croptype)
    plot_soil_temperature(
      soildata,
      selected$id,
      thrs$Threshold_low,
      thrs$Threshold_high,
      input$period,
      input$range
    )
    
  })
  
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    
    district$id <- sites %>%
      dplyr::filter(siteID == input$map_marker_click$id) %>%
      dplyr::select(district) %>%
      unlist()
  })
  
  
  # ------------------------------- Plant Advice
  
  output$status_plant <- renderValueBox({
    
    tmpdist <- district$id
    thrs <- criteria %>%
      dplyr::filter(district == tmpdist &
                    Croptype == input$croptype)
    
   
    
    last_temp <- soildata %>%
      dplyr::filter(siteID == selected$id  & day >= Sys.Date() - lubridate::days(1)) %>%
      dplyr::select(Temperature) %>%
        tail(., 2)
    
    if (is.na(last_temp$Temperature[1])) {
      status <- "Unknown"
      color <- "red"
    } else {
      if (last_temp$Temperature[1] >= thrs$Threshold_low &
          last_temp$Temperature[1] <= thrs$Threshold_high) {
        status <- "Ready"
        color <- "green"
      } else {
        status <- i18n$t("Not ready")
        color <- "red"
      }
    }
    
    valueBox(value = tags$p(status, style = "font-size: 75%;"),
             paste(Sys.Date() - lubridate::days(1)), color = color)
  })
  
  output$criteria_plant <- renderValueBox({
    tmpdist <- district$id
    thrs <- criteria %>%
      dplyr::filter(district == tmpdist &
                      Croptype == input$croptype)
    
    valueBox(
      value = tags$p(i18n$t("Criteria"), style = "font-size: 75%;"),
      paste0(
        i18n$t("Soil temperatures between "),
        thrs$Threshold_low,
        " - ",
        thrs$Threshold_high,
        " °C"
      ),
      color = "blue",
      width = "12cm"
    )
  })
  
  output$criteria2_plant <- renderValueBox({
    tmpdist <- district$id
    thrs <- criteria %>%
      dplyr::filter(district == tmpdist &
                      Croptype == input$croptype)
    
    valueBox(
      value = tags$p(i18n$t("Window"), style = "font-size: 75%;"),
      paste0(
        i18n$t("Expected planting period between "),
        thrs$Window_low ,
        " and ",
        thrs$Window_high,
        " "
      ),
      color = "blue",
      width = "12cm"
    )
  })
  
}
