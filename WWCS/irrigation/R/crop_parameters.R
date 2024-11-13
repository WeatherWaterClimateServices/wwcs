# ------------------------------------------------
# PARAMETERS FOR IRRIGATION TRIALS
# ------------------------------------------------

# Field Capacity
FC <- 36

# Wilting Point
WP <- 18

# Total Available Water
TAW <- FC - WP

# Management Allowed Deficit
MAD <- 0.4

# Readily Available Moisture Content
RAW <- 7.2

# Crop Coefficient
Kc <- readr::read_csv(file = "/srv/shiny-server/irrigation/appdata/Kc.csv", col_names="value", show_col_types = FALSE) 

# Crop Coefficient Stressed
Ks <- array(0, dim = c(window)) 

# Average Crop Evapotranspiration
ETc <- 2.5

# Root Depth
RD <- 0.0043 * seq(1,window) + 0.1957

# Threshold Moisture Content
PHIt <- FC - TAW*MAD

# Moisture Content
PHIc <- array(NA, dim = c(window))

# Soil Water Deficit
SWD <-  array(0, dim = c(window))
