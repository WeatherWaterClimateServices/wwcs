# PREPARE UI
# ------------------------------------------------

# ------------------------------- Dashboard Header

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


sidebar <- dashboardSidebar(collapsed = TRUE, sidebarMenu(
  menuItem(
    "Overview",
    tabName = "overview",
    icon = icon("dashboard")),
    sliderInput(
      "range",
      i18n$t("Range Observations"),
      min = as.Date(time_obs_min),
      max = as.Date(time_obs_max),
      value = start_date_o,
      timeFormat = "%Y-%m-%d"
    ),
    br(),
    sliderInput(
      "period",
      i18n$t("Forecast Time"),
      min = as.Date(time_range_min),
      max = as.Date(time_range_max),
      value = start_date_f,
      timeFormat = "%Y-%m-%d"
    ),
  br()
  #,menuItem("Site Parameters", tabName = "control", icon = icon("th"))
))

# ------------------------------- Dashboard Body

body <- dashboardBody(
  shiny.i18n::usei18n(i18n),
  tags$style(type = "text/css", "#map {height: calc(82vh) !important;}; "),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "caritas.css")
  ),
  fluidRow(
    box(
      width = 6,
      title = i18n$t("STATION MAP"),
      leafletOutput("map") %>% shinycssloaders::withSpinner(color = "lightblue"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE
    ),
    box(
      width = 6,
      title = i18n$t("PLANTING"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE,
      selectInput(
        "croptype",
        label = "",
        width = "180px",
        choices = c("Winter Wheat" , "Spring Wheat" , "Spring Potato",
                    "Summer Potato"),
        selected = "winter_wheat"
      ),
      br(),
      br(),
      valueBoxOutput("status_plant"),
      valueBoxOutput("criteria_plant"),
      valueBoxOutput("criteria2_plant"),
      br()
    ),
    box(
      width = 6,
      title = i18n$t("SOIL TEMPERATURE"),
      plotlyOutput("plot_soil", height = "40vh") %>% shinycssloaders::withSpinner(color =
                                                                                    "lightblue"),
      br(),
      br(),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE
    )
  )
)

ui <- dashboardPage(skin = "blue",
                    title = tags$head(tags$link(rel="icon", 
                                                href="data:image/x-icon;base64,AAABAAEAEBAQAAEAetc", 
                                                type="image/x-icon")
                    ),
                    header,
                    sidebar,
                    body)
