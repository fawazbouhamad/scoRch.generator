fixture <- function(name) test_path("fixtures", name)
heatwave_runs <- scoRch.generator:::heatwave_runs

test_that("heatwave runs bridge single days, split at double gaps and never cross calendar gaps", {
  no_gap <- rep(FALSE, 16)
  runs <- heatwave_runs(c(1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1), no_gap, 3, 3)
  expect_equal(runs, data.frame(start = c(1L, 9L), end = c(6L, 16L), ones = c(5L, 5L)))
  # A trailing or leading non-exceeding day is trimmed; two days too short.
  expect_equal(heatwave_runs(c(0, 1, 1, 1, 0), rep(FALSE, 5), 3, 3), data.frame(start = 2L, end = 4L, ones = 3L))
  expect_equal(nrow(heatwave_runs(c(1, 1, 0, 0, 1, 1), rep(FALSE, 6), 3, 3)), 0)
  expect_equal(heatwave_runs(c(1, 0, 1, 1), rep(FALSE, 4), 3, 3), data.frame(start = 1L, end = 4L, ones = 3L))
  expect_equal(nrow(heatwave_runs(c(1, 0, 1), rep(FALSE, 3), 3, 3)), 0)
  # Six exceeding days with a season break after day 3 are two heatwaves.
  gap <- c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE)
  expect_equal(heatwave_runs(rep(1, 6), gap, 3, 3)$start, c(1L, 4L))
  expect_equal(heatwave_runs(rep(1, 6), rep(FALSE, 6), 3, 3)$end, 6L)
})

test_that("a study cell reproduces its catalog threshold and local heatwaves", {
  cell <- readRDS(fixture("study_cell_series.rds"))
  n <- length(cell$dates)
  values <- array(rep(cell$tmax, 4), c(n, 2, 2))
  tmax <- tmax_from_array(values, cell$dates, c(cell$lon, cell$lon + 1), c(cell$lat, cell$lat + 1))
  heatwaves <- detect_heatwaves(tmax)
  expect_equal(heatwaves$thresholds$threshold_tmax_c[1], cell$threshold, tolerance = 1e-12)
  mine <- heatwaves$events[heatwaves$events$cell_id == 1, ]
  expect_equal(nrow(mine), nrow(cell$events))
  for (column in c("duration_days", "exceeding_days", "bridged_days", "peak_tmax_c")) {
    expect_equal(mine[[column]], cell$events[[column]], info = column)
  }
  for (column in c("start_date", "end_date", "peak_date")) {
    expect_equal(as.character(mine[[column]]), cell$events[[column]], info = column)
  }
})

test_that("the regional threshold uses the 'higher' quantile rule", {
  quantile_higher <- scoRch.generator:::quantile_higher
  expect_equal(quantile_higher(1:100, 0.975), 98)
  expect_equal(quantile_higher(c(5, 1, 3), 0.5), 3)
  expect_equal(quantile_higher(rep(0, 10), 0.975), 0)
})

test_that("DBSCAN settings, pooling and labels reproduce a study sequence", {
  cells <- read.csv(fixture("study_day_cells.csv"))
  settings <- read.csv(fixture("study_day_settings.csv"))
  days <- as.Date(settings$date)
  regional <- structure(list(
    selected_days = data.frame(date = days, n_heatwave_cells = settings$n_heatwave_cells),
    selected_cells = data.frame(date = as.Date(cells$date), cell_id = cells$cell_id, lat = cells$lat,
                                lon = cells$lon, local_event_id = cells$local_event_id),
    grid = list(lon_step = 1, lat_step = 1)), class = "scorch_regional")
  clusters <- cluster_heatwaves(regional)
  daily <- clusters$daily_settings
  expect_equal(daily$modal_cluster_counts, as.character(settings$modal_cluster_counts))
  expect_equal(daily$n_pairs_retained, settings$n_pairs_retained)
  expect_equal(daily$daily_eps, settings$daily_eps, tolerance = 1e-12)
  expect_equal(daily$daily_min_samples, settings$daily_min_samples)
  expect_equal(daily$sequence_eps, settings$sequence_eps, tolerance = 1e-12)
  expect_equal(daily$sequence_min_samples, settings$sequence_min_samples)
  expect_equal(clusters$cluster_cells$dbscan_label, cells$dbscan_label)
  expect_equal(clusters$cluster_cells$is_core_cell, cells$is_core_cell)
  expect_equal(clusters$cluster_cells$n_cells_within_eps, cells$n_cells_within_eps)
  expect_equal(nrow(clusters$clusters), sum(settings$n_clusters))
})

