# The complete workflow: read, analyse, model, write and draw.

#' Run the complete SCORCH workflow
#'
#' Reads the temperature input named in the configuration (raw ERA5 2-m
#' temperature, reduced to daily maxima as described in [read_era5()], or
#' daily maximum temperature, see [read_tmax()]), runs the five
#' catalog stages, fits the power-law and LGCP models, and writes the
#' catalogs, tables, model results and plots to the output folder:
#' `catalogs/` (Catalogs 1-5 and their day and cell tables), `tables/`
#' (Table 1, cell thresholds, daily counts, duration trends), `models/`
#' (power-law fits, LGCP parameters, intensity and centroid concentration),
#' `figures/` (descriptively named PNG results) and `run_summary.txt`.
#' Package-generated files are replaced after the new run is written; other
#' files in those folders are preserved.
#' A valid run can have an unavailable LGCP fit or a plot whose event type is
#' absent. Their status and reasons are written to `run_summary.txt`; an
#' unexpected plot error stops the run without publishing its partial output.
#' When no selected day forms a cluster, only Catalogs 1-3 and the first
#' tables are published, and `run_summary.txt` marks the run incomplete.
#'
#' The package ships with the configuration of the SCORCH study, and its
#' settings are the defaults. A run can use them as they are or change
#' individual settings: any setting that `config` leaves out keeps its study
#' value.
#'
#' @param config Path of a YAML configuration file (an edited copy from
#'   [write_scorch_config()] or [scorch_template()]), or a list with the same
#'   structure. `NULL` (the default) runs with the SCORCH study settings; the
#'   temperature must then be given as `tmax`, because the shipped
#'   configuration names no input file, and the results are written to
#'   `scorch_output/` in the working directory.
#' @param tmax Optional `scorch_tmax` object (from [read_tmax()] or
#'   [tmax_from_array()]) to analyse instead of reading the file named in the
#'   configuration. The configured warm-season months and date limits also
#'   apply to this object.
#' @return A `scorch_result` list (invisibly) with the configuration, the
#'   input description and the tables of every stage: `heatwaves`, `regional`,
#'   `clusters`, `ellipses`, `events`, `power_law` and `lgcp`. Use it with
#'   [scorch_figure()] to redraw a result plot.
#' @examples
#' \donttest{
#' old <- setwd(tempdir())                              # results go to tempdir()/scorch_output
#' scorch_template("scorch_config.yaml", fast = TRUE)   # fast demonstration for the example data
#' result <- run_scorch("scorch_config.yaml")
#' result$events$table_1
#' setwd(old)
#' }
#' @export
run_scorch <- function(config = NULL, tmax = NULL) {
  started <- Sys.time()
  cfg <- read_config(config, input_required = is.null(tmax))
  out <- cfg$output$directory
  published <- FALSE
  on.exit(if (!published && dir.exists(out)) {
    message("This run did not publish output; files in ", out, " belong to an earlier run.")
  }, add = TRUE)
  step <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

  if (is.null(tmax)) {
    step("Reading %s", paste(cfg$input$file, collapse = ", "))
    tmax <- read_configured_input(cfg)
  } else if (!inherits(tmax, "scorch_tmax")) {
    fail("`tmax` must come from read_tmax() or tmax_from_array().")
  } else {
    tmax <- subset_tmax_period(tmax, months = cfg$period$warm_season_months,
                               start = cfg$period$start_date, end = cfg$period$end_date)
  }
  step("%d cells, %d dates from %s to %s", nrow(tmax$cells), length(tmax$dates),
       format(tmax$dates[1]), format(tmax$dates[length(tmax$dates)]))
  step("Stage 1: local heatwaves")
  heatwaves <- detect_heatwaves(tmax, cfg$heatwaves$threshold_percentile,
                                cfg$heatwaves$min_duration_days, cfg$heatwaves$min_exceeding_days)
  step("Stage 2: regionally extensive days")
  regional <- select_regional_days(heatwaves, cfg$regional_days$percentile)
  heatwaves <- heatwaves[c("events", "thresholds")]
  step("Stage 3: DBSCAN clustering of %d selected days", nrow(regional$selected_days))
  clusters <- cluster_heatwaves(regional, cfg$clustering$eps_values, cfg$clustering$min_samples_values)
  stage <- prepare_run_output(out)
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE), add = TRUE)
  if (!any(clusters$daily_settings$n_clusters > 0)) {
    # Publish only the partial results of this run, so old downstream results
    # cannot be mistaken for output from the current attempt.
    write_partial_outputs(stage, heatwaves, regional, clusters)
    writeLines(c("Incomplete SCORCH run: no selected day formed a cluster.",
                 sprintf("Started %s", format(started, "%Y-%m-%d %H:%M:%S")),
                 "Catalogs 1-3, cell thresholds and daily extent are available.",
                 "No ellipses, compound events, models or figures were produced."),
               file.path(stage, "run_summary.txt"))
    publish_run_output(stage, out)
    published <- TRUE
    fail(paste("No selected day formed a cluster, so there are no ellipses or compound events.",
               "Partial catalogs and tables were written to", out, "."))
  }
  step("Stage 4: ellipses of %d clusters", nrow(clusters$clusters))
  ellipses <- fit_ellipses(clusters, tmax, cfg$ellipses$scale_factor)
  step("Stage 5: compound events")
  events <- classify_events(clusters, ellipses)
  validate_representative_event_overrides(cfg, events)
  step("Power-law fits with %d bootstrap repetitions", cfg$power_law$bootstrap_repetitions)
  power_law <- fit_power_law(events, cfg$power_law$bootstrap_repetitions,
                             cfg$power_law$seed_daily_maxima, cfg$power_law$seed_event_maxima)
  step("Log-Gaussian Cox process of %d centroids", nrow(events$ellipses))
  lgcp_error <- NULL
  lgcp <- tryCatch(fit_lgcp(events, tmax, cfg$lgcp$covariates, cfg$lgcp$raster_km, cfg$lgcp$window_margin_km),
                   error = function(e) {
                     lgcp_error <<- conditionMessage(e)
                     message("The LGCP could not be fitted: ", lgcp_error)
                     NULL
                   })

  result <- structure(list(
    config = cfg,
    input = c(list(source = tmax$source, cells = tmax$cells, grid = tmax$grid, dates = tmax$dates),
              if (!is.null(tmax$preprocessing)) list(preprocessing = tmax$preprocessing)),
    heatwaves = heatwaves,
    regional = regional[c("daily", "selected_days", "selected_cells", "threshold_cells")],
    clusters = clusters[c("clusters", "cluster_cells", "daily_settings", "sequences")],
    ellipses = events$ellipses,
    events = events[c("events", "event_days", "table_1", "annual_counts", "annual_duration", "trends")],
    power_law = power_law, lgcp = lgcp, lgcp_error = lgcp_error, output_dir = stage,
    package_version = as.character(utils::packageVersion("scoRch.generator")),
    started = started), class = "scorch_result")

  step("Writing catalogs, tables and model results to %s", out)
  write_outputs(result)
  plot_names <- names(figure_specs())
  plots <- data.frame(name = plot_names, status = rep("skipped", length(plot_names)),
                      reason = rep("", length(plot_names)))
  for (i in seq_along(plot_names)) {
    figure <- plot_names[i]
    step("Plot %s", figure)
    file <- file.path(stage, "figures", paste0(figure, ".png"))
    reason <- character()
    drawn <- withCallingHandlers(scorch_figure(result, figure, file),
                                 message = function(m) reason <<- c(reason, trimws(conditionMessage(m))))
    if (isTRUE(drawn)) {
      plots$status[i] <- "generated"
    } else {
      plots$reason[i] <- if (length(reason)) paste(reason, collapse = " ") else "Not available for this dataset."
    }
  }
  result$plots <- plots
  result$elapsed_minutes <- as.numeric(difftime(Sys.time(), started, units = "mins"))
  writeLines(run_summary(result), file.path(stage, "run_summary.txt"))
  publish_run_output(stage, out)
  published <- TRUE
  result$output_dir <- out
  if (is.null(lgcp)) {
    step("Finished with the LGCP unavailable in %.1f minutes; see run_summary.txt", result$elapsed_minutes)
  } else {
    step("Done in %.1f minutes", result$elapsed_minutes)
  }
  print(result)
  invisible(result)
}

