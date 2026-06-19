plot_maintenance <- function(data, id, desktop) {
  colors <-
    setNames(c("orange",
               "darkgreen",
               "purple"),
             c("U_Solar",
               "signalStrength",
               "U_Battery"))
  
  labels <- setNames(c("mV", "db", "mV"),
                     c("ta",
                       "rh",
                       "p"))
  
  plt_data <- data %>%
    dplyr::mutate(time = lubridate::ymd_hms(timestamp)) %>%
    dplyr::select(c("U_Solar", "signalStrength", "U_Battery"), time) %>%
    tidyr::gather("variable", "value", -time, na.rm = T) %>%
    dplyr::mutate(group = cumsum(c(difftime(time, lag(time, default = first(time)), units = "secs")) > 700)) 

  if (nrow(plt_data) > 0) {
    plt <-
      plt_data %>% ggplot(aes(x = time, y = value, color = variable, group = group)) +
      scale_color_manual(name = '', values = colors) +
      geom_line() +
      theme_light() +
      guides(fill = "none") +
      theme(legend.position = "none") +
      guides(fill = "none") +
      labs(x = "", y = "") +
      facet_wrap(~variable, scales = "free_y", ncol = 1) +
      theme(
        plot.title = element_text(hjust = 0.5, size = 12),
        legend.text = element_text(size = 12),
        axis.text.x = element_text(size = 10),
        axis.text.y = element_text(size = 10),
        axis.title.y = element_text(size = 10),
        strip.background = element_rect(colour = "white", fill = "white"),
        strip.text = element_text(colour = 'black')
      ) +
      theme(legend.position = "none")
    
    
    p <- plotly::ggplotly(plt,
                          orientation = "h") %>%
      plotly::config(
        modeBarButtonsToRemove = c(
          "toggleSpikelines",
          "autoScale2d",
          "hoverClosestCartesian",
          "hoverCompareCartesian"
        ),
        displaylogo = FALSE
      ) 
    
    if (desktop) {
     # p <- p %>% plotly::layout(width = 800, height = 600, autosize = F, margin = list(l = 50, r = 50, b = 50, t = 50))
      
      p <- p %>% plotly::layout(autosize = T)
      
    } else {
      p <- p %>% plotly::layout(autosize = T)
    }
    
    
  } else {
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(title = list(text = "No data available",
                                  yref = "paper",
                                  y = 0.5))
  }
  p
}