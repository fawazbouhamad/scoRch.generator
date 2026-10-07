# Power-law fits of the largest ellipse areas.

#' Fit power laws to the largest ellipse areas
#'
#' Two samples are fitted: the area of the largest ellipse of every selected
#' day ("daily maxima") and of every compound event ("event maxima"). The fit
#' follows Clauset, Shalizi and Newman (2009): every distinct area except the
#' largest is tried as the lower cutoff; for each cutoff the exponent is the
#' maximum-likelihood estimate on the tail, and the cutoff with the smallest
#' Kolmogorov-Smirnov distance (two-sided, with the smaller cutoff on ties) is
#' kept. The goodness-of-fit p-value comes from a semiparametric bootstrap:
#' each repetition draws a sample of the same size, taking each observation
#' from the observed values below the cutoff or from the fitted power law with
#' the observed tail fraction, refits it and records its distance; p is the
#' share of repetitions whose distance reaches the observed one.
#'
#' @param events A `scorch_events` object from [classify_events()].
#' @param n_bootstrap Number of bootstrap repetitions (the study used 5000).
#' @param seed_daily_maxima,seed_event_maxima Random seeds of the two bootstraps.
#' @return A `scorch_power_law` object: a list with one element per sample
#'   (`daily_maxima`, `event_maxima`), each holding the `sample` table, the
#'   `fit` and the `bootstrap` results, and a `summary` table with one row per
#'   sample.
#' @examples
#' file <- system.file("extdata", "example_tmax.nc", package = "scoRch.generator")
#' tmax <- read_tmax(file)
#' clusters <- cluster_heatwaves(select_regional_days(detect_heatwaves(tmax)))
#' events <- classify_events(clusters, fit_ellipses(clusters, tmax))
#' power_law <- fit_power_law(events, n_bootstrap = 50)   # 50 repetitions only for speed
#' power_law$summary
#' @export
fit_power_law <- function(events, n_bootstrap = 5000, seed_daily_maxima = 20261020,
                          seed_event_maxima = 20261120) {
  if (!inherits(events, "scorch_events")) fail("`events` must come from classify_events().")
  check_number(n_bootstrap, "n_bootstrap (bootstrap_repetitions in the configuration)", 1, integer = TRUE)
  check_number(seed_daily_maxima, "seed_daily_maxima", integer = TRUE)
  check_number(seed_event_maxima, "seed_event_maxima", integer = TRUE)
  e <- events$ellipses
  daily <- events$event_days[!is.na(events$event_days$largest_ellipse_id), ]
  daily_sample <- e[match(daily$largest_ellipse_id, e$ellipse_id),
                    c("date", "compound_event_id", "ellipse_id", "cluster_id", "area_km2")]
  event_sample <- e[match(events$events$largest_ellipse_id, e$ellipse_id),
                    c("compound_event_id", "ellipse_id", "cluster_id", "date", "area_km2")]
  rownames(daily_sample) <- rownames(event_sample) <- NULL
  samples <- list(daily_maxima = list(sample = daily_sample, seed = seed_daily_maxima),
                  event_maxima = list(sample = event_sample, seed = seed_event_maxima))
  results <- lapply(names(samples), function(name) {
    areas <- samples[[name]]$sample$area_km2
    fit <- pl_fit(areas)
    boot <- NULL
    if (identical(fit$status, "ok")) {
      boot <- pl_bootstrap(areas, fit, reps = as.integer(n_bootstrap), seed = samples[[name]]$seed)
      if (boot$n_undefined > 0) {
        message(sprintf(paste("Power law (%s): %d of %d bootstrap samples had no defined fit, so the",
                              "p-value is undefined; its bounds p_lower and p_upper are reported instead."),
                        name, boot$n_undefined, boot$reps))
      }
    } else {
      message(sprintf("Power law (%s): no fit is possible with %d areas (%d distinct values).",
                      name, length(areas), length(unique(areas))))
    }
    list(sample = samples[[name]]$sample, fit = fit, bootstrap = boot, seed = samples[[name]]$seed)
  })
  names(results) <- names(samples)
  summary <- do.call(rbind, lapply(names(results), function(name) power_law_summary(name, results[[name]])))
  structure(c(results, list(summary = summary,
                            settings = list(n_bootstrap = n_bootstrap,
                                            seed_daily_maxima = seed_daily_maxima,
                                            seed_event_maxima = seed_event_maxima))),
            class = "scorch_power_law")
}

# One summary row per sample.
power_law_summary <- function(name, result) {
  fit <- result$fit
  boot <- result$bootstrap
  alpha <- if (is.null(boot)) numeric() else boot$alpha_boot[!is.na(boot$alpha_boot)]
  q <- if (length(alpha)) stats::quantile(alpha, c(0.025, 0.25, 0.5, 0.75, 0.975), type = 7, names = FALSE) else rep(NA_real_, 5)
  value <- function(x) if (is.null(x)) NA_real_ else x
  data.frame(dataset = name, status = fit$status, n = fit$n, n_tail = fit$n_tail, xmin_km2 = fit$xmin,
             alpha = fit$alpha, ks_distance = fit$D, p_value = value(boot$p),
             p_lower = value(boot$p_lower), p_upper = value(boot$p_upper),
             n_exceed = value(boot$n_exceed), reps = value(boot$reps),
             n_undefined = value(boot$n_undefined), mc_se = value(boot$mc_se), seed = result$seed,
             alpha_boot_median = q[3], alpha_boot_q2.5 = q[1], alpha_boot_q25 = q[2],
             alpha_boot_q75 = q[4], alpha_boot_q97.5 = q[5])
}

