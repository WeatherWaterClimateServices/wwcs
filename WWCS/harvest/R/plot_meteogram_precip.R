plot_meteogram_precip <- function(id, range, seltime) {
  # FILTER DATA FOR SELECTED FORECAST REFERENCE TIME
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
  
  noaa_tmp <- noaadata %>%
    dplyr::filter(time >= range & siteID == id) %>%
    dplyr::select(c(siteID, time, Precipitation)) %>%
    dplyr::mutate(Precipitation = ifelse(Precipitation <= 0.1, NA, Precipitation)) %>%
    na.omit()
  
  if (nrow(noaa_tmp) > 0) {
    noaa_pr <- noaa_tmp %>%
      rowwise() %>%
      mutate(bins = assign_bins(time)$bin,
             center_time = assign_bins(time)$center_time) %>%
      ungroup() %>%
      group_by(bins, center_time) %>%
      summarize(PR = sum(Precipitation, na.rm = TRUE), )
  } else {
    noaa_pr <- data.frame(
      bins = character(),
      center_time = as.POSIXct(character()),
      PR = numeric()
    )
  }
  
  
  obs_tmp <- obs %>%
    dplyr::filter(time >= range & siteID == id) %>%
    dplyr::select(c(time, Precipitation)) %>%
    dplyr::mutate(Precipitation = ifelse(Precipitation <= 0.1, NA, Precipitation)) %>%
    na.omit()
  
  if (nrow(obs_tmp) > 0) {
    obs_pr <- obs_tmp %>%
      rowwise() %>%
      mutate(bins = assign_bins(time)$bin,
             center_time = assign_bins(time)$center_time) %>%
      ungroup() %>%
      group_by(bins, center_time) %>%
      summarize(PR = sum(Precipitation, na.rm = TRUE), )
    
  } else {
    obs_pr <- data.frame(
      bins = character(),
      center_time = as.POSIXct(character()),
      PR = numeric()
    )
  }
  
  frcst_tmp <- dmo %>%
    dplyr::filter(as.Date(reftime) == as.Date(seltime) & siteID == id) %>%
    dplyr::select(c(time, IFS_PR_mea, siteID)) %>%
    dplyr::rename(Precipitation = IFS_PR_mea) %>%
    dplyr::mutate(Precipitation = ifelse(Precipitation <= 0.1, NA, Precipitation)) %>%
    na.omit()
  
  if (nrow(frcst_tmp) > 0) {
    frcst_pr <- frcst_tmp %>%
      rowwise() %>%
      mutate(bins = assign_bins(time)$bin,
             center_time = assign_bins(time)$center_time) %>%
      ungroup() %>%
      group_by(bins, center_time) %>%
      summarize(PR = sum(Precipitation, na.rm = TRUE), )
  } else {
    frcst_pr <- data.frame(
      bins = character(),
      center_time = as.POSIXct(character()),
      PR = numeric()
    )
  }
  
  # Define color scales
  color_scale_fill <- c(
    "Satellite" = "lightblue",
    "Station" = "blue",
    "Forecast" = "darkblue"
  )
  color_scale_line <- color_scale_fill
  
  forecast_start <- min(frcst_pr$center_time)
  forecast_end <- max(frcst_pr$center_time)
  
  # Define the plot
  p <-
    plotly::plot_ly()
  
  if (nrow(frcst_pr) > 0) {
    p <- p  %>%
      # Add the first ribbon layer (Q5 to Q95)
      plotly::add_bars(
        x = ~ frcst_pr$center_time,
        y = ~ frcst_pr$PR,
        marker = list(color = color_scale_fill["Forecast"]),
        name = 'Forecast',
        hovertemplate = paste(
          '<b>Time</b>: %{x|%b %d %H:%M} UTC<br>',
          '<b>Precipitation</b>: %{y:.1f}<br>'
        )
      )
  }
  
  if (nrow(obs_pr) > 0) {
    p <- p %>%
      # Add the first ribbon layer (Q5 to Q95)
      plotly::add_bars(
        x = ~ obs_pr$center_time,
        y = ~ obs_pr$PR,
        marker = list(color = color_scale_fill["Station"]),
        name = 'Station',
        hovertemplate = paste(
          '<b>Time</b>: %{x|%b %d %H:%M} UTC<br>',
          '<b>Precipitation</b>: %{y:.1f}<br>'
        ),
        opacity = 0.5
      )
  }
  
  if (nrow(noaa_pr) > 0) {
    p <- p %>%
      plotly::add_bars(
        x = ~ noaa_pr$center_time,
        y = ~ noaa_pr$PR,
        marker = list(color = color_scale_fill["Satellite"]),
        name = 'Satellite',
        hovertemplate = paste(
          '<b>Time</b>: %{x|%b %d %H:%M} UTC<br>',
          '<b>Precipitation</b>: %{y:.1f}<br>'
        ),
        opacity = 0.5,
        visible = "legendonly"
      )
  }
  

  if (nrow(frcst_pr) == 0 &
      nrow(obs_pr) == 0 ) {
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(title = list(text = "No data available", yref = "paper", y = 0.5))
  } else {
    p <- p %>%
      layout(
        title = list(
          text = id,
          x = 0.5,
          font = list(size = 15)
        ),
        yaxis = list(title = "Precipitation [mm/h]"),
        xaxis = list(title = ""),
        legend = list(
          bgcolor = 'transparent',
          font = list(size = 15),
          x = 0.1,
          y = 0.9,
          xanchor = 'left',
          yanchor = 'top'
        ),
        hoverlabel = list(
          font = list(size = 15, color = "white"),
          bordercolor = "transparent"
        ),
        font = list(size = 15, color = "black"),
        autosize = TRUE,
        shapes = list(
          list(
            type = "rect",
            x0 = forecast_start,
            x1 = forecast_end,
            y0 = 0,
            y1 = max(c(noaa_pr$PR, obs_pr$PR, frcst_pr$PR), na.rm = TRUE),
            fillcolor = "rgba(128, 128, 128, 0.2)",
            # Grey color with transparency
            line = list(color = "rgba(128, 128, 128, 0.2)"),
            layer = "below"
          )
        ),
        annotations = list(
          x = forecast_start + difftime(forecast_end, forecast_start, units = "secs") / 2,
          y = 0.9 * max(c(noaa_pr$PR, obs_pr$PR, frcst_pr$PR), na.rm = TRUE),
          text = "Forecast Range",
          showarrow = FALSE,
          font = list(size = 14, color = "black")
        )
      )
  }
  p
}


