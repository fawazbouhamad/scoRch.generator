# The from-scratch input without the network: request planning, caching and
# resuming against a fake CDS, the file writer and the configuration switch.
# The live request at the end runs only when SCORCH_CDS_LIVE is set.

plan <- scoRch.generator:::plan_cds_requests

# A small ERA5-like daily file for one request: t2m (K) on the 0.25-degree
# points of the request area, one value per requested day.
write_daily_era5 <- function(path, request) {
  area <- request$area
  lon <- seq(area[2], area[4], by = 0.25)
  lat <- seq(area[1], area[3], by = -0.25)
  dates <- as.Date(character())
  for (m in request$month) {
    first <- as.Date(sprintf("%s-%s-01", request$year, m))
    month_days <- seq(first, seq(first, by = "month", length.out = 2)[2] - 1, by = "day")
    dates <- c(dates, month_days[format(month_days, "%d") %in% request$day])
  }
  dims <- list(ncdf4::ncdim_def("longitude", "degrees_east", lon), ncdf4::ncdim_def("latitude", "degrees_north", lat),
               ncdf4::ncdim_def("valid_time", "seconds since 1970-01-01", as.numeric(dates) * 86400))
  var <- ncdf4::ncvar_def("t2m", "K", dims, missval = NA, prec = "float")
  nc <- ncdf4::nc_create(path, var)
  values <- array(290 + outer(seq_along(lon) / 10, seq_along(lat) / 10), c(length(lon), length(lat), length(dates)))
  values <- values + rep(seq_along(dates) / 100, each = length(lon) * length(lat))
  ncdf4::ncvar_put(nc, var, values)
  ncdf4::nc_close(nc)
  invisible(path)
}

# A fake CDS: submissions are accepted, become successful after `delay`
# status checks, and transfer a file written by write_daily_era5().
fake_cds <- function(delay = 0L, first_status = NULL, jobs = new.env()) {
  log <- new.env()
  log$submitted <- character()
  log$deleted <- character()
  list(
    key_present = function(user) TRUE,
    submit = function(request, user) {
      id <- paste0("job", length(log$submitted) + 1L)
      log$submitted <- c(log$submitted, request$target)
      assign(id, list(request = request, checks = 0L), envir = jobs)
      paste0("https://cds.example/jobs/", id)
    },
    status = function(url, user) {
      id <- basename(url)
      if (!exists(id, envir = jobs)) return("missing")
      job <- get(id, envir = jobs)
      job$checks <- job$checks + 1L
      assign(id, job, envir = jobs)
      if (!is.null(first_status) && id == "job1") return(first_status)
      if (job$checks > delay) "successful" else "accepted"
    },
    transfer = function(url, cache, filename, user) {
      write_daily_era5(file.path(cache, filename), get(basename(url), envir = jobs)$request)
    },
    delete = function(url, user) {
      log$deleted <- c(log$deleted, basename(url))
      invisible(NULL)
    },
    log = log, jobs = jobs)
}

with_fake_cds <- function(backend, code) {
  old <- options(scoRch.generator.cds_backend = backend)
  on.exit(options(old))
  force(code)
}

