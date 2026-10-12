# The XLSX writer: every value kept, blank cells for missing values, date
# cells, the workbook layout of a run, the display formats and the explicit
# errors for a sheet that would not fit or a file that cannot be written.

test_that("a workbook keeps every value, blank missing cells and date cells", {
  table <- data.frame(id = 1:5, when = as.Date("2012-06-28") + c(0, NA, 2, 3, 4),
                      value = c(2504509.1234567891, 0, NA, -4.28759e-05, 1e-7),
                      ratio = c(0.3291234567, NA, 0, 1, 0.5), label = c("a", NA, "", "d", "e"),
                      stringsAsFactors = FALSE)
  path <- file.path(tempfile("workbook-"), "Test.xlsx")
  dir.create(dirname(path))
  scoRch.generator:::write_workbook(path, list("First Sheet" = table, "Second" = table[1:2, ]))
  expect_equal(sheet_names(path), c("First Sheet", "Second"))
  back <- openxlsx2::read_xlsx(path, sheet = "First Sheet")
  expect_equal(names(back), names(table))
  expect_equal(nrow(back), 5)
  expect_s3_class(back$when, "Date")
  expect_equal(back$when, table$when)
  expect_equal(back$value, table$value, tolerance = 1e-14)          # the 15 significant digits of XLSX
  expect_equal(is.na(back$ratio), is.na(table$ratio))               # a blank cell is a missing value ...
  expect_equal(back$ratio[3], 0)                                    # ... and a zero is a zero
  expect_equal(back$label, c("a", NA, NA, "d", "e"))                 # an empty string is an empty cell
  expect_equal(nrow(openxlsx2::read_xlsx(path, sheet = "Second")), 2)
  sheet_xml <- paste(readLines(unz(path, "xl/worksheets/sheet1.xml"), warn = FALSE), collapse = "")
  expect_match(sheet_xml, 'state="frozen"')                          # the header row stays visible ...
  expect_match(sheet_xml, "<autoFilter")                             # ... and can be filtered
})

test_that("every written workbook passes the archive check, and defects are named", {
  path <- file.path(tempfile("archive-"), "Checked.xlsx")
  dir.create(dirname(path))
  sheets <- list(Data = data.frame(x = 1:3, y = c("a", "b", "c")), More = data.frame(z = 1.5))
  scoRch.generator:::write_workbook(path, sheets)
  expect_true(scoRch.generator:::check_workbook_archive(path, sheets))
  entries <- utils::unzip(path, list = TRUE)$Name
  expect_true(all(c("xl/workbook.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml") %in% entries))
  expect_match(scoRch.generator:::read_archive_part(path, "xl/worksheets/sheet1.xml", 4000), '<dimension ref="A1:B4"/>')
  expect_error(scoRch.generator:::check_workbook_archive(path, list(Other = sheets$Data, More = sheets$More)), "sheet names")
  # the defects of openxlsx 4.2: relationships to absent drawing parts and a dimension of A1
  parts <- list(
    "xl/worksheets/_rels/sheet1.xml.rels" = paste0('<Relationships><Relationship Id="rId1" Type="t" Target="../drawings/drawing1.xml"/>',
                                                   '<Relationship Id="rId2" Type="t" Target="https://example.org" TargetMode="External"/></Relationships>'),
    "xl/workbook.xml" = '<workbook><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
    "xl/worksheets/sheet1.xml" = '<worksheet><dimension ref="A1"/><sheetData/></worksheet>')
  problems <- scoRch.generator:::archive_problems(names(parts), function(name, n = 1e7) parts[[name]],
                                                   list(Data = data.frame(x = 1:3, y = 4:6)))
  expect_length(problems, 2)
  expect_match(problems[1], "missing part xl/drawings/drawing1.xml")
  expect_match(problems[2], "dimension A1 instead of A1:B4")
  expect_equal(scoRch.generator:::resolve_part_path("xl/worksheets/", "../drawings/drawing1.xml"), "xl/drawings/drawing1.xml")
  expect_equal(scoRch.generator:::resolve_part_path("", "xl/workbook.xml"), "xl/workbook.xml")
  expect_equal(scoRch.generator:::resolve_part_path("xl/", "/xl/styles.xml"), "xl/styles.xml")
})

test_that("README.txt keeps its degree signs when the session locale fell back to C", {
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  skip_if_not(identical(suppressWarnings(Sys.setlocale("LC_CTYPE", "C")), "C"), "the C locale is not available")
  line <- paste0("129.5", "\u00b0", "W to 58.5", "\u00b0", "W")
  path <- tempfile(fileext = ".txt")
  scoRch.generator:::write_text_file(c("INPUT", line), path)
  bytes <- readBin(path, "raw", file.size(path))
  expect_true(any(bytes[-length(bytes)] == as.raw(0xc2) & bytes[-1] == as.raw(0xb0)))   # the UTF-8 degree sign
  expect_false(grepl("<U+00B0>", rawToChar(bytes), fixed = TRUE))
  expect_identical(readLines(path, encoding = "UTF-8")[2], line)
})

