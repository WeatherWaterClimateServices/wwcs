plot_observations <- function(obs, id, period, var) {
  if (var == "Precipitation" || var == "Evapotranspiration") {
    var_filter = c(paste0(var))
  } else {
    var_filter = c(paste0(var, "_mean"))
  }
  
  if ("time" %in% colnames(obs)) {
    observation_data <- obs %>%
      filter(time >= as.POSIXct(period, tz = "UTC") &
               siteID == id) %>%
      dplyr::select(var, time)  %>% tidyr::gather("variable", "value",-time, na.rm = T)
    
    filter_data <- obs %>%
      filter(time >= as.POSIXct(period, tz = "UTC") &
               siteID == id) %>%
      dplyr::select(var_filter, time) %>%
      tidyr::gather("variable", "value",-time, na.rm = T)
    
    if (dim(observation_data)[1] > 0) {
      xlimits <- c(min(observation_data$time),
                   max(observation_data$time))
      
      ylimits <- c(
        min(observation_data$value) - 0.3 * (sd(observation_data$value)),
        max(observation_data$value) + 0.3 * (sd(observation_data$value))
      )
      
      p <- plot_ly() %>%
        add_lines(
          data = observation_data,
          x = ~ time,
          y = ~ value,
          color = ~ variable,
          colors = colors,
          line = list(
            width = 2,
            dash = "solid",
            color = colors[observation_data$variable]
          ),
          opacity = 0.4,
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M} UTC<br>',
            '<b>Value</b>: %{y:.1f}<br>'
          )
        ) %>%
        add_lines(
          data = filter_data,
          x = ~ time,
          y = ~ value,
          color = ~ variable,
          colors = colors,
          line = list(
            width = 2,
            dash = "solid",
            color = colors[filter_data$variable]
          ),
          name = "Smoothed",
          hovertemplate = paste(
            '<b>Time</b>: %{x|%b %d %H:%M} UTC<br>',
            '<b>Value</b>: %{y:.1f}<br>'
          )
        ) %>%
        layout(
          xaxis = list(
            title = "",
            range = xlimits,
            tickformat = "%b %d"
          ),
          yaxis = list(
            title = labels[var],
            range = ylimits,
            tickfont = list(color = colors[var]),
            titlefont = list(color = colors[var])
          ),
          xaxis = list(tickfont = list(size = 10)),
          yaxis = list(tickfont = list(size = 10)),
          showlegend = FALSE
        )
      
      p
      
    } else {
      plot.new()
      
    }
  } else {
    plot.new()
  }
}