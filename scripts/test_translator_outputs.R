# Usage: Rscript scripts/test_translator_outputs.R   (no API call, about 40 s)
# WP3 checks (C7 Parameters vs time series, C8 percent vs fraction, C9
# defaults applied) and WP4 outputs (file names, checks workbook, conversation
# document, workbook annotation).
suppressMessages({library(shiny); library(readxl); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
td <- tempfile("out"); dir.create(td)

# ---- a two-group fixture ----------------------------------------------------------
grp <- function(sc, N, DE) data.frame(
  cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = sc,
  parameter = c("N", "DE", "pct_pregnant", "Ym"), mean = c(N, DE, 0.5, 6.5),
  uncertainty_pct = c(10, 15, 20, 20), lower = NA, upper = NA, distribution = "normal",
  param_type = c("activity_data", "coefficient", "coefficient", "coefficient"),
  data_source = "user_file", stringsAsFactors = FALSE)
ps <- rbind(grp("bulls", 100, 55), grp("heifers", 200, 60))
pop <- data.frame(cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = c("bulls", "heifers", "bulls", "heifers"),
                  year = c(2022, 2022, 2021, 2021), N = c(100, 250, 90, 180), DE = c(55, 60, NA, NA), stringsAsFactors = FALSE)
src <- list(numbers = c(100, 200, 55, 60), families = character(0), family_values = list(),
            year_sums = list(`2022` = c(300, 999), `2021` = c(270)))
iss <- translator_consistency_checks(ps, NULL, source = src, population = pop, inventory_year = 2022)
c7 <- iss[grepl("heifers / N", iss$where), ]
ok(nrow(c7) == 1 && identical(c7$severity, "fail") && grepl("200", c7$issue) && grepl("250", c7$issue), "C7: a time-series value that differs from Parameters for the inventory year fails")
ok(!any(grepl("bulls / N", iss$where)), "C7: an agreeing value is not flagged")
ok(any(iss$where == "year 2022" & iss$severity == "warn" & iss$sheet == "Parameter_TimeSeries" & iss$parameter == "N" & iss$check == "time series totals"),
   "C7: a per-year total absent from the source year columns warns, on the time-series sheet, parameter N")
ok(!any(iss$where == "year 2021"), "C7: a per-year total that matches a source column is silent")
ok(identical(c7$check, "Parameters vs time series") && identical(c7$sheet, "Parameters") && nzchar(c7$group), "C7: the row carries its check name, sheet and group")
# every check names its sheet; the older checks now carry group and parameter too
ps3 <- rbind(ps, grp("calves", 50, 58)); ps3$uncertainty_pct[ps3$parameter == "DE" & ps3$sub_category == "calves"] <- 0.5
iss3 <- translator_consistency_checks(ps3, NULL, source = src)
u <- iss3[iss3$check %in% "uncertainty scale", ]
ok(nrow(u) == 1 && identical(u$sheet, "Parameters") && identical(u$group, "non_dairy||lvl||calves") && identical(u$parameter, "DE"),
   "uncertainty-scale check: sheet, group and parameter on the row")
ok(all(!is.na(iss3$sheet) & nzchar(iss3$sheet)) && all(!is.na(iss3$check) & nzchar(iss3$check)), "every issue names its sheet and its check")
nf <- iss3[iss3$check %in% "value not in file", ]
ok(nrow(nf) >= 2 && all(nzchar(nf$group)) && all(nzchar(nf$parameter)), "values not found in the file: one row per cell, with its group and parameter")
# C8
ps8 <- ps; ps8$mean[ps8$parameter == "DE" & ps8$sub_category == "bulls"] <- 0.55
ps8$mean[ps8$parameter == "pct_pregnant" & ps8$sub_category == "heifers"] <- 52
iss8 <- translator_consistency_checks(ps8, NULL, source = src)
ok(sum(iss8$severity == "fail" & grepl("looks like a fraction", iss8$issue)) == 1 && sum(iss8$severity == "fail" & grepl("looks like a percentage", iss8$issue)) == 1,
   "C8: DE 0.55 and pct_pregnant 52 are both unit failures")
mm8 <- data.frame(cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = "bulls", mms_type = "pasture",
                  fraction_pct = 100, MCF_pct = 0.02, EF3 = 2, Frac_GasMS_pct = 20, Frac_LeachMS_pct = 5, stringsAsFactors = FALSE)
iss8m <- translator_consistency_checks(ps, mm8, source = src)
ok(any(iss8m$parameter == "MCF_pct" & iss8m$severity == "warn") && any(iss8m$parameter == "EF3" & iss8m$severity == "fail"), "C8: MCF 0.02 warns, EF3 2 fails")
ok(all(c("sheet", "group", "parameter") %in% names(iss8m)) && all(iss8m$sheet[iss8m$parameter == "EF3"] == "Manure_Management"), "issues carry sheet, group and parameter")
# C9
piece <- list(parameters = data.frame(cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = "bulls",
                                      parameter = c("BW", "Ym"), mean = c(300, 6.5), uncertainty_pct = c(NA, 20),
                                      lower = NA, upper = NA, distribution = c(NA, "pert"), data_source = "user_file", stringsAsFactors = FALSE),
              manure_management = data.frame(cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = "bulls",
                                             mms_type = "pasture", fraction_pct = 100, MCF_pct = 1.5, EF3 = 0.02, stringsAsFactors = FALSE))
d9 <- .translator_defaults_applied(piece)
ok(nrow(d9) == 3 && any(grepl("BW", d9$where) & grepl("range and distribution", d9$issue)) && any(grepl("MCF_pct", d9$where)) && any(grepl("EF3", d9$where)),
   "C9: a value without a range or distribution, and manure coefficients without ranges, are listed")
iss9 <- translator_consistency_checks(ps, NULL, source = src, piece = piece)
ok(sum(iss9$severity == "info" & grepl("was applied", iss9$issue)) == 3, "C9 rows join the issues as info")

# ---- the source fingerprint and the label scan (2026-10-23) -----------------------------
pop_sheet <- data.frame(Description = c("Total cattle", "cows", "bulls", "ALL DAIRY", "notes"), `1990` = c(300, 100, 200, 300, NA), `1991` = c(330, 110, 220, 330, NA),
                        check.names = FALSE, stringsAsFactors = FALSE)
notes_sheet <- data.frame(a = c("Missing country-specific values:", "ASH", "UE", "Tw"), b = c(NA, "not available", NA, NA), stringsAsFactors = FALSE)
data_sheet <- data.frame(parameter = c("DE", "Ym"), value = c(60, 6.5), stringsAsFactors = FALSE)
fp <- translator_source_fingerprint(list(sheets = list(list(name = "pop", preview = pop_sheet), list(name = "notes", preview = notes_sheet), list(name = "data", preview = data_sheet))))
ok(all(c(300, 900) %in% fp$year_sums[["1990"]]) && 330 %in% fp$year_sums[["1991"]],
   "a year column gives the herd (rows not labelled total, and the total row itself) as well as the whole column")
ok(all(c("DE", "Ym") %in% fp$families) && !any(c("ASH", "UE", "Tw") %in% fp$families),
   "a parameter named on a row without a number (the notes sheet) is not reported as present")
pop2 <- data.frame(cattle_type = "non_dairy", aggregation_level = "lvl", sub_category = c("bulls", "heifers"), year = c(1990, 1990), N = c(100, 200), stringsAsFactors = FALSE)
iss_fp <- translator_consistency_checks(ps, NULL, source = fp, population = pop2, inventory_year = 2022)
ok(!any(iss_fp$check %in% "time series totals"), "a template whose year total equals the source's sub-category rows is not flagged")
mm_ct <- data.frame(cattle_type = c("dairy", "dairy", "non_dairy", "non_dairy"), aggregation_level = "lvl", sub_category = c("dairy_cows", "heifers", "bulls", "steers"),
                    mms_type = "pasture", fraction_pct = 100, MCF_pct = c(1, 1, 2, 2), EF3 = 0.02, Frac_GasMS_pct = c(30, 30, 45, 45), Frac_LeachMS_pct = 5, stringsAsFactors = FALSE)
iss_mm <- translator_consistency_checks(ps, mm_ct, source = src)
ok(!any(iss_mm$check %in% "manure coefficient consistency"), "dairy and other cattle may carry different coefficients for the same manure system")
mm_ct$Frac_GasMS_pct[2] <- 40
iss_mm2 <- translator_consistency_checks(ps, mm_ct, source = src)
ok(sum(iss_mm2$check %in% "manure coefficient consistency") == 1 && grepl("(dairy)", iss_mm2$issue[iss_mm2$check %in% "manure coefficient consistency"], fixed = TRUE),
   "two values within one cattle type are still flagged, naming the cattle type")

# ---- the uncertainty-scale correction (2026-10-23) -------------------------------------
pz <- list(parameters = rbind(grp("bulls", 100, 55), grp("heifers", 200, 60), grp("calves", 50, 58)),
           manure_management = data.frame(), inventory_metadata = list(country = "Z", year = 2024L))
pz$parameters$uncertainty_pct[pz$parameters$parameter == "N" & pz$parameters$sub_category == "bulls"] <- 0.5      # a fraction: 50 %
pz$parameters$uncertainty_pct[pz$parameters$parameter == "DE" & pz$parameters$sub_category == "calves"] <- 0.2     # a fraction: 20 %
pz$parameters$uncertainty_pct[pz$parameters$parameter == "Ym" & pz$parameters$sub_category == "heifers"] <- 0.3    # with bounds: left alone
pz$parameters$lower[pz$parameters$parameter == "Ym" & pz$parameters$sub_category == "heifers"] <- 5
pz$parameters$upper[pz$parameters$parameter == "Ym" & pz$parameters$sub_category == "heifers"] <- 8
fz <- .translator_fix_uncertainty_scale(pz)
gu <- function(p, sc) fz$parameters$uncertainty_pct[fz$parameters$parameter == p & fz$parameters$sub_category == sc]
ok(gu("N", "bulls") == 50 && gu("DE", "calves") == 20 && gu("Ym", "heifers") == 0.3 && gu("N", "heifers") == 10,
   "0.5 and 0.2 become 50 and 20 (catalogue says percent); a row with bounds and the normal rows are untouched")
ok(is.data.frame(fz$server_corrections) && nrow(fz$server_corrections) == 2 && all(fz$server_corrections$check == "uncertainty scale (corrected)") &&
   all(grepl("Read as", fz$server_corrections$issue)), "two corrections listed with the reason")
isz <- translator_consistency_checks(fz$parameters, NULL, source = src, piece = fz)
ok(sum(isz$check == "uncertainty scale (corrected)" & isz$severity == "warn") == 2 && !any(isz$check == "uncertainty scale"),
   "the corrections reach the checks as warnings and the scale warning no longer fires")
jz <- as.character(jsonlite::toJSON(pz, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows"))
jz2 <- .translator_fix_piece_json(jz)
ok(!identical(jz, jz2) && identical(.translator_fix_piece_json(jz2), jz2) &&
   jsonlite::fromJSON(jz2, simplifyVector = TRUE)$parameters$uncertainty_pct[1] == 50, "the JSON round trip applies the fix once and is then stable")
ok(identical(.translator_fix_piece_json(as.character(jsonlite::toJSON(list(parameters = grp("bulls", 100, 55)), auto_unbox = TRUE, dataframe = "rows"))),
             as.character(jsonlite::toJSON(list(parameters = grp("bulls", 100, 55)), auto_unbox = TRUE, dataframe = "rows"))), "nothing to fix: the same text back")

# ---- file names -----------------------------------------------------------------------
p2 <- list(inventory_metadata = list(country = "Costa Rica", year = 2022L))
fn <- translator_output_filename(p2, "template", stamp = as.POSIXct("2026-10-22 15:30:00"))
ok(identical(fn, "Costa_Rica_2022_cattle_uncertainty_template_2026-10-22_1530.xlsx"), "template file name")
ok(grepl("_translation_checks_.*xlsx$", translator_output_filename(p2, "checks")) && grepl("_translation_conversation_.*docx$", translator_output_filename(p2, "conversation")), "checks and conversation names")
ok(grepl("^inventory_", translator_output_filename(list(), "template")), "no metadata: a safe fallback name")

# ---- checks workbook ------------------------------------------------------------------
pc <- list(issues = iss8m, qa = data.frame(group = "bulls", parameter = "BW", check = "benchmark_deviation", status = "warn",
                                           message = "BW far from the IPCC default", level = NA, stringsAsFactors = FALSE),
           summary = NULL, n_params = 8L, n_manure = 1L, error = NULL)
reg <- translator_register_set_user(list(), "calves_handling", "pooled")
f_chk <- file.path(td, "checks.xlsx")
translator_write_checks_xlsx(pc, reg, f_chk, extra = list(model = "stub", prompt_hash = "abc", register_digest = "d1"))
sh <- readxl::excel_sheets(f_chk)
ok(identical(sh, c("Checks", "Decisions", "Summary")), "checks workbook has the three sheets")
ck <- readxl::read_excel(f_chk, "Checks")
ok(nrow(ck) == nrow(iss8m) + 1 && identical(ck$Severity[1], "fail") && "Your decision" %in% names(ck), "checks sheet: every row, fail first, a decision column")
ok(all(!is.na(ck$Sheet) & nzchar(ck$Sheet)) && !any(grepl(" / ", ck$Check)) && all(!is.na(ck$Check)), "checks sheet: Sheet filled on every row, Check is a name, never a location")
ok(sum(is.na(ck$Group)) <= sum(ck$Check %in% c("manure coefficient consistency", "manure bounds", "manure bounds missing", "default replaced file value", "category coverage")),
   "checks sheet: Group blank only for checks that span groups")
dc <- readxl::read_excel(f_chk, "Decisions"); ok(nrow(dc) == 1 && dc$Topic[1] == "calves_handling", "decisions sheet")
wbc <- openxlsx::loadWorkbook(f_chk); ok(!is.null(wbc$worksheets[[1]]$autoFilter) && nzchar(wbc$worksheets[[1]]$autoFilter), "checks sheet has an autofilter")

# ---- conversation document ------------------------------------------------------------
msgs <- list(list(role = "user", content = "UPLOADED FILE x", display = "Uploaded x.xlsx", source = "server_upload", ts = "2026-10-22T10:00:00Z"),
             list(role = "assistant", content = "Before I produce:\n\n1. Which year?\n\n```decisions\n[]\n```", display = "1. Which year?", ts = "2026-10-22T10:01:00Z"),
             list(role = "user", content = "2022", display = "2022", ts = "2026-10-22T10:02:00Z"),
             list(role = "assistant", content = "(prompt changed notice)", display = "notice", source = "server_notice"))
f_doc <- file.path(td, "conv.docx")
translator_write_conversation_docx(msgs, f_doc)
xml <- paste(readLines(unz(f_doc, "word/document.xml"), warn = FALSE), collapse = "")
ok(grepl("Conversation started 2026-10-22 10:00:00 UTC", xml, fixed = TRUE), "document starts with the start time")
ok(grepl("1D4ED8", xml, fixed = TRUE) && grepl("166534", xml, fixed = TRUE) && grepl('w:sz w:val="20"', xml, fixed = TRUE), "two colours, size 10")
ok(!grepl("decisions", xml, fixed = TRUE) && !grepl("notice", xml, fixed = TRUE) && grepl("Which year?", xml, fixed = TRUE) && grepl(">2022<", xml, fixed = TRUE), "questions and answers only")

# ---- annotation on a written template -------------------------------------------------
f_tpl <- file.path(td, "tpl.xlsx")
generate_template_openxlsx(f_tpl, include_example = TRUE)
pu0 <- suppressMessages(parse_uploaded_template(f_tpl))
one <- pu0$param_specs[1, ]
iss_a <- data.frame(where = "x", issue = "flag me", severity = "fail", sheet = "Parameters",
                    group = paste(one$cattle_type, one$aggregation_level, one$sub_category, sep = "||"),
                    parameter = one$parameter, check = "unit test", stringsAsFactors = FALSE)
two <- pu0$param_specs[2, ]
qa_a <- data.frame(group = paste(two$cattle_type, two$sub_category, sep = " / "), parameter = two$parameter,
                   check = "benchmark_deviation", status = "warn", message = "far from the default",
                   level = two$aggregation_level, stringsAsFactors = FALSE)
ts0 <- tryCatch(openxlsx::read.xlsx(f_tpl, sheet = "Parameter_TimeSeries", startRow = 2), error = function(e) NULL)
yr_a <- if (!is.null(ts0) && "year" %in% names(ts0) && any(!is.na(ts0$year))) as.character(ts0$year[!is.na(ts0$year)][1]) else NULL
if (!is.null(yr_a)) iss_a <- rbind(iss_a, data.frame(where = paste("year", yr_a), issue = "total off", severity = "warn", sheet = "Parameter_TimeSeries",
                                                       group = NA_character_, parameter = "N", check = "time series totals", stringsAsFactors = FALSE))
ok(isTRUE(.translator_annotate_workbook(f_tpl, iss_a, qa_a)), "annotation runs on the example template")
wba <- openxlsx::loadWorkbook(f_tpl)
pidx <- match("Parameters", names(wba))
ok(!is.null(wba$worksheets[[pidx]]$autoFilter) && nzchar(wba$worksheets[[pidx]]$autoFilter), "Parameters has an autofilter")
hdr <- openxlsx::read.xlsx(f_tpl, sheet = "Parameters", startRow = 3, colNames = TRUE)
ok(all(c("Check", "Why") %in% names(hdr)) && any(hdr$Check == "fail", na.rm = TRUE) && any(grepl("flag me", hdr$Why)), "Check and Why columns written")
ok(any(hdr$Check == "warn" & hdr$parameter == two$parameter & hdr$sub_category == two$sub_category, na.rm = TRUE) && any(grepl("far from the default", hdr$Why)),
   "a QA/QC row (cattle_type / sub_category + level) lands on its Parameters row")
if (!is.null(yr_a)) {
  ts1 <- openxlsx::read.xlsx(f_tpl, sheet = "Parameter_TimeSeries", startRow = 2)
  ok(all(ts1$Check[!is.na(ts1$year) & as.character(ts1$year) == yr_a] == "warn"), "a time-series total flag lands on every row of that year")
}
pu1 <- suppressMessages(parse_uploaded_template(f_tpl))
ok(nrow(pu1$param_specs) == nrow(pu0$param_specs) && identical(pu1$param_specs$mean, pu0$param_specs$mean), "the annotated workbook still parses identically")
cat("OUTPUT TESTS PASSED\n")
