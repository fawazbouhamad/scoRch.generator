# The result workbooks: every table of a run as a sheet of an XLSX file.
#
# Each sheet holds all rows and columns of its table, written with openxlsx2:
# the header row bold, frozen and filtered; dates as date cells; numbers as
# numeric cells whose stored values keep the 15 significant digits of the
# XLSX format (the precision of write.csv() as well) and whose display
# format follows the magnitude of the column; missing values as empty cells,
# distinct from zero. A table too long for a sheet or a file that cannot be
# written stops the run with an explicit error instead of losing rows, and
# every written archive is checked the way other readers open it (see
# check_workbook_archive()).

XLSX_MAX_ROWS <- 1048576L   # rows an XLSX sheet can hold, header included

# The workbooks of a complete run: relative path -> named list of sheets.
result_workbooks <- function(result) {
  books <- list(
    "Heatwave_Catalogs/Heatwaves.xlsx" = list(
      "Heatwave Events" = result$heatwaves$events),
    "Heatwave_Catalogs/Regional_Heatwaves.xlsx" = list(
      "Regional Days" = result$regional$selected_days,
      "Regional Day Cells" = result$regional$selected_cells),
    "Heatwave_Catalogs/Heatwave_Clusters.xlsx" = list(
      "Clusters" = result$clusters$clusters,
      "Cluster Cells" = result$clusters$cluster_cells),
    "Heatwave_Catalogs/Heatwave_Ellipses.xlsx" = list(
      "Ellipses" = result$ellipses),
    "Heatwave_Catalogs/Compound_Heatwaves.xlsx" = list(
      "Compound Events" = result$events$events,
      "Event Days" = result$events$event_days),
    "Modelling/Power_Law.xlsx" = list(
      "Power Law Fits" = result$power_law$summary))
  if (!is.null(result$lgcp)) {
    books[["Modelling/LGCP.xlsx"]] <- list(
      "Parameters" = result$lgcp$parameter_table,
      "Intensity" = result$lgcp$cells,
      "Centroid Concentration" = result$lgcp$concentration)
  }
  books[["Additional_Results/Analysis_Summary.xlsx"]] <- list(
    "Event Type Summary" = result$events$table_1,
    "Cell Thresholds" = result$heatwaves$thresholds,
    "Daily Heatwave Extent" = result$regional$daily,
    "Duration Trends" = result$events$trends)
  books
}

# The workbooks of a run that stopped because no selected day formed a
# cluster: Catalogs 1-3 and the per-cell and per-day tables.
partial_workbooks <- function(heatwaves, regional, clusters) {
  list(
    "Heatwave_Catalogs/Heatwaves.xlsx" = list(
      "Heatwave Events" = heatwaves$events),
    "Heatwave_Catalogs/Regional_Heatwaves.xlsx" = list(
      "Regional Days" = regional$selected_days,
      "Regional Day Cells" = regional$selected_cells),
    "Heatwave_Catalogs/Heatwave_Clusters.xlsx" = list(
      "Clusters" = clusters$clusters,
      "Cluster Cells" = clusters$cluster_cells),
    "Additional_Results/Analysis_Summary.xlsx" = list(
      "Cell Thresholds" = heatwaves$thresholds,
      "Daily Heatwave Extent" = regional$daily))
}

# One line per sheet for README.txt.
sheet_descriptions <- function() c(
  "Heatwave Events" = "every local heatwave of every cell (Catalog 1): dates, duration, exceeding and bridged days, peak",
  "Regional Days" = "the selected regionally extensive days (Catalog 2) with their heatwave-cell counts",
  "Regional Day Cells" = "the heatwave cells of every selected day and their local heatwave",
  "Clusters" = "the DBSCAN clusters of every selected day (Catalog 3): members, core cells, eps and min_samples applied",
  "Cluster Cells" = "every heatwave cell of every selected day with its cluster label, core and noise flags",
  "Ellipses" = "the ellipse of every cluster (Catalog 4): centroids, axes, area, orientation, temperature weights",
  "Compound Events" = "every compound heatwave event (Catalog 5): type, days, cluster counts, mean geometry, largest ellipse",
  "Event Days" = "every day of every compound event with its clusters and largest ellipse",
  "Power Law Fits" = "cutoff, exponent, KS distance, bootstrap p-value and bootstrap quantiles for daily and event maxima",
  "Parameters" = "the fitted LGCP coefficients, field variance and scale",
  "Intensity" = "mean LGCP intensity and concentration rank of every cell",
  "Centroid Concentration" = "share of the centroids inside the top-20% and top-50% intensity zones",
  "Event Type Summary" = "statistics by compound heatwave type: days, events, durations, ellipses per event",
  "Cell Thresholds" = "the local threshold and heatwave counts of every cell",
  "Daily Heatwave Extent" = "heatwave and exceeding cells on every day, the regional threshold and the selection flag",
  "Duration Trends" = "trend tests of the annual mean duration of Type 3 and Type 4 events")

