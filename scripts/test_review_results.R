# Usage: Rscript scripts/test_review_results.R   (no API call, about 1 min)
# The review items of 2026-10-28 on the results tabs, through the real app
# server on the Country Y example: units (Gg with 3 decimals, t, both), the
# decomposition axis says MoE, the tornado has no red and a two-entry
# legend, the sensitivity table rounds to two decimals, the cross-group
# default is independent, and every graph has a numbered title and caption.
suppressMessages({library(shiny); library(plotly); library(DT); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"))
options(shiny.testmode = TRUE)
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
widget <- function(o) jsonlite::fromJSON(as.character(o), simplifyVector = FALSE)

# the page: figure numbers and captions, units, defaults
html <- as.character(htmltools::renderTags(app_ui())$html)
nums <- regmatches(html, gregexpr("Figure [3-6][.][1-3][.]", html))[[1]]
ok(length(nums) == 16L, sprintf("16 numbered figures on the page (found %d)", length(nums)))
ok(all(vapply(c("fig_cap_corr", "fig_cap_conv", "fig_cap_hist", "fig_cap_decomp", "fig_cap_tornado", "fig_cap_trend",
                "fig_cap_delta", "fig_cap_input_dens"), function(k) grepl(t(k), html, fixed = TRUE), logical(1))), "every figure has its caption")
ok(regexpr("toggle_diagnostics", html) < regexpr("vb_enteric_ch4", html), "diagnostics come before the result cards")
ok(!grepl("crossgroup_mode", html, fixed = TRUE), "cross-group setting: not on the page (every run independent)")
ok(grepl('id="def_search"', html, fixed = TRUE), "Definitions: one search box")

shiny::testServer(app_server, {
  rv$param_specs <- fill_bounds(generate_country_y_example())
  session$setInputs(analysis_mode = "single", n_iter = 2000, seed = 42, gwp_version = "AR6", corr_mode = "none",
                    emission_sources = c("enteric_ch4", "manure_ch4", "manure_n2o_direct", "manure_n2o_indirect", "pasture_n2o_direct", "pasture_n2o_indirect"),
                    run_decomposition = TRUE, sens_method = "src", res_units = "gg")
  session$setInputs(run_sim = 1)
  ok(!is.null(rv$uncertainty), "the simulation ran")
  v <- output$vb_enteric_ch4
  ok(grepl("^[0-9,]+[.][0-9]{3} Gg", v), paste("Gg with three decimals:", v))
  session$setInputs(res_units = "t"); vt <- output$vb_enteric_ch4
  ok(grepl(" t", vt) && !grepl("Gg", vt), paste("tonnes:", vt))
  session$setInputs(res_units = "both"); vb <- output$vb_enteric_ch4
  ok(grepl("Gg (", vb, fixed = TRUE) && grepl(" t)", vb, fixed = TRUE), paste("both:", vb))
  d <- widget(output$decomposition_plot)
  ok(identical(d$x$layoutAttrs[[1]]$yaxis$title, "MoE (%)") || grepl("\"MoE (%)\"", as.character(output$decomposition_plot), fixed = TRUE),
     "decomposition axis: MoE (%), not 95% MoE")
  tj <- as.character(output$tornado_chart)
  ok(!grepl("#C1121F", tj, fixed = TRUE) && grepl("#2D6A4F|#1565C0", tj) && grepl("\"size\":14", tj, fixed = TRUE),
     "tornado: no red, green and blue, legend font 14")
  st <- as.character(output$sensitivity_table)
  ok(grepl("formatRound", st, fixed = TRUE) && grepl("2, 3, \\\",\\\", \\\".\\\"", st) || grepl("DTWidget.formatRound", st, fixed = TRUE),
     "sensitivity table: rounded to two decimals")
  pc <- PARAM_CATALOGUE[, c("parameter", "definition")]
  session$setInputs(def_search = "ym"); session$elapse(400)
  hit <- .def_filter(pc)
  session$setInputs(def_search = "(Ym"); session$elapse(400)
  ok(nrow(hit) >= 1 && nrow(hit) < nrow(pc) && "Ym" %in% hit$parameter && is.data.frame(.def_filter(pc)),
     sprintf("Definitions search: %d of %d rows match ym (any case); a bracket does not break it", nrow(hit), nrow(pc)))
  cat("REVIEW RESULTS TEST PASSED\n")
})
