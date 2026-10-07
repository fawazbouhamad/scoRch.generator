example_file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")

test_that("the complete workflow runs on the example data and writes every output", {
  out <- file.path(tempfile("scorch"), "results")
  dir.create(file.path(out, "figures"), recursive = TRUE)
  writeLines("old", file.path(out, "figures", "figure_2.png"))
  writeLines("keep", file.path(out, "figures", "user-plot.png"))
  config <- list(input = list(file = example_file), output = list(directory = out),
                 power_law = list(bootstrap_repetitions = 20))
  expect_output(result <- suppressMessages(run_scorch(config)), "34 compound events")
  expect_s3_class(result, "scorch_result")
  expect_equal(result$regional$threshold_cells, 80)
  expect_equal(nrow(result$regional$selected_days), 141)
  expect_equal(nrow(result$clusters$clusters), 149)
  expect_equal(nrow(result$ellipses), 149)
  expect_equal(nrow(result$events$events), 34)
  expect_equal(tabulate(result$events$events$event_type, 4), c(5, 1, 23, 5))
  expect_equal(sum(result$events$table_1$number_of_compound_events), 34)
  expect_equal(result$power_law$summary$reps, c(20, 20))
  expect_true(all(is.finite(result$lgcp$parameters)))
  expect_equal(nrow(result$lgcp$concentration), 6)
  expect_true(all(result$lgcp$cells$concentration_rank > 0 & result$lgcp$cells$concentration_rank <= 1))
  expected <- c(file.path("catalogs", c("1_heatwave_events.csv", "2_regional_days.csv", "2_regional_day_cells.csv",
                                        "3_clusters.csv", "3_cluster_cells.csv", "4_ellipses.csv",
                                        "5_compound_events.csv", "5_event_days.csv")),
                file.path("tables", c("table_1.csv", "cell_thresholds.csv", "daily_heatwave_extent.csv", "duration_trends.csv")),
                file.path("models", c("power_law_fits.csv", "lgcp_parameters.csv", "lgcp_intensity.csv",
                                      "lgcp_centroid_concentration.csv")),
                file.path("figures", paste0(c("ellipse_spatial_patterns", "single_day_events",
                                             "consistent_multiday_events", "mixed_multiday_events",
                                             "ellipse_geometry_by_type", "event_geometry_distributions",
                                             "annual_event_counts_and_duration", "ellipse_area_power_law",
                                             "centroid_concentration"), ".png")), "run_summary.txt")
  expect_true(all(file.exists(file.path(out, expected))))
  expect_true(all(result$plots$status == "generated"))
  expect_match(paste(readLines(file.path(out, "run_summary.txt")), collapse = "\n"),
               "Plots\\n  ellipse_spatial_patterns: generated")
  expect_false(file.exists(file.path(out, "figures", "figure_2.png")))
  expect_equal(readLines(file.path(out, "figures", "user-plot.png")), "keep")
  catalog_5 <- read.csv(file.path(out, "catalogs", "5_compound_events.csv"))
  expect_equal(catalog_5$compound_event_id, seq_len(34))
  expect_equal(nrow(read.csv(file.path(out, "tables", "table_1.csv"))), 4)
  # A figure can be redrawn from the result, and the overrides are checked.
  png_file <- tempfile(fileext = ".png")
  expect_true(scorch_figure(result, name = "annual_event_counts_and_duration", file = png_file))
  expect_true(file.exists(png_file))
  expect_error(scorch_figure(result, 2), "no visualization")
  type_4 <- result$events$events[result$events$events$event_type == 4, ]
  result$config$figures$representative_events$type_4 <- format(type_4$start_date[1])
  shown <- scoRch.generator:::representative_events(result, 4)[[1]]
  expect_equal(shown[1], type_4$start_date[1])
  result$config$figures$representative_events$type_4 <- "1900-01-01"
  expect_error(scoRch.generator:::representative_events(result, 4), "not inside a Type 4 event")
  previous_png <- unname(tools::md5sum(png_file))
  expect_error(scorch_figure(result, "mixed_multiday_events", png_file), "not inside a Type 4 event")
  expect_equal(unname(tools::md5sum(png_file)), previous_png)
  result_without_lgcp <- result
  result_without_lgcp$lgcp <- NULL
  skipped_file <- tempfile(fileext = ".png")
  expect_false(suppressMessages(scorch_figure(result_without_lgcp, "centroid_concentration", skipped_file)))
  expect_false(file.exists(skipped_file))
  expect_length(scoRch.generator:::representative_events(result, 3), 2)   # other types unaffected
  type_3 <- result$events$events[result$events$events$event_type == 3, ]
  result$config$figures$representative_events$type_3 <- format(type_3$start_date[1] + 0:1)
  expect_error(scoRch.generator:::representative_events(result, 3), "different Type 3 events")
  result$config$figures$representative_events$type_3 <- format(type_3$end_date[1])
  expect_error(scoRch.generator:::representative_events(result, 3), "last day")
  result$config$figures$representative_events$type_4 <- NULL
  automatic <- scoRch.generator:::representative_events(result, 4)
  expect_true(all(diff(automatic[[1]]) == 1))
  bad_config <- config
  bad_config$figures <- list(representative_events = list(type_4 = "1900-01-01"))
  previous_catalog <- unname(tools::md5sum(file.path(out, "catalogs", "5_compound_events.csv")))
  expect_error(suppressMessages(run_scorch(bad_config)), "not inside a Type 4 event")
  expect_equal(unname(tools::md5sum(file.path(out, "catalogs", "5_compound_events.csv"))), previous_catalog)
  # Data already in R can replace the input file.
  tmax <- read_tmax(example_file, start = "2015-01-01")
  again <- suppressMessages(run_scorch(list(output = list(directory = file.path(out, "again")),
                                            power_law = list(bootstrap_repetitions = 10)), tmax = tmax))
  expect_equal(nrow(again$input$cells), 256)
  expect_true(file.exists(file.path(out, "again", "run_summary.txt")))
  july <- suppressMessages(run_scorch(list(output = list(directory = file.path(out, "july")),
                                           period = list(warm_season_months = 7),
                                           power_law = list(bootstrap_repetitions = 10)), tmax = tmax))
  expect_true(all(format(july$input$dates, "%m") == "07"))
  expect_equal(length(july$input$dates), 31L * 11L)
})

