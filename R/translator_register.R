# Decisions register for the AI translator (2026-10-22, WP1 of
# knowledge/24-translator-plan-2026-10-22.md).
#
# The user's answers to the AI's questions used to live only as plain chat
# messages: every emission call resent the transcript and nothing extracted
# or enforced them. The register is the structured home for those answers.
#
#   capture   the model ends each clarify reply with a fenced ```decisions
#             block (rule 11 of the in-app presentation rules); the server
#             parses it and merges it here. A user's own answer (basis
#             "user") is never overwritten by a file reading or a default.
#   ask       required topics with no decision, or an unclear one, are put
#             to the user one at a time before the template is produced
#             (translator_register_missing).
#   inject    translator_register_block() renders the register as the last
#             paragraph of every emission request, so it outranks the file
#             and the catalogue defaults.
#   enforce   translator_register_check() compares the emitted rows with
#             the register (WP1 step 4).
#
# One entry per topic:
#   list(topic, decision, basis = user | file | default | assumed | server,
#        confidence = high | medium | low, status = decided | unclear | pending,
#        quote, set_at, msg_index, edited_by_user, applied, applied_note)

.TRANSLATOR_REQUIRED_TOPICS <- c("species", "ipcc_edition", "inventory_year",
                                 "aggregation_level", "mms_split_source",
                                 "calves_handling", "uncertainty_source")

# Fixed choices per topic; NULL means free text.
.translator_topic_choices <- function(topic) {
  switch(topic,
    species            = c("cattle_dairy", "cattle_non_dairy", "cattle_mixed"),
    ipcc_edition       = c("2006", "2019_refinement"),
    mms_split_source   = c("herd_wide_from_file", "per_subcategory_from_file", "ipcc_default_split"),
    calves_handling    = c("pooled", "split_as_in_file"),
    uncertainty_source = c("file_bounds", "catalogue_ranges", "mixed"),
    NULL)
}

# Server-detected topics are named "<kind>:<detail>"; the kind decides the
# question text and the choices.
.translator_topic_kind <- function(topic) sub(":.*$", "", topic)

.translator_topic_question <- function(topic) {
  kind <- .translator_topic_kind(topic)
  key  <- paste0("ai_q_", kind)
  q <- t(key)
  detail <- sub("^[^:]*:?", "", topic)
  if (nzchar(detail)) q <- sprintf(q, detail)
  q
}

.translator_topic_label <- function(topic) {
  kind <- .translator_topic_kind(topic)
  lab <- t(paste0("ai_topic_", kind))
  detail <- sub("^[^:]*:?", "", topic)
  if (nzchar(detail)) paste0(lab, ": ", detail) else lab
}

.translator_choice_label <- function(choice) {
  key <- paste0("ai_q_choice_", choice)
  lab <- t(key)
  if (startsWith(lab, "[?")) choice else lab
}

.translator_topic_choices_for <- function(topic) {
  kind <- .translator_topic_kind(topic)
  if (identical(kind, "pct_vs_fraction")) return(c("percent", "fraction"))
  if (identical(kind, "category")) return(NULL)
  .translator_topic_choices(topic)
}

# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

.TRANSLATOR_DECISIONS_FENCE <- "```decisions[ \\t]*\\n([\\s\\S]*?)\\n```"

.translator_norm_decision <- function(e) {
  if (!is.list(e)) return(NULL)
  topic <- tolower(trimws(as.character(e$topic %||% "")))
  topic <- gsub("[^a-z0-9_:!./ -]", "", topic)
  topic <- gsub("[ -]+", "_", topic)
  decision <- trimws(as.character(e$decision %||% ""))
  if (!nzchar(topic) || !nzchar(decision)) return(NULL)
  basis <- tolower(trimws(as.character(e$basis %||% "assumed")))
  if (!basis %in% c("user", "file", "default", "assumed")) basis <- "assumed"
  conf <- tolower(trimws(as.character(e$confidence %||% "medium")))
  if (!conf %in% c("high", "medium", "low")) conf <- "medium"
  list(topic = topic, decision = decision, basis = basis, confidence = conf,
       quote = trimws(as.character(e$quote %||% "")))
}

