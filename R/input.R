# Reading and validating gridded daily maximum temperature.

#' Read gridded daily maximum temperature from a NetCDF file
#'
#' Reads daily maximum temperature (Tmax) on a regular longitude-latitude grid
#' and keeps the warm-season dates to analyse.
#'
#' The file needs one temperature variable with three dimensions: time,
#' latitude and longitude, in any order. Longitudes and latitudes are cell
#' centres with constant spacing. Time is `"days since YYYY-MM-DD"` (or
#' hours, minutes or seconds since) in a standard Gregorian calendar; the file
#' may hold every day of the year or only the warm-season days. Missing values
#' are read from the file's `_FillValue` or `missing_value` attribute. Cells
#' that are missing on every date (for example sea cells of a land-only
#' dataset) are excluded; any other missing value stops the analysis, because
#' the method needs a complete record for every cell.
#'
#' @param file Path to the NetCDF file.
#' @param variable,lon,lat,time Names of the temperature variable and of the
#'   longitude, latitude and time dimensions.
#' @param units `"auto"` reads the variable's `units` attribute; `"degC"` or
#'   `"K"` override it. Kelvin values are converted to degrees Celsius.
#' @param months Calendar months (1-12) that form the warm season.
#' @param start,end Optional first and last dates (`"YYYY-MM-DD"`) to analyse.
#' @return A `scorch_tmax` object: a list with `dates` (class `Date`), `cells`
#'   (data frame with `cell_id`, `lon` and `lat`), `tmax` (matrix with one row
#'   per date and one column per cell, degrees Celsius) and `grid` (longitude
#'   and latitude values and steps in degrees).
#' @seealso [tmax_from_array()] for temperature already in R.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file)
#' tmax
#' @export
read_tmax <- function(file, variable = "tmax", lon = "lon", lat = "lat",
                      time = "time", units = "auto", months = 4:9,
                      start = NULL, end = NULL) {
  if (!is.character(file) || length(file) != 1 || !file.exists(file)) {
    fail("The input file does not exist: ", file)
  }
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  var <- nc$var[[variable]]
  if (is.null(var)) {
    fail(sprintf("The file has no variable called '%s'. Its variables are: %s.",
                 variable, paste(names(nc$var), collapse = ", ")))
  }
  dim_names <- vapply(var$dim, function(d) d$name, "")
  missing <- setdiff(c(time, lat, lon), dim_names)
  if (length(missing) || length(dim_names) != 3) {
    fail(sprintf(paste("Variable '%s' has the dimensions %s; it needs exactly the",
                       "three dimensions named '%s', '%s' and '%s' (any order)."),
                 variable, paste(dim_names, collapse = ", "), time, lat, lon))
  }
  for (name in c(time, lat, lon)) {
    if (!isTRUE(nc$dim[[name]]$create_dimvar)) {
      fail(sprintf("The dimension '%s' has no coordinate values in the file.", name))
    }
  }
  values <- ncdf4::ncvar_get(nc, variable, collapse_degen = FALSE)
  values <- aperm(values, match(c(time, lat, lon), dim_names))
  time_dim <- nc$dim[[time]]
  calendar <- ncdf4::ncatt_get(nc, time, "calendar")
  dates <- decode_time(time_dim$vals, time_dim$units,
                       if (calendar$hasatt) calendar$value else "standard")
  if (identical(units, "auto")) {
    attribute <- ncdf4::ncatt_get(nc, variable, "units")
    if (!attribute$hasatt) {
      fail("The temperature variable has no 'units' attribute. Set units to 'degC' or 'K'.")
    }
    units <- attribute$value
  }
  tmax_from_array(values, dates, nc$dim[[lon]]$vals, nc$dim[[lat]]$vals,
                  units = units, months = months, start = start, end = end,
                  source = file)
}

