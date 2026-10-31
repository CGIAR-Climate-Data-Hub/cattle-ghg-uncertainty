# Consistency checks on a translator-produced template (2026-09-18).
#
# run_qaqc() judges each row on its own. The errors the AI actually made on
# the Zambia file were relational: a calf row split into male and female
# halves with different invented weights, a manure allocation that summed to
# 111 %, one production system given a pasture MCF four times the value the
# file gives every other system, and an uncertainty of 0.5 where the file
# said 50 %. None of these is visible from one row.
#
# These checks run server-side, on the workbook the writer produced, before
# the Download button and again from scripts/translator_eval.R. They are
# advisory: each finding is a sentence the compiler can check against the
# source file. They never change a value.
#
# Returns a data.frame(where, issue) with zero rows when nothing was found.

# ---------------------------------------------------------------------------
# Source reconciliation (2026-10-14)
#
# Everything above compares the template against itself. On the Colombian
# municipal file that was not enough twice in one evening:
#
#   Run 1 emitted 2,067,473 head where the file said 1,873,832, because one
#   group appeared under two aggregation levels. It passed 2,434 checks.
#   Run 2 replaced the Ym of seven groups with the IPCC default of 7.0 where
#   the file gives 5.85 to 6.00, and said so in data_source, unread.
#
# A translator's job is fidelity to a source, so the source has to be one of
# the things it is checked against. `source` carries a fingerprint of the
# uploaded workbook: every number in it, and the parameter families the
# server-side scan found. Both are already computed elsewhere.
#
# When `source` is NULL these checks are skipped and the behaviour is exactly
# as before.
# ---------------------------------------------------------------------------

# Numbers the translator may legitimately derive rather than copy: a unit
# conversion of a single cell. Sums and weighted averages are NOT here; those
# must be tagged user_chat, which exempts them from the verbatim check.
.TRANSLATOR_VALUE_TRANSFORMS <- c(1, 100, 1/100, 18.45, 1/18.45, 365, 1/1000)

# Every numeric reading of a column, including cells that store the number
# as TEXT. A Spanish or French workbook writes 10,78 for ten point seven
# eight, and as.numeric() returns NA for it, so the value is invisible to
# every check below. The Colombian municipal file has two such cells
# (DMI "10,78" and BW "300,00"): they produced a false "no matching number
# is in your file" report on DMI for two municipalities, and they are why
# the translator read 15 rows from a sheet that has 16.
#
# Both continental conventions are read, and the pattern decides which:
#   "10,78" or "1.234,56"  -> comma is the decimal mark
#   "1,234,567"            -> comma groups thousands
# A bare "1,234" is ambiguous, so both readings are kept. This set is only
# ever used for "is this number present in the source", where an extra
# candidate costs sensitivity, never a false alarm.
# [0-9] rather than a shorthand class throughout: R's default TRE
# engine reads a shorthand inside a bracket as literal characters.
.translator_cell_numbers <- function(col) {
  if (is.numeric(col)) return(col[is.finite(col)])
  x <- trimws(as.character(col))
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(numeric(0))
  out <- suppressWarnings(as.numeric(x))
  out <- out[is.finite(out)]
  dec <- grepl("^[-+]?[0-9]+,[0-9]+$", x) |
         grepl("^[-+]?[0-9]{1,3}([.][0-9]{3})+,[0-9]+$", x)
  if (any(dec)) {
    v <- suppressWarnings(as.numeric(gsub(",", ".", gsub("[.]", "", x[dec]))))
    out <- c(out, v[is.finite(v)])
  }
  thou <- grepl("^[-+]?[0-9]{1,3}(,[0-9]{3})+$", x)
  if (any(thou)) {
    v <- suppressWarnings(as.numeric(gsub(",", "", x[thou])))
    out <- c(out, v[is.finite(v)])
  }
  out
}

# The values the source itself gives for each manure coefficient, read from
# the column whose HEADER names it. Matching on the header rather than on
# any cell keeps this precise: the question is "what does their EF3 column
# say", not "does this number appear anywhere in the workbook".
#
# Needed because testing a manure value against the whole number pool is
# far too weak. EF3 = 0.02 passed that test by matching 2/100, where 2 is
# some unrelated count, while the file's own EF3 column says 0.009.
.MANURE_FAMILY_HEADERS <- list(
  MCF          = c("^mcf", "methane conversion", "factor de conversi"),
  EF3          = c("^ef3", "^fe[ _]*n2o", "^factor de emisi.*n2o", "direct n2o"),
  Bo           = c("^bo$", "^b0$", "methane producing", "potencial.*metano"),
  Frac_GasMS   = c("frac_?gas", "volatilis", "volatiliz"),
  Frac_LeachMS = c("frac_?leach", "lixivia", "leaching")
)

.translator_family_column_values <- function(sheets) {
  out <- list()
  for (sh in sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d) || is.null(names(d))) next
    hdr <- tolower(trimws(names(d)))
    for (fam in names(.MANURE_FAMILY_HEADERS)) {
      for (pat in .MANURE_FAMILY_HEADERS[[fam]]) {
        k <- which(grepl(pat, hdr, perl = TRUE))
        if (!length(k)) next
        v <- unlist(lapply(k, function(j) .translator_cell_numbers(d[[j]])))
        v <- v[is.finite(v) & v != 0]
        if (length(v)) out[[fam]] <- unique(c(out[[fam]], round(v, 6)))
        break
      }
    }
  }
  out
}

translator_source_fingerprint <- function(parsed) {
  if (is.null(parsed) || !length(parsed$sheets)) return(NULL)
  nums <- numeric(0)
  for (sh in parsed$sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d)) next
    for (col in d) nums <- c(nums, .translator_cell_numbers(col))
  }
  fam <- tryCatch(.translator_scan_param_labels(parsed$sheets),
                  error = function(e) character(0))
  # 2026-10-22 (WP3, C7): columns headed by a year carry the source's own
  # per-year totals; every sheet's column sum is kept as a candidate.
  # 2026-10-23: a population sheet carries subtotal and total rows, so the
  # whole column is a multiple of the herd (Zambia: four times). Three
  # candidates per column: the whole column, the rows not labelled total,
  # and the largest cell (a grand-total row is the herd itself).
  year_sums <- list()
  for (sh in parsed$sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d)) next
    tot_row <- tryCatch(apply(d, 1, function(r) any(grepl("\\btotal\\b|^\\s*all\\b", as.character(r), ignore.case = TRUE))),
                        error = function(e) rep(FALSE, NROW(d)))
    tot_row[is.na(tot_row)] <- FALSE
    for (col in names(d)) {
      yr <- suppressWarnings(as.integer(trimws(as.character(col))))
      if (is.na(yr) || yr < 1950 || yr > 2100) next
      vv <- suppressWarnings(as.numeric(gsub(",", "", as.character(d[[col]]))))
      if (!any(is.finite(vv))) next
      key <- as.character(yr)
      cands <- c(sum(vv[is.finite(vv)]), sum(vv[is.finite(vv) & !tot_row]), max(vv[is.finite(vv)]))
      year_sums[[key]] <- unique(c(year_sums[[key]], cands[is.finite(cands) & cands > 0]))
    }
  }
  # 2026-10-30: the numbers of each year's column (for the time-series
  # year check) and every row that changes from year to year (for the
  # time-series coverage check). A sheet needs two or more year columns.
  year_values <- list(); varying_rows <- list()
  for (sh in parsed$sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d)) next
    yrs <- suppressWarnings(as.integer(trimws(names(d))))
    yc <- which(!is.na(yrs) & yrs >= 1950 & yrs <= 2100)
    if (length(yc) < 2) next
    M <- vapply(yc, function(j) suppressWarnings(as.numeric(gsub(",", "", as.character(d[[j]])))),
                numeric(NROW(d)))
    if (is.null(dim(M))) M <- matrix(M, nrow = NROW(d))
    colnames(M) <- as.character(yrs[yc])
    for (k in seq_along(yc)) {
      v <- M[, k]; v <- v[is.finite(v)]
      key <- colnames(M)[k]
      year_values[[key]] <- sort(unique(c(year_values[[key]], signif(v, 9))))
    }
    for (r in seq_len(nrow(M))) {
      v <- M[r, ]; ok <- is.finite(v)
      if (sum(ok) < 3) next
      vv <- v[ok]
      if (length(unique(signif(vv, 9))) > 1) varying_rows[[length(varying_rows) + 1L]] <- vv
    }
  }
  list(numbers  = unique(round(nums, 6)),
       year_values = year_values,
       varying_rows = varying_rows,
       families = sub(" .*$", "", fam),      # "Ym (methane ...)" -> "Ym"
       family_values = tryCatch(.translator_family_column_values(parsed$sheets),
                                error = function(e) list()),
       year_sums = year_sums)
}

# 2026-10-23: a relative uncertainty written as a fraction of 1 (0.5 for
# 50 %) where the catalogue and the rest of the file say percent. The
# Zambia MoE sheet gives "95% margin of error (%)" as 0.5; the user
# confirmed it means 50 %, and one production system still came out with
# 0.5. The reference is the catalogue's suggested uncertainty for the
# parameter, else the median of the other rows of the same parameter: when
# it is 5 % or more and the row is below 1 with no explicit bounds, the row
# is multiplied by 100 (never beyond 200 %) and the correction is listed
# in piece$server_corrections for the checks.
.translator_fix_uncertainty_scale <- function(piece) {
  ps <- piece$parameters
  if (!is.data.frame(ps) || !nrow(ps) || !all(c("parameter", "uncertainty_pct") %in% names(ps)))
    return(piece)
  u <- suppressWarnings(as.numeric(ps$uncertainty_pct))
  lo <- if ("lower" %in% names(ps)) suppressWarnings(as.numeric(ps$lower)) else rep(NA_real_, nrow(ps))
  hi <- if ("upper" %in% names(ps)) suppressWarnings(as.numeric(ps$upper)) else rep(NA_real_, nrow(ps))
  cat_u <- if (exists("PARAM_CATALOGUE") && all(c("parameter", "suggested_uncertainty_pct") %in% names(PARAM_CATALOGUE)))
    stats::setNames(suppressWarnings(as.numeric(PARAM_CATALOGUE$suggested_uncertainty_pct)), PARAM_CATALOGUE$parameter) else numeric(0)
  rows <- list(); fixed <- integer(0)
  for (p in unique(as.character(ps$parameter))) {
    idx <- which(as.character(ps$parameter) == p)
    ref <- if (p %in% names(cat_u)) cat_u[[p]] else NA_real_
    if (!is.finite(ref)) {
      others <- u[idx][is.finite(u[idx]) & u[idx] >= 1]
      ref <- if (length(others) >= 2L) stats::median(others) else NA_real_
    }
    if (!is.finite(ref) || ref < 5) next
    for (i in idx) {
      if (!is.finite(u[i]) || u[i] <= 0 || u[i] >= 1) next
      if (is.finite(lo[i]) || is.finite(hi[i])) next   # explicit bounds carry the spread
      if (u[i] * 100 > 200) next
      new <- u[i] * 100
      u[i] <- new; fixed <- c(fixed, i)
      rows[[length(rows) + 1L]] <- data.frame(
        where = sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", ps$sub_category[i], p),
        issue = sprintf(paste0("Uncertainty was written as %s for %s, a fraction where the template takes a ",
                               "percentage (the IPCC catalogue suggests about %s%% for %s). Read as %s%% and ",
                               "corrected on this row. Check it against your file."),
                        format(signif(u[i] / 100, 4)), p, format(signif(ref, 3)), p, format(signif(new, 4))),
        sheet = "Parameters",
        group = paste(ps$cattle_type[i] %||% "", ps$aggregation_level[i] %||% "", ps$sub_category[i] %||% "", sep = "||"),
        parameter = p, check = "uncertainty scale (corrected)", stringsAsFactors = FALSE)
    }
  }
  if (!length(fixed)) return(piece)
  ps$uncertainty_pct <- u
  piece$parameters <- ps
  corr <- do.call(rbind, rows); rownames(corr) <- NULL
  piece$server_corrections <- if (is.data.frame(piece$server_corrections) && nrow(piece$server_corrections))
    rbind(piece$server_corrections, corr) else corr
  piece
}