# Check a date against the actual catalog before fitting models or drawing
# plots. Invalid manual choices should never be hidden as a skipped plot.
validate_representative_event_overrides <- function(cfg, events) {
  context <- list(config = cfg, events = events)
  for (type in 1:4) {
    if (!is.null(cfg$figures$representative_events[[paste0("type_", type)]])) {
      representative_events(context, type)
    }
  }
  invisible(TRUE)
}

#' @export
print.scorch_result <- function(x, ...) {
  types <- tabulate(x$events$events$event_type, 4)
  cat(sprintf(paste0("<scorch_result> %d cells, %d dates; %d local heatwaves; regional threshold %d cells;\n",
                     "  %d selected days, %d clusters/ellipses, %d compound events (Type 1-4: %s)\n",
                     "  outputs in %s\n"),
              nrow(x$input$cells), length(x$input$dates), nrow(x$heatwaves$events),
              x$regional$threshold_cells, nrow(x$regional$selected_days), nrow(x$ellipses),
              nrow(x$events$events), paste(types, collapse = "/"), x$output_dir))
  invisible(x)
}

# Build each run away from the published output. Package-generated files are
# moved into place only after they have all been written.
prepare_run_output <- function(out) {
  parent <- dirname(out)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
    fail("Could not create the parent of the output directory: ", parent)
  }
  stage <- tempfile(pattern = ".scorch-stage-", tmpdir = parent)
  if (!dir.create(stage, showWarnings = FALSE)) fail("Could not create the temporary output directory: ", stage)
  for (folder in c("catalogs", "tables", "models", "figures")) {
    if (!dir.create(file.path(stage, folder), showWarnings = FALSE)) {
      unlink(stage, recursive = TRUE)
      fail("Could not prepare the output folder: ", folder)
    }
  }
  stage
}

