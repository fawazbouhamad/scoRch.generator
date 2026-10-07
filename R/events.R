# Stage 5: compound heatwave events, their types and summaries (Catalog 5, Table 1).

#' Group consecutive selected days into compound events and classify them
#'
#' Selected days that follow each other in the calendar form one compound
#' heatwave event. The event type follows the number of clusters (ellipses) on
#' each of its days: Type 1, one day with one cluster; Type 2, one day with
#' several clusters; Type 3, several days with one cluster every day or
#' several clusters every day; Type 4, several days mixing one-cluster and
#' several-cluster days or containing a day without a cluster. A selected day
#' on which no cluster formed stays in its event but has no ellipse. A run of
#' days without any cluster is left out. Orientation summaries use the axial
#' mean (doubled angles), because axes 180 degrees apart are the same axis.
#'
#' @param clusters A `scorch_clusters` object from [cluster_heatwaves()].
#' @param ellipses Catalog 4 from [fit_ellipses()].
#' @return A `scorch_events` object: a list with `events` (Catalog 5),
#'   `event_days` (date, event and day-in-event), `ellipses` (Catalog 4 with
#'   the event and type of every ellipse appended), `table_1` (statistics by
#'   type), `annual_counts`, `annual_duration` (mean duration of Type 3 and
#'   Type 4 events by start year) and `trends` (trend tests on those series).
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file)
#' clusters <- cluster_heatwaves(select_regional_days(detect_heatwaves(tmax)))
#' events <- classify_events(clusters, fit_ellipses(clusters, tmax))
#' events$table_1
#' @export
classify_events <- function(clusters, ellipses) {
  if (!inherits(clusters, "scorch_clusters")) fail("`clusters` must come from cluster_heatwaves().")
  if (!is.data.frame(ellipses) || !all(c("ellipse_id", "cluster_id", "date", "area_km2", "axis_ratio", "azimuth_north_cw_deg") %in% names(ellipses)) ||
      !identical(ellipses$cluster_id, clusters$clusters$cluster_id)) {
    fail("`ellipses` must be the table returned by fit_ellipses() for these clusters.")
  }
  daily <- clusters$daily_settings
  if (!any(daily$n_clusters > 0)) {
    fail(paste("No selected day formed a cluster, so there are no compound events. The heatwave cells of",
               "the selected days are too scattered for the candidate DBSCAN settings; consider a larger",
               "region or smaller 'min_samples_values'."))
  }
  # Runs of consecutive selected days form the events. A selected day without
  # a cluster stays in its event and its zero count affects classification;
  # an event without any ellipse is left out.
  days <- daily$date
  event_of_day <- cumsum(c(TRUE, diff(days) > 1))
  with_ellipse <- (tapply(daily$n_clusters, event_of_day, sum) > 0)[event_of_day]
  if (!all(with_ellipse)) {
    message(sprintf("%d run(s) of selected days formed no cluster on any day and are left out: %s",
                    length(unique(event_of_day[!with_ellipse])),
                    paste(format(days[!with_ellipse]), collapse = ", ")))
  }
  days <- days[with_ellipse]
  event_of_day <- as.integer(factor(event_of_day[with_ellipse]))
  event_days <- data.frame(date = days, compound_event_id = event_of_day,
                           day_in_event = stats::ave(event_of_day, event_of_day, FUN = seq_along),
                           n_clusters = daily$n_clusters[with_ellipse])
  ellipses$compound_event_id <- event_of_day[match(ellipses$date, days)]
  if (anyNA(ellipses$compound_event_id)) fail("An ellipse date is missing from the selected days.")

  events <- do.call(rbind, lapply(split(ellipses, ellipses$compound_event_id), function(e) {
    dates <- event_days$date[event_days$compound_event_id == e$compound_event_id[1]]
    per_day <- as.integer(table(factor(e$date, levels = as.character(dates))))
    counts <- per_day                         # all selected days decide the type
    axial <- axial_mean(e$azimuth_north_cw_deg)
    largest <- which.max(e$area_km2)        # earliest on a tie (catalog order)
    settings <- daily[daily$date %in% dates, ]
    data.frame(
      compound_event_id = e$compound_event_id[1], start_date = dates[1], end_date = dates[length(dates)],
      duration_days = as.integer(dates[length(dates)] - dates[1]) + 1L, n_selected_days = length(dates),
      event_type = classify_event(counts), event_type_name = TYPE_NAMES[classify_event(counts)],
      daily_cluster_counts = paste(per_day, collapse = "-"), total_clusters = sum(per_day),
      min_daily_clusters = min(counts), max_daily_clusters = max(counts),
      n_single_cluster_days = sum(counts == 1), n_multi_cluster_days = sum(counts > 1),
      event_eps = max(settings$sequence_eps), event_min_samples = max(settings$sequence_min_samples),
      mean_area_km2 = mean(e$area_km2), mean_axis_ratio = mean(e$axis_ratio),
      axial_mean_azimuth_deg = axial$mean, axial_resultant_length = axial$resultant,
      largest_ellipse_id = e$ellipse_id[largest], largest_ellipse_date = e$date[largest],
      largest_ellipse_area_km2 = e$area_km2[largest])
  }))
  rownames(events) <- NULL
  ellipses$event_type <- events$event_type[ellipses$compound_event_id]
  # Largest ellipse of every selected day (earliest cluster on a tie; none on
  # a day without a cluster).
  largest_of_day <- vapply(split(seq_len(nrow(ellipses)), factor(ellipses$date, levels = as.character(days))),
                           function(i) if (length(i)) i[which.max(ellipses$area_km2[i])] else NA_integer_, 0L)
  event_days$largest_ellipse_id <- ellipses$ellipse_id[largest_of_day]
  event_days$largest_ellipse_area_km2 <- ellipses$area_km2[largest_of_day]
  # Years are warm-season years: a season that spans the new year is counted
  # in the year it starts.
  season_months <- clusters$season_months
  if (is.null(season_months)) {
    # Older or manually assembled stage objects have no season metadata.
    season_months <- as.integer(format(clusters$dates, "%m"))
  } else {
    # Explicit season metadata must identify a single start month. Sparse
    # observed dates in older stage objects retain their existing fallback.
    season_months <- validate_season_months(season_months)
  }
  season_start <- season_start_month(season_months)
  analyzed_years <- season_year(clusters$dates, season_start)
  year <- season_year(events$start_date, season_start)
  years <- sort(unique(analyzed_years))
  annual_counts <- data.frame(year = years)
  for (t in 1:4) annual_counts[[paste0("type_", t, "_events")]] <- tabulate(match(year[events$event_type == t], years), length(years))
  annual_counts$all_events <- rowSums(annual_counts[, -1])
  structure(list(events = events, event_days = event_days, ellipses = ellipses,
                 table_1 = table_1(events), annual_counts = annual_counts,
                 annual_duration = annual_duration(events, year),
                 trends = duration_trends(events, year)),
            class = "scorch_events")
}