# Stop before anything is written when a sheet would not fit.
check_workbook_rows <- function(books, limit = XLSX_MAX_ROWS) {
  for (path in names(books)) {
    for (sheet in names(books[[path]])) {
      rows <- nrow(books[[path]][[sheet]]) + 1L
      if (rows > limit) {
        fail("The sheet '", sheet, "' of ", path, " would need ", rows, " rows, more than the ", limit,
             " an XLSX sheet can hold. No results were written, so that none are lost silently;",
             " shorten the period or split the region.")
      }
    }
  }
  invisible(TRUE)
}

write_workbooks <- function(out, books) {
  check_workbook_rows(books)
  for (path in names(books)) write_workbook(file.path(out, path), books[[path]])
  invisible(names(books))
}

# One workbook: `sheets` is a named list of data frames. The file is checked
# after it is written.
write_workbook <- function(path, sheets) {
  wb <- openxlsx2::wb_workbook()
  for (name in names(sheets)) add_sheet(wb, name, sheets[[name]])
  saved <- tryCatch({
    save_workbook(wb, path)
    TRUE
  }, error = function(e) conditionMessage(e))
  if (!isTRUE(saved) || !file.exists(path) || file.size(path) == 0) {
    fail("Could not write ", path, if (is.character(saved)) paste0(": ", saved), ".")
  }
  check_workbook_archive(path, sheets)
  invisible(path)
}

# openxlsx2 zips a workbook with the first zipper it finds: a system zip
# program, bsdtar, or the zip package. The programs differ between sessions
# and machines (R CMD check on this machine found a zip program that was
# not there), so the pure-R zip package, an import of this package, is used
# every time.
save_workbook <- function(wb, path) {
  old_options <- options(openxlsx2.no_utils_zip = TRUE, openxlsx2.no_bsdtar = TRUE, openxlsx2.no_maybe_zip = TRUE)
  on.exit(options(old_options), add = TRUE)
  old_command <- Sys.getenv("R_ZIPCMD", unset = NA)
  Sys.unsetenv("R_ZIPCMD")
  on.exit(if (!is.na(old_command)) Sys.setenv(R_ZIPCMD = old_command), add = TRUE)
  wb$save(path)
  invisible(path)
}

# openxlsx2 workbooks are R6 objects: the methods modify `wb` in place.
add_sheet <- function(wb, name, table) {
  table <- as.data.frame(table, stringsAsFactors = FALSE)
  rownames(table) <- NULL
  rows <- nrow(table) + 1L
  columns <- ncol(table)
  wb$add_worksheet(name)
  wb$add_data(x = table, with_filter = nrow(table) > 0, na.strings = NULL)
  wb$freeze_pane(first_row = TRUE)
  header <- sprintf("A1:%s1", column_letter(columns))
  wb$add_font(dims = header, bold = TRUE)
  wb$add_fill(dims = header, color = openxlsx2::wb_color(hex = "FFE7E6E6"))
  wb$add_border(dims = header, bottom_border = "thin", top_border = "", left_border = "", right_border = "",
                inner_hgrid = "", inner_vgrid = "")
  if (nrow(table)) {
    for (j in seq_len(columns)) {
      format <- cell_format(table[[j]])
      if (!is.null(format)) {
        wb$add_numfmt(dims = sprintf("%s2:%s%d", column_letter(j), column_letter(j), rows), numfmt = format)
      }
    }
  }
  wb$set_col_widths(cols = seq_len(columns), widths = column_widths(table))
  invisible(name)
}

# Column letters of the XLSX cell references: 1 -> A, 27 -> AA.
column_letter <- function(j) {
  letters_of <- function(n) {
    out <- ""
    while (n > 0) {
      out <- paste0(LETTERS[(n - 1) %% 26 + 1], out)
      n <- (n - 1) %/% 26
    }
    out
  }
  vapply(j, letters_of, "")
}

# Display format of a column (NULL: Excel's General format). Whole numbers
# and columns spanning many orders of magnitude are left to General; other
# numbers get a fixed number of decimals chosen from their typical size.
cell_format <- function(values) {
  if (inherits(values, "Date")) return("yyyy-mm-dd")
  if (inherits(values, "POSIXt")) return("yyyy-mm-dd hh:mm:ss")
  if (!is.numeric(values)) return(NULL)
  finite <- values[is.finite(values)]
  if (!length(finite) || all(finite == round(finite))) return(NULL)
  nonzero <- abs(finite[finite != 0])
  if (!length(nonzero)) return(NULL)
  if (diff(range(log10(nonzero))) > 4) return(NULL)
  size <- stats::median(nonzero)
  if (size < 0.01) "0.000E+00" else if (size < 10) "0.000" else if (size < 1000) "0.00" else "0.0"
}

