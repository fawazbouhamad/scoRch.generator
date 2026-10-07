# Build the small test fixtures in tests/testthat/fixtures from the study's
# reproducibility repository (github.com/fawazbouhamad/compound-heatwave-typologies-SCORCH)
# and its processed temperature file. Run from the package root:
#   Rscript data-raw/make_test_fixtures.R path/to/compound-heatwave-typologies-SCORCH
library(ncdf4)
ref <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(ref) || !dir.exists(ref)) stop("give the path of the reproducibility repository")
out <- file.path("tests", "testthat", "fixtures")
catalogs <- file.path(ref, "output", "catalogs")
modeling <- file.path(ref, "output", "modeling")

nc <- nc_open(file.path(ref, "input", "tmax_processed.nc"))
lon <- nc$dim$lon$vals; lat <- nc$dim$lat$vals
dates <- as.Date("1940-01-01") + nc$dim$time$vals
cell_of <- function(id) list(lon_index = (id - 1) %% length(lon) + 1, lat_index = (id - 1) %/% length(lon) + 1)

# One cell's complete daily Tmax series with its catalog events and threshold.
cell_id <- 900L
c <- cell_of(cell_id)
series <- as.numeric(ncvar_get(nc, "tmax", start = c(c$lon_index, c$lat_index, 1), count = c(1, 1, -1)))
events <- read.csv(file.path(catalogs, "01_heatwave_events", "heatwave_events.csv"))
thresholds <- read.csv(file.path(catalogs, "01_heatwave_events", "cell_thresholds.csv"))
saveRDS(list(cell_id = cell_id, lon = lon[c$lon_index], lat = lat[c$lat_index], dates = dates, tmax = series,
             threshold = thresholds$threshold_tmax_c[thresholds$cell_id == cell_id],
             events = events[events$cell_id == cell_id, ]),
        file.path(out, "study_cell_series.rds"), compress = "xz")

# The heatwave cells of one run of consecutive selected days (compound event 2)
# with their catalog clusters and settings.
days <- format(seq(as.Date("1987-07-23"), as.Date("1987-07-27"), by = "day"))
cells <- read.csv(file.path(catalogs, "03_extreme_heatwave_clusters", "cluster_cells.csv"))
settings <- read.csv(file.path(catalogs, "03_extreme_heatwave_clusters", "daily_settings.csv"))
# The settings of a run of consecutive days are named sequence_* in the package.
settings$sequence_start_date <- ave(settings$date, settings$compound_event_id, FUN = min)
names(settings)[match(c("event_eps", "event_min_samples"), names(settings))] <- c("sequence_eps", "sequence_min_samples")
settings <- settings[, c("date", "sequence_start_date", "n_heatwave_cells", "modal_cluster_counts", "modal_frequency", "n_pairs_retained",
                         "daily_eps", "daily_min_samples_mean", "daily_min_samples", "sequence_eps", "sequence_min_samples", "n_clusters")]
write.csv(cells[cells$date %in% days, c("date", "cell_id", "lat", "lon", "local_event_id", "dbscan_label", "is_core_cell", "n_cells_within_eps")],
          file.path(out, "study_day_cells.csv"), row.names = FALSE)
write.csv(settings[settings$date %in% days, ], file.path(out, "study_day_settings.csv"), row.names = FALSE)

# Member cells and Tmax of three clusters with their catalog ellipses.
ellipses <- read.csv(file.path(catalogs, "04_extreme_heatwave_ellipses", "ellipses.csv"))
chosen <- c(1L, 2L, 400L)
members <- cells[cells$cluster_id %in% chosen & !is.na(cells$cluster_id), ]
members$tmax_c <- vapply(seq_len(nrow(members)), function(i) {
  c <- cell_of(members$cell_id[i])
  as.numeric(ncvar_get(nc, "tmax", start = c(c$lon_index, c$lat_index, match(as.Date(members$date[i]), dates)), count = c(1, 1, 1)))
}, 0)
write.csv(members[, c("cluster_id", "date", "cell_id", "lat", "lon", "tmax_c")], file.path(out, "study_cluster_cells.csv"), row.names = FALSE)
write.csv(ellipses[ellipses$ellipse_id %in% chosen, ], file.path(out, "study_ellipses.csv"), row.names = FALSE)
nc_close(nc)

# The power-law samples with the catalog fits.
pl <- file.path(modeling, "power_law")
areas <- rbind(data.frame(dataset = "daily_maxima", area_km2 = read.csv(file.path(pl, "daily_max_area.csv"))$area_km2),
               data.frame(dataset = "event_maxima", area_km2 = read.csv(file.path(pl, "event_max_area.csv"))$area_km2))
write.csv(areas, file.path(out, "study_power_law_areas.csv"), row.names = FALSE)
write.csv(read.csv(file.path(pl, "power_law_fits.csv"))[, c("dataset", "n", "n_tail", "xmin_km2", "alpha", "ks_distance", "p_value", "n_exceed", "reps", "seed")],
          file.path(out, "study_power_law_fits.csv"), row.names = FALSE)

# Projected centroid coordinates (pyproj, Lambert azimuthal equal-area, WGS84).
centroids <- read.csv(file.path(modeling, "lgcp", "centroids.csv"))
write.csv(centroids[seq(1, nrow(centroids), by = 40), c("ellipse_id", "centroid_lon", "centroid_lat", "x_km", "y_km")],
          file.path(out, "study_centroids_projected.csv"), row.names = FALSE)
cat("fixtures written:\n"); print(file.info(list.files(out, full.names = TRUE))["size"])
