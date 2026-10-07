# Ellipse statistics by type, event summaries, annual counts
# and durations, and the power-law fits.

type_label <- function(t) paste("Type", t)

clean_axes <- function(cex = 0.75) {
  graphics::box(bty = "l", lwd = 0.6)
  graphics::axis(1, cex.axis = cex, mgp = c(2, 0.4, 0), tck = -0.02, lwd = 0.6)
  graphics::axis(2, cex.axis = cex, mgp = c(2, 0.5, 0), tck = -0.02, lwd = 0.6, las = 1)
}

# Histograms and box plots of the ellipse geometry by type ------------------

draw_ellipse_geometry_by_type <- function(result) {
  e <- result$ellipses
  area <- e$area_km2 / 1e6
  area_range <- if (diff(range(area)) == 0) range(area) + c(-0.1, 0.1) else range(area)
  rows <- list(
    list(values = e$axis_ratio, breaks = seq(0, 1, 0.05), xlab = expression(Ratio ~ (L[2] / L[1])), xlim = c(0, 1)),
    list(values = area, breaks = seq(area_range[1], area_range[2], length.out = 13),
         xlab = expression(Area ~ (km^2 %*% 10^6)), xlim = area_range),
    list(values = e$azimuth_north_cw_deg, breaks = seq(-90, 90, 15), xlab = "Orientation (\u00b0)", xlim = c(-90, 90)))
  # Drawing order: histogram then box plot of every type, row by row.
  cells <- matrix(0, 6, 4)
  for (r in 1:3) for (t in 1:4) cells[2 * r - 1:0, t] <- 8 * (r - 1) + 2 * t - 1:0
  graphics::layout(cells, heights = rep(c(4.1, 1.3), 3))
  for (r in seq_along(rows)) {
    row <- rows[[r]]
    for (t in 1:4) {
      values <- row$values[e$event_type == t]
      graphics::par(mai = c(0.05, 0.55, if (r == 1) 0.4 else 0.25, 0.15))
      if (!length(values)) {
        graphics::plot.new()
        graphics::text(0.5, 0.5, "No data", cex = 0.9)
        if (r == 1) graphics::mtext(type_label(t), font = 2, col = TYPE_COLOURS[t], line = 0.6, cex = 0.95)
        graphics::par(mai = c(0.55, 0.55, 0.05, 0.15))
        graphics::plot.new()
        graphics::mtext(row$xlab, side = 1, line = 2.2, cex = 0.8)
        next
      }
      h <- graphics::hist(values, breaks = row$breaks, plot = FALSE)
      # Bins closed on the left, the last one on both sides (numpy's rule).
      h$counts <- tabulate(findInterval(values, row$breaks, rightmost.closed = TRUE), length(row$breaks) - 1)
      graphics::plot(h, col = grDevices::adjustcolor(TYPE_COLOURS[t], 0.9), border = "black", lwd = 0.35,
                     main = "", xlab = "", ylab = "", xlim = row$xlim, axes = FALSE)
      graphics::grid(nx = NA, ny = NULL, col = grDevices::adjustcolor("black", 0.15), lwd = 0.45)
      graphics::box(bty = "l", lwd = 0.6)
      at <- unique(round(pretty(c(0, max(h$counts)))))
      graphics::axis(2, at = at, cex.axis = 0.75, mgp = c(2, 0.5, 0), tck = -0.02, lwd = 0.6, las = 1)
      if (t == 1) graphics::mtext("Number of ellipses", side = 2, line = 2.2, cex = 0.8)
      if (r == 1) graphics::mtext(type_label(t), font = 2, col = TYPE_COLOURS[t], line = 0.6, cex = 0.95)
      if (t == 1) graphics::mtext(sprintf("(%s)", letters[r]), side = 3, adj = 0, line = 0.5, font = 2, cex = 1.2)
      graphics::legend("topright", legend = sprintf("n = %d\nMed = %.2f", length(values), stats::median(values)),
                       bty = "o", box.col = "grey60", bg = "white", cex = 0.7, box.lwd = 0.5)
      graphics::par(mai = c(0.55, 0.55, 0.05, 0.15))
      graphics::boxplot(values, horizontal = TRUE, ylim = row$xlim, axes = FALSE, col = "#E6E6E6",
                        border = "#404040", medcol = "#8B1E1E", medlwd = 1.4, outpch = 1, outcex = 0.5, lwd = 0.7)
      graphics::box(bty = "l", lwd = 0.6)
      graphics::axis(1, cex.axis = 0.75, mgp = c(2, 0.4, 0), tck = -0.05, lwd = 0.6)
      graphics::mtext(row$xlab, side = 1, line = 2.2, cex = 0.8)
    }
  }
  invisible(TRUE)
}

