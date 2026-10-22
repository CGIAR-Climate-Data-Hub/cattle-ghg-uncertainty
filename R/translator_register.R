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
# Revised the same day: only these two are put to the user when nothing has
# settled them; the others are assumed with the text below, said in one
# line in the conversation, and corrected by replying. Seven questions
# before every Produce was too many.
# 2026-10-22, later the same day: calves are not asked either. The
# one-category rule in the prompt settles them (one source category
# becomes one template category, never a split the file does not make),
# and asking after the user had confirmed everything sent the
# conversation round in circles.
.TRANSLATOR_ASK_TOPICS <- c("inventory_year")
.TRANSLATOR_ASSUMED <- list(
  species            = "the species as mapped from the file",
  ipcc_edition       = "as in the file, else the latest IPCC edition",
  aggregation_level  = "all production systems in the file",
  mms_split_source   = "from the file where present, else the IPCC default split",
  uncertainty_source = "the file's ranges where given, IPCC catalogue ranges elsewhere")

# Fill the assumable topics that have no decision with their assumption
# (basis "assumed"). Returns the register and the topics added.
translator_register_assume_defaults <- function(register) {
  register <- register %||% list(); added <- character(0)
  for (tp in names(.TRANSLATOR_ASSUMED)) {
    e <- register[[tp]]
    if (!is.null(e) && identical(e$status, "decided")) next
    register[[tp]] <- list(topic = tp, decision = .TRANSLATOR_ASSUMED[[tp]], basis = "assumed",
                           confidence = "medium", status = "decided", quote = "",
                           set_at = .translator_now(), msg_index = NA_integer_,
                           edited_by_user = FALSE, applied = NULL, applied_note = NULL)
    added <- c(added, tp)
  }
  list(register = register, added = added)
}

# What the API sees: the upload, the typed messages, the batched answers
# and the decisions; not the question bubbles, the per-question answers
# (the batch carries them) or the server's notices.
.translator_api_history <- function(msgs) {
  Filter(function(m) !(m$source %||% "") %in% c("server_question", "server_notice", "user_answer"), msgs)
}

# One question as a bubble in the conversation.
.translator_q_bubble <- function(state, i) {
  qs <- state$pending_questions; q <- qs[[i]]
  txt <- sprintf(t("ai_q_bubble"), i, length(qs), q$text)
  ch <- if (identical(q$kind, "server")) .translator_topic_choices_for(q$topic) else NULL
  if (!is.null(ch))
    txt <- paste0(txt, "\n", sprintf(t("ai_q_choices"),
                                     paste(vapply(ch, .translator_choice_label, character(1)), collapse = " / ")))
  state$messages[[length(state$messages) + 1L]] <-
    list(role = "assistant", content = txt, display = txt, source = "server_question", ts = .translator_now())
  invisible(NULL)
}

# Start a round: the notice bubble, then the first question.
.translator_begin_round <- function(state, notice) {
  state$q_index <- 1L
  state$messages[[length(state$messages) + 1L]] <-
    list(role = "assistant", content = notice, display = notice, source = "server_notice", ts = .translator_now())
  .translator_q_bubble(state, 1L)
  invisible(NULL)
}

