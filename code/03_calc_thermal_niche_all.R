library(dplyr)
library(pals)
library(sp)

set.seed(1234)

# df_wc <- readRDS("output/wc/models.RDS")
# df_goa <- readRDS("output/goa/models.RDS")
# df_bc <- readRDS("output/bc/models.RDS")
# # filter only models that have depth
# df_wc <- dplyr::mutate(df_wc, id = 1:nrow(df_wc)) %>% 
#   dplyr::filter(depth_effect==TRUE)
# df_goa <- dplyr::mutate(df_goa, id = 1:nrow(df_goa)) %>% 
#   dplyr::filter(depth_effect==TRUE)
# df_bc <- dplyr::mutate(df_bc, id = 1:nrow(df_bc)) %>% 
#   dplyr::filter(depth_effect==TRUE)
# # 'pacific spiny dogfish' in wc data
# # 'spiny dogfish' in goa data
# # 'north pacific spiny dogfish' in bc data
# df_wc$species = as.character(df_wc$species)
# df_bc$species = tolower(as.character(df_bc$species))
# df_goa$species = tolower(as.character(df_goa$species))
# df_wc$species[which(df_wc$species=="pacific spiny dogfish")] = "north pacific spiny dogfish"
# df_goa$species[which(df_goa$species=="spiny dogfish")] = "north pacific spiny dogfish"

# species table
species_table <- read.csv("species_table.csv")
species_table = dplyr::mutate(species_table, 
                              GOA = ifelse(GOA=="x",1,0),
                              BC = ifelse(BC=="x",1,0),
                              WC = ifelse(WC=="x",1,0),
                              n_regions = GOA + BC + WC) %>%
  dplyr::filter(n_regions > 1)
spp <- readRDS("output/spp_for_brms.rds")
# filter out the 30 spp used in paper
spp <- spp[-which(spp == "Pacific ocean perch")]
spp <- c(spp, "Longspine thornyhead")
species_table <- dplyr::filter(species_table, species %in% tolower(spp))

mu_logdepth <- 5.21517
sd_logdepth <- 0.8465829

# gridded temp predictions from WC
pred_temp_wc <- readRDS("output/wc_pred_temp.rds")
pred_temp_wc <- dplyr::rename(pred_temp_wc, enviro = est, X = longitude, Y = latitude)
pred_temp_wc$enviro2 <- pred_temp_wc$enviro ^ 2 
pred_temp_wc <- dplyr::group_by(pred_temp_wc, lat_lon) %>%
  dplyr::mutate(n = length(which(abs(enviro) > 14))) %>%
  dplyr::filter(n == 0) %>%
  dplyr::select(-n)
pred_temp_wc <- dplyr::filter(pred_temp_wc, enviro > 0)
pred_temp_wc$depth <- log(-pred_temp_wc$depth)
pred_temp_wc$depth <- (pred_temp_wc$depth - mu_logdepth) / sd_logdepth
pred_temp_wc$logdepth <- pred_temp_wc$depth
pred_temp_wc$logdepth2 <- pred_temp_wc$logdepth ^ 2
pred_temp_wc$Area_km2 <- 10.28971 # area size of raster cells
pred_temp_wc$region <- "COW"
wc_area <- sum(pred_temp_wc$Area_km2[which(pred_temp_wc$year == 2010)])
wc_area <- dplyr::group_by(pred_temp_wc, year) %>%
  dplyr::summarize(tot_km2 = sum(Area_km2))

# gridded temp predictions from BC
pred_temp_bc <- readRDS("output/bc_pred_temp.rds")
pred_temp_bc <- dplyr::rename(pred_temp_bc, enviro = est, X = longitude, Y = latitude)
pred_temp_bc$enviro2 <- pred_temp_bc$enviro ^ 2 
pred_temp_bc <- dplyr::group_by(pred_temp_bc, lat_lon) %>%
  dplyr::mutate(n = length(which(abs(enviro) > 14))) %>%
  dplyr::filter(n == 0) %>%
  dplyr::select(-n)