test_that("a no-cluster rerun replaces old results with clearly partial output", {
  out <- tempfile("scorch-partial-")
  dir.create(out)
  dir.create(file.path(out, "catalogs"))
  dir.create(file.path(out, "tables"))
  dir.create(file.path(out, "models"))
  dir.create(file.path(out, "figures"))
  writeLines("old", file.path(out, "catalogs", "4_ellipses.csv"))
  writeLines("old", file.path(out, "models", "lgcp_parameters.csv"))
  writeLines("old", file.path(out, "figures", "figure_2.png"))
  writeLines("keep", file.path(out, "user-notes.txt"))
  writeLines("keep", file.path(out, "tables", "user-table.csv"))
  values <- array(30, c(10, 3, 3))
  dates <- as.Date("2000-06-01") + 0:9
  tmax <- tmax_from_array(values, dates, 1:3, 1:3)
  config <- list(output = list(directory = out),
                 clustering = list(min_samples_values = 1000))
  expect_error(suppressMessages(run_scorch(config, tmax = tmax)), "No selected day formed a cluster")
  expect_true(file.exists(file.path(out, "catalogs", "3_clusters.csv")))
  expect_false(file.exists(file.path(out, "catalogs", "4_ellipses.csv")))
  expect_false(file.exists(file.path(out, "models", "lgcp_parameters.csv")))
  expect_false(file.exists(file.path(out, "figures", "figure_2.png")))
  expect_match(readLines(file.path(out, "run_summary.txt"))[1], "Incomplete SCORCH run")
  expect_equal(readLines(file.path(out, "user-notes.txt")), "keep")
  expect_equal(readLines(file.path(out, "tables", "user-table.csv")), "keep")
})

test_that("an unavailable LGCP and absent event types are reported explicitly", {
  out <- tempfile("scorch-lgcp-")
  tmax <- tmax_from_array(array(30, c(3, 3, 3)),
                          as.Date("2000-06-01") + 0:2, 1:3, 1:3)
  config <- list(output = list(directory = out),
                 power_law = list(bootstrap_repetitions = 1),
                 clustering = list(eps_values = 1, min_samples_values = 1))
  result <- suppressMessages(suppressWarnings(run_scorch(config, tmax = tmax)))
  expect_null(result$lgcp)
  expect_match(result$lgcp_error, "needs more centroids than the 3 available")
  expect_equal(result$plots$status[result$plots$name == "centroid_concentration"], "skipped")
  expect_equal(result$plots$status[result$plots$name == "annual_event_counts_and_duration"], "generated")
  summary_lines <- readLines(file.path(out, "run_summary.txt"))
  summary <- paste(summary_lines, collapse = "\n")
  expect_match(summary, "LGCP: not fitted. Reason: The LGCP needs more centroids")
  expect_match(summary, "centroid_concentration: skipped")
  expect_true(any(grepl("^  centroid_concentration: skipped \\(.*\\)$", summary_lines)))
  expect_false(any(summary_lines == ")"))
  expect_false(file.exists(file.path(out, "models", "lgcp_parameters.csv")))
  expect_false(file.exists(file.path(out, "figures", "centroid_concentration.png")))
})

test_that("the stage functions can be chained by hand", {
  tmax <- read_tmax(example_file, start = "2010-01-01")
  clusters <- cluster_heatwaves(select_regional_days(detect_heatwaves(tmax)))
  events <- classify_events(clusters, fit_ellipses(clusters, tmax))
  expect_true(nrow(events$events) > 0)
  expect_equal(sum(events$events$total_clusters), nrow(events$ellipses))
  expect_true(all(events$event_days$date %in% clusters$daily_settings$date))
  expect_equal(sum(events$event_days$n_clusters), nrow(events$ellipses))
  power_law <- fit_power_law(events, n_bootstrap = 10)
  expect_equal(nrow(power_law$summary), 2)
  expect_error(fit_ellipses(clusters, tmax, scale_factor = -1), "scale_factor")
  expect_error(detect_heatwaves(tmax, threshold_percentile = 150), "threshold_percentile")
})
