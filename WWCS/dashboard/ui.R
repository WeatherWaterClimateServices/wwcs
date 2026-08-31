# ------------------------------- Dashboard Header


header <- dashboardHeader(title = tags$a(
  tags$img(
    src = 'logo_hydromet.png',
    width = "90px",
    height = "90px"
  )
)
,
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
    selected = "en/ru",
    width = "180px"
  )
))

# ------------------------------- Dashboard Sidebar
# ctx is the list returned by ui_context() (global.R), rebuilt on every page
# request. 

sidebar <- function(ctx) {
  dashboardSidebar(
    width = 350,
    collapsed = TRUE,
    sidebarMenu(),
    sliderInput(
      "period_f",
      i18n$t("Forecast Time"),
      min = ctx$f_min_date,
      max = ctx$f_max_date,
      value = ctx$start_date_f,
      timeFormat = "%Y-%m-%d"
    ),
    sliderInput(
      "period_o",
      i18n$t("Observation Time"),
      min = as.Date(ctx$time_range_o$min),
      max = as.Date(ctx$time_range_o$max),
      value = as.Date(ctx$start_date_o),
      timeFormat = "%Y-%m-%d"
    ),
    checkboxInput(
      "ecmwf",
      label = i18n$t("Show raw forecast"),
      value = FALSE
    ),
    checkboxInput(
      "admin",
      label = i18n$t("Show administrative areas"),
      value = FALSE
    ),
    checkboxInput(
      "raster",
      label = i18n$t("Show map forecast"),
      value = TRUE
    ),
    sliderInput(
      "period_raster",
      i18n$t("Map Forecast Time"),
      min = ctx$raster_base,
      max = ctx$raster_base + lubridate::hours(tail(time_range_raster, 1)),
      value = ctx$raster_base + lubridate::hours(time_range_raster[1]),
      timeFormat = "%Y-%m-%d %H-%M-%S",
      timezone = timezone_country,
      step = 21600 / 2
    ),
    br(),
    br(),
    div(
      style = "padding-left: 10px; padding-right: 10px;",
      h4("Development Information"),
      # Bullet points for additional information
      tags$ul(
        tags$li("Service development and operation:", tags$div(style = "flex: 0; display: flex; align-items: center;",
                                                               tags$a(href = "https://www.meteoswiss.ch", target = "_blank",  # Opens link in a new tab
                                                                      img(src = "logo_meteoswiss.png", height = "30px")))),
        tags$li("Station management:",
                tags$a(style = "flex: 0; display: flex; align-items: center;",
                       # Optional Link to hydromet: e.g. href = "https://www.meteo.tj", target = "_blank",  # Opens link in a new tab
                       img(src = "logo_hydromet.png", height = "30px")),
                tags$a(href = "https://www.caritas.ch", target = "_blank",  # Opens link in a new tab
                       img(src = "logo_caritas.png", height = "10px"))),
        tags$li("Funding:", tags$div(style = "flex: 0; display: flex; align-items: center;",
                                     tags$a(href = "https://www.caritas.ch", target = "_blank",  # Opens link in a new tab
                                            img(src = "logo_caritas.png", height = "10px")),
                                     tags$a(href = "https://www.eda.admin.ch/deza/de/home.html", target = "_blank",  # Opens link in a new tab
                                            img(src = "logo_sdc.png", height = "80px"))))
      )
    )
  )
}

# ------------------------------- Dashboard Body
body <- dashboardBody(
  shinybrowser::detect(),
  shiny.i18n::usei18n(i18n),
  tags$style(type = "text/css", "#map {height: calc(82vh) !important;}; "),
  tags$head(tags$link(rel = "stylesheet", type = "text/css", href = "hydromet.css")),
  fluidRow(
    box(
      width = 6,
      title = i18n$t("Station Map"),
      leafletOutput("map") %>% shinycssloaders::withSpinner(color =
                                                              "lightblue"),
      collapsible = TRUE,
      status = "primary",
      solidHeader = TRUE
    ),
    tabBox(
      width = 6,
      title = i18n$t("Meteogram"),
      side = "right",
      tabPanel(
        i18n$t("Meteogram"),
        plotlyOutput("meteogram", height = "35vh") %>% shinycssloaders::withSpinner(color =
                                                                                      "lightblue")        
      ),
      tabPanel(
        i18n$t("Map forecast"),
        plotlyOutput("meteogram2", height = "35vh")
      )
    ),
    tabBox(
      width = 6,
      title = i18n$t("Observations"),
      side = "right",
      tabPanel(
        i18n$t("Data"),
        tags$style(type = "text / css", "{
text - align:center
}"),
        selectInput(
          "var",
          label = "",
          width = "180px",
          choices = c(
            "Temperature" = "Temperature",
            "Relative Humidity" = "RH",
            "Pressure" = "Pressure",
            "Solar" = "Solar",
            "Signal" = "Signal",
            "Battery" = "Battery",
            "Precipitation" = "Precipitation",
            "Evapotranspiration" = "Evapotranspiration"
          ),
          selected = "Temperature"
        ),
        plotlyOutput("observations", height = "35vh") %>% shinycssloaders::withSpinner(color =
                                                                                         "lightblue")
      ) ,
      tabPanel(
        i18n$t("Station"),
        valueBoxOutput("id"),
        valueBoxOutput("alt"),
        valueBoxOutput("logger"),
        valueBoxOutput("sdate"),
        valueBoxOutput("lat"),
        valueBoxOutput("lng")
      )
    )
  )
)

# ------------------------------- Page assembly
build_page <- function(request) {
  ctx <- ui_context()   # one snapshot per page request

  tagList(
    # Add favicon
    tags$head(
      tags$link(rel = "shortcut icon", href = "dashboard_favicon.ico")
    ),

    # Dashboard page layout
    dashboardPage(
      skin = "blue",
      title = "WWCS - Dashboard",
      header,
      sidebar(ctx),
      body
    )
  )
}

## secure_app() is called on concrete tags rather than on the function, which
# works on every shinymanager version. Newer versions return function(request)
# from secure_app(), older ones return tags, so unwrap whichever comes back.
ui <- function(request) {
  page <- build_page(request)

  if (!("dashboard" %in% use_pass)) {
    return(page)
  }

  secured <- secure_app(page)
  if (is.function(secured)) secured(request) else secured
}
