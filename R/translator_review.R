# AI review of the checks (2026-10-30)
#
# The server-side checks (R/translator_checks.R) find what a translation got
# wrong, but until now they only reported it: on the Zambia file of 30
# October the checks named a coefficient filled from the IPCC default where
# the file gives one, an MCF column with every range dropped and a set of
# manure ranges copied across rows, and all three reached the workbook.
#
# After the workbook is written and checked, the flagged items go back to
# the AI once, with the rows they point at. For each item the AI either
# returns the corrected rows (from the file, which is earlier in the same
# conversation) or explains, quoting the file, why it is not an error. The
# server applies the corrected rows, rewrites the workbook, runs the checks
# again, and lists every correction and every explanation in the checks
# file, so the user sees what the review changed and what it left alone.
#
# One round only. What is still flagged afterwards stays in the checks for
# the user, as before. A failed or stopped review keeps the template as it
# was.

.TRANSLATOR_REVIEW_MAX_ITEMS <- 120L
.TRANSLATOR_REVIEW_MAX_CHARS <- 40000L

.translator_rows_csv <- function(df, cols) {
  if (!is.data.frame(df) || !nrow(df)) return("")
  cols <- intersect(cols, names(df))
  if (!length(cols)) return("")
  con <- textConnection("out", "w", local = TRUE)
  on.exit(close(con))
  utils::write.csv(df[, cols, drop = FALSE], con, row.names = FALSE, na = "")
  paste(out, collapse = "\n")
}

