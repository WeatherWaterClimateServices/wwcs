plot_water_balance <- function(irrigation_data, id) {
  
  if ((nrow(irrigation_data()) > 0)) {
    irrigation_plot <- irrigation_data() %>%
      dplyr::filter(siteID == id & date <= Sys.Date()) %>%
      dplyr::select(date, Ineed, Iapp, Precipitation) %>%
      dplyr::mutate(Ineed = -Ineed) %>%
      dplyr::rename(Need = Ineed, Irrigation = Iapp) %>%
      tidyr::gather("variable", "value", -date, na.rm = T)
  } else {
    irrigation_plot <- data_frame()
  }
  

  
  if (nrow(irrigation_plot) > 0) {
    plt <- irrigation_plot %>%
      ggplot(aes(x = date, y = value, fill = variable)) +
      theme_classic() +
      # ylab(expression(Water ~ balance ~ (m ^ {
      #   3
      # }))) +
      ylab("mm") +
      xlab("") +
      geom_bar(stat = "identity")  +
      scale_fill_manual(values = irrigation_colors, name = "") +
      theme(plot.title = element_text(hjust = 0.5)) +
      theme(
        plot.title = element_text(hjust = 0.5, size = 10),
        legend.text = element_text(size = 10),
        axis.text.x = element_text(size = 10),
        axis.title.x = element_text(size = 10),
        axis.text.y = element_text(size = 10),
        axis.title.y = element_text(size = 10)
      )
    
    font <- list(size = 15,
                 color = "white")
    label <- list(bordercolor = "transparent",
                  font = font)
    
    p <- plotly::ggplotly(plt, orientation = "h") %>%
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
        title = font
      )
    
  } else {
    # No records
    p <-
      plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "No records for this location available\n Записи для этого места отсутствуют",
                     yref = "paper",
                     y = 0.5)
      )
  }
  
  return(p)
}