test_that("requests are planned month by month or year by year, clipped to the period", {
  monthly <- plan(as.Date("1996-04-15"), as.Date("1997-09-30"), 4:9, "month")
  expect_equal(nrow(monthly), 12)
  expect_equal(monthly$year, rep(1996:1997, each = 6))
  expect_equal(monthly$month, rep(4:9, 2))
  expect_equal(monthly$days[[1]], sprintf("%02d", 15:30))      # April 1996 starts on the 15th
  expect_equal(monthly$days[[2]], sprintf("%02d", 1:31))
  expect_equal(monthly$months[[3]], "06")
  yearly <- plan(as.Date("1996-04-15"), as.Date("1997-09-30"), 4:9, "year")
  expect_equal(yearly$year, 1996:1997)
  expect_equal(yearly$months[[1]], sprintf("%02d", 4:9))
  expect_equal(yearly$days[[2]], sprintf("%02d", 1:31))
  # A Southern Hemisphere season crosses the new year: the months of each calendar year.
  southern <- plan(as.Date("1996-11-01"), as.Date("1997-03-31"), c(11, 12, 1, 2, 3), "month")
  expect_equal(paste(southern$year, southern$month), c("1996 11", "1996 12", "1997 1", "1997 2", "1997 3"))
  by_year <- plan(as.Date("1996-11-01"), as.Date("1997-03-31"), c(11, 12, 1, 2, 3), "year")
  expect_equal(by_year$months, I(list(c("11", "12"), c("01", "02", "03"))))
  expect_equal(nrow(plan(as.Date("1996-01-01"), as.Date("1996-03-31"), 4:9, "month")), 0)
  expect_error(scoRch.generator:::check_area(c(25, -130, 50, -58)), "North above South")
  expect_error(scoRch.generator:::check_area(c(50, -130, 25)), "four numbers")
})

test_that("area edges off the 0.25-degree ERA5 grid are refused before any request", {
  check_area <- scoRch.generator:::check_area
  expect_equal(check_area(c(44.25, -104, 34, -93.75)), c(44.25, -104, 34, -93.75))   # on the grid
  for (bad in list(c(44.1, -104, 34, -94), c(44, -104.3, 34, -94), c(44, -104, 34.05, -94), c(44, -104, 34, -93.9))) {
    expect_error(check_area(bad), "multiples of 0.25")
  }
  # The configuration and the fetch function refuse such an area without reaching the CDS.
  untouched <- fake_cds()
  expect_error(with_fake_cds(untouched, fetch_era5_daily_tmax(c(44.1, -104, 34, -94), "2012-07-01", "2012-07-31",
                                                                cache = tempfile())), "multiples of 0.25")
  expect_length(untouched$log$submitted, 0)
  expect_error(scoRch.generator:::read_config(list(input = list(source = "cds", cds = list(area = c(44.1, -104, 34, -94))),
                                                   period = list(start_date = "2012-07-01", end_date = "2012-07-31"))),
               "multiples of 0.25")
})

test_that("downloads are cached, resumed and re-submitted without touching the network", {
  cache <- tempfile("cds-cache-")
  area <- c(37, -98, 35, -96)                                      # 2 x 2 one-degree cells
  fetch <- function(backend, ...) {
    with_fake_cds(backend, suppressMessages(fetch_era5_daily_tmax(area, "2012-06-20", "2012-07-10", months = 4:9,
                                                                   cache = cache, retry = 1, ...)))
  }
  cds <- fake_cds()
  files <- fetch(cds)
  expect_equal(basename(files), c("era5_daily_tmax_N37_W-98_S35_E-96_2012-06-20_2012-06-30.nc",
                                  "era5_daily_tmax_N37_W-98_S35_E-96_2012-07-01_2012-07-10.nc"))
  expect_true(all(file.exists(paste0(files, ".request"))))             # the request record beside each file
  expect_true(all(file.exists(files)))
  expect_equal(cds$log$submitted, basename(files))
  expect_equal(cds$log$deleted, c("job1", "job2"))                  # finished jobs are removed from the CDS
  expect_false(any(file.exists(paste0(files, ".job"))))
  tmax <- suppressMessages(read_era5(files, months = 6:7, cell_size = 1))
  expect_equal(tmax$dates, seq(as.Date("2012-06-20"), as.Date("2012-07-10"), by = "day"))
  expect_equal(nrow(tmax$cells), 4)                                 # the complete 1-degree cells
  # A second run requests nothing.
  again <- fake_cds()
  expect_identical(fetch(again), files)
  expect_length(again$log$submitted, 0)
  # A run that gives up leaves the job noted; the next run resumes the same job.
  unlink(files)
  slow <- fake_cds(delay = 1000L)
  expect_error(fetch(slow, time_out = 0), "still accepted on the CDS")
  expect_true(file.exists(paste0(files[1], ".job")))
  expect_length(slow$log$submitted, 1)
  resumed <- fake_cds(jobs = slow$jobs)                            # the same CDS, now delivering
  resumed$status <- function(url, user) "successful"
  expect_identical(fetch(resumed), files)
  expect_length(resumed$log$submitted, 1)                           # only the second month was new
  # A rejected or dropped job is submitted again.
  unlink(files)
  rejected <- fake_cds(first_status = "rejected")
  expect_identical(fetch(rejected), files)
  expect_equal(rejected$log$submitted, basename(files)[c(1, 1, 2)])
  unlink(files)
  failed <- fake_cds(first_status = "failed")
  expect_error(fetch(failed), "could not produce")
  no_key <- fake_cds()
  no_key$key_present <- function(user) FALSE
  expect_error(fetch(no_key), "wf_set_key")
  # An empty period is refused before the token is looked for, so the check needs no credentials.
  expect_error(with_fake_cds(no_key, suppressMessages(fetch_era5_daily_tmax(area, "2012-01-01", "2012-03-31", cache = cache))),
               "No day of the warm-season")
})