#' Build the temperature input from data already in R
#'
#' Use this when the temperature does not come from a NetCDF file.
#'
#' @param tmax Numeric array with dimensions time, latitude, longitude.
#' @param dates Dates (class `Date`) of the first array dimension.
#' @param lon,lat Longitudes and latitudes (degrees) of the cell centres along
#'   the third and second array dimensions, evenly spaced.
#' @param units `"degC"` or `"K"`.
#' @param source Optional description of the data origin for the run summary.
#' @inheritParams read_tmax
#' @inherit read_tmax return
#' @export
tmax_from_array <- function(tmax, dates, lon, lat, units = "degC", months = 1:12,
                            start = NULL, end = NULL, source = "array") {
  lon <- as.numeric(lon)
  lat <- as.numeric(lat)
  dates <- as.Date(dates)
  if (length(dim(tmax)) != 3 ||
      !all(dim(tmax) == c(length(dates), length(lat), length(lon)))) {
    fail(sprintf("The temperature array has dimensions %s; expected time x latitude x longitude = %d x %d x %d.",
                 paste(dim(tmax), collapse = " x "), length(dates), length(lat), length(lon)))
  }
  if (anyNA(dates) || anyDuplicated(dates)) fail("The dates contain missing or duplicated values.")
  unit <- temperature_unit(units)
  if (unit == "K") {
    tmax <- tmax - 273.15
    message("Temperature converted from Kelvin to degrees Celsius.")
  }
  # Ascending coordinates with a constant grid step in each direction.
  lon_step <- grid_step(lon, "longitude")
  lat_step <- grid_step(lat, "latitude")
  if (lon_step < 0) {
    lon <- rev(lon)
    tmax <- tmax[, , rev(seq_along(lon)), drop = FALSE]
    lon_step <- -lon_step
  }
  if (lat_step < 0) {
    lat <- rev(lat)
    tmax <- tmax[, rev(seq_along(lat)), , drop = FALSE]
    lat_step <- -lat_step
  }
  # Warm-season dates in calendar order.
  if (!is.numeric(months) || !length(months) || !all(months %in% 1:12)) {
    fail("`months` must list calendar months between 1 and 12.")
  }
  keep <- as.integer(format(dates, "%m")) %in% months
  if (!is.null(start)) keep <- keep & dates >= check_date(start, "start")
  if (!is.null(end)) keep <- keep & dates <= check_date(end, "end")
  if (!any(keep)) fail("No dates are left after selecting the warm-season months and the start and end dates.")
  order_time <- order(dates[keep])
  dates <- dates[keep][order_time]
  tmax <- tmax[which(keep)[order_time], , , drop = FALSE]
  # One column per cell: west to east within each latitude row, south to north.
  cells <- expand.grid(lon_index = seq_along(lon), lat_index = seq_along(lat))
  values <- matrix(aperm(tmax, c(1, 3, 2)), nrow = length(dates))
  storage.mode(values) <- "double"
  all_missing <- colSums(!is.na(values)) == 0
  if (any(all_missing)) {
    message(sprintf("%d of %d cells have no temperature on any date and are excluded (for example sea cells).",
                    sum(all_missing), length(all_missing)))
    values <- values[, !all_missing, drop = FALSE]
    cells <- cells[!all_missing, ]
  }
  if (ncol(values) < 2) fail("Fewer than two grid cells have temperature values.")
  if (anyNA(values)) {
    where <- which(is.na(values), arr.ind = TRUE)[1, ]
    fail(sprintf(paste("The temperature has %d missing values on dates that other cells cover,",
                       "for example on %s at %g E, %g N. The method needs a complete record;",
                       "fill the gaps or restrict the region and period before running."),
                 sum(is.na(values)), format(dates[where[1]]),
                 lon[cells$lon_index[where[2]]], lat[cells$lat_index[where[2]]]))
  }
  if (!all(is.finite(values))) fail("The temperature contains infinite values.")
  cells <- data.frame(cell_id = seq_len(nrow(cells)),
                      lon = lon[cells$lon_index], lat = lat[cells$lat_index])
  dimnames(values) <- NULL
  structure(list(dates = dates, cells = cells, tmax = values,
                 season_months = months,
                 grid = list(lon = lon, lat = lat, lon_step = lon_step, lat_step = lat_step),
                 source = source),
            class = "scorch_tmax")
}

# Apply the configured period to temperature already assembled in R. Keep the
# cell indexing and grid metadata unchanged so downstream tables still refer
# to the same cells.
subset_tmax_period <- function(tmax, months = 1:12, start = NULL, end = NULL) {
  if (!inherits(tmax, "scorch_tmax")) {
    fail("`tmax` must come from read_tmax() or tmax_from_array().")
  }
  if (!is.numeric(months) || !length(months) || anyNA(months) ||
      !all(months %in% 1:12)) {
    fail("`months` must list calendar months between 1 and 12.")
  }
  keep <- as.integer(format(tmax$dates, "%m")) %in% months
  if (!is.null(start)) keep <- keep & tmax$dates >= check_date(start, "start")
  if (!is.null(end)) keep <- keep & tmax$dates <= check_date(end, "end")
  if (!any(keep)) {
    fail("No dates are left after selecting the warm-season months and the start and end dates.")
  }
  tmax$dates <- tmax$dates[keep]
  tmax$tmax <- tmax$tmax[keep, , drop = FALSE]
  tmax$season_months <- months
  tmax
}

#' @export
print.scorch_tmax <- function(x, ...) {
  cat(sprintf("<scorch_tmax> %d cells (%s to %s, %s to %s, %g x %g degree grid), %d dates (%s to %s)\n",
              nrow(x$cells), format_degrees(min(x$cells$lon), c("E", "W")), format_degrees(max(x$cells$lon), c("E", "W")),
              format_degrees(min(x$cells$lat), c("N", "S")), format_degrees(max(x$cells$lat), c("N", "S")),
              x$grid$lon_step, x$grid$lat_step, length(x$dates),
              format(x$dates[1]), format(x$dates[length(x$dates)])))
  invisible(x)
}

