server <- function(input, output, session) {
  selected <- reactiveValues(id = warning_default_station,
                             type = "station")
  
  thresholds <- reactiveValues(
    cold1 = NA,
    cold2 = NA,
    cold3 = NA,
    heat1 = NA,
    heat2 = NA,
    heat3 = NA
  )
  
  warnings_df <- reactive({
    #make reactive to
    input$submit_edit
    
    dbReadTable(pool_service, "Warnings")
  })
  
  
  # ------------------------------- Leaflet Map
  
  output$map <- renderLeaflet({
    leaflet(
      data = ews_district_map,
      options = leafletOptions(minZoom = 7, maxZoom = 17),
      elementId = "map"
    ) %>%
      setView(lng = setlon,
              lat = setlat,
              zoom = 7)  %>%
      addTiles(group = i18n$t("Street View")) %>%
      addProviderTiles("Esri.WorldImagery", group = i18n$t("Satellite")) %>%
      addLayersControl(baseGroups = c(i18n$t("Satellite"), i18n$t("Street View")),
                       options = layersControlOptions(collapsed = FALSE)) %>%
      addPolygons(
        layerId = as.character(ews_district_map$district),
        label = as.character(ews_district_map$district),
        data = ews_district_map$geometry,
        fillOpacity = 0.8,
        color = "black",
        fillColor = as.vector(ews_colors[ews_district_map$level]),
        weight = 3,
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
      addPolygons(
        data = mask,
        color = "black",
        fillColor = "white",
        fillOpacity = 1,
        weight = 2
      ) %>%
      addAwesomeMarkers(
        lng = ews_station_index$lon,
        lat = ews_station_index$lat,
        label = ews_station_index$siteID,
        layerId = ews_station_index$siteID,
        icon = icon_neutral,
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
      addLegend(
        position = c("bottomright"),
        colors = c(colgreen, colyellow, colred),
        labels = c(
          paste(i18n$t("Low probability"),"< 40 %"),
          paste(i18n$t("Moderate probability"),"< 70 %"),
          paste(i18n$t("High probability"), "> 70 %")
        ),
        title = "Warning Level"
      )
    
  
  })
  
  # ------------------------------- Language Translation
  
  observeEvent(input$selected_language, {
    update_lang(language = input$selected_language, session)
  })
  
  # ------------------------------- Station Selection
  
  observeEvent(input$map_shape_click, {
    selected$id <- input$map_shape_click$id
    selected$type <- "district"
  })
  
  observeEvent(input$map_marker_click, {
    selected$id <- input$map_marker_click$id
    selected$type <- "station"
  })
  
  output$plot <- renderPlot({
    plot_warning(selected$id,
                 selected$type,
                 input$threshold,
                 input$reftime)
  })
  
  # ------------------------------- Warning Adjustment
  
  observeEvent(c(input$reftime, input$threshold), {
    
    # Prepare map data
    ews_district_map <- ews_district %>%
      dplyr::filter(reftime == input$reftime) %>%
      dplyr::filter(date == input$reftime) %>%
      dplyr::right_join(bd) %>%
      dplyr::mutate(level = .data[[input$threshold]])
    
    
    warn_stations <- ews_station %>%
      dplyr::filter(reftime == input$reftime) %>%
      dplyr::filter(date == input$reftime) %>%
      filter(!!as.name(input$threshold) == 'red') %>%
      distinct(siteID)
    
    ws <- which(ews_station_index$siteID %in% warn_stations$siteID)
    
    print(ws)

    proxy <- leafletProxy('map')
    proxy %>%
      addPolygons(
        layerId = as.character(ews_district_map$district),
        label = as.character(ews_district_map$district),
        data = ews_district_map$geometry,
        fillOpacity = 0.8,
        color = "black",
        fillColor = as.vector(ews_colors[ews_district_map$level]),
        weight = 3,
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
    
    if (length(ws) > 0) {

      if (stringr::str_detect(input$threshold, "Cold")) {
        icon_warn <- icon_cold
      } else if (stringr::str_detect(input$threshold, "Heat")) {
        icon_warn <- icon_heat
      }

      proxy <- leafletProxy('map')
      proxy %>%
        addAwesomeMarkers(
          lng = ews_station_index$lon,
          lat = ews_station_index$lat,
          label = ews_station_index$siteID,
          layerId = ews_station_index$siteID,
          icon = icon_neutral,
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
          lng = ews_station_index$lon[ws],
          lat = ews_station_index$lat[ws],
          label = ews_station_index$siteID[ws],
          layerId = ews_station_index$siteID[ws],
          icon = icon_warn,
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
    } else {
    proxy <- leafletProxy('map')
    proxy %>%
      addAwesomeMarkers(
        lng = ews_station_index$lon,
        lat = ews_station_index$lat,
        label = ews_station_index$siteID,
        layerId = ews_station_index$siteID,
        icon = icon_neutral,
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
  
  
  # ------------------------------- Value Boxes
  
  observe({
    if (selected$type == "district") {
      levels <- ews_district %>%
        dplyr::filter(district == selected$id) %>%
        dplyr::filter(reftime == input$reftime) %>%
        dplyr::select(c(
          Coldthres1,
          Coldthres2,
          Coldthres3,
          Heatthres1,
          Heatthres2,
          Heatthres3
        ))
      
    } else if (selected$type == "station") {
      levels <- ews_station %>%
        dplyr::filter(siteID == selected$id) %>%
        dplyr::filter(reftime == input$reftime) %>%
        dplyr::select(c(
          Coldthres1,
          Coldthres2,
          Coldthres3,
          Heatthres1,
          Heatthres2,
          Heatthres3
        ))
      
    }
    
    thresholds$cold1 = levels$Coldthres1[1]
    thresholds$cold2 = levels$Coldthres2[2]
    thresholds$cold3 = levels$Coldthres3[3]
    thresholds$heat1 = levels$Heatthres1[1]
    thresholds$heat2 = levels$Heatthres2[2]
    thresholds$heat3 = levels$Heatthres3[3]
    
  })
  
  output$cold1 <- renderValueBox({
    valueBox(paste0(thresholds$cold1, " °C"),
             paste(i18n$t('Frost'),' Level 1'),
             color = "blue")
  })
  output$cold2 <- renderValueBox({
    valueBox(paste0(thresholds$cold2, " °C"),
             paste(i18n$t('Frost'),' Level 2'),
             color = "blue")
  })
  output$cold3 <- renderValueBox({
    valueBox(paste0(thresholds$cold3, " °C"),
             paste(i18n$t('Frost'),' Level 3'),
             color = "blue")
  })
  output$heat1 <- renderValueBox({
    valueBox(paste0(thresholds$heat1, " °C"),
             paste(i18n$t('Heat'),' Level 1'),
             color = "red")
  })
  output$heat2 <- renderValueBox({
    valueBox(paste0(thresholds$heat2, " °C"),
             paste(i18n$t('Heat'),' Level 2'),
             color = "red")
  })
  output$heat3 <- renderValueBox({
    valueBox(paste0(thresholds$heat3, " °C"),
             paste(i18n$t('Heat'),' Level 3'),
             color = "red")
  })
  
  # ------------------------------- Warning Table
  
  output$table <- DT::renderDataTable({
    table <- warnings_df()
    DT::datatable(table)
  })
  
  # ------------------------------- Modification of Table
  
  #Form for data entry
  entry_form <- function(button_id) {
    showModal(modalDialog(div(
      id = ("entry_form"),
      tags$head(tags$style(".modal-dialog{ width:400px}")),
      tags$head(tags$style(
        HTML(".shiny-split-layout > div {overflow: visible}")
      )),
      fluidPage(
        fluidRow(
          splitLayout(
            cellWidths = c("175px", "175px"),
            cellArgs = list(style = "vertical-align: top"),
            textInput("Heat1", "Heat Threshold 1 (°C)", placeholder = ""),
            textInput("Cold1", "Heat Threshold 1 (°C)", placeholder = ""),
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px"),
            cellArgs = list(style = "vertical-align: top"),
            textInput("Heat2", "Heat Threshold 2 (°C)", placeholder = ""),
            textInput("Cold2", "Heat Threshold 2 (°C)", placeholder = ""),
          ),
          br(),
          br(),
          splitLayout(
            cellWidths = c("175px", "175px"),
            cellArgs = list(style = "vertical-align: top"),
            textInput("Heat3", "Heat Threshold 3 (°C)", placeholder = ""),
            textInput("Cold3", "Heat Threshold 3 (°C)", placeholder = ""),
          ),
          br(),
          checkboxInput(
            "alldistricts",
            width = "200px",
            label = HTML("<b>Apply to all districts?</b>")
          ),
          br(),
          actionButton(button_id, "Submit")
        ),
        easyClose = TRUE
      )
    )))
  }
  
  observeEvent(input$edit_button, priority = 20, {
    warnings_df <- dbReadTable(pool_service, "Warnings")
    
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
      
      updateTextInput(session, "Heat1", value = unlist(warnings_df[input$table_rows_selected, "Heat1"], use.names = FALSE))
      updateTextInput(session, "Heat2", value = unlist(warnings_df[input$table_rows_selected, "Heat2"], use.names = FALSE))
      updateTextInput(session, "Heat3", value = unlist(warnings_df[input$table_rows_selected, "Heat3"], use.names = FALSE))
      updateTextInput(session, "Cold1", value = unlist(warnings_df[input$table_rows_selected, "Cold1"], use.names = FALSE))
      updateTextInput(session, "Cold2", value = unlist(warnings_df[input$table_rows_selected, "Cold2"], use.names = FALSE))
      updateTextInput(session, "Cold3", value = unlist(warnings_df[input$table_rows_selected, "Cold3"], use.names = FALSE))
      
    }
  })
  
  observeEvent(input$submit_edit, priority = 20, {
    warnings_df <- dbReadTable(pool_service, "Warnings")
    
    district_selection <-
      warnings_df[input$table_row_last_clicked, "district"]
    
    if (input$alldistricts) {
      pool::dbExecute(
        pool_service,
        sprintf(
          'UPDATE Warnings SET Heat1 = ?, Heat2 = ?, Heat3 = ?, Cold1 = ?, Cold2 = ?, Cold3 = ?'
        ),
        params = list(
          as.numeric(input$Heat1),
          as.numeric(input$Heat2),
          as.numeric(input$Heat3),
          as.numeric(input$Cold1),
          as.numeric(input$Cold2),
          as.numeric(input$Cold3)
        )
      )
    } else {
      pool::dbExecute(
        pool_service,
        sprintf(
          'UPDATE Warnings SET Heat1 = ?, Heat2 = ?, Heat3 = ?, Cold1 = ?, Cold2 = ?, Cold3 = ? WHERE district = ("%s")',
          district_selection
        ),
        params = list(
          as.numeric(input$Heat1),
          as.numeric(input$Heat2),
          as.numeric(input$Heat3),
          as.numeric(input$Cold1),
          as.numeric(input$Cold2),
          as.numeric(input$Cold3)
        )
      )
    }
    
    removeModal()
    
  })
  
  
  # ------------------------------- SMS Functionality
  
  
  # Update picker input with numbers from the database
  recipients <- data.frame("id" = humans$humanID, "phone" = humans$phone, "firstName" = humans$firstName, "lastName" = humans$lastName)
  updatePickerInput(session, "selected_numbers", choices = recipients$id)
  
  # Combine selected numbers and message into JSON
  observeEvent(input$send_button, {

    levels <- ews_station %>%
      dplyr::filter(reftime == input$reftime) %>%
      dplyr::mutate(level = .data[[input$threshold]]) %>%
      dplyr::right_join(humans_at_site)
    
    selected_numbers <- input$selected_numbers
    message <- input$message
    
    if (!is.null(selected_numbers) && length(selected_numbers) > 0 && nchar(message) > 0) {
        json_data <- lapply(selected_numbers, function(num) {
        recipient <- recipients[recipients$id == num, ]

        for (i in 1:as.numeric(input$num_days)) {
          level_forecasted <- levels[levels$humanID == num, ]$level
          
          if (!purrr::is_empty(level_forecasted)) {
            level <- level_forecasted[i] 
            
            if (level == "green") {
              level = "low"
            } else if (level == "yellow") {
              level = "moderate"
            } else if (level == "red") {
              level = "high"
            }
            
          } else {
            level = "UKNOWN"
          }
          
          msg_level <- gsub("\\[Level\\]", level, message)
          msg_date <- gsub("\\[Date\\]",  format_date(Sys.Date() + (i - 1)), msg_level)


          # # Check if input$threshold contains the word cold in the string
          # 
          if (stringr::str_detect(input$threshold, "Cold")) {
            msg_type <- gsub("\\[Heat/Cold\\]", "frost", msg_date)
          } else if (stringr::str_detect(input$threshold, "Heat")) {
            msg_type <- gsub("\\[Heat/Cold\\]", "heat", msg_date)
          }

          # Concatenate msg along the loop with a newline

          if (i == 1) {
            msg <- msg_type
          } else {
            msg <- paste(msg, "\n", msg_type)
          }
        }
        
        list(number = num, message = msg, phone = recipient$phone, firstName = recipient$firstName, lastName = recipient$lastName)
      })
      output$combined_json <- renderPrint({
        jsonlite::toJSON(json_data, pretty = TRUE)
      })
    } else {
      output$combined_json <- renderPrint({
        "Select humand id numbers and enter a message to generate JSON."
      })
    }
  })

}
