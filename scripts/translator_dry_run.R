# Usage: Rscript scripts/translator_dry_run.R   (needs the gitignored test_data/ZAM/zam2_fixed.xlsx; no API call, about 15 minutes since the review step of 2026-10-30 rebuilds the workbook; do not run it under a 10-minute timeout)
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
    # WP5: the sub-categories per system drive the time estimate
    scbl <- lapply(setNames(levels, levels), function(lv) unique(ps$sub_category[ps$aggregation_level == lv]))
    reply <- jsonlite::toJSON(list(mode = "enumerate", aggregation_levels = levels, inventory_metadata = meta,
                                   sub_categories_by_level = scbl), auto_unbox = TRUE)
    return(c(list(reply = as.character(reply), tool_used = TRUE), base))
  }
  if (grepl("mode = 'batch'", last, fixed = TRUE)) {
    lv <- levels[vapply(levels, function(l) grepl(paste0("'", l, "'"), last, fixed = TRUE), logical(1))][1]
    rejected <- grepl("REJECTED for", last, fixed = TRUE)
    # 2026-10-31 (Stage 3): a sub-category rejection is told apart from a
    # decision rejection by its wording
    scope_rej <- rejected && grepl("the batch carries", last, fixed = TRUE)
    calls <<- c(calls, paste0(if (scope_rej) "retry_scope:" else if (rejected) "retry:" else "batch:", lv))
    # 2026-10-22 (WP1): the binding decisions must be the last paragraph of
    # every batch request and name this batch's level.
    if (!rejected)
      stopifnot(grepl("BINDING DECISIONS", last, fixed = TRUE),
                grepl(sprintf("For this batch ('%s')", lv), last, fixed = TRUE),
                grepl("inventory_year: 2022", last, fixed = TRUE),
                # 2026-10-31 (Stage 2): the checklist and the GE/DMI sentence
                # sit in every batch request, before the decisions
                grepl("EMISSION CHECKLIST", last, fixed = TRUE),
                grepl("no GE or DMI row", last, fixed = TRUE),
                regexpr("EMISSION CHECKLIST", last, fixed = TRUE) < regexpr("BINDING DECISIONS", last, fixed = TRUE),
                # Stage 3: the system's rows and expected sub-categories, before the checklist
                grepl("SOURCE ROWS FOR THIS BATCH", last, fixed = TRUE),
                grepl(sprintf("Expected sub-categories (%d)", length(unique(ps$sub_category[ps$aggregation_level == lv]))), last, fixed = TRUE),
                regexpr("SOURCE ROWS FOR THIS BATCH", last, fixed = TRUE) < regexpr("EMISSION CHECKLIST", last, fixed = TRUE))
    nudge_checked <<- nudge_checked + 1L
    # On a decision re-emit (WP1 step 4) the stub honours the pooled-calves
    # decision: the male half is dropped, the female half stands for the
    # pooled group.
    ps_lv <- ps[ps$aggregation_level == lv, param_cols]
    if (rejected && !scope_rej) ps_lv <- ps_lv[ps_lv$sub_category != "calves_male", ]
    # Stage 3: the first batch of the run drops one sub-category once; the
    # server must ask again and the stub then gives the full set
    if (scope_drop_once && !rejected && lv == levels[1]) {
      scope_drop_once <<- FALSE
      ps_lv <- ps_lv[ps_lv$sub_category != unique(ps_lv$sub_category)[1], ]
    }
    piece <- sprintf('{"mode":"batch","aggregation_level":"%s","inventory_metadata":%s,"parameters":%s,"manure_management":%s,"parameter_timeseries":%s}',
                     lv, jsonlite::toJSON(meta, auto_unbox = TRUE),
                     rows_json(ps_lv),
                     rows_json(mn[mn$aggregation_level == lv & !is.na(mn$fraction_pct), mm_cols]),
                     rows_json(ts[ts$aggregation_level == lv, ts_cols]))
    return(c(list(reply = piece, tool_used = TRUE), base))
  }
  # 2026-10-30: the review of the checks (R/translator_review.R). The stub
  # corrects one row (a visible uncertainty change) and explains the first
  # flagged item as not an error.
  if (startsWith(last, "REVIEW.")) {
    calls <<- c(calls, "review")
    stopifnot(grepl("FLAGGED ITEMS", last, fixed = TRUE), grepl("mode = \"review\"", last, fixed = TRUE))
    first <- regmatches(last, regexpr("[[]1[]] [^|]+[|] [^|]+[|]", last))
    where1 <- if (length(first)) trimws(strsplit(first, "|", fixed = TRUE)[[1]][2]) else "unknown"
    r1 <- ps[ps$aggregation_level == levels[1] & ps$parameter == "BW", param_cols][1, ]
    r1$uncertainty_pct <- 12.34; r1$lower <- NA; r1$upper <- NA
    reply <- sprintf('{"mode":"review","parameters":%s,"not_errors":[{"check":"stub","where":"%s","reason":"The file gives this value (stub)."}]}',
                     rows_json(r1), where1)
    return(c(list(reply = reply, tool_used = TRUE), base))
  }
  calls <<- c(calls, "chat")
  # a clarify reply the way rule 11 asks for it: prose, questions, then the
  # decisions block
  # The Zambia ground truth splits calves (the transcript asked for 50/50),
  # so the stub's decision is "split" until the user says otherwise in
  # scenario 3; from then on it is "pooled" and the batches violate it.
  pooled <- grepl("keep calves pooled", last, fixed = TRUE)
  calves_dec <- if (pooled) "pooled: one calves category per system" else "split into calves_male and calves_female, 50/50"
  # Stage 3: section B as a source_values block built from the fixture
  sv_json <- jsonlite::toJSON(lapply(seq_len(nrow(ps)), function(i) list(
    system = ps$aggregation_level[i], label = ps$sub_category[i], section = "Parameters", sheet = "Data",
    row = i + 1L, col = "value", mean = ps$mean[i], parameter = ps$parameter[i],
    sub_category = ps$sub_category[i], aggregation_level = ps$aggregation_level[i])), auto_unbox = TRUE, na = "null", digits = NA)
  txt <- paste0("Thanks. Before I can produce, please answer:\n\n### B. Inventory of values found\nsource_values: ", nrow(ps),
                " entries\n```source_values\n", sv_json, "\n```\n\n### D. Ambiguities to ask the user\n\n1. Which year?\n2. Split calves?\n\n",
                "```decisions\n[{\"topic\": \"inventory_year\", \"decision\": \"2022\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"Year 2022\"},",
                " {\"topic\": \"calves_handling\", \"decision\": \"", calves_dec, "\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"calves\"}]\n```")
  on_chunk(txt)
  c(list(reply = txt, tool_used = FALSE), base)
}
nudge_checked <- 0L
scope_drop_once <- TRUE
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
# Stage 3: the batch that dropped a sub-category was asked again once
stopifnot(sum(grepl("^retry_scope:", calls)) == 1L, length(state$source_values) == nrow(ps))
# 2026-10-30: the review ran once, its correction is in the workbook and
# both the correction and the explanation are listed with the checks.
stopifnot(sum(calls == "review") == 1L, !is.null(state$review), state$review$corrected >= 1L,
          any(state$precheck$issues$check %in% "corrected by the AI review"),
          any(state$precheck$issues$check %in% "reviewed: not an error"))