# Column widths in characters: the longer of the header and the values.
column_widths <- function(table) {
  width <- function(values) {
    if (inherits(values, "Date")) return(10)
    if (is.numeric(values)) {
      finite <- values[is.finite(values)]
      if (!length(finite)) return(4)
      return(min(max(nchar(formatC(range(finite), format = "fg", digits = 7))), 16))
    }
    text <- as.character(values)
    text <- text[!is.na(text)]
    if (!length(text)) return(4)
    min(stats::quantile(nchar(text), 0.95, names = FALSE), 48)
  }
  pmin(pmax(vapply(table, width, numeric(1)), nchar(names(table))) + 2, 50)
}

# Validation of a written workbook ------------------------------------------
#
# Microsoft Excel repairs or ignores small defects of an XLSX archive that
# stricter readers refuse: openxlsx 4.2, for example, wrote every sheet with
# relationships to drawing parts that did not exist and declared a dimension
# of A1 whatever the table, so Python's openpyxl could not open the files.
# After every save the archive is therefore checked without any external
# tool: every relationship target of every part must exist in the archive,
# every sheet must declare the dimension of its table, and the sheet names
# must be the ones requested.

check_workbook_archive <- function(path, sheets) {
  entries <- zip::zip_list(path)$filename
  problems <- archive_problems(entries, function(name, n = 1e7) read_archive_part(path, name, n), sheets)
  if (length(problems)) {
    fail("The workbook ", path, " is not a sound XLSX archive: ", paste(problems, collapse = "; "),
         ". The run was stopped so that no unreadable file is published.")
  }
  invisible(TRUE)
}

# The first `n` bytes of one part of a zip archive, as text.
read_archive_part <- function(path, name, n = 1e7) {
  con <- unz(path, name, open = "rb")
  on.exit(close(con))
  readChar(con, n, useBytes = TRUE)
}

# The defects of an archive, as sentences; empty when it is sound. `part`
# returns the text of a part (its first `n` bytes).
archive_problems <- function(entries, part, sheets) {
  problems <- character()
  for (rels in grep("[.]rels$", entries, value = TRUE)) {
    xml <- part(rels)
    targets <- regmatches(xml, gregexpr('Target="[^"]*"', xml))[[1]]
    targets <- sub('"$', "", sub('^Target="', "", targets))
    modes <- regmatches(xml, gregexpr('<Relationship [^>]*>', xml))[[1]]
    external <- grepl('TargetMode="External"', modes)
    base <- sub("_rels/[^/]*$", "", rels)
    for (k in seq_along(targets)) {
      if (isTRUE(external[k]) || grepl("^[a-z]+:", targets[k])) next
      resolved <- resolve_part_path(base, targets[k])
      if (!resolved %in% entries) {
        problems <- c(problems, sprintf("%s refers to the missing part %s", rels, resolved))
      }
    }
  }
  if (!"xl/workbook.xml" %in% entries) return(c(problems, "the archive has no xl/workbook.xml"))
  workbook <- part("xl/workbook.xml")
  found <- regmatches(workbook, gregexpr('<sheet [^>]*name="[^"]*"', workbook))[[1]]
  found <- sub('"$', "", sub('.*name="', "", found))
  found <- gsub("&amp;", "&", gsub("&quot;", '"', gsub("&apos;", "'", gsub("&lt;", "<", gsub("&gt;", ">", found)))))
  if (!identical(found, names(sheets))) {
    problems <- c(problems, sprintf("the sheet names are %s instead of %s", paste(found, collapse = ", "),
                                    paste(names(sheets), collapse = ", ")))
  }
  for (i in seq_along(sheets)) {
    name <- sprintf("xl/worksheets/sheet%d.xml", i)
    if (!name %in% entries) {
      problems <- c(problems, sprintf("the archive has no %s", name))
      next
    }
    head <- part(name, 4000)
    declared <- regmatches(head, regexpr('<dimension ref="[^"]*"', head))
    declared <- if (length(declared)) sub('"$', "", sub('.*ref="', "", declared)) else "(none)"
    expected <- sprintf("A1:%s%d", column_letter(ncol(sheets[[i]])), nrow(sheets[[i]]) + 1L)
    if (declared != expected) {
      problems <- c(problems, sprintf("sheet %d (%s) declares the dimension %s instead of %s",
                                      i, names(sheets)[i], declared, expected))
    }
  }
  problems
}

# A relationship target resolved against the folder of its source part.
resolve_part_path <- function(base, target) {
  if (startsWith(target, "/")) return(substring(target, 2))
  pieces <- strsplit(paste0(base, target), "/", fixed = TRUE)[[1]]
  out <- character()
  for (piece in pieces) {
    if (piece == "..") out <- out[-length(out)] else if (piece != "." && nzchar(piece)) out <- c(out, piece)
  }
  paste(out, collapse = "/")
}