test_that("write_tmax() writes a file that read_tmax() reads back", {
  dates <- as.Date("2000-06-01") + 0:9
  values <- array(20 + seq_len(10 * 2 * 3) / 7, c(10, 2, 3))
  values[, 1, 1] <- NA                                              # a cell without data on any date
  tmax <- tmax_from_array(values, dates, lon = c(10, 11, 12), lat = c(50, 51), source = "test array")
  expect_true(suppressMessages(nrow(tmax$cells)) == 5)
  packed <- write_tmax(tmax, tempfile(fileext = ".nc"), title = "test", licence = "none")
  back <- read_tmax(packed, months = 6)
  expect_equal(back$cells[c("lon", "lat")], tmax$cells[c("lon", "lat")], ignore_attr = TRUE)
  expect_equal(back$dates, tmax$dates)
  expect_lte(max(abs(back$tmax - tmax$tmax)), 0.0051)
  exact <- write_tmax(tmax, tempfile(fileext = ".nc"), precision = "float32")
  expect_equal(read_tmax(exact, months = 6)$tmax, tmax$tmax, tolerance = 1e-6)
  nc <- ncdf4::nc_open(packed)
  expect_equal(ncdf4::ncatt_get(nc, 0, "title")$value, "test")
  expect_match(ncdf4::ncatt_get(nc, 0, "source")$value, "test array")
  expect_match(ncdf4::ncatt_get(nc, 0, "history")$value, "scoRch.generator")
  expect_equal(ncdf4::ncatt_get(nc, "tmax", "scale_factor")$value, 0.01)
  ncdf4::nc_close(nc)
  expect_error(write_tmax(tmax, packed), "already exists")
  expect_error(write_tmax(list(), tempfile()), "scorch_tmax|read_era5")
})

test_that("the configuration selects the from-scratch path and checks its settings", {
  read <- scoRch.generator:::read_config
  base <- list(input = list(source = "cds", cds = list(area = c(37, -98, 35, -96))),
               period = list(start_date = "2012-06-20", end_date = "2012-07-10"))
  cfg <- read(base)
  expect_equal(cfg$input$cds$area, c(37, -98, 35, -96))
  expect_equal(cfg$input$cds$cache_directory, "era5_cache")          # defaults fill the rest
  expect_equal(cfg$input$cds$request_period, "month")
  expect_null(cfg$input$file)
  expect_error(read(list(input = list(source = "ftp"))), "file or cds")
  expect_error(read(list(input = list(source = "cds"))), "area")
  expect_error(read(list(input = list(source = "cds", cds = list(area = c(37, -98, 35, -96))))), "start_date")
  expect_error(read(modifyList(base, list(input = list(cds = list(request_period = "week"))))), "month or year")
  expect_error(read(modifyList(base, list(input = list(cds = list(bucket = "x"))))), "Unknown settings")
  expect_error(read(modifyList(base, list(input = list(cds = list(area = c(35, -98, 36, -97)))))), "North above South")
  # The whole path: download (fake), reduce to cells, save the processed file.
  cache <- tempfile("cds-run-")
  processed <- tempfile(fileext = ".nc")
  cfg <- read(modifyList(base, list(input = list(cds = list(cache_directory = cache, processed_file = processed)))))
  tmax <- with_fake_cds(fake_cds(), suppressMessages(scoRch.generator:::read_configured_input(cfg)))
  expect_s3_class(tmax, "scorch_tmax")
  expect_true(file.exists(processed))
  expect_match(tmax$preprocessing, "saved to")
  saved <- read_tmax(processed, months = 6:7)
  expect_equal(saved$dates, tmax$dates)
  expect_lte(max(abs(saved$tmax - tmax$tmax)), 0.0051)
  expect_equal(length(list.files(cache, pattern = "[.]nc$")), 2)
})

