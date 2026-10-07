# The SCORCH configuration: the shipped settings, copies to edit, reading and
# validation.

#' Write an editable copy of the SCORCH configuration
#'
#' The package ships with the configuration of the SCORCH study
#' (`scorch_config.yaml`), the single source of the default settings. This
#' function copies it, unchanged and fully commented, so that individual
#' settings can be changed for another application. Set `input: file` to the
#' NetCDF file to analyse, change any other setting, and pass the copy to
#' [run_scorch()]. Settings deleted from the copy keep their study values.
#'
#' @param path File to write (YAML).
#' @param overwrite Replace an existing file?
#' @return The path, invisibly.
#' @seealso [scorch_template()] for a copy already set up for the example
#'   dataset.
#' @examples
#' path <- write_scorch_config(tempfile(fileext = ".yaml"))
#' cat(readLines(path, n = 16), sep = "\n")
#' @export
write_scorch_config <- function(path = "scorch_config.yaml", overwrite = FALSE) {
  check_new_file(path, overwrite)
  writeLines(readLines(scorch_config_file()), path)
  invisible(path)
}

#' Write a configuration for the example dataset
#'
#' Writes a copy of the SCORCH configuration (see [write_scorch_config()])
#' with `input: file` set to the example dataset shipped with the package, so
#' that [run_scorch()] can be tried at once. All other settings are those of
#' the SCORCH study.
#'
#' @param path File to write (YAML).
#' @param fast If `TRUE`, the file is a clearly labelled fast demonstration
#'   with 200 bootstrap repetitions instead of the study's 5000, for learning
#'   and testing only.
#' @param overwrite Replace an existing file?
#' @return The path, invisibly.
#' @examples
#' path <- scorch_template(tempfile(fileext = ".yaml"), fast = TRUE)
#' cat(readLines(path, n = 12), sep = "\n")
#' @export
scorch_template <- function(path = "scorch_config.yaml", fast = FALSE, overwrite = FALSE) {
  check_new_file(path, overwrite)
  lines <- readLines(scorch_config_file())
  example <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
  input_line <- grep("^  file: null ", lines)
  if (length(input_line) != 1L) fail("The shipped configuration has no single 'input: file' line.")
  lines[input_line] <- sprintf("  file: '%s'    # the example dataset; replace with your NetCDF file, in quotes", example)
  if (fast) {
    lines <- sub("bootstrap_repetitions: 5000", "bootstrap_repetitions: 200 ", lines, fixed = TRUE)
    lines <- c("# FAST DEMONSTRATION: 200 bootstrap repetitions instead of the study's 5000.",
               "# Use it to learn and test the workflow, not for results.", "", lines)
  }
  writeLines(lines, path)
  invisible(path)
}

check_new_file <- function(path, overwrite) {
  if (file.exists(path) && !overwrite) {
    fail("The file already exists: ", path, ". Choose another name or set overwrite = TRUE.")
  }
  invisible(path)
}

# The SCORCH configuration installed with the package.
scorch_config_file <- function() {
  path <- system.file("scorch_config.yaml", package = "scoRch.generator")
  if (!nzchar(path)) fail("The SCORCH configuration shipped with the package is missing; reinstall scoRch.generator.")
  path
}

# Study defaults for every setting except the input file, read from the
# shipped SCORCH configuration. Whole numbers take the types R gives them in
# code: single settings are doubles (95), lists are integers (4:9).
scorch_defaults <- function() {
  lapply(yaml::read_yaml(scorch_config_file()), function(section) {
    lapply(section, function(value) {
      value <- yaml_vector(value)
      if (is.integer(value) && length(value) == 1L) as.numeric(value) else value
    })
  })
}

# YAML lists of mixed integers and decimals arrive as R lists.
yaml_vector <- function(value) {
  if (is.list(value) && length(value) && is.null(names(value)) &&
      all(lengths(value) == 1L)) unlist(value) else value
}

