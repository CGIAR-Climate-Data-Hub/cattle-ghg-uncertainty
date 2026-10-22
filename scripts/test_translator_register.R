# Usage: Rscript scripts/test_translator_register.R   (no API call, about 30 s)
# Unit tests for R/translator_register.R: the decisions block parser, the
# register's merge precedence, the binding block, the question list and
# the upload-time percent/fraction scan.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }

# ---- extraction fixtures ----------------------------------------------------
block <- paste0("```decisions\n[{\"topic\": \"inventory_year\", \"decision\": \"2022\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"year 2022\"},",
                " {\"topic\": \"Calves Handling\", \"decision\": \"pooled\", \"basis\": \"file\", \"confidence\": \"low\"}]\n```")
r1 <- paste0("Confirmed. Before I produce, please answer:\n\n1. Which region is the herd in?\n2. Is the MoE column a fraction?\n\n", block)
d1 <- .translator_extract_decisions(r1)
ok(length(d1) == 2 && d1[[1]]$topic == "inventory_year" && d1[[2]]$topic == "calves_handling", "block present: 2 entries, topic normalised")
ok(is.null(.translator_extract_decisions("No block here. 1. A question?")), "block absent: NULL")
ok(is.null(.translator_extract_decisions("```decisions\n[{not json}]\n```")), "malformed block: NULL")
r4 <- paste0(block, "\nMore text.\n", sub("2022", "2023", block, fixed = TRUE))
d4 <- .translator_extract_decisions(r4)
ok(length(d4) == 4 && d4[[3]]$decision == "2023", "two blocks: both read, in order")
r5 <- paste0("Intro.\n", block, "\nThen questions:\n1. Why?\n")
ok(length(.translator_extract_decisions(r5)) == 2, "mid-reply block: found")
ok(!grepl("```decisions", .translator_strip_decisions(r1), fixed = TRUE) && grepl("Which region", .translator_strip_decisions(r1)), "strip keeps the prose, drops the block")

# ---- merge precedence ---------------------------------------------------------
reg <- translator_register_merge(list(), d1, msg_index = 3L)
ok(identical(reg$inventory_year$status, "decided") && identical(reg$calves_handling$status, "unclear"), "low confidence -> unclear")
reg2 <- translator_register_merge(reg, list(list(topic = "inventory_year", decision = "2021", basis = "file", confidence = "high", quote = "")), 5L)
ok(identical(reg2$inventory_year$decision, "2022"), "a file reading never overwrites a user decision")
reg3 <- translator_register_merge(reg, list(list(topic = "calves_handling", decision = "split", basis = "user", confidence = "high", quote = "split them")), 6L)
ok(identical(reg3$calves_handling$decision, "split") && identical(reg3$calves_handling$status, "decided"), "a user answer replaces an unclear file reading")
reg4 <- translator_register_set_user(reg3, "species", "cattle_mixed")
reg4 <- translator_register_add_pending(reg4, "pct_vs_fraction:MoE!moe")
miss <- translator_register_missing(reg4)
ok(all(c("ipcc_edition", "aggregation_level", "mms_split_source", "uncertainty_source", "pct_vs_fraction:MoE!moe") %in% miss) &&
   !any(c("inventory_year", "species", "calves_handling") %in% miss), "missing = undecided required topics + pending entries")
ok(identical(translator_register_keep_user(reg4)$species$basis, "user"), "keep_user keeps user entries")
ok(is.null(translator_register_keep_user(reg)$calves_handling), "keep_user drops file entries")

# ---- block text ---------------------------------------------------------------
b <- translator_register_block(reg3, level = "emergent_dairy")
ok(grepl("BINDING DECISIONS", b, fixed = TRUE) && grepl("inventory_year: 2022 [the user said (\"year 2022\")]", b, fixed = TRUE) &&
   grepl("For this batch ('emergent_dairy')", b, fixed = TRUE), "block lists decisions with their basis and the level")
ok(grepl("UNRESOLVED calves_handling", translator_register_block(reg), fixed = TRUE), "unclear entries are flagged UNRESOLVED")
ok(identical(translator_register_block(list()), ""), "empty register -> empty block")
ok(nchar(translator_register_digest(reg3)) == 12, "digest is 12 chars")
df <- translator_register_df(reg4); ok(nrow(df) == 4 && all(c("topic", "decision", "basis", "status") %in% names(df)), "register as data frame")