# 2026-10-23: the Parameters sheet is the single-year snapshot of the time
# series, so for the inventory year the two must agree. On the Zambia run
# of 15:50 the model emitted four systems' populations from its
# exploration table, built for 2022 before the user chose 2024, while the
# time series (read straight from the year columns) was right. Where they
# differ by more than 0.5 %, the Parameters value is set to the
# time-series value, explicit bounds are scaled with it, and the
# correction is listed for the user.
.translator_fix_year_from_timeseries <- function(piece) {
  ps <- piece$parameters; ts <- piece$parameter_timeseries
  if (!is.data.frame(ps) || !nrow(ps) || !is.data.frame(ts) || !nrow(ts)) return(piece)
  if (!all(c("sub_category", "parameter", "mean") %in% names(ps)) || !"year" %in% names(ts)) return(piece)
  yr <- suppressWarnings(as.integer(.translator_scalar(.translator_metadata_list(piece$inventory_metadata)$year %||% NA)))
  if (is.na(yr)) return(piece)
  num <- function(x) suppressWarnings(as.numeric(x))
  key <- function(df, i) paste(df$cattle_type[i] %||% "", df$aggregation_level[i] %||% "", df$sub_category[i] %||% "", sep = "||")
  py <- ts[num(ts$year) == yr, , drop = FALSE]
  if (!nrow(py)) return(piece)
  pcols <- intersect(names(py), if (exists("PARAM_CATALOGUE")) PARAM_CATALOGUE$parameter else character(0))
  if (!length(pcols)) return(piece)
  ps_key <- paste(key(ps, seq_len(nrow(ps))), ps$parameter, sep = "##")
  mu <- num(ps$mean)
  lo <- if ("lower" %in% names(ps)) num(ps$lower) else rep(NA_real_, nrow(ps))
  hi <- if ("upper" %in% names(ps)) num(ps$upper) else rep(NA_real_, nrow(ps))
  rows <- list(); fixed <- integer(0)
  for (i in seq_len(nrow(py))) for (pc in pcols) {
    v <- num(py[[pc]][i]); if (!is.finite(v)) next
    j <- match(paste(key(py, i), pc, sep = "##"), ps_key)
    if (is.na(j) || !is.finite(mu[j]) || abs(v - mu[j]) <= 0.005 * max(1e-9, abs(mu[j]))) next
    ratio <- if (mu[j] != 0) v / mu[j] else NA_real_
    old <- mu[j]; mu[j] <- v
    if (is.finite(ratio) && ratio > 0) { if (is.finite(lo[j])) lo[j] <- lo[j] * ratio; if (is.finite(hi[j])) hi[j] <- hi[j] * ratio }
    fixed <- c(fixed, j)
    rows[[length(rows) + 1L]] <- data.frame(
      where = sprintf("%s / %s / %s", ps$aggregation_level[j] %||% "", ps$sub_category[j], pc),
      issue = sprintf(paste0("Parameters gave %s for %s but the time series gives %s for the inventory year %d. ",
                             "The single-year sheet must agree with the time series, so the row was set to %s",
                             "%s. Check it against your file."),
                      format(signif(old, 7)), pc, format(signif(v, 7)), yr, format(signif(v, 7)),
                      if (is.finite(ratio) && (is.finite(lo[j]) || is.finite(hi[j]))) " and its bounds scaled with it" else ""),
      sheet = "Parameters", group = key(ps, j), parameter = pc, check = "year value (corrected)", stringsAsFactors = FALSE)
  }
  if (!length(fixed)) return(piece)
  ps$mean <- mu
  if ("lower" %in% names(ps)) ps$lower <- lo
  if ("upper" %in% names(ps)) ps$upper <- hi
  piece$parameters <- ps
  corr <- do.call(rbind, rows); rownames(corr) <- NULL
  piece$server_corrections <- if (is.data.frame(piece$server_corrections) && nrow(piece$server_corrections))
    rbind(piece$server_corrections, corr) else corr
  piece
}

# 2026-10-30: a relative spread on the manure sheet ("all shares +/-50 %",
# "every MCF +/-25 %") is turned into bounds by the server, row by row, from
# the percentage the AI wrote in the *_unc_pct field. The model kept doing
# this arithmetic wrong (0 to 50 on every row, then 0 to twice the share).
# Explicit bounds the AI wrote are kept. Bounds are clipped at 0 and, for
# the percent columns, at 100.
.TRANSLATOR_MANURE_REL <- list(
  list(u = "fraction_unc_pct",   v = "fraction_pct",     lo = "lower_fraction",   hi = "upper_fraction",   cap = 100),
  list(u = "mcf_unc_pct",        v = "MCF_pct",          lo = "lower_mcf",        hi = "upper_mcf",        cap = 100),
  list(u = "ef3_unc_pct",        v = "EF3",              lo = "lower_ef3",        hi = "upper_ef3",        cap = Inf),
  list(u = "frac_gas_unc_pct",   v = "Frac_GasMS_pct",   lo = "lower_frac_gas",   hi = "upper_frac_gas",   cap = 100),
  list(u = "frac_leach_unc_pct", v = "Frac_LeachMS_pct", lo = "lower_frac_leach", hi = "upper_frac_leach", cap = 100))

.translator_apply_relative_ranges <- function(piece) {
  mm <- piece$manure_management
  if (!is.data.frame(mm) || !nrow(mm)) return(piece)
  num <- function(x) suppressWarnings(as.numeric(x))
  changed <- FALSE
  for (s in .TRANSLATOR_MANURE_REL) {
    if (!s$u %in% names(mm) || !s$v %in% names(mm)) next
    u <- num(mm[[s$u]]); v <- num(mm[[s$v]])
    lo <- if (s$lo %in% names(mm)) num(mm[[s$lo]]) else rep(NA_real_, nrow(mm))
    hi <- if (s$hi %in% names(mm)) num(mm[[s$hi]]) else rep(NA_real_, nrow(mm))
    i <- which(is.finite(u) & u > 0 & is.finite(v) & v > 0 & is.na(lo) & is.na(hi))
    if (!length(i)) next
    lo[i] <- pmax(0, v[i] * (1 - u[i] / 100))
    hi[i] <- pmin(s$cap, v[i] * (1 + u[i] / 100))
    mm[[s$lo]] <- lo; mm[[s$hi]] <- hi
    changed <- TRUE
  }
  if (changed) { piece$manure_management <- mm; piece$.relative_ranges_applied <- TRUE }
  piece
}

# 2026-10-30 (Lolita, hard rule): an optional input (GE, DMI: measured
# intake) appears in the template only when the uploaded file has it. The
# AI wrote GE = DMI = 0 for every Zambia group from about 22 October, and a
# value it invents would replace the energy balance. `families` is the
# source scan (NULL when the source is unknown: nothing is removed then).
.translator_drop_unsourced_intake <- function(piece, families = NULL) {
  ps <- piece$parameters
  if (is.null(families) || !is.data.frame(ps) || !nrow(ps) || !"parameter" %in% names(ps)) return(piece)
  opt <- PARAM_CATALOGUE$parameter[PARAM_CATALOGUE$param_tier %in% "optional"]
  drop <- ps$parameter %in% setdiff(opt, families)
  if (!any(drop)) return(piece)
  corr <- do.call(rbind, lapply(split(which(drop), ps$parameter[drop]), function(i) {
    p <- ps$parameter[i[1]]
    data.frame(where = "Parameters", issue = sprintf(paste0(
      "%s is not in your file, so it was removed from %d row(s) and left blank: ",
      "the tool calculates feed intake from the energy balance. Fill %s in only ",
      "if you measured it."), p, length(i), p),
      sheet = "Parameters", group = NA_character_, parameter = p,
      check = "measured intake not in the file (removed)", stringsAsFactors = FALSE)
  }))
  rownames(corr) <- NULL
  piece$parameters <- ps[!drop, , drop = FALSE]
  piece$server_corrections <- if (is.data.frame(piece$server_corrections) && nrow(piece$server_corrections))
    rbind(piece$server_corrections, corr) else corr
  piece
}