rv_ps <- suppressMessages(parse_uploaded_template(state$template_file))$param_specs
stopifnot(any(abs(num(rv_ps$uncertainty_pct[rv_ps$aggregation_level == levels[1] & rv_ps$parameter == "BW"]) - 12.34) < 1e-6, na.rm = TRUE))
cat("review: flagged", state$review$flagged, " corrected", state$review$corrected, " not errors", state$review$not_errors,
    " still flagged", state$review$still_flagged, "\n")

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

# ---- WP5/WP6: the job file and the delivery -----------------------------------
jb <- translator_job_read(state$job_id)
stopifnot(!is.null(jb), identical(jb$status, "done"), isTRUE(as.numeric(jb$progress) >= 1),
          length(jb$outputs) == 3L, all(file.exists(unlist(jb$outputs))),
          !is.null(jb$estimate), length(jb$levels) == length(levels),
          identical(jb$delivery$mode, "browser"))
cat("job", jb$id, ": done, 3 outputs,", basename(jb$outputs$template), "; estimate source:", jb$estimate$source,
    "; delivery:", jb$delivery$mode, "\n")
stopifnot(grepl("^Zambia_2022_cattle_uncertainty_template_", basename(jb$outputs$template)),
          grepl("_translation_checks_", basename(jb$outputs$checks)),
          grepl("_translation_conversation_.*docx$", basename(jb$outputs$conversation)))
# a second session of the same user finds the job and its files
stopifnot(identical(translator_job_find("dryrun@local")$id, jb$id))

# ---- scenario 4: the tab is gone, the files go by email ------------------------
mails <- list()
.auth_send_email <- function(to, subject, text, html = NULL, attachments = NULL, ...) {
  mails[[length(mails) + 1L]] <<- list(to = to, subject = subject, n_att = length(attachments),
                                       names = vapply(attachments, function(a) a$name, character(1)))
  list(ok = TRUE, provider = "stub", attempts = character(0))
}
session$close()
calls <- character(); state$last_template_json <- NULL
state$messages[[length(state$messages) + 1]] <- list(role = "user", content = "One more change: nothing else.", display = "answer")
.translator_send(state, session, stage = "clarify"); settle(); stopifnot(is.null(state$last_error))
.translator_force_template(state, session); settle()
jb4 <- translator_job_read(state$job_id)
cat("scenario 4: session closed; job", jb4$status, "; delivery", jb4$delivery$mode, "; mails:", length(mails),
    if (length(mails)) paste("attachments:", mails[[1]]$n_att) else "", "\n")
stopifnot(identical(jb4$status, "done"), identical(jb4$delivery$mode, "email"), length(mails) == 1L,
          mails[[1]]$n_att == 3L, identical(mails[[1]]$to, "dryrun@local"))

# ---- scenario 5: one and two production systems take the same path -----------
# 2026-10-28: until now a file with two systems or fewer went to the
# single-request path, which is synchronous and held the process for every
# user. The synchronous client stops this script if it is ever called.
all_levels <- levels
for (n_lv in 1:2) {
  levels <- all_levels[seq_len(n_lv)]
  calls <- character(); state$last_template_json <- NULL; state$batch_parts <- list(); state$batch_parts_key <- NULL
  state$messages[[length(state$messages) + 1]] <- list(role = "user", content = sprintf("Only %d system(s) this time.", n_lv), display = "answer")
  .translator_force_template(state, session); settle()
  cat(sprintf("scenario 5 (%d system(s)): %s; error: %s\n", n_lv, paste(calls, collapse = " -> "), state$last_error %||% "none"))
  stopifnot(is.null(state$last_error), sum(grepl("^batch:", calls)) == n_lv, !is.null(state$last_template_json),
            !is.null(state$template_file), file.exists(state$template_file))
}
levels <- all_levels

cat(sprintf("dry run finished in %.0f s\n", as.numeric(Sys.time() - t0, units = "secs")))
cat("DRY RUN PASSED\n")
