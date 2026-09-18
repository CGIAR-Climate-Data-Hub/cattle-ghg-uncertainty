# =============================================================================
# translator_eval.R -- score a translator output against a ground truth, and
# (optionally) replay the in-app pipeline on a fixture to produce one.
# =============================================================================
#
# Two entry points, both from the project root:
#
#   1. SCORE (offline, free):
#        Rscript scripts/translator_eval.R score <translated.xlsx> <truth.csv> [report.md]
#        Rscript scripts/translator_eval.R check <translated.xlsx>   (QA/QC fails + consistency notes)
#
#      truth.csv has one row per expected cell:
#        aggregation_level, sub_category, parameter, mean, lower, upper, data_source
#      (lower/upper/data_source may be blank). Manure rows use
#      parameter = "MMS:<mms_type>" with mean = fraction_pct.
#      The report gives: value match rate (relative tolerance 0.5 %),
#      bounds bracketing, data_source correctness, sub-category coverage,
#      manure fraction sums, and a list of every mismatch.
#
#   2. REPLAY (calls the API, costs money, never in CI):
#        Rscript scripts/translator_eval.R replay <fixture.xlsx> <transcript.json> <out.xlsx>
#
#      transcript.json is a JSON array of the user's clarification answers
#      in order. The script runs Explore, one Clarify turn per answer,
#      Discovery, the batch (or full) emission and the writer, exactly as
#      chat_ui.R does, without Shiny, and logs tokens, dollars and seconds
#      per stage to stderr. Needs ANTHROPIC_API_KEY in .Renviron.
#
# Why this exists (plan E): nothing in the translator should change what the
# model emits without a number saying whether the output got better or
# worse. The June writer contamination (9 of 56 values wrong) was found by
# exactly this kind of comparison, by hand. A Zambia replay costs about $5
# and 45 minutes; the offline score costs nothing and takes a second.
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("usage: score <translated.xlsx> <truth.csv> [report.md] | replay <fixture.xlsx> <transcript.json> <out.xlsx>")

for (f in sort(list.files("R", pattern = "[.]R$", full.names = TRUE))) suppressMessages(source(f, local = FALSE))

# ---- scoring -----------------------------------------------------------------