# Mean geometry of every compound event -------------------------------------

draw_event_geometry_distributions <- function(result) {
  events <- result$events$events
  graphics::layout(matrix(c(1, 2, 3, 4, 4, 4), 2, 3, byrow = TRUE), heights = c(1, 0.14))
  types_present <- sort(unique(events$event_type))
  draw_cdf <- function(values_by_type, xlab, letter) {
    values <- unlist(values_by_type)
    pad <- if (diff(range(values)) == 0) 0.05 else 0.035 * diff(range(values))
    xlim <- range(values) + c(-pad, pad)
    graphics::par(mai = c(0.7, 0.75, 0.5, 0.2))
    graphics::plot(NA, xlim = xlim, ylim = c(0, 1.02), xlab = "", ylab = "", axes = FALSE)
    graphics::grid(col = grDevices::adjustcolor("black", 0.2), lwd = 0.45)
    for (t in types_present) {
      v <- sort(values_by_type[[t]])
      graphics::lines(c(xlim[1], v, xlim[2]), c(0, seq_along(v) / length(v), 1), col = TYPE_COLOURS[t], lwd = 2.2)
    }
    clean_axes(0.8)
    graphics::mtext(xlab, side = 1, line = 2.2, cex = 0.9)
    graphics::mtext("Cumulative probability", side = 2, line = 2.6, cex = 0.9)
    panel_label(letter)
  }
  by_type <- function(column) lapply(1:4, function(t) events[[column]][events$event_type == t])
  draw_cdf(by_type("mean_axis_ratio"), expression(Ratio ~ (L[2] / L[1])), "(a)")
  draw_cdf(lapply(by_type("mean_area_km2"), function(v) v / 1e6), expression(Area ~ (km^2 %*% 10^6)), "(b)")
  # (c) kernel density of the axial mean orientation (Scott's bandwidth)
  x <- seq(-90, 90, length.out = 600)
  curves <- lapply(1:4, function(t) {
    v <- events$axial_mean_azimuth_deg[events$event_type == t]
    v <- v[is.finite(v)]
    if (length(v) < 2 || stats::sd(v) == 0) return(NULL)
    stats::density(v, bw = stats::sd(v) * length(v)^(-1 / 5), from = -90, to = 90, n = 600)$y
  })
  graphics::par(mai = c(0.7, 0.75, 0.5, 0.2))
  graphics::plot(NA, xlim = c(-90, 90), ylim = c(0, max(c(unlist(curves), 1e-3)) * 1.05), xlab = "", ylab = "", axes = FALSE)
  graphics::grid(col = grDevices::adjustcolor("black", 0.2), lwd = 0.45)
  graphics::abline(v = 0, col = "grey35", lty = 2, lwd = 0.75)
  for (t in types_present) {
    if (is.null(curves[[t]])) {
      v <- events$axial_mean_azimuth_deg[events$event_type == t]
      graphics::points(v, rep(0, length(v)), pch = 21, bg = TYPE_COLOURS[t], col = "white", cex = 1.1)
    } else {
      graphics::lines(x, curves[[t]], col = TYPE_COLOURS[t], lwd = 2.2)
    }
  }
  graphics::box(bty = "l", lwd = 0.6)
  graphics::axis(1, at = seq(-90, 90, 30), cex.axis = 0.8, mgp = c(2, 0.4, 0), tck = -0.02, lwd = 0.6)
  graphics::axis(2, cex.axis = 0.8, mgp = c(2, 0.5, 0), tck = -0.02, lwd = 0.6, las = 1)
  graphics::mtext("Orientation (\u00b0)", side = 1, line = 2.2, cex = 0.9)
  graphics::mtext("Probability density", side = 2, line = 3.2, cex = 0.9)
  panel_label("(c)")
  graphics::par(mai = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::legend("center", legend = type_label(types_present), col = TYPE_COLOURS[types_present], lwd = 2.2,
                   horiz = TRUE, bty = "n", cex = 1.05, x.intersp = 1.2)
  invisible(TRUE)
}

# Annual event counts and mean duration -------------------------------------

draw_annual_event_counts_and_duration <- function(result) {
  counts <- result$events$annual_counts
  duration <- result$events$annual_duration
  events <- result$events$events
  years <- counts$year
  xlim <- c(min(years) - 0.5, max(years) + 0.5)
  year_ticks <- pretty(years)
  year_ticks <- year_ticks[year_ticks == round(year_ticks)]
  if (length(year_ticks) < 2) year_ticks <- seq(min(years), max(years))
  graphics::layout(matrix(1:2, 2), heights = c(1, 1.15))
  # (a) events per year and type; years without events are left out
  graphics::par(mai = c(0.45, 0.8, 0.4, 0.3))
  with_events <- counts[counts$all_events > 0, ]
  graphics::plot(NA, xlim = xlim, ylim = c(0, max(counts$all_events) + 1), axes = FALSE, xlab = "", ylab = "")
  graphics::abline(h = seq_len(max(counts$all_events) + 1), col = grDevices::adjustcolor("black", 0.15), lty = 2, lwd = 0.45)
  for (i in seq_len(nrow(with_events))) {
    bottom <- 0
    for (t in 1:4) {
      n <- with_events[[paste0("type_", t, "_events")]][i]
      if (n > 0) {
        graphics::rect(with_events$year[i] - 0.36, bottom, with_events$year[i] + 0.36, bottom + n,
                       col = TYPE_COLOURS[t], border = "white", lwd = 0.45)
        bottom <- bottom + n
      }
    }
  }
  graphics::box(bty = "l", lwd = 0.75)
  graphics::axis(1, at = year_ticks, cex.axis = 0.85, mgp = c(2, 0.4, 0), tck = -0.02)
  graphics::axis(2, at = seq(0, max(counts$all_events) + 1), cex.axis = 0.85, las = 1, mgp = c(2, 0.5, 0), tck = -0.02)
  graphics::mtext("Number of events", side = 2, line = 2.4, cex = 0.9)
  graphics::legend("topleft", legend = type_label(1:4), fill = TYPE_COLOURS, border = NA, bty = "n", ncol = 2, cex = 0.8)
  graphics::mtext("(a)", side = 3, adj = 0, line = 0.3, font = 2, cex = 1.4)
  # (b) mean duration of Type 3 and Type 4 events by start year
  longest <- max(c(events$duration_days[events$event_type %in% 3:4], 1))
  graphics::par(mai = c(0.7, 0.8, 0.4, 0.3))
  graphics::plot(NA, xlim = range(years), ylim = c(0, longest + 4), axes = FALSE, xlab = "", ylab = "")
  graphics::abline(h = seq(0, longest + 4, 5), col = grDevices::adjustcolor("black", 0.12), lty = 2, lwd = 0.4)
  for (t in 3:4) {
    s <- duration[duration$event_type == t, ]
    if (nrow(s)) graphics::lines(s$year, s$mean_duration_days, col = TYPE_COLOURS[t], lwd = 2, type = "o", pch = 16, cex = 0.7)
  }
  graphics::box(bty = "l", lwd = 0.75)
  graphics::axis(1, at = year_ticks, cex.axis = 0.85, mgp = c(2, 0.4, 0), tck = -0.02)
  graphics::axis(2, at = seq(0, longest + 4, 5), cex.axis = 0.85, las = 1, mgp = c(2, 0.5, 0), tck = -0.02)
  graphics::mtext("Mean duration (days)", side = 2, line = 2.4, cex = 0.9)
  graphics::mtext("Year", side = 1, line = 2.2, cex = 0.9)
  graphics::legend("topleft", legend = type_label(3:4), col = TYPE_COLOURS[3:4], lwd = 2, pch = 16, bty = "n", ncol = 2, cex = 0.8)
  graphics::mtext("(b)", side = 3, adj = 0, line = 0.3, font = 2, cex = 1.4)
  invisible(TRUE)
}

# Power-law fits of the largest areas ---------------------------------------

draw_ellipse_area_power_law <- function(result) {
  pl <- result$power_law
  graphics::layout(matrix(1:4, 2, byrow = TRUE), widths = c(1.15, 1))
  letters_of <- list(daily_maxima = c("(a)", "(b)"), event_maxima = c("(c)", "(d)"))
  for (name in c("daily_maxima", "event_maxima")) {
    sample <- pl[[name]]
    areas <- sample$sample$area_km2
    fit <- sample$fit
    boot <- sample$bootstrap
    ok <- identical(fit$status, "ok") && !is.null(boot)
    # CCDF with the fitted tail
    graphics::par(mai = c(0.75, 0.85, 0.5, 0.2))
    x <- sort(areas)
    ccdf <- 1 - (seq_along(x) - 1) / length(x)
    graphics::plot(x, ccdf, log = "xy", pch = 16, cex = 0.55, col = grDevices::adjustcolor("black", 0.85),
                   axes = FALSE, xlab = "", ylab = "")
    graphics::grid(col = "grey90", lwd = 0.5)
    if (ok) {
      xt <- exp(seq(log(fit$xmin), log(max(x)), length.out = 200))
      graphics::lines(xt, (fit$n_tail / fit$n) * (xt / fit$xmin)^(1 - fit$alpha), col = "#b2182b", lwd = 2.2)
      graphics::abline(v = fit$xmin, lty = 2, lwd = 1.1)
      graphics::legend("bottomleft", bty = "n", cex = 0.85, legend = c(
        bquote(italic(n) == .(fit$n)), bquote(italic(n)[tail] == .(fit$n_tail)),
        bquote(alpha %~~% .(sprintf("%.2f", fit$alpha))), bquote(italic(p) %~~% .(sprintf("%.3f", boot$p)))))
      if (name == "daily_maxima") graphics::legend("topright", legend = expression(A[min]), lty = 2, bty = "n", cex = 0.9)
    } else {
      graphics::legend("bottomleft", bty = "n", cex = 0.85, legend = sprintf("no power-law fit (%d areas, %d distinct)",
                                                                             length(areas), length(unique(areas))))
    }
    graphics::box(bty = "l", lwd = 0.8)
    graphics::axis(1, cex.axis = 0.8, mgp = c(2, 0.5, 0), tck = -0.02)
    graphics::axis(2, cex.axis = 0.8, mgp = c(2, 0.5, 0), tck = -0.02, las = 1)
    graphics::mtext(expression(Area ~ (km^2)), side = 1, line = 2.4, cex = 0.9)
    graphics::mtext(expression(italic(P)(area >= italic(A))), side = 2, line = 3.4, cex = 0.9)
    panel_label(letters_of[[name]][1])
    # box plot of the bootstrap exponents (whiskers at the 2.5th and 97.5th percentiles)
    graphics::par(mai = c(0.75, 0.85, 0.5, 0.4))
    if (ok) {
      alpha <- boot$alpha_boot[!is.na(boot$alpha_boot)]
      stats <- stats::quantile(alpha, c(0.025, 0.25, 0.5, 0.75, 0.975), names = FALSE, type = 7)
      graphics::bxp(list(stats = matrix(stats, 5), n = length(alpha), names = ""), outline = FALSE,
                    boxfill = "#E6E6E6", boxcol = "grey35", whiskcol = "grey35", staplecol = "grey35",
                    medlwd = 1.6, whisklty = 1, axes = FALSE, boxwex = 0.45, ylim = range(stats) + c(-0.3, 0.3))
      graphics::grid(nx = NA, ny = NULL, col = "grey90", lwd = 0.5)
      graphics::box(bty = "l", lwd = 0.8)
      graphics::axis(2, cex.axis = 0.8, mgp = c(2, 0.5, 0), tck = -0.02, las = 1)
      graphics::mtext(expression(Bootstrap ~ alpha ~ estimate), side = 2, line = 2.8, cex = 0.9)
    } else {
      graphics::plot.new()
      graphics::text(0.5, 0.5, "no bootstrap", cex = 0.9)
    }
    panel_label(letters_of[[name]][2])
  }
  invisible(TRUE)
}