test_that("a cache folder never answers another area, period or month selection with an old file", {
  cache <- tempfile("cds-stale-")
  fetch <- function(area, start, end, ...) {
    cds <- fake_cds()
    files <- with_fake_cds(cds, suppressMessages(fetch_era5_daily_tmax(area, start, end, cache = cache, retry = 1, ...)))
    list(files = files, submitted = cds$log$submitted)
  }
  first <- fetch(c(37, -98, 35, -96), "2012-06-20", "2012-06-30")
  expect_length(first$submitted, 1)
  # another area, same dates: a new name, a new request, the old file untouched
  moved <- fetch(c(38, -99, 36, -97), "2012-06-20", "2012-06-30")
  expect_length(moved$submitted, 1)
  expect_false(identical(moved$files, first$files))
  expect_true(all(file.exists(c(first$files, moved$files))))
  expect_equal(range(suppressMessages(read_era5(moved$files, months = 6, cell_size = NULL))$cells$lon), c(-99, -97))
  # the same month extended to its full length: a new request, not the ten-day file
  longer <- fetch(c(37, -98, 35, -96), "2012-06-01", "2012-06-30")
  expect_length(longer$submitted, 1)
  expect_equal(length(suppressMessages(read_era5(longer$files, months = 6, cell_size = NULL))$dates), 30)
  # other season months, and yearly instead of monthly requests
  summer <- fetch(c(37, -98, 35, -96), "2012-06-01", "2012-07-31", months = 6:7, period = "year")
  expect_length(summer$submitted, 1)
  expect_match(basename(summer$files), "2012_months06-07")
  wider <- fetch(c(37, -98, 35, -96), "2012-06-01", "2012-08-31", months = 6:8, period = "year")
  expect_length(wider$submitted, 1)
  expect_match(basename(wider$files), "2012_months06-07-08")
  # every earlier request is still served from the cache without a new submission
  expect_length(fetch(c(37, -98, 35, -96), "2012-06-20", "2012-06-30")$submitted, 0)
  expect_length(fetch(c(37, -98, 35, -96), "2012-06-01", "2012-07-31", months = 6:7, period = "year")$submitted, 0)
  expect_equal(length(list.files(cache, pattern = "[.]nc$")), 5)
})

