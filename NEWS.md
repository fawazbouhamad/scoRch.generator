# scoRch.generator 0.1.0

* First R implementation of the SCORCH workflow: local heatwaves, regionally
  extensive days, DBSCAN clusters, principal-component ellipses, compound
  heatwave typology, power-law and log-Gaussian Cox process models, Table 1
  and the result plots of spatial patterns, event examples, geometry, trends
  and fitted models. Output images use descriptive names; the paper's Figure 2
  is not generated as a result.
* Correctly filter supplied `scorch_tmax` objects by the configured period,
  decode complete CF time origins at midnight, retain leading zero-event
  seasons, and classify selected zero-cluster days consistently with the
  reference method.
* Publish each run from a temporary output directory so a partial no-cluster
  run cannot retain downstream catalogs, models or images from a previous run.
  Files added by the user to the output folders are preserved.
* One configuration file and one function (`run_scorch()`) run the complete
  workflow on a user's NetCDF file. The package ships with the configuration
  of the SCORCH study (`inst/scorch_config.yaml`), the single source of the
  default settings; `write_scorch_config()` writes an editable copy, and any
  setting left out of a user's configuration keeps its study value.
  `run_scorch()` without a configuration uses the study settings.
  `scorch_template()` writes the same configuration set up for the example
  dataset.
* Raw ERA5 input: `run_scorch()` reads ERA5 2-m temperature (`t2m`) NetCDF
  files as downloaded, hourly or daily, from one file, several files or a
  folder, and prepares them as the SCORCH study did: maximum of each UTC day,
  Kelvin to degrees Celsius, and averages over 1-degree cells
  (`era5_cell_size_deg`). The new configuration setting `input: format`
  (`auto`, `era5`, `daily_tmax`) and automatic variable and coordinate names
  select the reader; daily maximum temperature files are read as before.
  `read_era5()` exposes the preprocessing on its own.
* `demo/` runs the complete workflow on the example data with one
  configuration file and one command.
* Example dataset: a 16 x 16 cell, 30-season subset of the study's processed
  ERA5 temperature.
* Verified against the study's reproducibility repository (see README).
* The reference results now come from the study's corrected processed input
  (doi:10.5281/zenodo.21717874), in which every 1-degree cell is the mean of
  its 16 ERA5 0.25-degree points (the first processed input averaged the
  45.5 N row from the 45.0 N points only). The full-study test uses this final
  reference (176,061 local heatwaves, 753 clusters, 51 compound events of
  Types 1-4: 3/3/20/25); the historical results remain testable as an audit.
  The study-derived test fixtures were regenerated from the final reference.
