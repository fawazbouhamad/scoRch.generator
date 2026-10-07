# Stage 1: cell thresholds and local heatwaves (Catalog 1).

#' Detect local heatwaves in every grid cell
#'
#' A cell's threshold is the empirical percentile (linear interpolation) of its
#' Tmax over all analysed dates; a day exceeds when Tmax is at or above it. A
#' local heatwave is a run of days that starts and ends on exceeding days,
#' contains no two consecutive non-exceeding days, spans at least
#' `min_duration_days` days and has at least `min_exceeding_days` exceeding
#' days. Single non-exceeding days inside the run are bridged (they belong to
#' the heatwave). A heatwave never crosses a gap in the calendar, such as the
#' break between two warm seasons.
#'
#' @param tmax A `scorch_tmax` object from [read_tmax()] or [tmax_from_array()].
#' @param threshold_percentile Local threshold percentile (0-100).
#' @param min_duration_days Shortest heatwave, in days.
#' @param min_exceeding_days Fewest exceeding days a heatwave must contain.
#' @return A `scorch_heatwaves` object: a list with `events` (Catalog 1, one
#'   row per local heatwave), `thresholds` (one row per cell with its threshold
#'   and counts), the logical matrix `exceedance` and the integer matrix
#'   `local_event_id` (dates x cells; 0 = not in a heatwave), plus the input's
#'   `dates`, `cells` and `grid`.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' heatwaves <- detect_heatwaves(read_tmax(file))
#' head(heatwaves$events)
#' @export
detect_heatwaves <- function(tmax, threshold_percentile = 95, min_duration_days = 3,
                             min_exceeding_days = 3) {
  if (!inherits(tmax, "scorch_tmax")) fail("`tmax` must come from read_tmax() or tmax_from_array().")
  check_number(threshold_percentile, "threshold_percentile", 0, 100)
  check_number(min_duration_days, "min_duration_days", 1, integer = TRUE)
  check_number(min_exceeding_days, "min_exceeding_days", 1, integer = TRUE)
  values <- tmax$tmax
  dates <- tmax$dates
  cells <- tmax$cells
  n_cells <- ncol(values)

  thresholds <- apply(values, 2, stats::quantile, probs = threshold_percentile / 100,
                      type = 7, names = FALSE)
  exceedance <- sweep(values, 2, thresholds, ">=")
  gap_after <- c(diff(dates) > 1, FALSE)

  local_event_id <- matrix(0L, nrow(values), n_cells)
  events <- vector("list", n_cells)
  next_id <- 0L
  for (j in seq_len(n_cells)) {
    runs <- heatwave_runs(exceedance[, j], gap_after, min_duration_days, min_exceeding_days)
    if (nrow(runs) == 0) next
    ids <- next_id + seq_len(nrow(runs))
    for (k in seq_len(nrow(runs))) local_event_id[runs$start[k]:runs$end[k], j] <- ids[k]
    series <- values[, j]
    # Peak: first day of the highest Tmax in the heatwave (bridged days included).
    peak <- runs$start - 1L + mapply(function(s, e) which.max(series[s:e]), runs$start, runs$end)
    events[[j]] <- data.frame(
      local_event_id = ids, cell_id = cells$cell_id[j], lat = cells$lat[j], lon = cells$lon[j],
      event_number_in_cell = seq_len(nrow(runs)),
      start_date = dates[runs$start], end_date = dates[runs$end],
      duration_days = runs$end - runs$start + 1L, exceeding_days = runs$ones,
      bridged_days = runs$end - runs$start + 1L - runs$ones,
      peak_date = dates[peak], peak_tmax_c = series[peak])
    next_id <- next_id + nrow(runs)
  }
  events <- do.call(rbind, events)
  if (is.null(events)) {
    events <- data.frame(local_event_id = integer(), cell_id = integer(), lat = numeric(),
                         lon = numeric(), event_number_in_cell = integer(),
                         start_date = as.Date(character()), end_date = as.Date(character()),
                         duration_days = integer(), exceeding_days = integer(),
                         bridged_days = integer(), peak_date = as.Date(character()),
                         peak_tmax_c = numeric())
  }
  rownames(events) <- NULL
  threshold_table <- data.frame(
    cell_id = cells$cell_id, lat = cells$lat, lon = cells$lon,
    threshold_tmax_c = thresholds,
    n_exceeding_days = colSums(exceedance),
    n_heatwave_days = colSums(local_event_id > 0L),
    n_local_events = tabulate(match(events$cell_id, cells$cell_id), n_cells))
  structure(list(events = events, thresholds = threshold_table, exceedance = exceedance,
                 local_event_id = local_event_id, dates = dates, cells = cells,
                 grid = tmax$grid, season_months = tmax$season_months,
                 settings = list(threshold_percentile = threshold_percentile,
                                 min_duration_days = min_duration_days,
                                 min_exceeding_days = min_exceeding_days)),
            class = "scorch_heatwaves")
}

# Heatwave runs in one cell's exceedance series.
#
# `gap_after[i]` is TRUE when a calendar gap follows date i. Two virtual
# non-exceeding days are inserted at every gap, so that a run can never
# continue across it. Returns a data frame with the first and last date index
# (`start`, `end`) and the number of exceeding days (`ones`) of every run.
heatwave_runs <- function(exceed, gap_after, min_len, min_ones) {
  n <- length(exceed)
  shift <- 2L * c(0L, cumsum(gap_after)[-n])
  position <- seq_len(n) + shift
  x <- integer(n + 2L * sum(gap_after))
  x[position] <- as.integer(exceed)
  r <- rle(x)
  ends <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1L
  # Two or more consecutive non-exceeding days separate pieces; inside a
  # piece, single non-exceeding days are bridged.
  separator <- r$values == 0L & r$lengths >= 2L
  piece <- cumsum(separator)
  ones <- r$values == 1L
  empty <- data.frame(start = integer(), end = integer(), ones = integer())
  if (!any(ones)) return(empty)
  p <- factor(piece[ones])
  first <- tapply(starts[ones], p, min)
  last <- tapply(ends[ones], p, max)
  n_ones <- tapply(r$lengths[ones], p, sum)
  keep <- (last - first + 1L) >= min_len & n_ones >= min_ones
  if (!any(keep)) return(empty)
  original <- integer(length(x))
  original[position] <- seq_len(n)
  data.frame(start = original[first[keep]], end = original[last[keep]],
             ones = as.integer(n_ones[keep]))
}
