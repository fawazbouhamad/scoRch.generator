example_file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")

test_that("the example NetCDF file is read into the expected structure", {
  tmax <- read_tmax(example_file)
  expect_s3_class(tmax, "scorch_tmax")
  expect_equal(nrow(tmax$cells), 256)
  expect_equal(dim(tmax$tmax), c(5490, 256))
  expect_equal(range(tmax$dates), as.Date(c("1996-04-01", "2025-09-30")))
  expect_equal(c(tmax$grid$lon_step, tmax$grid$lat_step), c(1, 1))
  expect_equal(tmax$season_months, 4:9)
  expect_false(anyNA(tmax$tmax))
  # Cells run west to east within each latitude row, rows south to north.
  expect_equal(tmax$cells$lon[1:3], c(38.5, 39.5, 40.5))
  expect_equal(tmax$cells$lat[c(1, 17)], c(22.5, 23.5))
  july <- read_tmax(example_file, months = 7, start = "2000-01-01", end = "2000-12-31")
  expect_equal(length(july$dates), 31)
  expect_output(print(july), "256 cells")
})

test_that("arrays are validated, oriented and converted", {
  dates <- as.Date("2000-06-01") + 0:9
  lon <- c(10, 11, 12)
  lat <- c(50, 49)                      # descending: must be flipped
  values <- array(seq_len(10 * 2 * 3), c(10, 2, 3)) + 273.15
  expect_message(tmax <- tmax_from_array(values, dates, lon, lat, units = "K"), "Kelvin")
  expect_equal(tmax$grid$lat, c(49, 50))
  expect_equal(tmax$tmax[1, ], c(values[1, 2, ], values[1, 1, ]) - 273.15)
  masked <- values - 273.15
  masked[, 1, 1] <- NA                  # one cell missing on every date
  expect_message(tmax <- tmax_from_array(masked, dates, lon, lat), "excluded")
  expect_equal(nrow(tmax$cells), 5)
  partial <- values - 273.15
  partial[3, 1, 1] <- NA
  expect_error(tmax_from_array(partial, dates, lon, lat), "missing values")
  expect_error(tmax_from_array(values, dates, c(10, 11, 13), lat), "evenly spaced")
  expect_error(tmax_from_array(values, rep(dates[1], 10), lon, lat), "duplicated")
  expect_error(tmax_from_array(values, dates, lon, lat, units = "F"), "not recognised")
  expect_error(tmax_from_array(values, dates, lon, lat, months = 1), "No dates are left")
})

test_that("CF time units are decoded", {
  decode_time <- scoRch.generator:::decode_time
  expect_equal(decode_time(c(0, 1), "days since 2000-01-01"), as.Date(c("2000-01-01", "2000-01-02")))
  expect_equal(decode_time(36, "hours since 2000-01-01 00:00:00"), as.Date("2000-01-02"))
  expect_equal(decode_time(0.5, "days since 2000-01-01 12:00:00"), as.Date("2000-01-02"))
  # The seconds part of the origin matters on both sides of midnight.
  expect_equal(decode_time(c(0, 1), "seconds since 2000-01-01 23:59:59"),
               as.Date(c("2000-01-01", "2000-01-02")))
  expect_equal(decode_time(c(0.4, 0.5), "seconds since 2000-01-01 23:59:59.5"),
               as.Date(c("2000-01-01", "2000-01-02")))
  # Both integer minute offsets and a fractional day can land exactly at midnight.
  expect_equal(decode_time(c(0, 1), "minutes since 2000-01-01 23:59"),
               as.Date(c("2000-01-01", "2000-01-02")))
  expect_equal(decode_time(c(0.25, 0.5), "days since 2000-01-01 12:00"),
               as.Date(c("2000-01-01", "2000-01-02")))
  expect_equal(decode_time(-1, "seconds since 2000-01-02 00:00:00"), as.Date("2000-01-01"))
  expect_equal(decode_time(0, "hours since 2000-01-01 01:00:00 +01:00"), as.Date("2000-01-01"))
  expect_equal(decode_time(0, "hours since 2000-01-01 00:00:00 +01:00"), as.Date("1999-12-31"))
  expect_error(decode_time(1, "months since 2000-01-01"), "not supported")
  expect_error(decode_time(1, "days since 2000-01-01", calendar = "360_day"), "calendar")
  expect_error(decode_time(1, "2000-01-01"), "days since")
  expect_error(decode_time(0, "days since 2000-01-01 12:61:00"), "valid time")
})

