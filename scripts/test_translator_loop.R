# Usage: Rscript scripts/test_translator_loop.R   (no API call, about 1 minute)
# The one-question-at-a-time loop, the Produce gate, the register card and
# the fallback summariser, through the real chat server with the sign-in
# and the AI stubbed (2026-10-22, WP1).
suppressMessages({library(shiny); library(later); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"), ANTHROPIC_API_KEY = "stub-key")
options(shiny.testmode = TRUE)
auth_cookie_lookup <- function(...) "cookie"
auth_session_cookie_verify <- function(v) "loop@local"
auth_is_approved <- function(e) TRUE
produce_calls <- 0L
.translator_force_template <- function(state, session) { produce_calls <<- produce_calls + 1L; invisible(NULL) }
ai_calls <- character()
with_block <- TRUE
anthropic_chat_stream_async <- function(messages, on_chunk = function(text) {}, on_tick = function(n = 0L) {},
                                        should_stop = function() FALSE, on_result = function(res) {}, ...) {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
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

shiny::testServer(translator_chat_server, {
  session$setInputs(dummy = 1)
  stopifnot(identical(state$user_email, "loop@local"))

  # ---- an AI round of two questions, answered one at a time -----------------
  state$messages <- list(list(role = "user", content = "UPLOADED FILE x.xlsx", display = "upload", source = "server_upload"),
                         list(role = "assistant", content = "Please answer:\n\n1. Which year?\n2. Split calves?", display = "Please answer the questions below."))
  state$pending_questions <- list(list(id = 1, kind = "ai", text = "Which year?", answer = NULL),
                                  list(id = 2, kind = "ai", text = "Split calves?", answer = NULL))
  state$q_index <- 1L
  card <- as.character(output$translator_qa_card$html)
  stopifnot(grepl("Question 1 of 2", card, fixed = TRUE), grepl("Which year?", card, fixed = TRUE))
  session$setInputs(translator_qa_answer = "2022"); session$setInputs(translator_qa_next = 1)
  stopifnot(identical(state$q_index, 2L), identical(state$pending_questions[[1]]$answer, "2022"))
  session$setInputs(translator_qa_back = 1); stopifnot(identical(state$q_index, 1L))
  session$setInputs(translator_qa_next = 2)
  session$setInputs(translator_qa_answer = "no, keep them pooled"); session$setInputs(translator_qa_next = 3)
  pump(state)
  ans <- state$messages[[3]]$content
  stopifnot(grepl("Answers to your questions", ans, fixed = TRUE), grepl("Answer: 2022", ans, fixed = TRUE),
            grepl("keep them pooled", ans, fixed = TRUE), sum(ai_calls == "chat") == 1L)
  stopifnot(length(state$pending_questions) == 1L, grepl("region", state$pending_questions[[1]]$text))
  stopifnot(identical(state$register$inventory_year$decision, "2022"))
  stopifnot(!grepl("```decisions", state$messages[[length(state$messages)]]$display, fixed = TRUE))
  cat("round 1: answers sent in one message, register has inventory_year\n")

  # ---- the fallback summariser: a reply without its block ------------------
  with_block <<- FALSE
  session$setInputs(translator_qa_answer = "Africa"); session$setInputs(translator_qa_next = 4)
  pump(state)
  stopifnot(sum(ai_calls == "summariser") == 1L, identical(state$register$uncertainty_source$decision, "file_bounds"))
  cat("round 2: no block in the reply, the summariser filled uncertainty_source\n")
  with_block <<- TRUE

  # ---- the Produce gate ------------------------------------------------------
  session$setInputs(translator_force_template = 1)   # AI question still open -> refused
  stopifnot(produce_calls == 0L, length(state$pending_questions) == 1L)
  session$setInputs(translator_qa_skip = 1); pump(state)
  state$pending_questions <- list()
  session$setInputs(translator_force_template = 2)   # required topics missing -> server questions
  stopifnot(produce_calls == 0L, length(state$pending_questions) >= 4L,
            all(vapply(state$pending_questions, function(q) q$kind, "") == "server"),
            !"uncertainty_source" %in% vapply(state$pending_questions, function(q) q$topic, ""))
  cat("gate asks:", paste(vapply(state$pending_questions, function(q) q$topic, ""), collapse = ", "), "\n")
  n <- length(state$pending_questions)
  for (k in seq_len(n)) {
    q <- state$pending_questions[[k]]
    ch <- .translator_topic_choices_for(q$topic)
    if (!is.null(ch)) session$setInputs(translator_qa_choice = ch[1]) else session$setInputs(translator_qa_answer = "all")
    session$setInputs(translator_qa_next = 10 + k)
  }
  stopifnot(produce_calls == 1L, length(state$pending_questions) == 0L, length(translator_register_missing(state$register)) == 0L)
  dec_msgs <- Filter(function(m) identical(m$source, "user_decision"), state$messages)
  stopifnot(length(dec_msgs) == n, grepl("^Decision: species = cattle_dairy", dec_msgs[[1]]$content))
  cat("gate: ", n, "server questions answered, Produce started once\n")

  # ---- the register card and the edit dialog ---------------------------------
  reg_html <- as.character(output$translator_register$html)
  stopifnot(grepl("What the AI will apply", reg_html, fixed = TRUE), grepl("you said", reg_html, fixed = TRUE))
  session$setInputs(translator_reg_edit = "inventory_year")
  session$setInputs(translator_reg_value = "2021", translator_reg_save = 1)
  stopifnot(identical(state$register$inventory_year$decision, "2021"), isTRUE(state$register$inventory_year$edited_by_user))
  saved <- conversation_load_full("loop@local")
  stopifnot(identical(saved$extra$register$inventory_year$decision, "2021"))

  # ---- WP7: a corrected template comes back with a note ----------------------
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
            grepl("NOTES FROM THE USER ABOUT THIS FILE", last_up$content, fixed = TRUE),
            grepl("Calves are one group", last_up$content, fixed = TRUE),
            grepl("Your notes: Calves are one group", last_up$display, fixed = TRUE),
            identical(state$register$corrected_template$basis, "user"),
            grepl("corrected_template.xlsx", state$register$corrected_template$decision, fixed = TRUE))
  cat("corrected template: recognised, checked, sent with the note; register entry written\n")
  cat("LOOP TEST PASSED\n")
})
