# Contributing to scoRch.generator

Thank you for your interest. The package is small on purpose; please keep
contributions in that spirit.

**Report a problem or ask for support.** Open an issue at
<https://github.com/fawazbouhamad/scoRch.generator/issues> with your R version,
the package version (`packageVersion("scoRch.generator")`), the configuration
file and the message you saw. Questions about the science of the method go to
the authors (see the README).

**Propose a change.** Open an issue first for anything that changes a
calculation, a default or the configuration file: the defaults are the
settings of the published study and are not changed lightly. For code:

1. Fork the repository and create a branch.
2. Keep functions short and comments plain; follow the existing style.
3. Add or update tests in `tests/testthat` and run them with
   `devtools::test()`; run `devtools::check()` before opening the pull request.
4. Describe in the pull request what changed and why.

Changes to the scientific calculations must keep the study reproduction in
`tests/testthat/test-reference-study.R` passing (set `SCORCH_REFERENCE_DIR`
to a copy of the reproducibility repository to run it).
