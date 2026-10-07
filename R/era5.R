# Reading ERA5 2-m temperature: hourly or daily values in one or several
# NetCDF files, reduced to the daily maximum temperature that SCORCH analyses.

#' Read ERA5 2-m temperature as daily maximum temperature
#'
#' Reads ERA5 2-m air temperature (`t2m`) from NetCDF files as downloaded from
#' the Copernicus Climate Data Store, and prepares the daily maximum
#' temperature that SCORCH analyses, in the same way as the SCORCH study:
#'
#' 1. Hourly (or other sub-daily) values are reduced to the maximum of each
#'    calendar day in UTC, the time standard of ERA5. Every analysed day must
#'    be complete (for hourly data, all 24 hours). Daily values, such as the
#'    ERA5 daily statistics of the 2-m temperature maximum, are used as they
#'    are.
#' 2. Kelvin is converted to degrees Celsius.
#' 3. With `cell_size` (1 degree, as in the study), the daily maxima at the
#'    ERA5 grid points are averaged to cells of that size: a point belongs to
#'    the cell `[k, k + cell_size)` of longitude and latitude that contains it,
#'    and the cell value is the mean of its points (points without a value are
#'    left out of the mean). Only cells whose points are all in the file are
#'    kept, so a region downloaded with its edges included (for example
#'    20-70 E at 0.25 degrees) gives the cells between those edges.
#'    `cell_size = NULL` analyses the ERA5 grid itself.
#'
#' Longitudes from 0 to 360 are converted to -180 to 180 when the region stays
#' contiguous, and latitudes may run north to south. Several files (for
#' example one per year or month) are combined by date; each must contain
#' whole days on the same grid, and no date may appear in two files. The
#' warm-season months and date limits are applied before the files are
#' reduced, so only the analysed days need to be complete.
#'
#' Accepted files hold the temperature as a variable with the dimensions
#' longitude, latitude and time (any order, any names given by the
#' arguments). An `expver` dimension (ERA5 combined with the preliminary
#' ERA5T) is merged by taking, at every time, the version that has a value;
#' other extra dimensions must have length one. Packed values
#' (`scale_factor`, `add_offset`) and missing values (`_FillValue`,
#' `missing_value`) are decoded.
#'
#' @param files Paths of one or several NetCDF files, or of a folder whose
#'   `.nc` files are all read.
#' @param variable,lon,lat,time Names of the temperature variable and of the
#'   longitude, latitude and time dimensions. `"auto"` finds `t2m` (or
#'   `2m_temperature`), `longitude` (or `lon`), `latitude` (or `lat`) and
#'   `valid_time` (or `time`).
#' @param units `"auto"` reads the variable's `units` attribute (ERA5: `K`);
#'   `"degC"` or `"K"` override it.
#' @param cell_size Size in degrees of the cells to which the daily maxima are
#'   averaged (1 in the SCORCH study), or `NULL` to keep the ERA5 grid. It must
#'   be a whole multiple of the grid spacing.
#' @inheritParams read_tmax
#' @inherit read_tmax return
#' @seealso [read_tmax()] for daily maximum temperature that is already
#'   prepared.
#' @examples
#' # A small ERA5-like file: hourly 2-m temperature (K) on a 0.25-degree grid.
#' file <- tempfile(fileext = ".nc")
#' lon <- seq(20, 22, by = 0.25); lat <- seq(12, 10, by = -0.25)
#' hours <- 0:(24 * 3 - 1)
#' dims <- list(ncdf4::ncdim_def("longitude", "degrees_east", lon),
#'              ncdf4::ncdim_def("latitude", "degrees_north", lat),
#'              ncdf4::ncdim_def("valid_time", "hours since 2000-07-01", hours))
#' t2m <- ncdf4::ncvar_def("t2m", "K", dims, prec = "float")
#' nc <- ncdf4::nc_create(file, t2m)
#' ncdf4::ncvar_put(nc, t2m, 300 + runif(length(lon) * length(lat) * length(hours)))
#' ncdf4::nc_close(nc)
#' tmax <- read_era5(file, months = 7)   # daily maxima averaged to 1-degree cells
#' tmax
#' @export
read_era5 <- function(files, variable = "auto", lon = "auto", lat = "auto", time = "auto",
                      units = "auto", months = 4:9, start = NULL, end = NULL, cell_size = 1) {
  files <- input_files(files)
  if (!is.numeric(months) || !length(months) || anyNA(months) || !all(months %in% 1:12)) {
    fail("`months` must list calendar months between 1 and 12.")
  }
  start <- if (is.null(start)) NULL else check_date(start, "start")
  end <- if (is.null(end)) NULL else check_date(end, "end")
  if (!is.null(cell_size)) check_number(cell_size, "cell_size", lower = 1e-9)
  parts <- list()
  for (file in files) {
    part <- read_era5_file(file, variable, lon, lat, time, units, months, start, end, cell_size)
    if (is.null(part)) next
    if (length(parts)) {
      first <- parts[[1]]
      if (length(part$lon) != length(first$lon) || length(part$lat) != length(first$lat) ||
          max(abs(part$lon - first$lon)) > 1e-6 || max(abs(part$lat - first$lat)) > 1e-6) {
        fail("The ERA5 files ", first$file, " and ", file, " do not cover the same grid.")
      }
    }
    parts[[length(parts) + 1L]] <- part
  }
  if (!length(parts)) fail("No dates are left after selecting the warm-season months and the start and end dates.")
  dates <- do.call(c, lapply(parts, `[[`, "dates"))
  if (anyDuplicated(dates)) {
    fail("The date ", format(dates[anyDuplicated(dates)]), " appears in more than one ERA5 file.")
  }
  values <- array(unlist(lapply(parts, function(p) aperm(p$values, c(2, 3, 1))), use.names = FALSE),
                  c(length(parts[[1]]$lat), length(parts[[1]]$lon), length(dates)))
  values <- aperm(values, c(3, 1, 2))
  source <- if (length(files) == 1L) files else sprintf("%d ERA5 files (%s to %s)", length(files),
                                                         basename(files[1]), basename(files[length(files)]))
  tmax <- tmax_from_array(values, dates, parts[[1]]$lon, parts[[1]]$lat, units = "degC", months = months,
                          start = start, end = end, source = source)
  per_day <- unique(vapply(parts, `[[`, 1, "per_day"))
  tmax$preprocessing <- paste0(
    "ERA5 2-m temperature, ",
    if (identical(per_day, 1)) "daily values" else paste(paste(per_day, collapse = "/"), "values per day reduced to the daily maximum (UTC days)"),
    if (is.null(cell_size)) ", ERA5 grid" else sprintf(", averaged to %g-degree cells", cell_size))
  message(tmax$preprocessing, ".")
  tmax
}