# A one-line bubble with what the user's answers settled, when a reply
# recorded something new from them. Only the user's own decisions are
# said (basis "user"); what the model read from the file or assumed is in
# the checks workbook. A decision already recorded, or one that is only a
# placeholder ("pending"), is not repeated. At most six items.
.translator_post_recorded <- function(state, before) {
  before <- before %||% list(); after <- state$register %||% list()
  changed <- Filter(function(tp) {
    a <- after[[tp]]; b <- before[[tp]]
    identical(a$basis, "user") && identical(a$status, "decided") &&
      .translator_decision_is_real(a$decision) &&
      (is.null(b) || !identical(.translator_norm_text(b$decision), .translator_norm_text(a$decision)))
  }, names(after))
  if (!length(changed)) return(invisible(NULL))
  parts <- vapply(changed, function(tp)
    sprintf("%s: %s", .translator_topic_label(tp), .translator_decision_text(after[[tp]]$decision)), character(1))
  if (length(parts) > 6L) parts <- c(parts[1:6], sprintf(t("ai_q_recorded_more"), length(parts) - 6L))
  txt <- sprintf(t("ai_q_recorded"), paste(parts, collapse = "; "))
  state$messages[[length(state$messages) + 1L]] <-
    list(role = "assistant", content = txt, display = txt, source = "server_notice", ts = .translator_now())
  invisible(NULL)
}
.translator_norm_text <- function(x) trimws(gsub("[^a-z0-9]+", " ", tolower(x %||% "")))
.translator_decision_is_real <- function(d) {
  d <- .translator_norm_text(d)
  nzchar(d) && !grepl("^(pending|tbd|to be (decided|confirmed|determined)|unknown|not (yet )?(decided|known)|n a|none)( .*)?$", d, perl = TRUE)
}
.translator_decision_text <- function(d) {
  d <- gsub("\\s+", " ", trimws(as.character(d %||% "")))
  if (nchar(d) > 90L) paste0(substr(d, 1L, 87L), "...") else d
}

# The questions the user has answered in this conversation: the first line
# of each question in the batched answers messages, normalised.
.translator_answered_questions <- function(msgs) {
  out <- character(0)
  for (m in msgs) {
    if (!identical(m$source %||% "", "answers_batch")) next
    lines <- strsplit(m$content %||% "", "\n", fixed = TRUE)[[1]]
    qs <- sub("^\\s*\\d+[.)]\\s+", "", lines[grepl("^\\s*\\d+[.)]\\s+\\S", lines, perl = TRUE)], perl = TRUE)
    out <- c(out, .translator_norm_text(qs))
  }
  unique(out[nzchar(out)])
}
# Which of the new questions were already answered (same first line, or
# one the start of the other when the shorter is long enough to be the same
# question reworded).
.translator_question_seen <- function(qs, answered) {
  if (!length(qs) || !length(answered)) return(rep(FALSE, length(qs)))
  firsts <- .translator_norm_text(vapply(qs, function(q) strsplit(q, "\n", fixed = TRUE)[[1]][1], character(1)))
  vapply(firsts, function(f) {
    if (!nzchar(f)) return(FALSE)
    any(f == answered |
        (pmin(nchar(f), nchar(answered)) >= 20L & (startsWith(f, answered) | startsWith(answered, f))))
  }, logical(1), USE.NAMES = FALSE)
}
# The reply without its closing instruction to answer: the app puts the
# questions one at a time, so the line only confuses.
.translator_strip_answer_prompt <- function(text) {
  if (is.null(text) || !nzchar(text)) return(text)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  drop <- grepl("^\\s*[*_]*\\s*(please )?(answer|reply to|respond to) (the )?(section d |above |these |my |numbered )*questions?\\b", lines, ignore.case = TRUE, perl = TRUE) |
          grepl("^\\s*[*_]*\\s*(merci de |veuillez )?r.pond(ez|re) (aux|. la) questions?\\b", lines, ignore.case = TRUE, perl = TRUE)
  out <- paste(lines[!drop], collapse = "\n")
  gsub("\\n{3,}", "\n\n", trimws(out))
}

.translator_is_skip <- function(txt) {
  grepl("^\\s*(skip|pass|default|idk|i do not know|i don't know|je ne sais pas|-)\\s*[.!]?\\s*$", tolower(txt), perl = TRUE)
}

