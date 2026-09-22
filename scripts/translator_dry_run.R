# Usage: Rscript scripts/translator_dry_run.R   (needs the gitignored test_data/ZAM/zam2_fixed.xlsx; no API call, about 2 minutes)
# End-to-end dry run of the translator pipeline with a stubbed model.
# Explore -> clarify -> Produce (enumerate + 5 batches) -> merge -> writer ->
# finalise -> precheck -> download copy, using the corrected Zambia workbook
# as the "model's" answers. No API call is made.
suppressMessages({library(shiny); library(readxl)})
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
# ---- the stub -----------------------------------------------------------------
anthropic_chat_stream <- function(messages, on_chunk = function(text) {}, on_tick = function() {}, model = "stub", max_tokens = 1, temperature = 0,
                                  timeout_sec = 1, tools = NULL, tool_choice = NULL, cache_ttl = "auto") {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
  usage <- list(prompt_tokens = 10L, completion_tokens = 10L, cached_tokens = 100L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L, total_tokens = 120L)
  base <- list(usage = usage, model = "stub", cost_usd = 0, latency_sec = 0.1, error = NULL, cache_ttl = "1h")
  if (grepl("mode = 'enumerate'", last, fixed = TRUE)) {
    calls <<- c(calls, "enumerate")
    reply <- jsonlite::toJSON(list(mode = "enumerate", aggregation_levels = levels, inventory_metadata = meta), auto_unbox = TRUE)
    return(c(list(reply = as.character(reply), tool_used = TRUE), base))
  }
  if (grepl("mode = 'batch'", last, fixed = TRUE)) {
    lv <- levels[vapply(levels, function(l) grepl(paste0("'", l, "'"), last, fixed = TRUE), logical(1))][1]
    calls <<- c(calls, paste0("batch:", lv))
    piece <- sprintf('{"mode":"batch","aggregation_level":"%s","inventory_metadata":%s,"parameters":%s,"manure_management":%s,"parameter_timeseries":%s}',
                     lv, jsonlite::toJSON(meta, auto_unbox = TRUE),
                     rows_json(ps[ps$aggregation_level == lv, param_cols]),
                     rows_json(mn[mn$aggregation_level == lv & !is.na(mn$fraction_pct), mm_cols]),
                     rows_json(ts[ts$aggregation_level == lv, ts_cols]))
    return(c(list(reply = piece, tool_used = TRUE), base))
  }
  calls <<- c(calls, "chat")
  on_chunk("Thanks. Section D: 1. Which year? 2. Split calves?")
  c(list(reply = "Thanks. Section D: 1. Which year? 2. Split calves?", tool_used = FALSE), base)
}
# ---- state and session stand-ins ---------------------------------------------
state <- new.env()
state$user_email <- "dryrun@local"; state$messages <- list(); state$batch_parts <- list()
state$last_template_json <- NULL; state$last_error <- NULL; state$pending <- FALSE; state$prompt_stale <- FALSE
state$pending_upload <- NULL; state$precheck <- NULL; state$precheck_key <- NULL; state$template_file <- NULL; state$template_file_key <- NULL
msgs <- character()
session <- list(sendCustomMessage = function(type, msg) { msgs <<- c(msgs, type); invisible(NULL) })
# an upload message the way the sheet picker would post it
state$messages[[1]] <- list(role = "user", content = "UPLOADED FILE zambia.xlsx: sheets Country-specific data, Estimated populations, MMS activity data, Coefficients, MoE (rows omitted in this dry run). Production systems: commercial dairy, emergent dairy, commercial beef, emergent beef, extensive beef.", display = "Uploaded zambia.xlsx", source = "server_upload")
t0 <- Sys.time()
.translator_send(state, session, stage = "explore"); stopifnot(is.null(state$last_error))
state$messages[[length(state$messages) + 1]] <- list(role = "user", content = "Year 2022. Split calves 50/50. Milk as kg per day.", display = "answers")
.translator_send(state, session, stage = "clarify"); stopifnot(is.null(state$last_error))
cat("chat turns done; messages:", length(state$messages), "\n")
.translator_force_template(state, session)
cat("calls made:", paste(calls, collapse = " -> "), "\n")
cat("last_error:", state$last_error %||% "none", "\n")
stopifnot(!is.null(state$last_template_json), .translator_template_is_well_formed(state$last_template_json))
cat("template JSON chars:", nchar(state$last_template_json), " workbook built:", !is.null(state$template_file) && file.exists(state$template_file), " precheck error:", state$precheck$error %||% "none", "\n")
print(unlist(state$precheck$summary)); cat("consistency notes:", nrow(state$precheck$issues), "\n")
# download path: the cached file is what the handler copies
out <- suppressMessages(parse_uploaded_template(state$template_file))
cat("workbook: params", nrow(out$param_specs), " manure", nrow(out$manure), " ts", nrow(out$population), " levels", length(unique(out$param_specs$aggregation_level)), "\n")
cmp <- merge(ps[, c("aggregation_level","sub_category","parameter","mean")], out$param_specs[, c("aggregation_level","sub_category","parameter","mean")], by = c("aggregation_level","sub_category","parameter"))
cat("parameter means preserved end to end:", sum(abs(num(cmp$mean.x) - num(cmp$mean.y)) < 1e-6 | (is.na(cmp$mean.x) & is.na(cmp$mean.y))), "of", nrow(cmp), "\n")
cat("notes stamp present:", grepl("translator: app", out$metadata$notes %||% "", fixed = TRUE), "\n")
cat("persisted history in runtime:", length(list.files(Sys.getenv("APP_RUNTIME_DIR"), "translator_history_")), " memos:", length(list.files(Sys.getenv("APP_RUNTIME_DIR"), "translator_memo_")), "\n")
cat("browser messages:", paste(unique(msgs), collapse = ", "), "\n")
cat(sprintf("dry run finished in %.0f s\n", as.numeric(Sys.time() - t0, units = "secs")))
stopifnot(nrow(out$param_specs) == 800, state$precheck$summary$n_fail == 0)
cat("DRY RUN PASSED\n")
