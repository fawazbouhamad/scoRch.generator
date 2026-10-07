test_that("a day without clusters yields the full empty ellipse schema", {
  dates <- as.Date("2000-06-01") + 0:2
  tmax <- tmax_from_array(array(30, c(3, 3, 3)), dates, 1:3, 1:3)
  regional <- select_regional_days(detect_heatwaves(tmax))
  clusters <- cluster_heatwaves(regional, min_samples_values = 1000)
  expect_equal(nrow(clusters$clusters), 0L)

  ellipses <- fit_ellipses(clusters, tmax, scale_factor = 1.5)
  expect_equal(nrow(ellipses), 0L)
  expect_named(ellipses, c(
    "ellipse_id", "cluster_id", "date", "cluster_number_in_day", "n_member_cells",
    "centroid_lon_unweighted", "centroid_lat_unweighted", "eigenvalue_major_km2",
    "eigenvalue_minor_km2", "major_axis_km", "minor_axis_km", "area_km2",
    "axis_ratio", "orientation_east_ccw_deg", "azimuth_north_cw_deg",
    "major_axis_east", "major_axis_north", "centroid_lon_weighted",
    "centroid_lat_weighted", "tmax_weight_sum_c", "tmax_min_c", "tmax_max_c"))
  expect_s3_class(ellipses$date, "Date")
  expect_equal(attr(ellipses, "scale_factor"), 1.5)
})
