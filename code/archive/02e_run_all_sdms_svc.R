library(dplyr)
library(pals)
library(sp)

set.seed(1234)

cow <- readRDS("survey_data/joined_nwfsc_data.rds")
bc <- readRDS("survey_data/bc_data_2021.rds")
bc <- dplyr::select(bc, -start_time, -count, -sensor_name) %>%
  dplyr::rename(temp = temperature)
goa <- readRDS("survey_data/joined_goa_data.rds")
cow$region <- "COW"
bc$region <- "BC"
goa$region <- "GOA"

dat <- rbind(dplyr::select(bc, year, survey, species, scientific_name, 
                           latitude_dd, longitude_dd, depth, temp, 
                           cpue_kg_km2, region),
             dplyr::select(cow, year, survey, species, scientific_name, 
                           latitude_dd, longitude_dd, depth, temp, 
                           cpue_kg_km2, region),
             dplyr::select(goa, year, survey, species, scientific_name, 
                           latitude_dd, longitude_dd, depth, temp, 
                           cpue_kg_km2, region))
dat$species <- tolower(dat$species)
dat$species[which(dat$species%in%c("spiny dogfish","pacific spiny dogfish"))] = "north pacific spiny dogfish"

df_wc <- readRDS("output/wc/models.RDS")
df_goa <- readRDS("output/goa/models.RDS")
df_bc <- readRDS("output/bc/models.RDS")
# filter only models that have depth
df_wc <- dplyr::mutate(df_wc, id = 1:nrow(df_wc)) %>% 
  dplyr::filter(depth_effect==TRUE)
df_goa <- dplyr::mutate(df_goa, id = 1:nrow(df_goa)) %>% 
  dplyr::filter(depth_effect==TRUE)
df_bc <- dplyr::mutate(df_bc, id = 1:nrow(df_bc)) %>% 
  dplyr::filter(depth_effect==TRUE)
# 'pacific spiny dogfish' in wc data
# 'spiny dogfish' in goa data
# 'north pacific spiny dogfish' in bc data
df_wc$species = as.character(df_wc$species)
df_bc$species = tolower(as.character(df_bc$species))
df_goa$species = tolower(as.character(df_goa$species))
df_wc$species[which(df_wc$species=="pacific spiny dogfish")] = "north pacific spiny dogfish"
df_goa$species[which(df_goa$species=="spiny dogfish")] = "north pacific spiny dogfish"

# species table
species_table <- read.csv("species_table.csv")
species_table = dplyr::mutate(species_table, 
                              GOA = ifelse(GOA=="x",1,0),
                              BC = ifelse(BC=="x",1,0),
                              WC = ifelse(WC=="x",1,0),
                              n_regions = GOA + BC + WC) %>%
  dplyr::filter(n_regions > 1)
 
for (i in 1:nrow(species_table)) {
  
  this_species = species_table$species[i]
  sub <- dplyr::filter(dat, species == this_species, !is.na(depth),
                       year != 2020,
                       !is.na(temp))
  #sub <- sub[seq(1,27000,by=100),]
  sub <- add_utm_columns(sub, ll_names = c("longitude_dd","latitude_dd"))
  sub$enviro <- sub$temp
  sub$enviro2 <- sub$enviro * sub$enviro
  sub$enviro_scaled = scale(sub$enviro)
  sub$logdepth <- scale(log(sub$depth))
  
  spde <- try(make_mesh(sub, c("X", "Y"),
                        cutoff = 20
  ), silent = TRUE)

  priors <- sdmTMBpriors(
    matern_s = pc_matern(
      range_gt = 50, range_prob = 0.05,
      sigma_lt = 25, sigma_prob = 0.05
    )
  )
  fit = list()
  fit[[1]] <- try(sdmTMB(
    cpue_kg_km2 ~ -1 + enviro_scaled + I(enviro_scaled^2) + region + as.factor(year) + s(depth),
    #cpue_kg_km2 ~ -1 + enviro + enviro2 + region + as.factor(year),
    spatial_varying = ~ enviro_scaled + I(enviro_scaled^2),
    mesh = spde,
    time = "year",
    family = tweedie(link = "log"),
    data = sub,
    priors = priors,
    spatial = "on",
    spatiotemporal = "iid"
  ), silent = TRUE)
  
  saveRDS(fit, file = paste0("output/all/", this_species, "-svc.rds"))
}


