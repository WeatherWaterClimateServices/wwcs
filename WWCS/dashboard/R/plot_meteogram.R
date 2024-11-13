plot_meteogram <- function(emos, dmo, pictos, id, period, ecmwf, mobile) {
  # CHECK IF STATON IS CONTAINED
  station_id <- unique(dmo$siteID)
  
  if (id %in% station_id) {
    # FILTER DATA FOR SELECTED FORECAST REFRENCE TIME
    dmo_data <-
      dmo %>% dplyr::filter(reftime == period & siteID == id)
    emos_data <-
      emos %>% dplyr::filter(reftime == period & siteID == id)
    pictos_data <-
      pictos %>% dplyr::filter(reftime == period & siteID == id)
    
    mean_emos_data <- emos_data %>%
      dplyr::select(WWCS, time) %>%
      tidyr::gather("variable", "value", -time, na.rm = T)
    
    
    if (ecmwf) {
      mean_dmo_data <- dmo_data %>%
        dplyr::select(ECMWF, time) %>%
        tidyr::gather("variable", "value", -time, na.rm = T)
      
      forecast_data <-
        dplyr::bind_rows(mean_dmo_data, mean_emos_data) %>%
        dplyr::as_tibble()
      
      forecast_data$Q5 <- c(dmo_data$q05, emos_data$q05)
      forecast_data$Q25 <- c(dmo_data$q25, emos_data$q25)
      forecast_data$Q75 <- c(dmo_data$q75, emos_data$q75)
      forecast_data$Q95 <- c(dmo_data$q95, emos_data$q95)
      
      color_scale_fill <- setNames(c("skyblue", "red", "black"),
                                   c("ECMWF", "WWCS", "Observations"))
      
      color_scale_line <- setNames(c("skyblue", "darkred", "black"),
                                   c("ECMWF", "WWCS", "Observations"))
      
      legend_labels <-
        c("ECMWF forecast", "WWCS forecast", "Observations")
      
    } else {
      forecast_data <- mean_emos_data %>% as_tibble()
      forecast_data$Q5 <- c(emos_data$q05)
      forecast_data$Q25 <- c(emos_data$q25)
      forecast_data$Q75 <- c(emos_data$q75)
      forecast_data$Q95 <- c(emos_data$q95)
      
      color_scale_fill <- setNames(c("red", "black"),
                                   c("WWCS", "Observations"))
      
      color_scale_line <- setNames(c("darkred", "black"),
                                   c("WWCS", "Observations"))
      
      legend_labels <- c("WWCS forecast", "Observations")
      
    }
    
    
    observations_data <- emos_data %>%
      dplyr::select(Observations, time) %>%
      tidyr::gather("variable", "value", -time, na.rm = T) %>%
      dplyr::as_tibble()
    
    # Create plot object
    if (nrow(observations_data) > 0) {
      xlimits <- c(min(forecast_data$time),
                   max(forecast_data$time))
      
      xlimits_shadow <- c(min(forecast_data$time),
                          max(observations_data$time))
      
      plt <- forecast_data %>%
        ggplot(aes(x = time)) +
        geom_rect(
          aes(
            xmin = xlimits_shadow[1],
            xmax = xlimits_shadow[2],
            alpha = 0.4
          ),
          ymin = -100,
          ymax = 100,
          inherit.aes = FALSE,
          fill = "#ebebeb",
          colour = "NA"
        ) +
        geom_vline(
          xintercept = as.numeric(xlimits_shadow[2]),
          color = "gray",
          linewidth = 0.5
        ) +
        scale_color_manual(name = '',
                           labels = legend_labels,
                           values = color_scale_line) +
        scale_fill_manual(name = '', values = color_scale_fill) +
        geom_ribbon(aes(
          ymin = Q5,
          ymax = Q95,
          fill = variable
        ), alpha = 0.2) +
        geom_ribbon(aes(
          ymin = Q25,
          ymax = Q75,
          fill = variable
        ), alpha = 0.5) +
        geom_line(aes(y = value, color = variable)) +
        geom_line(data = observations_data, aes(y = value, color = variable)) +
        #ggimage::geom_image(data = pictos_plt, aes(x = time, y = height, image = image)) +
        labs(y = "°C", x = "") +
        scale_x_datetime(
          limits = xlimits,
          expand = c(0, 0),
          date_breaks = "1 days",
          date_labels = "%b %d"
        ) +
        theme_light() + guides(fill = "none") +
        theme(
          plot.title = element_text(hjust = 0.5, size = 18),
          legend.text = element_text(size = 10),
          axis.text.x = element_text(size = 10),
          axis.title.x = element_text(size = 10),
          axis.text.y = element_text(size = 10),
          axis.title.y = element_text(size = 10),
          legend.box.background = element_rect(fill = 'transparent')
        ) +
        scale_alpha(guide = 'none')
      
      # Do not show legend in mobile version
      
      
      if (mobile) {
        plt <- plt +
          theme(legend.position = "none") +
          scale_x_datetime(
            limits = xlimits,
            expand = c(0, 0),
            date_breaks = "2 days",
            date_labels = "%b %d"
          )
      }
      
      # Create plotly object
      
      font <- list(size = 15,
                   color = "white")
      label <- list(bordercolor = "transparent",
                    font = font)
      
      # Create pictos list
      
      pictos_list <- list()
      xpos <- seq(0.02, 0.92, length.out = 10)
      
      image_path <-
        "/srv/shiny-server/dashboard/appdata/weather_icons/png/"
      
      if (nrow(pictos_data) > 0) {
        for (i in 1:nrow(pictos_data)) {
          image_file <- paste0(image_path, pictos_data$day[i], "_big.png")
          txt <-
            RCurl::base64Encode(readBin(image_file, "raw", file.info(image_file)[1, "size"]), "txt")
          
          a <-
            list(
              source =  paste('data:image/png;base64', txt, sep = ','),
              x = xpos[i],
              y = 0.92,
              xref = "paper",
              yref = "paper",
              sizex = 0.125,
              sizey = 0.125
            )
          
          pictos_list[[i]] <- a
        }
      }
      
      p <- plotly::ggplotly(plt,
                            orientation = "h",
                            tooltip = c("text")) %>%
        plotly::config(
          modeBarButtonsToRemove = c(
            "toggleSpikelines",
            "autoScale2d",
            "hoverClosestCartesian",
            "hoverCompareCartesian"
          ),
          displaylogo = FALSE
        ) %>%
        plotly::layout(
          autosize = T,
          hoverlabel = label,
          title = font,
          legend = list(
            x = 0.7,
            y = 0.01,
            font = list(size = 12) ,
            bgcolor = 'rgba(0,0,0,0)'
          ),
          images = pictos_list
        )
      
      
      if (ecmwf) {
        p$x$data[[7]]$text <-
          paste0(round(mean_dmo_data$value, digits = 2),
                 "°C \n",
                 mean_dmo_data$variable)
        p$x$data[[8]]$text <-
          paste0(round(mean_emos_data$value, digits = 2),
                 "°C \n",
                 mean_emos_data$variable)
        p$x$data[[9]]$text <-
          paste0(
            round(observations_data$value, digits = 2),
            "°C \n",
            observations_data$variable
          )
        p$x$data[[3]]$name <- "ECMWF Forecast"
        p$x$data[[4]]$name <- "WWCS Forecast"
        p$x$data[[5]]$name <- "ECMWF Forecast"
        p$x$data[[6]]$name <- "WWCS Forecast"
        p$x$data[[7]]$name <- "ECMWF Forecast"
        p$x$data[[8]]$name <- "WWCS Forecast"
        p$x$data[[9]]$name <- "Observations"
        
      } else {
        p$x$data[[3]]$text <-
          paste0(round(forecast_data$Q5, digits = 2),
                 "°C \nUncertainty: 5 - 95%")
        p$x$data[[4]]$text <-
          paste0(round(forecast_data$Q25, digits = 2),
                 "°C \nUncertainty: 25 - 75%")
        p$x$data[[5]]$text <-
          paste0(round(mean_emos_data$value, digits = 2),
                 "°C \n",
                 mean_emos_data$variable)
        p$x$data[[6]]$text <-
          paste0(
            round(observations_data$value, digits = 2),
            "°C \n",
            observations_data$variable
          )
        p$x$data[[3]]$name <- "WWCS Forecast"
        p$x$data[[4]]$name <- "WWCS Forecast"
        p$x$data[[5]]$name <- "WWCS Forecast"
        p$x$data[[6]]$name <- "Observations"
      }
      
    } else {
      xlimits <- c(min(forecast_data$time),
                   max(forecast_data$time))
      
      
      plt <- forecast_data %>%
        ggplot(aes(x = time)) +
        scale_color_manual(name = '',
                           labels = legend_labels,
                           values = color_scale_line) +
        scale_fill_manual(name = '', values = color_scale_fill) +
        geom_ribbon(aes(
          ymin = Q5,
          ymax = Q95,
          fill = variable
        ), alpha = 0.2) +
        geom_ribbon(aes(
          ymin = Q25,
          ymax = Q75,
          fill = variable
        ), alpha = 0.5) +
        geom_line(aes(y = value, color = variable)) +
        labs(y = "°C", x = "") +
        scale_x_datetime(
          limits = xlimits,
          expand = c(0, 0),
          date_breaks = "1 days",
          date_labels = "%b %d"
        ) +
        theme_light() + guides(fill = "none") +
        theme(
          plot.title = element_text(hjust = 0.5, size = 18),
          legend.text = element_text(size = 10),
          axis.text.x = element_text(size = 10),
          axis.title.x = element_text(size = 10),
          axis.text.y = element_text(size = 10),
          axis.title.y = element_text(size = 10),
          legend.box.background = element_rect(fill = 'transparent')
        ) +
        scale_alpha(guide = 'none')
      
      # Create plotly object
      
      font <- list(size = 15,
                   color = "white")
      label <- list(bordercolor = "transparent",
                    font = font)
      
      # Create pictos list
      
      pictos_list <- list()
      xpos <- seq(0.02, 0.92, length.out = 10)
      
      image_path <-
        "/srv/shiny-server/dashboard/appdata/weather_icons/png/"
      
      if (nrow(pictos_data) > 0) {
        for (i in 1:nrow(pictos_data)) {
          image_file <- paste0(image_path, pictos_data$day[i], "_big.png")
          txt <-
            RCurl::base64Encode(readBin(image_file, "raw", file.info(image_file)[1, "size"]), "txt")
          
          a <-
            list(
              source =  paste('data:image/png;base64', txt, sep = ','),
              x = xpos[i],
              y = 0.92,
              xref = "paper",
              yref = "paper",
              sizex = 0.125,
              sizey = 0.125
            )
          
          pictos_list[[i]] <- a
        }
      }
      
      p <- plotly::ggplotly(plt,
                            orientation = "h",
                            tooltip = c("text")) %>%
        plotly::config(
          modeBarButtonsToRemove = c(
            "toggleSpikelines",
            "autoScale2d",
            "hoverClosestCartesian",
            "hoverCompareCartesian"
          ),
          displaylogo = FALSE
        ) %>%
        plotly::layout(
          autosize = T,
          hoverlabel = label,
          title = font,
          legend = list(
            x = 0.7,
            y = 0.01,
            font = list(size = 12) ,
            bgcolor = 'rgba(0,0,0,0)'
          ),
          images = pictos_list
        )
      
      if (mobile) {
        p <- p %>% plotly::layout(
          showlegend = FALSE
        )
      }
      
      
      if (ecmwf) {
        p$x$data[[5]]$text <-
          paste0(round(mean_dmo_data$value, digits = 2),
                 "°C \n",
                 mean_dmo_data$variable)
        p$x$data[[6]]$text <-
          paste0(round(mean_emos_data$value, digits = 2),
                 "°C \n",
                 mean_emos_data$variable)
        
        p$x$data[[1]]$name <- "ECMWF Forecast"
        p$x$data[[2]]$name <- "WWCS Forecast"
        p$x$data[[3]]$name <- "ECMWF Forecast"
        p$x$data[[4]]$name <- "WWCS Forecast"
        p$x$data[[5]]$name <- "ECMWF Forecast"
        p$x$data[[6]]$name <- "WWCS Forecast"
        
      } else {
        p$x$data[[1]]$text <-
          paste0(round(forecast_data$Q5, digits = 2),
                 "°C \nUncertainty: 5 - 95%")
        p$x$data[[2]]$text <-
          paste0(round(forecast_data$Q25, digits = 2),
                 "°C \nUncertainty: 25 - 75%")
        p$x$data[[3]]$text <-
          paste0(round(mean_emos_data$value, digits = 2),
                 "°C \n",
                 mean_emos_data$variable)
        
        p$x$data[[1]]$name <- "WWCS Forecast"
        p$x$data[[2]]$name <- "WWCS Forecast"
        p$x$data[[3]]$name <- "WWCS Forecast"
      }
    }
    
    
    # } else { # No observations currently
    #   p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
    #     plotly::config(displayModeBar = FALSE) %>%
    #     plotly::layout(
    #       title = list(text = "Station currently not operating\n Станция в настоящее время не работает",
    #                    yref = "paper",
    #                    y = 0.5))
    # }
  } else {
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "Observational record too short for forecast calibration\n Данные наблюдений слишком коротки для калибровки прогнозов",
                     yref = "paper",
                     y = 0.5)
      )
    
  }
  p
}