# The temperature named in the configuration: raw ERA5 through read_era5(),
# daily maximum temperature through read_tmax().
read_configured_input <- function(cfg) {
  input <- cfg$input
  period <- cfg$period
  files <- input_files(input$file)
  format <- input$format
  if (identical(format, "auto")) format <- detect_input_format(files[1])
  if (format == "era5") {
    return(read_era5(files, variable = input$variable, lon = input$longitude, lat = input$latitude,
                     time = input$time, units = input$units, months = period$warm_season_months,
                     start = period$start_date, end = period$end_date, cell_size = input$era5_cell_size_deg))
  }
  if (length(files) != 1L || any(dir.exists(input$file))) {
    fail("Daily maximum temperature (format daily_tmax) is read from one NetCDF file; ",
         "several files or a folder are supported for ERA5 input (format era5).")
  }
  nc <- ncdf4::nc_open(files)
  dims <- names(nc$dim)
  variable <- pick_name(input$variable, "tmax", names(nc$var), "temperature variable", files)
  lon <- pick_name(input$longitude, c("lon", "longitude"), dims, "longitude dimension", files)
  lat <- pick_name(input$latitude, c("lat", "latitude"), dims, "latitude dimension", files)
  time <- pick_name(input$time, c("time", "valid_time"), dims, "time dimension", files)
  ncdf4::nc_close(nc)
  read_tmax(files, variable = variable, lon = lon, lat = lat, time = time, units = input$units,
            months = period$warm_season_months, start = period$start_date, end = period$end_date)
}

# era5 when the file holds ERA5 2-m temperature, otherwise daily_tmax.
detect_input_format <- function(file) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  if (any(c("t2m", "2m_temperature") %in% names(nc$var))) "era5" else "daily_tmax"
}

# The NetCDF files named by a path, several paths, or a folder.
input_files <- function(files) {
  if (!is.character(files) || !length(files) || anyNA(files) || any(!nzchar(trimws(files)))) {
    fail("The input must be the path of a NetCDF file, several such paths, or a folder.")
  }
  missing <- files[!file.exists(files)]
  if (length(missing)) fail("The input file does not exist: ", missing[1])
  unlist(lapply(files, function(path) {
    if (!dir.exists(path)) return(path)
    inside <- sort(list.files(path, pattern = "\\.nc$", full.names = TRUE, ignore.case = TRUE))
    if (!length(inside)) fail("The input folder contains no .nc files: ", path)
    inside
  }), use.names = FALSE)
}

