# Log-Gaussian Cox process of the ellipse centroids.

#' Fit a log-Gaussian Cox process to the ellipse centroids
#'
#' The temperature-weighted centroids of all ellipses form a point pattern in
#' a Lambert azimuthal equal-area projection (WGS84) centred on the grid. The
#' study window is the set of `raster_km` pixels whose centre lies within
#' `raster_km + window_margin_km` of a grid-cell centre. The intensity trend
#' is log-linear in the chosen covariates: the pixel's longitude and latitude
#' and the nearest cell's mean and (population) standard deviation of Tmax
#' over the analysed dates. The model is fitted by minimum contrast of the K
#' function with an exponential covariance (`spatstat.model::kppm`). The
#' mean intensity at every grid cell is converted to a relative concentration
#' rank between 0 and 1, and the share of centroids inside the cells that
#' cover the top 20% and 50% of the area with the highest intensity is
#' reported for all centroids, the daily-largest centroids and the
#' event-largest centroids.
#'
#' @param events A `scorch_events` object from [classify_events()].
#' @param tmax The `scorch_tmax` object the events were derived from.
#' @param covariates Trend covariates, a subset of `"lon"`, `"lat"`,
#'   `"mean_tmax"` and `"std_tmax"`.
#' @param raster_km Pixel size of the covariate images and study window (km).
#' @param window_margin_km Distance beyond the nearest grid-cell centre (plus
#'   one pixel) that still counts as inside the study window (km). The study
#'   value of 80 km suits 1-degree cells; about three quarters of the cell
#'   size in km suits other grids.
#' @return A `scorch_lgcp` object: a list with `parameters` (trend
#'   coefficients, Gaussian-field variance and correlation scale in km),
#'   `cells` (mean intensity and concentration rank of every grid cell),
#'   `centroids` (projected centroids with their nearest cell and
#'   daily-largest and event-largest flags), `concentration` (zone shares),
#'   `diagnostics`, `warnings` and the fitted `kppm` model.
#' @examples
#' \donttest{
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file)
#' clusters <- cluster_heatwaves(select_regional_days(detect_heatwaves(tmax)))
#' events <- classify_events(clusters, fit_ellipses(clusters, tmax))
#' lgcp <- fit_lgcp(events, tmax)
#' lgcp$parameters
#' }
#' @export
fit_lgcp <- function(events, tmax, covariates = c("lon", "lat", "mean_tmax", "std_tmax"),
                     raster_km = 25, window_margin_km = 80) {
  if (!inherits(events, "scorch_events")) fail("`events` must come from classify_events().")
  if (!inherits(tmax, "scorch_tmax")) fail("`tmax` must come from read_tmax() or tmax_from_array().")
  known <- c("lon", "lat", "mean_tmax", "std_tmax")
  if (!length(covariates) || !all(covariates %in% known) || anyDuplicated(covariates)) {
    fail("The LGCP covariates must be distinct names from: ", paste(known, collapse = ", "), ".")
  }
  check_number(raster_km, "raster_km", lower = 1e-6)
  check_number(window_margin_km, "window_margin_km", lower = 0)
  if (nrow(events$ellipses) < 5) {
    fail(sprintf("The LGCP needs more centroids than the %d available.", nrow(events$ellipses)))
  }

  # 1. Temperature covariates of the grid cells.
  values <- tmax$tmax
  cells <- tmax$cells
  cells$mean_tmax <- colMeans(values)
  cells$std_tmax <- sqrt(pmax(0, colMeans(values^2) - cells$mean_tmax^2))
  # 2. Equal-area projection centred on the grid.
  lon0 <- (min(cells$lon) + max(cells$lon)) / 2
  lat0 <- (min(cells$lat) + max(cells$lat)) / 2
  xy <- laea_forward(cells$lon, cells$lat, lon0, lat0)
  cells$x_km <- xy[, 1]
  cells$y_km <- xy[, 2]
  # 3. Centroids and their nearest cell.
  e <- events$ellipses
  xy <- laea_forward(e$centroid_lon_weighted, e$centroid_lat_weighted, lon0, lat0)
  nearest <- dbscan::kNN(cells[, c("x_km", "y_km")], k = 1, query = xy)
  centroids <- data.frame(
    ellipse_id = e$ellipse_id, compound_event_id = e$compound_event_id, date = e$date,
    event_type = e$event_type, centroid_lon = e$centroid_lon_weighted,
    centroid_lat = e$centroid_lat_weighted, x_km = xy[, 1], y_km = xy[, 2],
    nearest_cell_id = cells$cell_id[nearest$id[, 1]], nearest_cell_distance_km = nearest$dist[, 1],
    is_daily_largest = e$ellipse_id %in% events$event_days$largest_ellipse_id,
    is_event_largest = e$ellipse_id %in% events$events$largest_ellipse_id)
  # 4. Pixel raster, study window and covariate images.
  inside_km <- raster_km + window_margin_km
  if (any(centroids$nearest_cell_distance_km > inside_km)) {
    fail("A centroid lies outside the study window; increase 'window_margin_km'.")
  }
  pixel_x <- pixel_centres(min(cells$x_km) - raster_km, max(cells$x_km) + raster_km, raster_km)
  pixel_y <- pixel_centres(min(cells$y_km) - raster_km, max(cells$y_km) + raster_km, raster_km)
  pixels <- expand.grid(x_km = pixel_x, y_km = pixel_y)      # x varies fastest
  nearest <- dbscan::kNN(cells[, c("x_km", "y_km")], k = 1, query = pixels)
  inside <- nearest$dist[, 1] <= inside_km
  # The pixel that holds a centroid always belongs to the window.
  centroid_pixel <- (findInterval(xy[, 2], pixel_y - raster_km / 2) - 1) * length(pixel_x) +
    findInterval(xy[, 1], pixel_x - raster_km / 2)
  inside[centroid_pixel] <- TRUE
  lonlat <- laea_inverse(pixels$x_km, pixels$y_km, lon0, lat0)
  pixel_values <- list(lon = lonlat[, 1], lat = lonlat[, 2],
                       mean_tmax = cells$mean_tmax[nearest$id[, 1]],
                       std_tmax = cells$std_tmax[nearest$id[, 1]])
  as_image <- function(v) {
    v[!inside] <- NA
    spatstat.geom::im(matrix(v, nrow = length(pixel_y), ncol = length(pixel_x), byrow = TRUE),
                      xcol = pixel_x, yrow = pixel_y)
  }
  images <- lapply(pixel_values[covariates], as_image)
  window <- spatstat.geom::as.owin(as_image(rep(1, nrow(pixels))))
  points <- spatstat.geom::ppp(centroids$x_km, centroids$y_km, window = window, checkdup = FALSE)
  if (points$n != nrow(centroids)) fail("Some centroids fall outside the study window.")
  # 5. Minimum-contrast fit.
  warnings_seen <- character()
  fit <- withCallingHandlers(
    spatstat.model::kppm(points, trend = stats::as.formula(paste("~", paste(covariates, collapse = " + "))),
                         clusters = "LGCP", method = "mincon", statistic = "K",
                         model = "exponential", covariates = images),
    warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  coefficients <- stats::coef(fit)
  parameters <- c(coefficients, var_sigma2 = as.numeric(fit$clustpar[["var"]]),
                  scale_km = as.numeric(fit$clustpar[["scale"]]))
  optimisation <- fit$Fit$mcfit$opt
  diagnostics <- list(mincon_convergence_code = as.integer(optimisation$convergence),
                      mincon_objective = as.numeric(optimisation$value),
                      trend_glm_converged = isTRUE(fit$po$internal$glmfit$converged))
  # 6. Mean intensity at the cells (the fitted trend already contains the
  # -sigma2/2 term of the LGCP) and its concentration rank.
  linear <- coefficients[["(Intercept)"]]
  for (term in covariates) linear <- linear + coefficients[[term]] * cells[[term]]
  cells$mean_intensity_per_km2 <- exp(linear)
  if (anyDuplicated(cells$mean_intensity_per_km2)) {
    message("Some cells have identical fitted intensities; their order in the concentration zones is arbitrary.")
  }
  cells$concentration_rank <- rank(cells$mean_intensity_per_km2, ties.method = "average") / nrow(cells)
  concentration <- concentration_zones(cells, centroids, tmax$grid, c(0.2, 0.5))
  structure(list(parameters = parameters,
                 parameter_table = data.frame(parameter = names(parameters), value = unname(parameters)),
                 cells = cells[, c("cell_id", "lon", "lat", "mean_tmax", "std_tmax",
                                   "mean_intensity_per_km2", "concentration_rank")],
                 centroids = centroids, concentration = concentration,
                 window = list(projection_centre_lon = lon0, projection_centre_lat = lat0,
                               pixel_km = raster_km, nx = length(pixel_x), ny = length(pixel_y),
                               n_pixels_inside = sum(inside), inside_rule_km = inside_km),
                 diagnostics = diagnostics, warnings = unique(warnings_seen), fit = fit,
                 settings = list(covariates = covariates, raster_km = raster_km,
                                 window_margin_km = window_margin_km)),
            class = "scorch_lgcp")
}

# Pixel centres from `first` to `last` in steps of `size`, as numpy's arange.
pixel_centres <- function(first, last, size) {
  start <- first + size / 2
  start + size * seq_len(ceiling((last - start) / size)) - size
}

# Share of centroids inside the cells that cover the highest-intensity
# fractions of the total area, for all, daily-largest and event-largest centroids.
concentration_zones <- function(cells, centroids, grid, fractions) {
  area <- KM_PER_DEG_LON_EQUATOR * cos(cells$lat * pi / 180) * grid$lon_step * KM_PER_DEG_LAT * grid$lat_step
  descending <- order(cells$mean_intensity_per_km2, decreasing = TRUE)
  share <- cumsum(area[descending]) / sum(area)
  cell_row <- match(centroids$nearest_cell_id, cells$cell_id)
  groups <- list(all_centroids = rep(TRUE, nrow(centroids)),
                 daily_largest = centroids$is_daily_largest,
                 event_largest = centroids$is_event_largest)
  do.call(rbind, lapply(fractions, function(fraction) {
    n_zone <- sum(share < fraction) + 1L
    in_zone <- seq_len(nrow(cells)) %in% descending[seq_len(n_zone)]
    do.call(rbind, lapply(names(groups), function(name) {
      rows <- cell_row[groups[[name]]]
      data.frame(zone_area_fraction = fraction, group = name, n_centroids_in_group = length(rows),
                 n_in_zone = sum(in_zone[rows]), percent_in_zone = 100 * mean(in_zone[rows]))
    }))
  }))
}

# Lambert azimuthal equal-area projection on the WGS84 ellipsoid (Snyder 1987,
# oblique aspect), in kilometres, centred on (lon0, lat0).
laea_constants <- function(lat0) {
  a <- 6378137
  f <- 1 / 298.257223563
  e2 <- 2 * f - f^2
  e <- sqrt(e2)
  q <- function(phi) {
    s <- sin(phi)
    (1 - e2) * (s / (1 - e2 * s^2) - log((1 - e * s) / (1 + e * s)) / (2 * e))
  }
  qp <- q(pi / 2)
  phi1 <- lat0 * pi / 180
  beta1 <- asin(q(phi1) / qp)
  rq <- a * sqrt(qp / 2)
  m1 <- cos(phi1) / sqrt(1 - e2 * sin(phi1)^2)
  list(e = e, e2 = e2, q = q, qp = qp, beta1 = beta1, rq = rq, d = a * m1 / (rq * cos(beta1)))
}

laea_forward <- function(lon, lat, lon0, lat0) {
  k <- laea_constants(lat0)
  beta <- asin(k$q(lat * pi / 180) / k$qp)
  dlon <- (lon - lon0) * pi / 180
  b <- k$rq * sqrt(2 / (1 + sin(k$beta1) * sin(beta) + cos(k$beta1) * cos(beta) * cos(dlon)))
  cbind(b * k$d * cos(beta) * sin(dlon),
        (b / k$d) * (cos(k$beta1) * sin(beta) - sin(k$beta1) * cos(beta) * cos(dlon))) / 1000
}

laea_inverse <- function(x_km, y_km, lon0, lat0) {
  k <- laea_constants(lat0)
  x <- x_km * 1000
  y <- y_km * 1000
  rho <- sqrt((x / k$d)^2 + (k$d * y)^2)
  ce <- 2 * asin(pmin(1, rho / (2 * k$rq)))
  at_centre <- rho == 0
  q <- k$qp * (cos(ce) * sin(k$beta1) + ifelse(at_centre, 0, k$d * y * sin(ce) * cos(k$beta1) / rho))
  lon <- lon0 + atan2(x * sin(ce), k$d * rho * cos(k$beta1) * cos(ce) - k$d^2 * y * sin(k$beta1) * sin(ce)) * 180 / pi
  phi <- asin(q / 2)
  for (i in 1:30) {
    s <- sin(phi)
    step <- (1 - k$e2 * s^2)^2 / (2 * cos(phi)) *
      (q / (1 - k$e2) - s / (1 - k$e2 * s^2) + log((1 - k$e * s) / (1 + k$e * s)) / (2 * k$e))
    phi <- phi + step
    if (max(abs(step)) < 1e-14) break
  }
  cbind(lon, phi * 180 / pi)
}
