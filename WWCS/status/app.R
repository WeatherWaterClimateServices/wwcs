library(shiny)
library(tidyverse)
library(lubridate)
library(highcharter)
library(jsonlite)

ROOT_DIR <- normalizePath(getwd(), mustWork=TRUE)
while (!file.exists(file.path(ROOT_DIR, ".git"))) {
  parent <- dirname(ROOT_DIR)
  if (parent == ROOT_DIR) break
  ROOT_DIR <- parent
}

ui <- fluidPage(
  titlePanel('Shiny Server Monitor'),
  highchartOutput('user_chart_today')
)

server <- function(input, output, session) {
  
  filter_user_data_today <- reactive({
    Dat <- readRDS(file.path(ROOT_DIR, "WWCS/status/sysLoad.rds"))
    
    Dat %>%
      mutate(hour = as.POSIXct(trunc(Time, 'mins'))) %>%
      filter(hour >= as.Date(Sys.time()) - lubridate::days(50)) %>%
      group_by(hour, app) %>%
      filter(Time == max(Time)) %>%
      slice(1) %>%
      ungroup %>%
      arrange(hour) %>%
      mutate(hour = datetime_to_timestamp(hour))    
  })
  
  output$user_chart_today <- renderHighchart({
    filter_user_data_today() %>%
      hchart(hcaes(x = hour, y = usr, group = app), type = 'line') %>%
      hc_xAxis(type = 'datetime') %>%
      hc_tooltip(shared = TRUE) %>%
      hc_add_theme(hc_theme_smpl())
  })
  
}

shinyApp(ui = ui, server = server)
