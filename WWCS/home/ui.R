library(shiny)
library(shinyBS)
library(shinyLP)
library(shinythemes)

source('/opt/shiny-server/WWCS/.Rprofile')

# Define UI for application
shinyUI(# Include a fliudPage above the navbar to incorporate a icon in the header
  fluidPage(
    list(tags$head(
      HTML('<link rel="icon", href="meteoswiss.png",
                        type="image/png" />')
    )),
    div(style = "padding: 0px 0px; width: '100%'",
        titlePanel(
          title = "", windowTitle = "WWCS"
        )),
    
    navbarPage(
      title = "WWCS",
      inverse = F,
      # for diff color view
      theme = shinytheme("flatly"),
      
      tabPanel(
        "Home",
        icon = icon("home"),
        jumbotron(
          "Weather, Water and Climate Services (WWCS)",
          div(
            img(src = "meteoswiss.png", style = "width: 80px"),
            "Access page for prototype services developed by MeteoSwiss under the WWCS Tajikistan project",
            style = "font-size: 22px"
          ),
          button = FALSE
        ),
        hr(),
        fluidRow(
          column(
            4,
            align = "center",
            thumbnail_label(
              image = "monitor-small.png",
              label = 'WWCS-Dashboard',
              content = 'Forecasting dashboard for Tajik Hydromet',
              button_link = paste0('https://', wwcs_domain,'/dashboard'),
              button_label = 'Click me'
            )
          ),
          column(
            4,
            align = "center",
            thumbnail_label(
              image = 'cold-wave-small.png',
              label = 'Cold and Heat Early Warning',
              content = 'Control Panel for Early Warning',
              button_link = paste0('https://', wwcs_domain,'ews'), 
              button_label = 'Click me'
            )
          ),
          column(
            4,
            align = "center",
            thumbnail_label(
              image = 'water-system-small.png',
              label = 'Irrigation Scheduling',
              content = 'Irrigation service for reduced water consumption and yield increase.',
              button_link = paste0('https://', wwcs_domain ,'/irrigation'),
              button_label = 'Click me'
            )
          ),
          column(
            4,
            align = "center",
            thumbnail_label(
              image = "planting-small.png",
              label = 'Planting Scheduling',
              content = 'Service to advice on optimal sowing dates.',
              button_link = paste0('https://', wwcs_domain,'/planting'),
              button_label = 'Click me'
            )
          ),
          column(
            4,
            align = "center",
            thumbnail_label(
              image = "harvest-small.png",
              label = 'Harvest Scheduling',
              content = 'Service to advice on optimal harvesting dates.',
              button_link = paste0('https://', wwcs_domain,'/harvest'),
              button_label = 'Click me'
            )
          ),
          column(
            4,
            align = "center",
            thumbnail_label(
              image = "api-small.png",
              label = 'Service Interface',
              content = 'Application Programming Interface (API) of the services',
              button_link = paste0('https://', wwcs_domain,'/api'),
              button_label = 'Click me'
            )
          )
        )
      )
    )
  ) # end of fluid page
) # end of shiny