pred_temp_bc <- dplyr::filter(pred_temp_bc, enviro > 0)
pred_temp_bc <- dplyr::rename(pred_temp_bc, Area_km2 = cell_area)
pred_temp_bc$depth <- log(pred_temp_bc$depth)
pred_temp_bc$depth <- (pred_temp_bc$depth - mu_logdepth) / sd_logdepth
pred_temp_bc$logdepth <- pred_temp_bc$depth
pred_temp_bc$logdepth2 <- pred_temp_bc$logdepth ^ 2
pred_temp_bc$region <- "BC"
bc_area <- dplyr::group_by(pred_temp_bc, year) %>%
  dplyr::summarize(tot_km2 = sum(Area_km2))
  
# gridded temp predictions from GOA
pred_temp_goa <- readRDS("output/goa_pred_temp.rds")
pred_temp_goa <- dplyr::rename(pred_temp_goa, enviro = est, X = longitude, Y = latitude)
pred_temp_goa$enviro2 <- pred_temp_goa$enviro ^ 2 
pred_temp_goa <- dplyr::group_by(pred_temp_goa, lat_lon) %>%
  dplyr::mutate(n = length(which(abs(enviro) > 14))) %>%
  dplyr::filter(n == 0) %>%
  dplyr::select(-n)
pred_temp_goa <- dplyr::filter(pred_temp_goa, enviro > 0)
pred_temp_goa$depth <- log(pred_temp_goa$depth)
pred_temp_goa$depth <- (pred_temp_goa$depth - mu_logdepth) / sd_logdepth
pred_temp_goa$logdepth <- pred_temp_goa$depth
pred_temp_goa$logdepth2 <- pred_temp_goa$logdepth ^ 2
pred_temp_goa$region <- "GOA"
goa_area <- dplyr::group_by(pred_temp_goa, year) %>%
  dplyr::summarize(tot_km2 = sum(Area_km2))