# All decision entries in a reply, or NULL when there is no usable block.
# Every block is read (the model is asked for one, cumulative; two are
# merged in order), so a block placed mid-reply is still found.
.translator_extract_decisions <- function(reply) {
  if (is.null(reply) || !nzchar(reply)) return(NULL)
  ms <- gregexpr(.TRANSLATOR_DECISIONS_FENCE, reply, perl = TRUE)[[1]]
  if (length(ms) == 0 || ms[1] < 0) return(NULL)
  out <- list()
  for (k in seq_along(ms)) {
    fence <- substr(reply, ms[k], ms[k] + attr(ms, "match.length")[k] - 1L)
    inner <- sub("^```decisions[ \\t]*\\n", "", fence, perl = TRUE)
    inner <- sub("\\n```$", "", inner)
    arr <- tryCatch(jsonlite::fromJSON(inner, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (is.null(arr)) next
    if (!is.null(arr$topic)) arr <- list(arr)          # a single object
    for (e in arr) { n <- .translator_norm_decision(e); if (!is.null(n)) out[[length(out) + 1L]] <- n }
  }
  if (!length(out)) NULL else out
}

# The reply without its decisions block(s), for display.
.translator_strip_decisions <- function(text) {
  if (is.null(text) || !nzchar(text)) return(text)
  out <- gsub(.TRANSLATOR_DECISIONS_FENCE, "", text, perl = TRUE)
  gsub("\\n{3,}", "\n\n", trimws(out))
}

# ---------------------------------------------------------------------------
# The register
# ---------------------------------------------------------------------------

.translator_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Merge model-emitted entries. Later wins, except that a user's own answer
# is never replaced by a file reading, a default or an assumption.
translator_register_merge <- function(register, entries, msg_index = NA_integer_) {
  register <- register %||% list()
  for (e in entries) {
    cur <- register[[e$topic]]
    if (!is.null(cur) && identical(cur$basis, "user") && !identical(e$basis, "user")) next
    register[[e$topic]] <- list(
      topic = e$topic, decision = e$decision, basis = e$basis,
      confidence = e$confidence,
      status = if (identical(e$confidence, "low")) "unclear" else "decided",
      quote = e$quote %||% "", set_at = .translator_now(), msg_index = msg_index,
      edited_by_user = FALSE, applied = NULL, applied_note = NULL)
  }
  register
}

# A user's answer, from the question loop or the edit dialog.
translator_register_set_user <- function(register, topic, decision, quote = "",
                                         msg_index = NA_integer_, edited = FALSE) {
  register <- register %||% list()
  register[[topic]] <- list(
    topic = topic, decision = trimws(as.character(decision)), basis = "user",
    confidence = "high", status = "decided", quote = quote %||% "",
    set_at = .translator_now(), msg_index = msg_index,
    edited_by_user = isTRUE(edited), applied = NULL, applied_note = NULL)
  register
}

# A pending entry the server created from the upload (a conflict it found).
translator_register_add_pending <- function(register, topic, note = "") {
  register <- register %||% list()
  if (!is.null(register[[topic]]) && identical(register[[topic]]$basis, "user")) return(register)
  register[[topic]] <- list(
    topic = topic, decision = "", basis = "server", confidence = "low",
    status = "pending", quote = note %||% "", set_at = .translator_now(),
    msg_index = NA_integer_, edited_by_user = FALSE, applied = NULL, applied_note = NULL)
  register
}

# Keep the user's own decisions when a new file arrives; drop what the
# model read from the previous file.
translator_register_keep_user <- function(register) {
  Filter(function(e) identical(e$basis, "user"), register %||% list())
}

# Topics that must be settled before the template is produced: required
# topics with no decision or an unclear one, plus every pending entry.
translator_register_missing <- function(register) {
  register <- register %||% list()
  miss <- character(0)
  for (tp in .TRANSLATOR_REQUIRED_TOPICS) {
    e <- register[[tp]]
    if (is.null(e) || !identical(e$status, "decided")) miss <- c(miss, tp)
  }
  for (nm in names(register)) {
    e <- register[[nm]]
    if (!nm %in% miss && identical(e$status, "pending")) miss <- c(miss, nm)
  }
  miss
}

# The decided entries as the binding block appended to every emission
# request; "" when there is nothing to say.
translator_register_block <- function(register, level = NULL) {
  register <- register %||% list()
  if (!length(register)) return("")
  decided <- Filter(function(e) identical(e$status, "decided") && nzchar(e$decision), register)
  unclear <- Filter(function(e) identical(e$status, "unclear"), register)
  if (!length(decided) && !length(unclear)) return("")
  lines <- c(
    "BINDING DECISIONS (confirmed in this conversation). They override the",
    "uploaded file, the catalogue defaults and anything you assumed earlier.",
    "If a row would contradict one of them, follow the decision and tag that",
    "row data_source = 'user_chat'.")
  fmt <- function(e) {
    src <- switch(e$basis, user = "the user said", file = "from the file",
                  default = "IPCC default", assumed = "assumed", server = "server")
    q <- if (nzchar(e$quote %||% "")) sprintf(' ("%s")', substr(e$quote, 1, 120)) else ""
    sprintf("- %s: %s [%s%s]", e$topic, e$decision, src, q)
  }
  for (e in decided) lines <- c(lines, fmt(e))
  for (e in unclear)
    lines <- c(lines, sprintf("- UNRESOLVED %s: %s. Do not resolve this yourself: follow the file literally and tag affected rows data_source = 'placeholder'.",
                              e$topic, e$decision))
  if (!is.null(level) && nzchar(level))
    lines <- c(lines, sprintf("For this batch ('%s') the decisions above apply unchanged.", level))
  paste(lines, collapse = "\n")
}

# Short digest for the provenance stamp.
translator_register_digest <- function(register) {
  register <- register %||% list()
  if (!length(register)) return("")
  txt <- paste(vapply(register[order(names(register))], function(e)
    paste(e$topic, e$decision, e$basis, sep = "|"), character(1)), collapse = "\n")
  substr(.tp_sha256(txt), 1, 12)
}

# The register as a data frame (UI, checks workbook, Word report).
translator_register_df <- function(register) {
  register <- register %||% list()
  if (!length(register)) return(data.frame(topic = character(0), decision = character(0),
                                          basis = character(0), confidence = character(0),
                                          status = character(0), applied = character(0),
                                          note = character(0), stringsAsFactors = FALSE))
  rows <- lapply(register, function(e) data.frame(
    topic = e$topic, decision = e$decision %||% "", basis = e$basis %||% "",
    confidence = e$confidence %||% "", status = e$status %||% "",
    applied = if (is.null(e$applied)) "" else if (isTRUE(e$applied)) "yes" else "no",
    note = e$applied_note %||% "", stringsAsFactors = FALSE))
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

# ---------------------------------------------------------------------------
# Server-side scan at upload: columns that mix percent and fraction
# ---------------------------------------------------------------------------

# A header that says percent while every value sits in (0, 1], or a header
# that says fraction while values exceed 1, is a conflict the AI must ask
# about. Returns a character vector of "sheet!column" labels.
.translator_detect_pct_conflicts <- function(parsed) {
  if (is.null(parsed) || !length(parsed$sheets)) return(character(0))
  out <- character(0)
  for (sh in parsed$sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d)) next
    for (col in names(d)) {
      v <- .translator_cell_numbers(d[[col]])
      v <- v[is.finite(v)]
      if (length(v) < 2L) next
      says_pct  <- grepl("(^|[^a-z])(%|pct|percent|moe)([^a-z]|$)", tolower(col), perl = TRUE)
      says_frac <- grepl("frac|fraction|share", tolower(col), perl = TRUE)
      label <- paste0(sh$name %||% "sheet", "!", col)
      if (says_pct && all(v > 0 & v <= 1)) out <- c(out, label)
      else if (says_frac && any(v > 1.5)) out <- c(out, label)
    }
  }
  unique(out)
}

# ---------------------------------------------------------------------------
# Questions out of a reply
# ---------------------------------------------------------------------------

# The numbered items of a reply that read as questions, one string each.
# Same walker as .translator_extract_numbered_questions(), without the
# "at least two" and 30% gates: one question is still a question.
.translator_question_list <- function(content) {
  if (is.null(content) || !nzchar(content)) return(character(0))
  lines <- strsplit(content, "\n", fixed = TRUE)[[1]]
  is_numbered <- grepl("^\\s{0,3}\\d+[.)]\\s+\\S", lines, perl = TRUE)
  if (!any(is_numbered)) return(character(0))
  blocks <- character(0); cur <- character(0); in_block <- FALSE; blank <- 0L
  flush <- function() if (length(cur)) blocks <<- c(blocks, paste(cur, collapse = "\n"))
  for (i in seq_along(lines)) {
    ln <- lines[i]
    if (is_numbered[i]) { flush(); cur <- ln; in_block <- TRUE; blank <- 0L }
    else if (in_block) {
      if (!nzchar(trimws(ln))) { blank <- blank + 1L; if (blank >= 2L) { flush(); cur <- character(0); in_block <- FALSE; blank <- 0L } else cur <- c(cur, ln) }
      else { blank <- 0L; cur <- c(cur, ln) }
    }
  }
  flush()
  blocks <- trimws(blocks)
  blocks <- sub("^\\d+[.)]\\s+", "", blocks, perl = TRUE)
  blocks[grepl("\\?", blocks)]
}

# The reply without its numbered question blocks (what stays in the bubble
# while the questions are put one at a time).
.translator_strip_question_blocks <- function(content, questions) {
  if (is.null(content) || !length(questions)) return(content)
  out <- content
  for (q in questions) {
    first <- strsplit(q, "\n", fixed = TRUE)[[1]][1]
    # the block runs from its numbered line to the next numbered line or the
    # next blank line, whichever comes first
    out <- sub(paste0("(?m)^\\s{0,3}\\d+[.)]\\s+", .translator_regex_escape(first),
                      "[^\\n]*(\\n(?!\\s{0,3}\\d+[.)]\\s)[ \\t]*\\S[^\\n]*)*"),
               "", out, perl = TRUE)
  }
  gsub("\\n{3,}", "\n\n", trimws(out))
}

.translator_regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)