# The text of the review request: the rules, the flagged items, and the
# current rows they concern.
.translator_review_request <- function(targets, piece, register = NULL) {
  tg <- targets
  # "placeholder range" can be long (one row per input without a range); it is
  # summarised per parameter, and the model is told when to act on it.
  rn <- tg[tg$check %in% "placeholder range", , drop = FALSE]
  tg <- tg[!tg$check %in% "placeholder range", , drop = FALSE]
  if (nrow(tg) > .TRANSLATOR_REVIEW_MAX_ITEMS) tg <- tg[seq_len(.TRANSLATOR_REVIEW_MAX_ITEMS), , drop = FALSE]
  items <- if (nrow(tg)) sprintf("[%d] %s | %s | %s", seq_len(nrow(tg)), tg$check, tg$where, tg$issue) else character(0)
  if (nrow(rn)) {
    by_p <- table(rn$parameter)
    items <- c(items, sprintf(paste0("[%d] placeholder range | %s | %d row(s) of %s have no uncertainty range in your ",
                                     "output, so a placeholder was written. Return the ranges only if the file states ",
                                     "one for them (for example a line that covers 'all sub-categories' or 'all manure ",
                                     "management systems'); otherwise add one not_errors entry for %s saying the file gives none."),
                              length(items) + seq_along(by_p), names(by_p), as.integer(by_p), names(by_p), names(by_p)))
  }

  # rows concerned: the flagged groups' parameter and manure rows, and the
  # time-series rows of the flagged group-years
  ps <- piece$parameters; mm <- piece$manure_management; ts <- piece$parameter_timeseries
  grp_lv <- function(g) { p <- strsplit(g %||% "", "||", fixed = TRUE)[[1]]; if (length(p) >= 3) as.character(c(p[2], p[3])) else c(NA_character_, NA_character_) }
  # 2026-10-30: not `targets$group %||% ...`, which drops every group when
  # the first target has none (a manure-wide finding), so no rows were sent
  grp_v <- if ("group" %in% names(targets)) as.character(targets$group) else rep(NA_character_, nrow(targets))
  gl <- base::t(vapply(grp_v, function(g) grp_lv(g), character(2), USE.NAMES = FALSE))
  if (!is.matrix(gl)) gl <- matrix(gl, ncol = 2L)
  keys_pg <- unique(paste(.translator_norm_level(gl[, 1]), gl[, 2], targets$parameter, sep = "##"))
  keys_g  <- unique(paste(.translator_norm_level(gl[, 1]), gl[, 2], sep = "##"))
  rows_p <- if (is.data.frame(ps) && nrow(ps)) {
    k <- paste(.translator_norm_level(ps$aggregation_level), ps$sub_category, ps$parameter, sep = "##")
    ps[k %in% keys_pg, , drop = FALSE]
  } else NULL
  manure_checks <- c("manure bounds missing", "manure bounds reused", "manure shares sum",
                     "manure coefficient consistency", "placeholder range")
  rows_m <- if (is.data.frame(mm) && nrow(mm)) {
    k <- paste(.translator_norm_level(mm$aggregation_level), mm$sub_category, sep = "##")
    sel <- k %in% keys_g
    # sheet-wide manure findings: one group per production system
    if (any(targets$check %in% manure_checks & targets$sheet %in% "Manure_Management")) {
      first <- !duplicated(paste(.translator_norm_level(mm$aggregation_level), mm$mms_type))
      sel <- sel | first
    }
    mm[sel, , drop = FALSE]
  } else NULL
  # 2026-10-30: a gap in a series or rows the trend ignores (C13) send every
  # time-series row of the group, so the model sees the whole series
  ts_grp_checks <- c("time series: gap", "time series: rows ignored")
  rows_t <- if (is.data.frame(ts) && nrow(ts) && any(targets$check %in% c("time-series year", ts_grp_checks))) {
    yr_t <- targets$check %in% "time-series year"
    yrs <- sub("^.* / ", "", targets$where[yr_t])
    k <- paste(.translator_norm_level(ts$aggregation_level), ts$sub_category, ts$year, sep = "##")
    want <- paste(.translator_norm_level(gl[yr_t, 1]), gl[yr_t, 2], yrs, sep = "##")
    g_t <- targets$check %in% ts_grp_checks
    kg <- paste(.translator_norm_level(ts$aggregation_level), ts$sub_category, sep = "##")
    want_g <- paste(.translator_norm_level(gl[g_t, 1]), gl[g_t, 2], sep = "##")
    ts[k %in% want | kg %in% want_g, , drop = FALSE]
  } else NULL
  rows_txt <- c(
    if (!is.null(rows_p) && nrow(rows_p)) c("parameters:", .translator_rows_csv(rows_p,
      c("cattle_type", "aggregation_level", "sub_category", "parameter", "mean", "uncertainty_pct",
        "lower", "upper", "distribution", "data_source"))),
    if (!is.null(rows_m) && nrow(rows_m)) c("manure_management:", .translator_rows_csv(rows_m,
      c("cattle_type", "aggregation_level", "sub_category", "mms_type", "fraction_pct", "lower_fraction",
        "upper_fraction", "distribution_fraction", "MCF_pct", "lower_mcf", "upper_mcf", "distribution_mcf",
        "EF3", "lower_ef3", "upper_ef3", "Frac_GasMS_pct", "lower_frac_gas", "upper_frac_gas",
        "Frac_LeachMS_pct", "lower_frac_leach", "upper_frac_leach"))),
    if (!is.null(rows_t) && nrow(rows_t)) c("parameter_timeseries:", .translator_rows_csv(rows_t, names(rows_t))))
  rows_txt <- paste(rows_txt, collapse = "\n")
  if (nchar(rows_txt) > .TRANSLATOR_REVIEW_MAX_CHARS)
    rows_txt <- paste0(substr(rows_txt, 1, .TRANSLATOR_REVIEW_MAX_CHARS), "\n[... cut: the rest of the rows are as you emitted them]")

  reg <- tryCatch(translator_register_block(register), error = function(e) "")
  paste0(
    "REVIEW. The template you produced has been written and checked against the uploaded file. ",
    "The checks flagged the items below. The uploaded file is earlier in this conversation: read it ",
    "again for each item.\n\n",
    "For each item, decide:\n",
    "(a) It is an error. Return the corrected rows, complete (every field of the row, not only the one that changes).\n",
    "(b) It is not an error. Add it to not_errors with the check name, the location, and one sentence that quotes the file.\n\n",
    "How to return corrections:\n",
    "- parameters: one complete row per corrected (aggregation_level, sub_category, parameter), with data_source set ",
    "to where the value comes from.\n",
    "- manure_management: one complete row per corrected (aggregation_level, sub_category, mms_type). For a spread the ",
    "file states as a percentage (for example 'all manure management systems, 0.5'), write the percentage in ",
    "fraction_unc_pct, mcf_unc_pct, ef3_unc_pct, frac_gas_unc_pct or frac_leach_unc_pct and leave the matching lower_ ",
    "and upper_ fields null: the server computes each row's bounds.\n",
    "- parameter_timeseries: one row per (aggregation_level, sub_category, year), with cattle_type and the value taken ",
    "from THAT year's column of the file. When the file gives one series for several groups (or for 'all categories'), ",
    "write it for each of those groups. Cover every year the file gives.\n",
    "- A line of the file that says 'all ...' (all production systems, all categories, all sub-categories, all manure ",
    "management systems) applies to every row it names.\n",
    "- Keep the distribution the file names for each row.\n",
    "- Return nothing else: rows you do not return stay as they are. Never invent a value: a correction comes from ",
    "the file or from a decision in this conversation.\n\n",
    "Call emit_inventory_piece with mode = \"review\".\n\n",
    "FLAGGED ITEMS (check | location | message)\n", paste(items, collapse = "\n"), "\n\n",
    "CURRENT ROWS CONCERNED (as you emitted them)\n", rows_txt,
    if (nzchar(reg %||% "")) paste0("\n\n", reg) else "")
}

