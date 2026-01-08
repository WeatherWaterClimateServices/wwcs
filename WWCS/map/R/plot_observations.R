plot_observations <- function(data, id, var){
  colors <-
    setNames(
      c(
        "#c92118",
        "lightblue",
        "cadetblue" ,
        "orange",
        "darkgreen",
        "purple",
        "darkblue",
        "darkblue",
        "#c92118",
        "lightblue",
        "cadetblue" ,
        "orange",
        "darkgreen",
        "purple",
        "darkblue",
        "darkblue",
        "#c92118",
        "cadetblue" ,
        "darkgreen",
        "darkblue",
        "darkblue",
        "#c92118",
        "lightblue",
        "cadetblue" ,
        "orange",
        "darkgreen",
        "purple",
        "darkblue",
        "darkblue",
        "orange",
        "darkgreen",
        "purple",
        "darkblue",
        "darkblue"
      ),
      c(
        "ta",
        "rh",
        "p",
        "U_Solar",
        "signalStrength",
        "U_Battery",
        "Precipitation",
        "Evapotranspiration",
        "logger_ta",
        "logger_rh",
        "Pressure_mean",
        "Solar_mean",
        "Signal_mean",
        "Battery_mean",
        "Precipitation_mean",
        "Evapotranspiration_mean",
        "Charge_Battery",
        "Temp_Battery",
        "U_Battery1",
        "compass",
        "lightning_count",
        "lightning_dist",
        "pr",
        "rad",
        "wind_speed",
        "wind_dir",
        "wind_gust",
        "wind_speed_E",
        "wind_speed_N",
        "vapour_press",
        "ts10cm",
        "tilt_x",
        "tilt_y",
        "Temp_Humisens"
      )
    )
  
  labels <- setNames(
    c("°C", "%", "mb", "mV", "db", "mV", "°C", "%", "mV", "°C", "mV",
      "°", "", "km", "mm", "W/m2", "m/s", "°", "m/s", "m/s", "m/s", "mb", "°C", "°", "°", "°C"),
    c(
      "ta",
      "rh",
      "p",
      "U_solar",
      "signalStrength",
      "U_battery",
      "logger_ta",
      "logger_rh",
      "Charge_Battery",
      "Temp_Battery",
      "U_Battery1",
      "compass",
      "lightning_count",
      "lightning_dist",
      "pr",
      "rad",
      "wind_speed",
      "wind_dir",
      "wind_gust",
      "wind_speed_E",
      "wind_speed_N",
      "vapour_press",
      "ts10cm",
      "tilt_x",
      "tilt_y",
      "Temp_Humisens"
    )
  )
  
  plt_data <- data %>%
              dplyr::mutate(time = lubridate::ymd_hms(timestamp)) %>%
              dplyr::select(var, time) %>% 
              tidyr::gather("variable","value",-time, na.rm = T) 
  
  if (nrow(plt_data) > 0) {
    plt <- plt_data %>% ggplot(aes(x = time, y = value, color = variable)) +
      scale_color_manual(name = '', values = colors) +
      geom_line() +
      theme_light() +
      guides(fill = "none") +
      theme(legend.position = "none") + 
      guides(fill = "none") +       
      labs(x = "", y = "") +
      theme(plot.title = element_text(hjust = 0.5,size = 12),
            legend.text = element_text(size = 12),
            axis.text.x = element_text(size = 10),
            axis.text.y = element_text(size = 10, color = colors[var]),
            axis.title.y = element_text(size = 10, color = colors[var])) +
      theme(legend.position = "none")
    
    
    p <- plotly::ggplotly(plt,
                          orientation = "h",
                          tooltip = c("value", "variable", "time")) %>%
      plotly::config(
        modeBarButtonsToRemove = c(
          "toggleSpikelines",
          "autoScale2d",
          "hoverClosestCartesian",
          "hoverCompareCartesian"
        ),
        displaylogo = FALSE
      ) %>%
      plotly::layout(autosize = T)
    
    
    
  } else {
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "No data available",
                     yref = "paper",
                     y = 0.5)
      )
  }
  p
}