test_that("a scorch_tmax can be restricted to the configured period", {
  dates <- as.Date(c("2000-03-31", "2000-04-01", "2000-04-02", "2000-09-30", "2000-10-01"))
  values <- array(seq_len(5 * 2 * 2), dim = c(5, 2, 2))
  tmax <- tmax_from_array(values, dates, lon = c(40, 41), lat = c(30, 31))
  subset <- scoRch.generator:::subset_tmax_period(tmax, months = c(4, 9),
                                                   start = "2000-04-02", end = "2000-09-30")
  expect_s3_class(subset, "scorch_tmax")
  expect_equal(subset$dates, dates[c(3, 4)])
  expect_equal(subset$tmax, tmax$tmax[c(3, 4), , drop = FALSE])
  expect_identical(subset$cells, tmax$cells)
  expect_identical(subset$grid, tmax$grid)
  expect_identical(subset$source, tmax$source)
  expect_equal(subset$season_months, c(4, 9))
  expect_equal(length(tmax$dates), 5)  # original object was not modified
  single <- scoRch.generator:::subset_tmax_period(tmax, months = 4,
                                                   start = "2000-04-02", end = "2000-04-02")
  expect_equal(dim(single$tmax), c(1, 4))
  expect_error(scoRch.generator:::subset_tmax_period(tmax, months = 2), "No dates are left")
})

test_that("the shipped SCORCH configuration is the source of the study settings", {
  shipped <- system.file("scorch_config.yaml", package = "scoRch.generator")
  expect_true(nzchar(shipped))
  defaults <- scoRch.generator:::scorch_defaults()
  # The study settings, written out once more here so that a change to the
  # shipped file cannot pass unnoticed.
  study <- list(
    input = list(file = NULL, format = "auto", variable = "auto", longitude = "auto", latitude = "auto",
                 time = "auto", units = "auto", era5_cell_size_deg = 1),
    output = list(directory = "scorch_output"),
    period = list(warm_season_months = 4:9, start_date = NULL, end_date = NULL),
    heatwaves = list(threshold_percentile = 95, min_duration_days = 3, min_exceeding_days = 3),
    regional_days = list(percentile = 97.5),
    clustering = list(eps_values = c(1, 1.5, 2, 2.5, 3, 3.5, 4), min_samples_values = 4:12),
    ellipses = list(scale_factor = 1.25),
    power_law = list(bootstrap_repetitions = 5000, seed_daily_maxima = 20261020,
                     seed_event_maxima = 20261120),
    lgcp = list(covariates = c("lon", "lat", "mean_tmax", "std_tmax"), raster_km = 25,
                window_margin_km = 80),
    figures = list(representative_events = list(type_1 = NULL, type_2 = NULL, type_3 = NULL, type_4 = NULL)))
  expect_identical(defaults, study)
  # The stage functions' own defaults agree with the shipped configuration.
  expect_equal(as.list(formals(detect_heatwaves))[-1], defaults$heatwaves)
  expect_equal(formals(select_regional_days)$percentile, defaults$regional_days$percentile)
  expect_equal(eval(formals(cluster_heatwaves)$eps_values), defaults$clustering$eps_values)
  expect_equal(eval(formals(cluster_heatwaves)$min_samples_values), defaults$clustering$min_samples_values)
  expect_equal(formals(fit_ellipses)$scale_factor, defaults$ellipses$scale_factor)
  expect_equal(unname(unlist(formals(fit_power_law)[-1])), unname(unlist(defaults$power_law)))
  expect_equal(eval(formals(fit_lgcp)$covariates), defaults$lgcp$covariates)
  expect_equal(as.list(formals(fit_lgcp))[c("raster_km", "window_margin_km")],
               defaults$lgcp[c("raster_km", "window_margin_km")])
  expect_equal(eval(formals(read_tmax)$months), defaults$period$warm_season_months)

  expect_identical(scoRch.generator:::read_config(NULL, input_required = FALSE),
                   scoRch.generator:::read_config(list(), input_required = FALSE))
  expect_error(scoRch.generator:::read_config(NULL), "No input file is set")
  expect_error(run_scorch(), "No input file is set")
})

