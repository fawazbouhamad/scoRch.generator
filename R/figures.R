# Result maps and their shared drawing helpers.

#' Draw one result visualization
#'
#' Redraws a visualization from the results of [run_scorch()], on the current
#' graphics device or into a PNG file.
#'
#' @param result The list returned by [run_scorch()].
#' @param name Descriptive visualization name, such as
#'   `"annual_event_counts_and_duration"`.
#' @param file Optional PNG file to write. When `NULL`, the figure is drawn on
#'   the current device.
#' @param dpi Resolution of the PNG file.
#' @param number Legacy paper figure number (3 or 5-12), accepted for
#'   compatibility. Use `name` for new code.
#' @return `TRUE` (invisibly) when the visualization was drawn, `FALSE` when the
#'   results do not contain what it needs (a message says why).
#' @examples
#' \donttest{
#' old <- setwd(tempdir())
#' result <- run_scorch(scorch_template("scorch_config.yaml", fast = TRUE, overwrite = TRUE))
#' scorch_figure(result, "annual_event_counts_and_duration")
#' setwd(old)
#' }
#' @export
scorch_figure <- function(result, name = NULL, file = NULL, dpi = 300, number = NULL) {
  if (!is.null(number)) {
    if (!is.null(name)) fail("Use either `name` or the legacy `number`, not both.")
    name <- number
  }
  id <- as.character(name)
  if (length(id) != 1L || is.na(id)) fail("Choose one visualization name from: ",
                                        paste(names(figure_specs()), collapse = ", "), ".")
  aliases <- figure_number_aliases()
  if (id %in% names(aliases)) id <- unname(aliases[[id]])
  spec <- figure_specs()[[id]]
  if (is.null(spec)) fail("There is no visualization named '", id,
                          "'; choose one of: ", paste(names(figure_specs()), collapse = ", "), ".")
  size <- spec$size(result)
  if (!is.null(file)) {
    # Draw beside the requested file. A skipped or failed plot must not leave
    # a blank or partial PNG, or replace a plot from an earlier successful run.
    temporary <- tempfile(".scorch-plot-", tmpdir = dirname(file), fileext = ".png")
    grDevices::png(temporary, width = size[1], height = size[2], units = "in", res = dpi)
    device_open <- TRUE
    on.exit({
      if (device_open) grDevices::dev.off()
      if (file.exists(temporary)) unlink(temporary)
    }, add = TRUE)
    drawn <- spec$draw(result)
    grDevices::dev.off()
    device_open <- FALSE
    if (!isTRUE(drawn)) return(invisible(FALSE))
    if (!isTRUE(file.copy(temporary, file, overwrite = TRUE))) {
      fail("Could not write the plot to ", file, ".")
    }
    return(invisible(TRUE))
  }
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  tryCatch(invisible(spec$draw(result)), error = function(e) {
    if (grepl("margins too large|plot region", conditionMessage(e))) {
      fail(sprintf("The graphics device is too small for %s; write it with `file = ` or open a device of about %.1f x %.1f inches.",
                   id, size[1], size[2]))
    }
    stop(e)
  })
}

figure_number_aliases <- function() c(
  "3" = "ellipse_spatial_patterns",
  "5" = "single_day_events",
  "6" = "consistent_multiday_events",
  "7" = "mixed_multiday_events",
  "8" = "ellipse_geometry_by_type",
  "9" = "event_geometry_distributions",
  "10" = "annual_event_counts_and_duration",
  "11" = "ellipse_area_power_law",
  "12" = "centroid_concentration"
)