# The first of the candidate names found in `available`, or the given name.
pick_name <- function(name, candidates, available, what, file) {
  if (!identical(name, "auto")) {
    if (!name %in% available) {
      fail(sprintf("The file %s has no %s called '%s'. It has: %s.", file, what, name,
                   paste(available, collapse = ", ")))
    }
    return(name)
  }
  found <- intersect(candidates, available)
  if (!length(found)) {
    fail(sprintf("The file %s has no %s called %s; name it in the configuration. It has: %s.", file, what,
                 paste0("'", candidates, "'", collapse = " or "), paste(available, collapse = ", ")))
  }
  found[1]
}

# One file: daily maxima (degrees Celsius) of the selected days, as an array
# date x latitude x longitude with ascending coordinates; NULL when the file
# holds no selected day.
read_era5_file <- function(file, variable, lon, lat, time, units, months, start, end, cell_size) {
  nc <- ncdf4::nc_open(file)
  on.exit(ncdf4::nc_close(nc))
  variable <- pick_name(variable, c("t2m", "2m_temperature"), names(nc$var), "temperature variable", file)
  var <- nc$var[[variable]]
  dim_names <- vapply(var$dim, function(d) d$name, "")
  lon <- pick_name(lon, c("longitude", "lon"), dim_names, "longitude dimension", file)
  lat <- pick_name(lat, c("latitude", "lat"), dim_names, "latitude dimension", file)
  time <- pick_name(time, c("valid_time", "time"), dim_names, "time dimension", file)
  extra <- setdiff(dim_names, c(lon, lat, time))
  sizes <- vapply(var$dim, function(d) d$len, 1)
  names(sizes) <- dim_names
  bad <- extra[extra != "expver" & sizes[extra] != 1]
  if (length(bad)) {
    fail(sprintf("The variable '%s' in %s has the extra dimension '%s'; only longitude, latitude, time and expver are supported.",
                 variable, file, bad[1]))
  }
  for (name in c(time, lat, lon)) {
    if (!isTRUE(nc$dim[[name]]$create_dimvar)) {
      fail(sprintf("The dimension '%s' in %s has no coordinate values.", name, file))
    }
  }
  if (identical(units, "auto")) {
    attribute <- ncdf4::ncatt_get(nc, variable, "units")
    if (!attribute$hasatt) fail("The temperature in ", file, " has no 'units' attribute. Set units to 'degC' or 'K'.")
    units <- attribute$value
  }
  unit <- temperature_unit(units)

  # Dates (UTC) of the time steps, the time step, and the selected days.
  time_dim <- nc$dim[[time]]
  calendar <- ncdf4::ncatt_get(nc, time, "calendar")
  calendar <- if (calendar$hasatt) calendar$value else "standard"
  cf <- cf_time_seconds(time_dim$vals, time_dim$units, calendar)
  seconds <- as.numeric(cf$origin) * 86400 + cf$seconds
  if (anyDuplicated(seconds)) fail("The time coordinate of ", file, " repeats a time.")
  dates <- decode_time(time_dim$vals, time_dim$units, calendar)
  step <- if (length(seconds) > 1) min(diff(sort(seconds))) else 86400
  if (step > 86400 * (1 + 1e-9)) fail("The time steps of ", file, " are longer than one day.")
  per_day <- 86400 / step
  if (abs(per_day - round(per_day)) > 1e-6) {
    fail(sprintf("The time step of %s (%g seconds) does not divide a day.", file, step))
  }
  per_day <- round(per_day)
  keep <- as.integer(format(dates, "%m")) %in% months
  if (!is.null(start)) keep <- keep & dates >= start
  if (!is.null(end)) keep <- keep & dates <= end
  if (!any(keep)) return(NULL)
  days <- sort(unique(dates[keep]))
  counts <- tabulate(match(dates[keep], days), length(days))
  if (any(counts != per_day)) {
    i <- which(counts != per_day)[1]
    fail(sprintf(paste("The day %s in %s has %d of its %d time steps. Every analysed day must be complete;",
                       "download whole days, or limit start_date and end_date."),
                 format(days[i]), file, counts[i], per_day))
  }

  # Coordinates: longitudes in -180..180 when the region stays contiguous,
  # then ascending order in both directions.
  lon_values <- as.numeric(nc$dim[[lon]]$vals)
  lat_values <- as.numeric(nc$dim[[lat]]$vals)
  lon_order <- wrap_longitudes(lon_values)
  lon_values <- lon_order$lon
  lat_order <- order(lat_values)
  lat_values <- lat_values[lat_order]

  # Read whole days in blocks of consecutive time steps (about 40 MB each)
  # and keep the maximum of each day.
  out <- array(NA_real_, c(length(days), length(lat_values), length(lon_values)))
  day_of_step <- ifelse(keep, match(dates, days), NA_integer_)
  first_step <- vapply(seq_along(days), function(d) min(which(day_of_step == d)), 1)
  last_step <- vapply(seq_along(days), function(d) max(which(day_of_step == d)), 1)
  if (any(last_step - first_step + 1 != per_day)) {
    fail("The time steps of each day must follow one another in ", file, ".")
  }
  block_days <- max(1, floor(5e6 / (per_day * length(lon_values) * length(lat_values))))
  pending <- order(first_step)
  while (length(pending)) {
    block <- pending[1]
    while (length(block) < block_days && length(block) < length(pending) &&
           first_step[pending[length(block) + 1]] == last_step[block[length(block)]] + 1) {
      block <- pending[seq_len(length(block) + 1)]
    }
    pending <- pending[-seq_along(block)]
    from <- first_step[block[1]]
    n_steps <- last_step[block[length(block)]] - from + 1
    values <- ncdf4::ncvar_get(nc, variable, start = ifelse(dim_names == time, from, 1),
                               count = ifelse(dim_names == time, n_steps, -1), collapse_degen = FALSE)
    values <- merge_extra_dimensions(values, dim_names, c(time, lat, lon))
    rows <- matrix(values[, lat_order, lon_order$index, drop = FALSE], nrow = n_steps)
    for (d in block) {
      at <- seq.int(first_step[d], last_step[d]) - from + 1
      out[d, , ] <- do.call(pmax, c(lapply(at, function(i) rows[i, ]), na.rm = TRUE))
    }
  }
  if (unit == "K") out <- out - 273.15

  if (!is.null(cell_size)) {
    cells <- average_to_cells(out, lon_values, lat_values, cell_size, file)
    out <- cells$values
    lon_values <- cells$lon
    lat_values <- cells$lat
  }
  list(file = file, dates = days, lon = lon_values, lat = lat_values, values = out, per_day = per_day)
}