for (i in 1:nrow(species_table)) {
  
  this_species = species_table$species[i]

  # WC
  spp <- df_wc$id[which(df_wc$species==this_species)]
  pred_df_wc <- NULL
  
  # get the best fit model
  aic_table <- read.csv("combined_table.csv", header=TRUE)
  best_model <- which.min(aic_table[i,9:13])
  
  fit <- readRDS(file = paste0("output/all/", this_species, "_model",(best_model-1),".rds"))
  
  if(class(fit) != "try-error") {
    
  if(length(spp) > 0) {
    #fit <- readRDS(file = paste0("output/wc/model_", spp, ".rds"))
    # make predictions -- response not link space
    newdata = dplyr::filter(pred_temp_wc, year %in% unique(fit$data$year))
    newdata$scaled_enviro <- (newdata$enviro - mean(fit$data$enviro)) / sd(fit$data$enviro)
    newdata$scaled_enviro2 <- newdata$scaled_enviro ^ 2
    pred_df_wc <- predict(fit, newdata = newdata) # , type="response")
    pred_df_wc <- ungroup(pred_df_wc) %>% dplyr::select(year, depth, enviro, Area_km2, est)
    pred_df_wc$region <- "COW"
  }
  
  # GOA
  spp <- df_goa$id[which(df_goa$species==this_species)]
  pred_df_goa <- NULL
  if(length(spp) > 0) {
    newdata = dplyr::filter(pred_temp_goa, year %in% unique(fit$data$year))
    newdata$scaled_enviro <- (newdata$enviro - mean(fit$data$enviro)) / sd(fit$data$enviro)
    newdata$scaled_enviro2 <- newdata$scaled_enviro ^ 2
    pred_df_goa <- predict(fit, newdata = newdata) 
    pred_df_goa <- ungroup(pred_df_goa) %>% dplyr::select(year, depth, enviro, Area_km2, est)
    pred_df_goa$region <- "GOA"
  }
  
  # BC
  spp <- df_bc$id[which(df_bc$species==this_species)]
  pred_df_bc <- NULL
  if(length(spp) > 0) {
    newdata = dplyr::filter(pred_temp_bc, year %in% unique(fit$data$year))
    newdata$scaled_enviro <- (newdata$enviro - mean(fit$data$enviro)) / sd(fit$data$enviro)
    newdata$scaled_enviro2 <- newdata$scaled_enviro ^ 2
    pred_df_bc <- predict(fit, newdata = newdata) # , type="response")
    pred_df_bc <- ungroup(pred_df_bc) %>% dplyr::select(year, depth, enviro, Area_km2, est)
    pred_df_bc$region <- "BC"
  }  
  
  # combine these 
  use_goa = FALSE
  if(!is.null(pred_df_wc)) {
    combined <- pred_df_wc
    if(!is.null(pred_df_bc)) {
      combined <- rbind(combined, pred_df_bc)
    }
    if(!is.null(pred_df_goa)) {
      combined <- rbind(combined, pred_df_goa)
      use_goa <- TRUE
    }
  } else {
    # wc data not used
    if(!is.null(pred_df_bc)) {
      combined <- pred_df_bc
    }
    if(!is.null(pred_df_goa)) {
      combined <- rbind(combined, pred_df_goa)
      use_goa <- TRUE
    }
  }
  
  p_summary <- dplyr::group_by(combined, year, region) %>%
    dplyr::summarise(sum = sum(exp(est))/1000) %>%
    dplyr::group_by(year) %>%
    dplyr::mutate(year_tot = sum(sum), p = sum/year_tot) %>%
    dplyr::select(year, region, p)
  p_summary$spp <- this_species
  
  # if using GOA data, apply to the same set of years
  totarea <- wc_area$tot_km2[1] + bc_area$tot_km2[1]
  years <- wc_area$year
  if(use_goa) {
    combined <- dplyr::filter(combined, year %in% goa_area$year)
    totarea <- totarea + goa_area$tot_km2[1]
  }
  
  #years = unique()
  # Loop over years -- no clean way to do this with dplyr
  years <- sort(unique(combined$year))
  for(ii in 1:length(years)) {
    # generate samples from this year that are equal in size to total area
    sub <- dplyr::filter(combined, year == years[ii])
    sampled_idx <- sample(1:nrow(sub), size = 10*nrow(sub), replace=T, prob = exp(sub$est))
    sampled_df <- sub[sampled_idx,]
    cutoff <- which(cumsum(sampled_df$Area_km2) > totarea)[1]
    sampled_df <- sampled_df[1:cutoff,]
    
    # summarize
    summarized_df <- 
      dplyr::summarise(sampled_df, year = year[1],
                       min_enviro = min(enviro),
                       max_enviro = max(enviro),
                       mean_enviro = mean(enviro),
                       lo10_enviro = quantile(enviro,0.05),
                       lo20_enviro = quantile(enviro,0.1),
                       lo30_enviro = quantile(enviro,0.15),
                       lo40_enviro = quantile(enviro,0.2),
                       lo50_enviro = quantile(enviro,0.25),
                       hi10_enviro = quantile(enviro,0.95),
                       hi20_enviro = quantile(enviro,0.9),
                       hi30_enviro = quantile(enviro,0.85),
                       hi40_enviro = quantile(enviro,0.8),
                       hi50_enviro = quantile(enviro,0.75))
    summarized_df$sci_name <- fit$data$scientific_name[1]
    summarized_df$species <- fit$data$species[1]
    #summarized_df$depth <- df$depth_effect[i]
    # calculate mean temp for this year -- based on estimated distribution
    sub <- dplyr::arrange(sub, -est) %>%
      dplyr::mutate(tot = exp(est))
    indx <- which(cumsum(sub$tot/sum(sub$tot)) > 0.95)[1]
    summarized_df$avg_temp <- mean(sub$enviro[1:indx])
    summarized_df$lo_temp <- quantile(sub$enviro[1:indx], 0.025)
    summarized_df$hi_temp <- quantile(sub$enviro[1:indx], 0.975)
    if(ii == 1) {
      sampled_temp_year <- summarized_df
    } else {
      sampled_temp_year <- rbind(sampled_temp_year, summarized_df)
    }
  }
  
  # ggplot(sampled_temp_year, aes(year, mean_enviro)) + 
  #   geom_line() + 
  #   geom_line(aes(year, lo40_enviro)) + 
  #   geom_line(aes(year, hi40_enviro)) 
  
  if (i == 1) {
    all_temp <- sampled_temp_year
    all_p <- p_summary
  } else {
    all_temp <- rbind(all_temp, sampled_temp_year)
    all_p <- rbind(all_p, p_summary)
  }
  } # end if 

}
saveRDS(all_p, "output/all_proportions_combined.rds")
saveRDS(all_temp, "output/temp_niche_combined.rds")
