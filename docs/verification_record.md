# Verification record, 12 October 2026

Package: scoRch.generator 1.0.0, the tree of the single root commit
released on 12 October 2026. (An earlier packaging of the code with the
study's own region as example data was checked the same way on 11 October
2026; the repository's public history starts with this release.)
Machine: Windows 11, R 4.5.1 (x86_64-w64-mingw32), testthat 3.3.2, ecmwfr
2.0.3, no Rtools, no LaTeX, no pandoc.
Reference for the study reproduction: a clone of the research record
https://github.com/fawazbouhamad/compound-heatwave-typologies-SCORCH at its
initial commit `fdfd5619d1587b09a1459c7ddb8dceece60a1e9e`, with the Zenodo
file placed at `input/tmax_processed.nc` (version 1.0.0 of
doi:10.5281/zenodo.21717874; `SCORCH_data.zip` MD5
`80772df9410306cbc419191d0dcb824c`, `tmax_processed.nc` SHA-256
`fc080880b6f2065fb5eec9fe9dce71abdfdc44a72d1ae91e50abdd278fadaa90`).

## 1. Reproduction of the study

Command, from the package root:

```r
Sys.setenv(SCORCH_REFERENCE_DIR = "<clone>", SCORCH_LONG_TESTS = "1")
devtools::test(filter = "reference-study|models")
```

Result: 76 expectations passed, 0 failed, 1 skipped (the optional audit of
the superseded historical analysis, `SCORCH_HISTORICAL_REFERENCE_DIR` not
set): `test-reference-study.R` 45 expectations and `test-models.R` 31,
including the 5000-repetition bootstrap. The scientific code did not change
since the check of 11 October 2026, and the comparison is the same:

| Stage | Package result | Compared with (research record) | Agreement |
|---|---|---|---|
| Input | 1,800 cells, 15,738 dates | dataset description | exact |
| 1 Local heatwaves | 176,061 events | `output/catalogs/01_heatwave_events/heatwave_events.csv`: ids, cells, dates, durations, peak dates and temperatures | exact |
| 2 Regional days | threshold 371 cells, 395 days | `output/catalogs/02_regionally_extensive_heatwaves/selected_day_cells.csv` | exact |
| 3 Clusters | 753 clusters | `output/catalogs/03_extreme_heatwave_clusters/cluster_cells.csv`: labels and core cells | exact |
| 4 Ellipses | 753 ellipses | `output/catalogs/04_extreme_heatwave_ellipses/ellipses.csv` | axes, areas and azimuths within 1e-9; weighted centroids within 1e-7 (single precision) |
| 5 Compound events | 51 events, Types 1-4 = 3, 3, 20, 25 | `output/catalogs/05_compound_heatwave_events/compound_events.csv` and `output/tables/table_1.csv` | exact |
| Power law | daily: A_min 4,854,155.16 km2, alpha 10.5208, p 0.2128; events: A_min 3,585,652.40 km2, alpha 5.3481, p 0.336 | `supporting_files/additional_results/modeling/power_law/power_law_fits.csv` | n_tail and n_exceed exact; x_min, alpha and p within 1e-9 |
| LGCP | 7 fitted parameters; centroids in the intensity zones 267, 189, 29 and 537, 326, 45 | `supporting_files/additional_results/modeling/lgcp/lgcp_parameters.csv` and the study's counts | parameters within 1e-6; counts exact |

## 2. Test suite

`devtools::test()` on the same tree: 605 expectations passed, 0 failed,
0 warnings, 4 skipped (the three environment-gated study tests above and the
live CDS request, which runs only with `SCORCH_CDS_LIVE=1`), 11 files.
`test-workbooks.R` checks the XLSX writer (every value and date read back,
blank cells for missing values distinct from zero, frozen and filtered
header, the explicit errors for a sheet beyond the row limit and for an
unwritable file, the workbook and sheet layout of a run, the display
formats, the archive check with crafted defects, and the UTF-8 README in a
session switched to the C locale); the workflow and ERA5 tests read the
workbooks and `README.txt`
of complete, incomplete and LGCP-less runs. The
CDS tests were also run with the keychain made unavailable
(`R_KEYRING_BACKEND=env`, the condition of the continuous-integration
runners): 104 expectations passed, 0 failed, 0 warnings, 1 skipped (the live
request). The
from-scratch path is tested against a fake CDS (`tests/testthat/test-cds.R`:
request planning including a November-March season, caching, resuming a
queued request, re-submitting a rejected or dropped one, the configuration
switch, `write_tmax()` round trips, the shipped CDS file reduced to the
cells of the demonstration data, and the cache safety: a changed area, an
extended partial month, other season months, yearly instead of monthly
requests, a file with the right name but the wrong grid or dates, a missing
or foreign request record, an empty or unreadable file and a stale job note
are all requested anew, a delivered file that does not match its request is
an error, and area edges that are not multiples of 0.25 degrees are refused
before anything is submitted). `test-figures.R` checks the state-outline
rule and that the event snapshot figures size their canvas by the panels
they draw.

## 3. R CMD check

```
R CMD build --no-build-vignettes --no-manual scoRch.generator
R CMD check --no-manual --ignore-vignettes --as-cran scoRch.generator_1.0.0.tar.gz
```

(`--no-manual` and the vignette flags because this machine has no LaTeX or
pandoc; the package has no vignettes.)

Status: 1 NOTE, the standard note for a package that is not on CRAN
(`New submission`, which also reports the tarball size, 13.6 MB, because of
the demonstration data); `checking installed package size` is an INFO line
(13.3 MB, of which `extdata` 12.4 MB). Examples ran in 24 s, the `donttest`
examples in 85 s and the tests inside the check in 108 s, all OK (the run of
12 October 2026 on the published tree with the unlettered figures; tarball MD5
`12b5ab3a268aac4404e88abeb5a755ba`). The
help-page examples of the stage functions use the last eleven seasons of the
demonstration data so that each stays under five seconds.

## 4. Demonstration data

`data-raw/make_demo_data.R` checked all 30 yearly source files (grid,
dates, units, missing values, metadata), recomputed eight cell means by
hand from the raw 0.25-degree files (exact to 1e-5), wrote
`inst/extdata/north_america_tmax.nc` (1,800 cells, 5,490 dates, 12.4 MB,
MD5 `526639b3a874be74fce28cee968ef36b`, Tmax -13.80 to 49.20 degC) and read
it back within 0.005 degC. Independently of the package, the ARCO-derived
daily maxima were compared with the CDS for the window 34-44 N, 104-94 W:
2012 against the CDS daily-maximum product and 1987-1990 against daily
maxima computed from CDS hourly data; the largest difference at any point
and day was 0.0012 degC.

## 5. Demonstration and example

`Rscript demo/run_demo.R` from the repository top with the installed 1.0.0
package: 43 s in all on the published tree (the analysis with the study's
5,000 bootstrap repetitions 16 s, the eight workbooks with their archive
checks 7 s, the nine figures at 600 or 500 dpi 10 s, the traced event and
the stage-by-stage repeat the rest);
65,790 local heatwaves, regional threshold 353 cells, 140 selected days, 376
ellipses, 29 compound events (Types 1-4 = 1, 4, 20, 4); LGCP fitted; all
nine figures generated and inspected (the Type 3 figure shows the traced
event of June 2012 and the August 2023 event in the 2 x 2 layout of the
study's Figure 6 without row letters; no figure carries panel letters; the
legend of the five-map figure sits below its first map; the dates of the
Type 4 panels sit above the maps); the
traced event is 28 June to 4 July 2012. The eight workbooks and the
`README.txt` of the run (with the traced event) are the files in
`demo/expected_output/`; `demo/compare_output.R` read every sheet of every
workbook back and found all 16 sheets the same (relative tolerance 1e-6,
1e-3 for the LGCP workbook) and the README the same apart from the run
time. Before the switch to workbooks, every sheet was compared with the
CSV file the previous tree wrote for the same run: the same rows,
columns and missing values, no numeric difference (openxlsx2 stores the 15
significant digits that `write.csv()` also wrote). The archives are zipped by
the zip package, never by a system program, and every workbook's archive is
checked after writing (relationship targets, sheet dimensions, sheet
names); as an external check on this machine, the eight produced and the
eight shipped workbooks were opened with Python openpyxl 3.1.2 in standard
and read-only mode, each with its full dimension (A1:L65791 for the
heatwave events). The demo and the comparison were also run in a session
started with `LC_ALL=C.UTF-8`, which R on Windows cannot set and which leaves
the session in the C locale: `README.txt` keeps its degree signs and the
comparison passes.
`Rscript demo/cds_processing_example.R`: under one second; the shipped CDS
file reduces to 100 cells that differ from the demonstration data by at
most 0.0054 degC.

## 6. Live CDS request

`fetch_era5_daily_tmax(area = c(44, -104, 34, -94), start = "2012-07-01",
end = "2012-07-31", months = 7)`, one monthly request, was submitted through
the new code on 12 October 2026 at 08:35 local time with the token read
from the keychain (CDS job `c43e8c81`). It waited 34 minutes in the CDS
queue and was delivered at 09:10 (0.12 MB). Read with `read_era5()` on the
native grid, its 1,681 points and 31 days are identical to July of the
shipped `cds_daily_tmax_2012_great_plains.nc` (largest difference
0.000000 degC), and it reduces to the same 100 one-degree cells. The job was
deleted from the CDS after the download; no other request was made. The
request-specific cache names and records were added after this run, so the
file carries the earlier month-only name; the fake-CDS tests cover the new
naming.

## 7. Continuous integration

Every push runs `R CMD check` on macOS, Windows and Ubuntu
(`.github/workflows/R-CMD-check.yaml`) and the demo plus the example on
Ubuntu with the workbook, README and figure comparisons of
`demo/compare_output.R` (`.github/workflows/demo.yaml`):
https://github.com/fawazbouhamad/scoRch.generator/actions.

The release tree was published four times on 12 October 2026, each time as
the single root commit of the repository, the earlier commit kept in a local
backup and replaced with a lease-protected force push after a check that no
archive or citation of it existed.

- The first publication (commit `67921cd`, 15:49 UTC) failed this check on
  all three platforms: the last expectation of the caching test in
  `tests/testthat/test-cds.R` called `fetch_era5_daily_tmax()` outside the
  fake CDS, so it reached the real backend, which looked for the CDS token
  before anything else. On this machine the token is in the keychain and
  the expectation passed; on the token-less runners the call raised the
  keychain error instead of the expected period error, and the Ubuntu
  runner also logged keyring backend warnings. The expectation now runs
  against a fake backend without a token and `fetch_era5_daily_tmax()`
  validates the period before it looks for the token.
- The second publication (commit `70db257`, 16:11 UTC) passed `R CMD
  check` on Ubuntu, Windows and macOS and the demo workflow. Its runs
  wrote the catalogs, tables and model results as CSV files with a text
  summary; at the maintainer's decision it was replaced the same day by a
  tree whose runs write the XLSX workbooks and the README.txt of section 5.
- The third publication (commit `6ec1adb`, 20:50 UTC) passed every check.
  The maintainer's independent rerun of it then found that the workbooks,
  written with openxlsx 4.2, could not be opened by Python's openpyxl (every
  sheet carried relationships to drawing parts that did not exist and
  declared a dimension of A1) and that README.txt lost its degree signs
  in a session whose locale had fallen back to C. The published tree
  writes the workbooks with openxlsx2, checks every written archive, and
  writes README.txt in UTF-8; the scientific computations are unchanged,
  and sections 2, 3 and 5 are the reruns on that tree (section 2 also with
  the keychain made unavailable, as on the runners).
- The runs of the published commit are linked from the release page; the
  superseded commits and their runs were superseded, not passed.

## 8. Not verified here

- Checks on macOS and Linux: by continuous integration only.
- A full from-scratch download of a large area over many years: only one
  monthly request was made live; the queue behaviour described in the README
  is what this account experienced on 11-12 October 2026.
- The Zenodo software DOI of the next release has not been minted
  (`release_checklist.md`).
