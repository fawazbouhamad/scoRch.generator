# SCORCH demonstration: North America between 25 N and 50 N, 1996-2025.
#
# Run from the top folder of the repository, after installing the package:
#     Rscript demo/run_demo.R
# or, in R, source("demo/run_demo.R"). It takes under a minute and writes the
# results to results/: eight XLSX workbooks, nine figures and README.txt.
# demo/README.md explains every input and output and the event traced in
# part 4.

library(scoRch.generator)

# A day of the compound event traced in part 4. It was chosen after a first
# run of this script (see demo/README.md); any date inside any event works.
trace_date <- "2012-06-30"

# 1. The input ---------------------------------------------------------------
# The demonstration data are ERA5-derived daily maximum 2-m temperatures on
# 25 x 72 one-degree cells between 25 N and 50 N and between 130 W and 58 W:
# the contiguous United States with southern Canada, northern Mexico and the
# adjacent Pacific, Atlantic and Gulf of Mexico waters, every April-September
# day of 1996-2025 (inst/extdata/README.md gives the source, licence and
# processing). read_tmax() reads any NetCDF file of daily maximum temperature
# on a regular grid.
file <- system.file("extdata", "north_america_tmax.nc", package = "scoRch.generator")
tmax <- read_tmax(file)
print(tmax)

# 2. The whole workflow with one command ---------------------------------------
# demo/scorch_config.yaml names the input, the output folder and the event to
# show in the figures; every other setting keeps the value of the SCORCH study
# (see inst/scorch_config.yaml).
result <- run_scorch("demo/scorch_config.yaml")

# 3. What was found -----------------------------------------------------------
cat("\nCompound heatwave events by type (the Event Type Summary sheet):\n")
print(result$events$table_1, row.names = FALSE)

cat("\nThe first compound events (Catalog 5):\n")
columns <- c("compound_event_id", "start_date", "end_date", "event_type_name", "daily_cluster_counts")
print(head(result$events$events[, columns]), row.names = FALSE)

cat("\nPower-law fits of the largest ellipse areas:\n")
print(result$power_law$summary[, c("dataset", "n", "n_tail", "xmin_km2", "alpha", "p_value")], row.names = FALSE)