# Apply the review's rows to the piece. Returns the new piece, the changes
# (one checks row each) and the items the review explained as not errors.
.translator_apply_review <- function(piece, rv) {
  changes <- list()
  fmtv <- function(v) {
    if (is.null(v) || length(v) == 0 || (length(v) == 1 && is.na(v))) return("(blank)")
    if (is.numeric(v)) return(format(signif(v, 7), trim = TRUE))
    as.character(v)
  }
  rec <- function(sheet, group, parameter, where, txt)
    changes[[length(changes) + 1L]] <<- data.frame(
      where = where, issue = txt, severity = "info", sheet = sheet, group = group,
      parameter = parameter, check = "corrected by the AI review", stringsAsFactors = FALSE)
  as_df <- function(x) {
    if (is.data.frame(x)) return(x)
    if (is.list(x) && length(x)) return(tryCatch(jsonlite::fromJSON(jsonlite::toJSON(x, auto_unbox = TRUE)), error = function(e) NULL))
    NULL
  }
  keyof <- function(d, keys) {
    parts <- lapply(keys, function(k) {
      v <- if (k %in% names(d)) as.character(d[[k]]) else rep(NA_character_, nrow(d))
      if (k == "aggregation_level") .translator_norm_level(v)
      else if (k == "year") as.character(suppressWarnings(as.integer(v)))
      else trimws(v)
    })
    do.call(paste, c(parts, sep = "||"))
  }
  upd <- function(df, rows, keys, sheet) {
    rows <- as_df(rows)
    if (is.null(rows) || !nrow(rows) || !all(keys %in% names(rows))) return(df)
    if (!is.data.frame(df)) df <- rows[0, , drop = FALSE]
    dk <- keyof(df, keys); rk <- keyof(rows, keys)
    skip <- c(keys, ".requested_aggregation_level")
    for (i in seq_len(nrow(rows))) {
      vals <- list()
      for (f in setdiff(names(rows), skip)) {
        v <- rows[[f]][i]
        if (is.list(v)) v <- unlist(v)
        if (is.null(v) || !length(v) || (length(v) == 1 && is.na(v))) next
        vals[[f]] <- v
      }
      grp <- paste(rows$cattle_type[i] %||% "", rows$aggregation_level[i] %||% "", rows$sub_category[i] %||% "", sep = "||")
      par <- if ("parameter" %in% names(rows)) as.character(rows$parameter[i]) else NA_character_
      where <- paste(vapply(keys, function(k) as.character(rows[[k]][i]), character(1)), collapse = " / ")
      j <- match(rk[i], dk)
      if (is.na(j)) {
        new <- as.list(rep(NA, ncol(df))); names(new) <- names(df)
        for (k in keys) new[[k]] <- rows[[k]][i]
        for (f in names(vals)) new[[f]] <- vals[[f]]
        for (f in setdiff(names(new), names(df))) df[[f]] <- if (nrow(df)) NA else logical(0)
        df <- rbind(df, as.data.frame(new[names(df)], stringsAsFactors = FALSE))
        dk <- c(dk, rk[i])
        rec(sheet, grp, par, where, sprintf("Added by the AI review: %s.",
            paste(names(vals), vapply(vals, fmtv, character(1)), sep = " = ", collapse = ", ")))
        next
      }
      ch <- character(0)
      for (f in names(vals)) {
        if (!f %in% names(df)) df[[f]] <- NA
        old <- df[[f]][j]; nv <- vals[[f]]
        if (is.numeric(df[[f]]) || (is.logical(df[[f]]) && is.numeric(nv))) {
          nv <- suppressWarnings(as.numeric(nv)); if (!is.finite(nv)) next
          if (is.logical(df[[f]])) df[[f]] <- as.numeric(df[[f]])
          o <- suppressWarnings(as.numeric(old))
          if (is.finite(o) && abs(o - nv) <= 1e-9 * max(1, abs(nv))) next
        } else if (!is.na(old) && identical(as.character(old), as.character(nv))) next
        df[[f]][j] <- nv
        ch <- c(ch, sprintf("%s %s -> %s", f, fmtv(old), fmtv(nv)))
      }
      if (length(ch)) rec(sheet, grp, par, where, sprintf("Corrected by the AI review: %s.", paste(ch, collapse = "; ")))
    }
    df
  }
  piece$parameters <- upd(piece$parameters, rv$parameters,
                          c("aggregation_level", "sub_category", "parameter"), "Parameters")
  piece$manure_management <- upd(piece$manure_management, rv$manure_management,
                                 c("aggregation_level", "sub_category", "mms_type"), "Manure_Management")
  # A row the review gives a relative spread for drops the bounds it had, so
  # the server recomputes them from the percentage (a null in a reply row
  # otherwise means "leave as it is").
  rm_ <- as_df(rv$manure_management); mm <- piece$manure_management
  if (is.data.frame(rm_) && nrow(rm_) && is.data.frame(mm) && nrow(mm) &&
      all(c("aggregation_level", "sub_category", "mms_type") %in% names(rm_))) {
    mk <- keyof(mm, c("aggregation_level", "sub_category", "mms_type"))
    rk <- keyof(rm_, c("aggregation_level", "sub_category", "mms_type"))
    for (sp in .TRANSLATOR_MANURE_REL) {
      if (!sp$u %in% names(rm_)) next
      u <- suppressWarnings(as.numeric(rm_[[sp$u]]))
      j <- match(rk[is.finite(u) & u > 0], mk); j <- j[!is.na(j)]
      if (!length(j)) next
      for (cl in c(sp$lo, sp$hi)) if (cl %in% names(mm)) mm[[cl]][j] <- NA
    }
    piece$manure_management <- mm
  }
  piece$parameter_timeseries <- upd(piece$parameter_timeseries, rv$parameter_timeseries,
                                    c("aggregation_level", "sub_category", "year"), "Parameter_TimeSeries")
  ne <- as_df(rv$not_errors)
  dismissed <- if (is.data.frame(ne) && nrow(ne) && all(c("where", "reason") %in% names(ne)))
    data.frame(where = as.character(ne$where),
               issue = paste("Checked by the AI review, not an error:", as.character(ne$reason)),
               severity = "info", sheet = NA_character_, group = NA_character_,
               parameter = NA_character_,
               check = "reviewed: not an error", stringsAsFactors = FALSE)
  else data.frame(where = character(), issue = character(), severity = character(), sheet = character(),
                  group = character(), parameter = character(), check = character(), stringsAsFactors = FALSE)
  ch <- if (length(changes)) do.call(rbind, changes) else dismissed[0, , drop = FALSE]
  list(piece = piece, changes = ch, dismissed = dismissed)
}