figure_specs <- function() {
  map_size <- function(width, rows, cols, heading = 0, legend = 0) function(result) {
    c(cols * (width + MAP_MAI[2] + MAP_MAI[4]),
      rows * (width * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3]) + heading + legend)
  }
  list(
    "ellipse_spatial_patterns" = list(draw = draw_ellipse_spatial_patterns, size = function(result) c(2 * (5.2 + MAP_MAI[2] + MAP_MAI[4]) + 2 * CBAR_WIDTH, 3 * (5.2 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3]))),
    "single_day_events" = list(draw = draw_single_day_events, size = map_size(5.3, 1, 2, heading = 0.7, legend = 0.5)),
    "consistent_multiday_events" = list(draw = draw_consistent_multiday_events, size = map_size(4.6, 2, 2, heading = 0.9, legend = 0.5)),
    "mixed_multiday_events" = list(draw = draw_mixed_multiday_events, size = map_size(4.4, 2, 3, heading = 0.9, legend = 0.5)),
    "ellipse_geometry_by_type" = list(draw = draw_ellipse_geometry_by_type, size = function(result) c(12.2, 9.8)),
    "event_geometry_distributions" = list(draw = draw_event_geometry_distributions, size = function(result) c(13.5, 4.8)),
    "annual_event_counts_and_duration" = list(draw = draw_annual_event_counts_and_duration, size = function(result) c(9.4, 6.5)),
    "ellipse_area_power_law" = list(draw = draw_ellipse_area_power_law, size = function(result) c(10, 8.4)),
    "centroid_concentration" = list(draw = draw_centroid_concentration, size = function(result) c(6.4 + MAP_MAI[2] + MAP_MAI[4] + CBAR_WIDTH, 6.4 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3] + 0.5)))
}

# Shared map style --------------------------------------------------------

MAP_MAI <- c(0.4, 0.5, 0.35, 0.1)   # map panel margins in inches (bottom, left, top, right)
CBAR_WIDTH <- 0.9                   # width of a colour-bar column in inches
HEAT_PALETTE <- grDevices::colorRampPalette(c("#2ca25f", "#f7fcb9", "#f03b20"))

# Map extent: the grid cells plus half a step on every side.
map_extent <- function(result) {
  g <- result$input$grid
  c(min(g$lon) - g$lon_step / 2, max(g$lon) + g$lon_step / 2,
    min(g$lat) - g$lat_step / 2, max(g$lat) + g$lat_step / 2)
}

extent_ratio <- function(result) {
  e <- map_extent(result)
  (e[4] - e[3]) / (e[2] - e[1])
}

# An empty map frame with ocean, land, lakes, borders and degree axes.
map_frame <- function(extent, cex_axis = 0.75, mai = MAP_MAI) {
  graphics::par(mai = mai, xpd = FALSE)
  graphics::plot(NA, xlim = extent[1:2], ylim = extent[3:4], asp = 1, xaxs = "i", yaxs = "i",
                 axes = FALSE, xlab = "", ylab = "")
  usr <- graphics::par("usr")
  graphics::rect(usr[1], usr[3], usr[2], usr[4], col = "#dcecf2", border = NA)
  map_layer("world", usr, fill = TRUE, col = "#f8f6ef", border = NA)
  map_layer("lakes", usr, fill = TRUE, col = "#eaf3f7", border = NA)
  map_outlines(usr)
  degree_axes(usr, cex_axis)
  graphics::box(lwd = 0.8)
  invisible(usr)
}

map_outlines <- function(usr) {
  map_layer("world", usr, col = "grey35", lwd = 0.45)
}

# A Natural Earth layer of the maps package, skipped when nothing of it lies
# inside the map (an all-sea or lake-free region). Longitudes beyond 180 E
# use the 0-360 world map; it has no lakes layer.
map_layer <- function(database, usr, ...) {
  if (usr[2] > 180) {
    if (database == "lakes") return(invisible())
    database <- "world2"
  }
  try(suppressWarnings(maps::map(database, xlim = usr[1:2], ylim = usr[3:4], add = TRUE, ...)),
      silent = TRUE)
  invisible()
}

