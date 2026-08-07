server <- function(input, output, session) {

  # Read default_station once at session start (sql_rv already populated)
  default_station <- isolate(sql_rv())$default_station

  selected_station <- reactiveValues(
    id   = unlist(default_station$siteID),
    lat  = unlist(default_station$latitude),
    lon  = unlist(default_station$longitude),
    type = unlist(default_station$type)
  )

  selected_point <- reactiveValues(
    xy = cbind(
      as.numeric(unlist(default_station$longitude)),
      as.numeric(unlist(default_station$latitude))
    )
  )

  # Per-session reactive: join obs with sql sites/deployments
  obs_joined <- reactive({
    obs <- obs_rv()
    sql <- sql_rv()
    sites_not_in_obs <- sql$sites %>%
      dplyr::filter(!siteID %in% obs$siteID) %>%
      dplyr::select(siteID, latitude, longitude, altitude) %>%
      dplyr::left_join(sql$deployments, by = "siteID")
    if (nrow(obs) > 1) dplyr::full_join(obs, sites_not_in_obs) else sites_not_in_obs
  })

  # Per-session reactive: derive station classification from joined obs + emos
  station_derived <- reactive({
    obs          <- obs_joined()
    station_emos <- {
      emos <- daily_rv()$emos
      if ("siteID" %in% colnames(emos)) dplyr::distinct(emos, siteID) else data.frame()
    }

    if ("Temperature" %in% colnames(obs)) {
      last_obs <- obs %>%
        dplyr::group_by(siteID) %>%
        dplyr::filter(!is.na(Temperature)) %>%
        dplyr::summarize(last_obs = dplyr::last(Temperature), .groups = "drop")

      station_down <- obs %>%
        dplyr::group_by(siteID) %>%
        dplyr::arrange(time) %>%
        dplyr::summarize(
          last_time = dplyr::last(time),
          last_obs  = dplyr::last(Temperature)
        ) %>%
        dplyr::filter(last_time < (Sys.Date() - lubridate::days(1)) | is.na(last_obs))
    } else {
      last_obs     <- obs %>% dplyr::distinct(siteID) %>% dplyr::mutate(last_obs = NA)
      station_down <- last_obs %>% dplyr::mutate(last_time = Sys.Date() - lubridate::days(1))
    }

    station_data <- if ("type" %in% colnames(obs)) {
      obs %>%
        dplyr::group_by(siteID) %>%
        dplyr::filter(dplyr::row_number() == dplyr::n()) %>%
        dplyr::mutate(type = ifelse(is.na(type), "WWCS", type))
    } else {
      obs %>%
        dplyr::group_by(siteID) %>%
        dplyr::filter(dplyr::row_number() == dplyr::n())
    }

    rd      <- which(station_data$siteID %in% station_emos$siteID)
    hd      <- which(!station_data$siteID %in% station_emos$siteID &
                     !station_data$siteID %in% station_down$siteID)
    dw      <- which(station_data$siteID %in% station_down$siteID)
    tjhm_hd <- which(station_data$type[hd] == "TJHM")
    tjhm_rd <- which(station_data$type[rd] == "TJHM")

    list(
      station_data = station_data, station_emos = station_emos,
      last_obs = last_obs, station_down = station_down,
      rd = rd, hd = hd, dw = dw, tjhm_hd = tjhm_hd, tjhm_rd = tjhm_rd
    )
  })

  # ------------------------------- Leaflet Map

  output$map <- renderLeaflet({
    sd <- isolate(station_derived())
    leaflet(data = sd$station_data,
            options = leafletOptions(minZoom = 6, maxZoom = 17)) %>%
      setView(lng = setlon, lat = setlat, zoom = 7) %>%
      addTiles(group = i18n$t("Street View")) %>%
      addProviderTiles("Esri.WorldImagery", group = i18n$t("Satellite")) %>%
      addLayersControl(
        baseGroups = c(i18n$t("Satellite"), i18n$t("Street View")),
        options = layersControlOptions(collapsed = FALSE)
      ) %>%
      addPolygons(
        data        = mask,
        color       = "black",
        fillColor   = "white",
        fillOpacity = 1,
        weight      = 2
      ) %>%
      addLegend(
        position = c("bottomright"),
        raster_colors,
        values = seq(-25, 25, length.out = 12),
        title  = "Temperature °C"
      )
  })


  # ------------------------------- Variable Selection

  observeEvent(input$var, {
    sd           <- isolate(station_derived())
    station_data <- sd$station_data
    rd           <- sd$rd; hd <- sd$hd; dw <- sd$dw
    tjhm_hd      <- sd$tjhm_hd; tjhm_rd <- sd$tjhm_rd

    icons_ready <- awesomeIcons(
      icon         = NULL,
      markerColor  = as.character(colors_marker[input$var]),
      iconColor    = "white",
      squareMarker = rep(FALSE, length(rd)),
      text         = paste0(round(unlist(station_data[rd, input$var])), "\n", labels[input$var]),
      fontFamily   = "Helvetica"
    )

    icons_hold <- awesomeIcons(
      icon         = NULL,
      markerColor  = as.character(colors_marker[input$var]),
      iconColor    = "black",
      squareMarker = rep(FALSE, length(hd)),
      text         = paste0(round(unlist(station_data[hd, input$var])), "\n", labels[input$var]),
      fontFamily   = "Helvetica"
    )

    icons_hold$squareMarker[tjhm_hd] <- TRUE
    icons_ready$squareMarker[tjhm_rd] <- TRUE

    proxy <- leafletProxy("map")
    proxy %>%
      addAwesomeMarkers(
        lng         = station_data$longitude[rd],
        lat         = station_data$latitude[rd],
        label       = station_data$siteID[rd],
        layerId     = station_data$siteID[rd],
        icon        = icons_ready,
        labelOptions = labelOptions(style = list(
          "color" = "white", "font-size" = "14px",
          "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
        ))
      ) %>%
      addAwesomeMarkers(
        lat         = selected_station$lat,
        lng         = selected_station$lon,
        label       = selected_station$id,
        layerId     = "selid",
        icon        = icon_sel,
        labelOptions = labelOptions(noHide = TRUE, style = list(
          "color" = "white", "font-size" = "16px",
          "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
        ))
      )

    if (length(hd) > 0) {
      leafletProxy("map") %>%
        addAwesomeMarkers(
          lng         = station_data$longitude[hd],
          lat         = station_data$latitude[hd],
          label       = station_data$siteID[hd],
          layerId     = station_data$siteID[hd],
          icon        = icons_hold,
          labelOptions = labelOptions(style = list(
            "color" = "white", "font-size" = "14px",
            "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
          ))
        )
    }

    if (length(dw) > 0) {
      leafletProxy("map") %>%
        addAwesomeMarkers(
          lng         = station_data$longitude[dw],
          lat         = station_data$latitude[dw],
          label       = station_data$siteID[dw],
          layerId     = station_data$siteID[dw],
          icon        = icons_down,
          labelOptions = labelOptions(style = list(
            "color" = "white", "font-size" = "14px",
            "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
          ))
        )
    }
  })


  # ------------------------------- Station Selection

  observeEvent(input$map_marker_click, {
    click        <- input$map_marker_click
    sd           <- isolate(station_derived())
    station_data <- sd$station_data
    rd           <- sd$rd; hd <- sd$hd; dw <- sd$dw
    tjhm_hd      <- sd$tjhm_hd; tjhm_rd <- sd$tjhm_rd

    selected_station$id   <- click$id
    selected_station$lat  <- click$lat
    selected_station$lon  <- click$lng
    selected_station$type <- station_data$type[station_data$siteID == click$id]

    icons_ready <- awesomeIcons(
      icon         = NULL,
      markerColor  = as.character(colors_marker[input$var]),
      iconColor    = "white",
      squareMarker = rep(FALSE, length(rd)),
      text         = paste0(round(unlist(station_data[rd, input$var])), "\n", labels[input$var]),
      fontFamily   = "Helvetica"
    )

    icons_hold <- awesomeIcons(
      icon         = NULL,
      markerColor  = as.character(colors_marker[input$var]),
      iconColor    = "black",
      squareMarker = rep(FALSE, length(hd)),
      text         = paste0(round(unlist(station_data[hd, input$var])), "\n", labels[input$var]),
      fontFamily   = "Helvetica"
    )

    if (selected_station$type == "TJHM") {
      icon_sel <- makeAwesomeIcon(iconColor = "#FFFFFF", library = "fa", squareMarker = TRUE)
    } else {
      icon_sel <- makeAwesomeIcon(iconColor = "#FFFFFF", library = "fa", squareMarker = FALSE)
    }

    icons_hold$squareMarker[tjhm_hd] <- TRUE
    icons_ready$squareMarker[tjhm_rd] <- TRUE

    proxy <- leafletProxy("map")
    proxy %>%
      addAwesomeMarkers(
        lng         = station_data$longitude[rd],
        lat         = station_data$latitude[rd],
        label       = station_data$siteID[rd],
        layerId     = station_data$siteID[rd],
        icon        = icons_ready,
        labelOptions = labelOptions(style = list(
          "color" = "white", "font-size" = "14px",
          "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
        ))
      )

    if (length(hd) > 0) {
      leafletProxy("map") %>%
        addAwesomeMarkers(
          lng         = station_data$longitude[hd],
          lat         = station_data$latitude[hd],
          label       = station_data$siteID[hd],
          layerId     = station_data$siteID[hd],
          icon        = icons_hold,
          labelOptions = labelOptions(style = list(
            "color" = "white", "font-size" = "14px",
            "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
          ))
        )
    }

    if (length(dw) > 0) {
      leafletProxy("map") %>%
        addAwesomeMarkers(
          lng         = station_data$longitude[dw],
          lat         = station_data$latitude[dw],
          label       = station_data$siteID[dw],
          layerId     = station_data$siteID[dw],
          icon        = icons_down,
          labelOptions = labelOptions(style = list(
            "color" = "white", "font-size" = "14px",
            "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
          ))
        )
    }

    proxy %>%
      addAwesomeMarkers(
        lat         = selected_station$lat,
        lng         = selected_station$lon,
        label       = selected_station$id,
        layerId     = "selid",
        icon        = icon_sel,
        labelOptions = labelOptions(noHide = TRUE, style = list(
          "color" = "white", "font-size" = "16px",
          "background-color" = "#404040", "border-color" = "#404040", "font-weight" = "bold"
        ))
      )
  })


  # ------------------------------- Map click

  observeEvent(input$map_click, {
    click <- input$map_click
    selected_point$xy <- cbind(click$lng, click$lat)
    print(selected_point$xy)
  })


  # ------------------------------- Raster handling

  observeEvent(input$admin, {
    if (input$admin) {
      leafletProxy("map") %>%
        addPolygons(
          layerId     = as.character(bd$district),
          label       = as.character(bd$district),
          data        = bd$geometry,
          fillOpacity = 0,
          color       = "black",
          weight      = 2
        )
    } else {
      leafletProxy("map") %>% removeShape(layerId = as.character(bd$district))
    }
  })

  observeEvent(input$period_raster, {
    print(input$period_raster)
    time_range_f <- isolate(daily_rv())$time_range_f
    timeraster   <- as.numeric(difftime(input$period_raster, time_range_f$max, units = "hours"))
    if (timeraster < 0) timeraster <- 0

    raster_path <- file.path(
      ROOT_DIR, "WWCS/dashboard/appdata/gemos_raster",
      paste0("raster_plot_", timeraster, ".tif")
    )

    if (file.exists(raster_path)) {
      ifsmap <- raster::raster(raster_path)
      leafletProxy("map") %>%
        addRasterImage(x = ifsmap, layerId = "raster", opacity = 0.65, colors = raster_colors) %>%
        addPolygons(data = mask, color = "black", fillColor = "white", weight = 2)
    }
  })

  observeEvent(input$raster, {
    if (input$raster) {
      ifsmap <- isolate(daily_rv())$ifsmap
      if (!is.data.frame(ifsmap)) {
        leafletProxy("map") %>%
          addRasterImage(x = ifsmap, layerId = "raster", opacity = 0.65, colors = raster_colors) %>%
          addPolygons(data = mask, color = "black", fillColor = "white", weight = 2)
      }
    } else {
      leafletProxy("map") %>% clearImages()
    }
  })


  # ------------------------------- Language

  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
  })

  observeEvent(input$selected_language, {
    choices_en <- c(
      "Temperature" = "Temperature", "Relative Humidity" = "RH",
      "Pressure" = "Pressure", "Solar" = "Solar", "Signal" = "Signal",
      "Battery" = "Battery", "Precipitation" = "Precipitation",
      "Evapotranspiration" = "Evapotranspiration"
    )
    choices_ru <- c(
      "Температура" = "Temperature", "Относительная влажность" = "RH",
      "Давление" = "Pressure", "Солнечный" = "Solar", "Сигнал" = "Signal",
      "Аккумулятор" = "Battery", "Дождь" = "Precipitation",
      "Эвапотранспирация" = "Evapotranspiration"
    )
    updateSelectInput(session, "var",
      choices = if (input$selected_language == "ru") choices_ru else choices_en
    )
  })


  # ------------------------------- Data Plots

  output$meteogram2 <- renderPlotly({
    daily <- daily_rv()
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      plot_meteogram_raster(selected_point$xy, daily$gemos_mea, daily$gemos_std)
    })
  })

  output$meteogram <- renderPlotly({
    daily <- daily_rv()
    obs   <- obs_joined()
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      # Inject obs into the function's enclosing environment so the original
      # 7-param signature can find it via lexical scoping (obs_tmp <- obs %>% ...)
      fn     <- plot_meteogram_precip
      fn_env <- new.env(parent = environment(fn))
      fn_env$obs <- obs
      environment(fn) <- fn_env
      fn(
        daily$emos, daily$dmo, daily$pictos,
        selected_station$id, input$period_f, input$ecmwf,
        mobile = shinybrowser::get_all_info()$device == "Mobile"
      )
    })
  })

  output$observations <- renderPlotly({
    obs <- obs_joined()
    withProgress(message = "Loading data ...", {
      incProgress(0.5)
      plot_observations(obs, selected_station$id, input$period_o, input$var)
    })
  })


  # ------------------------------- Value Boxes

  output$id <- renderValueBox({
    sd   <- station_derived()
    id   <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(sd$station_data$siteID[id]), paste(i18n$t("Station")), color = "teal")
  })

  output$alt <- renderValueBox({
    sd <- station_derived()
    id <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(sd$station_data$altitude[id], " m"), paste(i18n$t("Altitude")), color = "teal")
  })

  output$logger <- renderValueBox({
    sd <- station_derived()
    id <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(sd$station_data$loggerID[id]), paste(i18n$t("Logger ID")), color = "teal")
  })

  output$sdate <- renderValueBox({
    sd <- station_derived()
    id <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(as.Date(sd$station_data$startDate[id])), paste(i18n$t("Start Date")), color = "teal")
  })

  output$lat <- renderValueBox({
    sd <- station_derived()
    id <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(sd$station_data$latitude[id]), paste(i18n$t("Latitude")), color = "teal")
  })

  output$lng <- renderValueBox({
    sd <- station_derived()
    id <- which(sd$station_data$siteID == selected_station$id)
    valueBox(paste0(sd$station_data$longitude[id]), paste(i18n$t("Longitude")), color = "teal")
  })


  # ------------------------------- Login Security

  res_auth <- secure_server(check_credentials = check_credentials(credentials))

  output$auth_output <- renderPrint({
    reactiveValuesToList(res_auth)
    updateTabItems(session, "sidebar", "overview")
  })
}