# The one message that carries a round of answers back to the AI.
.translator_answers_message <- function(questions) {
  lines <- "Answers to your questions:"
  for (i in seq_along(questions)) {
    q <- questions[[i]]
    first <- strsplit(q$text, "\n", fixed = TRUE)[[1]][1]
    a <- q$answer %||% ""
    if (!nzchar(a)) a <- "(no answer: use the IPCC default and say so)"
    lines <- c(lines, "", sprintf("%d. %s", i, first), sprintf("   Answer: %s", a))
  }
  paste(lines, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Fallback capture
# ---------------------------------------------------------------------------

# When a clarify reply carries no decisions block right after a user
# answer, one cheap call (no tools, temperature 0, the last six messages)
# asks for the array alone and merges it. Asynchronous; failures are
# logged and ignored, the register then simply waits for the next reply.
.translator_register_summarise_async <- function(state, session) {
  msgs <- state$messages
  if (!length(msgs)) return(invisible(NULL))
  recent <- utils::tail(msgs, 6L)
  transcript <- paste(vapply(recent, function(m) {
    c_ <- m$content
    if (!is.character(c_)) c_ <- paste(vapply(c_, function(b) b$text %||% "", ""), collapse = " ")
    sprintf("[%s] %s", toupper(m$role %||% "user"), substr(c_ %||% "", 1, 4000))
  }, character(1)), collapse = "\n\n")
  system_txt <- paste(
    "You read an excerpt of a conversation between an inventory compiler and",
    "an AI that maps cattle data into a template. List every decision the two",
    "made or confirmed in the excerpt as a JSON array and nothing else: no",
    "prose, no code fence. Fields: topic (snake_case; use species,",
    "ipcc_edition, inventory_year, aggregation_level, mms_split_source,",
    "calves_handling, uncertainty_source, pct_vs_fraction:<column> or",
    "category:<label> where they fit), decision, basis (user | file |",
    "default | assumed), confidence (high | medium | low), quote (the",
    "user's words, verbatim, or the file cell). Return [] if there is none.")
  req <- anthropic_build_messages(system_txt, history = list(),
                                  new_user_message = paste0("Excerpt:\n\n", transcript, "\n\nThe JSON array:"))
  msg_index <- length(msgs)
  anthropic_chat_stream_async(
    req, max_tokens = 1500, temperature = 0, timeout_sec = 120,
    on_result = function(resp) shiny::withReactiveDomain(session, {
      if (!is.null(resp$error) || is.null(resp$reply)) {
        message("translator: decisions summariser failed (", resp$error %||% "no reply", ")")
        return(invisible(NULL))
      }
      txt <- trimws(resp$reply)
      txt <- sub("^```[a-z]*[ \\t]*\\n", "", txt, perl = TRUE)
      txt <- sub("\\n```$", "", txt, perl = TRUE)
      arr <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(arr)) { message("translator: decisions summariser returned no JSON"); return(invisible(NULL)) }
      if (!is.null(arr$topic)) arr <- list(arr)
      entries <- Filter(Negate(is.null), lapply(arr, .translator_norm_decision))
      if (length(entries)) {
        state$register <- translator_register_merge(state$register, entries, msg_index = msg_index)
        tryCatch(.translator_persist(state), error = function(e) NULL)
      }
      tryCatch(.translator_log_usage(state, resp, stage = "decisions", expect_warm = FALSE),
               error = function(e) NULL)
      invisible(NULL)
    }))
  invisible(NULL)
}
