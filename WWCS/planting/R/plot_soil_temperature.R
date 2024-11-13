plot_soil_temperature <- function(soildata, id, low, high, period, range) {
  frcstdata <- emosdata %>%
    dplyr::filter(reftime == period, siteID == id) %>%
    dplyr::rename(day = time) %>%
    dplyr::select(c(IFS_Temperature, IFS_Temperature_std, day)) %>%
    dplyr::mutate(in_range = ifelse(IFS_Temperature >= low &
                                      IFS_Temperature <= high, TRUE, FALSE))  %>%
    na.omit() %>%
    distinct()
  
  seldata <- soildata %>%
    dplyr::filter(siteID == id, day >= range) %>%
    dplyr::select(day, Temperature, TemperatureProxy) %>%
    dplyr::rename("Soil Temperature" = Temperature, "Soil Proxy" = TemperatureProxy)
  
  if (nrow(frcstdata) > 0) {
    plotdata <- frcstdata %>%
      dplyr::rename("Soil Forecast" = IFS_Temperature) %>%
      dplyr::select(c("Soil Forecast", day)) %>%
      dplyr::full_join(seldata) %>%
      tidyr::gather("variable", "value", -day, na.rm = T)
    if (any(frcstdata$in_range)) {
      color_scale_line <- setNames(
        c("gray", "black", "darkgreen"),
        c("Soil Proxy", "Soil Temperature", "Soil Forecast")
      )
      legend_labels <- c("Soil Proxy", "Soil Temperature", "Soil Forecast")
      color_fill <- "darkgreen"
    } else {
      color_scale_line <- setNames(c("gray", "black", "red"),
                                   c("Soil Proxy", "Soil Temperature", "Soil Forecast"))
      legend_labels <- c("Soil Proxy", "Soil Temperature", "Soil Forecast")
      color_fill <- "red"
    }
  } else if (nrow(seldata) > 0) {
    plotdata <- seldata %>%
      tidyr::gather("variable", "value", -day, na.rm = T)
    
    color_scale_line <- setNames(c("gray", "black"), c("Soil Proxy", "Soil Temperature"))
    legend_labels <- c("Soil Proxy", "Soil Temperature")
  } else {
    plotdata <- data.frame()
  }
  
  # Check if any in_range is true then use green, red otherwise
  
  print(plotdata)
  
  if (nrow(plotdata) > 0) {
    p <- plot_ly() %>%
      add_lines(
        data = plotdata,
        x = ~ day,
        y = ~ value,
        color = ~ variable,
        colors = color_scale_line,
        line = list(width = 2),
        name = ~ variable
      ) %>%
      layout(
        title = list(
          text = id,
          x = 0.5,
          font = list(size = 15)
        ),
        yaxis = list(
          title = "Soil Temperature [°C]",
          titlefont = list(size = 15),
          tickfont = list(size = 15)
        ),
        xaxis = list(
          title = "",
          titlefont = list(size = 15),
          tickfont = list(size = 15)
        ),
        legend = list(bgcolor = 'transparent', font = list(size = 15)),
        shapes = list(
          list(
            type = "rect",
            x0 = min(plotdata$day),
            x1 = max(plotdata$day),
            y0 = low,
            y1 = high,
            fillcolor = "lightgreen",
            opacity = 0.4,
            line = list(width = 0)
          )
        )
      )
    
    if (nrow(frcstdata) > 0) {
      p <- p %>%
        add_ribbons(
          data = frcstdata,
          x = ~ day,
          ymin = ~ IFS_Temperature - IFS_Temperature_std,
          ymax = ~ IFS_Temperature + IFS_Temperature_std,
          fillcolor = color_fill,
          opacity = 0.2,
          line = list(color = color_fill, width = 1),
          name = "Uncertainty"
        )
    }
  } else {
    # No records
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "No records for this location available\n Записи для этого места отсутствуют", yref = "paper", y = 0.5)
      )
  }
  
  return(p)
}