# Usage: Rscript scripts/test_translator_roundtrip.R   (no API call, about 40 s)
#
# 2026-11-01: the server-side pieces between the AI's JSON and the app's
# QA/QC tab, end to end on a small synthetic file:
#   1. translator_rebuild_series: the series of a group and parameter whose
#      file row the source check confirmed is copied from that row.
#   2. The blocking failures travel on the hidden Translator_Checks sheet,
#      parse_uploaded_template reads them back and run_qaqc reports them.
suppressMessages({for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
n_ok <- 0L; n_bad <- 0L
ok <- function(cond, what) { if (isTRUE(cond)) { n_ok <<- n_ok + 1L; cat("PASS", what, "\n") } else { n_bad <<- n_bad + 1L; cat("FAIL", what, "\n"); stop(what) } }

# ---- 1. the series from the file row -------------------------------------------
df <- data.frame(a = c("Sys A", "Weight (kg)", "Cows", "Feedlot", NA, "Sys A", "Milk (kg/lactating day)", "Cows"),
                 `2020` = c(NA, NA, 400, 300.0, NA, NA, NA, 4.1),
                 `2021` = c(NA, NA, 405, 301.0, NA, NA, NA, 4.2),
                 `2022` = c(NA, NA, 410, 301.0, NA, NA, NA, 4.2375),
                 check.names = FALSE, stringsAsFactors = FALSE)
sheets <- list(list(name = "Data", json = .translator_table_to_json(df, "Data"), n_rows = nrow(df)))
sv <- list(
  list(system = "Sys A", label = "Cows", section = "Weight (kg)", sheet = "Data", row = 4L, col = "2022", mean = 410, parameter = "BW",
       sub_category = "other_cows", aggregation_level = "sys_a"),
  list(system = "Sys A", label = "Feedlot", section = "Weight (kg)", sheet = "Data", row = 5L, col = "2022", mean = 301, parameter = "BW",
       sub_category = "feedlot_cattle", aggregation_level = "sys_a"),
  list(system = "Sys A", label = "Cows", section = "Milk (kg/lactating day)", sheet = "Data", row = 9L, col = "2022", mean = 2.9836, parameter = "Milk",
       sub_category = "other_cows", aggregation_level = "sys_a"))
f <- 257 / 365
ps <- data.frame(cattle_type = "non_dairy", aggregation_level = "sys_a", sub_category = c("other_cows", "feedlot_cattle", "other_cows"),
                 parameter = c("BW", "BW", "Milk"), mean = c(410, 301, 4.2375 * f), distribution = "normal", param_type = "coefficient",
                 data_source = "user_file", conversion_factor = c(NA, NA, f), stringsAsFactors = FALSE)
# the AI's series: cows BW right, feedlot BW smoothed (300, 302, 304) and 2021 missing for milk
ts <- data.frame(cattle_type = "non_dairy", aggregation_level = "sys_a",
                 sub_category = c("other_cows", "other_cows", "other_cows", "feedlot_cattle", "feedlot_cattle", "feedlot_cattle"),
                 year = c(2020L, 2021L, 2022L, 2020L, 2021L, 2022L),
                 BW = c(400, 405, 410, 300, 302, 304), Milk = c(4.1 * f, NA, 4.2375 * f, NA, NA, NA), stringsAsFactors = FALSE)
piece <- list(parameters = ps, manure_management = data.frame(), parameter_timeseries = ts)
out <- translator_rebuild_series(piece, sv, sheets)
t2 <- out$parameter_timeseries
fl <- t2[t2$sub_category == "feedlot_cattle", ]; fl <- fl[order(fl$year), ]
ok(identical(fl$BW, c(300, 301, 301)), "the feedlot BW series is the file row, not the AI's smoothed one")
cw <- t2[t2$sub_category == "other_cows", ]; cw <- cw[order(cw$year), ]
ok(isTRUE(all.equal(cw$Milk, c(4.1, 4.2, 4.2375) * f)), "the milk series is the file row converted with the row's factor, the missing year filled")
ok(identical(cw$BW, c(400, 405, 410)), "a right series is unchanged")
sc <- out$server_corrections
ok(is.data.frame(sc) && sum(sc$check == "series taken from the file") == 3L, "one record per rebuilt series")
ok(sc$severity[sc$parameter == "BW" & grepl("feedlot", sc$group)] == "warn" && grepl("differed in 2 year", sc$issue[sc$parameter == "BW" & grepl("feedlot", sc$group)]),
   "a series that differed is a warning naming the years")
ok(sc$severity[sc$parameter == "BW" & grepl("other_cows", sc$group)] == "info", "a series that agreed is an info row")
ok(grepl("had no value in 1 year", sc$issue[sc$parameter == "Milk"]), "a missing year is named")
# the AI's rows without their system label (the writer fills it from the
# requested level): matched on that level, no second row per year
ts_nolab <- ts; ts_nolab$aggregation_level <- NA_character_; ts_nolab$.requested_aggregation_level <- "sys_a"
out2 <- translator_rebuild_series(list(parameters = ps, parameter_timeseries = ts_nolab), sv, sheets)
t3 <- out2$parameter_timeseries
ok(nrow(t3) == 6L && all(t3$aggregation_level == "sys_a") && !any(duplicated(paste(t3$sub_category, t3$year))),
   "rows without a system label are matched on the requested level, not duplicated")
ts_dup <- rbind(ts, ts[ts$sub_category == "other_cows" & ts$year == 2021L, ])   # the AI wrote a year twice
out3 <- translator_rebuild_series(list(parameters = ps, parameter_timeseries = ts_dup), sv, sheets)
ok(!any(duplicated(paste(out3$parameter_timeseries$sub_category, out3$parameter_timeseries$year))), "a year the AI wrote twice is merged into one row")
json <- as.character(jsonlite::toJSON(piece, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
j2 <- translator_rebuild_series_json(json, sv, sheets)
ok(!identical(j2, json) && is.data.frame(jsonlite::fromJSON(j2)$parameter_timeseries), "the JSON path rebuilds and re-serialises")
ok(identical(translator_rebuild_series_json(json, list(), sheets), json), "no entries: the JSON is untouched")

# ---- 2. the blocking failures through the workbook to the QA/QC tab ------------
tmp <- tempfile(fileext = ".xlsx")
piece2 <- list(
  inventory_metadata = list(country = "Testland", region = "africa", inventory_year = 2022, ipcc_version = "2019_refinement", species = "cattle"),
  parameters = data.frame(cattle_type = "non_dairy", aggregation_level = "sys_a", sub_category = "other_cows",
                          parameter = c("N", "BW"), mean = c(1000, 410), uncertainty_pct = c(10, 15), distribution = "normal",
                          param_type = c("activity_data", "coefficient"), data_source = "user_file", stringsAsFactors = FALSE),
  manure_management = data.frame(), parameter_timeseries = data.frame())
.translator_write_official_template(piece2, tmp)
issues <- data.frame(where = c("a", "b", "c"), issue = c("The BW series of this group has 2 value(s) that are in no year column of the file (2019 to 2020).",
                                                        "a warning that must not block", "a failing check that is not blocking"),
                     severity = c("fail", "warn", "fail"), sheet = c("Parameter_TimeSeries", "Parameters", "Parameters"),
                     group = c("non_dairy / sys_a / other_cows", "non_dairy / sys_a / other_cows", "non_dairy / sys_a / other_cows"),
                     parameter = c("BW", "BW", "N"), check = c("time-series value not in file", "placeholder range", "bounds_order"),
                     stringsAsFactors = FALSE)
.translator_annotate_workbook(tmp, issues = issues)
ok("Translator_Checks" %in% readxl::excel_sheets(tmp), "the hidden sheet is written")
pu <- suppressMessages(suppressWarnings(parse_uploaded_template(tmp)))
ok(is.data.frame(pu$translator_checks) && nrow(pu$translator_checks) == 1L && pu$translator_checks$check == "time-series value not in file",
   "parse_uploaded_template reads back the one blocking failure (the warning and the non-blocking fail stay out)")
qa <- run_qaqc(pu$param_specs, region = "africa", manure_data = pu$manure, translator_checks = pu$translator_checks)
tr <- qa[grepl("^translator_", qa$check), ]
ok(nrow(tr) == 1L && tr$status == "fail" && grepl("^Translator check: The BW series", tr$message) && identical(tr$level, "sys_a"),
   "run_qaqc reports it as a failure with the translator's text and the system")
ok(qaqc_summary(qa)$n_fail >= 1L, "the QA/QC summary counts it")
qa0 <- run_qaqc(pu$param_specs, region = "africa", manure_data = pu$manure, translator_checks = NULL)
ok(!any(grepl("^translator_", qa0$check)), "no translator rows without the sheet")
unlink(tmp)

cat(sprintf("\n%d passed, %d failed\n", n_ok, n_bad))
if (n_bad == 0L) cat("ROUNDTRIP TESTS PASSED\n")
