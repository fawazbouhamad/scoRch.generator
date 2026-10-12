# Record of AI assistance

This file records where an AI coding tool helped with this package, so that
the use can be described accurately (for example in the generative-AI
declaration of a SoftwareX article). The tool was Claude Code (Anthropic),
running the model Claude Fable 5.1, operated in interactive sessions by Fawaz
Bouhamad, who gave the briefs, supplied the data access, reviewed the output
and committed it under his own Git identity. No commit carries an AI
co-author trailer; every commit is authored by Fawaz Bouhamad.

## Before the packaging sessions

The scientific method, the R implementation of the five stages and the
models (`R/`), the study-reproduction tests and fixtures, and the original
documentation were written by the authors. The authors have used AI coding
assistance in their own development work; this record covers the sessions
below, which were run as documented tasks.

## Session of 11 October 2026: release packaging

Release packaging prepared with the tool: citation and archiving metadata
(`inst/CITATION`, `CITATION.cff`, `codemeta.json`, `.zenodo.json`), the
demo walk-through of that version, `docs/softwarex_checklist.md`,
`docs/release_checklist.md`, `docs/verification_record.md`, README,
`CONTRIBUTING.md` and `NEWS.md` text, the `LICENSE.txt` rename, the
`data-raw/make_test_fixtures.R` and `tests/testthat/test-reference-study.R`
changes that read the public research record's layout, and the demo GitHub
Actions workflow. No scientific calculation changed. The tool also ran the
tests, `R CMD check` and the study reproduction and wrote the verification
record from their output.

## Sessions of 12 October 2026: two input paths, the North American demonstration, figures, release

Brief from the maintainer: offer two configuration-driven ways to provide
the temperature data (from scratch through the Copernicus Climate Data
Store with a token kept in the local keychain, or a ready processed file);
replace the demonstration (previously a 16 x 16 cell subset of the study's
own Eastern Mediterranean and Middle East input) with one North American
demonstration built from the authors' existing ERA5-derived daily files;
document the provenance; trace one real dated event from the temperature
data to its figure; keep the scientific algorithms unchanged; one commit,
one push after review.

Written by the tool in that session (first versions, reviewed by the
maintainer):

