# SoftwareX requirements checked against the official sources

Checked on 11 October 2026 against the SoftwareX *Guide for Authors*
(https://www.sciencedirect.com/journal/softwarex/publish/guide-for-authors)
and the *Original Software Publication* article template, version 6, March
2026 (https://legacyfileshare.elsevier.com/promis_misc/softwarex-osp-template.docx
and the LaTeX version `softwarex-osp-template.tex`). Quotations are from
those documents.

## Repository requirements

| Requirement (source) | Where scoRch.generator meets it |
|---|---|
| "Store your code/software in an open-access GitHub repository where it is publicly available" (guide) | https://github.com/fawazbouhamad/scoRch.generator, public |
| "README.md and LICENSE.txt files. Your README.md file should be well-written, explaining the use, installation, and purpose of your proposed software" (guide); "GitHub repositories must have a well-documented README.md file, and a Licence.txt file" (template) | `README.md` (purpose, installation, quick start, input formats, settings, outputs, verification, citation) and `LICENSE.txt` (GPL-3) |
| "Source code in a repo/src directory" (guide) | An R package keeps its source in `R/` by the R standard (`R CMD check` requires it); the README points to the files. If the editorial office insists on `src/`, a `src/README.md` pointer can be added without moving the code |
| "All software and code must be open source and released under a recognized legal license ... such as Apache License, GNU General Public License (GPL) or MIT License" (guide, template) | `License: GPL (>= 3)` in `DESCRIPTION`, GPL-3.0-or-later in `CITATION.cff` |
| "We only accept GitHub repositories within Metadata Tables" (template) | the C2 link below is the GitHub repository |
| Research data: "Deposit your research data in a relevant data repository. Cite and link to this dataset in your article" (guide) | the study input is the Zenodo dataset 10.5281/zenodo.21717874, cited in `CITATION.cff`, the README and the reproducibility repository |
| "Declaration of generative AI use ... Authors must declare the use of generative AI tools in the manuscript preparation process" (guide) | applies to the article text; the AI assistance used for the release packaging is recorded in `NEWS.md` and the README so the declaration can be written accurately |
| Software citation: "If the software repository you used supplied a DOI or another Persistent IDentifier (PID), please add a reference for your software" (template) | `CITATION.cff`, `inst/CITATION`, `codemeta.json` and `.zenodo.json` are ready; the Zenodo DOI is added after the GitHub release is archived (`release_checklist.md`) |

The guide does not prescribe a build system, a test framework or a
documentation format beyond the README. The template limits the article to
4,000 words, six figures and the five mandatory sections (Motivation and
significance; Software description; Illustrative examples; Impact;
Conclusions), with the code metadata table below.

## Code metadata table (template Table 1, "Code metadata (mandatory)")

| Nr | Code metadata description | Value for scoRch.generator |
|---|---|---|
| C1 | Current code version | v1.0.0 |
| C2 | Permanent link to code/repository used for this code version | https://github.com/fawazbouhamad/scoRch.generator (release tag `v1.0.0`) |
| C3 | Legal code license | GNU General Public License v3.0 or later (GPL-3.0-or-later) |
| C4 | Code versioning system used | git |
| C5 | Software code languages, tools and services used | R (>= 4.1); packages dbscan, ncdf4, spatstat.geom, spatstat.model, maps, yaml; optionally ecmwfr and httr for the download path from the Copernicus Climate Data Store; testthat for tests; GitHub Actions for continuous integration |
| C6 | Compilation requirements, operating environments and dependencies | pure R, no compilation; Windows, Linux and macOS (checked by `R CMD check` on all three in continuous integration); dependencies installed automatically by `remotes::install_github()` |
| C7 | If available, link to developer documentation/manual | https://github.com/fawazbouhamad/scoRch.generator/blob/main/README.md (plus the R help pages, `?run_scorch`, and `demo/`) |
| C8 | Support email for questions | the corresponding author's address (entered in the submission) |

## Illustrative example for the article

`demo/run_demo.R` with `demo/README.md` is the illustrative example: the
demonstration dataset shipped with the package (ERA5-derived daily maximum
temperature on 1,800 one-degree cells between 25 N and 50 N and 130 W and
58 W, the contiguous United States with its surroundings, 1996-2025, a
region other than the study's), one configuration file, one command, the
printed Table 1, one real heat wave (28 June to 4 July 2012) traced from the
temperature data through the five catalogs to its figure, and the result
figures in `demo/expected_output/`. `demo/cds_processing_example.R` shows
the from-scratch path (a Climate Data Store download reduced to 1-degree
cells) on a shipped CDS file, without a CDS account.

## Points to state in the article

- The package is the R implementation of the method of a manuscript in
  preparation; it has been used for that study and not yet by outside groups,
  so there are no download or user statistics to report.
- The package reproduces the study's published catalogs, tables and model
  results from the archived input (`docs/verification_record.md`).
- The hourly ERA5 preprocessing of the study was done outside the package;
  `read_era5()` reproduces it from raw ERA5 files, as documented in the README.