# Class index of every value for intervals closed on the left, [b_i, b_i+1),
# with the last interval closed on both sides, as matplotlib's BoundaryNorm.
# Drawn with image(), whose own intervals would be closed on the right.
class_image <- function(x, y, z, breaks, colours) {
  index <- findInterval(z, breaks, rightmost.closed = TRUE)
  index[index < 1 | index > length(colours)] <- NA
  dim(index) <- dim(z)
  graphics::image(x, y, index, col = colours, breaks = seq(0.5, length(colours) + 0.5), add = TRUE)
}

degree_axes <- function(usr, cex = 0.75) {
  lon_at <- pretty(usr[1:2], n = 5)
  lat_at <- pretty(usr[3:4], n = 5)
  graphics::axis(1, at = lon_at, labels = paste0(abs(lon_at), "\u00b0", ifelse(lon_at < 0, "W", "E")),
                 cex.axis = cex, mgp = c(2, 0.4, 0), tck = -0.015)
  graphics::axis(2, at = lat_at, labels = paste0(abs(lat_at), "\u00b0", ifelse(lat_at < 0, "S", "N")),
                 cex.axis = cex, mgp = c(2, 0.5, 0), tck = -0.015, las = 1)
}

# Panel letter above the top-left corner of the current plot.
panel_label <- function(text, cex = 1.4) {
  graphics::mtext(text, side = 3, adj = 0.5, line = 0.4, font = 2, cex = cex)
}

# Vertical colour bar in its own layout cell. `breaks` are the class limits
# (length(colours) + 1), drawn with equal heights; `ticks` are the values to
# label (the breaks by default, or a few round values of a continuous scale).
colour_bar <- function(breaks, colours, label, ticks = breaks, tick_labels = formatC(ticks, format = "fg", digits = 4),
                       mai = MAP_MAI, cex = 0.7) {
  graphics::par(mai = c(mai[1], 0.1, mai[3], CBAR_WIDTH - 0.3))
  n <- length(colours)
  graphics::image(x = c(0, 1), y = 0:n, z = matrix(seq_len(n), 1, n), col = colours,
                  axes = FALSE, xlab = "", ylab = "")
  graphics::box(lwd = 0.6)
  graphics::axis(4, at = stats::approx(breaks, 0:n, ticks)$y, labels = tick_labels, las = 1,
                 cex.axis = cex, mgp = c(2, 0.4, 0), tck = -0.15)
  graphics::mtext(label, side = 4, line = 2.6, cex = 0.8)
}

# Equal-width classes between two limits.
continuous_breaks <- function(limits, n = 64) seq(limits[1], limits[2], length.out = n + 1)

# Round tick values inside a continuous scale.
round_ticks <- function(breaks, n = 6) {
  ticks <- pretty(range(breaks), n)
  ticks[ticks >= min(breaks) & ticks <= max(breaks)]
}

colour_of <- function(values, breaks, colours) {
  colours[pmin(pmax(findInterval(values, breaks, all.inside = TRUE), 1), length(colours))]
}

# Colour limits clipped to the 2nd and 98th percentiles.
robust_limits <- function(values) {
  limits <- stats::quantile(values, c(0.02, 0.98), names = FALSE, type = 7)
  if (diff(limits) < 1e-12) limits[2] <- limits[1] + 1
  limits
}

# Ellipse outline and axis end points in degrees around the weighted centroid.
ellipse_outline <- function(e, n = 240) {
  t <- seq(0, 2 * pi, length.out = n)
  a <- e$major_axis_km / 2
  b <- e$minor_axis_km / 2
  u <- c(e$major_axis_east, e$major_axis_north)
  v <- c(-e$major_axis_north, e$major_axis_east)
  x <- a * cos(t) * u[1] + b * sin(t) * v[1]
  y <- a * cos(t) * u[2] + b * sin(t) * v[2]
  km_to_lonlat(e$centroid_lon_weighted, e$centroid_lat_weighted, x, y)
}

