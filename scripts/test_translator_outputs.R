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
ok(any(iss$where == "time series / 2022" & iss$severity == "warn"), "C7: a per-year total absent from the source year columns warns")
ok(!any(iss$where == "time series / 2021"), "C7: a per-year total that matches a source column is silent")
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
ok(all(c("sheet", "group", "parameter") %in% names(iss8m)) && identical(iss8m$sheet[which(iss8m$parameter == "EF3")], "Manure_Management"), "issues carry sheet, group and parameter")
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
                    parameter = one$parameter, stringsAsFactors = FALSE)
ok(isTRUE(.translator_annotate_workbook(f_tpl, iss_a, NULL)), "annotation runs on the example template")
wba <- openxlsx::loadWorkbook(f_tpl)
pidx <- match("Parameters", names(wba))
ok(!is.null(wba$worksheets[[pidx]]$autoFilter) && nzchar(wba$worksheets[[pidx]]$autoFilter), "Parameters has an autofilter")
hdr <- openxlsx::read.xlsx(f_tpl, sheet = "Parameters", startRow = 3, colNames = TRUE)
ok(all(c("Check", "Why") %in% names(hdr)) && any(hdr$Check == "fail", na.rm = TRUE) && any(grepl("flag me", hdr$Why)), "Check and Why columns written")
pu1 <- suppressMessages(parse_uploaded_template(f_tpl))
ok(nrow(pu1$param_specs) == nrow(pu0$param_specs) && identical(pu1$param_specs$mean, pu0$param_specs$mean), "the annotated workbook still parses identically")
cat("OUTPUT TESTS PASSED\n")
