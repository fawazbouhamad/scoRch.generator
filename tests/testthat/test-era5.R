example_file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")

# Write an ERA5-like NetCDF file of 2-m temperature (`values`: time x
# latitude x longitude, or time x latitude x longitude x expver). New CDS
# files use valid_time in seconds since 1970 and floats; older ones use time
# in hours since 1900 and 16-bit integers with a scale factor and offset.
write_era5 <- function(path, values, seconds, lon, lat, legacy = FALSE, prec = "float") {
  time <- if (legacy) {
    ncdf4::ncdim_def("time", "hours since 1900-01-01 00:00:00.0", seconds / 3600 + 613608, calendar = "gregorian")
  } else {
    ncdf4::ncdim_def("valid_time", "seconds since 1970-01-01", seconds)
  }
  dims <- list(ncdf4::ncdim_def("longitude", "degrees_east", lon), ncdf4::ncdim_def("latitude", "degrees_north", lat))
  if (length(dim(values)) == 4) dims <- c(dims, list(ncdf4::ncdim_def("expver", "", seq_len(dim(values)[4]))))
  dims <- c(dims, list(time))
  order <- if (length(dim(values)) == 4) c(3, 2, 4, 1) else c(3, 2, 1)
  if (legacy) {
    offset <- (max(values, na.rm = TRUE) + min(values, na.rm = TRUE)) / 2
    scale <- (max(values, na.rm = TRUE) - min(values, na.rm = TRUE)) / 65000
    var <- ncdf4::ncvar_def("t2m", "K", dims, missval = -32767, prec = "short")
    nc <- ncdf4::nc_create(path, var)
    ncdf4::ncatt_put(nc, var, "scale_factor", scale, prec = "double")
    ncdf4::ncatt_put(nc, var, "add_offset", offset, prec = "double")
    ncdf4::nc_close(nc)
    nc <- ncdf4::nc_open(path, write = TRUE)
    packed <- round((values - offset) / scale)
    packed[is.na(packed)] <- -32767
    ncdf4::ncvar_put(nc, "t2m", aperm(packed, order))
  } else {
    var <- ncdf4::ncvar_def("t2m", "K", dims, missval = NA, prec = prec)
    nc <- ncdf4::nc_create(path, var)
    ncdf4::ncvar_put(nc, var, aperm(values, order))
  }
  ncdf4::nc_close(nc)
  path
}

hourly_seconds <- function(first_day, n_days, per_day = 24) {
  as.numeric(as.Date(first_day)) * 86400 + (seq_len(n_days * per_day) - 1) * 86400 / per_day
}

# Daily maxima of time x latitude x longitude values with `per_day` steps.
daily_max <- function(values, per_day = 24) {
  n_days <- dim(values)[1] / per_day
  out <- array(NA_real_, c(n_days, dim(values)[2:3]))
  for (d in seq_len(n_days)) out[d, , ] <- apply(values[(d - 1) * per_day + seq_len(per_day), , , drop = FALSE], c(2, 3), max)
  out
}

test_that("hourly ERA5 becomes daily maximum temperature in Celsius on an ascending grid", {
  set.seed(1)
  lon <- c(358, 359, 0, 1)                       # 0..360 longitudes crossing the prime meridian
  lat <- c(2, 1, 0)                              # ERA5 latitudes run north to south
  seconds <- hourly_seconds("2000-06-30", 3)
  values <- array(290 + 15 * runif(72 * 3 * 4), c(72, 3, 4))
  file <- write_era5(tempfile(fileext = ".nc"), values, seconds, lon, lat, prec = "double")
  expect_message(read_era5(file, months = 1:12, cell_size = NULL), "24 values per day")
  tmax <- suppressMessages(read_era5(file, months = 1:12, cell_size = NULL))
  expected <- tmax_from_array(daily_max(values) - 273.15, as.Date(c("2000-06-30", "2000-07-01", "2000-07-02")),
                              lon = c(-2, -1, 0, 1), lat = lat, months = 1:12)
  expect_identical(tmax[c("dates", "cells", "tmax", "grid")], expected[c("dates", "cells", "tmax", "grid")])
  expect_equal(tmax$cells$lon[1:4], c(-2, -1, 0, 1))
  expect_equal(tmax$cells$lat[c(1, 5, 9)], c(0, 1, 2))
  # Months and dates are chosen by calendar day in UTC.
  july <- suppressMessages(read_era5(file, months = 7, cell_size = NULL))
  expect_equal(july$dates, as.Date(c("2000-07-01", "2000-07-02")))
  expect_identical(july$tmax, expected$tmax[2:3, ])
  one <- suppressMessages(read_era5(file, months = 1:12, start = "2000-07-01", end = "2000-07-01", cell_size = NULL))
  expect_identical(one$tmax, expected$tmax[2, , drop = FALSE])
})