# ---- questions ----------------------------------------------------------------
qs <- .translator_question_list("I read your file: 6 sheets.\n\nBefore I can produce, please answer:\n\n1. Year: confirm 2022?\n2. MoE column (e.g. 0.35): read as a\n   fraction?\n3. This is a statement, not a question.\n")
ok(length(qs) == 2 && grepl("^Year: confirm 2022\\?$", qs[1]) && grepl("fraction\\?$", qs[2]), "question list: numbered items with a question mark, multi-line kept")
ok(length(.translator_question_list("1. Single question?")) == 1, "one question is still a question")
st <- .translator_strip_question_blocks("Intro line.\n\n1. Year: confirm 2022?\n2. MoE column (e.g. 0.35): read as a\n   fraction?\n\nTail.", qs)
ok(grepl("Intro line", st) && grepl("Tail", st) && !grepl("confirm 2022", st) && !grepl("fraction", st), "strip removes the question blocks, keeps the rest")
msg <- .translator_answers_message(list(list(text = "Year: confirm 2022?", answer = "yes, 2022"), list(text = "MoE?", answer = "")))
ok(grepl("1. Year: confirm 2022?", msg, fixed = TRUE) && grepl("Answer: yes, 2022", msg, fixed = TRUE) && grepl("no answer", msg, fixed = TRUE), "answers message")

# ---- percent / fraction scan ---------------------------------------------------
parsed <- list(sheets = list(list(name = "MoE", preview = data.frame(`MoE %` = c(0.35, 0.2, 0.5), `BW kg` = c(300, 310, 290), `Frac share` = c(20, 30, 50), check.names = FALSE))))
conf <- .translator_detect_pct_conflicts(parsed)
ok(identical(sort(conf), sort(c("MoE!MoE %", "MoE!Frac share"))), "percent header with fractional values, and fraction header with values above 1, are flagged")
ok(length(.translator_detect_pct_conflicts(list(sheets = list(list(name = "s", preview = data.frame(`DE %` = c(55, 60, 58), check.names = FALSE)))))) == 0, "a consistent column is not flagged")

# ---- topic helpers --------------------------------------------------------------
ok(grepl("MoE!moe", .translator_topic_question("pct_vs_fraction:MoE!moe"), fixed = TRUE) && grepl("6%", .translator_topic_question("pct_vs_fraction:MoE!moe"), fixed = TRUE), "server question text carries the column and the percent sign")
ok(identical(.translator_topic_choices_for("pct_vs_fraction:x"), c("percent", "fraction")) && is.null(.translator_topic_choices_for("inventory_year")), "choices per topic kind")
# ---- enforcement (WP1 step 4) ----------------------------------------------------
reg_p <- translator_register_set_user(list(), "calves_handling", "pooled")
piece_split <- list(parameters = data.frame(aggregation_level = "lvl", sub_category = c("calves_male", "calves_female", "bulls"),
                                            parameter = "N", mean = c(50, 50, 10), stringsAsFactors = FALSE))
piece_pooled <- list(parameters = data.frame(aggregation_level = "lvl", sub_category = c("calves", "bulls"),
                                             parameter = "N", mean = c(100, 10), stringsAsFactors = FALSE))
