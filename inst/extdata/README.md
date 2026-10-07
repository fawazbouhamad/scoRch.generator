# Example dataset

`example_tmax.nc` holds daily maximum 2-m air temperature (degrees Celsius,
stored as 16-bit integers with a scale factor of 0.01) for 16 x 16 one-degree
cells, 38.5-53.5 E and 22.5-37.5 N (Arabian Peninsula, Iraq and western
Iran), on every April-September day of 1996-2025 (5,490 dates, no missing
values).

**Source.** A subset of the processed SCORCH temperature dataset of Bouhamad
and Najibi, Zenodo record <https://doi.org/10.5281/zenodo.21717874> (version 1.0.0), file
`scorch_data/tmax_processed.nc`: ERA5 hourly 2-m temperature (Hersbach et
al., 2020) reduced to daily maxima at 0.25 degrees and averaged to 1-degree
cells. The subset is rounded to 0.01 degrees Celsius. The script
`data-raw/make_example_data.R` regenerates the file from the Zenodo download.
The subset lies south of 45 N, where this dataset and the study's historical,
superseded processed file (doi:10.5281/zenodo.21717752, which differs only in
the 45.5 N row) are identical, so the example data are the same for both.

**Licence.** CC BY 4.0 for the authors' processing. The file contains modified
Copernicus Climate Change Service information 2026; the underlying ERA5 data
(<https://doi.org/10.24381/cds.adbb2d47>) remain under the
[Copernicus licence](https://ecds.ecmwf.int/licences/licence-to-use-copernicus-products).
Neither the European Commission nor ECMWF is responsible for any use of the
information.
