# Usage: Rscript scripts/test_qaqc_views.R   (no API call, about 30 s)
# The QA/QC tab after the Nairobi review (2026-10-28, second pass): one
# table, one row per parameter with its worst status and counts, opening
# to its findings; status tiles filter it (a single status keeps the
# parameters concerned and shows every finding of theirs that is not a
# pass); no Ignore column; the Data Input table read-only with the
# uncertainty columns. Through the real app server on the Country Y example.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"))
options(shiny.testmode = TRUE)
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
PASS_MARK <- "&#10003;"; WARN_MARK <- "&#9651;"; INFO_MARK <- "&#9432;"; FAIL_MARK <- "&#10007;"

shiny::testServer(app_server, {
  # The examples pass every check, so two edits give the table something
  # to show: a lower bound above the mean (fail) and a body weight three
  # times the IPCC default (warn).
  ps <- generate_country_y_example()
  i <- which(ps$parameter == "DE")[1]; ps$lower[i] <- ps$mean[i] * 1.2
  k <- which(ps$parameter == "BW")[1]; ps[k, c("mean", "lower", "upper")] <- ps[k, c("mean", "lower", "upper")] * 3
  rv$param_specs <- fill_bounds(ps)
  df <- qaqc_result()
  ok(any(df$status == "fail") && any(df$status == "warn"), "fixture: at least one failure and one warning")
  par <- ifelse(nzchar(df$parameter), df$parameter, t("qa_par_sheet"))
  p <- qa_parents()                                   # no tile clicked: every check
  ok(nrow(df) > 0 && nrow(p) == length(unique(par)), "all: one row per parameter")
  ok(sum(p$n_fail + p$n_warn + p$n_info + p$n_pass) == nrow(df), "all: the counts add up to every finding")
  ok(all(diff(.qa_status_rank[p$worst]) <= 0), "all: worst status first")
  ok(all(grepl("<table", p$child, fixed = TRUE)) && any(grepl(PASS_MARK, p$child, fixed = TRUE)),
     "all: every row carries its findings, passes included")
  session$setInputs(qa_status_filter = "warn")
  pw <- qa_parents()
  ok(nrow(pw) >= 1 && all(pw$n_warn >= 1), "warn: only the parameters with a warning")
  ok(!any(grepl(PASS_MARK, pw$child, fixed = TRUE)) && all(grepl(WARN_MARK, pw$child, fixed = TRUE)),
     "warn: the open findings show the warnings and leave the passes out")
  both <- pw$parameter[pw$n_info > 0]
  if (length(both))
    ok(grepl(INFO_MARK, pw$child[pw$parameter == both[1]], fixed = TRUE),
       "warn: a parameter's other findings (info) are shown with its warning")
  session$setInputs(qa_status_filter = "pass")
  pp <- qa_parents()
  ok(all(pp$n_pass >= 1) && !any(grepl(WARN_MARK, pp$child, fixed = TRUE)) && all(grepl(PASS_MARK, pp$child, fixed = TRUE)),
     "pass: the pass findings only")
  session$setInputs(qa_status_filter = "fail")
  pf <- qa_parents()
  ok(nrow(pf) == 0 || all(pf$n_fail >= 1 & grepl(FAIL_MARK, pf$child, fixed = TRUE)),
     "fail: only the parameters with a failure, their failure shown")
  session$setInputs(qa_status_filter = "all")
  # the rendered tables (testServer hands back the widget as JSON text)
  widget <- function(o) jsonlite::fromJSON(as.character(o), simplifyVector = FALSE)
  headers <- function(w) { h <- as.character(w$x$container); m <- regmatches(h, gregexpr("<th[^>]*>[^<]*</th>", h))[[1]]; gsub("<[^>]+>", "", m) }
  wq <- widget(output$qaqc_table)
  hq <- headers(wq)
  ok(length(hq) == 9L && hq[2] == t("qa_col_parameter") && hq[4] == t("qa_badge_fail") && !any(grepl("Ignore", hq, fixed = TRUE)),
     "table: expander, parameter, status, four counts, the hidden findings and rank; no Ignore column")
  ok(grepl("qaToggleAll", as.character(wq$x$callback), fixed = TRUE) && !grepl("if (true)", as.character(wq$x$callback), fixed = TRUE),
     "table: rows open on click; nothing opens by itself when every check is shown")
  session$setInputs(qa_status_filter = "warn")
  ok(grepl("if (true)", as.character(widget(output$qaqc_table)$x$callback), fixed = TRUE),
     "table: in a single-status view every row opens by itself")
  tiles <- as.character(output$qa_tiles$html)
  ok(grepl("qa_status_filter", tiles, fixed = TRUE) && grepl("'fail'|&#39;fail&#39;", tiles) && grepl("'all'|&#39;all&#39;", tiles),
     "tiles: one button per status sets the filter")
  # the Data Input table: read-only, the uncertainty columns, no editing option
  wp <- widget(output$param_table)
  ok(is.null(wp$x$editable) || isFALSE(wp$x$editable), "Data Input table: not editable")
  ok(all(c("parameter", "mean", "uncertainty_pct", "distribution", "lower", "upper", "param_type") %in% headers(wp)), "Data Input table: shows the distribution, uncertainty, bounds and parameter type")
  cat("QAQC VIEWS TEST PASSED\n")
})