ellipse_axes <- function(e) {
  a <- e$major_axis_km / 2
  b <- e$minor_axis_km / 2
  major <- km_to_lonlat(e$centroid_lon_weighted, e$centroid_lat_weighted,
                        c(-a, a) * e$major_axis_east, c(-a, a) * e$major_axis_north)
  minor <- km_to_lonlat(e$centroid_lon_weighted, e$centroid_lat_weighted,
                        c(b, -b) * e$major_axis_north, c(-b, b) * e$major_axis_east)
  list(major = major, minor = minor)
}

km_to_lonlat <- function(lon0, lat0, x_km, y_km) {
  cbind(lon0 + x_km / (KM_PER_DEG_LON_EQUATOR * cos(lat0 * pi / 180)), lat0 + y_km / KM_PER_DEG_LAT)
}

# Maps of all ellipses ------------------------------------------------------

draw_ellipse_spatial_patterns <- function(result) {
  e <- result$ellipses
  extent <- map_extent(result)
  graphics::layout(matrix(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 0), 3, 4, byrow = TRUE),
                   widths = c(5.2 + MAP_MAI[2] + MAP_MAI[4], CBAR_WIDTH, 5.2 + MAP_MAI[2] + MAP_MAI[4], CBAR_WIDTH))
  # (a) centroids with their L1 and L2 axes
  map_frame(extent)
  axes <- lapply(seq_len(nrow(e)), function(i) ellipse_axes(e[i, ]))
  for (ax in axes) {
    graphics::lines(ax$major, col = grDevices::adjustcolor("red", 0.18), lwd = 0.75)
    graphics::lines(ax$minor, col = grDevices::adjustcolor("darkorange", 0.18), lwd = 0.75)
  }
  graphics::points(e$centroid_lon_weighted, e$centroid_lat_weighted, pch = 16, cex = 0.5,
                   col = grDevices::adjustcolor("black", 0.55))
  graphics::legend("bottomleft", inset = 0.01, legend = c(expression(L[1]), expression(L[2]), "Centroid"),
                   col = c("red", "darkorange", "black"), lty = c(1, 1, NA), pch = c(NA, NA, 16),
                   lwd = 2, horiz = TRUE, bg = "white", cex = 0.75, box.lwd = 0.6)
  panel_label("(a)")
  graphics::plot.new()
  # (b) ellipse footprints per point of a fine grid, in quantile classes
  g <- result$input$grid
  step <- min(g$lon_step, g$lat_step) / 4
  fine_lon <- seq(extent[1], extent[2], by = step)
  fine_lat <- seq(extent[3], extent[4], by = step)
  counts <- ellipse_footprints(e, fine_lon, fine_lat)
  levels <- unique(c(0, stats::quantile(counts, c(0.2, 0.4, 0.6, 0.8, 0.9, 0.95, 0.98, 1), names = FALSE)))
  colours <- HEAT_PALETTE(length(levels) - 1)
  usr <- map_frame(extent)
  class_image(fine_lon, fine_lat, counts, levels, grDevices::adjustcolor(colours, 0.78))
  map_outlines(usr)
  graphics::box()
  panel_label("(b)")
  colour_bar(levels, colours, "Ellipse footprints per grid point", tick_labels = formatC(levels, format = "fg", digits = 3))
  # (c) axis ratio, (d) area, (e) orientation of the major axis
  scatter_map <- function(values, breaks, colours, label, letter) {
    map_frame(extent)
    graphics::points(e$centroid_lon_weighted, e$centroid_lat_weighted, pch = 16, cex = 0.9,
                     col = grDevices::adjustcolor(colour_of(values, breaks, colours), 0.72))
    panel_label(letter)
    colour_bar(breaks, colours, label, ticks = round_ticks(breaks))
  }
  scatter_map(e$axis_ratio, continuous_breaks(robust_limits(e$axis_ratio)),
              grDevices::hcl.colors(64, "viridis", rev = TRUE), expression(L[2] / L[1]), "(c)")
  scatter_map(e$area_km2 / 1e6, continuous_breaks(robust_limits(e$area_km2 / 1e6)),
              grDevices::hcl.colors(64, "Plasma"), expression(Area ~ (km^2 %*% 10^6)), "(d)")
  scatter_map(e$azimuth_north_cw_deg, continuous_breaks(c(-90, 90)),
              grDevices::hcl.colors(64, "RdYlBu", rev = TRUE), expression(L[1] ~ orientation ~ (degree)), "(e)")
  invisible(TRUE)
}