# A season is one run of calendar months, with December followed by January.
# Return a canonical set so both configuration and stage metadata use the
# same rule. All twelve months are a valid, year-round season.
validate_season_months <- function(months) {
  if (!is.numeric(months) || !length(months) || anyNA(months) ||
      any(!is.finite(months)) || any(!months %in% 1:12)) {
    fail("The setting 'warm_season_months' must list calendar months between 1 and 12.")
  }
  months <- sort(unique(as.integer(months)))
  if (length(months) < 12L) {
    predecessor <- (months - 2L) %% 12L + 1L
    if (sum(!predecessor %in% months) != 1L) {
      fail(paste("The setting 'warm_season_months' must form one contiguous season",
                 "in calendar order; it may cross December and January."))
    }
  }
  months
}

# First month of the warm season: the analysed month whose predecessor is
# not analysed (November for a November-March season; 1 when all months are).
season_start_month <- function(months) {
  months <- sort(unique(months))
  starts <- months[!((months - 2) %% 12 + 1) %in% months]
  if (length(starts)) starts[1] else 1L
}

# Calendar year of the season a date belongs to.
season_year <- function(dates, season_start) {
  as.integer(format(dates, "%Y")) - as.integer(as.integer(format(dates, "%m")) < season_start)
}

# Type 1-4 from the number of clusters on each day of an event.
classify_event <- function(daily_cluster_counts) {
  counts <- daily_cluster_counts
  if (!length(counts) || anyNA(counts) || any(counts < 0) || !any(counts > 0)) {
    fail("An event needs at least one cluster to be classified.")
  }
  if (length(counts) == 1) return(if (counts[1] == 1) 1L else 2L)
  if (all(counts == 1) || all(counts > 1)) 3L else 4L
}

# Compound heatwave statistics by type (Table 1 of the study).
table_1 <- function(events) {
  do.call(rbind, lapply(1:4, function(t) {
    sub <- events[events$event_type == t, ]
    n <- nrow(sub)
    data.frame(compound_heatwave_type = sprintf("Type %d: %s", t, TYPE_NAMES[t]),
               selected_event_days = sum(sub$n_selected_days), number_of_compound_events = n,
               longest_event_days = if (n) max(sub$duration_days) else NA_integer_,
               mean_duration_days_per_event = if (n) round(mean(sub$duration_days), 2) else NA_real_,
               mean_ellipses_per_event = if (n) round(mean(sub$total_clusters), 2) else NA_real_,
               minimum_ellipses_per_event = if (n) min(sub$total_clusters) else NA_integer_,
               maximum_ellipses_per_event = if (n) max(sub$total_clusters) else NA_integer_)
  }))
}