test_that("daily maxima are averaged to whole cells as in the SCORCH study", {
  set.seed(2)
  lon <- seq(20, 22, by = 0.25)                  # edges included, as in a region download
  lat <- seq(12, 10, by = -0.25)
  values <- array(295 + 10 * runif(2 * 24 * 9 * 9), c(48, 9, 9))
  values[, 9, 2] <- NA                           # one point without data (lat 10, lon 20.25)
  file <- write_era5(tempfile(fileext = ".nc"), values, hourly_seconds("2001-08-09", 2), lon, lat, prec = "double")
  tmax <- suppressMessages(read_era5(file, months = 8))
  # The points on 22 E and 12 N start cells that are not complete: 2 x 2 cells remain.
  expect_equal(tmax$cells$lon, c(20.5, 21.5, 20.5, 21.5))
  expect_equal(tmax$cells$lat, c(10.5, 10.5, 11.5, 11.5))
  expect_equal(c(tmax$grid$lon_step, tmax$grid$lat_step), c(1, 1))
  daily <- daily_max(values) - 273.15            # date x lat (12..10) x lon (20..22)
  for (cell in seq_len(4)) {
    rows <- which(lat >= tmax$cells$lat[cell] - 0.5 & lat < tmax$cells$lat[cell] + 0.5)
    cols <- which(lon >= tmax$cells$lon[cell] - 0.5 & lon < tmax$cells$lon[cell] + 0.5)
    expect_length(rows, 4)
    expect_length(cols, 4)
    expected <- apply(daily[, rows, cols, drop = FALSE], 1, mean, na.rm = TRUE)
    expect_equal(tmax$tmax[, cell], expected, tolerance = 1e-12)
  }
  expect_error(suppressMessages(read_era5(file, months = 8, cell_size = 0.3)), "does not divide")
  native <- suppressMessages(read_era5(file, months = 8, cell_size = NULL))
  expect_equal(nrow(native$cells), 80)          # the point without data is left out
})

test_that("several ERA5 files, a folder, older CDS files and expver are read", {
  set.seed(3)
  lon <- c(30, 31, 32)
  lat <- c(41, 40)
  seconds <- hourly_seconds("2010-05-30", 4)
  values <- array(285 + 20 * runif(96 * 2 * 3), c(96, 2, 3))
  expected <- suppressMessages(read_era5(write_era5(tempfile(fileext = ".nc"), values, seconds, lon, lat, prec = "double"),
                                         months = 5:6, cell_size = NULL))
  folder <- tempfile("era5")
  dir.create(folder)
  first <- write_era5(file.path(folder, "era5_a.nc"), values[1:48, , ], seconds[1:48], lon, lat, legacy = TRUE)
  second <- write_era5(file.path(folder, "era5_b.nc"), values[49:96, , ], seconds[49:96], lon, lat, legacy = TRUE)
  from_files <- suppressMessages(read_era5(c(second, first), months = 5:6, cell_size = NULL))
  from_folder <- suppressMessages(read_era5(folder, months = 5:6, cell_size = NULL))
  expect_identical(from_files$tmax, from_folder$tmax)
  expect_equal(from_files$dates, expected$dates)
  expect_equal(from_files$tmax, expected$tmax, tolerance = 1e-3)   # 16-bit packing
  expect_match(from_folder$source, "2 ERA5 files")

  # ERA5 combined with ERA5T: each time has a value in one of the two versions.
  split <- array(NA_real_, c(dim(values), 2))
  split[1:60, , , 1] <- values[1:60, , ]
  split[61:96, , , 2] <- values[61:96, , ]
  merged <- suppressMessages(read_era5(write_era5(tempfile(fileext = ".nc"), split, seconds, lon, lat, prec = "double"),
                                       months = 5:6, cell_size = NULL))
  expect_identical(merged$tmax, expected$tmax)

  # Problems are reported, not guessed around.
  partial <- write_era5(tempfile(fileext = ".nc"), values[1:95, , ], seconds[1:95], lon, lat, prec = "double")
  expect_error(read_era5(partial, months = 5:6, cell_size = NULL), "2010-06-02 .* has 23 of its 24 time steps")
  expect_equal(suppressMessages(read_era5(partial, months = 5:6, end = "2010-06-01", cell_size = NULL))$tmax,
               expected$tmax[1:3, ])
  expect_error(read_era5(c(first, first), months = 5:6, cell_size = NULL), "more than one ERA5 file")
  other_grid <- write_era5(tempfile(fileext = ".nc"), values[49:96, , ], seconds[49:96], lon + 1, lat)
  expect_error(suppressMessages(read_era5(c(first, other_grid), months = 5:6, cell_size = NULL)), "same grid")
  expect_error(read_era5(example_file), "no temperature variable called 't2m' or '2m_temperature'")
  expect_error(read_era5(tempfile()), "does not exist")
  empty <- tempfile("empty")
  dir.create(empty)
  expect_error(read_era5(empty), "contains no .nc files")
})

