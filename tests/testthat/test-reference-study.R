# Reproduction of the complete study from its processed input, compared with
# the outputs of the study's independent reproducibility workflow
# (github.com/fawazbouhamad/compound-heatwave-typologies-SCORCH). A reference
# folder has that repository's layout: input/tmax_processed.nc and the
# outputs in output/catalogs, output/tables and output/modeling.
#
# SCORCH_REFERENCE_DIR: the final (corrected) reference. Its input is the
#   published dataset (doi:10.5281/zenodo.21717874), in which every 1-degree cell is the mean of
#   its 16 ERA5 0.25-degree points. These are the authoritative results.
# SCORCH_HISTORICAL_REFERENCE_DIR (optional, audit only): the historical first
#   analysis, whose archived input averaged the 45.5 N row from the 45.0 N
#   points only. Kept so that the historical results remain verifiable.
# Each run takes about three minutes.

reproduce_reference <- function(reference, expected) {
  input <- file.path(reference, "input", "tmax_processed.nc")
  skip_if_not(file.exists(input), "input/tmax_processed.nc is missing")
  catalogs <- file.path(reference, "output", "catalogs")
  modeling <- file.path(reference, "output", "modeling")
  same <- function(mine, theirs, columns, tolerance = 0) {
    for (column in columns) {
      if (is.numeric(theirs[[column]]) && tolerance > 0) {
        expect_equal(mine[[column]], theirs[[column]], tolerance = tolerance, info = column)
      } else {
        expect_equal(as.character(mine[[column]]), as.character(theirs[[column]]), info = column)
      }
    }
  }
  tmax <- read_tmax(input)
  expect_equal(c(nrow(tmax$cells), length(tmax$dates)), c(1800, 15738))
  heatwaves <- detect_heatwaves(tmax)
  expect_equal(nrow(heatwaves$events), expected$local_heatwaves)
  same(heatwaves$events, read.csv(file.path(catalogs, "01_heatwave_events", "heatwave_events.csv")),
       c("local_event_id", "cell_id", "start_date", "end_date", "duration_days", "exceeding_days",
         "bridged_days", "peak_date", "peak_tmax_c"))
  regional <- select_regional_days(heatwaves)
  expect_equal(regional$threshold_cells, expected$regional_threshold)
  expect_equal(nrow(regional$selected_days), expected$selected_days)
  same(regional$selected_cells, read.csv(file.path(catalogs, "02_regionally_extensive_heatwaves", "selected_day_cells.csv")),
       c("date", "cell_id", "local_event_id"))
  clusters <- cluster_heatwaves(regional)
  expect_equal(nrow(clusters$clusters), expected$clusters)
  same(clusters$cluster_cells, read.csv(file.path(catalogs, "03_extreme_heatwave_clusters", "cluster_cells.csv")),
       c("date", "cell_id", "dbscan_label", "is_core_cell"))
  ellipses <- fit_ellipses(clusters, tmax)
  reference_ellipses <- read.csv(file.path(catalogs, "04_extreme_heatwave_ellipses", "ellipses.csv"))
  same(ellipses, reference_ellipses, c("major_axis_km", "minor_axis_km", "area_km2", "azimuth_north_cw_deg"), 1e-9)
  # Centroid weights: single precision; the study's text-parsing path differs
  # by one single-precision step for values exactly between two floats.
  same(ellipses, reference_ellipses, c("centroid_lon_weighted", "centroid_lat_weighted"), 1e-7)
  events <- classify_events(clusters, ellipses)
  expect_equal(tabulate(events$events$event_type, 4), expected$types)
  same(events$events, read.csv(file.path(catalogs, "05_compound_heatwave_events", "compound_events.csv")),
       c("start_date", "end_date", "event_type", "daily_cluster_counts", "largest_ellipse_id"))
  same(events$table_1, read.csv(file.path(reference, "output", "tables", "table_1_compound_heatwave_types.csv")),
       c("selected_event_days", "number_of_compound_events", "longest_event_days",
         "mean_duration_days_per_event", "mean_ellipses_per_event"))
  power_law <- fit_power_law(events)
  fits <- read.csv(file.path(modeling, "power_law", "power_law_fits.csv"))
  same(power_law$summary, fits, c("n_tail", "n_exceed"))
  same(power_law$summary, fits, c("xmin_km2", "alpha", "p_value"), 1e-9)
  lgcp <- fit_lgcp(events, tmax)
  parameters <- read.csv(file.path(modeling, "lgcp", "lgcp_parameters.csv"))
  expect_equal(unname(lgcp$parameters[parameters$parameter]), as.numeric(parameters$value), tolerance = 1e-6)
  expect_equal(lgcp$concentration$n_in_zone, expected$centroids_in_zones)
}

test_that("the final (corrected) study input reproduces the reference catalogs, table and models", {
  reference <- Sys.getenv("SCORCH_REFERENCE_DIR")
  skip_if(reference == "", "set SCORCH_REFERENCE_DIR to the final (corrected) reference")
  reproduce_reference(reference, list(
    local_heatwaves = 176061, regional_threshold = 371, selected_days = 395, clusters = 753,
    types = c(3, 3, 20, 25),
    # centroids in the top-20% and top-50% intensity zones: all, daily largest, event largest
    centroids_in_zones = c(267, 189, 29, 537, 326, 45)))
})

test_that("the historical study input still reproduces the historical results (audit)", {
  reference <- Sys.getenv("SCORCH_HISTORICAL_REFERENCE_DIR")
  skip_if(reference == "", "set SCORCH_HISTORICAL_REFERENCE_DIR to audit the historical analysis")
  reproduce_reference(reference, list(
    local_heatwaves = 175978, regional_threshold = 371, selected_days = 395, clusters = 760,
    types = c(3, 4, 20, 24), centroids_in_zones = c(266, 188, 29, 533, 320, 46)))
})