translator_score <- function(xlsx, truth_csv, tol_rel = 0.005) {
  pu <- suppressMessages(parse_uploaded_template(xlsx))
  ps <- pu$param_specs
  mn <- pu$manure
  tr <- utils::read.csv(truth_csv, stringsAsFactors = FALSE, check.names = FALSE,
                        na.strings = c("", "NA"))
  for (nm in c("aggregation_level", "sub_category", "parameter", "data_source"))
    if (!nm %in% names(tr)) tr[[nm]] <- NA_character_
  for (nm in c("mean", "lower", "upper")) if (!nm %in% names(tr)) tr[[nm]] <- NA_real_
  norm <- function(x) .translator_norm_level(x)
  ps_key <- paste(norm(ps$aggregation_level), ps$sub_category, ps$parameter)
  rows <- list()
  for (i in seq_len(nrow(tr))) {
    t <- tr[i, ]
    if (startsWith(as.character(t$parameter), "MMS:")) {
      mms <- sub("^MMS:", "", t$parameter)
      hit <- mn[norm(mn$aggregation_level) == norm(t$aggregation_level) &
                mn$sub_category == t$sub_category & mn$mms_type == mms, , drop = FALSE]
      got <- if (nrow(hit)) suppressWarnings(as.numeric(hit$fraction_pct[1])) else NA_real_
      rows[[i]] <- data.frame(kind = "manure", key = paste(t$aggregation_level, t$sub_category, mms),
                              expected = t$mean, got = got,
                              value_ok = !is.na(got) && !is.na(t$mean) && abs(got - t$mean) <= tol_rel * max(abs(t$mean), 1e-9),
                              bounds_ok = NA, source_ok = NA, stringsAsFactors = FALSE)
      next
    }
    j <- match(paste(norm(t$aggregation_level), t$sub_category, t$parameter), ps_key)
    got <- if (!is.na(j)) ps$mean[j] else NA_real_
    value_ok <- !is.na(got) && !is.na(t$mean) &&
      (abs(got - t$mean) <= tol_rel * max(abs(t$mean), 1e-9))
    bounds_ok <- if (!is.na(j) && !is.na(t$lower) && !is.na(t$upper))
      !is.na(ps$lower[j]) && !is.na(ps$upper[j]) &&
        abs(ps$lower[j] - t$lower) <= tol_rel * max(abs(t$lower), 1e-9) &&
        abs(ps$upper[j] - t$upper) <= tol_rel * max(abs(t$upper), 1e-9)
      else NA
    source_ok <- if (!is.na(j) && !is.na(t$data_source) && "data_source" %in% names(ps))
      identical(tolower(trimws(ps$data_source[j])), tolower(trimws(t$data_source))) else NA
    rows[[i]] <- data.frame(kind = "parameter",
                            key = paste(t$aggregation_level, t$sub_category, t$parameter),
                            expected = t$mean, got = got, value_ok = value_ok,
                            bounds_ok = bounds_ok, source_ok = source_ok, stringsAsFactors = FALSE)
  }
  res <- do.call(rbind, rows)
  # Structural checks independent of the truth file.
  n_groups <- length(unique(paste(ps$aggregation_level, ps$sub_category)))
  complete <- nrow(ps) == n_groups * nrow(PARAM_CATALOGUE)
  bracket  <- with(ps, mean(is.na(lower) | is.na(upper) | (lower <= mean & mean <= upper)))
  mm_sum <- if (!is.null(mn) && nrow(mn)) {
    g <- paste(mn$aggregation_level, mn$sub_category)
    s <- tapply(suppressWarnings(as.numeric(mn$fraction_pct)), g, sum, na.rm = TRUE)
    mean(abs(s - 100) <= 1)
  } else NA
  list(rows = res,
       summary = list(
         n_truth = nrow(res),
         value_match_rate  = mean(res$value_ok),
         bounds_match_rate = if (any(!is.na(res$bounds_ok))) mean(res$bounds_ok, na.rm = TRUE) else NA,
         source_match_rate = if (any(!is.na(res$source_ok))) mean(res$source_ok, na.rm = TRUE) else NA,
         missing_cells     = sum(is.na(res$got)),
         n_groups = n_groups, rows_complete = complete,
         bracket_rate = bracket, manure_sum_ok_rate = mm_sum,
         stamp = as.character(pu$metadata$notes %||% "")))
}

translator_score_report <- function(sc, path = NULL) {
  s <- sc$summary
  pct <- function(x) if (is.na(x)) "n/a" else sprintf("%.1f %%", 100 * x)
  md <- c("# Translator evaluation", "",
          sprintf("- truth cells: %d", s$n_truth),
          sprintf("- value match: %s", pct(s$value_match_rate)),
          sprintf("- bounds match: %s", pct(s$bounds_match_rate)),
          sprintf("- data_source match: %s", pct(s$source_match_rate)),
          sprintf("- cells missing from the workbook: %d", s$missing_cells),
          sprintf("- groups: %d; rows complete (groups x %d): %s", s$n_groups, nrow(PARAM_CATALOGUE), s$rows_complete),
          sprintf("- rows whose bounds bracket the mean: %s", pct(s$bracket_rate)),
          sprintf("- manure groups summing to 100: %s", pct(s$manure_sum_ok_rate)),
          sprintf("- stamp: %s", s$stamp), "",
          "## Mismatches", "",
          "| kind | key | expected | got | value | bounds | source |", "|---|---|---|---|---|---|---|")
  bad <- sc$rows[!sc$rows$value_ok | (!is.na(sc$rows$bounds_ok) & !sc$rows$bounds_ok) |
                 (!is.na(sc$rows$source_ok) & !sc$rows$source_ok), , drop = FALSE]
  for (i in seq_len(nrow(bad)))
    md <- c(md, sprintf("| %s | %s | %s | %s | %s | %s | %s |", bad$kind[i], bad$key[i],
                        format(bad$expected[i]), format(bad$got[i]), bad$value_ok[i],
                        bad$bounds_ok[i], bad$source_ok[i]))
  if (!nrow(bad)) md <- c(md, "(none)")
  if (!is.null(path)) writeLines(md, path, useBytes = TRUE)
  md
}

