# Usage: Rscript scripts/translator_dry_run.R   (needs the gitignored test_data/ZAM/zam2_fixed.xlsx; no API call, about 3 minutes)
#
# End-to-end dry run of the translator pipeline with a stubbed model:
# explore -> clarify -> Produce (enumerate + 5 batches) -> merge -> writer ->
# finalise -> precheck -> download copy, using the corrected Zambia workbook as
# the "model's" answers. No API call is made.
#
# 2026-10-22: rebuilt around the asynchronous client. The translator has run
# through anthropic_chat_stream_async() since a3e2668 (15 October); the old
# harness stubbed the synchronous client, so it made no call at all and
# produced nothing, which is how the batched assembly defect (enum_resp out of
# scope in .translator_emit_finish) stayed unnoticed. The stub now schedules
# its reply through later::later(), exactly as the real transport delivers a
# result, and the script pumps the event loop until the state settles.
#
# Three scenarios, in this order:
#   1. a fresh conversation reaches a written workbook (the batched path, five
#      production systems), and the merged JSON carries the model id;
#   2. Produce again with nothing changed makes no batch call (the validated
#      parts are reused);
#   3. a new answer from the user, then Produce: every batch is re-called,
#      because the parts were validated against a different conversation.
suppressMessages({library(shiny); library(readxl); library(later)})
for (f in sort(list.files("R", pattern = "[.]R$", full.names = TRUE))) suppressMessages(source(f, local = FALSE))
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"), ANTHROPIC_API_KEY = "stub-key")
pu <- suppressMessages(parse_uploaded_template("test_data/ZAM/zam2_fixed.xlsx"))
ps <- pu$param_specs; mn <- pu$manure; ts <- pu$population
levels <- unique(ps$aggregation_level)
num <- function(x) suppressWarnings(as.numeric(x))
rows_json <- function(df) jsonlite::toJSON(df, dataframe = "rows", na = "null", auto_unbox = TRUE, digits = NA)
meta <- list(country = "Zambia", region = "africa", year = 2022L, species = "cattle_mixed",
             ipcc_version = "2019_refinement", prepared_by = "dry run", notes = "stub")
param_cols <- c("cattle_type","aggregation_level","sub_category","parameter","mean","uncertainty_pct","lower","upper","distribution","param_type","data_source")
if (!"param_type" %in% names(ps)) ps$param_type <- "N"
mm_cols <- intersect(c("cattle_type","aggregation_level","sub_category","mms_type","fraction_pct","lower_fraction","upper_fraction","distribution_fraction",
                       "MCF_pct","lower_mcf","upper_mcf","distribution_mcf","EF3","lower_ef3","upper_ef3","distribution_ef3",
                       "Frac_GasMS_pct","lower_frac_gas","upper_frac_gas","distribution_frac_gas","Frac_LeachMS_pct","lower_frac_leach","upper_frac_leach","distribution_frac_leach"), names(mn))
ts_cols <- intersect(c("cattle_type","aggregation_level","sub_category","year","N","BW","MW","WG","Milk","Fat","pct_pregnant","DE","CP","MilkPR"), names(ts))
calls <- character()

