header <- dashboardHeader(title = tags$a(
  tags$img(
    src = 'logo_hydromet.png',
    width = "90px",
    height = "90px"
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
    selected = "en",
    width = "180px"
  )
))

# ------------------------------- Dashboard Sidebar

sidebar <-  dashboardSidebar(
  width = 300,
  collapsed = TRUE, 
  sidebarMenu(
  menuItem(i18n$t("Warnings"), tabName = "warnings", icon = icon("dashboard")),
  menuItem(i18n$t("Thresholds"), tabName = "control", icon = icon("th")),
  div(
    style = "padding-left: 10px; padding-right: 10px;",
    h4("Development Information"),
    # Bullet points for additional information
    tags$ul(
      tags$li("Service development and operation:", tags$div(style = "flex: 0; display: flex; align-items: center;", 
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
  # menuItem(i18n$t("SMS"), tabName = "sms", icon = icon("envelope"))
))


# ------------------------------- Dashboard Body

body <- dashboardBody(
  shiny.i18n::usei18n(i18n),
  tags$style(type = "text/css", "#map {height: calc(82vh) !important;}; "),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "hydromet_ews.css")
  ),
  shinydashboard::tabItems(
    shinydashboard::tabItem("warnings", fluidRow(
      box(
        width = 8,
        title = i18n$t("Warning Map"),
        leafletOutput("map"),
        collapsible = TRUE,
        status = "primary",
        solidHeader = TRUE
      ),
      box(
        width = 4,
        title = i18n$t("Control Panel"),
        collapsible = TRUE,
        status = "primary",
        solidHeader = TRUE,
        fluidRow(column(
          6,
          selectInput(
            inputId = "reftime",
            label = i18n$t("Forecast Time"),
            choices = reftimes,
            selected = seltime
          )
        ), column(
          6,
          selectInput(
            inputId = "threshold",
            label = i18n$t("Thresholds"),
            choices = c(
              "Heat (Tmean > Level 1)" =  "Heat1",
              "Heat (Tmean > Level 2)" =  "Heat2",
              "Heat (Tmean > Level 3)" =  "Heat3",
              "Frost (Tmin < Level 1)" =  "Cold1",
              "Frost (Tmin < Level 2)" =  "Cold2",
              "Frost (Tmin < Level 3)" =  "Cold3"
            ),
            selected = "Cold2"
          )
        )),
        br(),
        br()
      ),
      box(
        width = 4,
        plotOutput("plot", height = "20vh"),
        br(),
        br(),
        collapsible = TRUE,
        status = "primary",
        solidHeader = TRUE
      ),
      box(
        width = 4,
        title = i18n$t("Warning Thresholds"),
        valueBoxOutput("cold1"),
        valueBoxOutput("cold2"),
        valueBoxOutput("cold3"),
        valueBoxOutput("heat1"),
        valueBoxOutput("heat2"),
        valueBoxOutput("heat3"),
        collapsible = TRUE,
        status = "primary",
        solidHeader = TRUE
      )
    )),
    shinydashboard::tabItem(
      "control",
      box(
        width = 12,
        title = i18n$t("Warning Levels"),
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
    shinydashboard::tabItem("sms",
      fluidRow(
        box(width = 6,
          selectInput("num_days", "Number of warning days:", choices = 1:5, selected = 3),
          hr(),
          textInput("message", "Message (can be modified):", value = default_message),
          hr(),
          pickerInput("selected_numbers", "Select Recipients (humanID)", choices = c(), options = list(`actions-box` = TRUE), multiple = TRUE),
          br(),
          br(),
          actionButton("send_button", "Create Message", icon("envelope"), class = "btn-primary")
        ),
       box(width = 6,
          h4("Combined JSON for SMS:"),
          verbatimTextOutput("combined_json")
        )
      )
    )
  )
)

ui <- tagList(
  # Add favicon
  tags$head(
    tags$link(rel = "shortcut icon", href = "coldwave_favicon.ico")
  ),
  
  # Dashboard page layout
  dashboardPage(
    skin = "blue",
    title = "WWCS - Early Warning",
    header,
    sidebar,
    body
  )
)