# The template JSON after the server-side corrections; the same text when
# there was nothing to correct, so the caller can tell.
.translator_fix_piece_json <- function(json, families = NULL) {
  if (is.null(json) || !nzchar(json)) return(json)
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(piece) || !is.data.frame(piece$parameters)) return(json)
  before <- if (is.data.frame(piece$server_corrections)) nrow(piece$server_corrections) else 0L
  piece <- tryCatch(.translator_drop_unsourced_intake(piece, families), error = function(e) piece)
  piece <- .translator_fix_uncertainty_scale(piece)
  piece <- tryCatch(.translator_fix_year_from_timeseries(piece), error = function(e) piece)
  piece <- tryCatch(.translator_apply_relative_ranges(piece), error = function(e) piece)
  rel <- isTRUE(piece$.relative_ranges_applied); piece$.relative_ranges_applied <- NULL
  after <- if (is.data.frame(piece$server_corrections)) nrow(piece$server_corrections) else 0L
  if (after == before && !rel) return(json)
  as.character(jsonlite::toJSON(piece, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
}

# The short name of a check from its location label, for the checks that
# pass only a label (2026-10-22): the checks workbook shows the name in its
# Check column and the label, when it is a place, in Group.
.translator_check_name <- function(where) {
  w <- where %||% ""
  if (w %in% c("source reconciliation", "category coverage", "Parameters vs time series")) return(w)
  if (identical(w, "Manure_Management")) return("manure bounds")
  if (grepl("^year ", w)) return("time series totals")
  NA_character_
}

# ---------------------------------------------------------------------------
# Time-series ("trend") checks (2026-10-30, C13)
#
# The trend run (.trend_year_specs in R/trend_tab.R) starts every year from
# the Parameters sheet and replaces only what Parameter_TimeSeries gives for
# that year and group. An input the series leaves out keeps its
# inventory-year value in every year, a year missing from one group's series
# falls back to that value too (nothing is interpolated), and a series row
# whose group or parameter matches no Parameters row is skipped without a
# word. Manure has no time series at all. None of this shows in the
# workbook, so the compiler is told before running the trend.
#
# Two kinds of finding. Translation mistakes the AI review can fix from the
# file: a gap in a series and rows the trend ignores (both in
# .TRANSLATOR_REVIEW_CHECKS). Notes for the country team: inputs held
# constant, uneven coverage within a system, a value repeated in two
# neighbouring years, two groups with the same series, large jumps, a unit
# change inside a series, what stays fixed, and the years covered. All of
# them reach the checks workbook and the Check and Why columns only, never
# the app's QA/QC tab. They run only when the series has two years or more.
# ---------------------------------------------------------------------------

# "DE", "CP", "BW" -> "DE, CP and BW"
.translator_and <- function(x) {
  x <- as.character(x)
  if (length(x) <= 1L) return(paste(x, collapse = ""))
  paste(paste(x[-length(x)], collapse = ", "), "and", x[length(x)])
}

# 1990, 1991, 1992, 1995 -> "1990 to 1992, 1995"
.translator_year_runs <- function(y) {
  y <- sort(unique(as.integer(y[!is.na(y)])))
  if (!length(y)) return("")
  br <- c(0L, which(diff(y) != 1L), length(y))
  paste(vapply(seq_len(length(br) - 1L), function(k) {
    a <- y[br[k] + 1L]; b <- y[br[k + 1L]]
    if (a == b) as.character(a) else sprintf("%d to %d", a, b)
  }, character(1)), collapse = ", ")
}

# Ratios between two neighbouring years that read as a change of unit
# (percent and fraction, per day and per year, kg and tonnes), within 3 %.
.TRANSLATOR_UNIT_RATIOS <- c("100" = 100, "1/100" = 1 / 100, "365" = 365, "1/365" = 1 / 365,
                             "1000" = 1000, "1/1000" = 1 / 1000)

# `add` is the row writer of translator_consistency_checks(); `skip` holds
# the level||sub_category||parameter keys C11 already reported: the
# uneven-coverage and gap checks leave them out, and the held-constant row
# names them with a pointer to C11 rather than a row of its own.
.translator_trend_checks <- function(ps, population, inventory_year, add, skip = character(0)) {
  if (!is.data.frame(ps) || !nrow(ps) || !all(c("sub_category", "parameter", "mean") %in% names(ps)) ||
      !is.data.frame(population) || !"year" %in% names(population)) return(invisible(NULL))
  # the trend drops the sheet's label rows (a year that is not a number)
  yr_all <- suppressWarnings(as.integer(as.character(population$year)))
  ok_yr <- !is.na(yr_all) & yr_all >= 1900 & yr_all <= 2100
  ts <- population[ok_yr, , drop = FALSE]; yr <- yr_all[ok_yr]
  years <- sort(unique(yr))
  if (length(years) < 2L) return(invisible(NULL))
  inputs <- intersect(names(ts), PARAM_CATALOGUE$parameter)
  if (!length(inputs)) return(invisible(NULL))

  num <- function(x) suppressWarnings(as.numeric(x))
  fmt <- function(x) format(signif(x, 6), trim = TRUE, big.mark = ",", scientific = FALSE)
  col <- function(df, nm) if (nm %in% names(df)) as.character(df[[nm]]) else rep(NA_character_, nrow(df))
  blank <- function(v) ifelse(is.na(v), "", v)
  quote_cell <- function(v) {
    if (is.na(v) || !nzchar(trimws(v))) return("(blank)")
    v <- trimws(v)
    sprintf("'%s'", if (nchar(v) > 30L) paste0(substr(v, 1, 27), "...") else v)
  }
  norm3 <- function(lv, sc, p) paste(.translator_norm_level(lv), sc, p, sep = "||")
  yr0 <- suppressWarnings(as.integer(.translator_scalar(inventory_year %||% NA)))
  yr_txt <- if (length(yr0) && is.finite(yr0)) as.character(yr0) else "inventory-year"
  TS <- "Parameter_TimeSeries"
  # inputs a file usually gives once for a whole production system (the
  # diet, the milk composition): the same series in two groups of one
  # system is expected, so the identical-series check looks across systems
  per_system <- c("DE", "CP", "Fat", "MilkPR", "pct_pregnant")

  # The trend's own group key (make_group_key, where a blank cell reads
  # "NA"), and the key the workbook annotation matches (a blank reads "").
  t_key <- make_group_key(ts)
  t_ann <- paste(blank(col(ts, "cattle_type")), blank(col(ts, "aggregation_level")),
                 blank(col(ts, "sub_category")), sep = "||")
  t_ct <- col(ts, "cattle_type"); t_lv <- col(ts, "aggregation_level"); t_sc <- col(ts, "sub_category")
  p_key <- make_group_key(ps)
  p_ann <- paste(blank(col(ps, "cattle_type")), blank(col(ps, "aggregation_level")),
                 blank(col(ps, "sub_category")), sep = "||")
  p_ct <- col(ps, "cattle_type"); p_lv <- col(ps, "aggregation_level"); p_sc <- col(ps, "sub_category")
  p_mu <- num(ps$mean); p_par <- as.character(ps$parameter)
  p_keys <- unique(p_key)
  V <- lapply(stats::setNames(inputs, inputs), function(p) num(ts[[p]]))
  any_val <- Reduce(`|`, lapply(V, is.finite))

  # A row whose key matches no Parameters group, but whose system and
  # sub-category name exactly one (a blank cattle_type, say), is counted
  # with that group by the series checks below: the wrong cell is reported
  # once, as rows ignored, and not again as a gap in the group's series.
  r_key <- t_key
  for (k in setdiff(unique(t_key), p_keys)) {
    rk <- which(t_key == k)
    cand <- unique(p_key[.translator_norm_level(p_lv) == .translator_norm_level(t_lv[rk[1]]) & p_sc %in% t_sc[rk[1]]])
    if (length(cand) == 1L) r_key[rk] <- cand
  }

  # One entry per (series group, input) as the sheet gives it, sorted by
  # year; where a year appears twice the later row wins, as in the trend.
  series <- list()
  for (k in unique(r_key[any_val])) {
    rk <- which(r_key == k)
    lab <- sprintf("%s / %s", blank(t_lv[rk[1]]), blank(t_sc[rk[1]]))
    ann <- names(which.max(table(t_ann[rk])))
    for (p in inputs) {
      v <- V[[p]][rk]; ok <- is.finite(v)
      if (!any(ok)) next
      y <- yr[rk][ok]; v <- v[ok]
      keep <- !duplicated(y, fromLast = TRUE); y <- y[keep]; v <- v[keep]; o <- order(y)
      series[[length(series) + 1L]] <- list(key = k, ann = ann, lab = lab,
        sys = .translator_norm_level(t_lv[rk[1]]), lv = blank(t_lv[rk[1]]), sc = blank(t_sc[rk[1]]),
        norm = norm3(t_lv[rk[1]], t_sc[rk[1]], p), p = p, y = y[o], v = v[o])
    }
  }

  # 11. Years covered
  miss_yr <- setdiff(seq(min(years), max(years)), years)
  add("time series: years covered",
      paste0(sprintf("The time series covers %d to %d", min(years), max(years)),
             if (length(miss_yr))
               sprintf(" with %d of the %d years: %s %s missing, so the trend has no result for %s.",
                       length(years), length(years) + length(miss_yr), .translator_year_runs(miss_yr),
                       if (length(miss_yr) == 1L) "is" else "are", if (length(miss_yr) == 1L) "it" else "them")
             else sprintf(" (%d years, none missing).", length(years)),
             if (length(yr0) && is.finite(yr0) && !yr0 %in% years)
               sprintf(" The inventory year %d is not one of them.", yr0) else ""),
      severity = "info", sheet = TS, check = "time series: years covered")

  # 10. Fixed across years by design
  add("time series: fixed across years",
      paste0("Manure system shares, MCF, EF3 and the N fractions (Frac_GasMS, Frac_LeachMS) have no time series: ",
             "the trend uses the same values in every year, as it does for Ym, Cfi and every other input with no ",
             "column on the Parameter_TimeSeries sheet. A year without its own range keeps the relative range of ",
             "the inventory year: a value given as +/-10% keeps +/-10% around each year's value."),
      severity = "info", sheet = TS, check = "time series: fixed across years")

  # 9. Rows the trend ignores: a group key, or a parameter, with no
  #    Parameters row to replace (`if (length(sel) == 0) next` in the trend).
  #    One row per group they were meant for.
  bad <- which(any_val & !t_key %in% p_keys)
  ignored_for <- character(0)   # Parameters groups whose series rows are skipped
  for (k in unique(r_key[bad])) {
    rk <- bad[r_key[bad] == k]
    trip <- paste(t_ct[rk], t_lv[rk], t_sc[rk], sep = "##")
    cells <- vapply(unique(trip), function(tr) {
      i <- rk[match(tr, trip)]; n <- sum(trip == tr)
      sprintf("cattle_type %s, aggregation_level %s, sub_category %s in %d row%s",
              quote_cell(t_ct[i]), quote_cell(t_lv[i]), quote_cell(t_sc[i]), n, if (n == 1L) "" else "s")
    }, character(1))
    j <- match(k, p_key)
    tail_txt <- if (!is.na(j)) {
      ignored_for <- c(ignored_for, k)
      sprintf(paste0(" So %s / %s keeps the %s values of the Parameters sheet in every year. On the Parameters ",
                     "sheet this group is cattle_type %s, aggregation_level %s, sub_category %s: write the same ",
                     "in these rows."),
              blank(p_lv[j]), blank(p_sc[j]), yr_txt, quote_cell(p_ct[j]), quote_cell(p_lv[j]), quote_cell(p_sc[j]))
    } else " Their values are not used. Correct the three cells so they match a row of the Parameters sheet, or delete these rows."
    add(sprintf("%s / %s", blank(t_lv[rk[1]]), blank(t_sc[rk[1]])),
        paste0(sprintf(paste0("The trend run skips %d row%s of the time series (%s): the group named in %s matches ",
                              "no group on the Parameters sheet (%s)."),
                       length(rk), if (length(rk) == 1L) "" else "s", .translator_year_runs(yr[rk]),
                       if (length(rk) == 1L) "it" else "them", paste(cells, collapse = "; ")),
               tail_txt),
        severity = "warn", sheet = TS, group = t_ann[rk[1]], check = "time series: rows ignored")
  }
  for (k in intersect(unique(t_key[any_val]), p_keys)) {
    rk <- which(t_key == k)
    for (p in inputs) {
      if (!any(is.finite(V[[p]][rk])) || any(p_key == k & p_par == p)) next
      add(sprintf("%s / %s / %s", blank(t_lv[rk[1]]), blank(t_sc[rk[1]]), p),
          sprintf(paste0("The time series gives %s for this group, but the Parameters sheet has no %s row for it, ",
                         "so the trend run skips these values. Add the %s row on the Parameters sheet."), p, p, p),
          severity = "warn", sheet = TS, group = t_ann[rk[1]], parameter = p, check = "time series: rows ignored")
    }
  }

  # 1. Inputs held constant, one row per Parameters group. An input with no
  #    value in the group (0 or blank: no milk for bulls) is not listed.
  applies <- function(i0, p) { j <- i0[p_par[i0] == p]; length(j) > 0 && any(is.finite(p_mu[j]) & p_mu[j] != 0) }
  in_series <- function(g, p) any(is.finite(V[[p]][t_key == g]))
  for (g in p_keys) {
    i0 <- which(p_key == g)
    app <- inputs[vapply(inputs, function(p) applies(i0, p), logical(1))]
    has <- app[vapply(app, function(p) in_series(g, p), logical(1))]
    held <- setdiff(app, has)
    if (!length(held)) next
    c11 <- held[norm3(p_lv[i0[1]], p_sc[i0[1]], held) %in% skip]
    see <- if (length(c11))
      sprintf(" %s %s also listed under 'time-series coverage'.", .translator_and(c11),
              if (length(c11) == 1L) "is" else "are") else ""
    msg <- if (g %in% ignored_for)
      sprintf("The time-series rows for this group are skipped (see 'time series: rows ignored'): the trend uses the %s value of %s in every year.",
              yr_txt, .translator_and(held))
    else if (!length(has))
      sprintf("This group has no values on the Parameter_TimeSeries sheet: the trend uses the %s value of %s in every year.",
              yr_txt, .translator_and(held))
    else
      sprintf("%s %s no year-by-year values for this group: the trend uses the %s value in every year.",
              .translator_and(held), if (length(held) == 1L) "has" else "have", yr_txt)
    add(sprintf("%s / %s", blank(p_lv[i0[1]]), blank(p_sc[i0[1]])), paste0(msg, see),
        severity = "info", sheet = TS, group = p_ann[i0[1]],
        parameter = if (length(held) == 1L) held else NA_character_, check = "time series: held constant")
  }

  # 3. Uneven coverage within a production system: an input changes from
  #    year to year for some sub-categories and has no series for others.
  #    A row for a whole system carries no group, so it is listed in the
  #    checks workbook without marking every row of the system.
  sys_id <- paste(blank(p_ct), blank(p_lv), sep = "||")
  for (sy in unique(sys_id)) {
    gs <- unique(p_key[sys_id == sy])
    if (length(gs) < 2L) next
    i_sys <- which(sys_id == sy)
    for (p in inputs) {
      vary <- character(0); none <- character(0)
      for (g in gs) {
        i0 <- i_sys[p_key[i_sys] == g]
        if (!applies(i0, p)) next
        v <- V[[p]][t_key == g]; v <- v[is.finite(v)]
        if (length(unique(signif(v, 9))) >= 2L) vary <- c(vary, p_sc[i0[1]])
        else if (!length(v) && !norm3(p_lv[i0[1]], p_sc[i0[1]], p) %in% skip) none <- c(none, p_sc[i0[1]])
      }
      if (!length(vary) || !length(none)) next
      lv <- p_lv[i_sys[1]]
      add(sprintf("%s / %s", blank(lv), p),
          sprintf(paste0("%s changes from year to year for %s in this production system, but not for %s, ",
                         "which %s the %s value in every year. If the file gives one series for the whole ",
                         "system, it applies to each of these sub-categories."),
                  p, .translator_and(vary), .translator_and(none), if (length(none) == 1L) "keeps" else "keep", yr_txt),
          severity = "info", sheet = TS, parameter = p, check = "time series: uneven within system")
    }
  }

  # 2, 8, 7 and 5, on each series as the sheet gives it.
  rep_hits <- list()
  for (s in series) {
    where_s <- sprintf("%s / %s", s$lab, s$p)
    # 2. Gaps: years the sheet covers that this series lacks
    gap <- setdiff(years, s$y)
    if (length(gap) && !s$norm %in% skip)
      add(where_s,
          sprintf(paste0("%s has values for %d of the %d years; missing: %s. In a missing year the trend uses ",
                         "the %s value from the Parameters sheet, not a value between the neighbouring years."),
                  s$p, length(s$y), length(years), .translator_year_runs(gap), yr_txt),
          severity = "warn", sheet = TS, group = s$ann, parameter = s$p, check = "time series: gap")
    n <- length(s$v)
    if (n < 2L) next
    a <- s$v[-n]; b <- s$v[-1L]; ya <- s$y[-n]; yb <- s$y[-1L]
    # 8. Unit change between two neighbouring values
    ratio <- ifelse(a != 0, b / a, NA_real_)
    unit <- vapply(ratio, function(r) {
      if (!is.finite(r) || r <= 0) return(NA_character_)
      hit <- names(.TRANSLATOR_UNIT_RATIOS)[abs(r / .TRANSLATOR_UNIT_RATIOS - 1) <= 0.03]
      if (length(hit)) hit[1] else NA_character_
    }, character(1))
    if (any(!is.na(unit))) {
      u <- which(!is.na(unit))
      add(where_s,
          sprintf(paste0("%s goes from %s: the unit seems to change inside the series (percent and fraction, ",
                         "per day and per year, kg and tonnes). Write every year in the unit of the Parameters sheet."),
                  s$p, paste(sprintf("%s in %d to %s in %d (a factor of %s)", vapply(a[u], fmt, ""), ya[u],
                                     vapply(b[u], fmt, ""), yb[u], unit[u]), collapse = "; and from ")),
          severity = "warn", sheet = TS, group = s$ann, parameter = s$p, check = "time series: unit change")
    }
    # 7. Large jumps, the unit changes above left out
    rel <- ifelse(a != 0, (b - a) / abs(a), ifelse(b != 0, Inf, 0))
    j <- which(is.na(unit) & abs(rel) > 0.25)
    if (length(j)) {
      lst <- sprintf("%d to %d (%s)", ya[j], yb[j],
                     ifelse(is.finite(rel[j]), sprintf("%+.0f%%", 100 * rel[j]), "from 0"))
      more <- if (length(lst) > 6L) sprintf(" and %d more", length(lst) - 6L) else ""
      add(where_s,
          sprintf(paste0("%s changes by more than 25%% from one year to the next %d time%s: %s%s. Check these ",
                         "against the file: a jump this size can be a real change or a value from the wrong cell."),
                  s$p, length(j), if (length(j) == 1L) "" else "s", paste(utils::head(lst, 6), collapse = ", "), more),
          severity = "info", sheet = TS, group = s$ann, parameter = s$p, check = "time series: large jump")
    }
    # 5. The same value in two neighbouring years while the rest of the
    #    series moves: at most two such pairs, neither next to another (a
    #    run of equal years is a value carried forward, not a slip).
    nb <- yb - ya == 1L
    same <- nb & abs(b - a) <= 1e-9 * pmax(1, abs(a))
    k5 <- which(same)
    if (n >= 5L && length(k5) && length(k5) <= 2L && !any(diff(k5) == 1L) && sum(nb & !same) >= 3L)
      rep_hits[[length(rep_hits) + 1L]] <- list(s = s, txt = paste(sprintf("%d and %d", ya[k5], yb[k5]), collapse = ", in "),
                                                val = paste(vapply(a[k5], fmt, ""), collapse = ", "))
  }
  # one row per system, input and years: a population split by fixed
  # shares repeats the same year in every sub-category of the system
  if (length(rep_hits)) {
    rk5 <- vapply(rep_hits, function(h) paste(h$s$sys, h$s$p, h$txt, sep = "##"), character(1))
    for (k in unique(rk5)) {
      hs <- rep_hits[rk5 == k]; s <- hs[[1]]$s
      who <- vapply(hs, function(h) sprintf("%s (%s)", h$s$sc, h$val), character(1))
      add(if (length(hs) == 1L) sprintf("%s / %s", s$lab, s$p) else sprintf("%s / %s", s$lv, s$p),
          sprintf(paste0("%s is the same in %s for %s, while the rest of the series changes every year. Check that ",
                         "one year's value was not copied into the next."),
                  s$p, hs[[1]]$txt, .translator_and(who)),
          severity = "info", sheet = TS, group = if (length(hs) == 1L) s$ann else NA_character_,
          parameter = s$p, check = "time series: repeated year")
    }
  }

  # 6. The same series in two groups: the same input and the same value in
  #    every common year (at most one year apart when there are five or
  #    more), the series not constant. One row per group, naming the others.
  for (p in inputs) {
    sp <- Filter(function(s) identical(s$p, p) && length(s$v) >= 2L && length(unique(signif(s$v, 9))) >= 2L, series)
    if (length(sp) < 2L) next
    partners <- vector("list", length(sp))
    for (i in seq_along(sp)) for (j in seq_along(sp)) {
      if (i >= j) next
      a <- sp[[i]]; b <- sp[[j]]
      if (p %in% per_system && identical(a$sys, b$sys)) next
      # the two halves of a pooled calves row are equal by design (C1)
      if (identical(a$sys, b$sys) && setequal(c(a$sc, b$sc), c("calves_male", "calves_female"))) next
      cy <- intersect(a$y, b$y)
      if (length(cy) < 2L || length(cy) < 0.9 * max(length(a$y), length(b$y))) next
      va <- a$v[match(cy, a$y)]; vb <- b$v[match(cy, b$y)]
      off <- which(abs(va - vb) > 1e-9 * pmax(1, abs(va)))
      if (length(off) > (if (length(cy) >= 5L) 1L else 0L)) next
      vv <- if (length(off)) va[-off] else va
      if (length(unique(signif(vv, 9))) < 2L) next
      ex <- function(x, y) if (length(off)) sprintf(" (except %d: %s here, %s there)", cy[off], fmt(x[off]), fmt(y[off])) else ""
      partners[[i]] <- c(partners[[i]], paste0(b$lab, ex(va, vb)))
      partners[[j]] <- c(partners[[j]], paste0(a$lab, ex(vb, va)))
    }
    for (i in seq_along(sp)) {
      oth <- partners[[i]]
      if (!length(oth)) next
      s <- sp[[i]]
      who <- if (length(oth) > 3L) sprintf("%s and %d other groups", paste(oth[1:3], collapse = ", "), length(oth) - 3L)
             else .translator_and(oth)
      add(sprintf("%s / %s", s$lab, p),
          sprintf("%s for this group has the same values, year by year (%s), as %s. %s",
                  p, .translator_year_runs(s$y), who,
                  if (identical(p, "N")) "Two groups rarely have the same head count every year: check that one series was not copied to the other."
                  else "This is expected if the file gives one series for these groups; otherwise one series was copied to the other."),
          severity = "info", sheet = TS, group = s$ann, parameter = p, check = "time series: same as another group")
    }
  }
  invisible(NULL)
}

translator_consistency_checks <- function(param_specs, manure = NULL,
                                          source = NULL, population = NULL,
                                          inventory_year = NULL, piece = NULL) {
  out <- list()
  # 2026-10-22: every issue carries a severity (fail, warn, info) and, where
  # it points at cells, the sheet, the group key and the parameter, so the
  # checks workbook and the data workbook can colour them.
  add <- function(where, issue, severity = "warn", sheet = NA_character_,
                  group = NA_character_, parameter = NA_character_, check = NA_character_) {
    if (is.na(check)) check <- .translator_check_name(where)
    out[[length(out) + 1L]] <<- data.frame(where = where, issue = issue,
                                            severity = severity, sheet = sheet,
                                            group = group, parameter = parameter,
                                            check = check, stringsAsFactors = FALSE)
  }
  gkey <- function(df, i) paste(df$cattle_type[i] %||% "", df$aggregation_level[i] %||% "",
                                df$sub_category[i] %||% "", sep = "||")
  fmt <- function(x) format(signif(x, 7), trim = TRUE)

  ps <- param_specs
  if (!is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("sub_category", "parameter", "mean") %in% names(ps))) {
    lvl <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level)
           else rep("", nrow(ps))
    lvl[is.na(lvl)] <- ""
    sc <- as.character(ps$sub_category)
    mu <- suppressWarnings(as.numeric(ps$mean))

    # 1. Calf halves. A source file almost always carries one calves row;
    #    the template splits it into calves_male and calves_female, and both
    #    halves should then carry the same numbers.
    for (L in unique(lvl)) {
      a <- which(lvl == L & sc == "calves_male")
      b <- which(lvl == L & sc == "calves_female")
      if (!length(a) || !length(b)) next
      m <- merge(data.frame(parameter = ps$parameter[a], m = mu[a], stringsAsFactors = FALSE),
                 data.frame(parameter = ps$parameter[b], f = mu[b], stringsAsFactors = FALSE),
                 by = "parameter")
      # Head counts are allowed to differ by one animal: an odd pooled
      # population splits into halves that differ by 0.5 or 1.
      tol <- ifelse(m$parameter == "N", 1, 1e-9 * pmax(1, abs(m$m)))
      m <- m[!is.na(m$m) & !is.na(m$f) & abs(m$m - m$f) > tol, , drop = FALSE]
      if (nrow(m)) {
        add(sprintf("%s%scalves", L, if (nzchar(L)) " / " else ""),
            sprintf(paste0("Male and female calves carry different values for %s. ",
                           "If the source file has a single calves row, both halves ",
                           "should be identical to it."),
                    paste(sprintf("%s (%s vs %s)", m$parameter, fmt(m$m), fmt(m$f)),
                          collapse = ", ")),
            sheet = "Parameters", group = gkey(ps, a[1]), check = "calves halves")
      }
    }

    # 2. Uncertainty far below the rest of the file for the same parameter:
    #    a fraction copied where a percentage was expected (0.5 for 50 %).
    if ("uncertainty_pct" %in% names(ps)) {
      u_all <- suppressWarnings(as.numeric(ps$uncertainty_pct))
      # a row with explicit bounds takes its spread from them, not from
      # uncertainty_pct (2026-10-23)
      lo2 <- if ("lower" %in% names(ps)) suppressWarnings(as.numeric(ps$lower)) else rep(NA_real_, nrow(ps))
      hi2 <- if ("upper" %in% names(ps)) suppressWarnings(as.numeric(ps$upper)) else rep(NA_real_, nrow(ps))
      has_bounds <- is.finite(lo2) | is.finite(hi2)
      for (p in unique(ps$parameter)) {
        idx <- which(ps$parameter == p & !is.na(u_all) & u_all > 0)
        if (length(idx) < 3) next
        med <- stats::median(u_all[idx])
        if (med < 5) next
        for (i in idx[u_all[idx] < 1 & !has_bounds[idx]]) {
          add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], p),
              sprintf(paste0("Uncertainty %s%% is far below the %s%% typical for %s in this ",
                             "file. A fraction may have been copied instead of a percentage."),
                      fmt(u_all[i]), fmt(med), p),
              sheet = "Parameters", group = gkey(ps, i), parameter = p, check = "uncertainty scale")
        }
      }
    }

    # 3. A distribution that cannot represent the value it was given, as
    #    the app's sampler reads it (utils_distributions.R): a beta is drawn
    #    between lower and upper on any scale, so it needs bounds that
    #    enclose the value strictly (until 2026-10-28 this rule wanted the
    #    value in (0, 1) and failed a valid beta on milk fat at 3.4 %); a
    #    log-normal reads its spread on the log scale, so its lower bound
    #    must be above 0. The app's QA/QC fails the same rows; naming them
    #    here lets the compiler fix the source before upload.
    if ("distribution" %in% names(ps)) {
      d <- tolower(as.character(ps$distribution))
      lo <- if ("lower" %in% names(ps)) suppressWarnings(as.numeric(ps$lower)) else rep(NA_real_, nrow(ps))
      hi <- if ("upper" %in% names(ps)) suppressWarnings(as.numeric(ps$upper)) else rep(NA_real_, nrow(ps))
      bad_beta <- which(d == "beta" & !is.na(mu) & (is.na(lo) | is.na(hi) | !(lo < mu & mu < hi)))
      for (i in bad_beta)
        add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], ps$parameter[i]),
            sprintf("A beta distribution was assigned to a value of %s with bounds that do not enclose it (lower %s, upper %s). The app draws a beta between the bounds; give bounds around the value, or use a normal or triangular distribution.", fmt(mu[i]), fmt(lo[i]), fmt(hi[i])),
            sheet = "Parameters", group = gkey(ps, i), parameter = ps$parameter[i], check = "distribution fit")
      bad_ln <- which(d == "lognormal" & !is.na(mu) & (mu <= 0 | (!is.na(lo) & lo <= 0)))
      for (i in bad_ln)
        add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], ps$parameter[i]),
            sprintf("A log-normal distribution was assigned with a lower bound of %s (value %s). The app reads the spread on the log scale, so the value and the lower bound must be above 0.", fmt(lo[i]), fmt(mu[i])),
            sheet = "Parameters", group = gkey(ps, i), parameter = ps$parameter[i], check = "distribution fit")
      if (all(c("lower", "upper") %in% names(ps))) {
        bad_b <- which(!is.na(mu) & !is.na(lo) & !is.na(hi) & d != "constant" & (lo > mu | mu > hi))
        for (i in bad_b)
          add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], ps$parameter[i]),
              sprintf("The bounds %s to %s do not bracket the mean %s. Either the mean or the bounds came from a different year or group of the source file.", fmt(lo[i]), fmt(hi[i]), fmt(mu[i])),
              sheet = "Parameters", group = gkey(ps, i), parameter = ps$parameter[i], check = "bounds bracket mean")
      }
    }
  }

  mm <- manure
  if (!is.null(mm) && is.data.frame(mm) && nrow(mm) > 0 &&
      all(c("sub_category", "mms_type", "fraction_pct") %in% names(mm))) {
    mlvl <- if ("aggregation_level" %in% names(mm)) as.character(mm$aggregation_level)
            else rep("", nrow(mm))
    mlvl[is.na(mlvl)] <- ""
    key <- paste0(mlvl, ifelse(nzchar(mlvl), " / ", ""), as.character(mm$sub_category))
    fr <- suppressWarnings(as.numeric(mm$fraction_pct))

    # 4. Shares of manure systems must sum to 100 % for each animal group.
    for (k in unique(key)) {
      if (all(is.na(fr[key == k]))) next   # placeholder or empty rows
      s <- sum(fr[key == k], na.rm = TRUE)
      if (abs(s - 100) > 1)
        add(k, sprintf("Manure system shares sum to %s%%, not 100%%. A system may have been added or a share copied from another group.", fmt(s)),
            sheet = "Manure_Management", group = gkey(mm, which(key == k)[1]), parameter = "fraction_pct", check = "manure shares sum")
    }

    # 5. One manure system, one set of coefficients. MCF depends on climate
    #    and system, not on which herd uses it, so different values for the
    #    same system across the file point at a copy error.
    #    2026-10-23: within a cattle type. The IPCC tables and the Zambia
    #    file give dairy and other cattle different Frac_GasMS for the same
    #    system, which is not a copy error.
    coef_cols <- intersect(c("MCF_pct", "EF3", "Frac_GasMS_pct", "Frac_LeachMS_pct"), names(mm))
    ct <- if ("cattle_type" %in% names(mm)) as.character(mm$cattle_type) else rep("", nrow(mm)); ct[is.na(ct)] <- ""
    mtyp <- as.character(mm$mms_type); mtyp[is.na(mtyp)] <- ""
    for (col in coef_cols) {
      v <- suppressWarnings(as.numeric(mm[[col]]))
      for (g in unique(paste(ct, mtyp, sep = "##"))) {
        parts <- strsplit(g, "##", fixed = TRUE)[[1]]
        ct_i <- parts[1]; mt <- if (length(parts) > 1) parts[2] else ""
        sel <- which(ct == ct_i & mtyp == mt & !is.na(v))
        vals <- unique(round(v[sel], 6))
        if (length(vals) < 2) next
        by_val <- vapply(vals, function(x) {
          grp <- unique(key[sel][round(v[sel], 6) == x])
          sprintf("%s in %s", fmt(x), paste(utils::head(grp, 3), collapse = ", "))
        }, character(1))
        add(mt, sprintf("%s takes %d different values for the same manure system%s: %s. Check which one the source file gives.",
                        col, length(vals), if (nzchar(ct_i)) paste0(" (", ct_i, ")") else "", paste(by_val, collapse = "; ")),
            sheet = "Manure_Management", parameter = col, check = "manure coefficient consistency")
      }
    }

    # 6. One bound pair reused across every manure row (Andreas, 2026-09-30).
    #    On the Zambia file the source gave a RELATIVE MoE of +/-50 % per
    #    share; the translator wrote lower = 0, upper = 50 on every row
    #    instead, so a 40 % dry-lot share and a 1.25 % digester share were
    #    given the same bounds. Every existing check passed it: the bounds
    #    bracket each mean and the centrals still sum to 100. The tell is
    #    that one bound pair repeats across rows whose centrals differ.
    if (all(c("lower_fraction", "upper_fraction") %in% names(mm))) {
      lo <- suppressWarnings(as.numeric(mm$lower_fraction))
      hi <- suppressWarnings(as.numeric(mm$upper_fraction))
      ok <- !is.na(lo) & !is.na(hi) & !is.na(fr)
      if (sum(ok) >= 3L) {
        pair <- paste(round(lo[ok], 6), round(hi[ok], 6), sep = "|")
        # EVERY repeated pair is examined, not just the commonest one. A
        # partly-corrected file can carry the error on a minority of rows
        # while some larger, entirely legitimate group sits above it: on the
        # Zambia file, once the 102 worst rows were fixed, the largest group
        # became 32 rows that correctly share both a bound pair AND a share,
        # which hid 21 rows that were still wrong.
        for (pv in names(table(pair))) {
          sel  <- which(pair == pv)
          n_sh <- length(sel)
          # Only a finding when the shares those rows carry actually differ:
          # several systems genuinely sitting at the same share may
          # legitimately share bounds, and that is not a mistake.
          if (n_sh < 3L) next
          cen <- unique(round(fr[ok][sel], 6))
          if (length(cen) < 2L) next
          b  <- as.numeric(strsplit(pv, "|", fixed = TRUE)[[1]])
          bg <- max(fr[ok][sel])
          add("Manure_Management",
              sprintf(paste0("%d of %d manure rows carry the same bounds (%s to %s) on shares that differ (%s). ",
                             "If the source gives a relative uncertainty, say +/-50%%, the bounds should be a ",
                             "percentage OF EACH SHARE, so a %s%% share becomes %s to %s, not %s to %s."),
                      n_sh, sum(ok), fmt(b[1]), fmt(b[2]),
                      paste(fmt(utils::head(sort(cen), 3)), collapse = ", "),
                      fmt(bg), fmt(bg * 0.5), fmt(bg * 1.5), fmt(b[1]), fmt(b[2])),
              sheet = "Manure_Management", parameter = "lower_fraction", check = "manure bounds reused")
        }
      }
    }

    # 7. A per-MMS coefficient given a central value but no bounds anywhere
    #    (Andreas, 2026-09-30). The engine treats a blank bound pair as
    #    EXACTLY KNOWN: sample_per_mms_param() returns a zero-variance column,
    #    so the source's stated uncertainty is dropped rather than replaced by
    #    a default. On the Zambia file MCF came through correctly but its
    #    +/-25 % did not, and nothing said so.
    for (col in coef_cols) {
      lo_col <- switch(col, MCF_pct = "lower_mcf", EF3 = "lower_ef3",
                       Frac_GasMS_pct = "lower_frac_gas",
                       Frac_LeachMS_pct = "lower_frac_leach", NULL)
      hi_col <- switch(col, MCF_pct = "upper_mcf", EF3 = "upper_ef3",
                       Frac_GasMS_pct = "upper_frac_gas",
                       Frac_LeachMS_pct = "upper_frac_leach", NULL)
      if (is.null(lo_col)) next
      v <- suppressWarnings(as.numeric(mm[[col]]))
      n_val <- sum(!is.na(v))
      if (n_val == 0L) next
      lo <- if (lo_col %in% names(mm)) suppressWarnings(as.numeric(mm[[lo_col]])) else rep(NA_real_, nrow(mm))
      hi <- if (hi_col %in% names(mm)) suppressWarnings(as.numeric(mm[[hi_col]])) else rep(NA_real_, nrow(mm))
      if (all(is.na(lo)) && all(is.na(hi)))
        add("Manure_Management",
            sprintf(paste0("%s has a value on %d row(s) but no lower or upper bound on any of them, so the tool will ",
                           "treat it as exactly known and its uncertainty will not reach the result. If the source ",
                           "gives a range for it, add %s and %s."),
                    col, n_val, lo_col, hi_col),
            sheet = "Manure_Management", parameter = col, check = "manure bounds missing")
    }
  }

  # ---- source reconciliation ------------------------------------------
  if (!is.null(source) && is.data.frame(ps) && nrow(ps) > 0 &&
      "data_source" %in% names(ps)) {
    # a placeholder range tag does not change where the value came from
    dsrc <- sub("; *placeholder range.*$", "", tolower(as.character(ps$data_source)))
    dsrc[is.na(dsrc)] <- ""
    val  <- suppressWarnings(as.numeric(ps$mean))
    lvl2 <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level)
            else rep("", nrow(ps))
    lvl2[is.na(lvl2)] <- ""

    # C3. A row tagged user_file claims the number appears in the file as
    # written. Anything else is either a transcription error or invented.
    # Derived values are tagged user_chat and are exempt by design.
    if (length(source$numbers)) {
      verbatim <- dsrc == "user_file" & is.finite(val) & val != 0
      if (any(verbatim)) {
        cand <- unique(as.vector(outer(source$numbers,
                                       .TRANSLATOR_VALUE_TRANSFORMS, "*")))
        seen <- vapply(val[verbatim], function(v)
          any(abs(cand - v) <= 5e-4 * max(1, abs(v))), logical(1))
        if (any(!seen)) {
          miss <- which(verbatim)[!seen]
          for (i in miss)
            add(sprintf("%s%s%s / %s", lvl2[i], ifelse(nzchar(lvl2[i]), " / ", ""), ps$sub_category[i], ps$parameter[i]),
                sprintf(paste0(
                  "%s = %s is marked as taken from your file but no matching number is in it ",
                  "(%d such value(s) in all). Either the value was altered, or it was computed ",
                  "and should be marked user_chat rather than user_file."),
                  ps$parameter[i], fmt(val[i]), length(miss)),
                sheet = "Parameters", group = gkey(ps, i), parameter = ps$parameter[i], check = "value not in file")
        }
      }
    }

    # C1. A population read from the file belongs to one group. The same
    # number under two groups is the signature of a double count, which is
    # how one run came to report ten per cent more animals than the file.
    isN <- ps$parameter %in% c("N", "cattle_pop") & dsrc == "user_file" &
           is.finite(val) & val > 0
    if (sum(isN) > 1) {
      key <- paste(lvl2[isN], ps$sub_category[isN])
      dup <- val[isN][duplicated(round(val[isN], 4))]
      if (length(dup)) {
        for (d in unique(dup)) {
          same <- round(val[isN], 4) == round(d, 4)
          w <- key[same]
          for (i in which(isN)[same])
            add("source reconciliation", sprintf(paste0(
              "The population %s appears on %d groups (%s). A head count read ",
              "from the file belongs to one group, so this is usually the same ",
              "animals counted twice."), fmt(d), length(w),
              paste(utils::head(w, 4), collapse = ", ")),
              sheet = "Parameters", group = gkey(ps, i), parameter = "N", check = "duplicate population")
        }
      }
    }

    # C14 (2026-10-30, Lolita). GE or DMI carries a value while the uploaded
    # file has neither: a measured intake nobody measured, which replaces the
    # energy balance for the group. The server removes these before writing
    # (.translator_drop_unsourced_intake); this catches anything that slips.
    opt_p <- PARAM_CATALOGUE$parameter[PARAM_CATALOGUE$param_tier %in% "optional"]
    opt_v <- suppressWarnings(as.numeric(ps$mean))
    # Any value counts, 0 included: the rule is that the input is not there.
    bad_i <- which(ps$parameter %in% setdiff(opt_p, source$families %||% character(0)) &
                   !is.na(opt_v))
    for (pn in unique(ps$parameter[bad_i])) {
      i <- bad_i[ps$parameter[bad_i] == pn]
      for (j in i)
        add("measured intake", sprintf(paste0(
          "%s has a value on %d row(s) (%s), but your file has no %s. Leave the ",
          "value blank unless it was measured: a value here replaces the energy ",
          "balance for the group (before 31 October, a 0 did as well)."),
          pn, length(i), paste(utils::head(unique(lvl2[i]), 4), collapse = ", "), pn),
          severity = "fail", sheet = "Parameters", group = gkey(ps, j), parameter = pn,
          check = "measured intake not in the file")
    }

    # C4. The template says a parameter was gap-filled, while the scan found
    # that parameter in the uploaded file. One of the two is wrong, and the
    # user should be the one to decide which.
    if (length(source$families)) {
      filled <- grepl("ipcc|default|auto", dsrc) & ps$parameter %in% source$families
      if (any(filled)) {
        by_p <- split(which(filled), ps$parameter[filled])
        for (pn in names(by_p)) {
          i <- by_p[[pn]]
          for (j in i)
            add("source reconciliation", sprintf(paste0(
              "%s was filled from the IPCC default on %d row(s) (%s), but %s is ",
              "present in your file. Check whether the file's value should have ",
              "been used."), pn, length(i),
              paste(utils::head(unique(lvl2[i]), 4), collapse = ", "), pn),
              sheet = "Parameters", group = gkey(ps, j), parameter = pn, check = "default replaced file value")
        }
      }
    }
  }

  # C3m (2026-10-23). A manure coefficient must be a number of the file
  # when the file carries that coefficient at all (the scan found the
  # family). The Zambia run of 15:50 came out with MCF 4.59 and 50 and
  # Frac_GasMS 48, none of which exist in the file, and nothing said so:
  # C5 compares against the file's own column, which the row-block layout
  # of the Coefficients sheet does not yield.
  if (!is.null(source) && length(source$numbers) && !is.null(manure) && is.data.frame(manure) && nrow(manure) > 0) {
    fam_of <- c(MCF_pct = "MCF", EF3 = "EF3", Frac_GasMS_pct = "Frac_GasMS", Frac_LeachMS_pct = "Frac_LeachMS")
    cand <- unique(as.vector(outer(source$numbers, .TRANSLATOR_VALUE_TRANSFORMS, "*")))
    for (cn in intersect(names(fam_of), names(manure))) {
      if (!fam_of[[cn]] %in% (source$families %||% character(0))) next
      v <- suppressWarnings(as.numeric(manure[[cn]]))
      for (i in which(is.finite(v) & v > 0)) {
        if (any(abs(cand - v[i]) <= 5e-4 * max(1, abs(v[i])))) next
        add(sprintf("%s / %s / %s", manure$aggregation_level[i] %||% "", manure$sub_category[i], cn),
            sprintf(paste0("%s = %s is not a number in your file, which does carry %s. The AI may have invented or ",
                           "mis-assigned this coefficient; check the file's value for this manure system."),
                    cn, fmt(v[i]), fam_of[[cn]]),
            severity = "warn", sheet = "Manure_Management", group = gkey(manure, i), parameter = cn, check = "value not in file")
      }
    }
  }

  # C5. The same question as C4, asked of the Manure_Management sheet.
  # C4 only sees param_specs, so a coefficient that lives on the manure
  # sheet escaped it entirely: the Colombian file gives a direct N2O
  # emission factor as "FE N2O" = 0.009 and a Bo of 0.19, and the template
  # was written with the IPCC 0.02 and 0.13, with nothing to notice.
  #
  # The comparison is against the source's OWN column for that coefficient,
  # not the workbook's number pool: 0.02 passes a pool test by matching an
  # unrelated 2 divided by 100. Percent against fraction is tolerated,
  # since the sheets differ on that and it is not an error.
  if (!is.null(source) && !is.null(manure) && is.data.frame(manure) &&
      nrow(manure) > 0 && length(source$family_values %||% list())) {
    fv <- source$family_values
    col_fam <- c(MCF_pct = "MCF", EF3 = "EF3", Bo = "Bo",
                 Frac_GasMS_pct = "Frac_GasMS", Frac_LeachMS_pct = "Frac_LeachMS")
    for (cn in names(col_fam)) {
      fam <- col_fam[[cn]]
      if (!cn %in% names(manure) || is.null(fv[[fam]]) || !length(fv[[fam]])) next
      v <- suppressWarnings(as.numeric(manure[[cn]]))
      v <- unique(v[is.finite(v) & v != 0])
      if (!length(v)) next
      ref <- unique(c(fv[[fam]], fv[[fam]] * 100, fv[[fam]] / 100))
      seen <- vapply(v, function(z)
        any(abs(ref - z) <= 1e-3 * max(1, abs(z))), logical(1))
      if (!all(seen)) {
        add("source reconciliation", sprintf(paste0(
          "Manure_Management: %s is set to %s, but your file's own %s column ",
          "gives %s. An IPCC default appears to have replaced a value your ",
          "file supplies. Check which should be used."),
          cn, paste(fmt(v[!seen]), collapse = ", "), fam,
          paste(fmt(utils::head(sort(fv[[fam]]), 4)), collapse = ", ")),
          sheet = "Manure_Management", parameter = cn, check = "default replaced file value")
      }
    }
  }

  # C6 (2026-10-22, WP2): every category the AI listed in the source must
  # be a group in the template, unless the user confirmed a merge. One
  # source category becomes one template category; a missing one is a
  # failure, because the template then simply has fewer animals.
  if (!is.null(source) && length(source$source_categories) &&
      !is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("sub_category", "aggregation_level") %in% names(ps))) {
    norm <- function(x) gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x))))
    have <- unique(paste(norm(ps$aggregation_level), norm(ps$sub_category), sep = "||"))
    have_sc <- unique(norm(ps$sub_category))
    reg <- source$register %||% list()
    merge_confirmed <- function(label) {
      e <- reg[[paste0("category:", label)]]
      !is.null(e) && identical(e$basis, "user") && grepl("merge|fusion|combine", tolower(e$decision %||% ""))
    }
    missing <- character(0)
    for (sc in source$source_categories) {
      if (nzchar(sc$merge_into %||% "") && merge_confirmed(sc$label)) next
      code <- norm(sc$sub_category %||% "")
      lvl  <- norm(sc$aggregation_level %||% "")
      found <- if (nzchar(code) && nzchar(lvl)) paste(lvl, code, sep = "||") %in% have
               else if (nzchar(code)) code %in% have_sc
               else TRUE
      if (!found) missing <- c(missing, sprintf("%s (%s / %s)", sc$label, sc$aggregation_level %||% "", sc$sub_category %||% ""))
    }
    n_src <- length(source$source_categories)
    n_tpl <- length(have)
    if (length(missing)) {
      add("category coverage", sprintf(paste0(
        "The source file lists %d categories and the template has %d groups; ",
        "%d source categor%s not in the template: %s. Every source category must ",
        "appear unless you confirmed a merge in the conversation."),
        n_src, n_tpl, length(missing), if (length(missing) == 1L) "y is" else "ies are",
        paste(utils::head(missing, 8), collapse = "; ")), severity = "fail", sheet = "Parameters")
    } else {
      add("category coverage", sprintf("Source categories: %d; template groups: %d; every source category is in the template.", n_src, n_tpl),
          severity = "info", sheet = "Parameters")
    }
  }

  # C7 (2026-10-22, WP3): the Parameters sheet and the Parameter_TimeSeries
  # sheet must agree for the inventory year, group by group and parameter by
  # parameter; and the time series' per-year population totals must be
  # found among the source's own year-column sums when the file has them.
  if (!is.null(population) && is.data.frame(population) && nrow(population) > 0 &&
      !is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("cattle_type", "aggregation_level", "sub_category", "year") %in% names(population))) {
    yr0 <- suppressWarnings(as.integer(.translator_scalar(inventory_year %||% NA)))
    pcols <- setdiff(intersect(names(population), PARAM_CATALOGUE$parameter), character(0))
    if (!is.na(yr0) && length(pcols)) {
      py <- population[suppressWarnings(as.integer(population$year)) == yr0, , drop = FALSE]
      ps_key <- paste(gkey(ps, seq_len(nrow(ps))), ps$parameter, sep = "##")
      ps_mu  <- suppressWarnings(as.numeric(ps$mean))
      n_bad <- 0L
      for (i in seq_len(nrow(py))) for (pc in pcols) {
        v_ts <- suppressWarnings(as.numeric(py[[pc]][i]))
        if (!is.finite(v_ts)) next
        k <- paste(gkey(py, i), pc, sep = "##")
        j <- match(k, ps_key)
        if (is.na(j) || !is.finite(ps_mu[j])) next
        if (abs(v_ts - ps_mu[j]) > 0.005 * max(1e-9, abs(ps_mu[j]))) {
          n_bad <- n_bad + 1L
          add(sprintf("%s / %s / %s", py$aggregation_level[i], py$sub_category[i], pc),
              sprintf(paste0("Parameters gives %s for %s but Parameter_TimeSeries gives %s for the ",
                             "inventory year %d. The two sheets must agree; one of them has the wrong value."),
                      fmt(ps_mu[j]), pc, fmt(v_ts), yr0),
              severity = "fail", sheet = "Parameters", group = gkey(py, i), parameter = pc, check = "Parameters vs time series")
        }
      }
      if (n_bad == 0L && nrow(py))
        add("Parameters vs time series", sprintf("Parameters and Parameter_TimeSeries agree for the inventory year %d on every group and parameter checked.", yr0),
            severity = "info", sheet = "Parameters")
    }
    if ("N" %in% names(population) && !is.null(source) && length(source$year_sums)) {
      yrs <- suppressWarnings(as.integer(population$year))
      tot <- tapply(suppressWarnings(as.numeric(population$N)), yrs, sum, na.rm = TRUE)
      for (y in names(tot)) {
        cand <- source$year_sums[[y]]
        if (is.null(cand) || !is.finite(tot[[y]]) || tot[[y]] <= 0) next
        if (!any(abs(cand - tot[[y]]) <= 0.01 * tot[[y]]))
          add(sprintf("year %s", y),
              sprintf(paste0("The template's total population for %s is %s, but no column of the source ",
                             "file headed %s sums to that (closest: %s). A group may carry a value from ",
                             "a neighbouring year or column."),
                      y, fmt(tot[[y]]), y, fmt(cand[which.min(abs(cand - tot[[y]]))])),
              severity = "warn", sheet = "Parameter_TimeSeries", parameter = "N", check = "time series totals")
      }
    }
  }

  # C10 (2026-10-30): one parameter, one distribution across the systems.
  # On the Zambia file of 30 October the file named "normal" for Ym in all
  # five systems and one batch came back with PERT. A minority shape among
  # three or more systems, against a clear majority, is listed for review.
  if (!is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("parameter", "distribution", "mean") %in% names(ps))) {
    lv10 <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level) else rep("", nrow(ps))
    lv10[is.na(lv10)] <- ""
    d10 <- tolower(trimws(as.character(ps$distribution))); m10 <- suppressWarnings(as.numeric(ps$mean))
    for (p in unique(as.character(ps$parameter))) {
      idx <- which(ps$parameter == p & !is.na(d10) & nzchar(d10) & !d10 %in% c("constant", "const") &
                   is.finite(m10) & m10 != 0)
      if (!length(idx)) next
      by_lvl <- tapply(d10[idx], lv10[idx], function(x) names(sort(table(x), decreasing = TRUE))[1])
      if (length(by_lvl) < 3) next
      tb <- table(by_lvl); maj <- names(tb)[which.max(tb)]
      if (max(tb) == length(by_lvl) || max(tb) <= length(by_lvl) / 2) next
      for (L in names(by_lvl)[by_lvl != maj])
        add(sprintf("%s / %s", L, p),
            sprintf(paste0("%s uses '%s' in %s but '%s' in %d other production systems (%s). ",
                           "If the file names one distribution for %s, every system should carry it."),
                    p, by_lvl[[L]], L, maj, max(tb), paste(names(by_lvl)[by_lvl == maj], collapse = ", "), p),
            severity = "info", sheet = "Parameters", parameter = p, check = "distribution differs between systems")
    }
  }

  # C11 and C12 (2026-10-30): the time series against the source.
  # C11, coverage: a value the file gives year by year must have a series
  # for that group. On the Zambia file of 30 October the series covered the
  # cows only in three systems (DE and CP of 12 other groups, and the
  # feedlot weights, were blank), so a trend run held those values at the
  # 2024 level for 35 years. A value is "given year by year" when it is the
  # inventory-year value of a source row that changes over the years.
  # C12, year column: each series value must be in the file's column for
  # that year; a value found only in another year's column was copied from
  # the wrong column (emergent beef calves 2023 carried the 2024 count).
  tsp <- intersect(c("N", "BW", "MW", "WG", "Milk", "Fat", "pct_pregnant", "DE", "CP", "MilkPR"),
                   if (is.data.frame(population)) names(population) else character(0))
  # tol_abs: a head count split into halves is rounded (25,927 calves give
  # 12,963 per half), so N matches its source within one animal.
  near_in <- function(x, s, tol = 1e-6, tol_abs = 0) {
    if (!length(s) || !is.finite(x)) return(FALSE)
    k <- findInterval(x, s)
    cand <- s[unique(pmax(1, pmin(length(s), c(k - 1L, k, k + 1L, k + 2L))))]
    any(abs(cand - x) <= max(tol * max(1, abs(x)), tol_abs))
  }
  ts_flagged <- character(0)   # level||sub_category||parameter rows C11 reported
  if (length(tsp) && nrow(population) > 0 && "year" %in% names(population) &&
      !is.null(ps) && is.data.frame(ps) && nrow(ps) > 0) {
    ts_lv <- if ("aggregation_level" %in% names(population)) .translator_norm_level(population$aggregation_level) else rep("", nrow(population))
    ts_key <- paste(ts_lv, population$sub_category, sep = "||")
    ts_n <- function(L, S, p) sum(is.finite(suppressWarnings(as.numeric(population[[p]][ts_key == paste(L, S, sep = "||")]))))
    p_lv <- if ("aggregation_level" %in% names(ps)) .translator_norm_level(ps$aggregation_level) else rep("", nrow(ps))
    p_mu <- suppressWarnings(as.numeric(ps$mean))
    p_src <- if ("data_source" %in% names(ps)) as.character(ps$data_source) else rep("user_file", nrow(ps))
    flagged <- character(0)
    yr0 <- suppressWarnings(as.integer(inventory_year))
    vr <- if (!is.null(source)) source$varying_rows else NULL
    if (length(vr) && length(yr0) && is.finite(yr0)) {
      at0 <- vapply(vr, function(v) { x <- v[as.character(yr0)]; if (length(x) && is.finite(x)) unname(x) else NA_real_ }, numeric(1))
      nyr <- vapply(vr, length, integer(1))
      for (i in which(ps$parameter %in% tsp & grepl("^user", p_src) & is.finite(p_mu) & p_mu != 0)) {
        v <- p_mu[i]
        hit <- which(is.finite(at0) & (abs(at0 - v) <= 1e-6 * max(1, abs(v)) |
                                       abs(at0 / 2 - v) <= 1e-6 * max(1, abs(v))))
        if (!length(hit)) next
        p <- as.character(ps$parameter[i]); L <- p_lv[i]; S <- as.character(ps$sub_category[i])
        n <- ts_n(L, S, p); need <- max(nyr[hit])
        k <- paste(L, S, p, sep = "||")
        if (n == 0L) {
          flagged <- c(flagged, k)
          add(sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", S, p),
              sprintf(paste0("The file gives %s for this group year by year (%d years), but the time series ",
                             "has no %s values for it. A trend run would hold it at the %d value for every year."),
                      p, need, p, yr0),
              severity = "fail", sheet = "Parameter_TimeSeries", group = gkey(ps, i), parameter = p,
              check = "time-series coverage")
        } else if (n < need - 1L) {
          flagged <- c(flagged, k)
          # the years the sheet has and this group's series lacks, so the
          # trend gap check need not repeat this row
          ts_yrs <- suppressWarnings(as.integer(population$year))
          have <- ts_yrs[ts_key == paste(L, S, sep = "||") & is.finite(suppressWarnings(as.numeric(population[[p]])))]
          miss <- setdiff(ts_yrs[!is.na(ts_yrs)], have)
          add(sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", S, p),
              sprintf("The file gives %s for this group for %d years; the time series has %d of them.%s", p, need, n,
                      if (length(miss)) sprintf(" Missing: %s.", .translator_year_runs(miss)) else ""),
              severity = "warn", sheet = "Parameter_TimeSeries", group = gkey(ps, i), parameter = p,
              check = "time-series coverage")
        }
      }
    }
    # Without a source: a group whose value equals another group's
    # inventory-year series value in the same system, and has no series.
    if (length(yr0) && is.finite(yr0)) {
      py0 <- population[suppressWarnings(as.integer(population$year)) == yr0, , drop = FALSE]
      py0_lv <- if ("aggregation_level" %in% names(py0)) .translator_norm_level(py0$aggregation_level) else rep("", nrow(py0))
      for (i in which(ps$parameter %in% tsp & is.finite(p_mu) & p_mu != 0)) {
        p <- as.character(ps$parameter[i]); L <- p_lv[i]; S <- as.character(ps$sub_category[i])
        k <- paste(L, S, p, sep = "||")
        if (k %in% flagged || ts_n(L, S, p) > 0L) next
        sib <- suppressWarnings(as.numeric(py0[[p]][py0_lv == L & py0$sub_category != S]))
        if (!any(is.finite(sib) & abs(sib - p_mu[i]) <= 1e-6 * max(1, abs(p_mu[i])))) next
        flagged <- c(flagged, k)
        add(sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", S, p),
            sprintf(paste0("Other groups of this production system have a %s series with the same %d value, ",
                           "but this group has none. If the file gives one series for these groups, copy it to each."),
                    p, yr0),
            severity = "fail", sheet = "Parameter_TimeSeries", group = gkey(ps, i), parameter = p,
            check = "time-series coverage")
      }
    }
    ts_flagged <- flagged
    yv <- if (!is.null(source)) source$year_values else NULL
    if (length(yv)) {
      tr <- c(1, 0.5, 2, 100, 0.01)
      yrs_ts <- as.character(suppressWarnings(as.integer(population$year)))
      for (r in seq_len(nrow(population))) {
        y <- yrs_ts[r]; s0 <- yv[[y]]
        if (is.null(s0)) next
        for (p in tsp) {
          v <- suppressWarnings(as.numeric(population[[p]][r]))
          if (!is.finite(v) || v == 0) next
          cand <- v / tr
          # one animal of rounding on the head-count readings only (x1, x2,
          # x0.5), never on the unit conversions (x100 matched 433.41 to 434)
          ta <- if (identical(p, "N")) ifelse(tr %in% c(1, 0.5, 2), 1.01, 0) else rep(0, length(tr))
          if (any(mapply(function(cc, tt) near_in(cc, s0, tol_abs = tt), cand, ta))) next
          other <- names(yv)[vapply(names(yv), function(yy) yy != y &&
                                    any(vapply(cand, near_in, logical(1), s = yv[[yy]], tol_abs = 0)), logical(1))]
          if (!length(other)) next
          add(sprintf("%s / %s / %s / %s", population$aggregation_level[r] %||% "", population$sub_category[r], p, y),
              sprintf(paste0("The time series gives %s for %s in %s, but the file's %s column does not have this ",
                             "number; it is the file's value for %s. A neighbouring year's column was probably copied."),
                      fmt(v), p, y, y, paste(utils::head(other, 3), collapse = ", ")),
              severity = "fail", sheet = "Parameter_TimeSeries", group = gkey(population, r), parameter = p,
              check = "time-series year")
        }
      }
    }
  }

  # C13 (2026-10-30): what the trend run will do with the time series, for
  # the country team (see .translator_trend_checks). C7 above already
  # compares the inventory year with the Parameters sheet, and C11 reports
  # the inputs the file gives year by year, so neither is repeated here.
  if (is.data.frame(population) && nrow(population) > 0)
    tryCatch(.translator_trend_checks(ps, population, inventory_year, add, skip = ts_flagged),
             error = function(e) message("translator checks: the time-series checks failed (", conditionMessage(e), ")"))

  # C8 (2026-10-22, WP3): percent and fraction follow the catalogue units.
  # A % parameter below 1, or a fraction above 1, is a unit mistake that
  # the simulation cannot detect (DE = 0.55 passes every bound check and
  # gives an impossible energy balance).
  if (!is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("sub_category", "parameter", "mean") %in% names(ps))) {
    units <- setNames(PARAM_CATALOGUE$unit, PARAM_CATALOGUE$parameter)
    dflt  <- setNames(PARAM_CATALOGUE$ipcc_default, PARAM_CATALOGUE$parameter)
    mu <- suppressWarnings(as.numeric(ps$mean))
    for (i in seq_len(nrow(ps))) {
      pn <- as.character(ps$parameter[i]); u <- units[pn]
      if (is.na(u) || !is.finite(mu[i]) || mu[i] <= 0) next
      bad <- NULL
      if (identical(unname(u), "%") && mu[i] < 1)
        bad <- sprintf("%s is %s but the catalogue unit is percent (IPCC default %s): this looks like a fraction. Multiply by 100 if so.",
                       pn, fmt(mu[i]), fmt(suppressWarnings(as.numeric(dflt[pn]))))
      if (grepl("^fraction", unname(u)) && mu[i] > 1)
        bad <- sprintf("%s is %s but the catalogue unit is a fraction 0 to 1 (IPCC default %s): this looks like a percentage. Divide by 100 if so.",
                       pn, fmt(mu[i]), fmt(suppressWarnings(as.numeric(dflt[pn]))))
      if (!is.null(bad))
        add(sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", ps$sub_category[i], pn), bad,
            severity = "fail", sheet = "Parameters", group = gkey(ps, i), parameter = pn, check = "percent vs fraction")
    }
  }
  if (!is.null(manure) && is.data.frame(manure) && nrow(manure) > 0) {
    chk_mm <- function(col, lo_frac, msg, sev) {
      if (!col %in% names(manure)) return()
      v <- suppressWarnings(as.numeric(manure[[col]]))
      hit <- which(is.finite(v) & v > 0 & lo_frac(v))
      for (i in hit)
        add(sprintf("%s / %s / %s", manure$aggregation_level[i] %||% "", manure$sub_category[i], col),
            sprintf(msg, col, fmt(v[i])), severity = sev, sheet = "Manure_Management",
            group = gkey(manure, i), parameter = col, check = "percent vs fraction")
    }
    chk_mm("MCF_pct", function(v) v < 0.3, "%s is %s: the column is a percentage, and a value this small is usually a fraction written where a percent was expected.", "warn")
    chk_mm("Frac_GasMS_pct", function(v) v < 1, "%s is %s: the column is a percentage; a value below 1 looks like a fraction.", "warn")
    chk_mm("Frac_LeachMS_pct", function(v) v < 0.1, "%s is %s: the column is a percentage; a value this small looks like a fraction.", "warn")
    chk_mm("EF3", function(v) v > 1, "%s is %s: EF3 is a fraction (kg N2O-N per kg N, IPCC values 0.001 to 0.1); a value above 1 looks like a percentage.", "fail")
  }

  # C9 (2026-10-22, WP3): ranges and distributions the writer had to take
  # from the catalogue because the AI supplied a value with no spread. The
  # workbook cannot tell them apart from the user's own, so they are listed.
  if (!is.null(piece)) {
    d9 <- tryCatch(.translator_defaults_applied(piece), error = function(e) NULL)
    if (!is.null(d9) && nrow(d9))
      for (i in seq_len(nrow(d9)))
        add(d9$where[i], d9$issue[i], severity = d9$severity[i] %||% "info", sheet = d9$sheet[i],
            group = d9$group[i], parameter = d9$parameter[i],
            check = if (identical(d9$severity[i], "warn")) "placeholder range" else "default applied")
    # 2026-10-23: what the server corrected before writing (see
    # .translator_fix_uncertainty_scale), for the user to check
    sc <- piece$server_corrections
    if (is.data.frame(sc) && nrow(sc))
      for (i in seq_len(nrow(sc)))
        add(sc$where[i], sc$issue[i], severity = "warn", sheet = sc$sheet[i],
            group = sc$group[i], parameter = sc$parameter[i], check = sc$check[i] %||% "corrected by the tool")
  }

  if (!length(out))
    return(data.frame(where = character(), issue = character(), severity = character(),
                      sheet = character(), group = character(), parameter = character(),
                      check = character(), stringsAsFactors = FALSE))
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}