# The review step of a translation run. `on_done` is called once, in every
# outcome. Everything it needs is passed in, so it runs from the job chain
# without the session.
.translator_review_async <- function(state, system_prompt, history, register,
                                     on_chunk, on_tick, should_stop, info, inseq,
                                     job_id, on_done) {
  pc <- shiny::isolate(state$precheck)
  targets <- tryCatch(translator_review_targets(pc$issues), error = function(e) {
    message("translator review: selecting the items failed (", conditionMessage(e), ")"); NULL })
  # 2026-10-30: every exit of the review is logged; the first live run left
  # no trace of why it did not review anything.
  if (is.null(targets) || !nrow(targets)) {
    message("translator review: nothing to review (", if (is.null(pc$issues)) "no checks" else
            paste(nrow(pc$issues), "check rows, none selected"), ")")
    return(on_done())
  }
  json <- shiny::isolate(state$last_template_json)
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(piece)) { message("translator review: the template JSON could not be read"); return(on_done()) }
  info(sprintf("The checks flagged %d item(s). The AI is now looking at each one against your file, to correct it or explain it...",
               nrow(targets)))
  translator_job_update(job_id, stage = "review", progress = 0.96,
                        stage_label = "Reviewing the flagged items with the AI")
  req <- .translator_review_request(targets, piece, register)
  message(sprintf("translator review: %d item(s), request %d characters", nrow(targets), nchar(req)))
  msgs <- anthropic_build_messages(system_prompt, history = history, new_user_message = req)
  anthropic_chat_batch_template_force_async(
    msgs, on_chunk = on_chunk, on_tick = on_tick, should_stop = should_stop,
    on_result = function(resp) inseq({
      if (isTRUE(resp$stopped) || !is.null(resp$error)) {
        message("translator review: the call failed (", resp$error %||% "stopped", ")")
        info(paste0("The review could not be completed (", resp$error %||% "stopped",
                    "). The template is kept as it was, with the checks listed."))
        return(on_done())
      }
      .translator_log_usage(state, resp, stage = "review", expect_warm = TRUE)
      rv <- tryCatch(jsonlite::fromJSON(resp$reply, simplifyVector = TRUE), error = function(e) NULL)
      ap <- if (is.null(rv)) NULL else tryCatch(.translator_apply_review(piece, rv), error = function(e) {
        message("translator: applying the review failed (", conditionMessage(e), ")"); NULL })
      if (is.null(ap)) {
        message("translator review: the reply could not be read or applied (", nchar(resp$reply %||% ""), " characters)")
        info("The review reply could not be read. The template is kept as it was, with the checks listed.")
        return(on_done())
      }
      extra <- rbind(ap$changes, ap$dismissed)
      new_json <- if (nrow(ap$changes))
        as.character(jsonlite::toJSON(ap$piece, auto_unbox = TRUE, na = "null", null = "null",
                                      dataframe = "rows", digits = NA)) else json
      if (nrow(ap$changes) && !.translator_template_is_well_formed(new_json)) {
        message("translator: the reviewed template is not well formed; keeping the original")
        new_json <- json; extra <- ap$dismissed
      }
      if (!identical(new_json, json)) state$last_template_json <- new_json
      if (nrow(extra))
        .translator_finalise_template(state, shiny::isolate(state$last_template_json), info,
                                      extra_issues = extra, force = TRUE)
      left <- tryCatch(translator_review_targets(shiny::isolate(state$precheck)$issues), error = function(e) NULL)
      n_left <- if (is.null(left)) 0L else sum(!left$where %in% ap$dismissed$where)
      state$review <- list(flagged = nrow(targets), corrected = nrow(ap$changes),
                           not_errors = nrow(ap$dismissed), still_flagged = n_left)
      message(sprintf("translator review: %d correction(s), %d not error(s), %d still flagged",
                      nrow(ap$changes), nrow(ap$dismissed), n_left))
      info(sprintf("Review done: %d correction(s) made, %d item(s) explained as not errors, %d still flagged for you to check.",
                   nrow(ap$changes), nrow(ap$dismissed), n_left))
      on_done()
    }))
  invisible(NULL)
}
