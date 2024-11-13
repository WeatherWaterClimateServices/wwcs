server <- function(input, output, session) {
  selected_station <- reactiveValues(
    id = unlist(default_station$siteID),
    lat = unlist(default_station$latitude),
    lon = unlist(default_station$longitude),
    type = unlist(default_station$type)
  )
  
  selected_point <-
    reactiveValues(xy = cbind(
      as.numeric(unlist(default_station$longitude)),
      as.numeric(unlist(default_station$latidude))
    ))
  
  # ------------------------------- Leaflet Map
  output$map <- renderLeaflet({
    leaflet(data = station_data,
            options = leafletOptions(minZoom = 6, maxZoom = 17)) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 7) %>%
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
      addLegend(
        position = c("bottomright"),
        raster_colors,
        values = seq(-25, 25, length.out = 12),
        title = "Temperature °C"
      )
  })
  
  
  # ------------------------------- Variable Selection
  
  observeEvent(input$var, {
    icons_ready <- awesomeIcons(
      icon = NULL,
      markerColor =  as.character(colors_marker[input$var]),
      iconColor = "white",
      squareMarker = rep(FALSE, length(rd)),
      text = paste0(round(unlist(station_data[rd, input$var])), "\n", labels[input$var]),
      fontFamily = "Helvetica"
    )
    
    icons_hold <- awesomeIcons(
      icon = NULL,
      markerColor =  as.character(colors_marker[input$var]),
      iconColor = "black",
      squareMarker =  rep(FALSE, length(hd)),
      text = paste0(round(unlist(station_data[hd, input$var])), "\n", labels[input$var]),
      fontFamily = "Helvetica"
    )
    
    icons_hold$squareMarker[tjhm_hd] = T
    icons_ready$squareMarker[tjhm_rd] = T
    
    proxy <- leafletProxy('map')
    proxy %>%
      addAwesomeMarkers(
        lng = station_data$longitude[rd],
        lat = station_data$latitude[rd],
        label = station_data$siteID[rd],
        layerId = station_data$siteID[rd],
        icon = icons_ready,
        labelOptions = labelOptions(
          style = list(
            "color" = "white",
            "font-size" = "14px",
            "background-color" = "#404040",
            "border-color" = "#404040",
            "font-weight" = "bold"
          )
        )
      ) %>%
      addAwesomeMarkers(
        lat = selected_station$lat ,
        lng = selected_station$lon,
        label = selected_station$id,
        layerId = "selid",
        icon = icon_sel,
        labelOptions = labelOptions(
          noHide = T,
          style = list(
            "color" = "white",
            "font-size" = "16px",
            "background-color" = "#404040",
            "border-color" = "#404040",
            "font-weight" = "bold"
          )
        )
      )
    
    if (length(hd) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = station_data$longitude[hd],
          lat = station_data$latitude[hd],
          label = station_data$siteID[hd],
          layerId = station_data$siteID[hd],
          icon = icons_hold,
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
    
    if (length(dw) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = station_data$longitude[dw],
          lat = station_data$latitude[dw],
          label = station_data$siteID[dw],
          layerId = station_data$siteID[dw],
          icon = icons_down,
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
  
  # ------------------------------- Station Selection
  
  observeEvent(input$map_marker_click, {
    click = input$map_marker_click
    selected_station$id = click$id
    selected_station$lat = click$lat
    selected_station$lon = click$lng
    selected_station$type = station_data$type[station_data$siteID == click$id]
    
    
    icons_ready <- awesomeIcons(
      icon = NULL,
      markerColor =  as.character(colors_marker[input$var]),
      iconColor = "white",
      squareMarker = rep(FALSE, length(rd)),
      text = paste0(round(unlist(station_data[rd, input$var])), "\n", labels[input$var]),
      fontFamily = "Helvetica"
    )
    
    icons_hold <- awesomeIcons(
      icon = NULL,
      markerColor =  as.character(colors_marker[input$var]),
      iconColor = "black",
      squareMarker =  rep(FALSE, length(hd)),
      text = paste0(round(unlist(station_data[hd, input$var])), "\n", labels[input$var]),
      fontFamily = "Helvetica"
    )
    
    
    if (selected_station$type == "TJHM") {
      icon_sel <- makeAwesomeIcon(
        #icon = "thermometer",
        iconColor = "#FFFFFF",
        library = "fa",
        squareMarker = TRUE
      )
    } else {
      icon_sel <- makeAwesomeIcon(
        #icon = "thermometer",
        iconColor = "#FFFFFF",
        library = "fa",
        squareMarker = FALSE
      )
    }
    
    icons_hold$squareMarker[tjhm_hd] = T
    icons_ready$squareMarker[tjhm_rd] = T
    
    
    proxy <- leafletProxy('map')
    proxy %>%
      addAwesomeMarkers(
        lng = station_data$longitude[rd],
        lat = station_data$latitude[rd],
        label = station_data$siteID[rd],
        layerId = station_data$siteID[rd],
        icon = icons_ready,
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
    
    if (length(hd) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = station_data$longitude[hd],
          lat = station_data$latitude[hd],
          label = station_data$siteID[hd],
          layerId = station_data$siteID[hd],
          icon = icons_hold,
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
    
    if (length(dw) > 0) {
      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = station_data$longitude[dw],
          lat = station_data$latitude[dw],
          label = station_data$siteID[dw],
          layerId = station_data$siteID[dw],
          icon = icons_down,
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
    
    proxy %>%
      addAwesomeMarkers(
        lat = selected_station$lat ,
        lng = selected_station$lon,
        label = selected_station$id,
        layerId = "selid",
        icon = icon_sel,
        labelOptions = labelOptions(
          noHide = T,
          style = list(
            "color" = "white",
            "font-size" = "16px",
            "background-color" = "#404040",
            "border-color" = "#404040",
            "font-weight" = "bold"
          )
        )
      )
  })
  
  # ------------------------------- Map Selection
  
  observeEvent(input$map_click, {
    click = input$map_click
    selected_point$xy <- cbind(click$lng, click$lat)
    print(selected_point$xy)
  })
  
  
  # ------------------------------- Raster handling
  
  observeEvent(input$admin, {
    if (input$admin) {
      proxy <- leafletProxy('map')
      proxy %>%
        addPolygons(
          layerId = as.character(bd$district),
          label = as.character(bd$district),
          data = bd$geometry,
          fillOpacity = 0,
          color = "black",
          weight = 2
        )
    } else {
      proxy <- leafletProxy('map')
      proxy %>% removeShape(layerId = as.character(bd$district))
    }
  })
  
  observeEvent(input$period_raster, {
    print(input$period_raster)
    timeraster <-
      as.numeric(difftime(input$period_raster, time_range_f$max, units = "hours"))
    
    print(timeraster)
    print(paste0(
      "/srv/shiny-server/dashboard/appdata/gemos_raster/raster_plot_",
      timeraster,
      ".tif"
    ))
    
    if (timeraster < 0) {
      timeraster <- 0
    }
    
    raster_path <- paste0("./appdata/gemos_raster/raster_plot_", timeraster, ".tif")
    
    # Check if the file exists
    if (file.exists(raster_path)) {
      # Load the raster if the file exists
      ifsmap <- raster::raster(raster_path)
      proxy <- leafletProxy('map')
      proxy %>% addRasterImage(
        x = ifsmap,
        layerId = "raster",
        opacity = 0.65,
        colors = raster_colors
      ) %>%
        addPolygons(
          data = mask,
          color = "black",
          fillColor = "white",
          weight = 2
        )
    }
  })
  
  observeEvent(input$raster, {
    if (input$raster) {
        raster_path <- paste0("./appdata/gemos_raster/raster_plot_0.tif")
        
        if (file.exists(raster_path)) {
          proxy <- leafletProxy('map')
          proxy %>%
            addRasterImage(
              x = ifsmap,
              layerId = "raster",
              opacity = 0.65,
              colors = raster_colors
            ) %>%
            addPolygons(
              data = mask,
              color = "black",
              fillColor = "white",
              weight = 2
            )
        }
    } else {
      proxy <- leafletProxy('map')
      proxy %>% clearImages()
    }
  })
  
  # ------------------------------- Language Translation
  
  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
  })
  
  observeEvent(input$selected_language, {
    if (input$selected_language == "en") {
      updateSelectInput(
        session,
        "var",
        choices = c(
          "Temperature" = "Temperature",
          "Relative Humidity" = "RH",
          "Pressure" = "Pressure",
          "Solar" = "Solar",
          "Signal" = "Signal",
          "Battery" = "Battery",
          "Precipitation" = "Precipitation",
          "Evapotranspiration" = "Evapotranspiration"
        )
      )
    } else if (input$selected_language == "ru") {
      updateSelectInput(
        session,
        "var",
        choices = c(
          "Температура" = "Temperature",
          "Относительная влажность" = "RH",
          "Давление" = "Pressure",
          "Солнечный" = "Solar",
          "Сигнал" = "Signal",
          "Аккумулятор" = "Battery",
          "Дождь" = "Precipitation",
          "Эвапотранспирация" = "Evapotranspiration"
        )
      )
    }
  })
  
  
  # ------------------------------- Data Plots
  
  output$meteogram2 <- renderPlotly({
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      plot_meteogram_raster(selected_point$xy)
    })
  })
  
  output$meteogram <- renderPlotly({
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      plot_meteogram_precip(
        emos,
        dmo,
        pictos,
        selected_station$id,
        input$period_f,
        input$ecmwf,
        mobile = shinybrowser::get_all_info()$device == "Mobile"
      )
    })
  })
  
  output$observations <- renderPlotly({
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      plot_observations(obs, selected_station$id, input$period_o, input$var)
    })
  })
  
  # ------------------------------- Value Boxes
  
  output$id <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(station_data$siteID[id]), paste(i18n$t('Station')), color = "teal")
  })
  
  output$alt <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(station_data$altitude[id], " m"),
             paste(i18n$t('Altitude')),
             color = "teal")
  })
  
  output$logger <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(station_data$loggerID[id]), paste(i18n$t('Logger ID')), color = "teal")
  })
  output$sdate <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(as.Date(station_data$startDate[id])), paste(i18n$t('Start Date')), color = "teal")
  })
  output$lat <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(station_data$latitude[id]), paste(i18n$t('Latitude')), color = "teal")
  })
  output$lng <- renderValueBox({
    id <- which(station_data$siteID == selected_station$id)
    valueBox(paste0(station_data$longitude[id]), paste(i18n$t('Longitude')), color = "teal")
  })
  
  # ------------------------------- Login Security
  
  # check_credentials returns a function to authenticate users
  res_auth <- secure_server(check_credentials = check_credentials(credentials))
  
  output$auth_output <- renderPrint({
    reactiveValuesToList(res_auth)
    updateTabItems(session, "sidebar", "overview")
  })
}