test_that("ellipse geometry and weighted centroids reproduce catalog ellipses", {
  members <- read.csv(fixture("study_cluster_cells.csv"))
  expected <- read.csv(fixture("study_ellipses.csv"))
  for (id in expected$ellipse_id) {
    g <- members[members$cluster_id == id, ]
    g <- g[scoRch.generator:::longitude_major_order(g$lon, g$lat), ]
    geometry <- scoRch.generator:::ellipse_geometry(g$lon, g$lat, 1.25)
    row <- expected[expected$ellipse_id == id, ]
    for (column in c("major_axis_km", "minor_axis_km", "area_km2", "axis_ratio", "azimuth_north_cw_deg",
                     "major_axis_east", "major_axis_north")) {
      expect_equal(geometry[[column]], row[[column]], tolerance = 1e-9, info = column)
    }
    w <- scoRch.generator:::as_single_precision(g$tmax_c)
    expect_equal(sum(g$lon * w) / sum(w), row$centroid_lon_weighted, tolerance = 1e-7)
    expect_equal(sum(g$lat * w) / sum(w), row$centroid_lat_weighted, tolerance = 1e-7)
  }
  single <- scoRch.generator:::ellipse_geometry(45, 30, 1.25)
  expect_equal(single$major_axis_km, 2.5)
  expect_equal(single$axis_ratio, 1)
})

test_that("event types, axial means and trend tests follow the study definitions", {
  classify_event <- scoRch.generator:::classify_event
  expect_equal(classify_event(1), 1L)
  expect_equal(classify_event(3), 2L)
  expect_equal(classify_event(c(1, 1, 1)), 3L)
  expect_equal(classify_event(c(2, 3, 2)), 3L)
  expect_equal(classify_event(c(1, 2, 1)), 4L)
  expect_equal(classify_event(c(1, 0)), 4L)
  expect_equal(classify_event(c(0, 2)), 4L)
  expect_error(classify_event(0), "at least one cluster")
  axial_mean <- scoRch.generator:::axial_mean
  expect_equal(axial_mean(c(10, 20))$mean, 15)
  expect_equal(axial_mean(c(80, -80))$mean, 90)
  expect_equal(axial_mean(c(45, 45))$resultant, 1)
  expect_true(is.na(axial_mean(c(0, 90))$mean))
  mk <- scoRch.generator:::mann_kendall(1:10)
  expect_equal(mk$s, 45)
  expect_equal(mk$z, 44 / sqrt(125))
  expect_equal(mk$result, "increasing")
  expect_equal(scoRch.generator:::mann_kendall(c(3, 1, 2, 3))$result, "no significant trend")
  expect_equal(scoRch.generator:::sens_slope(1:10, 2 * (1:10) + 1), 2)
})

test_that("seasons that span the new year are counted in the year they start", {
  season_start_month <- scoRch.generator:::season_start_month
  season_year <- scoRch.generator:::season_year
  expect_equal(season_start_month(4:9), 4L)
  expect_equal(season_start_month(c(11, 12, 1, 2, 3)), 11L)
  expect_equal(season_start_month(1:12), 1L)
  expect_equal(season_year(as.Date(c("2000-12-20", "2001-01-15", "2001-11-05")), 11), c(2000L, 2000L, 2001L))
  expect_equal(season_year(as.Date("2001-07-01"), 4), 2001L)
})

