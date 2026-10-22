# Usage: Rscript scripts/test_translator_callbacks.R   (no API call, about 1 minute)
#
# The callbacks the way production runs them (2026-10-22): `state` is a real
# shiny::reactiveValues, and the later() callbacks are pumped from a plain
# R session with NO reactive context, which is what a Shiny app does when the
# API answers. A read of `state` from a callback that is not inside isolate()
# fails here with "Can't access reactive value ... outside of reactive
# consumer", the error a user saw on the live app on 2026-10-22; testServer
# never shows it because it evaluates everything inside its own isolate.
suppressMessages({library(shiny); library(later); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"), ANTHROPIC_API_KEY = "stub-key")

# ---- a three-system fixture from the built-in example --------------------------
base <- fill_bounds(generate_country_y_example())
levels <- c("sys_a", "sys_b", "sys_c")
ps <- do.call(rbind, lapply(levels, function(lv) { d <- base; d$cattle_type <- "non_dairy"; d$aggregation_level <- lv; d }))
if (!"param_type" %in% names(ps)) ps$param_type <- "coefficient"
if (!"data_source" %in% names(ps)) ps$data_source <- "user_file"
param_cols <- intersect(c("cattle_type","aggregation_level","sub_category","parameter","mean","uncertainty_pct","lower","upper","distribution","param_type","data_source"), names(ps))
meta <- list(country = "Country Y", region = "africa", year = 2022L, species = "cattle_non_dairy",
             ipcc_version = "2019_refinement", prepared_by = "callbacks test", notes = "stub")
rows_json <- function(df) jsonlite::toJSON(df, dataframe = "rows", na = "null", auto_unbox = TRUE, digits = NA)
calls <- character()
anthropic_chat_stream_async <- function(messages, on_chunk = function(text) {}, on_tick = function(n = 0L) {},
                                        should_stop = function() FALSE, on_result = function(res) {}, ...) {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
  usage <- list(prompt_tokens = 10L, completion_tokens = 10L, cached_tokens = 0L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L, total_tokens = 20L)
  base_r <- list(usage = usage, model = "stub", cost_usd = 0, latency_sec = 0.1, error = NULL, stopped = FALSE)
  if (grepl("mode = 'enumerate'", last, fixed = TRUE)) {
    calls <<- c(calls, "enumerate")
    resp <- c(list(reply = as.character(jsonlite::toJSON(list(mode = "enumerate", aggregation_levels = levels, inventory_metadata = meta), auto_unbox = TRUE)), tool_used = TRUE), base_r)
  } else if (grepl("mode = 'batch'", last, fixed = TRUE)) {
    lv <- levels[vapply(levels, function(l) grepl(paste0("'", l, "'"), last, fixed = TRUE), logical(1))][1]
    calls <<- c(calls, paste0("batch:", lv))
    piece <- sprintf('{"mode":"batch","aggregation_level":"%s","inventory_metadata":%s,"parameters":%s,"manure_management":[],"parameter_timeseries":[]}',
                     lv, jsonlite::toJSON(meta, auto_unbox = TRUE), rows_json(ps[ps$aggregation_level == lv, param_cols]))
    resp <- c(list(reply = piece, tool_used = TRUE), base_r)
  } else if (grepl("The JSON array:", last, fixed = TRUE)) {
    calls <<- c(calls, "summariser")
    resp <- c(list(reply = "[{\"topic\": \"species\", \"decision\": \"cattle_non_dairy\", \"basis\": \"file\", \"confidence\": \"high\", \"quote\": \"\"}]", tool_used = FALSE), base_r)
  } else {
    calls <<- c(calls, "chat")
    # no decisions block on purpose: the summariser fallback has to run
    txt <- "Noted.\n\n1. Which year?"
    on_chunk(txt)
    resp <- c(list(reply = txt, tool_used = FALSE), base_r)
  }
  on_tick(10L)
  later::later(function() on_result(resp), 0.01)
  invisible(NULL)
}
anthropic_chat_stream <- function(...) stop("the synchronous client must not be called")

# ---- real reactive state, a mock session, no reactive context --------------------
state <- shiny::reactiveValues(
  user_email = "cb@local", messages = list(), batch_parts = list(), batch_parts_key = NULL,
  last_template_json = NULL, last_error = NULL, pending = FALSE, prompt_stale = FALSE,
  pending_upload = NULL, precheck = NULL, precheck_key = NULL, template_file = NULL, template_file_key = NULL,
  register = list(), pending_questions = list(), q_index = 1L, produce_after_answers = FALSE,
  reg_edit_topic = NULL, source_categories = NULL, job_id = NULL, dir_chosen = NULL,
  delivery_ack = TRUE, produce_after_ack = FALSE, source_fp = NULL)
session <- shiny::MockShinySession$new()
settle <- function(max_sec = 300) {
  t0 <- Sys.time(); later::run_now(0.05)
  while (isTRUE(isolate(state$pending)) && as.numeric(Sys.time() - t0, units = "secs") < max_sec) later::run_now(0.05)
  stopifnot(!isTRUE(isolate(state$pending)))
}
isolate({
  state$messages[[1]] <- list(role = "user", content = "UPLOADED FILE y.xlsx with three production systems.", display = "Uploaded y.xlsx", source = "server_upload")
})

# a chat turn: handle_result reads and writes state from the callback
isolate(.translator_send(state, session, stage = "explore")); settle()
err <- isolate(state$last_error)
cat("after explore: error =", err %||% "none", "; messages:", length(isolate(state$messages)), "\n")
stopifnot(is.null(err), length(isolate(state$messages)) == 2L, length(isolate(state$pending_questions)) == 1L)
# an answer: the reply has no block, so the summariser callback runs too
isolate({ state$messages[[3]] <- list(role = "user", content = "2022", display = "2022") })
isolate(.translator_send(state, session, stage = "clarify")); settle(); later::run_now(0.3)
stopifnot(is.null(isolate(state$last_error)), "summariser" %in% calls,
          identical(isolate(state$register)$species$decision, "cattle_non_dairy"))
cat("after clarify: summariser ran, register filled from the callback\n")

# Produce: the whole chain (discovery, three batches, assembly, job finish)
isolate(.translator_force_template(state, session)); settle()
err <- isolate(state$last_error)
cat("after produce: error =", err %||% "none", "; calls:", paste(calls, collapse = " -> "), "\n")
stopifnot(is.null(err) || !grepl("reactive", err), !is.null(isolate(state$last_template_json)),
          sum(grepl("^batch:", calls)) == 3L)
jb <- translator_job_read(isolate(state$job_id))
cat("job:", jb$status, "; outputs:", length(jb$outputs), "\n")
stopifnot(identical(jb$status, "done"), length(jb$outputs) == 3L)
cat("CALLBACK TEST PASSED\n")
