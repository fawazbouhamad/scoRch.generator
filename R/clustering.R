# Stage 3: DBSCAN settings and clusters of heatwave cells (Catalog 3).

#' Group the heatwave cells of every selected day with DBSCAN
#'
#' Distances are measured in grid-cell units: one unit is one grid step along
#' each axis. For every selected day, DBSCAN is run for every pair of a
#' candidate neighbourhood distance (`eps`) and a minimum neighbourhood size
#' (`min_samples`, the cell itself included). The most frequent non-zero
#' cluster count over all pairs is found (if several counts tie, all of them
#' are kept); the day's settings are the mean `eps` and the mean `min_samples`
#' (rounded half up, never below 1) of the pairs that gave those counts. Days
#' that form a run of consecutive selected dates share settings: the largest
#' daily `eps` and the largest daily `min_samples` of the run. Each day is
#' finally clustered with those pooled settings. Clusters are numbered in the
#' order DBSCAN finds them, scanning cells west to east and south to north.
#'
#' @param regional A `scorch_regional` object from [select_regional_days()].
#' @param eps_values Candidate neighbourhood distances, in grid-cell units.
#' @param min_samples_values Candidate minimum neighbourhood sizes.
#' @return A `scorch_clusters` object: a list with `clusters` (Catalog 3, one
#'   row per cluster), `cluster_cells` (every heatwave cell of every selected
#'   day with its cluster, noise and core flags), `daily_settings` (the
#'   parameter choice of every day), `sequences` (settings of every run of
#'   consecutive days) and the tables carried from the earlier stages.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' regional <- select_regional_days(detect_heatwaves(read_tmax(file)))
#' clusters <- cluster_heatwaves(regional)
#' head(clusters$clusters)
#' @export
cluster_heatwaves <- function(regional, eps_values = c(1, 1.5, 2, 2.5, 3, 3.5, 4),
                              min_samples_values = 4:12) {
  if (!inherits(regional, "scorch_regional")) fail("`regional` must come from select_regional_days().")
  if (!is.numeric(eps_values) || !length(eps_values) || anyNA(eps_values) || any(eps_values <= 0)) {
    fail("The setting 'eps_values' must be a list of positive distances in grid-cell units.")
  }
  if (!is.numeric(min_samples_values) || !length(min_samples_values) || anyNA(min_samples_values) ||
      any(min_samples_values < 1 | min_samples_values != round(min_samples_values))) {
    fail("The setting 'min_samples_values' must be a list of whole numbers of at least 1.")
  }
  days <- regional$selected_days$date
  grid <- regional$grid
  by_day <- split(regional$selected_cells, factor(regional$selected_cells$date, levels = as.character(days)))
  # Whole-number grid coordinates (distances do not depend on the origin), so
  # that distances between cells are exact.
  points <- lapply(by_day, function(g) cbind(round((g$lon - min(g$lon)) / grid$lon_step),
                                             round((g$lat - min(g$lat)) / grid$lat_step)))
  pairs <- expand.grid(min_samples = as.integer(min_samples_values), eps = as.numeric(eps_values))
  pairs <- pairs[, c("eps", "min_samples")]

  # 1-2. Parameter search and the daily choice.
  daily <- do.call(rbind, lapply(seq_along(days), function(k) {
    pts <- points[[k]]
    n_clusters <- mapply(function(eps, m) max(dbscan::dbscan(pts, eps = eps, minPts = m)$cluster),
                         pairs$eps, pairs$min_samples)
    choice <- select_daily_parameters(pairs$eps, pairs$min_samples, n_clusters)
    data.frame(date = days[k], n_heatwave_cells = nrow(pts),
               modal_cluster_counts = paste(choice$modal_counts, collapse = "|"),
               modal_frequency = choice$modal_frequency, n_pairs_retained = choice$n_retained,
               daily_eps = choice$eps, daily_min_samples_mean = choice$min_samples_mean,
               daily_min_samples = choice$min_samples)
  }))
  # 3. Pool the settings over runs of consecutive selected dates.
  sequence_id <- cumsum(c(TRUE, diff(days) > 1))
  daily$sequence_start_date <- days[match(sequence_id, sequence_id)]
  sequences <- do.call(rbind, lapply(split(daily, sequence_id), function(d) {
    data.frame(sequence_start_date = d$sequence_start_date[1], end_date = max(d$date),
               n_days = nrow(d), sequence_eps = max(d$daily_eps),
               sequence_min_samples = max(d$daily_min_samples))
  }))
  rownames(sequences) <- NULL
  daily$sequence_eps <- sequences$sequence_eps[sequence_id]
  daily$sequence_min_samples <- sequences$sequence_min_samples[sequence_id]

  # 4. Final clustering of every day with its pooled settings.
  next_id <- 1L
  clusters <- list()
  cluster_cells <- vector("list", length(days))
  for (k in seq_along(days)) {
    pts <- points[[k]]
    eps <- daily$sequence_eps[k]
    m <- daily$sequence_min_samples[k]
    labels <- dbscan::dbscan(pts, eps = eps, minPts = m)$cluster - 1L   # 0, 1, ... and -1 for noise
    is_core <- dbscan::is.corepoint(pts, eps = eps, minPts = m)
    n_within <- lengths(dbscan::frNN(pts, eps = eps)$id) + 1L
    day_labels <- sort(unique(labels[labels != NOISE_LABEL]))
    ids <- next_id - 1L + seq_along(day_labels)
    if (length(day_labels)) {
      clusters[[k]] <- data.frame(
        cluster_id = ids, date = days[k], cluster_number_in_day = day_labels,
        dbscan_label = day_labels,
        n_member_cells = tabulate(labels + 1L, length(day_labels)),
        n_core_cells = vapply(day_labels, function(l) sum(labels == l & is_core), 0L),
        eps_applied = eps, min_samples_applied = m,
        n_clusters_on_day = length(day_labels), n_noise_cells_on_day = sum(labels == NOISE_LABEL))
      next_id <- next_id + length(day_labels)
    }
    g <- by_day[[k]]
    cluster_cells[[k]] <- data.frame(
      date = g$date, cell_id = g$cell_id, lat = g$lat, lon = g$lon,
      local_event_id = g$local_event_id, dbscan_label = labels,
      cluster_id = ifelse(labels == NOISE_LABEL, NA_integer_, ids[match(labels, day_labels)]),
      is_noise = as.integer(labels == NOISE_LABEL), is_core_cell = as.integer(is_core),
      n_cells_within_eps = n_within)
  }
  clusters <- do.call(rbind, clusters)
  if (is.null(clusters)) {
    clusters <- data.frame(cluster_id = integer(), date = as.Date(character()), cluster_number_in_day = integer(),
                           dbscan_label = integer(), n_member_cells = integer(), n_core_cells = integer(),
                           eps_applied = numeric(), min_samples_applied = integer(),
                           n_clusters_on_day = integer(), n_noise_cells_on_day = integer())
  }
  cluster_cells <- do.call(rbind, cluster_cells)
  rownames(clusters) <- rownames(cluster_cells) <- NULL
  daily$n_clusters <- tabulate(match(clusters$date, days), length(days))
  if (any(daily$n_clusters == 0)) {
    message(sprintf("%d selected day(s) formed no cluster (they stay in their compound event without an ellipse): %s",
                    sum(daily$n_clusters == 0), paste(daily$date[daily$n_clusters == 0], collapse = ", ")))
  }
  structure(list(clusters = clusters, cluster_cells = cluster_cells, daily_settings = daily,
                 sequences = sequences, selected_days = regional$selected_days,
                 daily = regional$daily, thresholds = regional$thresholds,
                 threshold_cells = regional$threshold_cells, dates = regional$dates,
                 cells = regional$cells, grid = grid,
                 season_months = regional$season_months,
                 settings = list(eps_values = eps_values, min_samples_values = min_samples_values)),
            class = "scorch_clusters")
}

# One day's DBSCAN settings from the cluster counts of every (eps, min_samples) pair.
select_daily_parameters <- function(eps, min_samples, n_clusters) {
  pool <- n_clusters[n_clusters > 0]
  if (!length(pool)) pool <- n_clusters
  frequency <- table(pool)
  top <- max(frequency)
  modal_counts <- sort(as.integer(names(frequency)[frequency == top]))
  kept <- n_clusters %in% modal_counts
  mean_min_samples <- mean(min_samples[kept])
  list(modal_counts = modal_counts, modal_frequency = as.integer(top), n_retained = sum(kept),
       eps = mean(eps[kept]), min_samples_mean = mean_min_samples,
       min_samples = max(1L, as.integer(floor(mean_min_samples + 0.5))))
}
