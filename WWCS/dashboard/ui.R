# ------------------------------- Dashboard Header


header <- dashboardHeader(title = tags$a(
  tags$img(
    src = 'logo_hydromet_small.png',
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

sidebar <- dashboardSidebar(
  width = 350,
  collapsed = TRUE,
  sidebarMenu(),
  sliderInput(
    "period_f",
    i18n$t("Forecast Time"),
    min = as.Date(time_range_f$min),
    max = as.Date(time_range_f$max),
    value = start_date_f,
    timeFormat = "%Y-%m-%d"
  ),
  sliderInput(
    "period_o",
    i18n$t("Observation Time"),
    min = as.Date(time_range_o$min),
    max = as.Date(time_range_o$max),
    value = as.Date(c(start_date_o)),
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
    min = as.POSIXct(paste(time_range_f$max, "00:00:00"), tz = timezone_country),
    max = as.POSIXct(paste(
      time_range_f$max + lubridate::hours(tail(time_range_raster, 1))
    ), tz = timezone_country),
    value = as.POSIXct(paste(
      time_range_f$max + lubridate::hours(time_range_raster[1])
    ), tz = timezone_country),
    timeFormat = "%Y-%m-%d %H-%M-%S",
    timezone = timezone_country,
    step = 21600 / 2,
  ),
  br(),
  br(),
  div(
    style = "padding-left: 10px; padding-right: 10px;",
    h4("Development Information"),
    # Bullet points for additional information
    tags$ul(
      tags$li("Software development and service operation:", tags$div(style = "flex: 0; display: flex; align-items: center;", 
                                                                      tags$a(href = "https://www.meteoswiss.ch", target = "_blank",  # Opens link in a new tab
                                                                             img(src = "meteoswiss.png", height = "30px")))),
      tags$li("Station management:", 
              tags$a(style = "flex: 0; display: flex; align-items: center;", 
                      href = "https://www.meteo.tj", target = "_blank",  # Opens link in a new tab
                     img(src = "logo_hydromet_small.png", height = "30px")),
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
                                                                                      "lightblue"),
        tags$div(
          style = "display: flex; align-items: center; padding: 10px;",
          tags$div(style = "flex: 1; text-align: right; padding-right: 10px;", p("© weather icons")),
          # Image part
          tags$div(style = "flex: 0; display: flex; align-items: center;", 
                   tags$a(href = "https://www.meteoswiss.ch", target = "_blank",  # Opens link in a new tab
                          img(src = "meteoswiss.png", height = "30px")))
        )
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
            #"Precipitation" = "Precipitation",
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

ui <- tagList(
  # Add favicon
  tags$head(
    tags$link(rel = "shortcut icon", href = "dashboard_favicon.ico")
  ),
  
  # Dashboard page layout
  dashboardPage(
    skin = "blue",
    title = "WWCS - Dashboard",
    header,
    sidebar,
    body
  )
)

# ui <- secure_app(ui)
