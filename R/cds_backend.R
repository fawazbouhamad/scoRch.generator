# Talking to the CDS: submission, status, transfer and deletion of one
# request, behind a small interface so that tests can replace it; and the
# checks that make the cache safe to reuse.

# The functions that reach the CDS. An option can replace them (tests do), so
# the planning, caching and resuming logic runs without the network.
cds_backend <- function() {
  custom <- getOption("scoRch.generator.cds_backend")
  if (!is.null(custom)) return(custom)
  for (pkg in c("ecmwfr", "httr")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      fail("The from-scratch input needs the package '", pkg, "'; install it with install.packages(\"", pkg, "\").")
    }
  }
  list(
    key_present = function(user) {
      tryCatch(nzchar(ecmwfr::wf_get_key(user = user)), error = function(e) FALSE)
    },
    # Submit a request and return the URL of the CDS job.
    submit = function(request, user) {
      job <- ecmwfr::wf_request(request, user = user, transfer = FALSE, verbose = FALSE)
      job$get_url()
    },
    # accepted, running, successful, failed, rejected, or missing when the
    # CDS no longer knows the job.
    status = function(url, user) {
      key <- ecmwfr::wf_get_key(user = user)
      response <- httr::GET(url, httr::add_headers(`PRIVATE-TOKEN` = key))
      if (httr::status_code(response) == 404) return("missing")
      if (httr::http_error(response)) return("unknown")
      content <- httr::content(response, as = "parsed")
      status <- content$status
      if (is.null(status)) "unknown" else as.character(status)
    },
    transfer = function(url, cache, filename, user) {
      ecmwfr::wf_transfer(url, user = user, path = cache, filename = filename, verbose = FALSE)
      invisible(file.path(cache, filename))
    },
    delete = function(url, user) {
      try(ecmwfr::wf_delete(url, user = user, verbose = FALSE), silent = TRUE)
      invisible(NULL)
    }
  )
}

# Obtain one file: resume the job noted for this very request, or submit;
# wait for the CDS; download; check the delivered file; record the request.
cds_fetch_one <- function(backend, request, cache, user, time_out, retry, say) {
  target <- file.path(cache, request$target)
  note <- paste0(target, ".job")
  key <- cds_request_key(request)
  url <- NULL
  if (file.exists(note)) {
    lines <- readLines(note, warn = FALSE)
    if (length(lines) >= 2 && identical(lines[2], key) && nzchar(lines[1])) url <- lines[1] else unlink(note)
  }
  started <- Sys.time()
  resubmissions <- 0L
  repeat {
    if (is.null(url)) {
      url <- tryCatch(backend$submit(request, user), error = function(e) {
        text <- conditionMessage(e)
        if (grepl("too large|cost limit", text, ignore.case = TRUE)) {
          fail("The CDS refused the request for ", request$target, " as too large (", trimws(text),
               "). Use period = \"month\" (request_period: month in the configuration) or a smaller area.")
        }
        fail("The CDS did not accept the request for ", request$target, ": ", trimws(text))
      })
      writeLines(c(url, key), note)
      say("Requested %s (CDS job %s); waiting in the CDS queue", request$target, basename(url))
    } else {
      say("Resuming the CDS request for %s (job %s)", request$target, basename(url))
    }
    repeat {
      status <- backend$status(url, user)
      if (status == "successful") {
        backend$transfer(url, cache, request$target, user)
        problem <- check_cds_file(target, request)
        if (!is.null(problem)) {
          unlink(c(target, note))
          fail("The file the CDS delivered for ", request$target, " does not match the request (", problem,
               "). It was removed; run again to request it anew.")
        }
        writeLines(key, cds_record_path(target))
        backend$delete(url, user)
        unlink(note)
        say("Downloaded %s (%.1f MB)", request$target, file.size(target) / 1e6)
        return(invisible(target))
      }
      if (status %in% c("rejected", "missing", "dismissed", "failed")) break
      waited <- as.numeric(difftime(Sys.time(), started, units = "secs"))
      if (waited > time_out) {
        fail("Waited ", round(waited / 60), " minutes for ", request$target, ", which is still ", status,
             " on the CDS. The request stays queued there; run again later to resume it (its job is noted in ", note, ").")
      }
      Sys.sleep(retry)
    }
    if (status == "failed") {
      unlink(note)
      fail("The CDS could not produce ", request$target, " (job ", basename(url), " failed). ",
           "Check the request on https://cds.climate.copernicus.eu/requests and run again.")
    }
    # rejected (the queue limit of one request per user), missing or
    # dismissed: submit again after a pause.
    resubmissions <- resubmissions + 1L
    if (resubmissions > 50L) fail("The CDS keeps rejecting or dropping the request for ", request$target, "; try again later.")
    say("The CDS %s the request for %s; submitting it again in %d s", status, request$target, retry * 5)
    unlink(note)
    url <- NULL
    Sys.sleep(retry * 5)
  }
}

# The text file that records which request a cached file answers.
cds_record_path <- function(target) paste0(target, ".request")

# NULL when a cached file is good for this request, otherwise the reason it
# is not: it must exist, carry the record of the same request, and hold the
# requested grid and dates.
cds_cache_problem <- function(target, request) {
  if (!file.exists(target)) return("missing")
  if (file.size(target) == 0) return("the file is empty")
  record <- cds_record_path(target)
  if (!file.exists(record)) return("no record of the request that produced it")
  if (!identical(readLines(record, warn = FALSE)[1], cds_request_key(request))) {
    return("the recorded request differs from this one")
  }
  check_cds_file(target, request)
}

# NULL when a file holds the 2-m temperature on the requested grid for the
# requested dates, otherwise the reason it does not.
check_cds_file <- function(target, request) {
  nc <- tryCatch(ncdf4::nc_open(target), error = function(e) NULL)
  if (is.null(nc)) return("not a readable NetCDF file")
  on.exit(ncdf4::nc_close(nc))
  variable <- intersect(c("t2m", "2m_temperature"), names(nc$var))
  if (!length(variable)) return("no 2-m temperature variable")
  dims <- vapply(nc$var[[variable[1]]]$dim, function(d) d$name, "")
  lon_name <- intersect(c("longitude", "lon"), dims)
  lat_name <- intersect(c("latitude", "lat"), dims)
  time_name <- intersect(c("valid_time", "time"), dims)
  if (!length(lon_name) || !length(lat_name) || !length(time_name)) return("longitude, latitude or time dimension missing")
  lon <- sort(wrap_longitudes(as.numeric(nc$dim[[lon_name[1]]]$vals))$lon)
  lat <- sort(as.numeric(nc$dim[[lat_name[1]]]$vals))
  area <- request$area
  same <- function(have, want) length(have) == length(want) && max(abs(have - want)) < 1e-6
  if (!same(lon, seq(area[2], area[4], by = 0.25))) return("the longitudes are not those of the requested area")
  if (!same(lat, seq(area[3], area[1], by = 0.25))) return("the latitudes are not those of the requested area")
  time_dim <- nc$dim[[time_name[1]]]
  calendar <- ncdf4::ncatt_get(nc, time_name[1], "calendar")
  dates <- tryCatch(sort(unique(decode_time(time_dim$vals, time_dim$units, if (calendar$hasatt) calendar$value else "standard"))),
                    error = function(e) NULL)
  wanted <- cds_request_dates(request)
  if (is.null(dates) || length(dates) != length(wanted) || any(dates != wanted)) {
    return("the dates are not the requested ones")
  }
  NULL
}