test_that("an editable copy of the SCORCH configuration overrides only what it changes", {
  path <- tempfile(fileext = ".yaml")
  expect_identical(write_scorch_config(path), path)
  expect_identical(readLines(path), readLines(system.file("scorch_config.yaml", package = "scoRch.generator")))
  expect_error(write_scorch_config(path), "already exists")
  expect_error(scoRch.generator:::read_config(path), "No input file is set")
  lines <- readLines(path)
  lines <- sub("^  file: null ", sprintf("  file: '%s' ", example_file), lines)
  lines <- sub("threshold_percentile: 95 ", "threshold_percentile: 90 ", lines, fixed = TRUE)
  writeLines(lines, path)
  cfg <- scoRch.generator:::read_config(path)
  study <- scoRch.generator:::read_config(list(input = list(file = example_file)))
  expect_equal(cfg$input$file, example_file)
  expect_equal(cfg$heatwaves$threshold_percentile, 90)
  expect_equal(cfg$heatwaves[-1], study$heatwaves[-1])
  expect_equal(cfg[-match(c("input", "heatwaves"), names(cfg))],
               study[-match(c("input", "heatwaves"), names(study))])

  # A configuration with only some settings takes the rest from the shipped one.
  partial <- tempfile(fileext = ".yaml")
  writeLines(c("input:", sprintf("  file: '%s'", example_file),
               "clustering:", "  eps_values: [1, 2.5]", "lgcp:", "  raster_km: 50"), partial)
  cfg <- scoRch.generator:::read_config(partial)
  expect_equal(cfg$clustering$eps_values, c(1, 2.5))
  expect_equal(cfg$clustering$min_samples_values, study$clustering$min_samples_values)
  expect_equal(cfg$lgcp$raster_km, 50)
  expect_equal(cfg$lgcp[c("covariates", "window_margin_km")], study$lgcp[c("covariates", "window_margin_km")])
  expect_identical(cfg[-match(c("clustering", "lgcp"), names(cfg))],
                   study[-match(c("clustering", "lgcp"), names(study))])
})

test_that("the example configuration is written, read and completed with defaults", {
  path <- tempfile(fileext = ".yaml")
  scorch_template(path)
  expect_error(scorch_template(path), "already exists")
  cfg <- scoRch.generator:::read_config(path)
  expect_equal(cfg$input$file, example_file)
  expect_equal(cfg[-1], scoRch.generator:::read_config(list(input = list(file = example_file)))[-1])
  expect_equal(cfg$power_law$bootstrap_repetitions, 5000)
  expect_equal(cfg$clustering$eps_values, c(1, 1.5, 2, 2.5, 3, 3.5, 4))
  expect_type(cfg$clustering$eps_values, "double")
  expect_null(cfg$period$start_date)
  fast <- scorch_template(tempfile(fileext = ".yaml"), fast = TRUE)
  expect_equal(scoRch.generator:::read_config(fast)$power_law$bootstrap_repetitions, 200)
  expect_match(readLines(fast)[1], "FAST DEMONSTRATION")
  minimal <- list(input = list(file = example_file), output = list(directory = tempdir()))
  cfg <- scoRch.generator:::read_config(minimal)
  expect_equal(cfg$regional_days$percentile, 97.5)
  expect_error(scoRch.generator:::read_config(list(input = list(file = example_file), extra = list())), "Unknown settings")
  expect_error(scoRch.generator:::read_config(list(input = list(file = example_file, foo = 1))), "Unknown settings")
  expect_error(scoRch.generator:::read_config(list(output = list(directory = "x"))), "input: file")
  expect_error(scoRch.generator:::read_config(list(input = list(file = "missing.nc"))), "does not exist")
  bad <- list(input = list(file = example_file), period = list(warm_season_months = 13))
  expect_error(scoRch.generator:::read_config(bad), "warm_season_months")
  bad <- list(input = list(file = example_file), period = list(start_date = "01-02-2000"))
  expect_error(scoRch.generator:::read_config(bad), "YYYY-MM-DD")
  ok <- list(input = list(file = example_file), period = list(start_date = "2000-02-01"))
  expect_equal(scoRch.generator:::read_config(ok)$period$start_date, as.Date("2000-02-01"))
  bad <- list(input = list(file = example_file), figures = list(representative_events = list(type_5 = "2000-01-01")))
  expect_error(scoRch.generator:::read_config(bad), "representative_events")
})

