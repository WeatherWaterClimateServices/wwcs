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

sidebar <- dashboardSidebar(collapsed = TRUE, dashboardSidebar(sidebarMenu(
  menuItem(i18n$t("Warnings"), tabName = "warnings", icon = icon("dashboard")),
  menuItem(i18n$t("Thresholds"), tabName = "control", icon = icon("th")),
  menuItem(i18n$t("SMS"), tabName = "sms", icon = icon("envelope"))
)))


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

ui <- dashboardPage(skin = "blue", title = "WWCS - Early Warnings", header, sidebar, body)