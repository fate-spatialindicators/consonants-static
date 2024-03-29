# devtools::install_github("pbs-assess/sdmTMB")
library(sdmTMB)
library(dplyr)
library(sp)

dat <- readRDS("survey_data/joined_goa_data.rds")

# UTM transformation
dat_ll <- dat
coordinates(dat_ll) <- c("longitude_dd", "latitude_dd")
proj4string(dat_ll) <- CRS("+proj=longlat +datum=WGS84")
# convert to utm with spTransform
dat_utm <- spTransform(
  dat_ll,
  CRS("+proj=utm +zone=7 +datum=WGS84 +units=km")
)
# convert back from sp object to data frame
dat <- as.data.frame(dat_utm)
dat <- dplyr::rename(dat,
  longitude = longitude_dd,
  latitude = latitude_dd
)

dat <- dplyr::filter(dat, !is.na(temp))
dat$logdepth <- log(dat$depth)
# include date
dat$date <- lubridate::parse_date_time(dat$date, order = "ymd")
dat$yday <- lubridate::yday(dat$date)

# just use haul info -- can be for any spp
dat <- dplyr::filter(dat, scientific_name == "Atheresthes stomias")

# make mesh
spde <- try(make_mesh(dat, c("longitude", "latitude"),
  cutoff = 20
), silent = TRUE)

# priors <- sdmTMBpriors(
#   matern_s = pc_matern(
#     range_gt = 5, range_prob = 0.05,
#     sigma_lt = 25, sigma_prob = 0.05
#   )
# )

dat$fyear <- as.factor(dat$year)
mu_logdepth <- mean(dat$logdepth)
sd_logdepth <- sd(dat$logdepth)
dat$logdepth <- (dat$logdepth - mu_logdepth) / sd_logdepth
dat$yday <- scale(dat$yday)

fit <- sdmTMB(temp ~ s(yday) + s(logdepth), # s(yday) + s(logdepth),
  # time_varying ~ logdepth + I(logdepth^2) + I(logepth^3),
  mesh = spde,
  time = "year",
  data = dat,
  spatial = "off",
  spatiotemporal = "iid"
)

grid <- read.csv("grid_data/grid_goa.csv")

grid <- dplyr::rename(grid, 
                      depth = DEPTH_EFH,
                      logdepth = LOG_DEPTH_EFH,
                      latitude_dd = Lat,
                      longitude_dd = Lon) %>% 
  dplyr::select(Id, logdepth, latitude_dd, longitude_dd, Area_km2, depth)

grid_ll <- grid
coordinates(grid_ll) <- c("longitude_dd", "latitude_dd")
proj4string(grid_ll) <- CRS("+proj=longlat +datum=WGS84")
# convert to utm with spTransform
grid_utm <- spTransform(
  grid_ll,
  CRS("+proj=utm +zone=7 +datum=WGS84 +units=km")
)
# convert back from sp object to data frame
grid <- as.data.frame(grid_utm)
grid <- dplyr::rename(grid,
                     longitude = longitude_dd,
                     latitude = latitude_dd
)

grid$lat_lon <- paste(grid$latitude, grid$longitude)

# scale the grid variables
grid$logdepth_orig <- grid$logdepth
# mu_logdepth = 4.847897, sd_logdepth = 0.665218
grid$logdepth <- (grid$logdepth - mu_logdepth) / sd_logdepth

pred_df <- expand.grid(
  lat_lon = unique(grid$lat_lon),
  year = unique(dat$year)
)
pred_df <- dplyr::left_join(pred_df, grid)
pred_df$yday <- (182 - 182.932) / 22.65317 # Day 182 = July 1

# make a prediction for what this will be
pred_temp <- predict(fit, pred_df)
saveRDS(pred_temp, "output/goa_pred_temp.rds")

# also generate samples to propogate uncertainty
pred_temp <- predict(fit, pred_df, nsim = 100)
saveRDS(pred_temp, "output/goa_pred_temp_uncertainty.rds")


# generate temp_index
pred_temp <- predict(fit, pred_df, return_tmb_object = TRUE)
index <- get_index(pred_temp)
n_cells <- length(unique(pred_df$lat_lon))
index$est <- index$log_est / n_cells
index$se <- index$se / n_cells
index$lwr <- index$est - 1.96*index$se
index$upr <- index$est + 1.96*index$se
saveRDS(index, "output/temp_index_goa.rds")

# generate index for depths < 250
pred_df$depth <- exp(pred_df$logdepth_orig)
sub <- dplyr::filter(pred_df, abs(depth)<250)
pred_temp <- predict(fit, sub, return_tmb_object = TRUE)
index <- get_index(pred_temp)
n_cells <- length(unique(sub$lat_lon))
index$est <- index$log_est / n_cells
index$se <- index$se / n_cells
index$lwr <- index$est - 1.96*index$se
index$upr <- index$est + 1.96*index$se
saveRDS(index, "output/temp_index_goa_250.rds")

# generate index for depths 250 - 500
sub <- dplyr::filter(pred_df, abs(depth)>=250, abs(depth) < 500)
pred_temp <- predict(fit, sub, return_tmb_object = TRUE)
index <- get_index(pred_temp)
n_cells <- length(unique(sub$lat_lon))
index$est <- index$log_est / n_cells
index$se <- index$se / n_cells
index$lwr <- index$est - 1.96*index$se
index$upr <- index$est + 1.96*index$se
saveRDS(index, "output/temp_index_goa_250_500.rds")

