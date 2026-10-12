scoRch.generator 1.0.0 results
Run started 2026-10-12 19:36:18, finished in 33 seconds.

INPUT
  Source: inst/extdata/north_america_tmax.nc
  Area: 1800 cells on a 1 x 1 degree grid, 129.5°W to 58.5°W and 25.5°N to 49.5°N
  Period: 5490 dates from 1996-04-01 to 2025-09-30, warm-season months 4 5 6 7 8 9

MAIN SETTINGS
  Local heatwave: at least 3 consecutive days with at least 3 of them at or above the cell's 95th percentile of daily maximum temperature (days below it inside the run are bridged).
  Regionally extensive day: a day whose number of heatwave cells reaches the 97.5th percentile of all days (353 cells in this run).
  Clustering: DBSCAN of the heatwave cells of each selected day; eps candidates 1, 1.5, 2, 2.5, 3, 3.5, 4 grid cells, min_samples candidates 4, 5, 6, 7, 8, 9, 10, 11, 12; one pair is chosen for each run of consecutive days.
  Ellipses: principal axes of each cluster scaled by 1.25, centroids weighted by temperature.
  Power law: 5000 bootstrap repetitions (seeds 20261020 for daily maxima, 20261120 for event maxima).
  LGCP: covariates lon, lat, mean_tmax, std_tmax; 25 km raster; 80 km window margin.
  Figures: representative events chosen in the configuration: Type 3 2012-06-28, 2023-08-04.

RESULTS
  Stage 1  Local heatwaves: 65790
  Stage 2  Regionally extensive days: 140 of 5490 days (regional threshold 353 heatwave cells)
  Stage 3  Clusters: 376
  Stage 4  Ellipses: 376
  Stage 5  Compound heatwave events: 29
           Type 1: Widespread (Isolated): 1 event over 1 day, longest 1 day, 1 ellipse per event on average
           Type 2: Spatially Clustered: 4 events over 4 days, longest 1 day, 3.5 ellipses per event on average
           Type 3: Temporally Clustered: 20 events over 105 days, longest 28 days, 14.4 ellipses per event on average
           Type 4: Compound Clustering (Multi-Type): 4 events over 30 days, longest 16 days, 18.25 ellipses per event on average

MODELS
  Power law of the largest ellipse areas (Modelling/Power_Law.xlsx):
    daily_maxima: n = 140, tail n = 43, A_min = 2231770 km2, alpha = 5.767, bootstrap p = 0.748 (5000 repetitions)
    event_maxima: n = 29, tail n = 13, A_min = 2106524 km2, alpha = 4.412, bootstrap p = 0.582 (5000 repetitions)
  Log-Gaussian Cox process of the 376 ellipse centroids (Modelling/LGCP.xlsx):
    (Intercept) = -10.1179
    lon = -4.28759e-05
    lat = -0.0160473
    mean_tmax = -0.00757498
    std_tmax = 0.020096
    var_sigma2 = 1.64228
    scale_km = 168.14
    Centroids inside the top-20% intensity zone: all centroids 66 of 376 (17.6%); daily largest 5 of 140 (3.6%); event largest 3 of 29 (10.3%)
    Centroids inside the top-50% intensity zone: all centroids 203 of 376 (54.0%); daily largest 68 of 140 (48.6%); event largest 10 of 29 (34.5%)
    No warnings from the fit.

FIGURES (figures/)
  ellipse_spatial_patterns.png: maps of all ellipses: centroids with their axes, footprint density, axis ratio, area and orientation
  single_day_events.png: snapshots of representative single-day events (Types 1 and 2)
  consistent_multiday_events.png: the first two days of representative Type 3 events
  mixed_multiday_events.png: six consecutive days of a representative Type 4 event
  ellipse_geometry_by_type.png: ellipse geometry by event type
  event_geometry_distributions.png: distributions of event geometry by type
  annual_event_counts_and_duration.png: annual event counts and mean durations by type
  ellipse_area_power_law.png: the power-law fit of the largest ellipse areas
  centroid_concentration.png: the LGCP intensity with the centroids and the concentration zones

FILES
  Heatwave_Catalogs/Heatwaves.xlsx
    Heatwave Events (65790 rows): every local heatwave of every cell (Catalog 1): dates, duration, exceeding and bridged days, peak
  Heatwave_Catalogs/Regional_Heatwaves.xlsx
    Regional Days (140 rows): the selected regionally extensive days (Catalog 2) with their heatwave-cell counts
    Regional Day Cells (61694 rows): the heatwave cells of every selected day and their local heatwave
  Heatwave_Catalogs/Heatwave_Clusters.xlsx
    Clusters (376 rows): the DBSCAN clusters of every selected day (Catalog 3): members, core cells, eps and min_samples applied
    Cluster Cells (61694 rows): every heatwave cell of every selected day with its cluster label, core and noise flags
  Heatwave_Catalogs/Heatwave_Ellipses.xlsx
    Ellipses (376 rows): the ellipse of every cluster (Catalog 4): centroids, axes, area, orientation, temperature weights
  Heatwave_Catalogs/Compound_Heatwaves.xlsx
    Compound Events (29 rows): every compound heatwave event (Catalog 5): type, days, cluster counts, mean geometry, largest ellipse
    Event Days (140 rows): every day of every compound event with its clusters and largest ellipse
  Modelling/Power_Law.xlsx
    Power Law Fits (2 rows): cutoff, exponent, KS distance, bootstrap p-value and bootstrap quantiles for daily and event maxima
  Modelling/LGCP.xlsx
    Parameters (7 rows): the fitted LGCP coefficients, field variance and scale
    Intensity (1800 rows): mean LGCP intensity and concentration rank of every cell
    Centroid Concentration (6 rows): share of the centroids inside the top-20% and top-50% intensity zones
  Additional_Results/Analysis_Summary.xlsx
    Event Type Summary (4 rows): statistics by compound heatwave type: days, events, durations, ellipses per event
    Cell Thresholds (1800 rows): the local threshold and heatwave counts of every cell
    Daily Heatwave Extent (5490 rows): heatwave and exceeding cells on every day, the regional threshold and the selection flag
    Duration Trends (2 rows): trend tests of the annual mean duration of Type 3 and Type 4 events
  figures/: the figures listed above (PNG, 600 dpi; 500 dpi for the two largest)
  README.txt: this file
  Numbers are stored with the 15 significant digits of the XLSX format; the display formats are rounding for reading only. Empty cells are missing values, not zeros.