# Number of ellipses covering every point of a longitude-latitude grid.
ellipse_footprints <- function(e, lon, lat) {
  grid <- expand.grid(lon = lon, lat = lat)
  counts <- numeric(nrow(grid))
  for (i in seq_len(nrow(e))) {
    lon0 <- e$centroid_lon_weighted[i]
    lat0 <- e$centroid_lat_weighted[i]
    dx <- (grid$lon - lon0) * KM_PER_DEG_LON_EQUATOR * cos(lat0 * pi / 180)
    dy <- (grid$lat - lat0) * KM_PER_DEG_LAT
    x1 <- dx * e$major_axis_east[i] + dy * e$major_axis_north[i]
    x2 <- -dx * e$major_axis_north[i] + dy * e$major_axis_east[i]
    counts <- counts + ((x1 / (e$major_axis_km[i] / 2))^2 + (x2 / (e$minor_axis_km[i] / 2))^2 <= 1)
  }
  matrix(counts, length(lon), length(lat))
}

# Representative event plots -------------------------------------------------

# Dates to show for one type, as a list with one date vector per event: the
# longest event of the type (ties: larger largest ellipse, then earlier
# start), unless the config names an event. Types 1 and 2 show one day, Type
# 3 the first two days of up to two events, Type 4 the six consecutive days
# with the most ellipses (or the six days from the configured date).
representative_events <- function(result, type) {
  events <- result$events$events
  days <- result$events$event_days
  n_events <- c(1, 1, 2, 1)[type]
  n_days <- c(1, 1, 2, 6)[type]
  event_dates <- function(id) days$date[days$compound_event_id == id]
  override <- result$config$figures$representative_events[[paste0("type_", type)]]
  if (!is.null(override)) {
    starts <- as.Date(as.character(override))
    event_ids <- vapply(starts, function(start) {
      hit <- events$compound_event_id[events$start_date <= start & events$end_date >= start]
      if (!length(hit) || events$event_type[hit] != type) {
        fail(sprintf("The date %s given for a representative Type %d event is not inside a Type %d event.",
                     format(start), type, type))
      }
      hit
    }, integer(1))
    if (anyDuplicated(event_ids)) {
      fail(sprintf("Choose dates from different Type %d events for the representative plots.", type))
    }
    return(Map(function(start, hit) {
      dates <- event_dates(hit)
      dates <- dates[dates >= start]
      if (type == 3 && length(dates) < 2) {
        fail(sprintf("The date %s is the last day of its Type 3 event; give an earlier day so that two days can be shown.",
                     format(start)))
      }
      utils::head(dates, n_days)
    }, starts, event_ids))
  }
  sub <- events[events$event_type == type, ]
  sub <- sub[order(-sub$duration_days, -sub$largest_ellipse_area_km2, sub$start_date), ]
  lapply(utils::head(sub$compound_event_id, n_events), function(id) {
    dates <- event_dates(id)
    if (type != 4 || length(dates) <= n_days) return(utils::head(dates, n_days))
    n_clusters <- days$n_clusters[days$compound_event_id == id]
    windows <- vapply(seq_len(length(dates) - n_days + 1), function(i) sum(n_clusters[i:(i + n_days - 1)]), 0)
    first <- which.max(windows)
    dates[first:(first + n_days - 1)]
  })
}

