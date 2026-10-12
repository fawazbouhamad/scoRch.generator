# The from-scratch path, shown offline: what the package does with a file
# downloaded from the Copernicus Climate Data Store (CDS).
#
# With `input: source: cds` in the configuration, run_scorch() downloads the
# CDS product "ERA5 post-processed daily statistics" (daily maximum of the
# hourly 2-m temperature over each UTC day, 0.25-degree grid), reduces it to
# 1-degree cells and saves the result before the analysis. The package ships
# one such file, downloaded from the CDS for 2012 and a 10 x 10 degree window
# of the demonstration area (34-44 N, 104-94 W), so this script needs no CDS
# account and no download. Run it from the top folder of the repository:
#     Rscript demo/cds_processing_example.R

library(scoRch.generator)
library(ncdf4)

# 1. The raw CDS file -----------------------------------------------------------
sample <- system.file("extdata", "cds_daily_tmax_2012_great_plains.nc", package = "scoRch.generator")
nc <- nc_open(sample)
cat(sprintf("CDS file: variable t2m in %s, %d x %d grid points at 0.25 degrees, %d daily values from %s\n",
            ncatt_get(nc, "t2m", "units")$value, nc$dim$longitude$len, nc$dim$latitude$len, nc$dim$valid_time$len,
            sub("days since ", "", nc$dim$valid_time$units)))
history <- ncatt_get(nc, 0, "history")$value
cat("Processing recorded by the CDS:", regmatches(history, regexpr("earthkit[^;]*", history)), "
")
nc_close(nc)

# 2. The reduction to 1-degree cells --------------------------------------------
# read_era5() converts kelvin to degrees Celsius and averages the 4 x 4 points
# of every complete 1-degree cell; the points on the edges 44 N and 94 W begin
# cells that are not complete, so 10 x 10 cells remain. This is the step
# run_scorch() applies to every downloaded file before write_tmax() saves them.
cells <- read_era5(sample, months = 4:9, cell_size = 1)
print(cells)
hottest <- which(cells$tmax == max(cells$tmax), arr.ind = TRUE)[1, ]
cat(sprintf("Hottest cell-day: %.2f C in the cell %g N, %g W on %s\n", max(cells$tmax),
            cells$cells$lat[hottest[2]], -cells$cells$lon[hottest[2]], format(cells$dates[hottest[1]])))

# 3. The same cells in the demonstration data ---------------------------------------
# The demonstration file was made from another copy of ERA5 (the ARCO-ERA5
# archive, see inst/extdata/README.md). Two sources, the same reanalysis: the
# cells agree to the float32 rounding of the sources plus the 0.01-degree
# packing of the demonstration file.
demo <- read_tmax(system.file("extdata", "north_america_tmax.nc", package = "scoRch.generator"),
                  start = "2012-01-01", end = "2012-12-31")
columns <- match(paste(cells$cells$lon, cells$cells$lat), paste(demo$cells$lon, demo$cells$lat))
stopifnot(!anyNA(columns), identical(demo$dates, cells$dates))
difference <- max(abs(demo$tmax[, columns] - cells$tmax))
cat(sprintf("Largest difference from the demonstration data over %d cells and %d days: %.4f C\n",
            length(columns), length(cells$dates), difference))
stopifnot(difference <= 0.0065)

# 4. Doing it for real ---------------------------------------------------------------
cat("\nTo download your own area from the CDS, once per computer:\n",
    "  1. create a free account at https://cds.climate.copernicus.eu and accept the licence of the dataset\n",
    "     'ERA5 post-processed daily statistics on single levels';\n",
    "  2. in an interactive R session run ecmwfr::wf_set_key() with no arguments and paste your Personal\n",
    "     Access Token at its hidden prompt (into the keychain, not into a script or the R history);\n",
    "then write a configuration with write_scorch_config() and set\n",
    "  input:  source: cds  and  cds: area: [North, West, South, East]\n",
    "  period: start_date and end_date (and warm_season_months, e.g. [11, 12, 1, 2, 3] for a southern season)\n",
    "and run_scorch() it. Each monthly request waits in the CDS queue (minutes to hours); the files are\n",
    "cached and the run resumes where it stopped. The token stays in the keychain.\n", sep = "")
