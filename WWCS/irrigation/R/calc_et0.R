# ------------------------------------------------
# Source: Coded from ICARDA Excel Sheets
# ------------------------------------------------

calc_et0 <- function(station_data) {
  dr <- 1 + 0.033 * cos((2 * 3.14 / 365) * station$DOY)
  d <- 0.409 * sin(((2 * 3.14 / 365) * station$DOY) - 1.39)
  ws <- acos(-tan(station$lat) * tan(d))
  SinphiSind <- ws * sin(station$lat) * sin(d)
  CosphiCosdCosw <- cos(station$lat) * cos(d) * sin(ws)
  Term2 <- dr * (SinphiSind + CosphiCosdCosw)
  Term1 <- 0.082 * Term2
  Rs <- ((24 * 60) / 3.14) * Term1
  et0 <- 0.0023 * ((station$Tmax + station$Tmin) / 2) * ((station$Tmax -
                                                            station$Tmin) ^ 0.5) * Rs
  out <- station_data %>%
    bind_cols(data.frame("ET0new" = et0))
  return(out)
}
