fixture <- function(name) test_path("fixtures", name)
areas <- read.csv(fixture("study_power_law_areas.csv"))
fits <- read.csv(fixture("study_power_law_fits.csv"))

test_that("the power-law fit reproduces the study cutoffs and exponents", {
  for (name in fits$dataset) {
    fit <- scoRch.generator:::pl_fit(areas$area_km2[areas$dataset == name])
    row <- fits[fits$dataset == name, ]
    expect_equal(fit$status, "ok")
    expect_equal(fit$n, row$n)
    expect_equal(fit$n_tail, row$n_tail)
    expect_equal(fit$xmin, row$xmin_km2, tolerance = 1e-12)
    expect_equal(fit$alpha, row$alpha, tolerance = 1e-12)
    expect_equal(fit$D, row$ks_distance, tolerance = 1e-12)
  }
  expect_equal(scoRch.generator:::pl_fit(c(1, 1, 1))$status, "no_candidates")
})

test_that("the bootstrap is reproducible from its seed and counts every repetition", {
  x <- areas$area_km2[areas$dataset == "event_maxima"]
  fit <- scoRch.generator:::pl_fit(x)
  boot <- scoRch.generator:::pl_bootstrap(x, fit, reps = 150L, seed = 20261120L)
  again <- scoRch.generator:::pl_bootstrap(x, fit, reps = 150L, seed = 20261120L)
  expect_identical(boot$distance, again$distance)
  expect_equal(boot$reps, 150L)
  expect_equal(sum(!is.na(boot$alpha_boot)) + boot$n_undefined, 150L)
  expect_true(boot$p >= 0 && boot$p <= 1)
  expect_equal(boot$p, boot$n_exceed / 150)
  expect_equal(boot$gof, fit$D, tolerance = 1e-12)
})

test_that("the full 5000-repetition bootstrap reproduces the study p-values (long test)", {
  skip_if(Sys.getenv("SCORCH_LONG_TESTS") == "", "set SCORCH_LONG_TESTS=1 to run")
  for (name in fits$dataset) {
    x <- areas$area_km2[areas$dataset == name]
    row <- fits[fits$dataset == name, ]
    boot <- scoRch.generator:::pl_bootstrap(x, scoRch.generator:::pl_fit(x), reps = row$reps, seed = row$seed)
    expect_equal(boot$n_exceed, row$n_exceed)
    expect_equal(boot$p, row$p_value)
  }
})

test_that("the equal-area projection agrees with the study's PROJ coordinates", {
  centroids <- read.csv(fixture("study_centroids_projected.csv"))
  xy <- scoRch.generator:::laea_forward(centroids$centroid_lon, centroids$centroid_lat, 45, 28)
  expect_equal(xy[, 1], centroids$x_km, tolerance = 1e-7)
  expect_equal(xy[, 2], centroids$y_km, tolerance = 1e-7)
  back <- scoRch.generator:::laea_inverse(xy[, 1], xy[, 2], 45, 28)
  expect_equal(back[, 1], centroids$centroid_lon, tolerance = 1e-10)
  expect_equal(back[, 2], centroids$centroid_lat, tolerance = 1e-10)
  expect_equal(scoRch.generator:::laea_forward(45, 28, 45, 28), cbind(0, 0))
})

test_that("pixel centres follow numpy's arange", {
  expect_equal(scoRch.generator:::pixel_centres(0, 100, 25), c(12.5, 37.5, 62.5, 87.5))
  expect_equal(scoRch.generator:::pixel_centres(0, 101, 25), c(12.5, 37.5, 62.5, 87.5))
  expect_equal(scoRch.generator:::pixel_centres(0, 113, 25), c(12.5, 37.5, 62.5, 87.5, 112.5))
})