chk <- translator_register_check(reg_p, piece_split, "lvl")
ok(nrow(chk) == 1 && !chk$ok && chk$hard && chk$topic == "calves_handling", "pooled decision vs both calves halves: hard violation")
ok(all(translator_register_check(reg_p, piece_pooled, "lvl")$ok), "pooled decision vs one calves category: ok")
reg_s <- translator_register_set_user(list(), "calves_handling", "split_as_in_file")
ok(nrow(translator_register_check(reg_s, piece_split, "lvl")) == 0, "split decision: nothing to check")
reg_m <- translator_register_set_user(list(), "mms_split_source", "herd_wide_from_file")
mm_same <- list(manure_management = data.frame(aggregation_level = "lvl", sub_category = c("a", "a", "b", "b"), mms_type = c("pasture", "solid", "pasture", "solid"), fraction_pct = c(80, 20, 80, 20), stringsAsFactors = FALSE))
mm_diff <- mm_same; mm_diff$manure_management$fraction_pct <- c(80, 20, 60, 40)
ok(all(translator_register_check(reg_m, mm_same, "lvl")$ok) && !all(translator_register_check(reg_m, mm_diff, "lvl")$ok), "herd-wide manure split: identical passes, different fails")
reg_v <- translator_register_set_user(list(), "value:Ym:El Doncello", "6.0")
pv <- list(parameters = data.frame(aggregation_level = "x", sub_category = "el_doncello", parameter = "Ym", mean = 7, stringsAsFactors = FALSE))
ok(!translator_register_check(reg_v, pv, "x")$ok, "numeric decision vs a different emitted value: violation")
pv$parameters$mean <- 6.01; ok(translator_register_check(reg_v, pv, "x")$ok, "numeric decision within 0.5%: ok")
rj <- .translator_decision_rejection(chk, "lvl"); ok(grepl("REJECTED for 'lvl'", rj, fixed = TRUE) && grepl("calves_handling", rj, fixed = TRUE), "rejection message")
reg_md <- translator_register_set_user(translator_register_set_user(translator_register_set_user(list(), "inventory_year", "2022"), "species", "cattle_mixed"), "ipcc_edition", "2019_refinement")
fx <- translator_register_apply_metadata(reg_md, list(year = 2021L, species = "cattle_dairy", ipcc_version = "2006"))
ok(identical(fx$metadata$year, 2022L) && identical(fx$metadata$species, "cattle_mixed") && identical(fx$metadata$ipcc_version, "2019_refinement") &&
   setequal(fx$corrections, c("inventory_year", "species", "ipcc_edition")) && isTRUE(fx$register$inventory_year$applied), "metadata corrected from the register and marked applied")
# source categories
sc_reply <- paste0("I read your file.\n\n```source_categories\n[{\"label\": \"Dairy cows\", \"system\": \"Commercial\", \"sub_category\": \"dairy_cows\", \"aggregation_level\": \"commercial_dairy\", \"confidence\": \"high\"},",
                   " {\"label\": \"Young stock\", \"system\": \"Commercial\", \"sub_category\": \"heifers\", \"aggregation_level\": \"commercial_dairy\", \"confidence\": \"low\"}]\n```")
srcs <- .translator_extract_source_categories(sc_reply)
ok(length(srcs) == 2 && srcs[[2]]$confidence == "low" && srcs[[1]]$label == "Dairy cows", "source categories block parsed")
ok(!grepl("source_categories", .translator_strip_source_categories(sc_reply), fixed = TRUE), "source categories block stripped")
ps6 <- data.frame(cattle_type = "dairy", aggregation_level = "commercial_dairy", sub_category = c("dairy_cows", "dairy_cows"), parameter = c("N", "BW"), mean = c(100, 300), stringsAsFactors = FALSE)
iss <- translator_consistency_checks(ps6, NULL, source = list(numbers = c(100, 300), families = character(0), family_values = list(), source_categories = srcs, register = list()))
c6 <- iss[iss$where == "category coverage", ]
ok(nrow(c6) == 1 && identical(c6$severity, "fail") && grepl("Young stock", c6$issue, fixed = TRUE), "C6: a source category missing from the template is a failure")
reg_ok <- translator_register_set_user(list(), "category:Young stock", "merge into Dairy cows")
srcs2 <- srcs; srcs2[[2]]$merge_into <- "Dairy cows"
iss2 <- translator_consistency_checks(ps6, NULL, source = list(numbers = c(100, 300), families = character(0), family_values = list(), source_categories = srcs2, register = reg_ok))
ok(identical(iss2$severity[iss2$where == "category coverage"], "info"), "C6: a merge the user confirmed is accepted")
ok(identical(resolve_subcat_default("calves", "Milk")$data_source, "biological_zero") && resolve_subcat_default("calves", "BW")$value == 60, "pooled calves resolve biological zeros and their own defaults")
cat("REGISTER TESTS PASSED\n")
