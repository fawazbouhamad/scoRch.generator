# Stage 4: PCA ellipses and temperature-weighted centroids (Catalog 4).

#' Fit an ellipse and a temperature-weighted centroid to every cluster
#'
#' Member cells are projected to kilometres around their mean position (one
#' degree of latitude is 110.574 km; one degree of longitude is 111.320 km
#' times the cosine of the mean latitude). The ellipse axes are the principal
#' components of the sample covariance of these positions: the full axis
#' lengths are `2 * scale_factor * sqrt(eigenvalue)` (eigenvalues below 1 km^2
#' are raised to 1 km^2, so a single-cell cluster still gets a tiny ellipse).
#' The centroid is the Tmax-weighted mean position of the member cells, with
#' the day's Tmax of each cell (degrees Celsius, rounded to single precision
#' as in the study) as weight. This study-specific weighting requires positive
#' Celsius Tmax in every cluster cell; datasets with colder cluster days need
#' a different weighting rule and cannot use this stage unchanged.
#'
#' @param clusters A `scorch_clusters` object from [cluster_heatwaves()].
#' @param tmax The `scorch_tmax` object the clusters were derived from.
#' @param scale_factor Multiplier of the principal-component standard
#'   deviations that gives the ellipse semi-axes.
#' @return Catalog 4: a data frame with one row per cluster, giving the
#'   unweighted centre, eigenvalues, axis lengths (km), area (km^2), axis
#'   ratio, orientation (degrees counter-clockwise from east) and azimuth
#'   (degrees clockwise from north, in (-90, 90]) of the ellipse, and the
#'   temperature-weighted centroid.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file)
#' clusters <- cluster_heatwaves(select_regional_days(detect_heatwaves(tmax)))
#' ellipses <- fit_ellipses(clusters, tmax)
#' head(ellipses)
#' @export
fit_ellipses <- function(clusters, tmax, scale_factor = 1.25) {
  if (!inherits(clusters, "scorch_clusters")) fail("`clusters` must come from cluster_heatwaves().")
  if (!inherits(tmax, "scorch_tmax")) fail("`tmax` must come from read_tmax() or tmax_from_array().")
  check_number(scale_factor, "scale_factor", lower = 1e-9)
  if (!isTRUE(all.equal(clusters$cells[c("lon", "lat")], tmax$cells[c("lon", "lat")], check.attributes = FALSE))) {
    fail("`tmax` is not the temperature input the clusters were derived from (different grid cells).")
  }
  members <- clusters$cluster_cells[!is.na(clusters$cluster_cells$cluster_id), ]
  row <- match(members$date, tmax$dates)
  column <- match(members$cell_id, tmax$cells$cell_id)
  if (anyNA(row) || anyNA(column)) fail("The clusters do not belong to this temperature input.")
  members$tmax_c <- as_single_precision(tmax$tmax[cbind(row, column)])
  if (any(members$tmax_c <= 0)) {
    fail("The temperature-weighted centroid needs positive Tmax (degrees Celsius) in every cluster cell.")
  }
  if (!nrow(clusters$clusters)) {
    ellipses <- data.frame(
      ellipse_id = integer(), cluster_id = integer(), date = as.Date(character()),
      cluster_number_in_day = integer(), n_member_cells = integer(),
      centroid_lon_unweighted = numeric(), centroid_lat_unweighted = numeric(),
      eigenvalue_major_km2 = numeric(), eigenvalue_minor_km2 = numeric(),
      major_axis_km = numeric(), minor_axis_km = numeric(), area_km2 = numeric(),
      axis_ratio = numeric(), orientation_east_ccw_deg = numeric(),
      azimuth_north_cw_deg = numeric(), major_axis_east = numeric(),
      major_axis_north = numeric(), centroid_lon_weighted = numeric(),
      centroid_lat_weighted = numeric(), tmax_weight_sum_c = numeric(),
      tmax_min_c = numeric(), tmax_max_c = numeric())
    attr(ellipses, "scale_factor") <- scale_factor
    return(ellipses)
  }
  groups <- split(members, factor(members$cluster_id, levels = clusters$clusters$cluster_id))
  rows <- lapply(groups, function(g) {
    geometry <- ellipse_geometry(g$lon, g$lat, scale_factor)
    weight_sum <- sum(g$tmax_c)
    c(geometry, list(centroid_lon_weighted = sum(g$lon * g$tmax_c) / weight_sum,
                     centroid_lat_weighted = sum(g$lat * g$tmax_c) / weight_sum,
                     tmax_weight_sum_c = weight_sum, tmax_min_c = min(g$tmax_c),
                     tmax_max_c = max(g$tmax_c)))
  })
  geometry <- do.call(rbind, lapply(rows, as.data.frame))
  ellipses <- cbind(data.frame(ellipse_id = clusters$clusters$cluster_id,
                               cluster_id = clusters$clusters$cluster_id,
                               date = clusters$clusters$date,
                               cluster_number_in_day = clusters$clusters$cluster_number_in_day),
                    geometry)
  rownames(ellipses) <- NULL
  attr(ellipses, "scale_factor") <- scale_factor
  ellipses
}

# PCA ellipse of one cluster, centred on the mean cell position.
ellipse_geometry <- function(lon, lat, scale_factor) {
  lon0 <- mean(lon)
  lat0 <- mean(lat)
  xy <- project_local_km(lon, lat, lon0, lat0)
  if (length(lon) == 1) {
    eigenvalues <- c(1, 1)
    eigenvectors <- diag(2)
  } else {
    eig <- eigen(stats::cov(xy), symmetric = TRUE)   # values in decreasing order
    eigenvalues <- pmax(eig$values, 0)
    eigenvectors <- eig$vectors
  }
  a <- scale_factor * sqrt(max(eigenvalues[1], EIGENVALUE_FLOOR_KM2))
  b <- scale_factor * sqrt(max(eigenvalues[2], EIGENVALUE_FLOOR_KM2))
  orientation <- (atan2(eigenvectors[2, 1], eigenvectors[1, 1]) * 180 / pi) %% 180
  list(n_member_cells = length(lon), centroid_lon_unweighted = lon0, centroid_lat_unweighted = lat0,
       eigenvalue_major_km2 = eigenvalues[1], eigenvalue_minor_km2 = eigenvalues[2],
       major_axis_km = 2 * a, minor_axis_km = 2 * b, area_km2 = pi * a * b, axis_ratio = b / a,
       orientation_east_ccw_deg = orientation, azimuth_north_cw_deg = azimuth_from_north(orientation),
       major_axis_east = cos(orientation * pi / 180), major_axis_north = sin(orientation * pi / 180))
}

# Local equirectangular projection to kilometres around (lon0, lat0).
project_local_km <- function(lon, lat, lon0, lat0) {
  cbind((lon - lon0) * KM_PER_DEG_LON_EQUATOR * cos(lat0 * pi / 180),
        (lat - lat0) * KM_PER_DEG_LAT)
}

# Degrees clockwise from north in (-90, 90] from degrees counter-clockwise
# from east; an exact east-west axis is +90.
azimuth_from_north <- function(orientation_east_ccw) {
  out <- ((90 - orientation_east_ccw + 90) %% 180) - 90
  ifelse(out <= -90, out + 180, out)
}

# Round to single precision (the precision of the study's centroid weights).
as_single_precision <- function(x) {
  readBin(writeBin(as.numeric(x), raw(), size = 4L), "double", n = length(x), size = 4L)
}
