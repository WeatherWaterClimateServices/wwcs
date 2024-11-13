interpolate_leadtime <- function(l, ifs_lead, train_i, obs_i) {
  il <-
    max(which(ifs_lead <= l)) # Find next available smaller lead time
  dl <- l - ifs_lead[il] # Difference to next larger lead time
  dr <-
    ifs_lead[il + 1] - ifs_lead[il] # Step between lead times, 3h until 120h, 6h afterwards
  
  train_l <-
    train_i %>% dplyr::filter(lead == ifs_lead[il]) %>% dplyr::distinct(time, reftime, lead, .keep_all = TRUE) # Select two IFS closest values
  train_u <-
    train_i %>% dplyr::filter(lead == ifs_lead[il + 1])  %>% dplyr::distinct(time, reftime, lead, .keep_all = TRUE)
  
  dt <-
    str_c(dl, 0, 0, sep = ":")
  time_i <- train_l$time + hms(dt) # Compute time difference
  selobs <-
    obs_i %>% dplyr::filter(time %in% time_i) %>% dplyr::select(Temperature_mean, time)
  
  if (nrow(train_u) > 0) {
    out <-
      train_l %>% dplyr::select(-c(Temperature_mean)) %>% # Interpolate linearly for Mean and SD
      dplyr::mutate(
        IFS_T_mea = IFS_T_mea + (train_u$IFS_T_mea - IFS_T_mea) / dr * dl,
        IFS_T_std = IFS_T_std + (train_u$IFS_T_std - IFS_T_std) / dr * dl,
        lead = l,
        time = time_i
      ) %>%
      full_join(selobs, multiple = "all", by = "time")
  } else {
    out <- train_l
  }
  return(out)
}