# One day of an event: heatwave cells, cluster ellipses and centroids.
draw_snapshot <- function(result, date) {
  extent <- map_extent(result)
  g <- result$input$grid
  cells <- result$clusters$cluster_cells
  cells <- cells[cells$date == date, ]
  e <- result$ellipses[result$ellipses$date == date, ]
  usr <- map_frame(extent, cex_axis = 0.65, mai = c(0.3, 0.45, 0.3, 0.1))
  draw_cells <- function(c, colour, alpha, lwd) {
    graphics::rect(c$lon - g$lon_step / 2, c$lat - g$lat_step / 2, c$lon + g$lon_step / 2, c$lat + g$lat_step / 2,
                   col = grDevices::adjustcolor(colour, alpha), border = "black", lwd = lwd)
  }
  draw_cells(cells[cells$dbscan_label == NOISE_LABEL, ], "grey55", 0.7, 0.2)
  draw_cells(cells[cells$dbscan_label != NOISE_LABEL, ], "orange", 0.92, 0.24)
  map_outlines(usr)
  for (i in seq_len(nrow(e))) {
    graphics::lines(ellipse_outline(e[i, ]), lwd = 2, col = "black")
    ax <- ellipse_axes(e[i, ])
    graphics::lines(ax$major, lwd = 2.4)
    graphics::lines(ax$minor, lwd = 1.5)
  }
  graphics::points(e$centroid_lon_weighted, e$centroid_lat_weighted, pch = 21, bg = "black", cex = 1.3)
  graphics::box()
  graphics::legend("bottomright", legend = format(date), bty = "n", text.font = 2, cex = 1.1,
                   inset = c(0.01, 0.01), bg = "white")
}

snapshot_legend <- function() {
  graphics::par(mai = c(0.05, 0.2, 0.05, 0.2))
  graphics::plot.new()
  graphics::legend("center", legend = c(expression(L[1]), expression(L[2]), "Centroid"),
                   lwd = c(2.4, 1.5, NA), pch = c(NA, NA, 16), col = "black", horiz = TRUE,
                   pt.cex = 1.4, box.lwd = 0.8, cex = 1.1, x.intersp = 1.2)
}

type_heading <- function(type, cex = 2.4) {
  graphics::par(mai = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::text(0.5, 0.5, paste("Type", type), col = TYPE_COLOURS[type], font = 2, cex = cex)
}

time_label <- function(text, cex = 1.2) {
  graphics::mtext(text, side = 3, line = 0.4, font = 2, cex = cex)
}

draw_single_day_events <- function(result) {
  shown <- list(representative_events(result, 1), representative_events(result, 2))
  types <- c(1, 2)[lengths(shown) > 0]
  if (!length(types)) {
    message("Single-day events visualization skipped: there is no Type 1 or Type 2 event.")
    return(FALSE)
  }
  n <- length(types)
  graphics::layout(matrix(c(seq_len(n), n + seq_len(n), rep(2 * n + 1, n)), 3, n, byrow = TRUE),
                   heights = c(0.7, 5.3 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3], 0.5))
  for (t in types) type_heading(t, cex = 2.2)
  for (t in types) draw_snapshot(result, shown[[t]][[1]][1])
  snapshot_legend()
  invisible(TRUE)
}

draw_consistent_multiday_events <- function(result) {
  shown <- representative_events(result, 3)
  shown <- shown[lengths(shown) >= 2]
  if (!length(shown)) {
    message("Consistent multiday events visualization skipped: there is no Type 3 event.")
    return(FALSE)
  }
  n <- length(shown)
  panel_height <- 4.6 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3]
  graphics::layout(rbind(c(1, 1), matrix(1 + seq_len(2 * n), n, 2, byrow = TRUE), c(2 * n + 2, 2 * n + 2)),
                   heights = c(0.9, rep(panel_height, n), 0.5))
  type_heading(3)
  for (k in seq_len(n)) {
    for (j in 1:2) {
      draw_snapshot(result, shown[[k]][j])
      if (k == 1) time_label(if (j == 1) "t" else "t + 1")
      if (j == 1) graphics::mtext(sprintf("(%s)", letters[k]), side = 3, adj = 0, line = 0.4, font = 2, cex = 1.3)
    }
  }
  snapshot_legend()
  invisible(TRUE)
}

