library(dplyr)
## raw data.frame
crop.parameters <- data.frame(Index=1:300)

## potato from ICARDA
Kc <- read.csv("Kc.csv", header=F)
RD <- 0.0043 * seq(1, nrow(Kc)) + 0.1957
potato <- data.frame(Index=1:length(RD), Potato_Kc=Kc[,1], Potato_RD=RD)
## fill up the remaining empty rows and join
potato.end <- data.frame(Index=(length(RD)+1):nrow(crop.parameters),
                         Potato_Kc=potato[nrow(potato), "Potato_Kc"],
                         Potato_RD=potato[nrow(potato), "Potato_RD"])
crop.parameters <- full_join(crop.parameters, rbind(potato, potato.end), by="Index")

## Sen Kro Ob, 115 days; Kc based on a merge of https://www.fao.org/4/X0490E/x0490e0b.htm#crop%20coefficients and a pdf shared by ICARDA
Kcs <- c(.9, .9, .9, 1.1, 1.1, 1.2, 1.2, 1.3, 1.3, 1.3, 1.2, 1.2, .9, .9)
RD <- c(seq(.1, 0.7, length=60), rep(0.7, 115-60))
bins <- round(seq(0, by=115 / length(Kcs), length=length(Kcs)+1))
DryRice <- data.frame(Index=1:115, DryRice_Kc=rep(Kcs, diff(bins)), DryRice_RD=RD)
## fill up the remaining empty rows and join
DryRice.end <- data.frame(Index=(115+1):nrow(crop.parameters),
                          DryRice_Kc=DryRice[nrow(DryRice), "DryRice_Kc"],
                          DryRice_RD=DryRice[nrow(DryRice), "DryRice_RD"])

crop.parameters <- full_join(crop.parameters, rbind(DryRice, DryRice.end), by="Index")

## write out
write.csv(crop.parameters, "CropParameters.csv", row.names=FALSE)
