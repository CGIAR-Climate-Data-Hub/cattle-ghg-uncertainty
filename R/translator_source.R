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
  x <- gsub("[[:space:]]+", " ", x)
  gsub("[^[:alnum:] ]+", "", x)
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
  # section
  sec <- as.character(e$section %||% "")
  rsec <- as.character(row[["_section"]] %||% "")
  if (nzchar(sec) || nzchar(rsec)) {
    if (.translator_fold(sec) != .translator_fold(rsec))
      what <- c(what, sprintf("section (row: %s; entry: %s)", if (nzchar(rsec)) rsec else "none", if (nzchar(sec)) sec else "none"))
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
  tx <- NULL
  for (fld in c("label", "system")) {
    want <- .translator_fold(e[[fld]] %||% "")
    if (!nzchar(want)) next
    if (is.null(tx)) tx <- texts_up()
    if (!any(grepl(want, tx, fixed = TRUE) | vapply(tx, function(t) nzchar(t) && grepl(t, want, fixed = TRUE), logical(1))))
      what <- c(what, sprintf("%s '%s' not near row %s", fld, e[[fld]], rk))
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
    "source_values block, corrected, with the same fields. Nothing else: no other section, no questions, ",
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
