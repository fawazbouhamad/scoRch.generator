#' @keywords internal
"_PACKAGE"

# Numerical conventions of the SCORCH method that are not user settings.
NOISE_LABEL <- -1L             # DBSCAN label of a cell that belongs to no cluster
EIGENVALUE_FLOOR_KM2 <- 1.0    # smallest eigenvalue used for an ellipse axis
KM_PER_DEG_LAT <- 110.574      # local equirectangular projection of ellipses
KM_PER_DEG_LON_EQUATOR <- 111.320
TYPE_NAMES <- c("Widespread (Isolated)", "Spatially Clustered",
                "Temporally Clustered", "Compound Clustering (Multi-Type)")
TYPE_COLOURS <- c("#d7191c", "#f57c00", "#d9a300", "#6a3d9a")

# Stop with a plain-language message, without printing the call.
fail <- function(...) stop(paste0(...), call. = FALSE)

# Check that a setting is one number inside [lower, upper]; whole numbers
# must also fit R's integer range.
check_number <- function(value, name, lower = -Inf, upper = Inf, integer = FALSE) {
  if (integer) upper <- min(upper, .Machine$integer.max)
  if (integer) lower <- max(lower, -.Machine$integer.max)
  ok <- is.numeric(value) && length(value) == 1 && is.finite(value) &&
    value >= lower && value <= upper && (!integer || value == round(value))
  if (!ok) {
    fail(sprintf("The setting '%s' must be one %s between %s and %s (it is '%s').",
                 name, if (integer) "whole number" else "number", format(lower), format(upper),
                 paste(format(value), collapse = ", ")))
  }
  invisible(value)
}

# Sort cells west to east, then south to north: the cell order used by the
# clustering, which decides which cluster a border cell joins first.
longitude_major_order <- function(lon, lat) order(lon, lat)
