# Usage: Rscript scripts/test_qaqc_views.R   (no API call, about 30 s)
# The QA/QC tab after the Nairobi review (2026-10-28): an overview by
# parameter and check, a status filter, details narrowed by the selected
# overview row; no Ignore column; the Data Input table read-only with the
# uncertainty columns. Through the real app server on the Country Y example.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"))
options(shiny.testmode = TRUE)
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }

shiny::testServer(app_server, {
  rv$param_specs <- fill_bounds(generate_country_y_example())
  session$setInputs(qa_status_filter = "all")
  df <- qaqc_result()
  ov <- qa_overview()
  ok(nrow(df) > 0 && nrow(ov) == length(unique(paste(df$parameter, df$check))), "overview: one row per parameter and check")
  ok(sum(ov$n_fail + ov$n_warn + ov$n_info + ov$n_pass) == nrow(df), "overview: the counts add up to every finding")
  ok(all(ov$worst[ov$n_fail > 0] == "fail") && identical(ov$worst[1], if (any(ov$n_fail > 0)) "fail" else ov$worst[1]), "overview: worst status per row, failures first")
  ok(nrow(qa_details()) == nrow(df), "details: everything when nothing is selected")
  session$setInputs(qaqc_overview_rows_selected = 1L)
  d1 <- qa_details()
  ok(nrow(d1) >= 1 && all(d1$parameter == ov$parameter[1]) && all(d1$check == ov$check[1]), "details: narrowed to the selected overview row")
  session$setInputs(qaqc_overview_rows_selected = integer(0))
  ok(nrow(qa_details()) == nrow(df), "details: everything again when the selection is cleared")
  session$setInputs(qa_status_filter = "warn")
  ok(all(qa_filtered()$status == "warn") && all(qa_overview()$worst == "warn"), "filter: warnings only, in both tables")
  session$setInputs(qa_status_filter = "all")
  # the rendered tables (testServer hands back the widget as JSON text)
  widget <- function(o) jsonlite::fromJSON(as.character(o), simplifyVector = FALSE)
  headers <- function(w) { h <- as.character(w$x$container); m <- regmatches(h, gregexpr("<th[^>]*>[^<]*</th>", h))[[1]]; gsub("<[^>]+>", "", m) }
  wq <- widget(output$qaqc_table)
  ok(!any(grepl("Ignore", headers(wq), fixed = TRUE)) && length(headers(wq)) == 5L, "details table: group, parameter, check, status, message; no Ignore column")
  # the Data Input table: read-only, the uncertainty columns, no editing option
  wp <- widget(output$param_table)
  ok(is.null(wp$x$editable) || isFALSE(wp$x$editable), "Data Input table: not editable")
  ok(all(c("parameter", "mean", "uncertainty_pct", "distribution", "lower", "upper", "param_type") %in% headers(wp)), "Data Input table: shows the distribution, uncertainty, bounds and parameter type")
  cat("QAQC VIEWS TEST PASSED\n")
})
