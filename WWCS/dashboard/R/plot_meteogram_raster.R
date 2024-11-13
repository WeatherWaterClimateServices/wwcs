plot_meteogram_raster <- function(xy){

    IFS_T_mea <- as.vector(raster::extract(gemos_mea, xy))
    IFS_T_std <- as.vector(raster::extract(gemos_std, xy))
    
    a <- stringr::str_sub(names(gemos_mea), 2, 20)
    modify_time <- function(input_string) {
      if (stringr::str_length(input_string) < 11) {
        return(paste0(input_string, ".00.00.00"))
      } else {
        return(input_string)
      }
    }
    
    # Use lapply to apply the modification function to each string in the array
    b <- lapply(a, modify_time) %>% unlist()
    time <- as.POSIXct(b, format = "%Y.%m.%d.%H.%M.%S")
    
    forecast_data <-
      list("WWCS" = IFS_T_mea,
           "time" = time) %>%
      as_tibble() %>%
      tidyr::gather("variable","value",-time, na.rm = T) %>%
      dplyr::as_tibble()  %>%
      mutate(Q5 = qnorm(0.05, mean = value, sd = IFS_T_std),
             Q25 = qnorm(0.25, mean = value, sd = IFS_T_std),
             Q75 = qnorm(0.75, mean = value, sd = IFS_T_std),
             Q95 = qnorm(0.95, mean = value, sd = IFS_T_std))
    
    
    
    xlimits <- c(min(time),
                 max(time))
    
    color_scale_fill <- setNames(c("red"),
                                 c("WWCS"))
    
    color_scale_line <- setNames(c("darkred"),
                                 c("WWCS"))
    
    legend_labels <- c("WWCS forecast")
    
    plt <- forecast_data %>% 
      ggplot(aes(x=time)) +
      scale_color_manual(name='', labels = legend_labels, 
                         values = color_scale_line) + 
      scale_fill_manual(name='', values = color_scale_fill) + 
      geom_ribbon(aes(ymin=Q5, ymax=Q95, fill=variable), alpha=0.2) +
      geom_ribbon(aes(ymin=Q25, ymax=Q75, fill=variable), alpha=0.5) +
      geom_line(aes(y = value, color = variable)) +
      labs(y = "°C", x= "") +
      scale_x_datetime(limits = xlimits, expand = c(0,0), date_breaks = "1 days", date_labels = "%b %d") +
      theme_light() + guides(fill = "none") + 
      theme(plot.title = element_text(hjust = 0.5,size=18),
            legend.text = element_text(size=10),
            axis.text.x = element_text(size = 10),axis.title.x = element_text(size = 10),
            axis.text.y = element_text(size = 10),axis.title.y = element_text(size = 10),
            legend.box.background = element_rect(fill='transparent')) +
      scale_alpha(guide = 'none')  
    
  
    # Create plotly object
    
    font <- list(size = 15,
                 color = "white")
    label <- list(bordercolor = "transparent",
                  font = font)
    
    p <- plotly::ggplotly(plt, orientation = "h",
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
        )
      )
    
    p$x$data[[3]]$text <-  paste0(round(forecast_data$value, digits = 2), "°C \n", forecast_data$variable)
    p$x$data[[3]]$name <- "WWCS Forecast"
    
    p
 
}
    