# 4. One event, traced from the temperature data to its figure ----------------
# Every row of every catalog can be followed back to the temperature data.
# trace_event() takes one compound event (Catalog 5) and shows, stage by
# stage, why it exists: the selected days and their heatwave-cell counts
# (Catalog 2), the clusters DBSCAN formed (Catalog 3), the largest ellipse
# (Catalog 4), the hottest cell of that ellipse with its threshold and local
# heatwave (Catalog 1), and that cell's daily temperatures around the event.
trace_event <- function(result, tmax, date) {
  date <- as.Date(date)
  events <- result$events$events
  event <- events[events$start_date <= date & events$end_date >= date, ]
  if (nrow(event) != 1) stop("No compound event contains ", format(date))
  old_width <- options(width = 110)                 # the tables below fit on one line
  on.exit(options(old_width), add = TRUE)
  lines <- character()
  say <- function(...) lines <<- c(lines, sprintf(...))
  show <- function(df) lines <<- c(lines, paste0("  ", utils::capture.output(print(df, row.names = FALSE))))
  n_cells <- nrow(result$input$cells)
  say("Compound event %d (Catalog 5): %s to %s, %d days, %s = Type %d, clusters per day %s",
      event$compound_event_id, format(event$start_date), format(event$end_date), event$duration_days,
      event$event_type_name, event$event_type, event$daily_cluster_counts)
  # Stage 2: the days were selected because their heatwave cells reached the regional threshold.
  days <- result$events$event_days[result$events$event_days$compound_event_id == event$compound_event_id, ]
  daily <- result$regional$daily[match(days$date, result$regional$daily$date), ]
  say("")
  say("Stage 2 (Catalog 2): every day of the event had at least %d of the %d cells in a local heatwave,",
      result$regional$threshold_cells, n_cells)
  say("the regional threshold (the 97.5th percentile of the daily heatwave-cell counts):")
  show(data.frame(date = format(days$date), heatwave_cells = daily$n_heatwave_cells,
                  exceeding_cells = daily$n_exceeding_cells, clusters = days$n_clusters))
  # Stage 3: DBSCAN clusters of the heatwave cells on those days.
  clusters <- result$clusters$clusters[result$clusters$clusters$date %in% days$date, ]
  say("")
  say("Stage 3 (Catalog 3): DBSCAN grouped the heatwave cells of each day into these clusters")
  say("(eps in grid cells and min_samples cells are the settings chosen for the run of days):")
  show(data.frame(date = format(clusters$date), cluster_id = clusters$cluster_id,
                  member_cells = clusters$n_member_cells, core_cells = clusters$n_core_cells,
                  eps = round(clusters$eps_applied, 3), min_samples = clusters$min_samples_applied,
                  noise_cells = clusters$n_noise_cells_on_day))
  # Stage 4: the largest ellipse of the event.
  e <- result$ellipses[result$ellipses$ellipse_id == event$largest_ellipse_id, ]
  say("")
  say("Stage 4 (Catalog 4): the largest ellipse of the event is ellipse %d, fitted to cluster %d on %s:",
      e$ellipse_id, e$cluster_id, format(e$date))
  direction <- if (abs(e$azimuth_north_cw_deg) > 67.5) "nearly east-west" else if (abs(e$azimuth_north_cw_deg) < 22.5) "nearly north-south" else if (e$azimuth_north_cw_deg > 0) "northeast-southwest" else "northwest-southeast"
  say("  %d member cells; axes %.0f km x %.0f km; area %.0f km2; major axis %.0f degrees from north (%s);",
      e$n_member_cells, e$major_axis_km, e$minor_axis_km, e$area_km2, e$azimuth_north_cw_deg, direction)
  say("  Tmax-weighted centroid %.2f N, %.2f W; member Tmax %.1f to %.1f C.",
      e$centroid_lat_weighted, -e$centroid_lon_weighted, e$tmax_min_c, e$tmax_max_c)
  # Stage 1 and the data: the hottest member cell of that ellipse.
  members <- result$clusters$cluster_cells[which(result$clusters$cluster_cells$cluster_id == e$cluster_id), ]
  column <- match(members$cell_id, tmax$cells$cell_id)
  row <- match(e$date, tmax$dates)
  hottest <- members[which.max(tmax$tmax[row, column]), ]
  threshold <- result$heatwaves$thresholds[result$heatwaves$thresholds$cell_id == hottest$cell_id, ]
  heatwave <- result$heatwaves$events[result$heatwaves$events$local_event_id == hottest$local_event_id, ]
  say("")
  say("Stage 1 (Catalog 1): the hottest of those cells is cell %d (%.1f N, %.1f W). Its threshold is %.2f C,",
      hottest$cell_id, hottest$lat, -hottest$lon, threshold$threshold_tmax_c)
  say("the 95th percentile of its %d daily maxima. Local heatwave %d of that cell ran from %s to %s:",
      length(tmax$dates), heatwave$local_event_id, format(heatwave$start_date), format(heatwave$end_date))
  say("%d days, %d of them at or above the threshold, peak %.2f C on %s.",
      heatwave$duration_days, heatwave$exceeding_days, heatwave$peak_tmax_c, format(heatwave$peak_date))
  say("")
  say("The temperature data of that cell around the heatwave (daily maximum 2-m temperature, degrees C):")
  window <- seq(heatwave$start_date - 2, heatwave$end_date + 2, by = "day")
  window <- window[window %in% tmax$dates]
  series <- tmax$tmax[match(window, tmax$dates), match(hottest$cell_id, tmax$cells$cell_id)]
  show(data.frame(date = format(window), tmax_c = sprintf("%.2f", series),
                  exceeds_threshold = ifelse(series >= threshold$threshold_tmax_c, "yes", "no"),
                  local_heatwave = ifelse(window >= heatwave$start_date & window <= heatwave$end_date, "yes", "no"),
                  selected_day = ifelse(window %in% result$regional$selected_days$date, "yes", "no"),
                  in_event = ifelse(window >= event$start_date & window <= event$end_date, "yes", "no")))
  figure <- c("single_day_events", "single_day_events", "consistent_multiday_events", "mixed_multiday_events")[event$event_type]
  say("")
  say("Figure: %s/figures/%s.png shows this event (named in demo/scorch_config.yaml", result$output_dir, figure)
  say("under figures: representative_events): orange cells are the clustered heatwave cells, grey cells the")
  say("heatwave cells DBSCAN left out, the black outline is the ellipse and the dot its weighted centroid.")
  lines
}

trace <- trace_event(result, tmax, trace_date)
cat("\n", paste(trace, collapse = "\n"), "\n", sep = "")
# The trace joins README.txt, the one text file of the results, before the
# settings section.
readme_file <- file.path(result$output_dir, "README.txt")
readme <- readLines(readme_file, encoding = "UTF-8")             # the file is UTF-8 whatever the locale
settings_at <- grep("^SETTINGS OF THIS RUN", readme)[1]
indented <- ifelse(nzchar(trace), paste0("  ", trace), "")
writeLines(enc2utf8(c(readme[seq_len(settings_at - 1)], "TRACED EVENT (demo/run_demo.R, part 4)", indented, "",
                    readme[settings_at:length(readme)])), readme_file, useBytes = TRUE)

# 5. The same analysis one stage at a time --------------------------------------
# run_scorch() chains these functions; each returns plain data frames that
# can be inspected before moving on.
heatwaves <- detect_heatwaves(tmax)                       # Catalog 1: local heatwaves in every cell
regional  <- select_regional_days(heatwaves)              # Catalog 2: regionally extensive days
clusters  <- cluster_heatwaves(regional)                   # Catalog 3: DBSCAN clusters of those days
ellipses  <- fit_ellipses(clusters, tmax)                  # Catalog 4: an ellipse per cluster
events    <- classify_events(clusters, ellipses)           # Catalog 5: compound events and types
cat(sprintf("\nStage by stage: %d local heatwaves, %d selected days, %d ellipses, %d compound events\n",
            nrow(heatwaves$events), nrow(regional$selected_days), nrow(ellipses), nrow(events$events)))
stopifnot(identical(events$table_1, result$events$table_1))   # the same result as run_scorch()

# 6. The files ---------------------------------------------------------------
cat("\nFiles written:\n")
cat(paste0("  ", result$output_dir, "/", list.files(result$output_dir, recursive = TRUE)), sep = "\n")
cat("\nOpen the workbooks in", result$output_dir, "(Heatwave_Catalogs/, Modelling/, Additional_Results/), the maps in figures/,",
    "and README.txt for the input, settings, counts, models, files, traced event and warnings.\n")