test_that("a cached file that does not answer its request is set aside and requested again", {
  cache <- tempfile("cds-invalid-")
  dir.create(cache)
  area <- c(37, -98, 35, -96)
  request <- scoRch.generator:::cds_request(2012, "06", sprintf("%02d", 20:30), area)
  target <- file.path(cache, request$target)
  fetch <- function() {
    cds <- fake_cds()
    files <- with_fake_cds(cds, suppressMessages(fetch_era5_daily_tmax(area, "2012-06-20", "2012-06-30", cache = cache, retry = 1)))
    list(files = files, submitted = cds$log$submitted)
  }
  # a file with the right name but another area, and no record: not reused
  write_daily_era5(target, modifyList(request, list(area = c(38, -99, 36, -97))))
  out <- fetch()
  expect_length(out$submitted, 1)
  expect_true(file.exists(paste0(target, ".invalid")))
  expect_null(scoRch.generator:::cds_cache_problem(target, request))
  # a correct file whose record names another request: not reused
  writeLines("another request", scoRch.generator:::cds_record_path(target))
  expect_match(scoRch.generator:::cds_cache_problem(target, request), "recorded request differs")
  expect_length(fetch()$submitted, 1)
  # a truncated download: not reused
  writeLines(character(), target)
  expect_match(scoRch.generator:::cds_cache_problem(target, request), "empty")
  expect_length(fetch()$submitted, 1)
  con <- file(target, "wb"); writeBin(as.raw(1:100), con); close(con)
  expect_match(scoRch.generator:::cds_cache_problem(target, request), "not a readable NetCDF")
  expect_length(fetch()$submitted, 1)
  # a file with the right grid but one day missing: not reused
  write_daily_era5(target, modifyList(request, list(day = sprintf("%02d", 20:29))))
  writeLines(scoRch.generator:::cds_request_key(request), scoRch.generator:::cds_record_path(target))
  expect_match(scoRch.generator:::cds_cache_problem(target, request), "dates")
  expect_length(fetch()$submitted, 1)
  expect_null(scoRch.generator:::cds_cache_problem(target, request))
  # a job note of another request is ignored; a delivered file that does not match is an error
  writeLines(c("https://cds.example/jobs/old", "another request"), paste0(target, ".job"))
  unlink(c(target, scoRch.generator:::cds_record_path(target)))
  out <- fetch()
  expect_length(out$submitted, 1)
  expect_false(file.exists(paste0(target, ".job")))
  unlink(c(target, scoRch.generator:::cds_record_path(target)))
  wrong <- fake_cds()
  wrong$transfer <- function(url, cache, filename, user) write_daily_era5(file.path(cache, filename), modifyList(request, list(area = c(38, -99, 36, -97))))
  expect_error(with_fake_cds(wrong, suppressMessages(fetch_era5_daily_tmax(area, "2012-06-20", "2012-06-30", cache = cache, retry = 1))),
               "does not match the request")
  expect_false(file.exists(target))
})

test_that("the shipped CDS sample reduces to the cells of the demonstration data", {
  sample <- system.file("extdata", "cds_daily_tmax_2012_great_plains.nc", package = "scoRch.generator")
  demo <- system.file("extdata", "north_america_tmax.nc", package = "scoRch.generator")
  skip_if(!nzchar(demo), "the demonstration data are not installed")
  from_cds <- suppressMessages(read_era5(sample, months = 4:9, cell_size = 1))
  expect_equal(nrow(from_cds$cells), 100)
  expect_equal(length(from_cds$dates), 183)
  whole <- read_tmax(demo, start = "2012-01-01", end = "2012-12-31")
  columns <- match(paste(from_cds$cells$lon, from_cds$cells$lat), paste(whole$cells$lon, whole$cells$lat))
  expect_false(anyNA(columns))
  expect_equal(whole$dates, from_cds$dates)
  # the same ERA5 values from two sources (ARCO-ERA5 and the CDS), float32
  # rounding apart, plus the 0.01-degree packing of the demonstration file
  expect_lte(max(abs(whole$tmax[, columns] - from_cds$tmax)), 0.0065)
})

test_that("one live CDS request reproduces the shipped sample (SCORCH_CDS_LIVE=1 only)", {
  skip_if(Sys.getenv("SCORCH_CDS_LIVE") == "", "set SCORCH_CDS_LIVE=1 to make one real CDS request")
  cache <- tempfile("cds-live-")
  files <- fetch_era5_daily_tmax(area = c(44, -104, 34, -94), start = "2012-07-01", end = "2012-07-31",
                                 months = 7, cache = cache, time_out = 8 * 3600, retry = 60)
  live <- suppressMessages(read_era5(files, months = 7, cell_size = NULL))
  sample <- system.file("extdata", "cds_daily_tmax_2012_great_plains.nc", package = "scoRch.generator")
  shipped <- suppressMessages(read_era5(sample, months = 7, cell_size = NULL))
  expect_equal(live$dates, shipped$dates)
  expect_equal(live$tmax, shipped$tmax, tolerance = 1e-6)
})
