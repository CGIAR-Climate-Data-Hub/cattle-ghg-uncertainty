# Usage: Rscript scripts/test_translator_loop.R   (no API call, about 1 minute)
# Questions in the conversation (2026-10-22, revised): question bubbles,
# answers through the normal input, one AI call per round, the register
# folded into the chat, the reduced Produce gate, the fallback summariser,
# the corrected-template upload. Through the real chat server with the
# sign-in and the AI stubbed.
suppressMessages({library(shiny); library(later); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"), ANTHROPIC_API_KEY = "stub-key")
options(shiny.testmode = TRUE)
auth_cookie_lookup <- function(...) "cookie"
auth_session_cookie_verify <- function(v) "loop@local"
auth_is_approved <- function(e) TRUE
produce_calls <- 0L
.translator_force_template <- function(state, session) { produce_calls <<- produce_calls + 1L; invisible(NULL) }
ai_calls <- character(); seen_hist <- list()
with_block <- TRUE
anthropic_chat_stream_async <- function(messages, on_chunk = function(text) {}, on_tick = function(n = 0L) {},
                                        should_stop = function() FALSE, on_result = function(res) {}, ...) {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
  seen_hist[[length(seen_hist) + 1]] <<- messages
  usage <- list(prompt_tokens = 1L, completion_tokens = 1L, cached_tokens = 0L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L, total_tokens = 2L)
  base <- list(tool_used = FALSE, usage = usage, model = "stub", cost_usd = 0, latency_sec = 0.1, error = NULL, stopped = FALSE)
  if (grepl("The JSON array:", last, fixed = TRUE)) {
    ai_calls <<- c(ai_calls, "summariser")
    resp <- c(list(reply = "[{\"topic\": \"uncertainty_source\", \"decision\": \"file_bounds\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"use my bounds\"}]"), base)
  } else {
    ai_calls <<- c(ai_calls, "chat")
    reply <- "Thanks, noted.\n\n1. One more: which region is the herd in?"
    if (with_block) reply <- paste0(reply, "\n\n```decisions\n[{\"topic\": \"inventory_year\", \"decision\": \"2022\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"2022\"}]\n```")
    resp <- c(list(reply = reply), base)
  }
  later::later(function() on_result(resp), 0.01)
  invisible(NULL)
}
pump <- function(state) { t0 <- Sys.time(); later::run_now(0.05); while (isTRUE(state$pending) && as.numeric(Sys.time() - t0, units = "secs") < 60) later::run_now(0.05); later::run_now(0.2) }
src_of <- function(msgs) vapply(msgs, function(m) m$source %||% "", character(1))

shiny::testServer(translator_chat_server, {
  session$setInputs(dummy = 1)
  stopifnot(identical(state$user_email, "loop@local"))

  # ---- an AI round of two questions, answered in the chat ----------------------
  state$messages <- list(list(role = "user", content = "UPLOADED FILE x.xlsx", display = "upload", source = "server_upload"),
                         list(role = "assistant", content = "Please answer:\n\n1. Which year?\n2. Split calves?", display = "Please answer the questions below."))
  state$pending_questions <- list(list(id = 1, kind = "ai", text = "Which year?", answer = NULL),
                                  list(id = 2, kind = "ai", text = "Split calves?", answer = NULL))
  .translator_begin_round(state, sprintf(t("ai_q_notice"), 2L))
  s0 <- src_of(state$messages)
  stopifnot(identical(tail(s0, 2), c("server_notice", "server_question")),
            grepl("Question 1 of 2: Which year?", state$messages[[length(state$messages)]]$display, fixed = TRUE))
  session$setInputs(translator_input = "2022"); session$setInputs(translator_send = 1)
  stopifnot(identical(state$q_index, 2L), identical(state$pending_questions[[1]]$answer, "2022"),
            identical(tail(src_of(state$messages), 2), c("user_answer", "server_question")), length(ai_calls) == 0L)
  session$setInputs(translator_input = "no, keep them pooled"); session$setInputs(translator_send = 2)
  pump(state)
  batch <- Filter(function(m) identical(m$source, "answers_batch"), state$messages)
  stopifnot(length(batch) == 1L, grepl("Answer: 2022", batch[[1]]$content, fixed = TRUE),
            grepl("keep them pooled", batch[[1]]$content, fixed = TRUE), sum(ai_calls == "chat") == 1L)
  # the API saw the batch and the upload, not the bubbles or the single answers
  hist_src <- vapply(seen_hist[[1]], function(m) m$content, character(1))
  stopifnot(any(grepl("Answers to your questions", hist_src, fixed = TRUE)),
            !any(grepl("Question 1 of 2", hist_src, fixed = TRUE)), !any(hist_src == "2022"))
  # the reply settled the year (recorded line) and asked one more question (a bubble)
  stopifnot(identical(state$register$inventory_year$decision, "2022"))
  s1 <- src_of(state$messages)
  stopifnot(any(grepl("^Recorded: ", vapply(state$messages, function(m) m$display %||% "", ""))),
            identical(tail(s1, 1), "server_question"), length(state$pending_questions) == 1L)
  cat("round 1: bubbles in the chat, answers batched, history filtered, recorded line posted\n")

  # ---- the fallback summariser: a reply without its block ------------------
  with_block <<- FALSE
  session$setInputs(translator_input = "Africa"); session$setInputs(translator_send = 3)
  pump(state)
  stopifnot(sum(ai_calls == "summariser") == 1L, identical(state$register$uncertainty_source$decision, "file_bounds"))
  with_block <<- TRUE
  cat("round 2: summariser filled uncertainty_source\n")

  # ---- the Produce gate: assumptions in one line, only calves asked ----------
  session$setInputs(translator_input = "skip"); session$setInputs(translator_send = 4); pump(state)   # close the open question
  state$pending_questions <- list()
  session$setInputs(translator_force_template = 1)
  stopifnot(produce_calls == 0L, isTRUE(state$produce_after_answers))
  asked <- vapply(state$pending_questions, function(q) q$topic, "")
  cat("gate asks:", paste(asked, collapse = ", "), "\n")
  stopifnot(identical(asked, "calves_handling"),
            identical(state$register$species$basis, "assumed"), identical(state$register$ipcc_edition$basis, "assumed"))
  stopifnot(identical(tail(src_of(state$messages), 1), "server_question"),
            grepl("Reply with one of", state$messages[[length(state$messages)]]$display, fixed = TRUE))
  session$setInputs(translator_input = "keep them pooled please"); session$setInputs(translator_send = 5)
  stopifnot(identical(state$register$calves_handling$decision, "pooled"), identical(state$register$calves_handling$basis, "user"))
  cat("gate: one question, answered in words, mapped to the choice; Produce started:", produce_calls, "\n")
  stopifnot(produce_calls == 1L, length(state$pending_questions) == 0L, length(translator_register_missing(state$register)) == 0L)
  # the delivery pop-up is the next step in the live app; here the dispatcher is stubbed
  stopifnot(!is.null(state$delivery_ack))
  saved <- conversation_load_full("loop@local")
  stopifnot(identical(saved$extra$register$calves_handling$decision, "pooled"))

  # ---- a corrected template comes back with a note ------------------------------
  tpl <- file.path(tempdir(), "corrected_template.xlsx")
  generate_template_openxlsx(tpl, include_example = TRUE)
  session$setInputs(translator_file = list(datapath = tpl, name = "corrected_template.xlsx", size = file.size(tpl)))
  stopifnot(isTRUE(state$pending_upload$is_template), !is.null(state$pending_upload$precheck))
  picker <- as.character(output$translator_sheet_picker$html)
  stopifnot(grepl("looks like a template produced by the tool", picker, fixed = TRUE),
            grepl("translator_upload_note", picker, fixed = TRUE))
  n_sheets <- length(state$pending_upload$parsed$sheets)
  session$setInputs(translator_sheets = as.character(seq_len(n_sheets)),
                    translator_upload_note = "Calves are one group; the year is 2022.")
  session$setInputs(translator_send_sheets = 1)
  pump(state)
  up <- Filter(function(m) identical(m$source, "server_upload"), state$messages)
  last_up <- up[[length(up)]]
  stopifnot(grepl("CORRECTED TEMPLATE (version 2)", last_up$content, fixed = TRUE),
            grepl("Calves are one group", last_up$content, fixed = TRUE),
            identical(state$register$corrected_template$basis, "user"))
  cat("corrected template: recognised, checked, sent with the note\n")
  cat("LOOP TEST PASSED\n")
})