# Map a typed answer to one of a server question's choices when it clearly
# names one; otherwise keep the text.
.translator_parse_choice <- function(q, txt) {
  ch <- if (identical(q$kind, "server")) .translator_topic_choices_for(q$topic) else NULL
  if (is.null(ch)) return(trimws(txt))
  low <- tolower(txt)
  labs <- tolower(vapply(ch, .translator_choice_label, character(1)))
  hit <- which(vapply(seq_along(ch), function(k)
    grepl(ch[k], low, fixed = TRUE) || grepl(gsub("_", " ", ch[k]), low, fixed = TRUE) ||
      grepl(substr(labs[k], 1, 12), low, fixed = TRUE), logical(1)))
  if (length(hit) == 1L) return(ch[hit])
  kw <- list(percent = "percent|%|pourcent", fraction = "fraction",
             pooled = "pool|together|one group|single|un seul|regroup|ensemble",
             split_as_in_file = "split|separate|s\u00e9par|male",
             cattle_dairy = "^\\s*dairy|laitier", cattle_non_dairy = "non.?dairy|beef|viande|non laitier",
             cattle_mixed = "both|mixed|mixte|all|les deux",
             `2006` = "2006", `2019_refinement` = "2019|refine|affine",
             herd_wide_from_file = "herd|whole|entire|same|tout le|m\u00eame",
             per_subcategory_from_file = "per |each|chaque|sub", ipcc_default_split = "default|ipcc|d\u00e9faut",
             file_bounds = "file|bound|fichier|borne", catalogue_ranges = "catalog|ipcc", mixed = "mix")
  for (c_ in ch) if (!is.null(kw[[c_]]) && grepl(kw[[c_]], low, perl = TRUE)) return(c_)
  trimws(txt)
}

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
  if (.translator_missing_string(q)) return(sprintf(t("ai_q_generic"), .translator_humanise(topic)))
  if (nzchar(detail)) q <- sprintf(q, detail)
  q
}

# The label of a topic: the translated one for the known topics, else the
# topic name in words (the model may invent a topic such as
# oxen_handling; it must never show as "[?ai_topic_oxen_handling?]").
.translator_topic_label <- function(topic) {
  kind <- .translator_topic_kind(topic)
  lab <- t(paste0("ai_topic_", kind))
  if (.translator_missing_string(lab)) lab <- .translator_humanise(kind)
  detail <- sub("^[^:]*:?", "", topic)
  if (nzchar(detail)) paste0(lab, ": ", detail) else lab
}
.translator_missing_string <- function(s) grepl("^\\[\\?.*\\?\\]$", s %||% "")
.translator_humanise <- function(x) {
  x <- trimws(gsub("[_-]+", " ", x %||% ""))
  if (!nzchar(x)) return(x)
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
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
  for (tp in .TRANSLATOR_ASK_TOPICS) {
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
  # the closing instruction to answer is not part of the last question
  blocks <- vapply(blocks, .translator_strip_answer_prompt, character(1), USE.NAMES = FALSE)
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
    on_result = function(resp) shiny::withReactiveDomain(session, shiny::isolate({
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
    })))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Enforcement (WP1 step 4)
# ---------------------------------------------------------------------------

.translator_norm_key <- function(x) gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x))))

.translator_check_frame <- function() data.frame(
  topic = character(0), expected = character(0), found = character(0),
  where = character(0), ok = logical(0), hard = logical(0), stringsAsFactors = FALSE)