# ---- the stub: same answers as before, delivered asynchronously ---------------
.stub_reply <- function(messages, on_chunk) {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
  usage <- list(prompt_tokens = 10L, completion_tokens = 10L, cached_tokens = 100L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L, total_tokens = 120L)
  base <- list(usage = usage, model = "stub", cost_usd = 0, latency_sec = 0.1, error = NULL, cache_ttl = "1h", stopped = FALSE)
  if (grepl("mode = 'enumerate'", last, fixed = TRUE)) {
    calls <<- c(calls, "enumerate")
    reply <- jsonlite::toJSON(list(mode = "enumerate", aggregation_levels = levels, inventory_metadata = meta), auto_unbox = TRUE)
    return(c(list(reply = as.character(reply), tool_used = TRUE), base))
  }
  if (grepl("mode = 'batch'", last, fixed = TRUE)) {
    lv <- levels[vapply(levels, function(l) grepl(paste0("'", l, "'"), last, fixed = TRUE), logical(1))][1]
    rejected <- grepl("REJECTED for", last, fixed = TRUE)
    calls <<- c(calls, paste0(if (rejected) "retry:" else "batch:", lv))
    # 2026-10-22 (WP1): the binding decisions must be the last paragraph of
    # every batch request and name this batch's level.
    if (!rejected)
      stopifnot(grepl("BINDING DECISIONS", last, fixed = TRUE),
                grepl(sprintf("For this batch ('%s')", lv), last, fixed = TRUE),
                grepl("inventory_year: 2022", last, fixed = TRUE))
    nudge_checked <<- nudge_checked + 1L
    # On a decision re-emit (WP1 step 4) the stub honours the pooled-calves
    # decision: the male half is dropped, the female half stands for the
    # pooled group.
    ps_lv <- ps[ps$aggregation_level == lv, param_cols]
    if (rejected) ps_lv <- ps_lv[ps_lv$sub_category != "calves_male", ]
    piece <- sprintf('{"mode":"batch","aggregation_level":"%s","inventory_metadata":%s,"parameters":%s,"manure_management":%s,"parameter_timeseries":%s}',
                     lv, jsonlite::toJSON(meta, auto_unbox = TRUE),
                     rows_json(ps_lv),
                     rows_json(mn[mn$aggregation_level == lv & !is.na(mn$fraction_pct), mm_cols]),
                     rows_json(ts[ts$aggregation_level == lv, ts_cols]))
    return(c(list(reply = piece, tool_used = TRUE), base))
  }
  calls <<- c(calls, "chat")
  # a clarify reply the way rule 11 asks for it: prose, questions, then the
  # decisions block
  # The Zambia ground truth splits calves (the transcript asked for 50/50),
  # so the stub's decision is "split" until the user says otherwise in
  # scenario 3; from then on it is "pooled" and the batches violate it.
  pooled <- grepl("keep calves pooled", last, fixed = TRUE)
  calves_dec <- if (pooled) "pooled: one calves category per system" else "split into calves_male and calves_female, 50/50"
  txt <- paste0("Thanks. Before I can produce, please answer:\n\n1. Which year?\n2. Split calves?\n\n",
                "```decisions\n[{\"topic\": \"inventory_year\", \"decision\": \"2022\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"Year 2022\"},",
                " {\"topic\": \"calves_handling\", \"decision\": \"", calves_dec, "\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"calves\"}]\n```")
  on_chunk(txt)
  c(list(reply = txt, tool_used = FALSE), base)
}
nudge_checked <- 0L
anthropic_chat_stream_async <- function(messages, on_chunk = function(text) {}, on_tick = function(n = 0L) {},
                                        should_stop = function() FALSE, model = "stub", max_tokens = 1,
                                        temperature = 0, timeout_sec = 1, tools = NULL, tool_choice = NULL,
                                        cache_ttl = "auto", on_result = function(res) {}, ...) {
  resp <- .stub_reply(messages, on_chunk)
  on_tick(12L)
  later::later(function() on_result(resp), 0.01)
  invisible(NULL)
}
anthropic_chat_stream <- function(...) stop("the synchronous client must not be called in this dry run")

# ---- state and session stand-ins ---------------------------------------------
state <- new.env()
state$user_email <- "dryrun@local"; state$messages <- list(); state$batch_parts <- list(); state$batch_parts_key <- NULL
state$last_template_json <- NULL; state$last_error <- NULL; state$pending <- FALSE; state$prompt_stale <- FALSE
state$pending_upload <- NULL; state$precheck <- NULL; state$precheck_key <- NULL; state$template_file <- NULL; state$template_file_key <- NULL
# A MockShinySession, not a plain environment: the async chain installs the
# session as the reactive domain (withReactiveDomain), and Shiny internals
# then call methods on it that an environment does not have.
session <- shiny::MockShinySession$new()
# pump the event loop until the translator is idle again
settle <- function(max_sec = 600) {
  t0 <- Sys.time()
  later::run_now(0.05)
  while (isTRUE(state$pending) && as.numeric(Sys.time() - t0, units = "secs") < max_sec) later::run_now(0.05)
  stopifnot(!isTRUE(state$pending))
}

# an upload message the way the sheet picker would post it
state$messages[[1]] <- list(role = "user", content = "UPLOADED FILE zambia.xlsx: sheets Country-specific data, Estimated populations, MMS activity data, Coefficients, MoE (rows omitted in this dry run). Production systems: commercial dairy, emergent dairy, commercial beef, emergent beef, extensive beef.", display = "Uploaded zambia.xlsx", source = "server_upload")
t0 <- Sys.time()
.translator_send(state, session, stage = "explore"); settle(); stopifnot(is.null(state$last_error))
state$messages[[length(state$messages) + 1]] <- list(role = "user", content = "Year 2022. Split calves 50/50. Milk as kg per day.", display = "answers")
.translator_send(state, session, stage = "clarify"); settle(); stopifnot(is.null(state$last_error))
cat("chat turns done; messages:", length(state$messages), "\n")

