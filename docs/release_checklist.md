# Release and archiving checklist

The package version and its DOI are separate from the dataset's: the study's
processed input is version 1.0.0 of the Zenodo dataset 10.5281/zenodo.21717874
(concept DOI 10.5281/zenodo.21717873). Each release of this package
(`v1.0.0`, then later versions) gets its own DOI when archived.

1. Update `DESCRIPTION` (`Version`), `NEWS.md`, `CITATION.cff` (`version`),
   `inst/CITATION`, `codemeta.json` and `.zenodo.json`; regenerate the help
   pages with `roxygen2::roxygenise()`. Add `date-released` to `CITATION.cff`
   and `datePublished` to `codemeta.json` only on the day the release is made
   (they are absent while a version is pending; v1.0.0 carries 2026-10-12).
2. Run `devtools::test()`, the study reproduction
   (`SCORCH_REFERENCE_DIR=<clone of the reproducibility repository with input/tmax_processed.nc>`
   and `SCORCH_LONG_TESTS=1`), `R CMD check --as-cran` and `Rscript demo/run_demo.R`;
   record the results in `docs/verification_record.md`.
3. Commit and push to `main`; wait for the `R-CMD-check` and `demo` workflows.
4. Create the GitHub release (tag `vX.Y.Z` on the tested commit) with the
   `NEWS.md` entry as release notes, for example
   `gh release create vX.Y.Z --target <commit> --title "scoRch.generator vX.Y.Z" --notes-file <notes>`.
5. Archive on Zenodo: either enable this repository in the Zenodo GitHub
   integration (https://zenodo.org/account/settings/github/) **before**
   creating the release, so Zenodo archives it automatically with the metadata
   of `.zenodo.json`, or upload the release's source archive to a new Zenodo
   software record by hand with that metadata. A DOI cannot be withdrawn once
   published, so check the metadata first.
6. Add the software DOI to `CITATION.cff` (`identifiers:`), `inst/CITATION`,
   the README citation and `NEWS.md`; add the relation between the software
   record and the dataset record on Zenodo; commit that small follow-up.
7. For the article, fill the code metadata table from
   `softwarex_checklist.md` and cite the software DOI and the dataset DOI.

The Zenodo steps need the account owner's login; they were not done at the
time of the v1.0.0 release commit (see `verification_record.md`).
