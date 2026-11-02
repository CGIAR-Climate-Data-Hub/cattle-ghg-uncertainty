# Usage: Rscript scripts/test_translator_source_values.R   (no API call, about 30 s)
#
# Stage 3 of the 31 October plan: the source_values block (section B as a
# verifiable JSON block), its extractor, the server check of every entry
# against the uploaded sheets, the per-system rows for the batch nudge and
# the sub-category check. The real test-inventory file (gitignored) is used when it
# is present; the synthetic part runs everywhere.
suppressMessages({for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
n_ok <- 0L; n_bad <- 0L
ok <- function(cond, what) { if (isTRUE(cond)) { n_ok <<- n_ok + 1L; cat("PASS", what, "\n") } else { n_bad <<- n_bad + 1L; cat("FAIL", what, "\n"); stop(what) } }

# ---- the extractor ---------------------------------------------------------------
blk <- function(body) paste0("I read your file.\n\n### B. Inventory of values found\nsource_values: 2 entries\n```source_values\n", body, "\n```\n\n### D. Ambiguities to ask the user\n\n1. Which year?")
good <- '[{"system": "Sys A", "label": "Cows", "section": "Weight (kg)", "sheet": "Data", "row": 5, "col": "2020", "mean": 410, "lower": null, "upper": null, "unit": "kg", "distribution": null, "year_col": "2020", "parameter": "BW", "sub_category": "other_cows", "aggregation_level": "sys_a"},\n {"system": "Sys A", "label": "Cows", "section": "Mature weight (kg)", "sheet": "Data", "row": 9, "col": "2020", "mean": 450, "parameter": "MW", "sub_category": "other_cows", "aggregation_level": "sys_a"}]'
ev <- .translator_extract_source_values(blk(good))
ok(length(ev) == 2L && ev[[1]]$parameter == "BW" && ev[[1]]$row == 5L && ev[[2]]$mean == 450 && ev[[1]]$section == "Weight (kg)", "extractor reads the block")
cut <- '[{"system": "Sys A", "label": "Cows", "section": "Weight (kg)", "sheet": "Data", "row": 5, "col": "2020", "mean": 410, "parameter": "BW", "sub_category": "other_cows", "aggregation_level": "sys_a"},\n {"system": "Sys A", "label": "Bulls", "sheet": "Data", "row": 6, "co'
ok(length(.translator_extract_source_values(blk(cut))) == 1L, "a block cut at the output limit keeps its complete entries")
two <- paste0(blk(good), "\n\n```source_values\n[{\"system\": \"Sys B\", \"label\": \"Cows\", \"sheet\": \"Data\", \"row\": 20, \"mean\": 1, \"parameter\": \"N\", \"aggregation_level\": \"sys_b\"}]\n```")
ok(length(.translator_extract_source_values(two)) == 3L, "two blocks (a continuation) are concatenated")
ok(is.null(.translator_extract_source_values("no block here")), "no block gives NULL")
vis <- .translator_strip_source_values(blk(good))
ok(!grepl("```source_values", vis, fixed = TRUE) && grepl("### D.", vis, fixed = TRUE), "the block is stripped from the display, section D stays")
# while section B streams (no section D yet) the live view counts the entries
mid <- sub("\n\n### D[.].*$", "", blk(good))
live <- .translator_reply_visible(mid, live = TRUE)
ok(grepl("\\b2\\b", live) && !grepl("source_values", live, fixed = TRUE), "the live view counts the entries and hides the block")

# ---- the compact form (2026-11-01): one object per group, positional value rows ----
grp <- paste0('[{"system": "Sys A", "label": "Cows", "sub_category": "other_cows", "aggregation_level": "sys_a", "values": [\n',
              '["BW", "Data", 5, "2020", "Weight (kg)", 410, null, null, "kg", null],\n',
              '["MW", "Data", 9, "2020", "Mature weight (kg)", 450, 430, 470, "kg", "normal", "Margins", 3]\n',
              ']},\n{"system": "Sys B", "label": "Cows", "sub_category": "other_cows", "aggregation_level": "sys_b", "values": [\n',
              '["N", "Data", 20, "2020", "Animal numbers", 1, null, null, "head", null]\n]}]')
ev <- .translator_extract_source_values(blk(grp))
ok(length(ev) == 3L && ev[[1]]$system == "Sys A" && ev[[1]]$label == "Cows" && ev[[1]]$sub_category == "other_cows" &&
   ev[[1]]$aggregation_level == "sys_a" && ev[[1]]$parameter == "BW" && ev[[1]]$sheet == "Data" && ev[[1]]$row == 5L &&
   ev[[1]]$col == "2020" && ev[[1]]$section == "Weight (kg)" && ev[[1]]$mean == 410 && is.na(ev[[1]]$lower) && ev[[1]]$unit == "kg",
   "compact form: a value row carries its group's labels and codes")
ok(ev[[2]]$lower == 430 && ev[[2]]$upper == 470 && ev[[2]]$distribution == "normal" && ev[[2]]$bounds_sheet == "Margins" && ev[[2]]$bounds_row == 3L,
   "compact form: bounds, distribution and the bounds sheet")
ok(ev[[3]]$aggregation_level == "sys_b" && ev[[3]]$parameter == "N", "compact form: the second group")
# cut at the output limit: no closing fence, cut inside a value row of the second group
cut2 <- paste0("I read your file.\n\n### B. Inventory of values found\nsource_values: 3 entries\n```source_values\n",
               sub('\\["N", "Data", 20.*$', '["N", "Data", 20, "20', grp))
ev <- .translator_extract_source_values(cut2)
ok(length(ev) == 2L && ev[[2]]$parameter == "MW", "compact form: a block cut inside a value row, without a closing fence, keeps the complete rows")
cut3 <- sub("\n\\]\\},\n.*$", "\n]},\n", grp)   # cut right after the first group closed
ok(length(.translator_extract_source_values(blk(cut3))) == 2L, "compact form: a block cut between two groups keeps the first")
cut_flat <- paste0("I read your file.\n\n### B. Inventory of values found\n```source_values\n", cut)   # the flat form, cut, no closing fence
ok(length(.translator_extract_source_values(cut_flat)) == 1L, "flat form: a cut block without a closing fence keeps its complete entries")
live2 <- .translator_reply_visible(sub("\n\n### D[.].*$", "", blk(grp)), live = TRUE)
ok(grepl("\\b3\\b", live2) && !grepl("source_values", live2, fixed = TRUE), "the live view counts the value rows of the compact form")
# a continuation's block is appended to the cut block, a restarted row counted once
merged <- .translator_merge_source_values(.translator_extract_source_values(cut2), .translator_extract_source_values(blk(grp))[2:3])
ok(length(merged) == 3L && merged[[3]]$parameter == "N", "the continuation's rows are appended; a row written twice is kept once")
ok(is.null(.translator_merge_source_values(NULL, NULL)), "merging nothing gives NULL")

# ---- the loosened label rules (2026-11-01) -----------------------------------------
# rows that cover several groups, rows under no heading, singular/plural and spacing
df2 <- data.frame(a = c("Dairy cattle", "Cows", "Heifer (1 - 3 years)", "Oxen (> 3 years)", NA,
                        "Coefficients for growth (_C)", "All production systems", "Growing males", NA,
                        "Sys A", "Methane conversion (Ym)", "all categories except calves", "Adult bulls, heifers and growing males", "Cows"),
                  v = c(NA, 100, 200, 300, NA, NA, NA, 1.2, NA, NA, NA, 6.5, 7, 55), check.names = FALSE, stringsAsFactors = FALSE)
# a sheet whose first data row sits under no heading (the test-inventory population rows)
df3 <- data.frame(Description = c("Dairy cattle", "Dairy cattle"), b = c("Cows", "Bulls"), v = c(100, 110), check.names = FALSE, stringsAsFactors = FALSE)
sh2 <- list(list(name = "Data", json = .translator_table_to_json(df2, "Data"), n_rows = nrow(df2)),
            list(name = "Pop", json = .translator_table_to_json(df3, "Pop"), n_rows = nrow(df3)))
l_nosec <- list(system = "Dairy", label = "Cows", section = "Dairy cattle", sheet = "Pop", row = 2L, col = "v", mean = 100, parameter = "N")
l_plur  <- list(system = "Dairy", label = "Heifers (1 - 3 years)", section = "Dairy cattle", sheet = "Data", row = 4L, col = "v", mean = 200, parameter = "N")
l_space <- list(system = "Dairy", label = "Oxen (>3 years)", section = "Dairy cattle", sheet = "Data", row = 5L, col = "v", mean = 300, parameter = "N")
l_allsys <- list(system = "Commercial beef farms", label = "Growing males", section = "All production systems", sheet = "Data", row = 9L, col = "v", mean = 1.2, parameter = "C")
l_allcat <- list(system = "Sys A", label = "Adult cows (>3 years)", section = "Methane conversion (Ym)", sheet = "Data", row = 13L, col = "v", mean = 6.5, parameter = "Ym")
l_except <- modifyList(l_allcat, list(label = "Calves (0 - 1 year)"))
l_multi  <- list(system = "Sys A", label = "Heifers (1 - 3 years)", section = "Methane conversion (Ym)", sheet = "Data", row = 14L, col = "v", mean = 7, parameter = "Ym")
l_multi_cows <- modifyList(l_multi, list(label = "Adult cows (>3 years)"))
l_wrongsec <- list(system = "Sys A", label = "Cows", section = "Weight (kg)", sheet = "Data", row = 15L, col = "v", mean = 55, parameter = "BW")
c2 <- translator_source_values_check(list(l_nosec, l_plur, l_space, l_allsys, l_allcat, l_except, l_multi, l_multi_cows, l_wrongsec), sh2)
ok(isTRUE(c2$ok[1]), "a row under no heading accepts the entry's section")
ok(isTRUE(c2$ok[2]), "'Heifers' matches the file's 'Heifer'")
ok(isTRUE(c2$ok[3]), "'Oxen (>3 years)' matches 'Oxen (> 3 years)'")
ok(isTRUE(c2$ok[4]), "a system is accepted on an 'All production systems' row")
ok(isTRUE(c2$ok[5]), "a label is accepted on an 'all categories except calves' row")
ok(!isTRUE(c2$ok[6]) && grepl("label", c2$what[6]), "a calves label is refused on an 'all categories except calves' row")
ok(isTRUE(c2$ok[7]), "'Heifers' is accepted on 'Adult bulls, heifers and growing males'")
ok(!isTRUE(c2$ok[8]) && grepl("label", c2$what[8]), "'Adult cows' is refused on 'Adult bulls, heifers and growing males'")
ok(!isTRUE(c2$ok[9]) && grepl("section", c2$what[9]), "a row under a heading still has to name it")

# ---- the year check (2026-11-01) ---------------------------------------------------
reg24 <- translator_register_set_user(list(), "inventory_year", "2024")
tab22 <- list(list(sheet = "Data", row = 3L, col = "2022", parameter = "N"), list(sheet = "Data", row = 4L, col = "2022", parameter = "N"),
              list(sheet = "Coefficients", row = 9L, col = "value", parameter = "C"))
yf <- .translator_year_fix_message(reg24, tab22)
ok(!is.null(yf) && yf$year == "2024" && yf$table_year == "2022" && grepl("^YEAR CHECK: your source_values block reads 2 of its values from the 2022 column", yf$text),
   "a table on 2022 with the year decided 2024 gets the re-emit request")
ok(is.null(.translator_year_fix_message(translator_register_set_user(list(), "inventory_year", "the 2022 column"), tab22)), "same year: nothing to do")
ok(is.null(.translator_year_fix_message(reg24, tab22[3])), "no year column in the table: nothing to do")
ok(is.null(.translator_year_fix_message(translator_register_add_pending(list(), "inventory_year"), tab22)), "year still pending: nothing to do")

# ---- the check on synthetic sheets ------------------------------------------------
# the layout of the test-inventory sheets: the system label above the block heading
df <- data.frame(a = c("Sys A", "Weight (kg)", "Cows", "Bulls", NA, "Sys A", "Mature weight (kg)", "Cows", "Bulls"),
                 `2019` = c(NA, NA, 400, 500, NA, NA, NA, 440, 540),
                 `2020` = c(NA, NA, 410, 510, NA, NA, NA, 450, 550), check.names = FALSE, stringsAsFactors = FALSE)
sheets <- list(list(name = "Data", json = .translator_table_to_json(df, "Data"), n_rows = nrow(df)))
e_ok  <- list(system = "Sys A", label = "Cows", section = "Weight (kg)", sheet = "Data", row = 4L, col = "2020", mean = 410, parameter = "BW")
e_row <- modifyList(e_ok, list(row = 9L, mean = 450))                    # the MW row read as BW (section differs)
e_sec <- modifyList(e_ok, list(section = "Mature weight (kg)"))           # right row, wrong heading
e_sys <- modifyList(e_ok, list(system = "Sys Z"))                         # a system label not near the row
e_val <- modifyList(e_ok, list(mean = 999))                               # a number not on the row
e_col <- modifyList(e_ok, list(col = "2019"))                             # the mean sits in another column
e_let <- modifyList(e_ok, list(col = "C"))                                # Excel letter for the 2020 column
e_cap <- modifyList(e_ok, list(row = 1200L))
chk <- translator_source_values_check(list(e_ok, e_row, e_sec, e_sys, e_val, e_col, e_let, e_cap), sheets)
ok(nrow(chk) == 8L && chk$ok[1] && chk$ok[7], "a right entry passes, also with an Excel column letter")
ok(!chk$ok[2] && grepl("section", chk$what[2]), "the MW row offered as BW fails on the section")
ok(!chk$ok[3] && grepl("section", chk$what[3]), "a wrong heading fails on the section")
ok(!chk$ok[4] && grepl("system", chk$what[4]), "a system label not near the row fails")
ok(!chk$ok[5] && grepl("mean", chk$what[5]), "a number not on the row fails on the mean")
ok(!chk$ok[6] && grepl("column 2019 holds 400", chk$what[6], fixed = TRUE) && grepl("in column 2020", chk$what[6], fixed = TRUE), "the mean in another column is named")
ok(!chk$ok[8], "a row beyond the sheet fails")
one_sheet <- list(list(name = "Other", json = sheets[[1]]$json, n_rows = nrow(df)))
ok(translator_source_values_check(list(modifyList(e_ok, list(sheet = "whatever"))), one_sheet)$ok, "a one-sheet file matches any sheet name")
msg <- .translator_source_fix_message(chk, list(e_ok, e_row, e_sec, e_sys, e_val, e_col, e_let, e_cap))
ok(grepl("^SOURCE CHECK: 5 entries", msg) && grepl("re-emit the WHOLE", msg), "the corrective message counts the mismatches (the capped row is not the model's fault)")

# ---- per-system rows and the nudge paragraph ------------------------------------------
sv <- list(e_ok, modifyList(e_ok, list(row = 5L, label = "Bulls", mean = 510, sub_category = "bulls")),
           list(system = "Sys A", label = "Cows", section = "Mature weight (kg)", sheet = "Data", row = 9L, col = "2020", mean = 450, parameter = "MW", aggregation_level = "sys_a", sub_category = "other_cows"),
           list(system = "Sys B", label = "Cows", sheet = "Data", row = 30L, mean = 1, parameter = "N", aggregation_level = "sys_b", sub_category = "other_cows"))
sv[[1]]$aggregation_level <- "sys_a"; sv[[1]]$sub_category <- "other_cows"; sv[[2]]$aggregation_level <- "sys_a"
sc <- translator_level_rows("sys_a", sv, NULL, sheets, expected_subcats = c("other_cows", "bulls"))
# rows 4, 5 and 9: the three blank rows between 5 and 9 are a gap the rule
# merges (up to three), so one range
ok(identical(sc$systems, "Sys A") && sc$n_entries == 3L && nrow(sc$ranges) == 1L && sc$ranges$sheet == "Data" &&
   sc$ranges$from == 4L && sc$ranges$to == 9L, "rows per sheet from the entries, gaps merged")
sc_far <- translator_level_rows("sys_a", c(sv, list(list(system = "Sys A", sheet = "Data", row = 40L, mean = 2, parameter = "N", aggregation_level = "sys_a"))), NULL, NULL)
ok(nrow(sc_far$ranges) == 2L && sc_far$ranges$from[2] == 40L, "a row far below opens a second range")
txt <- .translator_scope_text(sc)
ok(grepl("SOURCE ROWS FOR THIS BATCH", txt, fixed = TRUE) && grepl("Data rows 4-9", txt, fixed = TRUE) &&
   grepl("Expected sub-categories (2): other_cows, bulls", txt, fixed = TRUE) && nchar(txt) / 3.6 < 300, "the nudge paragraph names the rows and the sub-categories, under 300 tokens")
sc_b <- translator_level_rows("sys_b", NULL, list(list(label = "Cows", system = "Sys B", sub_category = "other_cows", aggregation_level = "sys_b")), sheets)
ok(identical(sc_b$from, "source_categories") && identical(sc_b$systems, "Sys B") && identical(sc_b$sub_categories, "other_cows"), "without entries the systems and sub-categories come from the source categories")
ok(identical(.translator_scope_text(NULL), ""), "no scope, no paragraph")
piece <- list(parameters = data.frame(sub_category = c("other_cows", "bulls"), parameter = "N", mean = 1, stringsAsFactors = FALSE))
ok(isTRUE(translator_level_subcats_check(piece, sc)$ok), "the expected sub-categories pass")
piece2 <- list(parameters = data.frame(sub_category = c("other_cows", "calves"), parameter = "N", mean = 1, stringsAsFactors = FALSE))
c2 <- translator_level_subcats_check(piece2, sc)
ok(!c2$ok && c2$missing == "bulls" && c2$extra == "calves", "a missing and an extra sub-category are named")
rej <- .translator_subcat_rejection("sys_a", c2)
ok(grepl("^REJECTED for 'sys_a'", rej) && grepl("Missing: bulls", rej, fixed = TRUE) && grepl("the batch carries", rej, fixed = TRUE), "the rejection text")

# ---- the real test-inventory file, when present -------------------------------------------------
zf <- "test_data/inv_a/inv_a_source.xlsx"
if (file.exists(zf)) {
  parsed <- .translator_read_upload_memo(zf, basename(zf))
  zs <- lapply(parsed$sheets, function(s) list(name = s$name, json = s$json, n_rows = s$n_rows))
  csd <- "Country-specific data"; moe <- "MoE or 95%CI"
  z_ok <- list(system = "Commercial beef farms", label = "Feedlot cattle (1 - 3 years)", section = "Weight (kg) (Country specific value)",
               sheet = csd, row = 131L, col = "2022", mean = 333.8, parameter = "BW", sub_category = "feedlot_cattle", aggregation_level = "commercial_beef")
  z_bounds <- modifyList(z_ok, list(lower = 450, upper = 550, bounds_sheet = moe, bounds_row = 162L))   # the MW range on the BW row
  z_row <- modifyList(z_ok, list(row = 139L, mean = 470))                                                # the MW row as BW
  z_sec <- modifyList(z_ok, list(section = "Mature weight (kg) (Country specific value)"))
  z_sys <- list(system = "Extensive/traditional beef farms", label = "Adult cows (>3 years)", section = "Mature weight (kg) (Country specific value)",
                sheet = csd, row = 203L, col = "2022", mean = 366, parameter = "MW", aggregation_level = "extensive_beef")
  z_mw <- list(system = "Commercial beef farms", label = "Feedlot cattle (1 - 3 years)", section = "Mature weight (kg) (Country specific value)",
               sheet = csd, row = 139L, col = "2022", mean = 470, lower = 450, upper = 550, bounds_sheet = moe, bounds_row = 162L, parameter = "MW")
  zc <- translator_source_values_check(list(z_ok, z_bounds, z_row, z_sec, z_sys, z_mw), zs)
  ok(zc$ok[1], "Test inventory: feedlot BW on row 131 passes")
  ok(zc$ok[6], "Test inventory: feedlot MW with the MoE 450 to 550 bounds passes")
  ok(zc$ok[2], "Test inventory: bounds that exist on a MoE row are accepted on the BW entry (the section check is the one that tells BW from MW)")
  ok(!zc$ok[3] && grepl("section", zc$what[3]), "Test inventory: the MW row offered as BW fails on the section")
  ok(!zc$ok[4] && grepl("section", zc$what[4]), "Test inventory: a wrong heading on the right row fails")
  ok(!zc$ok[5] && grepl("system", zc$what[5]), "Test inventory: an emergent-beef row labelled extensive fails on the system")
  sv_z <- list(z_ok, z_mw, modifyList(z_ok, list(row = 126L, label = "Adult cows (>3 years)", mean = 460, sub_category = "other_cows")))
  for (i in seq_along(sv_z)) sv_z[[i]]$aggregation_level <- "commercial_beef"
  scz <- translator_level_rows("commercial_beef", sv_z, NULL, zs, expected_subcats = c("other_cows", "bulls", "heifers", "growing_males", "calves", "feedlot_cattle"))
  ok(identical(scz$systems, "Commercial beef farms") && any(scz$ranges$sheet == moe) && scz$n_expected == 6L, "Test inventory: the scope names the system, the MoE rows and six sub-categories")
  tz <- .translator_scope_text(scz)
  ok(nchar(tz) / 3.6 < 300 && grepl("Expected sub-categories (6)", tz, fixed = TRUE), "Test inventory: the paragraph stays under 300 tokens")
} else cat("(the test inventory file absent: the real-file part was skipped)\n")

cat(sprintf("\n%d passed, %d failed\n", n_ok, n_bad))
if (n_bad == 0L) cat("SOURCE VALUES TESTS PASSED\n")
