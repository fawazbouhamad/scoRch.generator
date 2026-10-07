# Stage 2: regionally extensive heatwave days (Catalog 2).

#' Select days with regionally extensive heatwaves
#'
#' Counts the heatwave cells on every analysed date (days with no heatwave
#' cell included) and selects the dates whose count reaches the regional
#' threshold: the observed count at or just above the `percentile` position
#' of all daily counts (the "higher" quantile rule of the study).
#'
#' @param heatwaves A `scorch_heatwaves` object from [detect_heatwaves()].
#' @param percentile Regional-day percentile of the daily heatwave-cell
#'   counts (0-100).
#' @return A `scorch_regional` object: a list with `daily` (one row per
#'   analysed date with its cell counts), `selected_days` (Catalog 2) and
#'   `selected_cells` (the heatwave cells of every selected date, west to east
#'   and south to north), `threshold_cells`, and the `thresholds`, `dates`,
#'   `cells` and `grid` carried from the earlier stages.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' regional <- select_regional_days(detect_heatwaves(read_tmax(file)))
#' regional$threshold_cells
#' head(regional$selected_days)
#' @export
select_regional_days <- function(heatwaves, percentile = 97.5) {
  if (!inherits(heatwaves, "scorch_heatwaves")) fail("`heatwaves` must come from detect_heatwaves().")
  check_number(percentile, "percentile", 0, 100)
  in_heatwave <- heatwaves$local_event_id > 0L
  n_cells <- ncol(in_heatwave)
  n_heatwave <- rowSums(in_heatwave)
  n_exceeding <- rowSums(heatwaves$exceedance)
  n_both <- rowSums(in_heatwave & heatwaves$exceedance)
  threshold <- quantile_higher(n_heatwave, percentile / 100)
  if (threshold <= 0) {
    fail(sprintf(paste("The regional threshold is zero: fewer than %g%% of the analysed days have",
                       "any heatwave cell, so no regionally extensive days can be selected."),
                 100 - percentile))
  }
  selected <- n_heatwave >= threshold
  daily <- data.frame(
    date = heatwaves$dates, n_domain_cells = n_cells, n_exceeding_cells = n_exceeding,
    n_heatwave_cells = n_heatwave, n_heatwave_and_exceeding_cells = n_both,
    heatwave_fraction_of_domain = n_heatwave / n_cells,
    heatwave_share_of_exceeding_cells = ifelse(n_exceeding > 0, n_both / pmax(n_exceeding, 1), NA_real_),
    regional_threshold_cells = threshold, selected = as.integer(selected))
  selected_days <- daily[selected, c("date", "n_heatwave_cells", "heatwave_fraction_of_domain",
                                     "n_exceeding_cells", "n_heatwave_and_exceeding_cells",
                                     "heatwave_share_of_exceeding_cells")]
  rownames(selected_days) <- NULL
  cells <- heatwaves$cells
  selected_cells <- do.call(rbind, lapply(which(selected), function(t) {
    on <- which(in_heatwave[t, ])
    on <- on[longitude_major_order(cells$lon[on], cells$lat[on])]
    data.frame(date = heatwaves$dates[t], cell_id = cells$cell_id[on], lat = cells$lat[on],
               lon = cells$lon[on], local_event_id = heatwaves$local_event_id[t, on])
  }))
  rownames(selected_cells) <- NULL
  structure(list(daily = daily, selected_days = selected_days, selected_cells = selected_cells,
                 threshold_cells = threshold, thresholds = heatwaves$thresholds,
                 dates = heatwaves$dates, cells = cells, grid = heatwaves$grid,
                 season_months = heatwaves$season_months,
                 settings = list(percentile = percentile)),
            class = "scorch_regional")
}

# The observed value at or just above the quantile position (the "higher"
# interpolation of pandas: sorted[ceiling((n - 1) q) + 1]).
quantile_higher <- function(x, q) {
  sorted <- sort(x)
  sorted[ceiling((length(sorted) - 1) * q) + 1]
}