# Compare the register with an emitted piece (a batch, or the full/merged
# template). One row per decision checked; `hard` rows trigger a re-emit.
translator_register_check <- function(register, piece, level = NULL) {
  register <- register %||% list()
  if (!length(register) || is.null(piece)) return(.translator_check_frame())
  rows <- list()
  add <- function(topic, expected, found, where, ok, hard = TRUE)
    rows[[length(rows) + 1L]] <<- data.frame(topic = topic, expected = expected, found = found,
                                             where = where, ok = ok, hard = hard,
                                             stringsAsFactors = FALSE)
  ps <- piece$parameters; mm <- piece$manure_management
  lv <- if (!is.null(level) && nzchar(level)) level else "(template)"
  decided <- function(tp) { e <- register[[tp]]; !is.null(e) && identical(e$status, "decided") }

  # calves: pooled means never both halves in one production system
  if (decided("calves_handling")) {
    d <- tolower(register$calves_handling$decision)
    pooled <- !grepl("^split", d) &&
      grepl("pooled|do not split|don.t split|not split|together|one categor|as in the file|single", d)
    if (pooled && is.data.frame(ps) && "sub_category" %in% names(ps)) {
      lvls <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level) else rep("", nrow(ps))
      lvls[is.na(lvls)] <- ""
      for (L in unique(lvls)) {
        sc <- unique(as.character(ps$sub_category[lvls == L]))
        both <- all(c("calves_male", "calves_female") %in% sc)
        add("calves_handling", "one calves category per production system (pooled)",
            if (both) "calves_male and calves_female both emitted" else "one calves category",
            if (nzchar(L)) L else lv, !both)
      }
    }
  }

  # manure shares: herd-wide means the same split on every sub-category
  if (decided("mms_split_source") &&
      grepl("herd.?wide|whole herd|same split|single split", tolower(register$mms_split_source$decision)) &&
      is.data.frame(mm) && all(c("sub_category", "mms_type", "fraction_pct") %in% names(mm)) && nrow(mm)) {
    lvls <- if ("aggregation_level" %in% names(mm)) as.character(mm$aggregation_level) else rep("", nrow(mm))
    lvls[is.na(lvls)] <- ""
    for (L in unique(lvls)) {
      sub <- mm[lvls == L, , drop = FALSE]
      sigs <- tapply(seq_len(nrow(sub)), as.character(sub$sub_category), function(i)
        paste(sort(paste(sub$mms_type[i], round(suppressWarnings(as.numeric(sub$fraction_pct[i])), 3))), collapse = ";"))
      ok <- length(unique(sigs)) <= 1L
      add("mms_split_source", "the same manure split for every sub-category (herd-wide)",
          if (ok) "identical splits" else sprintf("%d different splits across %d sub-categories",
                                                  length(unique(sigs)), length(sigs)),
          if (nzchar(L)) L else lv, ok)
    }
  }

  # numeric decisions: topic value:<parameter>:<sub_category>
  for (nm in names(register)) {
    e <- register[[nm]]
    if (!identical(e$status, "decided") || !grepl("^value:", nm)) next
    parts <- strsplit(nm, ":", fixed = TRUE)[[1]]
    if (length(parts) < 3L) next
    want <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", e$decision)))
    if (!is.finite(want)) next
    if (!is.data.frame(ps) || !all(c("parameter", "sub_category", "mean") %in% names(ps))) next
    hit <- ps$parameter == parts[2] & .translator_norm_key(ps$sub_category) == .translator_norm_key(parts[3])
    if (!any(hit, na.rm = TRUE)) next
    got <- suppressWarnings(as.numeric(ps$mean[which(hit)]))
    ok <- all(is.finite(got)) && all(abs(got - want) <= 0.005 * max(1, abs(want)))
    add(nm, sprintf("%s = %s for %s", parts[2], format(want), parts[3]),
        paste(format(got), collapse = ", "), lv, ok)
  }

  # production systems kept: a soft check, level names are fuzzy
  if (decided("aggregation_level") && !is.null(level) && nzchar(level)) {
    d <- tolower(register$aggregation_level$decision)
    if (!grepl("^all\\b|every|tous", d)) {
      names_in <- .translator_norm_key(unlist(strsplit(d, "[,;/]|\\band\\b|\\bet\\b")))
      names_in <- names_in[nzchar(names_in)]
      if (length(names_in)) {
        ok <- any(vapply(names_in, function(n) grepl(n, .translator_norm_key(level), fixed = TRUE) ||
                                               grepl(.translator_norm_key(level), n, fixed = TRUE), logical(1)))
        add("aggregation_level", register$aggregation_level$decision, level, lv, ok, hard = FALSE)
      }
    }
  }

  if (!length(rows)) return(.translator_check_frame())
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

