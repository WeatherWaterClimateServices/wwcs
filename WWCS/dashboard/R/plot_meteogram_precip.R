plot_meteogram_precip <- function(emos, dmo, pictos, id, period, ecmwf, mobile) {
  # CHECK IF STATON IS CONTAINED
  station_id <- unique(dmo$siteID)
  offset = 0.10
  
  assign_bins <- function(datetime) {
    hour <- as.numeric(format(datetime, "%H"))
    if (hour >= 0 & hour < 6) {
      bin <- "0-6am"
      center_time <- as.POSIXct(as.Date(datetime) + lubridate::hours(3), tz = timezone_country)
    } else if (hour >= 6 & hour < 12) {
      bin <- "7am-12pm"
      center_time <- as.POSIXct(as.Date(datetime) + lubridate::hours(9), tz = timezone_country)
    } else if (hour >= 12 & hour < 18) {
      bin <- "1pm-6pm"
      center_time <- as.POSIXct(as.Date(datetime) + lubridate::hours(15), tz = timezone_country)
    } else {
      bin <- "7pm-12am"
      center_time <- as.POSIXct(as.Date(datetime) + lubridate::hours(21), tz = timezone_country)
    }
    return(data.frame(bin, center_time))
  }
  
  if (id %in% station_id) {
    # FILTER DATA FOR SELECTED FORECAST REFRENCE TIME
    dmo_data <-
      dmo %>% dplyr::filter(as.Date(reftime) == period & siteID == id)
    emos_data <-
      emos %>% dplyr::filter(as.Date(reftime) == period & siteID == id)
    pictos_data <-
      pictos %>% dplyr::filter(as.Date(reftime) == period & siteID == id)
    
    mean_emos_data <- emos_data %>%
      dplyr::select(WWCS, time) %>%
      tidyr::gather("variable", "value", -time, na.rm = T)
    
    
    if (ecmwf) {
      mean_dmo_data <- dmo_data %>%
        dplyr::select(ECMWF, time) %>%
        tidyr::gather("variable", "value", -time, na.rm = T)
      
      forecast_data_dmo <-
        dplyr::bind_rows(mean_dmo_data) %>%
        dplyr::as_tibble()
      
      forecast_data_dmo$Q5 <- c(dmo_data$q05)
      forecast_data_dmo$Q25 <- c(dmo_data$q25)
      forecast_data_dmo$Q75 <- c(dmo_data$q75)
      forecast_data_dmo$Q95 <- c(dmo_data$q95)
    } 
    
    forecast_data <- mean_emos_data %>% as_tibble()
    forecast_data$Q5 <- c(emos_data$q05)
    forecast_data$Q25 <- c(emos_data$q25)
    forecast_data$Q75 <- c(emos_data$q75)
    forecast_data$Q95 <- c(emos_data$q95)
    
    emos_data <- emos_data %>%
      rowwise() %>%
      mutate(bins = assign_bins(time)$bin,
             center_time = assign_bins(time)$center_time) %>%
      ungroup()
    
    forecast_pr_data <- emos_data %>%
      group_by(bins, center_time) %>%
      summarize(
        PR = sum(IFS_PR_mea, na.rm = TRUE),
        PR_std = mean(IFS_PR_std, na.rm = TRUE)
      ) %>%
      dplyr::mutate(PR = ifelse(PR < 0, 0, PR))    
    
    observations_data <- emos_data %>%
      dplyr::select(Observations, time) %>%
      dplyr::mutate(Observations = Observations) %>%
      tidyr::gather("variable", "value", -time, na.rm = T) %>%
      dplyr::as_tibble()
    
    obs_tmp <- obs %>%
      dplyr::filter(time >= period & siteID == id) %>%
      dplyr::select(c(time, Precipitation)) %>%
      dplyr::mutate(Precipitation = ifelse(Precipitation <= 0.1, NA, Precipitation)) %>%
      na.omit()
    
    if (nrow(obs_tmp) > 0) {
      observations_pr <- obs_tmp %>%
        rowwise() %>%
        mutate(bins = assign_bins(time)$bin,
               center_time = assign_bins(time)$center_time) %>%
        ungroup() %>%
        group_by(bins, center_time) %>%
        summarize(PR = sum(Precipitation, na.rm = TRUE), )
      
    } else {
      observations_pr <- data.frame(
        bins = character(),
        center_time = as.POSIXct(character()),
        PR = numeric()
      )
    }
    
    if (nrow(observations_data) > 0) {
      xlimits <- c(min(forecast_data$time), max(forecast_data$time))
      
      xlimits_shadow <- c(min(forecast_data$time), max(observations_data$time))
      
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
              y = 0.95,
              xref = "paper",
              yref = "paper",
              sizex = 0.08,
              sizey = 0.08
            )
          
          pictos_list[[i]] <- a
        }
      }
      
      vline <- function(x = 0,
                        color = "gray") {
        list(
          type = "line",
          y0 = 0,
          y1 = 1,
          yref = "paper",
          x0 = x,
          x1 = x,
          line = list(color = color),
          layer = "below"
        )
      }
      
      p <- plotly::plot_ly() %>%
        # Add the first ribbon layer (Q5 to Q95)
        plotly::add_bars(
          x = ~ forecast_pr_data$center_time,
          y = ~ forecast_pr_data$PR,
          marker = list(color = "lightblue"),
          yaxis = "y2",
          hoverinfo = 'x+y',
          name = 'ECMWF Precipitation',
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Precipitation</b>: %{y:.1f}<br>'
          ),
          showlegend = FALSE,
          opacity = 0.5
        ) %>%
        plotly::add_ribbons(
          x = ~ forecast_data$time,
          ymin = ~ forecast_data$Q5,
          ymax = ~ forecast_data$Q95,
          fillcolor = "red",
          line = list(color = "red"),
          opacity = 0.2,
          showlegend = FALSE,
          name = "WWCS 5-95%",
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Temperature</b>: %{y:.1f}<br>'
          )
        ) %>%  # Add the second ribbon layer (Q25 to Q75)
        plotly::add_ribbons(
          x = ~ forecast_data$time,
          ymin = ~ forecast_data$Q25,
          ymax = ~ forecast_data$Q75,
          fillcolor = "red",
          line = list(color = "red"),
          opacity = 0.5,
          showlegend = FALSE,
          name = "WWCS 25-75%",
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Temperature</b>: %{y:.1f}<br>'
          )
        ) %>%
        # Add the line layer
        plotly::add_lines(
          x = ~ forecast_data$time,
          y = ~ forecast_data$value,
          line = list(color = "darkred"),
          line = list(width = 2),
          name = "WWCS",
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Temperature</b>: %{y:.1f}<br>'
          ),
          showlegend = FALSE
        ) %>%
        # Add the line layer
        plotly::add_lines(
          x = ~ observations_data$time,
          y = ~ observations_data$value,
          line = list(color = "black"),
          line = list(width = 2),
          name = "Observations",
          showlegend = FALSE,
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Temperature</b>: %{y:.1f}<br>'
          ),
          showlegend = FALSE
        )
      
      if (nrow(observations_pr)) {
        p  <- p %>% plotly::add_bars(
          x = ~ observations_pr$center_time,
          y = ~ observations_pr$PR,
          marker = list(color = "#2c7fb8"),
          yaxis = "y2",
          hoverinfo = 'x+y',
          name = 'Station Precipitation',
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M}<br>',
            '<b>Precipitation</b>: %{y:.1f}<br>'
          ),
          showlegend = FALSE,
          opacity = 1
        )
      }
        
      if (ecmwf) {
        p <- p %>%
          plotly::add_ribbons(
            x = ~ forecast_data_dmo$time,
            ymin = ~ forecast_data_dmo$Q5,
            ymax = ~ forecast_data_dmo$Q95,
            fillcolor = "skyblue",
            line = list(color = "skyblue"),
            opacity = 0.2,
            showlegend = FALSE,
            name = "ECMWF 5-95%",
            hovertemplate = paste(
              '<b>Time</b>: %{x|%b %d %H:%M}<br>',
              '<b>Temperature</b>: %{y:.1f}<br>'
            )
          ) %>%  # Add the second ribbon layer (Q25 to Q75)
          plotly::add_ribbons(
            x = ~ forecast_data_dmo$time,
            ymin = ~ forecast_data_dmo$Q25,
            ymax = ~ forecast_data_dmo$Q75,
            fillcolor = "skyblue",
            line = list(color = "skyblue"),
            opacity = 0.5,
            showlegend = FALSE,
            name = "ECMWF 25-75%",
            hovertemplate = paste(
              '<b>Time</b>: %{x|%b %d %H:%M}<br>',
              '<b>Temperature</b>: %{y:.1f}<br>'
            )
          ) %>%
          # Add the line layer
          plotly::add_lines(
            x = ~ forecast_data_dmo$time,
            y = ~ forecast_data_dmo$value,
            line = list(color = "skyblue"),
            line = list(width = 2),
            name = "ECMWF",
            hovertemplate = paste(
              '<b>Time</b>: %{x|%b %d %H:%M}<br>',
              '<b>Temperature</b>: %{y:.1f}<br>'
            ),
            showlegend = FALSE
          ) 
      }
      
      
      p <- plotly::layout(
        p,
        shapes = list(
          vline(xlimits_shadow[2]),
          list(
            type = "rect",
            fillcolor = "#ebebeb",
            line = list(color = "#ebebeb"),
            opacity = 0.3,
            x0 = xlimits_shadow[1],
            x1 = xlimits_shadow[2],
            y0 = min(min(forecast_data$Q5),0),
            y1 = max(forecast_data$Q95) + max(forecast_data$Q95)*offset,
            layer = "below"
          )
        ),
        yaxis = list(
          title = "°C",
          range = c(
            min(forecast_data$Q5) - min(forecast_data$Q5) * offset,
            max(forecast_data$Q95) + max(forecast_data$Q95) * offset
          )
        ),
        xaxis = list(
          title = "",
          range = xlimits,
          type = "date",
          tickformat = "%b %d",
          # Show date and time
          dtick = 86400000.0  # 1 day in milliseconds
        ),
        yaxis2 = list(
          title = "[mm / 6 hours]",
          overlaying = "y",
          side = "right",
          range = c(0, max(10, max(forecast_pr_data$PR) + max(forecast_pr_data$PR) * 2)),
          color = "lightblue",
          # Color the second y-axis in blue
          tickfont = list(color = "lightblue")
        ),
        images = pictos_list
      )
      p
      
    } else {
      # No observations currently
      p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
        plotly::config(displayModeBar = FALSE) %>%
        plotly::layout(
          title = list(
            text = "Station currently not operating\n Станция в настоящее время не работает",
            yref = "paper",
            y = 0.5
          )
        )
    }
  } else {
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "Observational record too short for forecast calibration\n Данные наблюдений слишком коротки для калибровки прогнозов", yref = "paper", y = 0.5)
      )
    
  }
  p
}