# ---- scenario 1: a fresh Produce reaches the workbook -------------------------
.translator_force_template(state, session); settle()
cat("calls made:", paste(calls, collapse = " -> "), "\n")
cat("last_error:", state$last_error %||% "none", "\n")
stopifnot(!is.null(state$last_template_json), .translator_template_is_well_formed(state$last_template_json))
merged <- jsonlite::fromJSON(state$last_template_json, simplifyVector = TRUE)
cat("merged .model:", merged$.model %||% "(missing)", "\n")
stopifnot(identical(merged$.model, "stub"))
cat("template JSON chars:", nchar(state$last_template_json), " workbook built:", !is.null(state$template_file) && file.exists(state$template_file), " precheck error:", state$precheck$error %||% "none", "\n")
print(unlist(state$precheck$summary)); cat("consistency notes:", nrow(state$precheck$issues), "\n")
out <- suppressMessages(parse_uploaded_template(state$template_file))
cat("workbook: params", nrow(out$param_specs), " manure", nrow(out$manure), " ts", nrow(out$population), " levels", length(unique(out$param_specs$aggregation_level)), "\n")
cmp <- merge(ps[, c("aggregation_level","sub_category","parameter","mean")], out$param_specs[, c("aggregation_level","sub_category","parameter","mean")], by = c("aggregation_level","sub_category","parameter"))
cat("parameter means preserved end to end:", sum(abs(num(cmp$mean.x) - num(cmp$mean.y)) < 1e-6 | (is.na(cmp$mean.x) & is.na(cmp$mean.y))), "of", nrow(cmp), "\n")
cat("notes stamp present:", grepl("translator: app", out$metadata$notes %||% "", fixed = TRUE), "\n")
# WP4: the workbook the user downloads is annotated (filters, Check and Why)
# and still parses; the issues carry a severity.
wb_a <- openxlsx::loadWorkbook(state$template_file)
hp <- openxlsx::read.xlsx(state$template_file, sheet = "Parameters", startRow = 3, colNames = TRUE)
stopifnot(all(c("Check", "Why") %in% names(hp)), nzchar(wb_a$worksheets[[match("Parameters", names(wb_a))]]$autoFilter %||% ""))
cat("annotated workbook: Check/Why columns and filters present; issues by severity:",
    paste(names(table(state$precheck$issues$severity)), table(state$precheck$issues$severity), collapse = ", "), "\n")
cat("persisted history in runtime:", length(list.files(Sys.getenv("APP_RUNTIME_DIR"), "translator_history_")), " memos:", length(list.files(Sys.getenv("APP_RUNTIME_DIR"), "translator_memo_")), "\n")
# every group carries the full catalogue (the writer back-fills gap rows,
# including the optional GE and DMI intake rows added in 2026-09)
n_groups <- length(unique(paste(ps$cattle_type, ps$aggregation_level, ps$sub_category)))
cat("groups:", n_groups, " expected parameter rows:", n_groups * nrow(PARAM_CATALOGUE), "\n")
stopifnot(nrow(out$param_specs) == n_groups * nrow(PARAM_CATALOGUE), state$precheck$summary$n_fail == 0,
          length(state$batch_parts) == length(levels), !is.null(state$batch_parts_key))
n_batch_1 <- sum(grepl("^batch:", calls))
stopifnot(n_batch_1 == length(levels))

# ---- scenario 2: Produce again, nothing changed: parts reused -----------------
calls <- character(); state$last_template_json <- NULL
.translator_force_template(state, session); settle()
cat("scenario 2 calls:", paste(calls, collapse = " -> "), "\n")
stopifnot(is.null(state$last_error), !is.null(state$last_template_json), sum(grepl("^batch:", calls)) == 0L)

# ---- scenario 3: a later answer invalidates the cached parts ------------------
calls <- character(); state$last_template_json <- NULL
state$messages[[length(state$messages) + 1]] <- list(role = "user", content = "Correction: keep calves pooled, do not split them.", display = "answer")
.translator_send(state, session, stage = "clarify"); settle(); stopifnot(is.null(state$last_error))
calls <- character()
.translator_force_template(state, session); settle()
cat("scenario 3 calls:", paste(calls, collapse = " -> "), "\n")
stopifnot(is.null(state$last_error), !is.null(state$last_template_json), sum(grepl("^batch:", calls)) == length(levels))
# WP1 step 4: the new decision (pooled calves) contradicts the batches the
# stub emits first; every level with both calves halves is re-emitted once
# and the retry honours it, so the decision ends up applied and the final
# workbook carries no calves_male.
n_split_levels <- length(unique(ps$aggregation_level[ps$sub_category == "calves_male"]))
cat("levels with both calves halves:", n_split_levels, " retries:", sum(grepl("^retry:", calls)), "\n")
stopifnot(sum(grepl("^retry:", calls)) == n_split_levels, isTRUE(state$register$calves_handling$applied))
out3 <- suppressMessages(parse_uploaded_template(state$template_file))
stopifnot(!"calves_male" %in% out3$param_specs$sub_category, "calves_female" %in% out3$param_specs$sub_category)
cat("decision enforced: calves_male absent from the final workbook\n")

cat(sprintf("dry run finished in %.0f s\n", as.numeric(Sys.time() - t0, units = "secs")))
cat("DRY RUN PASSED\n")
