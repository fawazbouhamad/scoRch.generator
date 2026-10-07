test_that("warm-season months form one contiguous calendar run", {
  validate <- scoRch.generator:::validate_season_months
  season_start <- scoRch.generator:::season_start_month

  expect_equal(validate(4:9), 4:9)
  expect_equal(validate(c(11, 12, 1, 2, 3)), c(1L, 2L, 3L, 11L, 12L))
  expect_equal(season_start(c(11, 12, 1, 2, 3)), 11L)
  expect_equal(validate(1:12), 1:12)
  expect_equal(season_start(1:12), 1L)
  expect_equal(validate(c(4, 5, 5, 6)), 4:6)

  expect_error(validate(c(11, 12, 1, 3)), "contiguous season")
  expect_error(validate(c(1, 3, 4)), "contiguous season")
  expect_error(validate(c(0, 1)), "between 1 and 12")
  expect_error(validate(c(1, NA)), "between 1 and 12")
})

test_that("configuration rejects seasons with more than one start month", {
  read_config <- scoRch.generator:::read_config
  expect_error(read_config(list(period = list(warm_season_months = c(11, 12, 1, 3))),
                           input_required = FALSE), "contiguous season")
  cfg <- read_config(list(period = list(warm_season_months = c(11, 12, 1, 2, 3))),
                     input_required = FALSE)
  expect_equal(cfg$period$warm_season_months, c(11, 12, 1, 2, 3))
  cfg <- read_config(list(period = list(warm_season_months = 1:12)),
                     input_required = FALSE)
  expect_equal(cfg$period$warm_season_months, 1:12)
})

test_that("explicit stage metadata rejects an ambiguous season", {
  date <- as.Date("2001-01-01")
  clusters <- structure(list(
    clusters = data.frame(cluster_id = 1L),
    daily_settings = data.frame(date = date, n_clusters = 1L,
                                sequence_eps = 1, sequence_min_samples = 1L),
    dates = date, season_months = c(11, 12, 1, 3)), class = "scorch_clusters")
  ellipses <- data.frame(ellipse_id = 1L, cluster_id = 1L, date = date,
                         area_km2 = 100, axis_ratio = 0.5,
                         azimuth_north_cw_deg = 20)
  expect_error(classify_events(clusters, ellipses), "contiguous season")
})
