plot_warning <- function(id, type, threshold, seldate) {
  if (type == "district") {
    levels <- ews_district %>%
      dplyr::filter(district == id) %>%
      dplyr::filter(reftime == seldate) %>%
      dplyr::mutate(level = .data[[threshold]]) %>%
      dplyr::mutate(name = district) %>%
      dplyr::mutate(level_number = ifelse(level == "green", 1, ifelse(level == "yellow", 2, 3))) %>%
      dplyr::mutate(level_text = level) %>%
      dplyr::top_n(5)
    
  } else if (type == "station") {
    levels <- ews_station %>%
      dplyr::filter(siteID == id) %>%
      dplyr::filter(reftime == seldate) %>%
      dplyr::mutate(level = .data[[threshold]]) %>%
      mutate(name = siteID) %>%
      dplyr::mutate(level_number = ifelse(level == "green", 1, ifelse(level == "yellow", 2, 3))) %>%
      dplyr::mutate(level_text = level) %>%
      dplyr::top_n(5)
    
  }
  
  
  plt <- levels %>%
    ggplot(aes(x = date, y = level_number, fill = level_text)) +
    theme_classic() +
    scale_fill_manual(values = ews_colors, name = "") +
    labs(x = "", y = "Warning Level", fill = "") +
    geom_bar(stat = "identity") +
    ggtitle(levels$name[1]) +
    theme(
      plot.title = element_text(
        hjust = 0.5,
        size = 14,
        face = "bold"
      ),
      legend.text = element_text(size = 12),
      legend.title = element_text(size = 12),
      axis.text.x = element_text(size = 12),
      axis.text.y = element_blank(),
      axis.title.y = element_text(size = 12),
      legend.position = "none"
    )
  
  return(plt)
}