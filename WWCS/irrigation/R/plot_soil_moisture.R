plot_soil_moisture <- function(irrigation_data, id) {
   
   if ((nrow(irrigation_data()) > 0)) {
     soil_data <- irrigation_data() %>%
       dplyr::filter(siteID == id & date <= Sys.Date()) %>%
       dplyr::select(c(PHIc, WP, PHIt, FC, date)) %>%
       dplyr::rename(
         "Soil Moisture" = PHIc,
         "Wilting Point" = WP,
         "Threshold Moisture" = PHIt,
         "Field Capacity" = FC,
         day = date
       ) %>%
       tidyr::gather("variable", "value", -day, na.rm = T)
   } else {
     soil_data <- data_frame()
   }
   
  if (nrow(soil_data) > 0) {
    plt <- soil_data %>%
      ggplot(aes(x = day, y = value, color = variable)) +
      theme_classic() +
      ylab("Soil Moisture Content [%]") + xlab("") +
      geom_line(size = 1) +
      scale_color_manual(
        name = '',
        values = c("#deebf7", "#9ecae1", "#3182bd", "black"),
        breaks = c(
          "Wilting Point",
          "Threshold Moisture",
          "Field Capacity",
          "Soil Moisture"
        )
      ) +
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
        yaxis = list(size = 5)
      )
    
  } else {
    # No records
    p <-  plotly::plotly_empty(type = "scatter", mode = "markers") %>%
      plotly::config(displayModeBar = FALSE) %>%
      plotly::layout(
        title = list(text = "No records for this location available\n Записи для этого места отсутствуют",
                     yref = "paper",
                     y = 0.5)
      )
  }
  
  return(p)
}
