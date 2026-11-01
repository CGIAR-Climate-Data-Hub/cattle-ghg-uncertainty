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
modal_shown <- 0L
showModal <- function(...) { modal_shown <<- modal_shown + 1L; invisible(NULL) }
showNotification <- function(...) invisible(NULL)
removeModal <- function(...) invisible(NULL)
.translator_force_template <- function(state, session) { produce_calls <<- produce_calls + 1L; invisible(NULL) }
ai_calls <- character(); seen_hist <- list()
with_block <- TRUE
truncate_next <- FALSE
anthropic_chat_stream_async <- function(messages, on_chunk = function(text) {}, on_tick = function(n = 0L) {},
                                        should_stop = function() FALSE, on_result = function(res) {}, ...) {
  last <- messages[[length(messages)]]$content
  if (!is.character(last)) last <- paste(vapply(last, function(b) b$text %||% "", ""), collapse = " ")
  seen_hist[[length(seen_hist) + 1]] <<- messages
  usage <- list(prompt_tokens = 1L, completion_tokens = 1L, cached_tokens = 0L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L, total_tokens = 2L)
  base <- list(tool_used = FALSE, usage = usage, model = "stub", cost_usd = 0, latency_sec = 0.1, error = NULL, stopped = FALSE, stop_reason = "end_turn")
  if (grepl("The JSON array:", last, fixed = TRUE)) {
    ai_calls <<- c(ai_calls, "summariser")
    resp <- c(list(reply = "[{\"topic\": \"uncertainty_source\", \"decision\": \"file_bounds\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"use my bounds\"}]"), base)
  } else if (truncate_next) {
    ai_calls <<- c(ai_calls, "chat"); truncate_next <<- FALSE
    resp <- c(list(reply = "I read your file: 2 sheets.\n\n### A. File shape\n- x\n\n### B. Inventory of values found\n| N | a |\n| N | b |\n\n### D. Ambiguities to ask the user\n\n1. Which year is the inv"),
              base[setdiff(names(base), "stop_reason")], list(stop_reason = "max_tokens"))
  } else if (grepl("cut off by the output length limit", last, fixed = TRUE)) {
    ai_calls <<- c(ai_calls, "chat")
    resp <- c(list(reply = "Section D:\n\n1. Which year do you want for the point estimate?"), base)
  } else {
    ai_calls <<- c(ai_calls, "chat")
    reply <- "Thanks, noted.\n\n1. One more: which region is the herd in?\n\nPlease answer the section D questions, then click **Produce template now** when ready."
    # from the third reply on, the model rewords the year decision (same quote): not a new decision
    dec_year <- if (sum(ai_calls == "chat") >= 3L) "2022 (single year, confirmed)" else "2022"
    if (with_block) reply <- paste0(reply, "\n\n```decisions\n[{\"topic\": \"inventory_year\", \"decision\": \"", dec_year, "\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"2022\"},",
                                           " {\"topic\": \"oxen_handling\", \"decision\": \"kept as one group\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"one group\"},",
                                           " {\"topic\": \"species\", \"decision\": \"cattle_mixed\", \"basis\": \"file\", \"confidence\": \"high\", \"quote\": \"\"},",
                                           " {\"topic\": \"mms_split_source\", \"decision\": \"pending\", \"basis\": \"user\", \"confidence\": \"high\", \"quote\": \"\"}]\n```")
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
            identical(tail(src_of(state$messages), 2), c("user_answer", "server_question")), length(ai_calls) == 0L,
            sum(src_of(state$messages) == "user_answer") == 1L)
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
  disp <- function() vapply(state$messages, function(m) m$display %||% "", "")
  rec <- disp()[grepl("^Recorded: ", disp())]
  # one short line: the user's decisions in words, not the file reading, not the placeholder, no raw keys
  stopifnot(length(rec) == 1L, grepl("Inventory year: 2022", rec, fixed = TRUE), grepl("Oxen handling: kept as one group", rec, fixed = TRUE),
            !grepl("[?", rec, fixed = TRUE), !grepl("cattle_mixed|pending|Manure", rec), nchar(rec) < 200,
            identical(tail(s1, 1), "server_question"), length(state$pending_questions) == 1L)
  # the closing "please answer" line is not shown
  stopifnot(!any(grepl("Please answer the section D", disp(), fixed = TRUE)))
  cat("round 1: bubbles in the chat, answers batched, history filtered, one short recorded line\n")

  # ---- the fallback summariser: a reply without its block ------------------
  with_block <<- FALSE
  session$setInputs(translator_input = "Africa"); session$setInputs(translator_send = 3)
  pump(state)
  stopifnot(sum(ai_calls == "summariser") == 1L, identical(state$register$uncertainty_source$decision, "file_bounds"))
  with_block <<- TRUE
  # the stub asked the region question again: it was answered, so no new round
  stopifnot(length(state$pending_questions) == 0L, !identical(tail(src_of(state$messages), 1), "server_question"))
  n_rec <- sum(grepl("^Recorded: ", disp()))
  cat("round 2: summariser filled uncertainty_source; the repeated question was not put again\n")

  # a plain reply: the same decisions, reworded by the model, record nothing new
  session$setInputs(translator_input = "thanks"); session$setInputs(translator_send = 4); pump(state)
  stopifnot(sum(grepl("^Recorded: ", disp())) == n_rec, length(state$pending_questions) == 0L,
            identical(state$register$inventory_year$decision, "2022 (single year, confirmed)"),
            !is.null(state$recorded$inventory_year), !is.null(conversation_load_full("loop@local")$extra$recorded))
  cat("round 3: a reworded decision posts no second recorded line; the announced topics persist\n")

  # ---- a reply cut off at the output length limit: one continuation ----------
  n_chat <- sum(ai_calls == "chat")
  truncate_next <<- TRUE
  session$setInputs(translator_input = "explore again please"); session$setInputs(translator_send = 10)
  # the continuation is scheduled 0.2 s after the first reply: pump until its reply has settled
  t0 <- Sys.time()
  while (!(sum(ai_calls == "chat") >= n_chat + 2L && !isTRUE(state$pending)) && as.numeric(Sys.time() - t0, units = "secs") < 30) later::run_now(0.05)
  later::run_now(0.2)
  src4 <- src_of(state$messages); dsp4 <- disp()
  cut_i <- which(src4 == "user_continue")
  stopifnot(length(cut_i) == 1L, identical(state$messages[[cut_i]]$display, ""),
            grepl("cut off by the output length limit", state$messages[[cut_i]]$content, fixed = TRUE),
            any(grepl("cut off at the length limit", dsp4, fixed = TRUE)),
            sum(ai_calls == "chat") == n_chat + 2L)
  # the truncated bubble shows the orientation line, not the table; the continuation's question is the open one
  trunc_disp <- dsp4[cut_i - 2L]
  stopifnot(startsWith(trunc_disp, "I read your file: 2 sheets."), !grepl("### B", trunc_disp, fixed = TRUE), !grepl("| N | a |", trunc_disp, fixed = TRUE),
            length(state$pending_questions) == 1L, grepl("point estimate", state$pending_questions[[1]]$text, fixed = TRUE),
            identical(tail(src4, 1), "server_question"))
  # the continuation request reaches the API, the bubbles do not
  hist4 <- vapply(seen_hist[[length(seen_hist)]], function(m) if (is.character(m$content)) m$content else "", character(1))
  stopifnot(any(grepl("cut off by the output length limit", hist4, fixed = TRUE)))
  cat("cut-off reply: one continuation asked and answered; the table stays out of the bubble\n")
  session$setInputs(translator_input = "2022"); session$setInputs(translator_send = 11); pump(state)
  stopifnot(length(state$pending_questions) == 0L)

  # ---- the Produce gate: only the year is asked, then the delivery pop-up ----
  state$register$inventory_year <- NULL
  session$setInputs(translator_force_template = 1)
  stopifnot(produce_calls == 0L, isTRUE(state$produce_after_answers))
  asked <- vapply(state$pending_questions, function(q) q$topic, "")
  cat("gate asks:", paste(asked, collapse = ", "), "\n")
  stopifnot(identical(asked, "inventory_year"), is.null(state$register$calves_handling),
            identical(state$register$species$basis, "file"), identical(state$register$ipcc_edition$basis, "assumed"))
  stopifnot(identical(tail(src_of(state$messages), 1), "server_question"),
            sum(grepl("^Recorded: ", disp())) == n_rec)   # the assumptions are not announced
  session$setInputs(translator_input = "2022"); session$setInputs(translator_send = 5)
  stopifnot(identical(state$register$inventory_year$decision, "2022"), identical(state$register$inventory_year$basis, "user"))
  # the last answer does not start the run: the delivery pop-up comes first
  stopifnot(produce_calls == 0L, modal_shown == 1L, isTRUE(state$produce_after_ack), !isTRUE(state$delivery_ack),
            length(state$pending_questions) == 0L, length(translator_register_missing(state$register)) == 0L)
  # the decision line is kept for the AI but not drawn (the answer bubble is already there)
  dec <- Filter(function(m) identical(m$source, "user_decision"), state$messages)
  stopifnot(length(dec) == 1L, identical(dec[[1]]$display, ""), grepl("inventory_year = 2022", dec[[1]]$content, fixed = TRUE),
            !grepl("Decision: inventory_year", as.character(output$translator_messages$html), fixed = TRUE))
  session$setInputs(translator_dlv_continue = 1)
  stopifnot(produce_calls == 1L, isTRUE(state$delivery_ack), !isTRUE(state$produce_after_ack))
  cat("gate: one question, then the pop-up, then Produce started:", produce_calls, "\n")
  saved <- conversation_load_full("loop@local")
  stopifnot(identical(saved$extra$register$inventory_year$decision, "2022"))

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

  # ---- the past-translation button (2026-10-23) --------------------------------------
  fp_before <- state$source_fp
  state$last_template_json <- "{\"parameters\": []}"   # a template was ready
  stopifnot(!isTRUE(state$revising))                       # not offered in the first conversation
  session$setInputs(translator_revise = 1)                 # Back to the conversation
  stopifnot(isTRUE(state$revising), is.null(state$last_template_json),
            grepl("translator_past_file", as.character(output$translator_past_upload$html), fixed = TRUE))
  session$setInputs(translator_past_file = list(datapath = tpl, name = "past_translation.xlsx", size = file.size(tpl)))
  stopifnot(isTRUE(state$pending_upload$past), isTRUE(state$pending_upload$is_template), is.null(state$last_template_json),
            identical(state$source_fp, fp_before), !is.null(state$pending_upload$precheck))
  session$setInputs(translator_sheets = as.character(seq_len(n_sheets)), translator_upload_note = "Corrected the two adult cow populations.")
  session$setInputs(translator_send_sheets = 2)
  pump(state)
  up2 <- Filter(function(m) identical(m$source, "server_upload"), state$messages)
  stopifnot(grepl("CORRECTED TEMPLATE", up2[[length(up2)]]$content, fixed = TRUE), grepl("two adult cow", up2[[length(up2)]]$content, fixed = TRUE))
  csv <- file.path(tempdir(), "raw.csv"); write.csv(data.frame(a = 1:2), csv, row.names = FALSE)
  session$setInputs(translator_past_file = list(datapath = csv, name = "raw.csv", size = file.size(csv)))
  stopifnot(is.null(state$pending_upload))
  cat("past translation: taken next to the source, the source fingerprint kept, a raw file refused\n")

  # ---- the source_values gate (2026-10-31, Stage 3) -----------------------------------
  # Back to a plain conversation: a template-free state with a source_values
  # block and the sheets to check it against.
  state$revising <- FALSE; state$last_template_json <- NULL; state$pending_upload <- NULL
  state$pending_questions <- list(); state$produce_after_answers <- FALSE; state$delivery_ack <- TRUE
  df_g <- data.frame(a = c("Sys A", "Weight (kg)", "Cows", NA, "Sys A", "Mature weight (kg)", "Cows"),
                     `2022` = c(NA, NA, 410, NA, NA, NA, 450), check.names = FALSE, stringsAsFactors = FALSE)
  state$source_sheets <- list(list(name = "Data", json = .translator_table_to_json(df_g, "Data"), n_rows = nrow(df_g)))
  e_good <- list(system = "Sys A", label = "Cows", section = "Weight (kg)", sheet = "Data", row = 4L, col = "2022", mean = 410,
                 parameter = "BW", sub_category = "other_cows", aggregation_level = "sys_a")
  e_bad <- modifyList(e_good, list(row = 8L, mean = 450))   # the MW row offered as BW
  state$source_values <- list(e_good, e_bad); state$source_fix_done <- FALSE; state$source_gate <- NULL
  n_chat <- sum(ai_calls == "chat"); p0 <- produce_calls
  session$setInputs(translator_force_template = 2)
  pump(state); session$flushReact()
  # one corrective call went out (the stub replies without a block), Produce did not start
  fix_msg <- Filter(function(m) identical(m$source, "server_correction"), state$messages)
  stopifnot(sum(ai_calls == "chat") == n_chat + 1L, length(fix_msg) == 1L,
            grepl("^SOURCE CHECK: 1 entry", fix_msg[[1]]$content), produce_calls == p0, isTRUE(state$source_fix_done))
  # the block did not change, so after the round the gate fails again and the list is shown
  stopifnot(is.data.frame(state$source_gate) && nrow(state$source_gate) == 1L, produce_calls == p0,
            grepl("translator_produce_anyway", as.character(output$translator_source_gate$html), fixed = TRUE))
  session$setInputs(translator_produce_anyway = 1)
  stopifnot(produce_calls == p0 + 1L, is.null(state$source_gate))
  # a correct block passes the gate straight into Produce
  state$source_values <- list(e_good); state$source_fix_done <- FALSE
  session$setInputs(translator_force_template = 3)
  pump(state); session$flushReact()
  stopifnot(produce_calls == p0 + 2L, sum(ai_calls == "chat") == n_chat + 1L,
            is.null(state$source_status),   # 2026-11-01, evening: a clean check shows no line
            any(vapply(state$messages, function(m) identical(m$content, "(all set)"), logical(1))))   # the closing bubble
  cat("source gate: one corrective round, then the list and Produce anyway; a right block goes straight through\n")
  cat("LOOP TEST PASSED\n")
})
