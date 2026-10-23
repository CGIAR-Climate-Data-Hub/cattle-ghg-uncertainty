# Usage: Rscript scripts/test_translator_jobs.R   (no API call, about 30 s)
# WP5 (estimate, progress) and WP6 (job file, mail attachments, trimming).
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
td <- tempfile("jobs"); dir.create(td)

# ---- estimate and progress ---------------------------------------------------------
ul <- data.frame(stage = c("batch", "batch", "enumerate", "explore"), completion_tokens = c(8000, 12000, 500, 1000),
                 latency_sec = c(200, 400, 20, 30), stringsAsFactors = FALSE)
est <- translator_job_estimate(c("a", "b"), list(a = c("bulls", "cows"), b = c("bulls")), ul)
ok(identical(est$source, "usage_log") && abs(est$tok_per_sec - 35) < 1 && est$discovery_sec == 20, "estimate: speed and discovery time from the usage log medians")
ok(est$per_level_tokens$a > est$per_level_tokens$b && est$total_tokens == est$per_level_tokens$a + est$per_level_tokens$b, "estimate: more sub-categories, more tokens")
est0 <- translator_job_estimate(c("a", "b"), NULL, NULL)
ok(identical(est0$source, "fallback") && est0$tok_per_sec == 100 && est0$per_level_tokens$a == 9000, "estimate: fallbacks with no history and no sub-categories")
pr0 <- translator_job_progress(est, 1L, 2L, 0, 0)
pr1 <- translator_job_progress(est, 2L, 2L, est$per_level_tokens$a, 0)
pr2 <- translator_job_progress(est, 2L, 2L, est$per_level_tokens$a, est$per_level_tokens$b * 3.6)
ok(pr0$progress < pr1$progress && pr1$progress < pr2$progress && pr2$progress <= 0.93 && grepl("min left|minute left", pr1$eta_text), "progress is monotone and carries an ETA text")
ok(grepl("first-run estimate", translator_job_progress(est0, 1L, 2L, 0, 0)$eta_text, fixed = TRUE), "a fallback estimate says so")
# the time series counts: a 35-year file is a bigger job than a single year
est35 <- translator_job_estimate(c("a", "b"), list(a = c("bulls", "cows"), b = c("bulls")), ul, n_years = 35)
ok(est35$per_level_tokens$a > 1.5 * est$per_level_tokens$a && est35$per_level_tokens$a == est$per_level_tokens$a + 2 * 35 * 65,
   "the estimate grows with the years of the time series")
# just past the estimate: the bar creeps on, no note yet
pp <- translator_job_progress(est, 2L, 2L, est$per_level_tokens$a, est$per_level_tokens$b * 3.6 * 1.2)
ok(!isTRUE(pp$over) && pp$progress > pr2$progress && !grepl("longer", pp$eta_text), "20% past the estimate: progress rises, no note")
# a system running past its estimate: the bar keeps moving, the text says so
po1 <- translator_job_progress(est, 2L, 2L, est$per_level_tokens$a, est$per_level_tokens$b * 3.6 * 2)
po2 <- translator_job_progress(est, 2L, 2L, est$per_level_tokens$a, est$per_level_tokens$b * 3.6 * 4)
ok(isTRUE(po1$over) && isTRUE(po2$over) && po1$progress >= pr2$progress && po2$progress > po1$progress && po2$progress < 0.93 &&
   grepl("longer than estimated", po1$eta_text, fixed = TRUE), "past the estimate: progress still rises, never completes, and the text says so")
# measured durations replace the token arithmetic for the systems to come
est3 <- translator_job_estimate(c("a", "b", "c"), list(a = c("bulls", "cows"), b = "bulls", c = "bulls"), ul)
A <- est3$per_level_tokens$a; B <- est3$per_level_tokens$b; C <- est3$per_level_tokens$c
pm <- translator_job_progress(est3, 2L, 3L, A, 0, level_elapsed = 10, level_secs = 100)
ok(abs(pm$eta_sec - ((B + C) * 100 / A + est3$assemble_sec + est3$delivery_sec)) < 1e-6 && !isTRUE(pm$over),
   "ETA from the measured rate: this system and the next at the tokens per second of the finished one")
