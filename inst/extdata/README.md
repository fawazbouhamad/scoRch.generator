# Demonstration data

Two NetCDF files derived from ERA5, the ECMWF reanalysis (Hersbach et al.,
2020), through two different distribution channels. They are real reanalysis
data, not synthetic, and a regional sample chosen for the demonstration, not
an analysis of all of North America.

## north_america_tmax.nc: daily maximum temperature on 1-degree cells

| | |
|---|---|
| Area | 25-50 N and 130-58 W: the contiguous United States with southern Canada (to 50 N), northern Mexico, the Great Lakes and the adjacent Pacific, Atlantic and Gulf of Mexico waters; sea cells are included, as in the study region of the SCORCH paper |
| Grid | 25 x 72 = 1,800 one-degree cells with centres at 129.5-58.5 W (`lon` -129.5 to -58.5) and 25.5-49.5 N; a cell covers [k, k + 1) degrees in both directions |
| Dates | every April-September day of 1996-2025: 5,490 dates, 9,882,000 values, none missing; `time` is days since 1996-01-01 |
| Variable | `tmax`, daily maximum 2-m air temperature in degrees Celsius, stored as 16-bit integers with a scale factor of 0.01 (fill value -32768); range -13.80 to 49.20 degC |
| File | 12.4 MB (12,445,463 bytes), MD5 `526639b3a874be74fce28cee968ef36b` |

**Source.** ERA5 hourly 2-m temperature read from the ARCO-ERA5 archive on
Google Cloud (Carver and Merose, 2023; `gs://gcp-public-data-arco-era5`, an
analysis-ready copy of the ERA5 data of the Copernicus Climate Change
Service) and reduced by the authors, before this package, to the daily
maximum of each UTC calendar day on the 0.25-degree ERA5 grid: one file per
year, `<year>_daily_Tmax_NA.nc`, 289 x 101 points, variable `Tmax_C` in
degrees Celsius. The MD5 checksums of the 30 yearly files used here are in
[`data-raw/arco_na_manifest.txt`](../../data-raw/arco_na_manifest.txt).

**Processing** ([`data-raw/make_demo_data.R`](../../data-raw/make_demo_data.R)):
every yearly file is checked (grid, dates, units, no missing values);
`read_era5()` averages the 4 x 4 points of every complete 1-degree cell
[k, k + 1), dropping the points on the edges 50 N and 58 W that begin
incomplete cells; eight cell means are recomputed by hand from the raw
files; `write_tmax()` writes the result rounded to 0.01 degC.

**Verification against the CDS.** For the window 34-44 N, 104-94 W, the
ARCO-derived daily maxima agree with the CDS daily-maximum product for 2012
and with daily maxima computed by `read_era5()` from CDS hourly data for
1987-1990 at every point and day to within 0.0012 degC (float32 rounding),
which confirms the UTC day boundary and identical ERA5 values.

## cds_daily_tmax_2012_great_plains.nc: a file as the CDS delivers it

| | |
|---|---|
| Product | *ERA5 post-processed daily statistics on single levels from 1940 to present* (`derived-era5-single-levels-daily-statistics`, [doi:10.24381/cds.4991cf48](https://doi.org/10.24381/cds.4991cf48)): daily maximum of the hourly 2-m temperature, time zone UTC+00:00, 1-hourly frequency |
| Request | area North 44, West -104, South 34, East -94 (41 x 41 points at 0.25 degrees), April-September 2012, made on 11 October 2026 with the CDS API; `fetch_era5_daily_tmax(area = c(44, -104, 34, -94), start = "2012-04-01", end = "2012-09-30", period = "year")` makes the same request |
| Contents | variable `t2m` in kelvin, 183 daily values, as downloaded, unchanged |
| File | 556,926 bytes, MD5 `d4a307cec120ca38ef41a1f753f8c194` |

It is the input of `demo/cds_processing_example.R` and of the tests of the
from-scratch path, which reduce it to 10 x 10 cells and compare them with the
same cells of `north_america_tmax.nc`.

## Licence and attribution

Both files contain modified Copernicus Climate Change Service information
2026; neither the European Commission nor ECMWF is responsible for any use
that may be made of the information they contain. The CDS catalogue lists the
ERA5 datasets under the Creative Commons Attribution 4.0 licence (checked on
12 October 2026 through the CDS catalogue API), and the ARCO-ERA5 archive
redistributes the ERA5 data under the same Copernicus terms (its code is
Apache 2.0). The authors' processing is CC BY 4.0. Please cite:

- Hersbach, H., et al. (2020). The ERA5 global reanalysis. *Quarterly
  Journal of the Royal Meteorological Society*, 146, 1999-2049.
  [doi:10.1002/qj.3803](https://doi.org/10.1002/qj.3803)
- Carver, R. W., and Merose, A. (2023). ARCO-ERA5: An Analysis-Ready
  Cloud-Optimized Reanalysis Dataset. 22nd Conference on Artificial
  Intelligence for Environmental Science, American Meteorological Society,
  Denver, CO, paper 4A.1. <https://github.com/google-research/arco-era5>
- the CDS dataset DOI above for the second file.
