test_that("state outlines are drawn only on maps over the United States", {
  overlaps <- scoRch.generator:::overlaps_us_states
  expect_true(overlaps(c(-104, -94, 34, 44)))       # central Great Plains
  expect_true(overlaps(c(-70, -60, 40, 50)))        # touches the north-east corner
  expect_false(overlaps(c(20, 70, 10, 46)))         # the SCORCH study region
  expect_false(overlaps(c(-60, -30, -40, -10)))     # South America
  expect_false(overlaps(c(-104, -94, 50, 60)))      # north of the database's extent
})

test_that("event snapshot figures size their canvas by the panels they draw", {
  specs <- scoRch.generator:::figure_specs()
  # A tiny result with one Type 3 event of two days and nothing else.
  dates <- as.Date(c("2000-07-01", "2000-07-02"))
  result <- list(
    input = list(grid = list(lon = 1:4, lat = 1:2, lon_step = 1, lat_step = 1)),
    config = list(figures = list(representative_events = list())),
    events = list(events = data.frame(compound_event_id = 1L, start_date = dates[1], end_date = dates[2],
                                      duration_days = 2L, event_type = 3L, largest_ellipse_area_km2 = 1),
                  event_days = data.frame(date = dates, compound_event_id = 1L, n_clusters = 1L)))
  ratio <- scoRch.generator:::extent_ratio(result)
  expect_equal(specs$consistent_multiday_events$size(result)[2], 0.9 + 0.5 + 1 * (4.6 * ratio + 0.3 + 0.45))
  expect_equal(specs$single_day_events$size(result)[1], 1 * (5.3 + 0.45 + 0.1))   # no Type 1 or 2: one column
  expect_equal(specs$mixed_multiday_events$size(result)[2], 0.9 + 0.5 + 1 * (4.4 * ratio + 0.3 + 0.45))
  two_rows <- result
  two_rows$events$events <- rbind(two_rows$events$events,
                                  data.frame(compound_event_id = 2L, start_date = dates[1] + 10, end_date = dates[2] + 10,
                                             duration_days = 2L, event_type = 3L, largest_ellipse_area_km2 = 1))
  two_rows$events$event_days <- rbind(two_rows$events$event_days,
                                      data.frame(date = dates + 10, compound_event_id = 2L, n_clusters = 1L))
  expect_equal(specs$consistent_multiday_events$size(two_rows)[2], 0.9 + 0.5 + 2 * (4.6 * ratio + 0.3 + 0.45))
  expect_equal(specs$consistent_multiday_events$dpi, 600)
  expect_equal(specs$ellipse_spatial_patterns$dpi, 500)
})