test_that("zero-cluster days affect event type and annual counts include early seasons", {
  selected <- as.Date(c("2000-07-01", "2001-07-01", "2001-07-02", "2002-07-01"))
  daily <- data.frame(date = selected, n_clusters = c(0L, 1L, 0L, 1L),
                      sequence_eps = rep(1, 4), sequence_min_samples = rep(1L, 4))
  clusters <- structure(list(
    clusters = data.frame(cluster_id = 1:2), daily_settings = daily,
    dates = as.Date(paste0(1999:2002, "-07-01"))), class = "scorch_clusters")
  ellipses <- data.frame(ellipse_id = 1:2, cluster_id = 1:2,
                         date = selected[c(2, 4)], area_km2 = c(100, 200),
                         axis_ratio = c(0.5, 0.7), azimuth_north_cw_deg = c(20, 30))
  expect_message(events <- classify_events(clusters, ellipses),
                 "1 run\\(s\\) of selected days formed no cluster")
  expect_equal(events$events$daily_cluster_counts, c("1-0", "1"))
  expect_equal(events$events$event_type, c(4L, 1L))
  expect_equal(events$events$min_daily_clusters, c(0L, 1L))
  expect_equal(events$event_days$n_clusters, c(1L, 0L, 1L))
  expect_equal(events$annual_counts$year, 1999:2002)
  expect_equal(events$annual_counts$all_events, c(0, 0, 1, 1))
  expect_equal(events$annual_counts$type_4_events, c(0, 0, 1, 0))
})

test_that("years without analyzed temperatures are not counted as zero-event seasons", {
  dates <- as.Date(c("2001-07-01", "2003-07-01"))
  clusters <- structure(list(
    clusters = data.frame(cluster_id = 1:2),
    daily_settings = data.frame(date = dates, n_clusters = c(1L, 1L),
                                sequence_eps = c(1, 1), sequence_min_samples = c(1L, 1L)),
    dates = as.Date(c("2000-07-01", "2001-07-01", "2003-07-01"))),
    class = "scorch_clusters")
  ellipses <- data.frame(ellipse_id = 1:2, cluster_id = 1:2, date = dates,
                         area_km2 = c(100, 200), axis_ratio = c(0.5, 0.7),
                         azimuth_north_cw_deg = c(20, 30))
  events <- classify_events(clusters, ellipses)
  expect_equal(events$annual_counts$year, c(2000L, 2001L, 2003L))
  expect_equal(events$annual_counts$all_events, c(0, 1, 1))
})

test_that("a clipped cross-year season keeps its configured start year", {
  dates <- as.Date(c("2000-11-01", "2000-12-01", paste0("2001-01-0", 1:5)))
  values <- array(30, c(length(dates), 3, 3))
  tmax <- tmax_from_array(values, dates, lon = 40:42, lat = 30:32,
                          months = c(11, 12, 1, 2, 3), start = "2001-01-01")
  expect_equal(tmax$season_months, c(11, 12, 1, 2, 3))
  expect_equal(format(tmax$dates[1], "%Y-%m"), "2001-01")

  heatwaves <- detect_heatwaves(tmax)
  regional <- select_regional_days(heatwaves)
  clusters <- cluster_heatwaves(regional, eps_values = 1.5, min_samples_values = 1)
  expect_equal(clusters$season_months, tmax$season_months)
  events <- classify_events(clusters, fit_ellipses(clusters, tmax))
  expect_equal(events$events$start_date, as.Date("2001-01-01"))
  expect_equal(events$annual_counts$year, 2000L)
  expect_equal(events$annual_counts$all_events, 1L)
  expect_equal(events$annual_duration$year, 2000L)
})
