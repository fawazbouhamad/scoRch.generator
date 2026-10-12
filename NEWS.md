# scoRch.generator 1.0.0

First public release, 12 October 2026: the R implementation of SCORCH
(Spatiotemporal Classification of Regional Compound Heatwaves), the method
of *Understanding Compound Space-Time Typologies of Large-Scale Extreme
Heatwaves* by Fawaz Bouhamad and Nasser Najibi (manuscript in preparation).

* The five stages of the method (local heatwaves, regionally extensive days,
  DBSCAN clusters, principal-component ellipses with temperature-weighted
  centroids, compound events of Types 1-4 with Table 1) and the power-law
  and log-Gaussian Cox process models, run by `run_scorch()` from one
  configuration file or stage by stage. A run writes eight XLSX workbooks
  (`Heatwave_Catalogs/`: the five catalogs with their day and cell tables;
  `Modelling/`: the power-law fits and the LGCP parameters, intensity and
  centroid concentration; `Additional_Results/Analysis_Summary.xlsx`: the
  event type summary, cell thresholds, daily heatwave extent and duration
  trends), nine descriptively named figures and one `README.txt` that
  explains the input, the settings, the counts, the models, every file and
  sheet, the run time and the warnings in plain language. Every sheet keeps
  all rows and columns of its table as date and numeric cells with a frozen,
  filtered header and empty cells for missing values; a table longer than
  an XLSX sheet stops the run with an error instead of losing rows. The
  workbooks are written with openxlsx2, and every archive is checked after
  writing (relationship targets, sheet dimensions, sheet names) so that
  readers stricter than Excel, such as Python's openpyxl, open them;
  `README.txt` is written in UTF-8 whatever the locale of the session.
* Two ways to provide the temperature data, both chosen in the configuration.
  From a prepared file (`input: source: file`, the default): any daily
  maximum temperature NetCDF file on a regular grid, or raw ERA5 files that
  `read_era5()` reduces to daily maxima on 1-degree cells as the study did.
  From scratch (`input: source: cds`): `fetch_era5_daily_tmax()` downloads
  the CDS product *ERA5 post-processed daily statistics* (daily maximum of
  the hourly 2-m temperature over the UTC day, 0.25-degree grid) for the
  area, period and warm-season months of the configuration, one request per
  month (or year), caching every file under a name that states the area and
  the requested dates with a record of the complete request, reusing a file
  only when its name, record, grid and dates match, resuming interrupted
  runs and refusing area edges off the 0.25-degree grid before any request;
  `read_era5()` reduces the files to cells and the new `write_tmax()` saves
  one Celsius NetCDF file. The CDS token is read from the operating system
  keychain written once by `ecmwfr::wf_set_key()` and never appears in a
  configuration file, the code, the logs or `README.txt` (`ecmwfr` and
  `httr` are optional dependencies). Warm seasons that cross the new year
  (`[11, 12, 1, 2, 3]`) are requested calendar year by calendar year.
* Demonstration data: `inst/extdata/north_america_tmax.nc`, daily maximum
  2-m temperature on 25 x 72 one-degree cells between 25 N and 50 N and
  130 W and 58 W (the contiguous United States with southern Canada,
  northern Mexico and the adjacent waters), every April-September day of
  1996-2025: 1,800 cells, 5,490 dates, 12.4 MB, built by
  `data-raw/make_demo_data.R` from the authors' ARCO-ERA5-derived daily
  files with `read_era5()` and `write_tmax()`, every source file, date,
  unit and missing value checked and cell means recomputed by hand;
  `inst/extdata/README.md` records the provenance, the verification against
  the CDS (agreement to 0.0012 degC) and the licence. A file as the CDS
  delivers it (`cds_daily_tmax_2012_great_plains.nc`) is shipped for the
  offline example and tests of the from-scratch path.
* Demo: `demo/run_demo.R` runs the whole analysis on the demonstration data
  in about half a minute (65,790 local heatwaves, 140 selected days, 376
  ellipses, 29 compound events of Types 1-4 = 1/4/20/4) and traces one real
  event, the heat wave of 28 June to 4 July 2012, from the temperature data
  through the five catalogs to its figure; `demo/cds_processing_example.R`
  shows the from-scratch processing on the shipped CDS file.
  `demo/expected_output/` holds the run's eight workbooks, its `README.txt` with
  the traced event, and figures; `demo/compare_output.R` compares every
  sheet and the README with them, in the demo workflow on every change.
* Figures follow the study's: the event snapshots use its plain basemap,
  write each panel's date above the map and size their canvas by the panels
  drawn; no figure carries panel letters; the five-map figure centres its
  bottom panel with the colour bar beside it and puts the legend of its
  first map below that map; maps over the United
  States show state outlines; every figure is written at 600 dpi (500 for
  the two largest).
* Verified against the study's research record: with the study's processed
  input the package reproduces all 176,061 local heatwaves, 395 selected
  days, 753 clusters and ellipses, 51 compound events of Types 1-4 =
  3/3/20/25, Table 1, the power-law cutoffs, exponents and bootstrap
  p-values, and the LGCP parameters (`docs/verification_record.md`).
* Citation and archiving metadata: `inst/CITATION`, `CITATION.cff` with
  ORCID iDs and the dataset reference, `codemeta.json` and `.zenodo.json`;
  `R CMD check` on Windows, macOS and Ubuntu and the demo run in continuous
  integration on every push.

### Development notes

The scientific method and the R implementation of the five stages, the
models and their study-reproduction tests are the authors' work. The
release packaging, the from-scratch input path, the demonstration data
build, the demo, the figure styling and the documentation were written with
the assistance of an AI coding tool (Claude Code by Anthropic) operated and
reviewed by Fawaz Bouhamad; `docs/ai_assistance_record.md` lists what the
tool wrote. The demonstration data are the authors' own ERA5-derived files;
no observation or result was invented. The repository's public history
begins with this release in a single commit, at the maintainer's decision;
earlier development versions were not published.