# "degC" or "K" from the spellings found in files (degC, deg_C, degree_Celsius,
# degrees_Celsius, Celsius, C; K, Kelvin, degree_Kelvin, ...).
temperature_unit <- function(units) {
  key <- gsub("[^a-z]", "", tolower(as.character(units)[1]))
  if (grepl("celsius", key) || key %in% c("degc", "c", "degreec", "degreesc")) return("degC")
  if (grepl("kelvin", key) || key %in% c("k", "degk", "degreek", "degreesk")) return("K")
  fail(sprintf("The temperature units '%s' are not recognised. Use 'degC' or 'K'.", units))
}

# Constant spacing of a coordinate vector (negative when descending).
grid_step <- function(values, name) {
  if (length(values) < 2 || anyNA(values)) {
    fail(sprintf("At least two %s values are needed, without missing values.", name))
  }
  steps <- diff(values)
  # Coordinates stored in single precision differ from a regular grid in the
  # sixth digit; a real irregularity is far larger than that.
  if (any(steps == 0) || max(abs(steps - steps[1])) > 1e-4 * abs(steps[1])) {
    fail(sprintf("The %s values are not evenly spaced (steps from %g to %g).", name, min(steps), max(steps)))
  }
  steps[1]
}

# Dates from CF time values such as "days since 1940-01-01". Work in
# seconds, then snap only rounding error at midnight; adding fractions of a
# day before floor() can otherwise place an exact midnight on the prior date.
decode_time <- function(values, units, calendar = "standard") {
  time <- cf_time_seconds(values, units, calendar)
  days <- time$seconds / 86400
  nearest <- round(days)
  rounding_error <- 16 * .Machine$double.eps * pmax(1, abs(days))
  days[abs(days - nearest) <= rounding_error] <- nearest[abs(days - nearest) <= rounding_error]
  time$origin + floor(days)
}

# Seconds after the origin date (midnight UTC) of CF time values.
cf_time_seconds <- function(values, units, calendar = "standard") {
  pattern <- paste0("^\\s*([A-Za-z]+)\\s+since\\s+",
                    "(\\d{1,4}-\\d{1,2}-\\d{1,2})",
                    "(?:[ T](\\d{1,2}):(\\d{2})(?::(\\d{2}(?:\\.\\d+)?))?)?",
                    "(?:\\s*(Z|UTC|[+-]\\d{1,2}:?\\d{2}))?\\s*$")
  parts <- regmatches(units, regexec(pattern, units, perl = TRUE))[[1]]
  if (length(parts) == 0) {
    fail(sprintf("The time units '%s' are not of the form 'days since YYYY-MM-DD'.", units))
  }
  seconds_per_unit <- unname(c(day = 86400, hour = 3600, minute = 60, second = 1)[sub("s$", "", tolower(parts[2]))])
  if (is.na(seconds_per_unit)) fail(sprintf("The time unit '%s' is not supported.", parts[2]))
  if (!tolower(calendar) %in% c("standard", "gregorian", "proleptic_gregorian")) {
    fail(sprintf("The time calendar '%s' is not supported; only standard Gregorian calendars are.", calendar))
  }
  origin <- as.Date(parts[3])
  if (is.na(origin)) fail(sprintf("The time origin '%s' is not a valid date.", parts[3]))
  hour <- if (nzchar(parts[4])) as.numeric(parts[4]) else 0
  minute <- if (nzchar(parts[5])) as.numeric(parts[5]) else 0
  second <- if (nzchar(parts[6])) as.numeric(parts[6]) else 0
  if (hour >= 24 || minute >= 60 || second >= 60) {
    fail(sprintf("The time origin in '%s' is not a valid time.", units))
  }
  timezone_seconds <- 0
  if (nzchar(parts[7]) && grepl("^[+-]", parts[7])) {
    offset <- gsub(":", "", substring(parts[7], 2), fixed = TRUE)
    zone_hour <- as.numeric(substr(offset, 1, nchar(offset) - 2))
    zone_minute <- as.numeric(substr(offset, nchar(offset) - 1, nchar(offset)))
    if (zone_hour >= 24 || zone_minute >= 60) {
      fail(sprintf("The time zone in '%s' is not valid.", units))
    }
    timezone_seconds <- if (startsWith(parts[7], "+")) 1 else -1
    timezone_seconds <- timezone_seconds * (zone_hour * 3600 + zone_minute * 60)
  }
  total_seconds <- as.numeric(values) * seconds_per_unit +
    hour * 3600 + minute * 60 + second - timezone_seconds
  if (any(!is.finite(total_seconds))) fail("The time coordinate contains missing or infinite values.")
  list(origin = origin, seconds = total_seconds)
}