# Mean duration of Type 3 and Type 4 events by start year (years with events only).
annual_duration <- function(events, year) {
  rows <- lapply(3:4, function(t) {
    sub <- events[events$event_type == t, ]
    if (!nrow(sub)) return(NULL)
    means <- tapply(sub$duration_days, year[events$event_type == t], mean)
    data.frame(event_type = t, year = as.integer(names(means)), mean_duration_days = as.numeric(means))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) data.frame(event_type = integer(), year = integer(), mean_duration_days = numeric()) else out
}

# Ordinary least squares, Sen's slope and Mann-Kendall tests on the annual
# mean duration of Type 3 and Type 4 events (at least three years needed).
duration_trends <- function(events, year) {
  series <- annual_duration(events, year)
  rows <- lapply(3:4, function(t) {
    s <- series[series$event_type == t, ]
    row <- data.frame(event_type = t, event_type_name = TYPE_NAMES[t], n_years = nrow(s),
                      ols_slope_days_per_decade = NA_real_, ols_p_value = NA_real_, ols_r_squared = NA_real_,
                      sen_slope_days_per_decade = NA_real_, mann_kendall_s = NA_real_,
                      mann_kendall_z = NA_real_, mann_kendall_p_value = NA_real_,
                      mann_kendall_result = "too few years")
    if (nrow(s) < 3) return(row)
    mk <- mann_kendall(s$mean_duration_days)
    if (stats::sd(s$mean_duration_days) == 0) {
      # A constant series: no slope, no explained variance.
      row$ols_slope_days_per_decade <- 0
      row$ols_p_value <- 1
      row$ols_r_squared <- 0
    } else {
      fit <- stats::lm(mean_duration_days ~ year, data = s)
      row$ols_slope_days_per_decade <- 10 * stats::coef(fit)[["year"]]
      row$ols_p_value <- summary(fit)$coefficients["year", 4]
      row$ols_r_squared <- summary(fit)$r.squared
    }
    row$sen_slope_days_per_decade <- 10 * sens_slope(s$year, s$mean_duration_days)
    row[c("mann_kendall_s", "mann_kendall_z", "mann_kendall_p_value")] <- mk[c("s", "z", "p")]
    row$mann_kendall_result <- mk$result
    row
  })
  do.call(rbind, rows)
}

# Two-sided Mann-Kendall test with tie-corrected variance and continuity correction.
mann_kendall <- function(y) {
  n <- length(y)
  pairs <- utils::combn(n, 2)
  s <- sum(sign(y[pairs[2, ]] - y[pairs[1, ]]))
  ties <- rle(sort(y))$lengths
  var_s <- (n * (n - 1) * (2 * n + 5) - sum(ties * (ties - 1) * (2 * ties + 5))) / 18
  z <- if (s > 0) (s - 1) / sqrt(var_s) else if (s < 0) (s + 1) / sqrt(var_s) else 0
  p <- 2 * (1 - stats::pnorm(abs(z)))
  result <- if (p < 0.05 && z > 0) "increasing" else if (p < 0.05 && z < 0) "decreasing" else "no significant trend"
  list(s = s, z = z, p = p, result = result)
}

# Median of all pairwise slopes.
sens_slope <- function(x, y) {
  pairs <- utils::combn(length(x), 2)
  dx <- x[pairs[2, ]] - x[pairs[1, ]]
  stats::median(((y[pairs[2, ]] - y[pairs[1, ]]) / dx)[dx != 0])
}

# Axial (doubled-angle) mean of orientations in degrees, wrapped to (-90, 90],
# and the resultant length (0 = no preferred axis, 1 = all parallel).
axial_mean <- function(azimuths_deg) {
  theta <- 2 * azimuths_deg[is.finite(azimuths_deg)] * pi / 180
  c <- mean(cos(theta))
  s <- mean(sin(theta))
  r <- sqrt(c^2 + s^2)
  if (!length(theta) || r <= 1e-12) return(list(mean = NA_real_, resultant = r))
  mu <- ((0.5 * atan2(s, c) * 180 / pi + 90) %% 180) - 90
  list(mean = if (mu <= -90) mu + 180 else mu, resultant = r)
}
