# The from-scratch input: ERA5 daily maximum 2-m temperature downloaded from
# the Copernicus Climate Data Store (CDS) through the ecmwfr package, cached
# file by file, then reduced to 1-degree cells by read_era5().

CDS_DATASET <- "derived-era5-single-levels-daily-statistics"

#' Download ERA5 daily maximum 2-m temperature from the Climate Data Store
#'
#' Requests the CDS product *ERA5 post-processed daily statistics on single
#' levels* (dataset `derived-era5-single-levels-daily-statistics`,
#' doi:10.24381/cds.4991cf48): the daily maximum of the hourly 2-m temperature
#' over each UTC calendar day, on the native 0.25-degree ERA5 grid, for the
#' warm-season months of every year between `start` and `end`. The files are
#' written to `cache`, one per calendar month (or per calendar year), under a
#' name that states the area and the requested dates, with a record of the
#' complete request beside it. A cached file is reused only when its name,
#' its record and its actual grid and dates match the request, so changing
#' the area, the period or the months with the same cache folder never
#' reuses an old file; running the function again downloads only what is
#' missing, and a request that was still queued when a previous run stopped
#' is picked up again. [read_era5()] then reduces the files to the daily maximum
#' temperature on 1-degree cells, and [run_scorch()] does all of this when a
#' configuration sets `input: source: cds`.
#'
#' @section Setup, once per computer:
#' 1. Create a free account at <https://cds.climate.copernicus.eu>, open the
#'    dataset page of the product above and accept its licence.
#' 2. In an interactive R session run `ecmwfr::wf_set_key()` with no
#'    arguments: it opens your CDS profile page and asks for the Personal
#'    Access Token at a hidden prompt, so the token is stored in the operating
#'    system's keychain without passing through a script or the R history.
#'    The token never goes into a configuration file, the code, the logs or
#'    the run summary; `ecmwfr::wf_get_key()` reads it from the keychain when a
#'    request is made. On a headless Linux computer without a keychain, set
#'    `options(keyring_backend = "file")` first.
#' 3. Install the packages this path needs: `install.packages(c("ecmwfr", "httr"))`.
#'
#' @section What to expect from the CDS:
#' Every request waits in the CDS queue before it runs. Waits of minutes are
#' common and waits of hours happen at busy times; the CDS also accepts only
#' one queued request per user for this product, so the months are requested
#' one after another. A 30-year season of six months is 180 monthly requests,
#' which can take days. The function polls every `retry` seconds, gives up on
#' one request after `time_out` seconds while leaving it queued on the CDS,
#' and resumes from the cache and the queued request when run again. One
#' calendar year per request (`period = "year"`) means fewer requests, but
#' the CDS refuses a request that exceeds its size limit; the error says so,
#' and `period = "month"` is then the choice.
#'
#' @param area Numeric vector of four values: North, West, South and East
#'   edges in degrees (longitudes from -180 to 180), as on the CDS form, each
#'   a multiple of 0.25 so that the CDS returns the native grid points rather
#'   than an interpolated grid shifted to the edges (other values are
#'   refused before any request). The points on the edges are included;
#'   [read_era5()] keeps the
#'   complete 1-degree cells between them, so a box from 25 N to 50 N and
#'   130 W to 58 W gives the 25 x 72 cells with centres 25.5-49.5 N and
#'   129.5-58.5 W.
#' @param start,end First and last date (`"YYYY-MM-DD"`) of the period. Only
#'   the days of the warm-season months are requested.
#' @param months Calendar months of the warm season; a season that crosses
#'   the new year, such as November-March, is `c(11, 12, 1, 2, 3)`.
#' @param cache Folder for the downloaded files; created if needed.
#' @param period `"month"` (one request per calendar month, recommended) or
#'   `"year"` (one request per calendar year, whole months).
#' @param user The keychain entry written by `ecmwfr::wf_set_key()`.
#' @param time_out Seconds to wait for one request before giving up (it stays
#'   queued on the CDS and is resumed by the next run).
#' @param retry Seconds between two checks of a queued request.
#' @param verbose Print progress messages.
#' @return The paths of the cached files (invisibly), in calendar order; pass
#'   them to [read_era5()].
#' @seealso [read_era5()], [write_tmax()], [run_scorch()]
#' @examples
#' \dontrun{
#' files <- fetch_era5_daily_tmax(area = c(50, -130, 25, -58), start = "1996-01-01",
#'                                end = "2025-12-31", cache = "era5_cache")
#' tmax <- read_era5(files, cell_size = 1)
#' write_tmax(tmax, "north_america_tmax.nc")
#' }
#' @export
fetch_era5_daily_tmax <- function(area, start, end, months = 4:9, cache = "era5_cache",
                                  period = c("month", "year"), user = "ecmwfr",
                                  time_out = 6 * 3600, retry = 60, verbose = TRUE) {
  period <- match.arg(period)
  area <- check_area(area)
  start <- check_date(start, "start")
  end <- check_date(end, "end")
  if (start > end) fail("`start` must be on or before `end`.")
  months <- validate_season_months(months)
  check_number(time_out, "time_out", lower = 0)
  check_number(retry, "retry", lower = 1)
  check_config_string(user, "user")
  # The request is validated completely before the token is looked for.
  plan <- plan_cds_requests(start, end, months, period)
  if (!nrow(plan)) fail("No day of the warm-season months lies between ", format(start), " and ", format(end), ".")
  backend <- cds_backend()
  if (!isTRUE(backend$key_present(user))) {
    fail("No CDS token is stored in the keychain for user '", user, "'. Create a free account at ",
         "https://cds.climate.copernicus.eu, accept the licence of the dataset '", CDS_DATASET,
         "', then run ecmwfr::wf_set_key() once in an interactive R session and paste the Personal ",
         "Access Token from your profile page at its hidden prompt. The token is read from the keychain ",
         "and is never written to a configuration file, the code or the logs.")
  }
  if (!dir.exists(cache) && !dir.create(cache, recursive = TRUE, showWarnings = FALSE)) {
    fail("Could not create the cache folder: ", cache)
  }
  say <- function(...) if (verbose) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))
  requests <- lapply(seq_len(nrow(plan)), function(i) cds_request(plan$year[i], plan$months[[i]], plan$days[[i]], area))
  targets <- file.path(cache, vapply(requests, `[[`, "", "target"))
  problems <- Map(cds_cache_problem, targets, requests)
  reusable <- vapply(problems, is.null, logical(1))
  say("%d of %d ERA5 files are already in %s; %d to request from the CDS",
      sum(reusable), length(targets), cache, sum(!reusable))
  for (i in which(!reusable)) {
    if (file.exists(targets[i])) {
      # A file with this request's name that does not answer it (an
      # interrupted download, another request, an edited file) is set aside.
      aside <- paste0(targets[i], ".invalid")
      file.rename(targets[i], aside)
      unlink(cds_record_path(targets[i]))
      say("%s was set aside as %s: %s; requesting it anew", basename(targets[i]), basename(aside), problems[[i]])
    }
    cds_fetch_one(backend, requests[[i]], cache, user, time_out, retry, say)
  }
  invisible(targets)
}

