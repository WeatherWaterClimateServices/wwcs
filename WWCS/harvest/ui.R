# PREPARE UI
# ------------------------------------------------

# ------------------------------- Dashboard Header

header <- dashboardHeader(title = tags$a(
  tags$img(
    src = 'logo_caritas.png',
    width = "150px",
    height = "20px"
  )
), tags$li(
  class = "dropdown",
  selectInput(
    inputId = "selected_language",
    label = "",
    choices = c(
      "Русский" = "ru",
      "English" = "en",
      "English / Русский" = "en/ru"
    ),
    selected = "en/ru",
    width = "180px"
  )
))


# ------------------------------- Dashboard Sidebar

sidebar <- dashboardSidebar(
  collapsed = TRUE,
  sidebarMenu(
    menuItem("Overview", tabName = "overview", icon = icon("dashboard")),
    sliderInput(
      "rangestat",
      i18n$t("Station Range"),
      min = time_obs_min,
      max = time_obs_max,
      value = time_obs_max - days(20),
      timezone = "UTC"
    ),
    br(),
    sliderInput(
      "reftime",
      i18n$t("Forecast Date"),
      min = time_ifs_min,
      max = time_ifs_max,
      value = start_date_f,
      timezone = "UTC"
    ),
    br(),
    sliderInput(
      "range",
      i18n$t("Satellite Map"),
      min = as.POSIXct(time_noaa_min, tz = "UTC"),
      max = as.POSIXct(time_noaa_max, tz = "UTC"),
      value = as.POSIXct(start_date_noaa, tz = "UTC"),
      timeFormat = "%Y-%m-%d %H-%M-%S",
      step = 21600,
      timezone = "UTC"
    )
  )
)

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
      title = i18n$t("Map"),
      leafletOutput("map") %>% shinycssloaders::withSpinner(color = "lightblue"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE
    ),
    box(
      width = 6,
      title = i18n$t("Harvest"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE,
      br(),
      valueBoxOutput("past_rain"),
      valueBoxOutput("future_rain"),
      valueBoxOutput("frost"),
      valueBoxOutput("status")
      ),
    box(
      width = 6,
      title = i18n$t("Precipitation"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE,
      br(),
      plotlyOutput("plot_rain", height = "45vh") %>% shinycssloaders::withSpinner(color =
                                                                                    "lightblue"),
      br()
    )
  )
)

ui <- dashboardPage(skin = "blue", title = "WWCS - Harvest", header, sidebar, body)