# The AI rows that carried a value and no spread (no bounds, no percentage),
# or no distribution: the writer fills these from the catalogue (C9). Read
# from the emitted JSON piece, since the written workbook no longer shows
# the difference.
.translator_defaults_applied <- function(piece) {
  empty <- data.frame(where = character(), issue = character(), sheet = character(),
                      group = character(), parameter = character(), severity = character(),
                      stringsAsFactors = FALSE)
  ps <- piece$parameters
  rows <- list()
  if (is.data.frame(ps) && nrow(ps) && all(c("sub_category", "parameter") %in% names(ps))) {
    num <- function(x) suppressWarnings(as.numeric(x))
    get <- function(nm) if (nm %in% names(ps)) ps[[nm]] else rep(NA, nrow(ps))
    mean_v <- num(get("mean") %||% get("value")); unc <- num(get("uncertainty_pct"))
    lo <- num(get("lower")); hi <- num(get("upper")); dist <- tolower(as.character(get("distribution")))
    src <- tolower(as.character(get("data_source")))
    for (i in seq_len(nrow(ps))) {
      if (!is.finite(mean_v[i]) || identical(dist[i], "constant")) next
      if (!grepl("^user", src[i] %||% "")) next
      no_spread <- !is.finite(unc[i]) && !is.finite(lo[i]) && !is.finite(hi[i])
      no_dist   <- is.na(dist[i]) || !nzchar(dist[i]) || dist[i] == "na"
      if (!no_spread && !no_dist) next
      # 2026-10-30: a range is applied only where a defensible default
      # exists; otherwise the user must add one (the app will not run).
      pn <- as.character(ps$parameter[i])
      has_def <- no_spread && !is.null(default_range_for(pn, mean_v[i]))
      what <- paste(c(if (no_spread && has_def) "range", if (no_dist) "distribution"), collapse = " and ")
      grp_i <- paste(ps$cattle_type[i] %||% "", ps$aggregation_level[i] %||% "", ps$sub_category[i] %||% "", sep = "||")
      where_i <- sprintf("%s / %s / %s", ps$aggregation_level[i] %||% "", ps$sub_category[i], pn)
      if (nzchar(what))
        rows[[length(rows) + 1L]] <- data.frame(
          where = where_i,
          issue = sprintf("The file gave a value for %s (%s) but no %s; the default %s was applied%s. Replace it if your inventory has its own.",
                          pn, format(signif(mean_v[i], 6)), what, what,
                          if (no_spread && has_def) sprintf(" (%s)", DEFAULT_RANGE_SOURCE[[pn]]) else ""),
          sheet = "Parameters", group = grp_i, parameter = pn, severity = "info",
          stringsAsFactors = FALSE)
      if (no_spread && !has_def)
        rows[[length(rows) + 1L]] <- data.frame(
          where = where_i,
          issue = sprintf("The file gave a value for %s (%s) but no uncertainty range, and there is no published default for %s. A placeholder range was written (marked 'placeholder range' in data_source) so the app can run. It has no source: replace it with a range from your own data.",
                          pn, format(signif(mean_v[i], 6)), pn),
          sheet = "Parameters", group = grp_i, parameter = pn, severity = "warn",
          stringsAsFactors = FALSE)
    }
  }
  mm <- piece$manure_management
  if (is.data.frame(mm) && nrow(mm) && "sub_category" %in% names(mm)) {
    num <- function(x) suppressWarnings(as.numeric(x))
    get <- function(nm) if (nm %in% names(mm)) mm[[nm]] else rep(NA, nrow(mm))
    for (i in seq_len(nrow(mm))) {
      mcf <- num(get("MCF_pct")[i] %||% get("mcf")[i]); ef3 <- num(get("EF3")[i] %||% get("ef3")[i])
      # 2026-10-30: the writer applies an IPCC range only at the system's
      # IPCC default value (EF3 a factor of 2, Table 10.22 fractions); MCF
      # never. Pasture's EF3 and fractions are unused (Chapter 11 pathway).
      id_i  <- as.character(get("mms_type")[i])
      grp_m <- paste(mm$cattle_type[i] %||% "", mm$aggregation_level[i] %||% "", mm$sub_category[i], sep = "||")
      share <- num(get("fraction_pct")[i])
      if (is.finite(share) && share <= 0) next
      cols_m <- list(MCF_pct = list(v = mcf, lo = "lower_mcf", hi = "upper_mcf"),
                     EF3 = list(v = ef3, lo = "lower_ef3", hi = "upper_ef3"),
                     Frac_GasMS_pct = list(v = num(get("Frac_GasMS_pct")[i]), lo = "lower_frac_gas", hi = "upper_frac_gas"),
                     Frac_LeachMS_pct = list(v = num(get("Frac_LeachMS_pct")[i]), lo = "lower_frac_leach", hi = "upper_frac_leach"))
      for (cn in names(cols_m)) {
        cm <- cols_m[[cn]]
        if (!is.finite(cm$v) || cm$v == 0) next
        if (identical(id_i, "pasture") && cn != "MCF_pct") next
        if (is.finite(num(get(cm$lo)[i])) || is.finite(num(get(cm$hi)[i]))) next
        r <- manure_default_range(id_i, cn, cm$v)
        rows[[length(rows) + 1L]] <- data.frame(
          where = sprintf("%s / %s / %s (%s)", mm$aggregation_level[i] %||% "", mm$sub_category[i], cn, id_i),
          issue = if (!is.null(r))
            sprintf("%s for %s came without a range; the IPCC range for this default value was applied (%s). Replace it if your inventory has its own.", cn, id_i, r$source)
          else
            sprintf("%s for %s (%s) came without a range, and IPCC gives none for this value. A placeholder range was written (MCF +/-25 %%, EF3 a factor of 2, fractions +/-50 %%; marked in data_source) so the app can run. It has no source: replace it with your own.", cn, id_i, format(signif(cm$v, 4))),
          sheet = "Manure_Management", group = grp_m, parameter = cn,
          severity = if (!is.null(r)) "info" else "warn", stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

# 2026-10-30: the checks the AI review is asked to look at, with the file in
# front of it. Every one of them can be a real error the model can fix from
# the source (a row left out, a column read from the wrong year, a range or
# a distribution not carried over), or a false alarm the model can explain
# (two groups that really have the same head count). "placeholder range" is
# included only when the source plausibly gives a range (manure and the
# parameters the file states uncertainty for); the review is told so.
# Of the trend checks (C13) only a gap in a series and rows the trend
# ignores are here: both are translation mistakes the file can settle. The
# others describe the country's data and are for the country team.
.TRANSLATOR_REVIEW_CHECKS <- c(
  "default replaced file value", "manure bounds missing", "manure bounds reused",
  "distribution differs between systems", "time-series coverage", "time-series year",
  "Parameters vs time series", "value not in file", "manure shares sum",
  "manure coefficient consistency", "bounds bracket mean", "percent vs fraction",
  "duplicate population", "category coverage", "time series totals", "placeholder range",
  "time series: gap", "time series: rows ignored")

translator_review_targets <- function(issues) {
  if (!is.data.frame(issues) || !nrow(issues)) return(issues)
  sev <- if ("severity" %in% names(issues)) issues$severity else rep("warn", nrow(issues))
  ck  <- if ("check" %in% names(issues)) issues$check else rep(NA_character_, nrow(issues))
  # A file may name different shapes in different systems, so that check
  # is only a note for the user (info); the review still looks at it.
  issues[ck %in% .TRANSLATOR_REVIEW_CHECKS &
         (sev %in% c("fail", "warn") | ck %in% "distribution differs between systems"), , drop = FALSE]
}
