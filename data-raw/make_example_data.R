# Build inst/extdata/example_tmax.nc, the example dataset of scoRch.generator.
#
# Source: the processed SCORCH temperature dataset (Bouhamad and Najibi),
# Zenodo record 10.5281/zenodo.21717874 (version 1.0.0), file scorch_data/tmax_processed.nc:
# ERA5 hourly 2-m temperature (Hersbach et al., 2020) reduced to daily maxima
# at 0.25 degrees and averaged to 1-degree cells, April-September 1940-2025,
# 20-70 E, 10-46 N. The example keeps the cells from 38.5 to 53.5 E and 22.5
# to 37.5 N (16 x 16 cells over the Arabian Peninsula, Iraq and Iran) for the
# 30 warm seasons 1996-2025, rounded to 0.01 degrees Celsius.
#
# Run from the package root, giving the path of the downloaded study file:
#   Rscript data-raw/make_example_data.R path/to/tmax_processed.nc
library(ncdf4)

source_file <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(source_file) || !file.exists(source_file)) stop("give the path of tmax_processed.nc")
lon_range <- c(38.5, 53.5)
lat_range <- c(22.5, 37.5)
years <- 1996:2025
target <- file.path("inst", "extdata", "example_tmax.nc")

nc <- nc_open(source_file)
lon <- nc$dim$lon$vals
lat <- nc$dim$lat$vals
days <- nc$dim$time$vals
dates <- as.Date("1940-01-01") + days
i <- which(lon >= lon_range[1] & lon <= lon_range[2])
j <- which(lat >= lat_range[1] & lat <= lat_range[2])
k <- which(as.integer(format(dates, "%Y")) %in% years)
tmax <- ncvar_get(nc, "tmax", start = c(i[1], j[1], k[1]), count = c(length(i), length(j), length(k)))
nc_close(nc)
stopifnot(!anyNA(tmax))

dim_lon <- ncdim_def("lon", "degrees_east", lon[i], longname = "longitude of grid-cell centre")
dim_lat <- ncdim_def("lat", "degrees_north", lat[j], longname = "latitude of grid-cell centre")
dim_time <- ncdim_def("time", "days since 1940-01-01", days[k], calendar = "standard",
                      longname = "date (April-September warm-season days)")
var <- ncvar_def("tmax", "degC", list(dim_lon, dim_lat, dim_time), missval = -32768L, prec = "short",
                 longname = "daily maximum 2-m air temperature, 1-degree cell mean", compression = 9,
                 shuffle = TRUE)
out <- nc_create(target, var, force_v4 = TRUE)
ncatt_put(out, "tmax", "scale_factor", 0.01, prec = "double")
ncatt_put(out, "tmax", "standard_name", "air_temperature")
ncatt_put(out, "tmax", "cell_methods", "time: maximum (interval: 1 day) area: mean")
ncvar_put(out, var, round(tmax * 100))
ncatt_put(out, 0, "title", "scoRch.generator example: daily maximum temperature, 38.5-53.5 E, 22.5-37.5 N, April-September 1996-2025")
ncatt_put(out, 0, "source", "Subset of the SCORCH processed temperature dataset (doi:10.5281/zenodo.21717874): ERA5 hourly 2-m temperature, daily maximum at 0.25 degrees, averaged to 1-degree cells, rounded to 0.01 degC")
ncatt_put(out, 0, "license", "CC BY 4.0 for the authors' processing; contains modified Copernicus Climate Change Service information 2026 (ERA5, Copernicus licence)")
ncatt_put(out, 0, "history", "written by data-raw/make_example_data.R of scoRch.generator")
nc_close(out)
cat(sprintf("wrote %s: %d x %d cells, %d dates, %.2f MB\n", target, length(i), length(j), length(k),
            file.size(target) / 1e6))