publish_run_output <- function(stage, out) {
  if (!dir.exists(out) && !dir.create(out, recursive = TRUE, showWarnings = FALSE)) {
    fail("Could not create the output directory: ", out)
  }
  backup <- tempfile(pattern = ".scorch-backup-", tmpdir = dirname(out))
  if (!dir.create(backup, showWarnings = FALSE)) fail("Could not prepare a backup of existing output: ", backup)
  managed <- managed_output_files()
  old_moved <- new_moved <- character()
  problem <- tryCatch({
    for (item in managed) {
      target <- file.path(out, item)
      if (file.exists(target)) {
        dir.create(dirname(file.path(backup, item)), recursive = TRUE, showWarnings = FALSE)
        if (!file.rename(target, file.path(backup, item))) fail("Could not back up existing output: ", target)
        old_moved <- c(old_moved, item)
      }
    }
    for (item in managed) {
      source <- file.path(stage, item)
      if (file.exists(source)) {
        dir.create(dirname(file.path(out, item)), recursive = TRUE, showWarnings = FALSE)
        if (!file.rename(source, file.path(out, item))) fail("Could not publish output: ", source)
        new_moved <- c(new_moved, item)
      }
    }
    NULL
  }, error = identity)
  if (!is.null(problem)) {
    returned_new <- vapply(rev(new_moved), function(item) {
      file.rename(file.path(out, item), file.path(stage, item))
    }, logical(1))
    restored_old <- vapply(rev(old_moved), function(item) {
      file.rename(file.path(backup, item), file.path(out, item))
    }, logical(1))
    if (!all(returned_new) || !all(restored_old)) {
      fail("Publishing failed and some previous files could not be restored. The backup remains at ", backup, ".")
    }
    unlink(backup, recursive = TRUE)
    stop(problem)
  }
  unlink(backup, recursive = TRUE)
  invisible(out)
}

# Include all optional outputs so a rerun cannot leave a stale model or plot.
# Numeric names belong to earlier package versions and are removed on upgrade.
managed_output_files <- function() {
  c(file.path("catalogs", c("1_heatwave_events.csv", "2_regional_days.csv",
                             "2_regional_day_cells.csv", "3_clusters.csv",
                             "3_cluster_cells.csv", "4_ellipses.csv",
                             "5_compound_events.csv", "5_event_days.csv")),
    file.path("tables", c("table_1.csv", "cell_thresholds.csv",
                           "daily_heatwave_extent.csv", "duration_trends.csv")),
    file.path("models", c("power_law_fits.csv", "lgcp_parameters.csv",
                           "lgcp_intensity.csv", "lgcp_centroid_concentration.csv")),
    file.path("figures", paste0(names(figure_specs()), ".png")),
    file.path("figures", paste0("figure_", c(2L, 3L, 5:12), ".png")),
    "run_summary.txt")
}

csv_writer <- function(out) function(table, ...) utils::write.csv(table, file.path(out, ...), row.names = FALSE)