# North, West, South, East in degrees, as the CDS wants them.
check_area <- function(area) {
  if (!is.numeric(area) || length(area) != 4 || anyNA(area)) {
    fail("`area` must be four numbers: North, West, South and East edges in degrees.")
  }
  if (area[1] <= area[3] || area[2] >= area[4]) fail("`area` must have North above South and West left of East.")
  if (any(abs(area[c(1, 3)]) > 90) || any(abs(area[c(2, 4)]) > 180)) {
    fail("`area` must lie within 90 S-90 N and 180 W-180 E.")
  }
  # The CDS returns the native 0.25-degree points only when the edges lie on
  # that grid; other edges make it interpolate onto a grid shifted to the
  # edges, which is not ERA5 as archived and would fail the file check after
  # the wait in the queue. Reject them before anything is requested.
  if (any(abs(area * 4 - round(area * 4)) > 1e-9)) {
    fail("`area` edges must be multiples of 0.25 degrees, the spacing of the ERA5 grid (for example ",
         "c(50, -130, 25, -58) or c(44.25, -104, 34, -94)), so that the CDS delivers the native grid points ",
         "without interpolation; round the edges outwards to the nearest 0.25.")
  }
  as.numeric(area)
}

# One row per CDS request: the calendar months of the season between start
# and end, requested month by month (days clipped at the ends) or grouped by
# calendar year (whole months). The list columns `months` and `days` hold
# the month and day codes of each request.
plan_cds_requests <- function(start, end, months, period = "month") {
  first <- as.Date(format(start, "%Y-%m-01"))
  month_starts <- seq(first, end, by = "month")
  rows <- lapply(month_starts, function(m) {
    month <- as.integer(format(m, "%m"))
    if (!month %in% months) return(NULL)
    last <- seq(m, by = "month", length.out = 2)[2] - 1
    data.frame(year = as.integer(format(m, "%Y")), month = month,
               first = max(m, start), last = min(last, end))
  })
  rows <- do.call(rbind, rows)
  empty <- data.frame(year = integer(), month = integer(), first = as.Date(character()),
                      last = as.Date(character()))
  if (is.null(rows)) return(empty)
  if (period == "month") {
    rows$months <- I(lapply(rows$month, function(m) sprintf("%02d", m)))
    rows$days <- I(Map(function(a, b) sprintf("%02d", as.integer(format(seq(a, b, by = "day"), "%d"))),
                       rows$first, rows$last))
    rownames(rows) <- NULL
    return(rows)
  }
  years <- sort(unique(rows$year))
  data.frame(year = years, month = NA_integer_,
             first = as.Date(vapply(years, function(y) format(min(rows$first[rows$year == y])), "")),
             last = as.Date(vapply(years, function(y) format(max(rows$last[rows$year == y])), "")),
             months = I(lapply(years, function(y) sprintf("%02d", sort(rows$month[rows$year == y])))),
             days = I(replicate(length(years), sprintf("%02d", 1:31), simplify = FALSE)))
}

