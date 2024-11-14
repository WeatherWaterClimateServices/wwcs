header <- dashboardHeader(title = tags$a(
  tags$img(
    src = 'logo_caritas.png',
    width = "150px",
    height = "20px"
  )
),
tags$li(
  class = "dropdown",
  selectInput(
    inputId = "selected_language",
    label = "",
    choices = c(
      "Русский" = "ru",
      "English" = "en",
      "English / Русский" = "en/ru"
    ),
    selected = "en",
    width = "180px"
  )
))

# ------------------------------- Dashboard Sidebar

sidebar <-
  dashboardSidebar(sidebarMenu(
    menuItem(i18n$t("Overview"), tabName = "overview", icon = icon("dashboard")),
    menuItem(i18n$t("Site Parameters"), tabName = "control", icon = icon("th")),
    menuItem(i18n$t("Irrigation"), tabName = "manual", icon = icon("water"))
  ))


# ------------------------------- Dashboard Body


body <- dashboardBody(
  shiny.i18n::usei18n(i18n),
  tags$style(type = "text/css", "#map {height: calc(82vh) !important;}; "),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "caritas.css")
  ),
  shinydashboard::tabItems(
    shinydashboard::tabItem("overview",
                            fluidRow(
                              box(
                                width = 6,
                                title = i18n$t("Map"),
                                leafletOutput("map")  %>% shinycssloaders::withSpinner(color =
                                                                                         "lightblue"),
                                collapsible = TRUE,
                                status = "primary",
                                solidHeader = TRUE
                              ),
                              box(
                                width = 5,
                                title = i18n$t("Irrigation Advice"),
                                valueBoxOutput("irradvice"),
                                valueBoxOutput("irrvalue")                              ),
                              box(
                                width = 6,
                                title = i18n$t("Water Balance"),
                                plotlyOutput("plot_balance", height = "25vh") %>% shinycssloaders::withSpinner(color =
                                                                                                                 "lightblue"),
                                collapsible = TRUE,
                                status = "primary",
                                solidHeader = TRUE,
                                
                              ),
                              box(
                                width = 6,
                                title = i18n$t("Soil Moisture Balance"),
                                plotlyOutput("plot_soil", height = "25vh") %>% shinycssloaders::withSpinner(color =
                                                                                                              "lightblue"),
                                br(),
                                br(),
                                collapsible = TRUE,
                                status = "primary",
                                solidHeader = TRUE
                              )
                            )),
    shinydashboard::tabItem(
      "control",
      box(
        width = 12,
        title = i18n$t("Site Parameters"),
        actionButton("edit_button", "Edit", icon("edit"), class = "btn-primary"),
        br(),
        br(),
        br(),
        DT::dataTableOutput("table"),
        collapsible = TRUE,
        status = "primary",
        solidHeader = TRUE
      )
    ),
    shinydashboard::tabItem("manual",
                            fluidRow(
                              box(
                                width = 4,
                                title = i18n$t("Manual Ingestion"),
                                selectInput(
                                  inputId = "selectid",
                                  label = "Select Site",
                                  choices = sites_map_ui$siteID,
                                  selected = "LAKH012-3",
                                  width = 200
                                ),
                                br(),
                                br(),
                                numericInput(
                                  width = "300px",
                                  "irrigationingest",
                                  label = "Irrigated Water [mm]",
                                  min = 0,
                                  max = 300,
                                  value = c(0),
                                  step = 0.1
                                ),
                                br(),
                                br(),
                                numericInput(
                                  width = "300px",
                                  "precipingest",
                                  label = "Precipitation [mm]",
                                  min = 0,
                                  max = 300,
                                  value = c(0),
                                  step = 0.1
                                ),
                                br(),
                                br(),
                                fluidRow(column(
                                  width = 12,
                                  dateInput(
                                    "dateingest",
                                    width = "300px",
                                    label = "Select date",
                                    value = Sys.Date() - days(1)
                                  )
                                )),
                                br(),
                                br(),
                                mainPanel(width = 8,
                                          verbatimTextOutput("apiresponse")),
                                br(),
                                div(
                                  style = "display:inline-block; float:right",
                                  actionButton("submit_data", label = "Submit", class = "btn-primary")
                                ),
                                br(),
                                br(),
                                collapsible = TRUE,
                                status = "primary",
                                solidHeader = TRUE
                              ),
                              box(
                                width = 6,
                                h4("Insert irrigation applied (in mm)"),
                                title = i18n$t("Automatic Ingestion"),
                                mainPanel(width = 12,
                                          verbatimTextOutput("apiOutput")),
                                br(),
                                br(),
                                h4("Get irrigation advice (in mm)"),
                                mainPanel(width = 12,
                                          verbatimTextOutput("api2Output"))
                              )
                            ))
  )
)



ui <- tagList(
  # Add favicon
  tags$head(
    tags$link(rel = "shortcut icon", href = "irrigation_favicon.ico")
  ),
  
  # Dashboard page layout
  dashboardPage(
    skin = "blue",
    title = "WWCS - Irrigation",
    header,
    sidebar,
    body
  )
)
# Wrap your UI with secure_app
# ui <- secure_app(ui)
