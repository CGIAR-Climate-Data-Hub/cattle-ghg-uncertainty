# A translation as a job (2026-10-22, WP5 and WP6 of
# knowledge/24-translator-plan-2026-10-22.md).
#
# The asynchronous emission chain already keeps running when the browser
# tab is closed (the callbacks run on the R process); what was lost was the
# result, kept only in the session. The job file is now the source of truth
# for a run: runtime/translator_jobs/<id>.json holds its stage, progress,
# estimate and, when it finishes, the three output files written into
# runtime/translator_jobs/<id>/. Any session of the same user (the one that
# started it, or one that reconnects later) reads the file; a 2 s poll shows
# the progress, and on completion the files are pushed to the browser if a
# session is open, or emailed to the signed-in address if none is.
#
# runtime/ is wiped when the shinyapps.io container recycles, like the
# conversation history; a job lost that way is reported as such.

.translator_jobs_dir <- function() {
  d <- file.path(.runtime_dir(), "translator_jobs")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}
.translator_job_path <- function(id) file.path(.translator_jobs_dir(), paste0(id, ".json"))
.translator_job_outdir <- function(id) {
  d <- file.path(.translator_jobs_dir(), id)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}
.translator_user_hash <- function(email) substr(.tp_sha256(tolower(trimws(email %||% ""))), 1, 32)

translator_job_new <- function(user_email, prompt_hash = NULL, emission_key = NULL) {
  id <- sprintf("job_%s_%s", format(Sys.time(), "%Y%m%d_%H%M%S"),
                substr(.tp_sha256(paste(user_email, Sys.time(), stats::runif(1))), 1, 6))
  job <- list(
    id = id, user_hash = .translator_user_hash(user_email), user_email = user_email,
    started_at = .translator_now(), updated_at = .translator_now(), finished_at = NULL,
    status = "running", stage = "discovery", stage_label = "Analysing the inventory structure",
    levels = character(0), level_index = 0L, progress = 0.02, eta_sec = NULL,
    estimate = NULL, actual = list(per_level_tokens = list(), per_level_sec = list()),
    prompt_hash = prompt_hash, emission_key = emission_key,
    outputs = list(), delivery = list(mode = NULL), warnings = character(0), error = NULL)
  translator_job_write(job)
  job
}

translator_job_write <- function(job) {
  path <- .translator_job_path(job$id)
  tmp <- paste0(path, ".tmp")
  ok <- tryCatch({
    jsonlite::write_json(job, tmp, auto_unbox = TRUE, null = "null", digits = NA, pretty = FALSE)
    file.rename(tmp, path)
  }, error = function(e) FALSE)
  invisible(isTRUE(ok))
}

translator_job_read <- function(id) {
  if (is.null(id) || !nzchar(id)) return(NULL)
  path <- .translator_job_path(id)
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
}

# Read, change the named fields, bump updated_at, write.
translator_job_update <- function(id, ...) {
  job <- translator_job_read(id)
  if (is.null(job)) return(invisible(NULL))
  changes <- list(...)
  for (nm in names(changes)) job[[nm]] <- changes[[nm]]
  job$updated_at <- .translator_now()
  translator_job_write(job)
  invisible(job)
}

