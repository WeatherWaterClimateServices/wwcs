library(dplyr)
library(xlsx)

## raw data.frame
crop.parameters <- data.frame(Index = 1:300)

## tomato for cambodia - default FAO values https://www.fao.org/4/x0490e/x0490e0b.htm
## chosen the shortest variety, and further shortened to 90 days. the Kcs seem to be the same for all

## the full cycle after planting
Ls <- round(c(ini = 30, dev = 40, mid = 40, late = 20) / 130 * 90)
Kc <- c(ini = 0.6, mid = 1.15, end = .8)
Kcs <- c(rep(Kc[["ini"]], Ls[["ini"]]),
         seq(Kc[["ini"]], Kc[["mid"]], length=Ls[["dev"]]),
         rep(Kc[["mid"]], Ls[["mid"]]),
         seq(Kc[["mid"]], Kc[["end"]], length=Ls[["late"]]))

## cut off initial days 45 which happen in a nursery (some tuning for RD -
## these will remain short in the pots of the nursery)
Kcs <- Kcs[46:length(Kcs)]
RDs <- c(seq(.25, 1, length=10), rep(1, length(Kcs) - 10))

TomatoCambodia <-
  data.frame(Index = 1:nrow(crop.parameters),
             TomatoCambodia_Kc=c(Kcs,
                            rep(last(Kcs), nrow(crop.parameters)-length(Kcs))),
             TomatoCambodia_RD=c(RDs,
                            rep(last(RDs), nrow(crop.parameters)-length(RDs))))
crop.parameters <- full_join(crop.parameters, TomatoCambodia, by = "Index")

##
## cucumber for cambodia
##
## default FAO values https://www.fao.org/4/x0490e/x0490e0b.htm
## fresh market, summer variety, shortened to 60 days
## rooting depth: additionally here:
##   https://soilandhealth.org/wp-content/uploads/01aglibrary/010137veg.roots/010137ch29.html

## the full cycle after planting
Ls <- round(c(ini=20, dev=30, mid=40, late=15) / 105 * 60)
Kc <- c(ini=0.6, mid=1, end=.75)
Kcs <- c(rep(Kc[["ini"]], Ls[["ini"]]),
         seq(Kc[["ini"]], Kc[["mid"]], length=Ls[["dev"]]),
         rep(Kc[["mid"]], Ls[["mid"]]),
         seq(Kc[["mid"]], Kc[["end"]], length=Ls[["late"]]))
RDs <- c(seq(0.1, 1, length=Ls[["ini"]]), rep(1, 60 - Ls[["ini"]]))

CucumberCambodiaSeeded <-
  data.frame(Index=1:nrow(crop.parameters),
             CucumberCambodiaSeeded_Kc=c(Kcs,
                                   rep(last(Kcs), nrow(crop.parameters)-length(Kcs))),
             CucumberCambodiaSeeded_RD=c(RDs,
                                   rep(last(RDs), nrow(crop.parameters)-length(RDs))))
crop.parameters <- full_join(crop.parameters, CucumberCambodiaSeeded, by = "Index")

## now the same cucumber, but with
## cut off initial days 10-15 which happen in a nursery (some tuning for RD -
## these will remain short in the pots of the nursery)
Kcs <- Kcs[Ls[["ini"]]:length(Kcs)]
RDs <- c(seq(.3, 1, length=5), rep(1, length(Kcs) - 5))

CucumberCambodiaTranspl <-
  data.frame(Index=1:nrow(crop.parameters),
             CucumberCambodiaTranspl_Kc=c(Kcs,
                                   rep(last(Kcs), nrow(crop.parameters)-length(Kcs))),
             CucumberCambodiaTranspl_RD=c(RDs,
                                   rep(last(RDs), nrow(crop.parameters)-length(RDs))))
crop.parameters <- full_join(crop.parameters, CucumberCambodiaTranspl, by = "Index")
                       

## winter wheat from ICARDA
kc_path <- "WinterWheat/Winter_Wheat_Kc_Tadjikistan_Updated.xlsx"
rd_path <- "WinterWheat/Winter_Wheat_Rooting_Depth_Tadjikistan_Updated.xlsx"

if (file.exists(kc_path) && file.exists(rd_path)) {
  Kc <- read.xlsx(kc_path, sheetIndex = 1)
  RD <- read.xlsx(rd_path, sheetIndex = 1)
  winterwheat <- data.frame(
    Index = crop.parameters$Index,
    WinterWheat_Kc = c(Kc[, 1], rep(Kc[nrow(Kc), 1], nrow(crop.parameters) - nrow(Kc))),
    WinterWheat_RD = c(RD[, 1], rep(RD[nrow(RD), 1], nrow(crop.parameters) - nrow(RD)))
  )
  crop.parameters <- full_join(crop.parameters, winterwheat, by = "Index")
}

## cotton from ICARDA
kc_path <- "Cotton/Cotton_Kc_Only.xlsx"
rd_path <- "Cotton/Estimated_Rooting_Depths.csv"

if (file.exists(kc_path) && file.exists(rd_path)) {
  Kc <- read.xlsx(kc_path, sheetIndex = 1)
  RD <- read.csv(rd_path)
  cotton <- data.frame(
    Index = crop.parameters$Index,
    Cotton_Kc = c(Kc[, 1], rep(Kc[nrow(Kc), 1], nrow(crop.parameters) - nrow(Kc))),
    Cotton_RD = c(RD[, 1], rep(RD[nrow(RD), 1], nrow(crop.parameters) - nrow(RD)))
  )
  crop.parameters <- full_join(crop.parameters, cotton, by = "Index")
}

## potato from ICARDA
kc_path <- "Potato/Kc.csv"

if (file.exists(kc_path)) {
  Kc <- read.csv(kc_path, header = FALSE)
  RD <- 0.0043 * seq(1, nrow(Kc)) + 0.1957
  potato <- data.frame(Index = 1:length(RD), Potato_Kc = Kc[,1], Potato_RD = RD)
  
  ## fill up the remaining empty rows and join
  potato.end <- data.frame(
    Index = (length(RD) + 1):nrow(crop.parameters),
    Potato_Kc = potato[nrow(potato), "Potato_Kc"],
    Potato_RD = potato[nrow(potato), "Potato_RD"]
  )
  
  crop.parameters <- full_join(crop.parameters, rbind(potato, potato.end), by = "Index")
}

## Sen Kro Ob, 115 days; DryRice manually defined
Kcs <- c(.9, .9, .9, 1.1, 1.1, 1.2, 1.2, 1.3, 1.3, 1.3, 1.2, 1.2, .9, .9)
RD <- c(seq(.1, 0.7, length = 60), rep(0.7, 115 - 60))
bins <- round(seq(0, by = 115 / length(Kcs), length = length(Kcs) + 1))
DryRice <- data.frame(Index = 1:115, DryRice_Kc = rep(Kcs, diff(bins)), DryRice_RD = RD)

## fill up the remaining empty rows and join
DryRice.end <- data.frame(
  Index = (115 + 1):nrow(crop.parameters),
  DryRice_Kc = DryRice[nrow(DryRice), "DryRice_Kc"],
  DryRice_RD = DryRice[nrow(DryRice), "DryRice_RD"]
)

crop.parameters <- full_join(crop.parameters, rbind(DryRice, DryRice.end), by = "Index")

## write out
write.csv(crop.parameters, "CropParameters.csv", row.names = FALSE)
Sys.chmod("CropParameters.csv", mode = "0666", use_umask = FALSE)

