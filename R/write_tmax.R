# Writing prepared daily maximum temperature to a NetCDF file that
# read_tmax() reads back.

#' Write daily maximum temperature to a NetCDF file
#'
#' Writes a `scorch_tmax` object (from [read_era5()], [read_tmax()] or
#' [tmax_from_array()]) as one NetCDF file with the dimensions `lon`, `lat`
#' and `time` and the variable `tmax` in degrees Celsius, the layout that
#' [read_tmax()] and the `input: file` setting of [run_scorch()] accept. The
#' from-scratch path of [run_scorch()] writes its processed input this way,
#' so that the download and reduction need to be done only once.
#'
#' @param tmax A `scorch_tmax` object.
#' @param file Path of the NetCDF file to write.
#' @param precision `"int16"` stores the values as 16-bit integers with a
#'   scale factor of 0.01 degrees Celsius (a third of the size of
#'   `"float32"`, rounded to 0.01); `"float32"` stores them unrounded.
#' @param title,source,licence,history Global attributes. `source` defaults to
#'   the input description of `tmax`, `history` to the package version and
#'   date.
#' @param overwrite Replace an existing file?
#' @return The path, invisibly.
#' @examples
#' file <- system.file("extdata", "north_america_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file, months = 7, start = "2012-01-01", end = "2012-12-31")
#' copy <- write_tmax(tmax, tempfile(fileext = ".nc"))
#' identical(read_tmax(copy, months = 7)$tmax, tmax$tmax)
#' @export
write_tmax <- function(tmax, file, precision = c("int16", "float32"), title = NULL, source = NULL,
                       licence = NULL, history = NULL, overwrite = FALSE) {
  if (!inherits(tmax, "scorch_tmax")) fail("`tmax` must come from read_era5(), read_tmax() or tmax_from_array().")
  precision <- match.arg(precision)
  check_new_file(file, overwrite)
  lon <- tmax$grid$lon
  lat <- tmax$grid$lat
  values <- array(NA_real_, c(length(lon), length(lat), length(tmax$dates)))
  index <- cbind(match(tmax$cells$lon, lon), match(tmax$cells$lat, lat))
  for (k in seq_len(nrow(tmax$cells))) values[index[k, 1], index[k, 2], ] <- tmax$tmax[, k]
  origin <- as.Date(paste0(format(tmax$dates[1], "%Y"), "-01-01"))
  dims <- list(
    ncdf4::ncdim_def("lon", "degrees_east", lon, longname = "longitude of grid-cell centre"),
    ncdf4::ncdim_def("lat", "degrees_north", lat, longname = "latitude of grid-cell centre"),
    ncdf4::ncdim_def("time", paste("days since", format(origin)), as.numeric(tmax$dates - origin),
                     calendar = "standard", longname = "date"))
  long_name <- "daily maximum 2-m air temperature"
  if (precision == "int16") {
    var <- ncdf4::ncvar_def("tmax", "degC", dims, missval = -32768L, prec = "short", longname = long_name,
                            compression = 9, shuffle = TRUE)
  } else {
    var <- ncdf4::ncvar_def("tmax", "degC", dims, missval = 1e30, prec = "float", longname = long_name,
                            compression = 9)
  }
  nc <- ncdf4::nc_create(file, var, force_v4 = TRUE)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  if (precision == "int16") {
    ncdf4::ncatt_put(nc, "tmax", "scale_factor", 0.01, prec = "double")
    ncdf4::ncvar_put(nc, var, round(values * 100))
  } else {
    ncdf4::ncvar_put(nc, var, values)
  }
  ncdf4::ncatt_put(nc, "tmax", "standard_name", "air_temperature")
  ncdf4::ncatt_put(nc, "tmax", "cell_methods", "time: maximum (interval: 1 day) area: mean")
  if (is.null(source)) {
    source <- paste(c(tmax$source, tmax$preprocessing), collapse = "; ")
  }
  if (is.null(history)) {
    history <- sprintf("written by scoRch.generator %s on %s",
                       as.character(utils::packageVersion("scoRch.generator")), format(Sys.Date()))
  }
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  if (!is.null(title)) ncdf4::ncatt_put(nc, 0, "title", title)
  ncdf4::ncatt_put(nc, 0, "source", source)
  if (!is.null(licence)) ncdf4::ncatt_put(nc, 0, "license", licence)
  ncdf4::ncatt_put(nc, 0, "history", history)
  invisible(file)
}