e_seq <- vapply(c(0, 0.5, 0.9, 1.2, 2), function(k)
  translator_job_progress(est3, 2L, 3L, A, B * 3.6 * k, level_elapsed = 10 + 100 * k, level_secs = 100)$eta_sec, numeric(1))
ok(all(diff(e_seq) <= 1e-9), "within a system the time left only falls, past the estimate included")
pm2 <- translator_job_progress(est3, 3L, 3L, A + B, 0, level_elapsed = 150, level_secs = c(100, 100))
ok(isTRUE(pm2$over) && abs(pm2$eta_sec - (C * 200 / (A + B) + est3$assemble_sec + est3$delivery_sec)) < 1e-6,
   "the last system well past its expected duration: the note, and only its own remainder")

# ---- job file ------------------------------------------------------------------------
Sys.setenv(APP_RUNTIME_DIR = tempfile("rt"))
jb <- translator_job_new("who@local", prompt_hash = "ph")
ok(identical(translator_job_read(jb$id)$status, "running") && identical(translator_job_find("who@local")$id, jb$id), "job written and found by user")
translator_job_update(jb$id, progress = 0.5, stage_label = "half")
ok(abs(translator_job_read(jb$id)$progress - 0.5) < 1e-9 && identical(translator_job_read(jb$id)$stage_label, "half"), "job update")
ok(is.null(translator_job_find("other@local")), "another user does not see it")
old <- translator_job_read(jb$id); old$updated_at <- "2026-01-01T00:00:00Z"; translator_job_write(old)
translator_job_mark_lost(); ok(identical(translator_job_read(jb$id)$status, "lost"), "a stale running job is marked lost")

# ---- mail attachments ------------------------------------------------------------------
f1 <- file.path(td, "a.xlsx"); writeLines("x", f1)
Sys.setenv(BREVO_API_KEY = "k", RESEND_API_KEY = "k", SENDGRID_API_KEY = "k")
att <- list(list(path = f1, name = "a.xlsx", type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
rb <- .auth_mail_request("brevo", "to@x", "s", "t", NULL, "from@x", "F", attachments = att)$body$data
rr <- .auth_mail_request("resend", "to@x", "s", "t", NULL, "from@x", "F", attachments = att)$body$data
rs <- .auth_mail_request("sendgrid", "to@x", "s", "t", NULL, "from@x", "F", attachments = att)$body$data
ok(identical(rb$attachment[[1]]$name, "a.xlsx") && nzchar(rb$attachment[[1]]$content), "brevo attachment shape")
ok(identical(rr$attachments[[1]]$filename, "a.xlsx"), "resend attachment shape")
ok(identical(rs$attachments[[1]]$disposition, "attachment") && grepl("spreadsheet", rs$attachments[[1]]$type), "sendgrid attachment shape")
ok(identical(jsonlite::base64_dec(rb$attachment[[1]]$content), readBin(f1, "raw", file.size(f1))), "attachment content round-trips")
ok(is.null(.auth_mail_request("brevo", "to@x", "s", "t", NULL, "from@x", "F")$body$data$attachment), "no attachments: field absent")

# ---- the email trims from the end when too large ----------------------------------------
big <- file.path(td, "big.xlsx"); writeBin(as.raw(rep(0L, 2000)), big)
jb2 <- translator_job_new("who@local")
translator_job_update(jb2$id, status = "done", outputs = list(template = big, checks = f1, conversation = f1))
sent <- list()
.auth_send_email <- function(to, subject, text, html = NULL, attachments = NULL, ...) {
  sent[[length(sent) + 1]] <<- attachments; list(ok = TRUE, provider = "stub", attempts = character(0)) }
translator_job_email(jb2$id, "who@local", limit_bytes = 2668)
ok(length(sent[[1]]) == 1L && identical(sent[[1]][[1]]$name, "big.xlsx") && identical(translator_job_read(jb2$id)$delivery$mode, "email"),
   "email keeps the data workbook first and drops the rest when over the limit")
translator_job_email(jb2$id, "who@local")
ok(length(sent[[2]]) == 3L, "within the limit all three go")
cat("JOB TESTS PASSED\n")