# The CDS request of one file, in the form ecmwfr::wf_request() takes. Its
# target file name is specific to the request, so that a cache folder can
# never answer a different area, period or month selection with an old file.
cds_request <- function(year, months, days, area) {
  request <- list(dataset_short_name = CDS_DATASET, product_type = "reanalysis", variable = "2m_temperature",
                  year = sprintf("%04d", as.integer(year)), month = months, day = days,
                  daily_statistic = "daily_maximum", time_zone = "utc+00:00", frequency = "1_hourly",
                  area = area)
  request$target <- cds_file_name(request)
  request
}

# One line that states everything a request asks for; it is written next to
# each cached file and into each job note, and compared before any reuse.
cds_request_key <- function(request) {
  paste(request$dataset_short_name, request$product_type, request$variable, request$daily_statistic,
        request$time_zone, request$frequency,
        paste0("area=", paste(format(request$area, trim = TRUE, digits = 6), collapse = ",")),
        paste0("year=", request$year), paste0("month=", paste(request$month, collapse = ",")),
        paste0("day=", paste(request$day, collapse = ",")), sep = "|")
}

# The calendar dates a request asks for (days that a month lacks, such as 31
# April, are dropped by the CDS and here).
cds_request_dates <- function(request) {
  dates <- as.Date(character())
  for (m in request$month) {
    first <- as.Date(sprintf("%s-%s-01", request$year, m))
    all_days <- seq(first, seq(first, by = "month", length.out = 2)[2] - 1, by = "day")
    dates <- c(dates, all_days[format(all_days, "%d") %in% request$day])
  }
  sort(dates)
}

# The cached file name: product, area edges and the requested dates.
cds_file_name <- function(request) {
  dates <- cds_request_dates(request)
  edge <- function(x) format(x, trim = TRUE, digits = 6)
  span <- if (length(request$month) == 1L) {
    sprintf("%s_%s", format(min(dates)), format(max(dates)))
  } else {
    sprintf("%s_months%s", request$year, paste(request$month, collapse = "-"))
  }
  sprintf("era5_daily_tmax_N%s_W%s_S%s_E%s_%s.nc", edge(request$area[1]), edge(request$area[2]),
          edge(request$area[3]), edge(request$area[4]), span)
}
