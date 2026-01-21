library(stringr)
server <- function(input, output, session) {
  ## read available crops from csv file
  crops <- names(read.csv("appdata/CropParameters.csv", nrows=1))
  crops <- unique(stringr::str_remove(crops[2:length(crops)], "_[KR][cD]"))
  
  selected <- reactiveValues(id = irrigation_default_station)
  
  advice <- reactiveValues(irrigate = "Do not irrigate",
                           ineed = "0 mm")
  
  sites_map <- reactive({
    sites_map <- dbReadTable(pool, "Sites")  %>%
      filter(irrigation == 1) %>%
      dplyr::select(c(siteID, siteName, latitude, longitude))
  })
  
  irrigation_df <- reactive({
    #make reactive to
    input$submit_edit
    
    sites <- dbReadTable(pool, "Sites")  %>%
      dplyr::as_tibble() %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(c(siteID, siteName, altitude, latitude, longitude, irrigation))
    
    dbReadTable(pool, "Sites")   %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(fieldproperties) %>%
      unlist() %>%
      spread_all %>%
      dplyr::bind_cols(sites) %>%
      dplyr::as_tibble() %>%
      dplyr::select(c(
        siteID,
        siteName,
        altitude,
        irrigation,
        Station,
        FC,
        WP,
        IE,
        WA,
        MAD,
        PHIc,
        StartDate,
        Crop,
        area,
        type,
        measurement_device,
        humanID
      ))
  })
  
  
  irrigation_data <- reactive({
    input$submit_data
    table_data <- dbReadTable(pool_service, "Irrigation") 
    
    if (nrow(table_data) > 0) {
      table_data <- table_data %>% 
        dplyr::filter(lubridate::year(date) == lubridate::year(Sys.Date())) %>%
        as_tibble() %>%
        dplyr::rename(Ineed = irrigationNeed,
                      Iapp = irrigationApp,
                      Precipitation = precipitation)
    } 
    
    table_data
  })
  
  # ------------------------------- Login Security
  
  # call the server part
  # check_credentials returns a function to authenticate users
  res_auth <- secure_server(check_credentials = check_credentials(credentials))
  
  output$auth_output <- renderPrint({
    reactiveValuesToList(res_auth)
    updateTabItems(session, "sidebar", "overview")
  })
  
  # your classic server logic
  
  # ------------------------------- Leaflet Map
  
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 7, maxZoom = 17)) %>%
      setView(lng = default_station$longitude,
              lat = default_station$latitude,
              zoom = 7)  %>%
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
        lng = sites_map()$longitude,
        lat = sites_map()$latitude,
        label = sites_map()$siteID,
        layerId = sites_map()$siteID,
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
  
  
  # ------------------------------- Add plot polygons
  
  observe({
    
    if (exists("plot_polygons")) {
      leafletProxy("map") %>%
        addPolygons(
          data = plot_polygons,
          color = "red",
          fillColor = "red",
          fillOpacity = 0.3,
          weight = 2
        )
    }
    
  })
  
  
  # ------------------------------- Language Translation
  
  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
    
  })
  
  # # ------------------------------- Station Selection
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    updateSelectInput(session, "selectid", selected = input$map_marker_click$id)
  })
  
  observeEvent(input$selectid, {
    selected$id <- input$selectid
  })
  
  observe({
    
    # Assign advice only if irrigation_data is not empty
    if (nrow(irrigation_data()) == 0) {
      advice$irrigate <- "No data available"
      advice$ineed <- "No data available"
    } else {
      advice$irrigate <- irrigation_data() %>%
        dplyr::filter(siteID == selected$id & date == Sys.Date() - days(1)) %>%
        dplyr::summarise(dplyr::if_else(PHIt > PHIc, i18n$t("Irrigate"), i18n$t("Do not irrigate")))
      
      advice$ineed <- irrigation_data() %>%
        dplyr::filter(siteID == selected$id & date == Sys.Date() - days(1)) %>%
        dplyr::summarise(paste0(round(Ineed), " mm"))
    }
    
    advice$rain <- "No rain expected"
    
  })
  
  output$plot_soil <- renderPlotly({
    plot_soil_moisture(irrigation_data, selected$id)
  })
  
  output$plot_balance <- renderPlotly({
    plot_water_balance(irrigation_data, selected$id)
  })
  
  # ------------------------------- Irrigation Table
  
  output$table <- DT::renderDataTable({
    table <- irrigation_df()
    DT::datatable(table,  options = list(pageLength = 20))
  })
  
  
  # ------------------------------- Modification of Table
  
  #Form for data entry
  entry_form <- function(button_id) {
    showModal(modalDialog(div(
      id = ("entry_form"),
      tags$head(tags$style(".modal-dialog{ width:600px}")),
      tags$head(tags$style(HTML(".shiny-split-layout > div {overflow: visible}"))),
      fluidPage(
        fluidRow(
          splitLayout(
            cellWidths = c("175px", "175px"),
            textInput("wp", "Wilting Point", placeholder = ""),
            textInput("fc", "Field Capacity", placeholder = "")
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px", "175px"),
            textInput("ie", "Irrigation Efficiency", placeholder = ""),
            textInput("wa", "Wetted Area", placeholder = ""),
            textInput("MAD", "Management Allowed Deficit", placeholder = "")
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px"),
            textInput("phic", "Initial Soil Moisture (PHIc)", placeholder = ""),
            textInput("Station", "Weather Station", placeholder = "")
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px"),
            dateInput("sd", "Start Date"),
            selectInput("cr", "Crop Type", choices = crops)
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px", "175px"),
            textInput("area", "Plot Area", placeholder = ""),
            selectInput("type", "Plot Type", choices = c("treatment", "control")),
            selectInput("measurement_device", "Measurement Device", choices = c("total_meter", "incremental_meter", "thomson_profile"))
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px"),
            textInput("humanID", "Responsible Farmer", placeholder = ""),
            checkboxInput("irrigation", width = "200px", label = HTML("<b>Activate Service?</b>"))
          ),
          br(),
          br(),
          actionButton(button_id, "Submit")
        ),
        easyClose = TRUE
      )
    )))
  }
  
  # Irrigation control
  # -----------------------------------------
  
  output$irradvice <- renderValueBox({
    valueBox(tags$p(advice$irrigate, style = "font-size: 60%;"),
             paste(paste0(Sys.Date())), color = "yellow")
  })
  
  output$irrvalue <- renderValueBox({
    valueBox(tags$p(advice$ineed, style = "font-size: 60%;"),
             paste(i18n$t('Next Irrigation')), color = "blue")
  })
  
  output$irrrain <- renderValueBox({
    valueBox(tags$p(advice$rain, style = "font-size: 60%;"),
             paste(paste0(Sys.Date())), color = "green")
  })
  
  output$apiOutput <- renderText({
    paste0(
      "curl -X POST -H \"Content-Type: application/json\" -d '{\"siteID\":\"",
      input$selectid,
      "\", \"Iapp\":",
      input$irrigationingest,
      ", \"precip\":",
      input$precipingest,
      ", \"date\":\"",
      input$dateingest,
      "\"}' https://",
      wwcs_domain,
      "/services/irrigationApp"
    )
    
  })
  
  output$api2Output <- renderText({
    paste0(
      "https://",
      wwcs_domain,
      "/services/irrigationNeed?siteID=",
      input$selectid,
      "&date=",
      input$dateingest
    )
    
  })
  
  observeEvent(input$submit_data, {
    output$apiresponse <- renderText({
      "Submitting ... "
    })
    
    out <-
      system(
        paste0(
          "curl -X POST -H \"Content-Type: application/json\" -d '{\"siteID\":\"",
          selected$id,
          "\", \"irrigationApp\":",
          input$irrigationingest,
          ", \"precip\":",
          input$precipingest,
          ", \"date\":\"",
          input$dateingest,
          "\"}' https://",
          wwcs_domain,
          "/services/irrigationApp"
        ),
        intern = TRUE
      )
    
    source(
      "/home/wwcs/wwcs/WWCS/irrigation/service/irrigation_calculation.R"
    )
    
    irrigation_data <- reactive({
      
      table_data <- dbReadTable(pool_service, "Irrigation") 
      
      if (nrow(table_data) > 0) {
        table_data <- table_data %>% 
          dplyr::filter(lubridate::year(date) == lubridate::year(Sys.Date())) %>%
          as_tibble() %>%
          dplyr::rename(Ineed = irrigationNeed,
                        Iapp = irrigationApp,
                        Precipitation = precipitation)
      } 
      
      table_data
    })
    
    output$plot_soil <- renderPlotly({
      plot_soil_moisture(irrigation_data, selected$id)
    })
    
    output$plot_balance <- renderPlotly({
      plot_water_balance(irrigation_data, selected$id)
    })
    
    # output$apiresponse <- renderText({"Values inserted successfully"})
    output$apiresponse <- renderText(out)
    
  })
  
  
  # Edit Data
  # -----------------------------------------
  
  observeEvent(input$edit_button, priority = 20, {
    sites <- dbReadTable(pool, "Sites")  %>%
      dplyr::as_tibble() %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(c(siteID, siteName, altitude, latitude, longitude, irrigation))
    
    SQL_df <- dbReadTable(pool, "Sites")   %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(fieldproperties) %>%
      unlist() %>%
      spread_all %>%
      dplyr::bind_cols(sites) %>%
      dplyr::as_tibble() %>%
      dplyr::select(c(
        siteID,
        siteName,
        altitude,
        irrigation,
        Station,
        FC,
        WP,
        IE,
        WA,
        MAD,
        PHIc,
        StartDate,
        Crop,
        area,
        type,
        measurement_device,
        humanID
      ))
    
    showModal(if (length(input$table_rows_selected) > 1) {
      modalDialog(title = "Warning",
                  paste("Please select only one row."),
                  easyClose = TRUE)
    } else if (length(input$table_rows_selected) < 1) {
      modalDialog(title = "Warning",
                  paste("Please select a row."),
                  easyClose = TRUE)
    })
    
    if (length(input$table_rows_selected) == 1) {
      entry_form("submit_edit")
      updateTextInput(session, "Station", value = unlist(SQL_df[input$table_rows_selected, "Station"], use.names = FALSE))
      updateTextInput(session, "wp", value = unlist(SQL_df[input$table_rows_selected, "WP"], use.names = FALSE))
      updateTextInput(session, "fc", value = unlist(SQL_df[input$table_rows_selected, "FC"], use.names = FALSE))
      updateTextInput(session, "ie", value = unlist(SQL_df[input$table_rows_selected, "IE"], use.names = FALSE))
      updateTextInput(session, "wa", value = unlist(SQL_df[input$table_rows_selected, "WA"], use.names = FALSE))
      updateTextInput(session, "MAD", value = unlist(SQL_df[input$table_rows_selected, "MAD"], use.names = FALSE))
      updateTextInput(session, "phic", value = unlist(SQL_df[input$table_rows_selected, "PHIc"], use.names = FALSE))
      updateTextInput(session, "sd", value = unlist(SQL_df[input$table_rows_selected, "StartDate"], use.names = FALSE))
      updateSelectInput(session, "cr", selected = unlist(SQL_df[input$table_rows_selected, "Crop"], use.names = FALSE))
      updateTextInput(session, "area", value = unlist(SQL_df[input$table_rows_selected, "area"], use.names = FALSE))
      updateSelectInput(session, "type", selected = unlist(SQL_df[input$table_rows_selected, "type"], use.names = FALSE))
      updateSelectInput(session, "measurement_device", selected = unlist(SQL_df[input$table_rows_selected, "measurement_device"], use.names = FALSE))
      updateTextInput(session, "humanID", value = unlist(SQL_df[input$table_rows_selected, "humanID"], use.names = FALSE))
      updateCheckboxInput(session, "irrigation", value = as.logical(unlist(SQL_df[input$table_rows_selected, "irrigation"], use.names = FALSE)))
    }
  })
  
  
  observeEvent(input$submit_edit, priority = 20, {
    sites <- dbReadTable(pool, "Sites")  %>%
      dplyr::as_tibble() %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(c(siteID, siteName, altitude, latitude, longitude, irrigation))
    
    SQL_df <- dbReadTable(pool, "Sites")   %>%
      dplyr::filter(type == "WWCS") %>%
      dplyr::select(fieldproperties) %>%
      unlist() %>%
      spread_all %>%
      dplyr::bind_cols(sites) %>%
      dplyr::as_tibble() %>%
      dplyr::select(c(
        siteID,
        siteName,
        altitude,
        irrigation,
        Station,
        FC,
        WP,
        IE,
        WA,
        MAD,
        PHIc,
        StartDate,
        Crop,
        area,
        type,
        measurement_device,
        humanID
      ))
    
    station_selection <-
      SQL_df[input$table_row_last_clicked, "siteID"]
    
    pool::dbExecute(
      pool,
      sprintf(
        'UPDATE Sites SET fieldproperties = JSON_SET(fieldproperties,
          "$.Station", ?,
          "$.StartDate", ?,
          "$.WP", ?,
          "$.FC", ?,
          "$.IE", ?,
          "$.WA", ?,
          "$.MAD", ?,
          "$.PHIc", ?,
          "$.Crop", ?,
          "$.area", ?,
          "$.type", ?,
          "$.measurement_device", ?,
          "$.humanID", ?
        ) WHERE siteID = ("%s")',
        station_selection
      ),
      params = list(
        as.character(input$Station),
        as.Date(input$sd),
        as.numeric(input$wp),
        as.numeric(input$fc),
        as.numeric(input$ie),
        as.numeric(input$wa),
        as.numeric(input$MAD),
        as.numeric(input$phic),
        as.character(input$cr),
        as.numeric(input$area),
        as.character(input$type),
        as.character(input$measurement_device),
        as.numeric(input$humanID)
      )
    )
    
    pool::dbExecute(
      pool,
      sprintf(
        'UPDATE Sites SET irrigation = ? WHERE siteID = ("%s")',
        station_selection
      ),
      params = list(as.numeric(input$irrigation))
    )
    
    sites_map <- reactive({
      sites_map <- dbReadTable(pool, "Sites")  %>%
        filter(irrigation == 1) %>%
        dplyr::select(c(siteID, siteName, latitude, longitude))
    })
    
    removeModal()
    
  })
}