# Order a block as time x latitude x longitude, merging an expver dimension
# (the version with a value at each time) and dropping dimensions of length one.
merge_extra_dimensions <- function(block, dim_names, keep) {
  extra <- setdiff(dim_names, keep)
  block <- aperm(block, match(c(keep, extra), dim_names))
  if (!length(extra)) return(block)
  shape <- dim(block)
  core <- prod(shape[1:3])
  layers <- matrix(block, nrow = core)
  merged <- layers[, 1]
  for (j in seq_len(ncol(layers))[-1]) merged[is.na(merged)] <- layers[is.na(merged), j]
  array(merged, shape[1:3])
}

# Longitudes converted from 0..360 to -180..180 and sorted, when the result
# is still evenly spaced (a region that does not cross 180 degrees).
wrap_longitudes <- function(lon) {
  if (all(lon <= 180)) {
    index <- order(lon)
    return(list(lon = lon[index], index = index))
  }
  wrapped <- ((lon + 180) %% 360) - 180
  index <- order(wrapped)
  steps <- diff(wrapped[index])
  if (length(steps) && (any(steps == 0) || max(abs(steps - steps[1])) > 1e-4 * abs(steps[1]))) {
    index <- order(lon)
    return(list(lon = lon[index], index = index))
  }
  list(lon = wrapped[index], index = index)
}

# Average daily values (date x latitude x longitude, ascending coordinates) to
# cells of `size` degrees: a point belongs to the cell [k * size, (k + 1) *
# size) that contains it, and only cells with all their points are kept.
average_to_cells <- function(values, lon, lat, size, file) {
  group <- function(coordinate, name) {
    step <- abs(grid_step(coordinate, name))
    n <- size / step
    if (n < 1 - 1e-6 || abs(n - round(n)) > 1e-6) {
      fail(sprintf("The ERA5 %s spacing (%g degrees) in %s does not divide era5_cell_size_deg (%g).",
                   name, step, file, size))
    }
    cell <- floor(coordinate / size + 1e-6)
    complete <- as.numeric(names(which(table(cell) == round(n))))
    if (!length(complete)) {
      fail(sprintf("The ERA5 grid in %s is too small for one %g-degree cell.", file, size))
    }
    list(cell = cell, ids = complete, centre = (complete + 0.5) * size)
  }
  by_lon <- group(lon, "longitude")
  by_lat <- group(lat, "latitude")
  out <- array(NA_real_, c(dim(values)[1], length(by_lat$ids), length(by_lon$ids)))
  for (i in seq_along(by_lat$ids)) {
    rows <- which(by_lat$cell == by_lat$ids[i])
    for (j in seq_along(by_lon$ids)) {
      cols <- which(by_lon$cell == by_lon$ids[j])
      points <- matrix(values[, rows, cols, drop = FALSE], nrow = dim(values)[1])
      mean_value <- rowMeans(points, na.rm = TRUE)
      mean_value[is.nan(mean_value)] <- NA_real_
      out[, i, j] <- mean_value
    }
  }
  list(values = out, lon = by_lon$centre, lat = by_lat$centre)
}