# Read a configuration (file path, list or NULL), check its keys and fill in
# the study defaults for settings that are left out.
read_config <- function(config = NULL, input_required = TRUE) {
  if (is.null(config)) {
    given <- list()
  } else if (is.character(config) && length(config) == 1) {
    if (!file.exists(config)) fail("The configuration file does not exist: ", config)
    given <- yaml::read_yaml(config)
  } else if (is.list(config)) {
    given <- config
  } else {
    fail("`config` must be the path of a YAML configuration file, a list of settings or NULL.")
  }
  defaults <- scorch_defaults()
  if (length(given) && (is.null(names(given)) || anyNA(names(given)) ||
                        any(!nzchar(names(given))))) {
    fail("Configuration sections must have names such as 'input' and 'period'.")
  }
  if (anyDuplicated(names(given))) fail("The configuration repeats a section name.")
  unknown <- setdiff(names(given), names(defaults))
  if (length(unknown)) fail("Unknown settings in the configuration: ", paste(unknown, collapse = ", "))
  cfg <- defaults
  for (section in names(given)) {
    if (!is.list(given[[section]])) fail("The configuration section '", section, "' must contain settings.")
    if (length(given[[section]]) &&
        (is.null(names(given[[section]])) || anyNA(names(given[[section]])) ||
         any(!nzchar(names(given[[section]]))))) {
      fail("The configuration section '", section, "' must contain named settings.")
    }
    if (anyDuplicated(names(given[[section]]))) {
      fail("The configuration section '", section, "' repeats a setting name.")
    }
    unknown <- setdiff(names(given[[section]]), names(defaults[[section]]))
    if (length(unknown)) {
      fail(sprintf("Unknown settings in the configuration section '%s': %s", section, paste(unknown, collapse = ", ")))
    }
    for (key in names(given[[section]])) {
      cfg[[section]][key] <- list(yaml_vector(given[[section]][[key]]))
    }
  }
  if (input_required && is.null(cfg$input$file)) {
    fail("No input file is set. Name the NetCDF file in the setting 'input: file' of a configuration ",
         "(write_scorch_config() writes an editable copy), or pass `tmax` to run_scorch().")
  }
  files <- cfg$input$file
  if (!is.null(files)) {
    if (!is.character(files) || !length(files) || anyNA(files) || any(!nzchar(trimws(files)))) {
      fail("The setting 'input: file' must be a file or folder path, or a list of file paths.")
    }
    missing <- files[!file.exists(files)]
    if (input_required && length(missing)) fail("The input file does not exist: ", missing[1])
  }
  check_config_string(cfg$input$format, "input: format")
  if (!cfg$input$format %in% c("auto", "era5", "daily_tmax")) {
    fail("The setting 'input: format' must be auto, era5 or daily_tmax.")
  }
  for (key in c("variable", "longitude", "latitude", "time")) {
    check_config_string(cfg$input[[key]], paste0("input: ", key))
  }
  dimensions <- unlist(cfg$input[c("longitude", "latitude", "time")], use.names = FALSE)
  dimensions <- dimensions[dimensions != "auto"]
  if (anyDuplicated(dimensions)) fail("The input longitude, latitude and time dimension names must be distinct.")
  check_config_string(cfg$input$units, "input: units")
  if (!is.null(cfg$input$era5_cell_size_deg)) {
    check_number(cfg$input$era5_cell_size_deg, "era5_cell_size_deg", lower = 1e-9)
  }
  if (!identical(cfg$input$units, "auto")) temperature_unit(cfg$input$units)
  check_config_string(cfg$output$directory, "output: directory")
  if (file.exists(cfg$output$directory) && !dir.exists(cfg$output$directory)) {
    fail("The output: directory path is an existing file: ", cfg$output$directory)
  }

  months <- cfg$period$warm_season_months
  validate_season_months(months)
  if (anyDuplicated(months)) fail("The setting 'warm_season_months' must list distinct calendar months.")
  for (key in c("start_date", "end_date")) cfg$period[[key]] <- check_date(cfg$period[[key]], key)
  if (!is.null(cfg$period$start_date) && !is.null(cfg$period$end_date) &&
      cfg$period$start_date > cfg$period$end_date) {
    fail("The setting 'start_date' must be on or before 'end_date'.")
  }

  check_number(cfg$heatwaves$threshold_percentile, "threshold_percentile", 0, 100)
  check_number(cfg$heatwaves$min_duration_days, "min_duration_days", 1, integer = TRUE)
  check_number(cfg$heatwaves$min_exceeding_days, "min_exceeding_days", 1, integer = TRUE)
  check_number(cfg$regional_days$percentile, "regional_days: percentile", 0, 100)
  check_config_numeric_vector(cfg$clustering$eps_values, "eps_values")
  check_config_numeric_vector(cfg$clustering$min_samples_values, "min_samples_values", integer = TRUE)
  check_number(cfg$ellipses$scale_factor, "scale_factor", lower = 0)
  if (cfg$ellipses$scale_factor == 0) fail("The setting 'scale_factor' must be positive.")
  check_number(cfg$power_law$bootstrap_repetitions, "bootstrap_repetitions", 1, integer = TRUE)
  check_number(cfg$power_law$seed_daily_maxima, "seed_daily_maxima", integer = TRUE)
  check_number(cfg$power_law$seed_event_maxima, "seed_event_maxima", integer = TRUE)
  covariates <- cfg$lgcp$covariates
  known <- c("lon", "lat", "mean_tmax", "std_tmax")
  if (!is.character(covariates) || !length(covariates) || anyNA(covariates) ||
      anyDuplicated(covariates) || !all(covariates %in% known)) {
    fail("The setting 'lgcp: covariates' must list distinct names from: ", paste(known, collapse = ", "), ".")
  }
  check_number(cfg$lgcp$raster_km, "raster_km", lower = 1e-6)
  check_number(cfg$lgcp$window_margin_km, "window_margin_km", lower = 0)

  chosen <- cfg$figures$representative_events
  if (!is.list(chosen) || (length(chosen) &&
      (is.null(names(chosen)) || anyNA(names(chosen)) || any(!nzchar(names(chosen)))))) {
    fail("The setting 'figures: representative_events' must contain named event types.")
  }
  if (anyDuplicated(names(chosen))) fail("The setting 'figures: representative_events' repeats an event type.")
  unknown <- setdiff(names(chosen), c("type_1", "type_2", "type_3", "type_4"))
  if (length(unknown)) fail("Unknown settings under figures: representative_events: ", paste(unknown, collapse = ", "))
  for (type in c("type_1", "type_2", "type_3", "type_4")) {
    dates <- chosen[[type]]
    if (is.null(dates)) next
    maximum <- if (type == "type_3") 2L else 1L
    if (!(is.character(dates) || inherits(dates, "Date")) ||
        !length(dates) || length(dates) > maximum) {
      fail("The setting 'figures: representative_events: ", type,
           "' needs ", if (maximum == 1L) "one date" else "one or two dates", " written as YYYY-MM-DD.")
    }
    for (i in seq_along(dates)) check_date(dates[i], paste0("figures: representative_events: ", type))
    if (anyDuplicated(as.character(dates))) {
      fail("The setting 'figures: representative_events: ", type, "' contains a repeated date.")
    }
  }
  cfg
}