write_outputs <- function(result) {
  out <- result$output_dir
  csv <- csv_writer(out)
  csv(result$heatwaves$events, "catalogs", "1_heatwave_events.csv")
  csv(result$regional$selected_days, "catalogs", "2_regional_days.csv")
  csv(result$regional$selected_cells, "catalogs", "2_regional_day_cells.csv")
  csv(result$clusters$clusters, "catalogs", "3_clusters.csv")
  csv(result$clusters$cluster_cells, "catalogs", "3_cluster_cells.csv")
  csv(result$ellipses, "catalogs", "4_ellipses.csv")
  csv(result$events$events, "catalogs", "5_compound_events.csv")
  csv(result$events$event_days, "catalogs", "5_event_days.csv")
  csv(result$events$table_1, "tables", "table_1.csv")
  csv(result$heatwaves$thresholds, "tables", "cell_thresholds.csv")
  csv(result$regional$daily, "tables", "daily_heatwave_extent.csv")
  csv(result$events$trends, "tables", "duration_trends.csv")
  csv(result$power_law$summary, "models", "power_law_fits.csv")
  if (!is.null(result$lgcp)) {
    csv(result$lgcp$parameter_table, "models", "lgcp_parameters.csv")
    csv(result$lgcp$cells, "models", "lgcp_intensity.csv")
    csv(result$lgcp$concentration, "models", "lgcp_centroid_concentration.csv")
  }
}

# Catalogs 1-3 and the first tables when no cluster could be formed.
write_partial_outputs <- function(out, heatwaves, regional, clusters) {
  csv <- csv_writer(out)
  csv(heatwaves$events, "catalogs", "1_heatwave_events.csv")
  csv(regional$selected_days, "catalogs", "2_regional_days.csv")
  csv(regional$selected_cells, "catalogs", "2_regional_day_cells.csv")
  csv(clusters$clusters, "catalogs", "3_clusters.csv")
  csv(clusters$cluster_cells, "catalogs", "3_cluster_cells.csv")
  csv(heatwaves$thresholds, "tables", "cell_thresholds.csv")
  csv(regional$daily, "tables", "daily_heatwave_extent.csv")
}

# Degrees with the hemisphere letter, for the run summary and print methods.
format_degrees <- function(value, letters) {
  paste0(abs(value), "\u00b0", ifelse(value < 0, letters[2], letters[1]))
}

run_summary <- function(result) {
  cfg <- result$config
  events <- result$events$events
  pl <- result$power_law$summary
  lines <- c(
    sprintf("scoRch.generator %s run summary", result$package_version),
    sprintf("Started %s, finished in %.1f minutes", format(result$started, "%Y-%m-%d %H:%M:%S"), result$elapsed_minutes),
    "", "Input",
    sprintf("  %s", result$input$source),
    if (!is.null(result$input$preprocessing)) sprintf("  %s", result$input$preprocessing),
    sprintf("  %d cells, %g x %g degree grid, %s to %s, %s to %s", nrow(result$input$cells),
            result$input$grid$lon_step, result$input$grid$lat_step,
            format_degrees(min(result$input$cells$lon), c("E", "W")), format_degrees(max(result$input$cells$lon), c("E", "W")),
            format_degrees(min(result$input$cells$lat), c("N", "S")), format_degrees(max(result$input$cells$lat), c("N", "S"))),
    sprintf("  %d dates from %s to %s, months %s", length(result$input$dates), format(min(result$input$dates)),
            format(max(result$input$dates)), paste(cfg$period$warm_season_months, collapse = " ")),
    "", "Results",
    sprintf("  Catalog 1: %d local heatwaves", nrow(result$heatwaves$events)),
    sprintf("  Catalog 2: regional threshold %d heatwave cells; %d selected days",
            result$regional$threshold_cells, nrow(result$regional$selected_days)),
    sprintf("  Catalog 3: %d clusters", nrow(result$clusters$clusters)),
    sprintf("  Catalog 4: %d ellipses", nrow(result$ellipses)),
    sprintf("  Catalog 5: %d compound events; by type: %s", nrow(events),
            paste(sprintf("Type %d = %d", 1:4, tabulate(events$event_type, 4)), collapse = ", ")),
    sprintf("  Power law (%s): n = %d, n_tail = %s, A_min = %s km2, alpha = %s, p = %s", pl$dataset, pl$n,
            format(pl$n_tail), format(pl$xmin_km2, digits = 6), format(pl$alpha, digits = 4),
            format(pl$p_value, digits = 3)),
    if (is.null(result$lgcp)) paste0("  LGCP: not fitted. Reason: ", result$lgcp_error) else
      c("  LGCP parameters:", sprintf("    %s = %s", names(result$lgcp$parameters),
                                      format(result$lgcp$parameters, digits = 6)),
        sprintf("    %s", if (length(result$lgcp$warnings)) paste("warning:", result$lgcp$warnings) else "no warnings")),
    "", "Plots",
    sprintf("  %s: %s%s", result$plots$name, result$plots$status,
            ifelse(nzchar(result$plots$reason), paste0(" (", result$plots$reason, ")"), "")),
    "", "Settings", paste0("  ", strsplit(yaml::as.yaml(cfg[setdiff(names(cfg), "output")]), "\n")[[1]]))
  lines
}