- `R/cds.R`, `R/cds_backend.R`: `fetch_era5_daily_tmax()` (request
  planning month by month or year by year, including seasons across the
  new year; request-specific cache names and request records; validation
  of a cached or delivered file's grid and dates before any reuse, added
  after the maintainer's review found that the first version keyed the
  cache by month only; resuming a queued request; re-submitting a rejected
  or dropped one; the keychain check that never reads the token into the
  package's own code) and the small interface to `ecmwfr` and `httr`.
- `R/write_tmax.R`: `write_tmax()`.
- The `input: source` switch and the `input: cds` settings in
  `inst/scorch_config.yaml`, their validation in `R/config.R`, and the
  from-scratch branch of `read_configured_input()` in `R/era5.R` with its
  run message in `R/run.R`.
- `tests/testthat/test-cds.R`: a fake CDS for offline tests of planning,
  caching, resuming, the writer, the configuration switch and the shipped
  CDS sample, plus the opt-in live request.
- `data-raw/make_demo_data.R`: validation of the 30 yearly ARCO-ERA5-derived
  files and the build of `inst/extdata/north_america_tmax.nc` with
  `read_era5()` and `write_tmax()`, with hand-recomputed cell means and
  the checksum manifest `data-raw/arco_na_manifest.txt`. The yearly source
  files themselves were produced earlier by the authors, outside this
  package.
- `demo/run_demo.R` (including `trace_event()`), `demo/cds_processing_example.R`,
  `demo/scorch_config.yaml`, `demo/README.md`, the choice of the traced
  event (the heat wave of 28 June to 4 July 2012, selected from the actual
  results and checked against NOAA's June 2012 national climate report).
- `R/figures.R`: `overlaps_us_states()` and the state outlines in
  `map_outlines()`; after the maintainer's review of the figures, the plain
  basemap style of the event snapshots, the dates written above the panels,
  the lettered rows, canvas sizes that follow the panels drawn and the
  per-figure resolution (presentation only), with
  `tests/testthat/test-figures.R`.
- Test updates: the expectations of `tests/testthat/test-input-config.R`,
  `test-workflow.R` and `test-era5.R` that referred to the old example data
  were replaced by values taken from the actual run on the new data, and
  the ERA5 round-trip test was restricted to a 12 x 12 cell window.
- Documentation of the change: `inst/extdata/README.md`, the README
  sections on the two paths and the demonstration, `NEWS.md`, the `docs/`
  updates, the paper draft sentences that described the old example,
  `CONTRIBUTING.md`, and this record.
- The tool ran the demo, the example, the test suite, `R CMD check`, the
  study reproduction and one live CDS request, and wrote the expected
  outputs and the verification record from the actual output.

Credentials: the maintainer's CDS token, already present on the
maintainer's computer in the file that the CDS Python client reads, was
copied into the operating-system keychain entry that `ecmwfr` uses by a
local script that printed nothing but the token's length; the tool never
displayed, logged or stored the token anywhere else, and the repository
holds no credential.

Earlier in the same session the tool had started a different demonstration
(a 10 x 10 degree Great Plains box downloaded from the CDS); the maintainer
stopped it after the CDS queue proved too slow. Its only remaining trace is
the shipped CDS sample file for 2012, downloaded on 11 October 2026 with
the CDS Python client and kept unchanged.

Not written by the tool: the scientific code of the five stages and the
models (unchanged in these sessions), the study fixtures, the typology and
workflow artwork, and the ERA5 data themselves.

## Session of 12 October 2026, later: workbook output

At the maintainer's request the tool replaced the CSV and text output of a run
with eight XLSX workbooks (`R/workbooks.R`, with openxlsx2), a plain-language
`README.txt` that absorbs the former run summary and the demo's event trace
(`R/readme.R`), the matching changes of `run_scorch()` (`R/run.R`), the demo
script and configuration, the comparison script `demo/compare_output.R`
and the demo workflow, the tests (`tests/testthat/test-workbooks.R` and the
converted workflow and ERA5 tests), the documentation, and the layout of the
five-map figure, whose bottom panel is now centred (`five_map_layout()` in
`R/figures.R`). The scientific computations were not changed: the tool
checked every sheet of the demo run against the previous CSV output row by
row (same rows, columns and missing values, no numeric difference) and the
top four panels of the figure pixel by pixel.

After the maintainer's independent rerun found that the files written with
openxlsx 4.2 could not be opened by Python's openpyxl (relationships to drawing
parts that did not exist and a declared dimension of A1) and that
`README.txt` lost its degree signs in a session whose locale had fallen back
to C, the tool moved the writer to openxlsx2, added a check of every written
archive (relationship targets, sheet dimensions, sheet names) with tests,
and made `README.txt` a UTF-8 file in every locale, read as UTF-8 by the demo
and the comparison script. At the maintainer's request the tool then removed
the alphabetic panel labels from all nine figures and moved the legend of
the five-map figure below its first map.

## How the record relates to the Git history

At the maintainer's decision, the public history of the repository was
collapsed on 12 October 2026 to a single root commit holding the complete
1.0.0 release, authored and committed by Fawaz Bouhamad; the two earlier
commits (an initial import and a packaging commit of 11 October 2026 that a
first v1.0.0 tag had pointed to, with the study's own region as example
data) were replaced before any archive or citation of them existed, and
are kept in a local backup. The sessions above therefore do not map onto
commits; this record is the account of the tool's part in the work.

The root commit was built twice. The continuous-integration check of the
first publication (12 October 2026, 15:49 UTC) failed on all three
platforms at one expectation of `tests/testthat/test-cds.R` that the tool
had written outside the fake CDS backend, so that it depended on the
maintainer's keychain token and passed only on that machine. The tool
rewrote the expectation against the fake backend, moved the period
validation of `fetch_era5_daily_tmax()` ahead of the token check, reran the
tests and `R CMD check`, and rebuilt the root commit, which the maintainer
republished in place of the first; no credential was added to the
continuous-integration configuration.