# Two-sided Kolmogorov-Smirnov distance between the sorted tail and the
# fitted power law. With tied observations the largest gap lies at the ends of
# each tied run; both one-sided gaps at every index cover them.
pl_ks <- function(tail_sorted, xmin, a) {
  n <- length(tail_sorted)
  fitted_cdf <- 1 - (xmin / tail_sorted)^a
  max(max(fitted_cdf - (0:(n - 1)) / n), max((1:n) / n - fitted_cdf))
}

# Try every candidate cutoff and keep the one with the smallest distance.
pl_fit <- function(x) {
  xs <- sort(as.numeric(x))
  N <- length(xs)
  distinct <- unique(xs)
  if (length(distinct) < 2L) {
    return(list(xmin = NA_real_, alpha = NA_real_, D = NA_real_, n_tail = NA_integer_,
                loglik = NA_real_, n = N, n_candidates = 0L, status = "no_candidates"))
  }
  candidates <- distinct[-length(distinct)]          # all but the largest value
  first_index <- match(candidates, xs)
  distance <- numeric(length(candidates))
  for (i in seq_along(candidates)) {
    tail_values <- xs[first_index[i]:N]              # all copies of a tied cutoff kept
    # sum(log(x / xmin)) rather than sum(log x) - n log xmin: the last digits
    # differ and could decide an exact tie.
    a <- length(tail_values) / sum(log(tail_values / candidates[i]))
    distance[i] <- pl_ks(tail_values, candidates[i], a)
  }
  D <- min(distance)
  selected <- which(distance <= D)[1L]                # smallest cutoff among exact ties
  xmin <- candidates[selected]
  tail_values <- xs[first_index[selected]:N]
  n <- length(tail_values)
  alpha <- 1 + n / sum(log(tail_values / xmin))
  list(xmin = xmin, alpha = alpha, D = D, n_tail = n,
       loglik = n * log((alpha - 1) / xmin) - alpha * sum(log(tail_values / xmin)),
       n = N, n_candidates = length(candidates),
       status = if (is.finite(alpha) && is.finite(D)) "ok" else "nonfinite_fit")
}

# Goodness-of-fit bootstrap (the semiparametric scheme of Clauset's plpva).
# Random draws happen in this order in every repetition: N uniforms deciding
# body or tail, one uniform per body value, then one per tail value.
pl_bootstrap <- function(x, fit, reps, seed) {
  x <- as.numeric(x)
  N <- length(x)
  xmin <- fit$xmin
  tail_values <- x[x >= xmin]
  body_values <- x[x < xmin]
  n_body <- length(body_values)
  alpha <- 1 + length(tail_values) / sum(log(tail_values / xmin))
  observed <- pl_ks(sort(tail_values), xmin, alpha - 1)
  tail_fraction <- length(tail_values) / N
  # Use the study's generator and seed, then give the session its own random
  # state back.
  old_kind <- RNGkind()
  old_seed <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit({
    RNGkind(old_kind[1], old_kind[2], old_kind[3])
    if (is.null(old_seed)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old_seed, envir = globalenv())
  }, add = TRUE)
  set.seed(seed, kind = "Mersenne-Twister")
  distance <- alpha_boot <- xmin_boot <- rep(NA_real_, reps)
  status <- character(reps)
  for (b in seq_len(reps)) {
    n1 <- sum(stats::runif(N) > tail_fraction)
    n2 <- N - n1
    q1 <- if (n1 > 0L && n_body > 0L) body_values[ceiling(n_body * stats::runif(n1))] else numeric(0)
    q2 <- if (n2 > 0L) xmin * (1 - stats::runif(n2))^(-1 / (alpha - 1)) else numeric(0)
    refit <- pl_fit(c(q1, q2))
    alpha_boot[b] <- refit$alpha
    xmin_boot[b] <- refit$xmin
    status[b] <- refit$status
    if (identical(refit$status, "ok")) distance[b] <- refit$D
  }
  ok <- !is.na(distance)
  n_undefined <- sum(!ok)
  n_exceed <- sum(distance[ok] >= observed)
  # The p-value is defined only when every refit succeeded; otherwise the
  # bounds count undefined refits as non-exceedances (lower) or exceedances (upper).
  complete <- n_undefined == 0L
  p_lower <- n_exceed / reps
  list(p = if (complete) p_lower else NA_real_, p_lower = p_lower,
       p_upper = (n_exceed + n_undefined) / reps, complete = complete, n_exceed = n_exceed,
       gof = observed, reps = reps, n_undefined = n_undefined,
       mc_se = if (complete) sqrt(p_lower * (1 - p_lower) / reps) else NA_real_,
       distance = distance, status = status, alpha_boot = alpha_boot, xmin_boot = xmin_boot,
       alpha_at_xmin = alpha)
}