test_that("configuration values are checked before analysis starts", {
  read <- scoRch.generator:::read_config
  one_setting <- function(section, key, value) {
    cfg <- list(input = list(file = example_file))
    if (is.null(cfg[[section]])) cfg[[section]] <- list()
    cfg[[section]][key] <- list(value)
    cfg
  }

  for (value in list("", " ", NA_character_, c("a", "b"), 7)) {
    expect_error(read(one_setting("input", "variable", value)), "input: variable")
    expect_error(read(one_setting("output", "directory", value)), "output: directory")
  }
  expect_error(read(one_setting("input", "file", NA_character_)), "input: file")
  expect_error(read(one_setting("input", "file", file.path(tempdir(), "missing"))), "input file does not exist")
  expect_error(read(one_setting("input", "units", "F")), "not recognised")
  expect_error(read(list(input = list(file = example_file, longitude = "lat", latitude = "lat"))), "must be distinct")
  expect_silent(read(list(output = list(directory = tempdir())), input_required = FALSE))
  expect_error(read(one_setting("input", "file", c("a.nc", "")), input_required = FALSE), "input: file")
  existing <- tempfile()
  writeLines("not a folder", existing)
  expect_error(read(one_setting("output", "directory", existing)), "existing file")
  expect_error(read(list(input = list(file = example_file), input = list(file = example_file))), "repeats a section")
  expect_error(read(list(input = list(file = example_file, file = example_file))), "repeats a setting")

  invalid <- list(
    list("heatwaves", "threshold_percentile", NA_real_),
    list("heatwaves", "threshold_percentile", 101),
    list("heatwaves", "min_duration_days", 2.5),
    list("heatwaves", "min_exceeding_days", 0),
    list("regional_days", "percentile", Inf),
    list("regional_days", "percentile", -1),
    list("clustering", "eps_values", c(1, Inf)),
    list("clustering", "eps_values", c(1, 0)),
    list("clustering", "eps_values", c(1, 1)),
    list("clustering", "min_samples_values", c(2, 2.5)),
    list("clustering", "min_samples_values", c(2, NA)),
    list("ellipses", "scale_factor", 0),
    list("ellipses", "scale_factor", Inf),
    list("power_law", "bootstrap_repetitions", 0),
    list("power_law", "bootstrap_repetitions", 1.5),
    list("power_law", "seed_daily_maxima", 2147483648),
    list("power_law", "seed_event_maxima", NA_real_),
    list("lgcp", "raster_km", 0),
    list("lgcp", "window_margin_km", -1),
    list("lgcp", "covariates", "foo"),
    list("lgcp", "covariates", c("lon", "lon")),
    list("lgcp", "covariates", character())
  )
  for (case in invalid) {
    expect_error(read(one_setting(case[[1]], case[[2]], case[[3]])), case[[2]])
  }

  expect_error(read(list(input = list(file = example_file),
                         period = list(start_date = "2001-01-01", end_date = "2000-12-31"))),
               "start_date.*before.*end_date")
  expect_error(read(one_setting("period", "warm_season_months", c(4, 4, 5))), "distinct")
  expect_error(read(one_setting("period", "warm_season_months", c(11, 1, 3))), "contiguous")
  expect_equal(read(one_setting("period", "warm_season_months", c(11, 12, 1, 2)))$period$warm_season_months,
               c(11, 12, 1, 2))
})

test_that("representative-event overrides have valid dates and counts", {
  read <- scoRch.generator:::read_config
  setting <- function(value, type = "type_3") {
    list(input = list(file = example_file),
         figures = list(representative_events = setNames(list(value), type)))
  }
  expect_equal(read(setting(c("2000-01-01", "2001-01-01")))$figures$representative_events$type_3,
               c("2000-01-01", "2001-01-01"))
  expect_equal(read(setting(as.Date("2000-01-01")))$figures$representative_events$type_3,
               as.Date("2000-01-01"))
  expect_silent(read(list(input = list(file = example_file),
                          figures = list(representative_events = list()))))
  expect_error(read(setting("2000-13-01")), "YYYY-MM-DD")
  expect_error(read(setting("2000-02-30")), "YYYY-MM-DD")
  expect_error(read(setting(c("2000-01-01", "2000-01-02", "2000-01-03"))), "one or two dates")
  expect_error(read(setting(c("2000-01-01", "2000-01-01"))), "repeated date")
  expect_error(read(setting(c("2000-01-01", "2000-01-02"), "type_1")), "one date")
  expect_error(read(setting(1)), "YYYY-MM-DD")
  expect_error(read(list(input = list(file = example_file),
                         figures = list(representative_events = "2000-01-01"))), "named event types")
  expect_error(read(list(input = list(file = example_file),
                         figures = list(representative_events = list(type_1 = "2000-01-01",
                                                                      type_1 = "2000-01-02")))), "repeats an event type")
})