check_config_string <- function(value, name, allow_null = FALSE) {
  if (allow_null && is.null(value)) return(invisible(NULL))
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(trimws(value))) {
    fail("The setting '", name, "' must be one non-empty string.")
  }
  invisible(value)
}

check_config_numeric_vector <- function(value, name, integer = FALSE) {
  valid <- is.numeric(value) && length(value) > 0L && all(is.finite(value)) &&
    (if (integer) all(value >= 1 & value == round(value) & value <= .Machine$integer.max)
     else all(value > 0)) &&
    !anyDuplicated(value)
  if (!valid) {
    fail("The setting '", name, "' must list distinct, finite ",
         if (integer) "whole numbers of at least 1" else "positive numbers", ".")
  }
  invisible(value)
}

# A date setting must be NULL or written as YYYY-MM-DD; returns it as a Date.
check_date <- function(value, name) {
  if (is.null(value)) return(NULL)
  text <- as.character(value)
  valid <- (is.character(value) || inherits(value, "Date")) && length(text) == 1L &&
    !is.na(text) && grepl("^\\d{4}-\\d{2}-\\d{2}$", text)
  date <- if (valid) as.Date(text, format = "%Y-%m-%d") else NA
  if (is.na(date)) fail(sprintf("The setting '%s' must be one date written as YYYY-MM-DD (it is '%s').", name, paste(text, collapse = ", ")))
  date
}
