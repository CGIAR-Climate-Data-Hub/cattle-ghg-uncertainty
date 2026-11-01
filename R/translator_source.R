# ---------------------------------------------------------------------------
# The verified exploration table (Stage 3 of the 31 October plan)
#
# The model's exploration reply used to carry section B as a prose table
# with no production-system column and no block-heading column, and the
# batches copied from it. On the Zambia file that produced a mature-weight
# range on a body-weight row, a per-system DE fix on the wrong system and
# an emergent-beef question labelled extensive. Section B is now a fenced
# `source_values` JSON block, one entry per value the model will emit from
# the file (R/openai_client.R rule 13). This file checks every entry
# against the uploaded sheets as the model saw them (the per-sheet JSON
# with Excel row keys and `_section`), tells each batch which rows of the
# file belong to its system, and checks a batch's sub-categories against
# the expected set.
# ---------------------------------------------------------------------------

# Text folding for labels: case, accents left as they are, whitespace and
# punctuation collapsed.
.translator_fold <- function(x) {
  x <- tolower(trimws(as.character(x %||% "")))
  # punctuation first, then the spaces: "Oxen (> 3 years)" and
  # "Oxen (>3 years)" fold to the same text (2026-11-01)
  x <- gsub("[^[:alnum:][:space:]]+", "", x)
  trimws(gsub("[[:space:]]+", " ", x))
}

