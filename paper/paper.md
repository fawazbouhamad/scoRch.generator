---
title: 'scoRch.generator: An R package for the spatiotemporal classification of regional compound heatwaves'
tags:
  - R
  - heatwaves
  - climate extremes
  - spatial clustering
  - point processes
authors:
  - name: Fawaz Bouhamad
    corresponding: true
    affiliation: 1
  - name: Nasser Najibi
    affiliation: 1
affiliations:
  - name: Department of Agricultural and Biological Engineering, University of Florida, Gainesville, Florida, United States
    index: 1
date: 6 October 2026
bibliography: paper.bib
---

# Summary

Heatwaves that cover large regions for several days cause the greatest harm,
yet most software describes heatwaves one location at a time. `scoRch.generator`
implements SCORCH (Spatiotemporal Classification of Regional Compound
Heatwaves), the method of our study of compound space-time heatwave
typologies [@bouhamad_najibi_scorch], as an R package for any gridded daily
maximum temperature dataset. It detects local heatwaves in every grid cell,
selects the days on which heatwaves cover an unusually large part of the
region, groups the heatwave cells of those days into spatial clusters with
DBSCAN [@ester1996], describes each cluster by a principal-component ellipse
with a temperature-weighted centroid, and classifies runs of consecutive days
into four types: a single widespread structure, several structures on one day,
consistently single or multiple structures over days, or varying daily cluster
counts. The largest ellipse areas are fitted with a power law [@clauset2009]
and the centroids with a log-Gaussian Cox process [@moller1998], giving a map of where large
heatwaves concentrate. A user supplies ERA5 2-m temperature as downloaded
(the package reduces it to daily maxima on 1-degree cells, as in the study)
or a file of daily maximum temperature, edits one commented
configuration file and runs one function; the package writes five catalogs,
a summary table, the model results and descriptively named result plots for
the user's own region and period.

# Statement of need

The space-time structure of regional heatwaves is studied with increasingly
diverse and ad hoc code: per-cell indices [@perkins2013], contiguous-area
measures [@lyon2019; @keellings2020] and one-off clustering scripts. Such
code is rarely reusable, and the many conventions that decide the result
(which quantile rule, which neighbourhood distance, how border cells are
assigned, how single cool days inside a hot spell are treated) are seldom
documented. `scoRch.generator` packages the complete SCORCH chain with its
conventions fixed and documented, so that climate scientists, hydrologists
and risk analysts can apply the published typology to their own regions with
nothing more than R. The target users are researchers and students with
gridded temperature data and basic R skills; the stage functions also serve
developers who want to reuse one step, such as the regional-day selection or
the ellipse fitting, in their own work.

# State of the field

`heatwaveR` [@schlegel2018] is the standard R tool for detecting heatwaves and
marine heatwaves in a single daily series with the Hobday definition
[@hobday2016]; applied to a grid it describes each cell separately and has no
notion of spatial extent or structure. Climate-index libraries such as
`xclim` [@bourgault2023] likewise compute per-cell heatwave frequency and
duration. Feature-tracking frameworks built for other phenomena, such as
TempestExtremes [@ullrich2021] and tobac [@heikenfeld2019], can delineate and
follow contiguous warm areas but do not provide a regional-day criterion, a
data-driven choice of clustering settings, ellipse descriptors or a typology.
General clustering and point-process software exists in R: `dbscan`
[@hahsler2019] implements DBSCAN efficiently and `spatstat` [@baddeley2005;
@baddeley2015] fits log-Gaussian Cox processes. `scoRch.generator` builds on
these two packages rather than reimplementing them, and contributes what no
existing package offers: the regional selection, the parameter search and
pooling rules, the ellipse geometry and weighting, the typology, and the
reproducible link between all of them.

# Software design

The guiding principle was that a beginner should understand the package from
the README and one configuration file. The public interface is therefore
small: the settings of the study ship as one commented YAML file, the single
source of the defaults, and `write_scorch_config()` writes an editable copy
of it; `run_scorch()` runs everything and writes the
results to `catalogs/`, `tables/`, `models/` and `figures/`, and
`scorch_figure()` redraws one result plot. Underneath, one function per stage
(`read_tmax()`, `detect_heatwaves()`, `select_regional_days()`,
`cluster_heatwaves()`, `fit_ellipses()`, `classify_events()`,
`fit_power_law()`, `fit_lgcp()`) returns plain data frames, so the chain can
be run and inspected step by step.

Faithfulness to the study took precedence over convenience. The package
keeps the study's numerical conventions: the "higher" quantile rule of the
regional threshold, distances in grid-cell units, the order in which cells
are scanned (which decides the cluster a border cell joins), single-precision
temperature weights for the centroids, the full two-sided Kolmogorov-Smirnov
distance and the semiparametric bootstrap of @clauset2009 with its exact
sequence of random draws, and the minimum-contrast fit of the Cox process.
Each stage was compared with the study's independent reproducibility
workflow: from the study's final processed input the package reproduces all
176,061 local heatwaves, 395 selected days, 753 clusters and ellipses, 51
compound events, Table 1, the power-law cutoffs, exponents and p-values, and
the Cox-process parameters to better than $10^{-6}$.

The final processed input corrects a boundary error in the study's first
preprocessing. The historical ERA5 extraction ended at 45.0° N, while the
1° aggregation retained a cell centred at 45.5° N, so that northernmost row
averaged only the four 0.25° points at 45.0° N. The final analysis uses
complete 1° cells built from the full 4 x 4 set of native 0.25° ERA5 points,
the same rule that the package applies to raw ERA5 input. The correction
changes only the 50 cells of that row; it alters some event classifications
and summary statistics (three of the 51 compound events change type) but not
the principal qualitative conclusions. The historical input and results remain
archived for audit, and the package's reference tests can reproduce both
versions; the corrected version is the reference.

At the same time nothing about the study's region is hard-coded. Grid
spacing, extent, dates and map limits come from the input; the warm season is
a list of months; heatwaves never cross real calendar gaps; cells missing on
every date (sea cells of a land-only dataset) are dropped, while any other gap
stops the run with a plain-language message rather than being filled
silently; Kelvin is converted only when declared. Plots adapt to the event
types present, and representative events for the snapshot plots are chosen
by a documented rule (the longest event of each type) that the user can
override. The dependency set is deliberately small (`ncdf4`, `dbscan`,
`spatstat`, `maps`, `yaml`); the equal-area projection needed by the Cox
process is implemented in a few lines of R so that no GDAL or PROJ
installation is required, and all plots use base graphics. A 16 x 16 cell
subset of the study data ships with the package so that the whole workflow
runs in seconds, with a clearly labelled fast mode for the bootstrap.

# Research impact statement

The package is the reference implementation of the SCORCH method. It
reproduces every catalog, table and model result of the companion study
[@bouhamad_najibi_scorch] from the study's final processed ERA5 temperature
file [@hersbach2020], and that reproduction is part of its test suite, so the
published numbers can be regenerated by anyone with the study's data and
one command. The study itself is in preparation, and the package has not yet
been used by groups outside the authors' laboratory; its reproducible
materials (example data, fixtures from the study catalogs, continuous
integration) are in place for that use.

# Acknowledgements

[Financial support, if any, to be stated by the authors.] The example data
contain modified Copernicus Climate Change Service information (ERA5).

# References