# The newest job of a user, within max_age_hours; NULL when there is none.
translator_job_find <- function(user_email, max_age_hours = 48) {
  d <- .translator_jobs_dir()
  files <- list.files(d, pattern = "^job_.*[.]json$", full.names = TRUE)
  if (!length(files)) return(NULL)
  h <- .translator_user_hash(user_email)
  best <- NULL
  for (f in sort(files, decreasing = TRUE)) {
    j <- tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(j) || !identical(j$user_hash, h)) next
    age <- as.numeric(difftime(Sys.time(), as.POSIXct(j$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours"))
    if (is.finite(age) && age > max_age_hours) next
    best <- j; break
  }
  best
}

# A job still "running" that has not been touched for a while was lost
# with its process (a container recycle, a crash). Called at session start.
translator_job_mark_lost <- function(stale_min = 5) {
  d <- .translator_jobs_dir()
  for (f in list.files(d, pattern = "^job_.*[.]json$", full.names = TRUE)) {
    j <- tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(j) || !identical(j$status, "running")) next
    upd <- as.POSIXct(j$updated_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (is.na(upd)) next
    if (as.numeric(difftime(Sys.time(), upd, units = "mins")) > stale_min) {
      j$status <- "lost"; j$error <- "The server restarted while this translation was running. Please produce the template again."
      j$updated_at <- .translator_now()
      translator_job_write(j)
    }
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Sessions interested in a job (the one that started it, any that reconnects)
# ---------------------------------------------------------------------------

.TRANSLATOR_JOB_SESSIONS <- new.env(parent = emptyenv())

translator_job_register_session <- function(id, session) {
  if (is.null(id) || is.null(session)) return(invisible(NULL))
  cur <- .TRANSLATOR_JOB_SESSIONS[[id]] %||% list()
  cur[[length(cur) + 1L]] <- session
  .TRANSLATOR_JOB_SESSIONS[[id]] <- cur
  invisible(NULL)
}

.translator_session_open <- function(s) {
  if (is.null(s)) return(FALSE)
  closed <- tryCatch(isTRUE(s$isClosed()), error = function(e) TRUE)
  !closed
}

translator_job_open_session <- function(id) {
  for (s in .TRANSLATOR_JOB_SESSIONS[[id]] %||% list()) if (.translator_session_open(s)) return(s)
  NULL
}

# ---------------------------------------------------------------------------
# Estimate and progress (WP5)
# ---------------------------------------------------------------------------

# Expected output tokens per production system and the speed, from the
# discovery result and the usage log. All fallbacks are stated.
# 2026-10-23: the time series (one row per sub-category per year) was not
# counted, so a system with a 35-year series was judged "over" at half
# its real length; n_years comes from the source fingerprint's year
# columns. Manure rows: six systems per sub-category as a middle value.
translator_job_estimate <- function(levels, subcats_by_level = NULL, usage_df = NULL, n_years = 0) {
  levels <- as.character(levels %||% character(0))
  df <- usage_df
  num <- function(x) suppressWarnings(as.numeric(x))
  tok_per_sec <- 100; src <- "fallback"   # Sonnet 4.6 measured at about 110 tokens/s on 2026-10-23
  batch_tokens_hist <- numeric(0); enum_sec <- 25
  if (!is.null(df) && is.data.frame(df) && nrow(df) && all(c("stage", "completion_tokens", "latency_sec") %in% names(df))) {
    b <- df[df$stage %in% c("batch", "full", "retry_defaults_only", "retry_decision") &
            num(df$completion_tokens) > 2000 & num(df$latency_sec) > 0, , drop = FALSE]
    if (nrow(b)) {
      tok_per_sec <- stats::median(num(b$completion_tokens) / num(b$latency_sec)); src <- "usage_log"
      batch_tokens_hist <- num(b$completion_tokens)
    }
    e <- df[df$stage == "enumerate" & num(df$latency_sec) > 0, , drop = FALSE]
    if (nrow(e)) enum_sec <- stats::median(num(e$latency_sec))
  }
  n_params <- nrow(PARAM_CATALOGUE)
  # per sub-category: a parameter row is about 60 tokens of JSON, a manure
  # row 70 (eight systems), a time-series row 65 (the Zambia run of
  # 2026-10-23: 17,500 to 35,400 tokens per system of 5 or 6 sub-categories)
  n_years <- suppressWarnings(as.numeric(n_years %||% 0)); if (!is.finite(n_years)) n_years <- 0
  ts_tokens <- if (n_years > 1) n_years * 65 else 0
  per_level <- vapply(levels, function(lv) {
    sc <- subcats_by_level[[lv]]
    if (!is.null(sc) && length(sc)) length(unique(unlist(sc))) * (n_params * 60 + 8 * 70 + ts_tokens) + 400
    else if (length(batch_tokens_hist)) stats::median(batch_tokens_hist)
    else 9000
  }, numeric(1))
  n_rows <- sum(vapply(levels, function(lv) { sc <- subcats_by_level[[lv]]; if (!is.null(sc)) length(unique(unlist(sc))) else 6L }, numeric(1))) * n_params
  list(tok_per_sec = max(5, tok_per_sec), per_level_tokens = as.list(per_level),
       total_tokens = sum(per_level), discovery_sec = enum_sec,
       assemble_sec = 60 + 0.12 * n_rows, delivery_sec = 5, source = src)   # 729 rows took about 2.7 min
}

# Progress fraction and remaining time, from what has been emitted so far.
# 2026-10-23: a system that runs past its token estimate used to freeze
# the bar and the time left ("about 2 min left" for a quarter of an hour).
# Now the bar keeps creeping towards, never reaching, the end of that
# system, the time left says "running longer than estimated", and once
# systems have finished their measured durations (level_secs, with the
# time spent on the current one in level_elapsed) replace the token
# arithmetic for the systems still to come.
translator_job_progress <- function(est, level_index, n_levels, done_tokens, level_bytes = 0, scale = 1,
                                    level_elapsed = NA_real_, level_secs = numeric(0)) {
  if (is.null(est) || !n_levels) return(list(progress = 0.05, eta_sec = NA_real_, eta_text = "", label = "", over = FALSE))
  per <- unlist(est$per_level_tokens) * scale
  total <- sum(per)
  cur_est <- if (level_index >= 1 && level_index <= length(per)) per[level_index] else 0
  cur_seen <- level_bytes / 3.6
  past <- is.finite(cur_est) && cur_est > 0 && cur_seen > cur_est
  # "running longer than estimated" only well past the estimate (1.5x):
  # an estimate is rough, and the note fired at three minutes (2026-10-23)
  over <- past && cur_seen > 1.5 * cur_est
  # the current system is credited at most 90% of its estimate until it is
  # done, so the bar never claims a system is finished before it is
  if (past) {
    # the share reached at the estimate, then a slow creep towards the rest
    frac_base <- if (total > 0) min(1, (done_tokens + 0.9 * cur_est) / total) else 0
    frac <- frac_base + (1 - frac_base) * (1 - cur_est / cur_seen) * 0.9
    remaining_tokens <- max(0, total - done_tokens - cur_est)
  } else {
    tokens_done <- done_tokens + min(cur_seen, 0.9 * cur_est)
    frac <- if (total > 0) tokens_done / total else 0
    remaining_tokens <- max(0, total - done_tokens - min(cur_seen, cur_est))
  }
  # The time left: the tokens still to come (the systems after this one,
  # plus what is left of this one, a 15% tail once past its estimate) at
  # the rate measured on the finished systems, else the usage-log rate.
  # Systems differ in size, so the finished ones give a RATE, not a mean
  # duration: a mean made the time left grow after every bigger system
  # (2026-10-23). Within a system the figure only falls.
  after_tokens <- if (level_index >= 1 && level_index < length(per))
    sum(per[(level_index + 1L):length(per)], na.rm = TRUE) else 0
  cur_left_tokens <- if (!is.finite(cur_est) || cur_est <= 0) 0
                     else if (past) 0.15 * cur_est * (cur_est / cur_seen)   # a shrinking tail
                     else max(cur_est - cur_seen, 0.15 * cur_est)
  rate <- if (length(level_secs) && done_tokens > 0 && sum(level_secs) > 0) done_tokens / sum(level_secs) else est$tok_per_sec
  rate <- max(rate, 1)
  eta <- (after_tokens + cur_left_tokens) / rate + est$assemble_sec + est$delivery_sec
  if (length(level_secs) && is.finite(level_elapsed) && is.finite(cur_est) && cur_est > 0 &&
      level_elapsed > 1.25 * cur_est / rate) over <- TRUE
  progress <- 0.05 + 0.88 * max(0, min(1, frac))
  eta_text <- if (eta < 60) t("ai_job_eta_under_min") else sprintf(t("ai_job_eta_min"), ceiling(eta / 60))
  if (over) eta_text <- paste0(eta_text, " (", t("ai_job_eta_over"), ")")
  else if (identical(est$source, "fallback")) eta_text <- paste0(eta_text, " (first-run estimate)")
  list(progress = progress, eta_sec = eta, eta_text = eta_text, over = over,
       label = sprintf("system %d of %d", max(level_index, 1L), n_levels))
}

# ---------------------------------------------------------------------------
# Completion and delivery (WP6)
# ---------------------------------------------------------------------------

# Write the three files into the job folder, mark the job done, and deliver:
# to an open session of the user (automatic download or chosen folder), or
# by email when none is open.
translator_job_finish <- function(job_id, state, session) {
  if (is.null(job_id)) return(invisible(NULL))
  job <- translator_job_read(job_id)
  if (is.null(job)) return(invisible(NULL))
  dir <- .translator_job_outdir(job_id)
  js <- shiny::isolate(state$last_template_json)
  piece <- tryCatch(jsonlite::fromJSON(js, simplifyVector = TRUE), error = function(e) NULL)
  nm <- list(template = translator_output_filename(piece, "template"),
             checks = translator_output_filename(piece, "checks"),
             conversation = translator_output_filename(piece, "conversation"))
  outputs <- list()
  tpl <- shiny::isolate(state$template_file)
  if (!is.null(tpl) && file.exists(tpl) &&
      isTRUE(file.copy(tpl, file.path(dir, nm$template), overwrite = TRUE)))
    outputs$template <- file.path(dir, nm$template)
  pc <- shiny::isolate(state$precheck)
  ok_c <- tryCatch({
    translator_write_checks_xlsx(
      pc %||% list(), shiny::isolate(state$register), file.path(dir, nm$checks),
      extra = list(model = .translator_scalar(piece$.model %||% ""),
                   prompt_hash = job$prompt_hash %||% "",
                   register_digest = translator_register_digest(shiny::isolate(state$register))))
    TRUE }, error = function(e) { message("translator: checks workbook failed (", conditionMessage(e), ")"); FALSE })
  if (ok_c) outputs$checks <- file.path(dir, nm$checks)
  ok_d <- tryCatch({ translator_write_conversation_docx(shiny::isolate(state$messages), file.path(dir, nm$conversation)); TRUE },
                   error = function(e) { message("translator: conversation document failed (", conditionMessage(e), ")"); FALSE })
  if (ok_d) outputs$conversation <- file.path(dir, nm$conversation)

  job <- translator_job_update(job_id, status = "done", stage = "done", stage_label = "Done",
                               progress = 1, eta_sec = 0, finished_at = .translator_now(),
                               outputs = outputs)
  s <- translator_job_open_session(job_id)
  if (!is.null(s)) {
    files <- list(list(key = "template", output_id = "translator_download_template", name = nm$template),
                  list(key = "checks", output_id = "translator_download_checks", name = nm$checks),
                  list(key = "conversation", output_id = "translator_download_conversation", name = nm$conversation))
    sent <- tryCatch({ s$sendCustomMessage("translatorJobDone", list(id = job_id, files = files, auto = "template")); TRUE },
                     error = function(e) { message("translator: delivery message failed (", conditionMessage(e), ")"); FALSE })
    message("translator: job ", job_id, " done; files sent to the browser: ", sent)
    translator_job_update(job_id, delivery = list(mode = if (sent) "browser" else "none",
                                                  browser_notified_at = if (sent) .translator_now() else NULL))
    if (sent) return(invisible(job))
  }
  message("translator: job ", job_id, " done; no open session, sending the files by email")
  translator_job_email(job_id, shiny::isolate(state$user_email))
  invisible(job)
}

# A run that failed while no page was open (2026-10-31): the user is told
# by email instead of finding a clock still running when they come back.
translator_job_email_failure <- function(job_id, to, msg) {
  if (is.null(to) || !nzchar(to)) return(invisible(NULL))
  body <- c(
    "Your AI translator run stopped before the template was produced.",
    "",
    paste0("Reason: ", msg),
    "",
    "Sign in again and open the AI translator. Your conversation and answers are kept, and the production systems that were already finished are reused, so clicking 'Produce template now' only repeats the rest.")
  res <- tryCatch(.auth_send_email(to, "Your AI translator run stopped", paste(body, collapse = "\n")),
                  error = function(e) list(ok = FALSE, attempts = conditionMessage(e)))
  translator_job_update(job_id, delivery = list(mode = "email_failure",
    email_sent_at = if (isTRUE(res$ok)) .translator_now() else NULL))
  if (!isTRUE(res$ok)) message("translator: failure email failed: ", paste(res$attempts, collapse = "; "))
  invisible(res)
}

# Email the outputs to the signed-in address: data workbook, checks, then
# the conversation, dropping from the end while the encoded total exceeds
# the first provider's limit (Brevo, 10 MB). If even the data workbook is
# too big, a text-only mail says the files are waiting in the app.
translator_job_email <- function(job_id, to, limit_bytes = 9 * 1024^2) {
  job <- translator_job_read(job_id)
  if (is.null(job) || is.null(to) || !nzchar(to)) return(invisible(NULL))
  order <- c("template", "checks", "conversation")
  paths <- unlist(job$outputs[order[order %in% names(job$outputs)]])
  paths <- paths[file.exists(paths)]
  atts <- lapply(paths, function(p) list(path = p, name = basename(p),
    type = if (grepl("[.]docx$", p)) "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
           else "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
  enc_size <- function(a) sum(vapply(a, function(x) ceiling(file.size(x$path) * 4 / 3), numeric(1)))
  while (length(atts) && enc_size(atts) > limit_bytes) atts <- atts[-length(atts)]
  dropped <- setdiff(basename(paths), vapply(atts, function(a) a$name, character(1)))
  md_digest <- ""
  body <- c(
    "Your translated template is ready.",
    "",
    if (length(atts)) c("Attached:", paste0("- ", vapply(atts, function(a) a$name, character(1)))) else
      "The files are too large for email; they are waiting in the app.",
    if (length(dropped)) c("", "Too large for this email, waiting in the app:", paste0("- ", dropped)),
    "",
    "Open the data workbook and go through the Check column; the checks workbook lists every point to review, and the conversation document keeps the questions and your answers.",
    "",
    if (length(job$warnings)) c("Notes from the run:", paste0("- ", unlist(job$warnings)), ""),
    "The files also stay in the app (sign in again and open the AI translator) until the server restarts.")
  res <- tryCatch(.auth_send_email(to, "Your translated template is ready", paste(body, collapse = "\n"),
                                   attachments = atts),
                  error = function(e) list(ok = FALSE, provider = NA_character_, attempts = conditionMessage(e)))
  translator_job_update(job_id, delivery = list(
    mode = "email", email_sent_at = if (isTRUE(res$ok)) .translator_now() else NULL,
    email_provider = res$provider %||% NA_character_,
    email_error = if (isTRUE(res$ok)) NULL else paste(res$attempts, collapse = "; "),
    attached = vapply(atts, function(a) a$name, character(1))))
  if (!isTRUE(res$ok)) message("translator: result email failed: ", paste(res$attempts, collapse = "; "))
  invisible(res)
}