WARNINGS
  None.

TRACED EVENT (demo/run_demo.R, part 4)
  Compound event 7 (Catalog 5): 2012-06-28 to 2012-07-04, 7 days, Temporally Clustered = Type 3, clusters per day 1-1-1-1-1-1-1

  Stage 2 (Catalog 2): every day of the event had at least 353 of the 1800 cells in a local heatwave,
  the regional threshold (the 97.5th percentile of the daily heatwave-cell counts):
           date heatwave_cells exceeding_cells clusters
     2012-06-28            359             385        1
     2012-06-29            386             420        1
     2012-06-30            365             375        1
     2012-07-01            379             397        1
     2012-07-02            378             320        1
     2012-07-03            370             386        1
     2012-07-04            379             404        1

  Stage 3 (Catalog 3): DBSCAN grouped the heatwave cells of each day into these clusters
  (eps in grid cells and min_samples cells are the settings chosen for the run of days):
           date cluster_id member_cells core_cells   eps min_samples noise_cells
     2012-06-28         51          357        353 3.075           8           2
     2012-06-29         52          385        378 3.075           8           1
     2012-06-30         53          365        359 3.075           8           0
     2012-07-01         54          379        376 3.075           8           0
     2012-07-02         55          378        375 3.075           8           0
     2012-07-03         56          370        364 3.075           8           0
     2012-07-04         57          379        377 3.075           8           0

  Stage 4 (Catalog 4): the largest ellipse of the event is ellipse 54, fitted to cluster 54 on 2012-07-01:
    379 member cells; axes 2203 km x 1218 km; area 2106524 km2; major axis -86 degrees from north (nearly east-west);
    Tmax-weighted centroid 39.50 N, 92.13 W; member Tmax 23.7 to 41.3 C.

  Stage 1 (Catalog 1): the hottest of those cells is cell 625 (33.5 N, 81.5 W). Its threshold is 35.84 C,
  the 95th percentile of its 5490 daily maxima. Local heatwave 22173 of that cell ran from 2012-06-28 to 2012-07-05:
  8 days, 7 of them at or above the threshold, peak 42.20 C on 2012-06-30.

  The temperature data of that cell around the heatwave (daily maximum 2-m temperature, degrees C):
           date tmax_c exceeds_threshold local_heatwave selected_day in_event
     2012-06-26  30.27                no             no           no       no
     2012-06-27  32.08                no             no           no       no
     2012-06-28  36.78               yes            yes          yes      yes
     2012-06-29  41.82               yes            yes          yes      yes
     2012-06-30  42.20               yes            yes          yes      yes
     2012-07-01  41.33               yes            yes          yes      yes
     2012-07-02  35.08                no            yes          yes      yes
     2012-07-03  35.84               yes            yes          yes      yes
     2012-07-04  36.56               yes            yes          yes      yes
     2012-07-05  38.00               yes            yes           no       no
     2012-07-06  35.34                no             no           no       no
     2012-07-07  35.81                no             no           no       no

  Figure: results/figures/consistent_multiday_events.png shows this event (named in demo/scorch_config.yaml
  under figures: representative_events): orange cells are the clustered heatwave cells, grey cells the
  heatwave cells DBSCAN left out, the black outline is the ellipse and the dot its weighted centroid.

SETTINGS OF THIS RUN (YAML)
  input:
    source: file
    file: inst/extdata/north_america_tmax.nc
    format: auto
    variable: auto
    longitude: auto
    latitude: auto
    time: auto
    units: auto
    era5_cell_size_deg: 1.0
    cds:
      area: ~
      cache_directory: era5_cache
      request_period: month
      processed_file: era5_tmax_1deg.nc
  period:
    warm_season_months:
    - 4
    - 5
    - 6
    - 7
    - 8
    - 9
  heatwaves:
    threshold_percentile: 95.0
    min_duration_days: 3.0
    min_exceeding_days: 3.0
  regional_days:
    percentile: 97.5
  clustering:
    eps_values:
    - 1.0
    - 1.5
    - 2.0
    - 2.5
    - 3.0
    - 3.5
    - 4.0
    min_samples_values:
    - 4
    - 5
    - 6
    - 7
    - 8
    - 9
    - 10
    - 11
    - 12
  ellipses:
    scale_factor: 1.25
  power_law:
    bootstrap_repetitions: 5000.0
    seed_daily_maxima: 2.026102e+07
    seed_event_maxima: 2.026112e+07
  lgcp:
    covariates:
    - lon
    - lat
    - mean_tmax
    - std_tmax
    raster_km: 25.0
    window_margin_km: 80.0
  figures:
    representative_events:
      type_3:
      - '2012-06-28'
      - '2023-08-04'