# Metadata the register settles outright: no re-emit needed, the server
# corrects the discovery result and records the decision as applied.
translator_register_apply_metadata <- function(register, md) {
  register <- register %||% list(); md <- md %||% list()
  corrections <- character(0)
  get <- function(tp) { e <- register[[tp]]; if (!is.null(e) && identical(e$status, "decided")) e$decision else NULL }
  yr <- get("inventory_year")
  if (!is.null(yr)) {
    y <- suppressWarnings(as.integer(gsub("[^0-9]", "", yr)))
    if (is.finite(y) && y >= 1900 && y <= 2100 && !identical(as.integer(.translator_scalar(md$year %||% NA)), y)) {
      md$year <- y; corrections <- c(corrections, "inventory_year")
    }
    if (is.finite(y)) register <- translator_register_mark(register, "inventory_year", TRUE, "server-corrected")
  }
  sp <- get("species")
  if (!is.null(sp) && sp %in% .translator_topic_choices("species")) {
    if (!identical(.translator_scalar(md$species %||% ""), sp)) { md$species <- sp; corrections <- c(corrections, "species") }
    register <- translator_register_mark(register, "species", TRUE, "server-corrected")
  }
  ed <- get("ipcc_edition")
  if (!is.null(ed)) {
    v <- if (grepl("2019", ed)) "2019_refinement" else if (grepl("2006", ed)) "2006" else NULL
    if (!is.null(v)) {
      if (!identical(.translator_scalar(md$ipcc_version %||% ""), v)) { md$ipcc_version <- v; corrections <- c(corrections, "ipcc_edition") }
      register <- translator_register_mark(register, "ipcc_edition", TRUE, "server-corrected")
    }
  }
  list(metadata = md, register = register, corrections = corrections)
}

translator_register_mark <- function(register, topic, applied, note = NULL) {
  register <- register %||% list()
  e <- register[[topic]]
  if (is.null(e)) return(register)
  # a decision found violated once stays marked unless a later check clears it explicitly
  e$applied <- isTRUE(applied)
  e$applied_note <- if (is.null(note)) e$applied_note else note
  register[[topic]] <- e
  register
}

.translator_decision_rejection <- function(viol, level) {
  items <- sprintf("'%s: %s' (found: %s)", viol$topic, viol$expected, viol$found)
  paste0("REJECTED for '", level, "': the user's binding decision(s) were not applied: ",
         paste(items, collapse = "; "), ". Re-emit the batch for '", level,
         "' now, honouring every decision in the BINDING DECISIONS block. ",
         "Same tool, mode = 'batch', same aggregation_level.")
}

# ---------------------------------------------------------------------------
# Source categories (WP2): the AI's own list of what the file contains
# ---------------------------------------------------------------------------

.TRANSLATOR_SOURCE_CATEGORIES_FENCE <- "```source_categories[ \\t]*\\n([\\s\\S]*?)\\n```"

# Entries: label (as in the file), system, sub_category, aggregation_level,
# merge_into (optional), confidence. NULL when there is no usable block.
.translator_extract_source_categories <- function(reply) {
  if (is.null(reply) || !nzchar(reply)) return(NULL)
  m <- regexpr(.TRANSLATOR_SOURCE_CATEGORIES_FENCE, reply, perl = TRUE)
  if (m < 0) return(NULL)
  fence <- regmatches(reply, m)
  inner <- sub("^```source_categories[ \\t]*\\n", "", fence, perl = TRUE)
  inner <- sub("\\n```$", "", inner)
  arr <- tryCatch(jsonlite::fromJSON(inner, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(arr)) return(NULL)
  if (!is.null(arr$label)) arr <- list(arr)
  out <- list()
  for (e in arr) {
    if (!is.list(e)) next
    lab <- trimws(as.character(e$label %||% ""))
    if (!nzchar(lab)) next
    out[[length(out) + 1L]] <- list(
      label = lab, system = trimws(as.character(e$system %||% e$aggregation_level %||% "")),
      sub_category = trimws(as.character(e$sub_category %||% "")),
      aggregation_level = trimws(as.character(e$aggregation_level %||% e$system %||% "")),
      merge_into = trimws(as.character(e$merge_into %||% "")),
      confidence = tolower(trimws(as.character(e$confidence %||% "medium"))))
  }
  if (!length(out)) NULL else out
}

.translator_strip_source_categories <- function(text) {
  if (is.null(text) || !nzchar(text)) return(text)
  gsub("\\n{3,}", "\n\n", trimws(gsub(.TRANSLATOR_SOURCE_CATEGORIES_FENCE, "", text, perl = TRUE)))
}