test_that("raw ERA5 named in the configuration gives the same analysis as its daily maxima", {
  # Six-hourly ERA5-like temperature whose daily maxima are the example data
  # for 1996-2005; the maximum falls on a different step each day.
  daily <- read_tmax(example_file, end = "2005-12-31")
  n_days <- length(daily$dates)
  lon <- daily$grid$lon
  lat <- rev(daily$grid$lat)
  grid <- array(NA_real_, c(n_days, length(lat), length(lon)))
  index <- cbind(match(daily$cells$lat, lat), match(daily$cells$lon, lon))
  for (i in seq_len(nrow(index))) grid[, index[i, 1], index[i, 2]] <- daily$tmax[, i] + 273.15
  values <- array(NA_real_, c(4 * n_days, length(lat), length(lon)))
  peak <- (seq_len(n_days) %% 4) + 1
  for (step in 1:4) {
    values[(seq_len(n_days) - 1) * 4 + step, , ] <- grid - ifelse(peak == step, 0, step)
  }
  folder <- tempfile("era5_run")
  dir.create(folder)
  seconds <- as.numeric(rep(daily$dates, each = 4)) * 86400 + rep(c(0, 6, 12, 18) * 3600, n_days)
  file <- write_era5(file.path(folder, "era5_t2m.nc"), values, seconds, lon, lat, prec = "double")

  config <- list(input = list(file = file), output = list(directory = file.path(folder, "era5")),
                 power_law = list(bootstrap_repetitions = 20))
  expect_equal(scoRch.generator:::detect_input_format(file), "era5")
  era5 <- suppressMessages(run_scorch(config))
  reference <- tmax_from_array(grid, daily$dates, lon, lat, units = "K", months = 4:9)
  baseline <- suppressMessages(run_scorch(list(output = list(directory = file.path(folder, "daily")),
                                               power_law = list(bootstrap_repetitions = 20)), tmax = reference))
  outputs <- function(dir) {
    files <- sort(list.files(dir, recursive = TRUE))
    setNames(tools::md5sum(file.path(dir, files)), files)
  }
  a <- outputs(file.path(folder, "era5"))
  b <- outputs(file.path(folder, "daily"))
  expect_identical(names(a), names(b))
  same <- setdiff(names(a), "run_summary.txt")
  expect_identical(unname(a[same]), unname(b[same]))
  expect_true(all(era5$plots$status == "generated"))
  expect_true(all(file.exists(file.path(folder, "era5", "figures",
                                        c("single_day_events.png", "consistent_multiday_events.png",
                                          "mixed_multiday_events.png")))))
  summary <- readLines(file.path(folder, "era5", "run_summary.txt"))
  expect_true(any(grepl("ERA5 2-m temperature, 4 values per day reduced to the daily maximum (UTC days), averaged to 1-degree cells",
                        summary, fixed = TRUE)))
})

test_that("daily maximum temperature files are read as before", {
  read <- function(input) scoRch.generator:::read_configured_input(scoRch.generator:::read_config(list(input = input)))
  before <- read_tmax(example_file)
  expect_identical(read(list(file = example_file)), before)
  expect_identical(read(list(file = example_file, format = "daily_tmax")), before)
  expect_identical(read(list(file = example_file, variable = "tmax", longitude = "lon", latitude = "lat",
                             time = "time")), before)
  expect_equal(scoRch.generator:::detect_input_format(example_file), "daily_tmax")
  expect_error(read(list(file = c(example_file, example_file))), "one NetCDF file")
  expect_error(read(list(file = example_file, variable = "t2m")), "no temperature variable called 't2m'")
  expect_error(read(list(file = example_file, format = "era5")), "no temperature variable")
})

test_that("the input settings are checked", {
  read <- scoRch.generator:::read_config
  expect_error(read(list(input = list(file = example_file, format = "grib"))), "auto, era5 or daily_tmax")
  expect_error(read(list(input = list(file = example_file, era5_cell_size_deg = -1))), "era5_cell_size_deg")
  expect_error(read(list(input = list(file = c(example_file, "missing.nc")))), "does not exist: missing.nc")
  expect_equal(read(list(input = list(file = c(example_file, example_file))))$input$file, rep(example_file, 2))
  expect_equal(read(list(input = list(file = tempdir())))$input$file, tempdir())
  expect_null(read(list(input = list(era5_cell_size_deg = NULL)), input_required = FALSE)$input$era5_cell_size_deg)
  expect_error(read(list(input = list(file = example_file, longitude = "x", latitude = "x"))), "distinct")
})
