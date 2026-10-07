# Demonstration

This folder runs the complete SCORCH analysis on the example data shipped
with the package, the way it is run on any dataset: temperature data, one
configuration file and one command.

| File | What it is |
|---|---|
| [`scorch_config.yaml`](scorch_config.yaml) | the configuration: it names the input data and the output folder; every other setting keeps its SCORCH study value |
| [`run_demo.R`](run_demo.R) | the one command, `run_scorch("demo/scorch_config.yaml")` |

**The data.** [`inst/extdata/example_tmax.nc`](../inst/extdata/example_tmax.nc):
ERA5 daily maximum 2-m temperature on 16 x 16 one-degree cells (38.5-53.5 E,
22.5-37.5 N), April-September 1996-2025, a subset of the SCORCH study's input
(source and licence in [`inst/extdata/README.md`](../inst/extdata/README.md)).
It is already daily and on 1-degree cells, so it is read as daily maximum
temperature. Raw ERA5 files are named in the same setting, for example
`file: 'era5_downloads'` for a folder of hourly ERA5 `t2m` files; the package
then computes the daily maxima and 1-degree cells itself (see the main
[README](../README.md#era5-recommended)).

**Run it** from the top folder of the repository, after installing the
package:

```
Rscript demo/run_demo.R
```

or, in R, `source("demo/run_demo.R")`. The run takes about a minute.

**The results** appear in `scorch_demo_output/`:

```
scorch_demo_output/
  catalogs/        the five SCORCH catalogs (heatwaves, regional days, clusters, ellipses, compound events)
  tables/          Table 1, cell thresholds, daily heatwave extent, duration trends
  models/          power-law fits and the log-Gaussian Cox process
  figures/         maps and plots, including automatically chosen representative events
  run_summary.txt  input, results, model parameters and every setting used
```

To analyse your own data, write the complete configuration with
`write_scorch_config("scorch_config.yaml")`, set `input: file`, and run
`run_scorch("scorch_config.yaml")`.