draw_mixed_multiday_events <- function(result) {
  shown <- representative_events(result, 4)
  if (!length(shown)) {
    message("Mixed multiday events visualization skipped: there is no Type 4 event.")
    return(FALSE)
  }
  dates <- shown[[1]]
  n <- length(dates)
  cols <- min(3, n)
  rows <- ceiling(n / cols)
  panel_height <- 4.4 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3]
  cells <- c(1 + seq_len(n), rep(0, rows * cols - n))
  graphics::layout(rbind(rep(1, cols), matrix(cells, rows, cols, byrow = TRUE), rep(n + 2, cols)),
                   heights = c(0.9, rep(panel_height, rows), 0.5))
  type_heading(4)
  for (k in seq_len(n)) {
    draw_snapshot(result, dates[k])
    time_label(if (k == 1) "t" else sprintf("t + %d", k - 1))
  }
  snapshot_legend()
  invisible(TRUE)
}

# LGCP concentration rank and centroids -------------------------------------

draw_centroid_concentration <- function(result) {
  lgcp <- result$lgcp
  if (is.null(lgcp)) {
    message("Centroid concentration visualization skipped: the LGCP was not fitted.")
    return(FALSE)
  }
  extent <- map_extent(result)
  g <- result$input$grid
  graphics::layout(matrix(c(1, 2, 3, 3), 2, 2, byrow = TRUE),
                   widths = c(6.4 + MAP_MAI[2] + MAP_MAI[4], CBAR_WIDTH),
                   heights = c(6.4 * extent_ratio(result) + MAP_MAI[1] + MAP_MAI[3], 0.5))
  z <- matrix(NA_real_, length(g$lon), length(g$lat))
  z[cbind(match(lgcp$cells$lon, g$lon), match(lgcp$cells$lat, g$lat))] <- lgcp$cells$concentration_rank
  breaks <- seq(0, 1, by = 0.1)
  colours <- HEAT_PALETTE(10)
  usr <- map_frame(extent)
  class_image(g$lon, g$lat, z, breaks, grDevices::adjustcolor(colours, 0.78))
  map_outlines(usr)
  m <- lgcp$centroids
  graphics::points(m$centroid_lon, m$centroid_lat, pch = 16, cex = 0.55, col = grDevices::adjustcolor("black", 0.55))
  graphics::points(m$centroid_lon[m$is_daily_largest], m$centroid_lat[m$is_daily_largest], pch = 1, cex = 1.3,
                   lwd = 0.9, col = grDevices::adjustcolor("black", 0.85))
  graphics::points(m$centroid_lon[m$is_event_largest], m$centroid_lat[m$is_event_largest], pch = 4, cex = 1.3,
                   lwd = 3.2, col = "white")
  graphics::points(m$centroid_lon[m$is_event_largest], m$centroid_lat[m$is_event_largest], pch = 4, cex = 1.2,
                   lwd = 1.6, col = "#b2182b")
  graphics::box()
  colour_bar(breaks, colours, "Relative centroid-concentration rank, R(s)", tick_labels = format(breaks))
  graphics::par(mai = c(0.05, 0.2, 0.05, 0.2))
  graphics::plot.new()
  graphics::legend("center", legend = c("Centroid", "Daily-largest structure centroid", "Event-largest structure centroid"),
                   pch = c(16, 1, 4), col = c("black", "black", "#b2182b"), pt.cex = c(0.8, 1.4, 1.2),
                   pt.lwd = c(1, 1, 1.6), horiz = TRUE, box.lwd = 0.8, cex = 0.85)
  invisible(TRUE)
}