test_that("a sheet beyond the XLSX row limit or an unwritable file is an explicit error", {
  books <- list("Folder/Book.xlsx" = list("Long Sheet" = data.frame(x = 1:5)))
  expect_error(scoRch.generator:::check_workbook_rows(books, limit = 5), "Long Sheet.*Folder/Book.xlsx.*6 rows")
  expect_true(scoRch.generator:::check_workbook_rows(books))
  expect_equal(scoRch.generator:::XLSX_MAX_ROWS, 1048576L)
  missing <- file.path(tempfile("missing-"), "deeper", "Book.xlsx")
  expect_error(scoRch.generator:::write_workbook(missing, list(Sheet = data.frame(x = 1))), "Could not write")
  expect_false(file.exists(missing))
})

test_that("the workbooks of a run cover every table, with the LGCP workbook optional", {
  df <- data.frame(x = 1)
  result <- list(heatwaves = list(events = df, thresholds = df),
                 regional = list(selected_days = df, selected_cells = df, daily = df),
                 clusters = list(clusters = df, cluster_cells = df), ellipses = df,
                 events = list(events = df, event_days = df, table_1 = df, trends = df),
                 power_law = list(summary = df),
                 lgcp = list(parameter_table = df, cells = df, concentration = df))
  books <- scoRch.generator:::result_workbooks(result)
  expect_equal(names(books), c("Heatwave_Catalogs/Heatwaves.xlsx", "Heatwave_Catalogs/Regional_Heatwaves.xlsx",
                               "Heatwave_Catalogs/Heatwave_Clusters.xlsx", "Heatwave_Catalogs/Heatwave_Ellipses.xlsx",
                               "Heatwave_Catalogs/Compound_Heatwaves.xlsx", "Modelling/Power_Law.xlsx",
                               "Modelling/LGCP.xlsx", "Additional_Results/Analysis_Summary.xlsx"))
  expect_equal(unname(lapply(books, names)),
               list("Heatwave Events", c("Regional Days", "Regional Day Cells"), c("Clusters", "Cluster Cells"),
                    "Ellipses", c("Compound Events", "Event Days"), "Power Law Fits",
                    c("Parameters", "Intensity", "Centroid Concentration"),
                    c("Event Type Summary", "Cell Thresholds", "Daily Heatwave Extent", "Duration Trends")))
  sheets <- unlist(lapply(books, names), use.names = FALSE)
  expect_true(all(sheets %in% names(scoRch.generator:::sheet_descriptions())))
  expect_false(any(grepl("Table 1", c(names(books), sheets))))
  expect_true(all(names(books) %in% scoRch.generator:::managed_output_files()))
  result$lgcp <- NULL
  expect_false("Modelling/LGCP.xlsx" %in% names(scoRch.generator:::result_workbooks(result)))
  partial <- scoRch.generator:::partial_workbooks(result$heatwaves, result$regional, result$clusters)
  expect_equal(names(partial), c("Heatwave_Catalogs/Heatwaves.xlsx", "Heatwave_Catalogs/Regional_Heatwaves.xlsx",
                                 "Heatwave_Catalogs/Heatwave_Clusters.xlsx", "Additional_Results/Analysis_Summary.xlsx"))
  expect_equal(names(partial[[4]]), c("Cell Thresholds", "Daily Heatwave Extent"))
})

test_that("display formats follow the column and never touch the stored values", {
  cell_format <- scoRch.generator:::cell_format
  expect_equal(cell_format(as.Date("2012-06-28") + 0:2), "yyyy-mm-dd")
  expect_null(cell_format(c(1L, 2L, NA)))
  expect_null(cell_format(c(353, 1800, 0)))                          # whole numbers: Excel's General
  expect_equal(cell_format(c(0.329, 0.785, NA)), "0.000")
  expect_equal(cell_format(c(3.075, 2.9)), "0.000")
  expect_equal(cell_format(c(23.56, 41.33)), "0.00")
  expect_equal(cell_format(c(2504509.12, 2106524.3)), "0.0")
  expect_equal(cell_format(c(2.39e-05, 3.1e-05)), "0.000E+00")
  expect_null(cell_format(c(-10.1179, -4.28759e-05, 168.14)))       # several orders of magnitude: General
  expect_null(cell_format(c("a", "b")))
  widths <- scoRch.generator:::column_widths(data.frame(heatwave_share_of_exceeding_cells = c(0.5, NA),
                                                        d = as.Date("2012-06-28"), s = "text"))
  expect_equal(unname(widths), c(35, 12, 6))
})