# The sheets as the model saw them: list(name, rows (by row key), headers,
# n_rows). `sheets` is parsed$sheets (each with $json) or the lighter
# state$source_sheets.
.translator_source_tables <- function(sheets) {
  out <- list()
  for (s in sheets %||% list()) {
    j <- s$json %||% NULL
    if (is.null(j) && !is.null(s$preview))
      j <- tryCatch(.translator_table_to_json(s$preview, sheet_name = s$name), error = function(e) NULL)
    if (is.null(j)) next
    p <- tryCatch(jsonlite::fromJSON(as.character(j), simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(p)) next
    out[[length(out) + 1L]] <- list(name = as.character(p$sheet %||% s$name %||% ""),
                                    headers = as.character(unlist(p$headers %||% character(0))),
                                    rows = p$rows %||% list(), n_rows = as.integer(p$n_rows %||% 0L),
                                    n_sent = length(p$rows %||% list()))
  }
  out
}

.translator_excel_col_index <- function(letters_) {
  l <- toupper(trimws(letters_))
  if (!grepl("^[A-Z]{1,3}$", l)) return(NA_integer_)
  v <- 0L
  for (ch in strsplit(l, "")[[1]]) v <- v * 26L + (utf8ToInt(ch) - 64L)
  v
}

# Numbers in a row object (every cell that reads as a number, text included).
.translator_row_numbers <- function(row) {
  vals <- unlist(row[setdiff(names(row), "_section")], use.names = FALSE)
  if (!length(vals)) return(numeric(0))
  .translator_cell_numbers(vals)
}
.translator_row_texts <- function(row) {
  cells <- row[setdiff(names(row), "_section")]
  txt <- vapply(cells, function(v) if (is.character(v)) v else "", character(1))
  txt[nzchar(txt)]
}

# ---------------------------------------------------------------------------
# The time series taken from the file by the server (2026-11-01). Once the
# source check has confirmed which row of the file a group's parameter is
# read from (an entry whose `col` is a year header), the row's values in
# every year column are the series: they replace what the AI wrote for
# that group and parameter, converted with the Parameters row's factor
# where the value is converted (milk per lactating day). The AI extended
# and smoothed the feedlot BW series of the 13:31 Zambia run and left the
# MW series out; copying the row is deterministic. Each rebuilt series is
# recorded: info when the AI's cells agreed, warn when some differed or
# were missing, with the years.
# ---------------------------------------------------------------------------
.TRANSLATOR_TS_PARAMS <- c("N", "BW", "MW", "WG", "Milk", "Fat", "pct_pregnant", "DE", "CP", "MilkPR")

translator_rebuild_series <- function(piece, source_values, sheets, tol = 0.002) {
  ps <- piece$parameters
  if (!length(source_values) || !length(sheets) || !is.data.frame(ps) || !nrow(ps)) return(piece)
  tables <- .translator_source_tables(sheets)
  if (!length(tables)) return(piece)
  tnames <- vapply(tables, function(t) .translator_fold(t$name), character(1))
  ts <- piece$parameter_timeseries
  if (!is.data.frame(ts)) ts <- data.frame()
  if (!nrow(ts)) ts <- data.frame(cattle_type = character(0), aggregation_level = character(0),
                                  sub_category = character(0), year = integer(0), stringsAsFactors = FALSE)
  for (cn in c("cattle_type", "aggregation_level", "sub_category", "year")) if (!cn %in% names(ts)) ts[[cn]] <- NA
  ts$year <- suppressWarnings(as.integer(ts$year))
  # a series row without its system label (the AI omits it in some batches;
  # the writer fills it from the batch's requested level) is matched on the
  # requested level, else on the piece's only level. 2026-11-01, 15:09 run:
  # the commercial dairy rows were not recognised and were written twice.
  lv_ts <- .translator_norm_level(ts$aggregation_level); lv_ts[is.na(lv_ts)] <- ""
  if (".requested_aggregation_level" %in% names(ts)) {
    rq <- .translator_norm_level(ts$.requested_aggregation_level); rq[is.na(rq)] <- ""
    lv_ts[!nzchar(lv_ts)] <- rq[!nzchar(lv_ts)]
  }
  lv_ps <- .translator_norm_level(ps$aggregation_level); lv_ps[is.na(lv_ps)] <- ""
  if (any(!nzchar(lv_ts)) && length(unique(lv_ps[nzchar(lv_ps)])) == 1L) lv_ts[!nzchar(lv_ts)] <- unique(lv_ps[nzchar(lv_ps)])
  ts$aggregation_level[!nzchar(as.character(ts$aggregation_level %||% "")) | is.na(ts$aggregation_level)] <-
    lv_ts[!nzchar(as.character(ts$aggregation_level %||% "")) | is.na(ts$aggregation_level)]
  fac <- if ("conversion_factor" %in% names(ps)) suppressWarnings(as.numeric(ps$conversion_factor)) else rep(NA_real_, nrow(ps))
  rows <- list(); n_rebuilt <- 0L
  for (e in source_values) {
    p <- as.character(e$parameter %||% ""); col <- trimws(as.character(e$col %||% ""))
    S <- as.character(e$sub_category %||% ""); L <- .translator_norm_level(e$aggregation_level %||% "")
    if (!p %in% .TRANSLATOR_TS_PARAMS || !grepl("^(19|20)[0-9]{2}$", col) || !nzchar(S) || !nzchar(L)) next
    k <- which(tnames == .translator_fold(e$sheet %||% ""))
    if (!length(k) && length(tables) == 1L) k <- 1L
    if (!length(k)) next
    tb <- tables[[k[1]]]; row <- tb$rows[[as.character(suppressWarnings(as.integer(e$row)))]]
    if (is.null(row)) next
    yh <- tb$headers[grepl("^(19|20)[0-9]{2}$", trimws(tb$headers))]
    vals <- vapply(yh, function(h) { v <- row[[h]]; n <- if (is.null(v)) numeric(0) else tryCatch(.translator_cell_numbers(unlist(v)), error = function(err) numeric(0))
                                     if (length(n)) n[1] else NA_real_ }, numeric(1))
    names(vals) <- trimws(yh)
    vals <- vals[is.finite(vals)]
    if (length(vals) < 2L) next
    i_ps <- which(ps$parameter == p & ps$sub_category == S & lv_ps == L)
    if (!length(i_ps)) next
    f <- fac[i_ps[1]]; if (!is.finite(f) || f == 0) f <- 1
    ct <- as.character(ps$cattle_type[i_ps[1]] %||% "")
    if (!p %in% names(ts)) ts[[p]] <- NA_real_
    changed <- character(0); added <- character(0)
    for (y in names(vals)) {
      yi <- as.integer(y); v <- unname(vals[[y]]) * f
      r <- which(lv_ts == L & ts$sub_category == S & ts$year == yi)
      if (!length(r)) {
        ts[nrow(ts) + 1L, ] <- NA
        r <- nrow(ts)
        ts$cattle_type[r] <- ct; ts$aggregation_level[r] <- as.character(e$aggregation_level); ts$sub_category[r] <- S; ts$year[r] <- yi
        lv_ts <- c(lv_ts, L)
        added <- c(added, y)
      } else {
        old <- suppressWarnings(as.numeric(ts[[p]][r[1]]))
        if (!is.finite(old)) added <- c(added, y)
        else if (abs(old - v) > tol * max(1, abs(v))) changed <- c(changed, y)
      }
      ts[[p]][r[1]] <- v
    }
    n_rebuilt <- n_rebuilt + 1L
    rows[[length(rows) + 1L]] <- list(level = as.character(e$aggregation_level), ct = ct, p = p, S = S, n = length(vals),
                                      f = f, changed = changed, added = added)
  }
  if (!n_rebuilt) return(piece)
  # one record per system and parameter (2026-11-01: 199 rows on the Zambia
  # file said the same thing); a warning only when the AI's cells differed
  # from the file, a note when it had written none or all agreed
  yr_txt <- function(x) .translator_year_runs(sort(unique(as.integer(x))))
  recs <- list()
  for (k in unique(vapply(rows, function(r) paste(r$level, r$p, sep = "||"), character(1)))) {
    rs <- rows[vapply(rows, function(r) paste(r$level, r$p, sep = "||") == k, logical(1))]
    r1 <- rs[[1]]
    g_diff <- rs[vapply(rs, function(r) length(r$changed) > 0, logical(1))]
    g_none <- rs[vapply(rs, function(r) length(r$added) >= r$n, logical(1))]
    g_part <- rs[vapply(rs, function(r) length(r$added) > 0 && length(r$added) < r$n && !length(r$changed), logical(1))]
    conv <- if (r1$f != 1) sprintf(", converted with the factor %s", format(signif(r1$f, 6))) else ""
    issue <- sprintf("The %s series of %d group(s) of %s were taken from their file rows (%d years each)%s.", r1$p, length(rs), r1$level, r1$n, conv)
    if (length(g_diff)) issue <- paste0(issue, sprintf(" The AI's series differed from the file for %s (%s).",
      paste(vapply(g_diff, function(r) r$S, character(1)), collapse = ", "),
      paste(vapply(g_diff, function(r) sprintf("%s: %s", r$S, yr_txt(r$changed)), character(1)), collapse = "; ")))
    if (length(g_none)) issue <- paste0(issue, sprintf(" The AI had written no series for %s.", paste(vapply(g_none, function(r) r$S, character(1)), collapse = ", ")))
    if (length(g_part)) issue <- paste0(issue, sprintf(" The AI's series had gaps for %s.", paste(vapply(g_part, function(r) sprintf("%s (%s)", r$S, yr_txt(r$added)), character(1)), collapse = ", ")))
    recs[[length(recs) + 1L]] <- data.frame(
      where = "Parameter_TimeSeries", issue = issue, severity = if (length(g_diff)) "warn" else "info",
      sheet = "Parameter_TimeSeries", group = NA_character_, parameter = r1$p,
      check = "series taken from the file", stringsAsFactors = FALSE)
  }
  rows <- recs
  # two rows for one group and year (the AI's and a rebuilt one, or two of
  # the AI's) are merged: the first non-blank value of each column
  key <- paste(lv_ts, ts$sub_category, ts$year, sep = "||")
  if (any(duplicated(key))) {
    vcols <- setdiff(names(ts), c("cattle_type", "aggregation_level", "sub_category", "year", ".requested_aggregation_level"))
    for (k in unique(key[duplicated(key)])) {
      idx <- which(key == k); first <- idx[1]
      for (cn in vcols) { v <- ts[[cn]][idx]; v <- v[!is.na(v)]; if (length(v)) ts[[cn]][first] <- v[1] }
      if (is.na(ts$cattle_type[first]) || !nzchar(ts$cattle_type[first])) {
        ctv <- ts$cattle_type[idx]; ctv <- ctv[!is.na(ctv) & nzchar(ctv)]; if (length(ctv)) ts$cattle_type[first] <- ctv[1]
      }
    }
    keep <- !duplicated(key)
    ts <- ts[keep, , drop = FALSE]; lv_ts <- lv_ts[keep]
  }
  ts <- ts[order(lv_ts, ts$sub_category, ts$year), , drop = FALSE]
  rownames(ts) <- NULL
  piece$parameter_timeseries <- ts
  corr <- do.call(rbind, rows); rownames(corr) <- NULL
  piece$server_corrections <- .translator_add_corrections(piece$server_corrections, corr)
  piece
}

# The JSON text after the rebuild; the same text when nothing was rebuilt.
translator_rebuild_series_json <- function(json, source_values, sheets) {
  if (is.null(json) || !nzchar(json) || !length(source_values) || !length(sheets)) return(json)
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(piece)) return(json)
  out <- tryCatch(translator_rebuild_series(piece, source_values, sheets), error = function(e) {
    message("translator: series rebuild failed (", conditionMessage(e), ")"); NULL })
  if (is.null(out)) return(json)
  before <- if (is.data.frame(piece$server_corrections)) nrow(piece$server_corrections) else 0L
  after <- if (is.data.frame(out$server_corrections)) nrow(out$server_corrections) else 0L
  if (after == before) return(json)
  message("translator: ", after - before, " series taken from the file rows")
  as.character(jsonlite::toJSON(out, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
}

# ---------------------------------------------------------------------------
# The ranges and distributions from the file, by the server (2026-11-01,
# evening). The source check has confirmed each entry's lower, upper and
# distribution against the file; a Parameters row that carries something
# else (the 16:18 Zambia run: a normal +-35 % where the file's row says
# triangular 3 to 7.5) takes the entry's, converted with the row's factor.
# Recorded as "range taken from the file" / "distribution taken from the
# file" warnings. Rows whose entry gives no bounds are left alone.
# ---------------------------------------------------------------------------
translator_apply_table_ranges <- function(piece, source_values, tol = 0.002) {
  ps <- piece$parameters
  if (!length(source_values) || !is.data.frame(ps) || !nrow(ps)) return(piece)
  dists <- if (exists("DISTRIBUTION_TYPES")) tolower(get("DISTRIBUTION_TYPES")) else
    c("normal", "lognormal", "beta", "triangular", "pert", "uniform", "constant")
  for (cn in c("lower", "upper", "uncertainty_pct")) if (!cn %in% names(ps)) ps[[cn]] <- NA_real_
  if (!"distribution" %in% names(ps)) ps$distribution <- NA_character_
  lv_ps <- .translator_norm_level(ps$aggregation_level); lv_ps[is.na(lv_ps)] <- ""
  fac <- if ("conversion_factor" %in% names(ps)) suppressWarnings(as.numeric(ps$conversion_factor)) else rep(NA_real_, nrow(ps))
  rows <- list(); n_changed <- 0L
  gk <- function(i) paste(ps$cattle_type[i] %||% "", ps$aggregation_level[i] %||% "", ps$sub_category[i], sep = " / ")
  for (e in source_values) {
    p <- as.character(e$parameter %||% ""); S <- as.character(e$sub_category %||% ""); L <- .translator_norm_level(e$aggregation_level %||% "")
    if (!nzchar(p) || !nzchar(S) || !nzchar(L)) next
    i <- which(ps$parameter == p & ps$sub_category == S & lv_ps == L)
    if (length(i) != 1L) next
    f <- fac[i]; if (!is.finite(f) || f == 0) f <- 1
    lo <- suppressWarnings(as.numeric(e$lower %||% NA)); up <- suppressWarnings(as.numeric(e$upper %||% NA))
    ed <- tolower(trimws(as.character(e$distribution %||% "")))
    mu <- suppressWarnings(as.numeric(ps$mean[i]))
    changed <- character(0)
    if (is.finite(lo) && is.finite(up) && up > lo) {
      elo <- lo * f; eup <- up * f
      rlo <- suppressWarnings(as.numeric(ps$lower[i])); rup <- suppressWarnings(as.numeric(ps$upper[i]))
      ru <- suppressWarnings(as.numeric(ps$uncertainty_pct[i]))
      differs <- !is.finite(rlo) || !is.finite(rup) || abs(rlo - elo) > tol * max(1, abs(elo)) || abs(rup - eup) > tol * max(1, abs(eup))
      if (differs && (is.finite(mu) && elo <= mu && mu <= eup || !is.finite(mu))) {
        was <- if (is.finite(rlo) && is.finite(rup)) sprintf("%s to %s", format(signif(rlo, 6)), format(signif(rup, 6)))
               else if (is.finite(ru)) sprintf("+-%s %%", format(signif(ru, 4))) else "no range"
        ps$lower[i] <- elo; ps$upper[i] <- eup; ps$uncertainty_pct[i] <- NA_real_
        changed <- c(changed, sprintf("the range %s became the file's %s to %s%s", was, format(signif(elo, 6)), format(signif(eup, 6)),
                                      if (f != 1) sprintf(" (the file's %s to %s times %s)", format(signif(lo, 6)), format(signif(up, 6)), format(signif(f, 6))) else ""))
      }
    }
    if (nzchar(ed) && ed %in% dists) {
      rd <- tolower(trimws(as.character(ps$distribution[i] %||% "")))
      if (!identical(rd, ed) && !identical(rd, "constant")) {
        ps$distribution[i] <- ed
        changed <- c(changed, sprintf("the distribution '%s' became the file's '%s'", if (nzchar(rd)) rd else "none", ed))
      }
    }
    if (length(changed)) {
      n_changed <- n_changed + 1L
      rows[[length(rows) + 1L]] <- data.frame(
        where = "Parameters", issue = sprintf("%s: %s (from the table of values the server checked against your file, %s!%s).",
                                             p, paste(changed, collapse = "; "), e$sheet %||% "", as.character(e$row %||% "")),
        severity = "warn", sheet = "Parameters", group = gk(i), parameter = p,
        check = if (any(grepl("^the range", changed))) "range taken from the file" else "distribution taken from the file",
        stringsAsFactors = FALSE)
    }
  }
  if (!n_changed) return(piece)
  piece$parameters <- ps
  corr <- do.call(rbind, rows); rownames(corr) <- NULL
  piece$server_corrections <- .translator_add_corrections(piece$server_corrections, corr)
  piece
}

translator_apply_table_ranges_json <- function(json, source_values) {
  if (is.null(json) || !nzchar(json) || !length(source_values)) return(json)
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(piece)) return(json)
  out <- tryCatch(translator_apply_table_ranges(piece, source_values), error = function(e) {
    message("translator: table ranges failed (", conditionMessage(e), ")"); NULL })
  if (is.null(out)) return(json)
  before <- if (is.data.frame(piece$server_corrections)) nrow(piece$server_corrections) else 0L
  after <- if (is.data.frame(out$server_corrections)) nrow(out$server_corrections) else 0L
  if (after == before) return(json)
  message("translator: ", after - before, " range(s) or distribution(s) taken from the table")
  as.character(jsonlite::toJSON(out, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
}

# ---------------------------------------------------------------------------
# The manure coefficients from the file, by the server (2026-11-01, night).
# The checked table has one entry per coefficient row of the file (MCF,
# EF3, Frac_GasMS, Frac_LeachMS), labelled with the file's manure-system
# name. The label is mapped to the template's code by keyword; when the
# table gives one value for a (system, manure system, coefficient), every
# manure row of that system takes it (the 17:13 Zambia run: Frac_GasMS of
# solid storage at the IPCC default 30 on four rows where the file gives
# 45). Two values for one code (the two slurry MCF variants) are left
# alone. A coefficient given as a fraction in the file is written in
# percent where the column is a percent column.
# ---------------------------------------------------------------------------
.TRANSLATOR_MMS_KEYWORDS <- c(
  pasture = "pasture|paddock|range|grazing", daily_spread = "daily spread", solid_storage = "solid storage",
  dry_lot = "dry ?lot", deep_bedding = "deep bedding", liquid_slurry = "slurry|liquid|pit storage",
  composting = "compost", anaerobic_lagoon = "lagoon", anaerobic_digester = "digester|biogas",
  aerobic_treatment = "aerobic treatment", burned_for_fuel = "burn")
.TRANSLATOR_MANURE_COLUMNS <- c(MCF = "MCF_pct", EF3 = "EF3", Frac_GasMS = "Frac_GasMS_pct", Frac_LeachMS = "Frac_LeachMS_pct")

.translator_mms_from_label <- function(label) {
  l <- .translator_fold(label)
  if (!nzchar(l)) return(NA_character_)
  ids <- if (exists("MMS_DEFAULTS")) as.character(get("MMS_DEFAULTS")$id) else names(.TRANSLATOR_MMS_KEYWORDS)
  for (code in names(.TRANSLATOR_MMS_KEYWORDS))
    if (code %in% ids && grepl(.TRANSLATOR_MMS_KEYWORDS[[code]], l, perl = TRUE)) return(code)
  NA_character_
}

translator_apply_table_manure <- function(piece, source_values, tol = 0.002) {
  mm <- piece$manure_management
  if (!length(source_values) || !is.data.frame(mm) || !nrow(mm) || !"mms_type" %in% names(mm)) return(piece)
  lv_mm <- .translator_norm_level(mm$aggregation_level); lv_mm[is.na(lv_mm)] <- ""
  if (".requested_aggregation_level" %in% names(mm)) {
    rq <- .translator_norm_level(mm$.requested_aggregation_level); rq[is.na(rq)] <- ""
    lv_mm[!nzchar(lv_mm)] <- rq[!nzchar(lv_mm)]
  }
  near <- function(a, b) is.finite(a) && is.finite(b) && abs(a - b) <= tol * max(1, abs(b))
  # the candidate values per (level or "", mms code, column)
  cand <- list()
  for (e in source_values) {
    p <- as.character(e$parameter %||% ""); if (!p %in% names(.TRANSLATOR_MANURE_COLUMNS)) next
    v <- suppressWarnings(as.numeric(e$mean %||% NA)); if (!is.finite(v)) next
    code <- .translator_mms_from_label(e$label %||% ""); if (is.na(code)) code <- .translator_mms_from_label(e$section %||% "")
    if (is.na(code)) next
    L <- .translator_norm_level(e$aggregation_level %||% ""); if (is.na(L)) L <- ""
    if (grepl("\\ball\\b", .translator_fold(e$system %||% ""), perl = TRUE)) L <- ""
    S <- as.character(e$sub_category %||% ""); if (is.na(S)) S <- ""
    k <- paste(L, code, p, sep = "||")
    cand[[k]] <- c(cand[[k]], list(list(v = v, S = S, sheet = e$sheet %||% "", row = e$row %||% "")))
  }
  if (!length(cand)) return(piece)
  rows <- list(); n_changed <- 0L
  levels <- unique(lv_mm[nzchar(lv_mm)])
  for (L in levels) for (code in unique(as.character(mm$mms_type))) for (p in names(.TRANSLATOR_MANURE_COLUMNS)) {
    col <- .TRANSLATOR_MANURE_COLUMNS[[p]]; if (!col %in% names(mm)) next
    ents <- c(cand[[paste(L, code, p, sep = "||")]], cand[[paste("", code, p, sep = "||")]])
    if (!length(ents)) next
    vals <- vapply(ents, function(x) x$v, numeric(1))
    distinct <- vals[!duplicated(round(vals, 6))]
    if (length(distinct) != 1L) next     # variants of one system (the slurry MCFs): not decided here
    v <- distinct[1]
    idx <- which(lv_mm == L & as.character(mm$mms_type) == code)
    S_only <- unique(vapply(ents, function(x) x$S, character(1))); S_only <- S_only[nzchar(S_only)]
    if (length(S_only) && all(S_only %in% as.character(mm$sub_category[idx]))) idx <- idx[as.character(mm$sub_category[idx]) %in% S_only]
    if (!length(idx)) next
    cur <- suppressWarnings(as.numeric(mm[[col]][idx]))
    scale <- if (any(vapply(cur, function(x) near(x, v * 100), logical(1)))) 100
             else if (any(vapply(cur, function(x) near(x, v), logical(1)))) 1
             else if (grepl("_pct$", col) && v <= 1) 100 else 1
    target <- v * scale
    off <- which(!vapply(cur, function(x) near(x, target), logical(1)))
    if (!length(off)) next
    old <- cur[off]
    mm[[col]][idx[off]] <- target
    n_changed <- n_changed + length(off)
    rows[[length(rows) + 1L]] <- data.frame(
      where = "Manure_Management",
      issue = sprintf("%s of %s in %s: %d row(s) (%s) carried %s; the file's row (%s!%s) gives %s, which the server wrote on them.",
                      col, code, L, length(off), paste(as.character(mm$sub_category[idx[off]]), collapse = ", "),
                      paste(unique(format(signif(old, 6))), collapse = ", "), ents[[1]]$sheet, as.character(ents[[1]]$row), format(signif(target, 6))),
      severity = "warn", sheet = "Manure_Management", group = NA_character_, parameter = col,
      check = "manure coefficient taken from the file", stringsAsFactors = FALSE)
  }
  if (!n_changed) return(piece)
  piece$manure_management <- mm
  corr <- do.call(rbind, rows); rownames(corr) <- NULL
  piece$server_corrections <- .translator_add_corrections(piece$server_corrections, corr)
  piece
}

translator_apply_table_manure_json <- function(json, source_values) {
  if (is.null(json) || !nzchar(json) || !length(source_values)) return(json)
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(piece)) return(json)
  out <- tryCatch(translator_apply_table_manure(piece, source_values), error = function(e) {
    message("translator: table manure failed (", conditionMessage(e), ")"); NULL })
  if (is.null(out)) return(json)
  before <- if (is.data.frame(piece$server_corrections)) nrow(piece$server_corrections) else 0L
  after <- if (is.data.frame(out$server_corrections)) nrow(out$server_corrections) else 0L
  if (after == before) return(json)
  message("translator: ", after - before, " manure coefficient(s) taken from the table")
  as.character(jsonlite::toJSON(out, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
}

# One entry against the file. Returns list(ok, what, cap).
.translator_check_entry <- function(e, tables) {
  what <- character(0); cap <- FALSE
  tol <- function(cand, v) any(abs(cand - v) <= 1e-6 * max(1, abs(v)))
  # sheet
  sheet <- as.character(e$sheet %||% "")
  tb <- NULL
  if (length(tables) == 1L) tb <- tables[[1]]
  else {
    nm <- vapply(tables, function(t) t$name, character(1))
    hit <- which(nm == sheet); if (!length(hit)) hit <- which(tolower(nm) == tolower(sheet))
    if (!length(hit)) hit <- which(.translator_fold(nm) == .translator_fold(sheet))
    if (length(hit)) tb <- tables[[hit[1]]]
  }
  if (is.null(tb)) return(list(ok = FALSE, what = "sheet not sent", cap = FALSE))
  # row
  rk <- as.character(suppressWarnings(as.integer(e$row)))
  row <- tb$rows[[rk]]
  if (is.null(row)) {
    if (!is.na(as.integer(rk)) && as.integer(rk) > tb$n_sent + 1L && tb$n_rows > tb$n_sent)
      return(list(ok = FALSE, what = "row beyond the rows sent", cap = TRUE))
    return(list(ok = FALSE, what = sprintf("empty row %s", rk), cap = FALSE))
  }
  # column
  col <- as.character(e$col %||% "")
  colname <- NULL
  if (nzchar(col)) {
    if (col %in% tb$headers) colname <- col
    else if (any(tolower(tb$headers) == tolower(col))) colname <- tb$headers[tolower(tb$headers) == tolower(col)][1]
    else {
      ci <- .translator_excel_col_index(col)
      if (!is.na(ci) && ci <= length(tb$headers)) colname <- tb$headers[ci]
      else {
        # a header written in a row above the data (the first header row of
        # the sheet is not the real header): the column whose cell holds
        # that text in some earlier row
        r_i <- as.integer(rk)
        for (k in rev(seq_len(max(0L, r_i - 1L)))) {
          r2 <- tb$rows[[as.character(k)]]; if (is.null(r2)) next
          m <- names(r2)[vapply(r2, function(v) is.character(v) && .translator_fold(v) == .translator_fold(col), logical(1))]
          if (length(m)) { colname <- m[1]; break }
        }
      }
    }
  }
  # year_col names the header the mean was read from
  yc <- as.character(e$year_col %||% "")
  if (nzchar(yc) && !is.null(colname) && .translator_fold(yc) != .translator_fold(colname))
    what <- c(what, sprintf("year_col %s is not column %s", yc, colname))
  # mean
  mean_v <- suppressWarnings(as.numeric(e$mean %||% NA))
  if (length(mean_v) == 1L && is.finite(mean_v)) {
    cell <- if (!is.null(colname) && !is.null(row[[colname]])) .translator_cell_numbers(unlist(row[[colname]])) else numeric(0)
    if (length(cell) && tol(cell, mean_v)) NULL
    else {
      nums <- .translator_row_numbers(row)
      other <- names(row)[vapply(row, function(v) {
        n <- tryCatch(.translator_cell_numbers(unlist(v)), error = function(err) numeric(0))
        length(n) > 0 && tol(n, mean_v) }, logical(1))]
      other <- setdiff(other, "_section")
      if (!is.null(colname) && length(cell))
        what <- c(what, sprintf("mean: column %s holds %s, not %s%s", col, format(cell[1]), format(mean_v),
                                if (length(other)) sprintf(" (%s is in column %s of this row)", format(mean_v), other[1]) else ""))
      else if (length(other)) { if (nzchar(col)) what <- c(what, sprintf("col %s not found; %s is in column %s", col, format(mean_v), other[1])) }
      else what <- c(what, sprintf("mean %s not on row %s", format(mean_v), rk))
    }
  }
  # section: a row under no heading (no `_section`) accepts whatever the
  # entry says (2026-11-01: the population rows of the Zambia file have
  # none and were all flagged); a row under a heading must name it.
  sec <- as.character(e$section %||% "")
  rsec <- as.character(row[["_section"]] %||% "")
  if (nzchar(rsec)) {
    if (.translator_fold(sec) != .translator_fold(rsec))
      what <- c(what, sprintf("section (row: %s; entry: %s)", rsec, if (nzchar(sec)) sec else "none"))
  }
  # label and system: on the row, or forward-filled from up to 8 rows above
  texts_up <- function(n_up = 8L) {
    r_i <- as.integer(rk); out <- .translator_row_texts(row)
    for (k in seq_len(n_up)) {
      r2 <- tb$rows[[as.character(r_i - k)]]
      if (!is.null(r2)) out <- c(out, .translator_row_texts(r2))
    }
    .translator_fold(out)
  }
  # 2026-11-01: a label or system is also accepted when (a) a text near
  # the row covers several groups ("all production systems", "all
  # categories except calves", "adult bulls, heifers and growing males")
  # and names no exception matching the entry, or (b) every content word
  # of the entry's label is found near the row as a word stem ("heifer"
  # for "Heifers (1 - 3 years)"). The entry carries the group the value
  # is used for; the file's row says which groups it covers.
  tx <- NULL
  stop_words <- c("adult", "year", "years", "and", "the", "of", "farms", "farm", "system", "systems")
  for (fld in c("label", "system")) {
    want <- .translator_fold(e[[fld]] %||% "")
    if (!nzchar(want)) next
    if (is.null(tx)) tx <- texts_up()
    hit <- any(grepl(want, tx, fixed = TRUE) | vapply(tx, function(t) nzchar(t) && grepl(t, want, fixed = TRUE), logical(1)))
    if (!hit) {
      # every word of the label (bare numbers and stop words aside) near
      # the row: a long word as a stem ("heifer" matches "heifers"), a
      # short one whole ("z" does not match "a")
      words <- setdiff(regmatches(want, gregexpr("[a-z][a-z0-9]*", want))[[1]], stop_words)
      stems <- unique(ifelse(nchar(words) > 3L, sub("s$", "", words), words))
      pats <- ifelse(nchar(words) > 3L, paste0("\\b", stems), paste0("\\b", stems, "\\b"))
      # a text that names the group after "except" does not count for it
      not_excepted <- function(s) !grepl(paste0("except[^;]*\\b", s), tx, perl = TRUE)
      if (length(stems))
        hit <- all(vapply(seq_along(stems), function(k) any(grepl(pats[k], tx, perl = TRUE) & not_excepted(stems[k])), logical(1)))
      if (!hit) {
        # a blanket text counts only on the row itself or in its heading
        # (an "All production systems" block a few rows up is another block)
        own <- .translator_fold(c(.translator_row_texts(row), rsec))
        blanket <- grepl("^all\\b|\\ball (production )?systems\\b|\\ball categories\\b", own, perl = TRUE)
        if (length(stems)) for (s in stems) blanket <- blanket & !grepl(paste0("except[^;]*\\b", s), own, perl = TRUE)
        hit <- any(blanket)
      }
    }
    if (!hit) what <- c(what, sprintf("%s '%s' not near row %s", fld, e[[fld]], rk))
  }
  # bounds
  for (fld in c("lower", "upper")) {
    v <- suppressWarnings(as.numeric(e[[fld]] %||% NA))
    if (length(v) != 1L || !is.finite(v)) next
    found <- tol(.translator_row_numbers(row), v)
    if (!found && nzchar(as.character(e$bounds_row %||% ""))) {
      bt <- tb
      bs <- as.character(e$bounds_sheet %||% "")
      if (nzchar(bs)) { nm <- vapply(tables, function(t) t$name, character(1)); h <- which(.translator_fold(nm) == .translator_fold(bs)); if (length(h)) bt <- tables[[h[1]]] }
      br <- bt$rows[[as.character(suppressWarnings(as.integer(e$bounds_row)))]]
      if (!is.null(br)) found <- tol(.translator_row_numbers(br), v)
    }
    if (!found) {
      # any row of any sheet with the same label whose numbers hold it
      lab <- .translator_fold(e$label %||% "")
      for (t2 in tables) {
        for (r2 in t2$rows) {
          if (nzchar(lab) && !any(grepl(lab, .translator_fold(.translator_row_texts(r2)), fixed = TRUE))) next
          if (tol(.translator_row_numbers(r2), v)) { found <- TRUE; break }
        }
        if (found) break
      }
    }
    if (!found) what <- c(what, sprintf("%s %s not found in the file", fld, format(v)))
  }
  list(ok = !length(what), what = paste(what, collapse = "; "), cap = cap)
}

# Every entry of the block against the sheets. data.frame(idx, sheet, row,
# parameter, ok, what, cap).
translator_source_values_check <- function(entries, sheets) {
  empty <- data.frame(idx = integer(0), sheet = character(0), row = integer(0), parameter = character(0),
                      ok = logical(0), what = character(0), cap = logical(0), stringsAsFactors = FALSE)
  if (!length(entries)) return(empty)
  tables <- .translator_source_tables(sheets)
  if (!length(tables)) return(empty)
  rows <- lapply(seq_along(entries), function(i) {
    e <- entries[[i]]
    r <- tryCatch(.translator_check_entry(e, tables), error = function(err) list(ok = FALSE, what = conditionMessage(err), cap = FALSE))
    data.frame(idx = i, sheet = as.character(e$sheet %||% ""), row = suppressWarnings(as.integer(e$row)),
               parameter = as.character(e$parameter %||% ""), ok = isTRUE(r$ok), what = r$what %||% "",
               cap = isTRUE(r$cap), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

# The corrective message after a failed gate.
.translator_source_fix_message <- function(chk, entries) {
  bad <- chk[!chk$ok & !chk$cap, , drop = FALSE]
  lines <- vapply(seq_len(min(nrow(bad), 60L)), function(k) {
    i <- bad$idx[k]; e <- entries[[i]]
    sprintf("[%d] %s!%s %s (%s, %s / %s): %s", i, e$sheet %||% "", as.character(e$row %||% ""), e$col %||% "",
            e$parameter %||% "", e$system %||% "", e$label %||% "", bad$what[k])
  }, character(1))
  paste0(
    "SOURCE CHECK: ", nrow(bad), " entr", if (nrow(bad) == 1L) "y" else "ies",
    " of your source_values block do", if (nrow(bad) == 1L) "es" else "", " not match the file ",
    "(the server looked up each sheet, row and column in the JSON you were given):\n",
    paste(lines, collapse = "\n"),
    if (nrow(bad) > 60L) sprintf("\n[... and %d more]", nrow(bad) - 60L) else "",
    "\n\nRe-read those rows in the JSON (the row key, its _section and its labels) and re-emit the WHOLE ",
    "source_values block, corrected, in the same form. A lower or upper that comes from another sheet (a margin-of-error ",
    "sheet) keeps its values in the row and adds bounds_sheet and bounds_row; never set them to null. Nothing else: no other section, no questions, ",
    "no decisions block.")
}

# ---------------------------------------------------------------------------
# Per-system rows for the batch nudge
# ---------------------------------------------------------------------------

# Row ranges per sheet from a vector of (sheet, row) pairs; gaps of `gap`
# rows or fewer are merged.
.translator_row_ranges <- function(sheet, row, gap = 3L) {
  ok <- !is.na(row) & nzchar(sheet)
  sheet <- sheet[ok]; row <- row[ok]
  if (!length(row)) return(data.frame(sheet = character(0), from = integer(0), to = integer(0), stringsAsFactors = FALSE))
  out <- list()
  for (s in unique(sheet)) {
    r <- sort(unique(row[sheet == s]))
    from <- r[1]; to <- r[1]
    for (x in r[-1]) {
      if (x - to <= gap + 1L) to <- x
      else { out[[length(out) + 1L]] <- data.frame(sheet = s, from = from, to = to, stringsAsFactors = FALSE); from <- x; to <- x }
    }
    out[[length(out) + 1L]] <- data.frame(sheet = s, from = from, to = to, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# What a batch is told about its system: the file's labels for it, the
# rows per sheet, the expected sub-categories.
translator_level_rows <- function(level, source_values = NULL, source_categories = NULL,
                                  sheets = NULL, expected_subcats = NULL) {
  lv <- .translator_norm_level(level)
  same <- function(x) { x <- .translator_norm_level(x); x == lv | grepl(lv, x, fixed = TRUE) | (nzchar(x) & grepl(x, lv, fixed = TRUE)) }
  ent <- Filter(function(e) same(e$aggregation_level %||% ""), source_values %||% list())
  systems <- unique(trimws(vapply(ent, function(e) as.character(e$system %||% ""), character(1))))
  systems <- systems[nzchar(systems)]
  from <- "source_values"
  if (!length(systems)) {
    cats <- Filter(function(c) same(c$aggregation_level %||% c$system %||% ""), source_categories %||% list())
    systems <- unique(trimws(vapply(cats, function(c) as.character(c$system %||% ""), character(1))))
    systems <- systems[nzchar(systems)]
    from <- if (length(systems)) "source_categories" else "none"
  }
  ranges <- if (length(ent)) {
    sh <- c(vapply(ent, function(e) as.character(e$sheet %||% ""), character(1)),
            vapply(ent, function(e) as.character(e$bounds_sheet %||% e$sheet %||% ""), character(1)))
    rw <- c(vapply(ent, function(e) suppressWarnings(as.integer(e$row %||% NA)), integer(1)),
            vapply(ent, function(e) suppressWarnings(as.integer(e$bounds_row %||% NA)), integer(1)))
    .translator_row_ranges(sh, rw)
  } else if (length(systems) && length(sheets)) {
    # rows where a system label appears, each extended over the block below it
    tables <- .translator_source_tables(sheets); sh <- character(0); rw <- integer(0)
    want <- .translator_fold(systems)
    for (tb in tables) for (k in names(tb$rows)) {
      tx <- .translator_fold(.translator_row_texts(tb$rows[[k]]))
      if (any(vapply(want, function(w) any(grepl(w, tx, fixed = TRUE)), logical(1)))) {
        r0 <- as.integer(k); sh <- c(sh, rep(tb$name, 9L)); rw <- c(rw, r0:(r0 + 8L))
      }
    }
    .translator_row_ranges(sh, rw)
  } else data.frame(sheet = character(0), from = integer(0), to = integer(0), stringsAsFactors = FALSE)
  subs <- unique(as.character(unlist(expected_subcats %||% character(0))))
  if (!length(subs)) {
    cats <- Filter(function(c) same(c$aggregation_level %||% c$system %||% ""), source_categories %||% list())
    subs <- unique(vapply(cats, function(c) as.character(c$sub_category %||% ""), character(1)))
  }
  subs <- subs[nzchar(subs)]
  list(level = level, systems = systems, ranges = ranges, n_entries = length(ent),
       sub_categories = subs, n_expected = length(subs), from = from)
}

# The paragraph of the batch nudge (under 300 tokens).
.translator_scope_text <- function(scope) {
  if (is.null(scope)) return("")
  rng <- scope$ranges
  rng_txt <- if (is.data.frame(rng) && nrow(rng))
    paste(vapply(unique(rng$sheet), function(s) {
      r <- rng[rng$sheet == s, , drop = FALSE]
      sprintf("%s rows %s", s, paste(ifelse(r$from == r$to, r$from, paste0(r$from, "-", r$to)), collapse = ", "))
    }, character(1)), collapse = "; ") else ""
  lines <- c("SOURCE ROWS FOR THIS BATCH.")
  if (length(scope$systems))
    lines <- c(lines, sprintf("In the file, '%s' is the system labelled %s.", scope$level,
                              paste(sprintf('"%s"', scope$systems), collapse = " / ")))
  if (nzchar(rng_txt)) lines <- c(lines, sprintf("Its rows: %s.", rng_txt))
  if (scope$n_entries > 0)
    lines <- c(lines, sprintf("Take every value from the source_values entries with aggregation_level '%s' (%d entries) and from no other rows: a row outside these ranges belongs to another system whatever its label says.",
                              scope$level, scope$n_entries))
  else if (nzchar(rng_txt))
    lines <- c(lines, "Take every value from these rows and from no other rows: a row outside these ranges belongs to another system whatever its label says.")
  if (scope$n_expected > 0) {
    n_req <- sum(!PARAM_CATALOGUE$param_tier %in% "optional")
    lines <- c(lines, sprintf("Expected sub-categories (%d): %s. Emit exactly these, each with %d parameters.",
                              scope$n_expected, paste(scope$sub_categories, collapse = ", "), n_req))
  }
  if (length(lines) == 1L) return("")
  paste(lines, collapse = "\n")
}

# The sub-categories a batch emitted against the expected set.
translator_level_subcats_check <- function(piece, scope) {
  exp_ <- .translator_norm_key(scope$sub_categories %||% character(0))
  ps <- piece$parameters
  got <- if (is.data.frame(ps) && "sub_category" %in% names(ps)) unique(.translator_norm_key(ps$sub_category)) else character(0)
  got <- got[!is.na(got) & nzchar(got)]
  if (!length(exp_)) return(data.frame(expected = length(got), found = length(got), missing = "", extra = "", ok = TRUE, stringsAsFactors = FALSE))
  miss <- setdiff(exp_, got); extra <- setdiff(got, exp_)
  data.frame(expected = length(exp_), found = length(got), missing = paste(miss, collapse = ", "),
             extra = paste(extra, collapse = ", "), ok = !length(miss) && !length(extra), stringsAsFactors = FALSE)
}

.translator_subcat_rejection <- function(level, chk) {
  paste0("REJECTED for '", level, "': the batch carries ", chk$found, " sub-categor", if (chk$found == 1L) "y" else "ies",
         " but the file has ", chk$expected, " for this system.",
         if (nzchar(chk$missing)) paste0(" Missing: ", chk$missing, ".") else "",
         if (nzchar(chk$extra)) paste0(" Not in this system: ", chk$extra, ".") else "",
         " Re-emit the batch for '", level, "' with exactly the expected sub-categories, every parameter for each,",
         " taking the values from this system's rows of the file. Same tool, mode = 'batch', same aggregation_level.")
}