# ---- replay (paid) -------------------------------------------------------------

translator_replay <- function(fixture, transcript_json, out_xlsx) {
  answers <- jsonlite::read_json(transcript_json, simplifyVector = TRUE)
  if (!nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) stop("ANTHROPIC_API_KEY is not set")
  # A minimal stand-in for the Shiny state and session.
  state <- new.env()
  state$user_email <- "eval@local"; state$messages <- list(); state$batch_parts <- list()
  state$last_template_json <- NULL; state$last_error <- NULL; state$pending <- FALSE
  state$prompt_stale <- FALSE
  session <- list(sendCustomMessage = function(type, msg) invisible(NULL))
  t0 <- Sys.time()
  parsed <- .translator_read_upload_memo(fixture, basename(fixture))
  built <- .translator_build_upload_message(parsed, basename(fixture))
  state$messages[[1]] <- list(role = "user", content = built$content, display = built$display,
                              source = "server_upload")
  .translator_send(state, session, stage = "explore")
  if (!is.null(state$last_error)) stop("explore failed: ", state$last_error)
  for (a in answers) {
    state$messages[[length(state$messages) + 1]] <- list(role = "user", content = a, display = a)
    .translator_send(state, session, stage = "clarify")
    if (!is.null(state$last_error)) message("clarify warning: ", state$last_error)
  }
  .translator_force_template(state, session)
  if (is.null(state$last_template_json)) stop("emission failed: ", state$last_error)
  .translator_write_template_xlsx(state$last_template_json, out_xlsx)
  message(sprintf("replay done in %.1f min; workbook at %s", as.numeric(difftime(Sys.time(), t0, units = "mins")), out_xlsx))
  if (!is.null(state$last_error)) message("warnings: ", state$last_error)
  invisible(out_xlsx)
}

# ---- dispatch -----------------------------------------------------------------

mode <- args[1]
if (identical(mode, "score")) {
  stopifnot(length(args) >= 3)
  sc <- translator_score(args[2], args[3])
  md <- translator_score_report(sc, if (length(args) >= 4) args[4] else NULL)
  cat(md, sep = "\n")
  # 2026-09-18: the relational checks the app shows before download.
  pu <- suppressMessages(parse_uploaded_template(args[2]))
  notes <- translator_consistency_checks(pu$param_specs, pu$manure)
  cat(sprintf("
## Consistency notes (%d)
", nrow(notes)))
  for (i in seq_len(nrow(notes))) cat(sprintf("- [%s] %s
", notes$where[i], notes$issue[i]))
} else if (identical(mode, "replay")) {
  stopifnot(length(args) >= 4)
  translator_replay(args[2], args[3], args[4])
} else if (identical(mode, "check")) {
  # check <xlsx>: QA/QC failures + consistency notes for a produced workbook.
  stopifnot(length(args) >= 2)
  pu <- suppressMessages(parse_uploaded_template(args[2]))
  region <- as.character(pu$metadata$region %||% "global"); if (!nzchar(region[1])) region <- "global"
  qa <- run_qaqc(pu$param_specs, region = region[1], manure_data = pu$manure)
  s <- qaqc_summary(qa)
  cat(sprintf("QA/QC: %d pass, %d warn, %d fail
", s$n_pass, s$n_warn, s$n_fail))
  f <- qa[qa$status == "fail", ]
  for (i in seq_len(nrow(f))) cat(sprintf("- FAIL %s: %s
", f$id[i], f$message[i]))
  notes <- translator_consistency_checks(pu$param_specs, pu$manure)
  cat(sprintf("
Consistency notes (%d)
", nrow(notes)))
  for (i in seq_len(nrow(notes))) cat(sprintf("- [%s] %s
", notes$where[i], notes$issue[i]))
} else stop("unknown mode '", mode, "'; use score, replay or check")
