# Every sheet of a workbook as a data frame, for comparisons between runs.
workbook_tables <- function(path) {
  sheets <- openxlsx2::wb_get_sheet_names(openxlsx2::wb_load(path))
  stats::setNames(lapply(sheets, function(sheet) openxlsx2::read_xlsx(path, sheet = sheet)), sheets)
}

# The sheet names of a workbook, in order and without names.
sheet_names <- function(path) unname(openxlsx2::wb_get_sheet_names(openxlsx2::wb_load(path)))
