complete_criteria <- function(criteria, ptns_sf) {
  
  criteria <- criteria %>%
    dplyr::bind_rows(
      pnts_sf %>%
        dplyr::distinct(area) %>%
        dplyr::mutate(district = area) %>%
        dplyr::mutate(
          Croptype = "Winter Wheat",
          Threshold_low = 12,
          Threshold_high = 15,
          Window_low = "15-Sep",
          Window_high = "15-Nov"
        ) %>%
        dplyr::bind_rows(
          pnts_sf %>%
            dplyr::distinct(area) %>%
            dplyr::mutate(district = area) %>%
            dplyr::mutate(
              Croptype = "Spring Wheat",
              Threshold_low = 6,
              Threshold_high = 7,
              Window_low = "15-Feb",
              Window_high = "15-Mar"
            ) %>%
            dplyr::bind_rows(
              pnts_sf %>%
                dplyr::distinct(area) %>%
                dplyr::mutate(district = area) %>%
                dplyr::mutate(
                  Croptype = "Spring Potato",
                  Threshold_low = 7,
                  Threshold_high = 8,
                  Window_low = "20-Feb",
                  Window_high = "20-Mar"
                ) %>%
                dplyr::bind_rows(
                  pnts_sf %>%
                    dplyr::distinct(area) %>%
                    dplyr::mutate(district = area) %>%
                    dplyr::mutate(
                      Croptype = "Summer Potato",
                      Threshold_low = 22,
                      Threshold_high = 25,
                      Window_low = "20-May",
                      Window_high = "1-Jun"
                    )
                )
            )
        )
    ) %>%
    dplyr::select(-c(area)) %>%
    arrange(district) %>%
    unique()
  
  # Write missing districts to criteria.csv file replacing existing
  
  write_csv(criteria,
            "/srv/shiny-server/planting/appdata/criteria_planting.csv")
  
}