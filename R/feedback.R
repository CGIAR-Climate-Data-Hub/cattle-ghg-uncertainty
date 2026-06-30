# In-app feedback → GitHub issue + admin email
#
# The floating "Feedback" button (see R/app_ui.R + R/app_server.R) opens a
# modal where any user — signed-in or not — can describe a bug/idea/question
# and optionally attach a screenshot. On submit, feedback_submit():
#   1. uploads any attachment to a dedicated `feedback-assets` branch of the
#      repo via the GitHub Contents API (so it can be embedded in the issue),
#   2. creates a GitHub issue with the text + an auto-captured context block,
#   3. emails an alert to ADMIN_EMAIL via the existing SendGrid plumbing.
#
# Everything degrades gracefully: if GitHub is unreachable/misconfigured the
# admin still gets the full feedback by email, so nothing is ever lost.
#
# Config (gitignored .Renviron, bundled into the deploy — same handling as
# SENDGRID_API_KEY / ANTHROPIC_API_KEY, never committed, never sent to the
# browser):
#   GITHUB_FEEDBACK_REPO   = "owner/repo"   (e.g. CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty)
#   GITHUB_FEEDBACK_TOKEN  = fine-grained PAT, scoped to that repo only,
#                            Issues:R+W + Contents:R+W.
#
# All HTTP reuses httr2 (already loaded by app.R) and the same perform/parse
# pattern as R/anthropic_client.R and R/auth_magic_link.R. base64 via
# jsonlite::base64_enc (already loaded) — no new package dependencies.

# ----- GitHub helpers -------------------------------------------------------

# Parse GITHUB_FEEDBACK_REPO ("owner/repo"). Returns NULL when unset/malformed
# (treated as "GitHub not configured" → callers fall back to email-only).
.gh_owner_repo <- function() {
  raw <- Sys.getenv("GITHUB_FEEDBACK_REPO", unset = "")
  parts <- strsplit(raw, "/", fixed = TRUE)[[1]]
  if (length(parts) != 2 || !all(nzchar(parts))) return(NULL)
  list(owner = parts[1], repo = parts[2])
}

.gh_token <- function() Sys.getenv("GITHUB_FEEDBACK_TOKEN", unset = "")

# A pre-configured GitHub request (headers + timeout + suppressed auto-error).
# GitHub REQUIRES a User-Agent header on every call (403 without it).
.gh_req <- function(url, token) {
  httr2::request(url) |>
    httr2::req_headers(
      `Authorization`        = paste("Bearer", token),
      `Accept`               = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28",
      `User-Agent`           = "cattle-ghg-uncertainty-feedback"
    ) |>
    httr2::req_timeout(20) |>
    httr2::req_error(is_error = function(resp) FALSE)
}

# Create an issue. Returns list(url=<html_url>, number=, error=NULL) on
# success, else list(url=NULL, number=NULL, error="…").
github_create_issue <- function(title, body, labels = NULL) {
  or <- .gh_owner_repo()
  if (is.null(or)) return(list(url = NULL, number = NULL, error = "GitHub not configured"))
  token <- .gh_token()
  if (!nzchar(token)) return(list(url = NULL, number = NULL, error = "GitHub token not set"))

  payload <- list(title = title, body = body)
  if (length(labels)) payload$labels <- as.list(labels)
  url <- sprintf("https://api.github.com/repos/%s/%s/issues", or$owner, or$repo)
  req <- .gh_req(url, token) |> httr2::req_body_json(payload)   # body ⇒ POST
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error"))
    return(list(url = NULL, number = NULL,
                error = paste("network:", conditionMessage(resp))))
  st <- httr2::resp_status(resp)
  if (st %in% 200:299) {
    b <- httr2::resp_body_json(resp)
    return(list(url = b$html_url, number = b$number, error = NULL))
  }
  msg <- tryCatch(httr2::resp_body_json(resp)$message, error = function(e) "")
  list(url = NULL, number = NULL,
       error = sprintf("GitHub issue create failed: HTTP %d — %s", st, msg %||% ""))
}

# Make sure the asset branch exists; create it from the default branch's HEAD
# if it doesn't. Returns list(error=NULL) on success.
github_ensure_branch <- function(branch = "feedback-assets") {
  or <- .gh_owner_repo()
  if (is.null(or)) return(list(error = "GitHub not configured"))
  token <- .gh_token()
  if (!nzchar(token)) return(list(error = "GitHub token not set"))
  base <- sprintf("https://api.github.com/repos/%s/%s", or$owner, or$repo)

  resp <- tryCatch(
    httr2::req_perform(.gh_req(sprintf("%s/git/ref/heads/%s", base, branch), token)),
    error = function(e) e)
  if (inherits(resp, "error")) return(list(error = paste("network:", conditionMessage(resp))))
  st <- httr2::resp_status(resp)
  if (st == 200) return(list(error = NULL))         # already exists
  if (st != 404) return(list(error = sprintf("branch check HTTP %d", st)))

  # 404 → create it from the default branch's head sha.
  repo_resp <- tryCatch(httr2::req_perform(.gh_req(base, token)), error = function(e) e)
  if (inherits(repo_resp, "error") || !(httr2::resp_status(repo_resp) %in% 200:299))
    return(list(error = "couldn't read repo default branch"))
  default_branch <- httr2::resp_body_json(repo_resp)$default_branch %||% "main"

  head_resp <- tryCatch(
    httr2::req_perform(.gh_req(sprintf("%s/git/ref/heads/%s", base, default_branch), token)),
    error = function(e) e)
  if (inherits(head_resp, "error") || !(httr2::resp_status(head_resp) %in% 200:299))
    return(list(error = "couldn't read default branch head"))
  sha <- httr2::resp_body_json(head_resp)$object$sha
  if (is.null(sha)) return(list(error = "no head sha"))

  create_req <- .gh_req(sprintf("%s/git/refs", base), token) |>
    httr2::req_body_json(list(ref = paste0("refs/heads/", branch), sha = sha))
  cr <- tryCatch(httr2::req_perform(create_req), error = function(e) e)
  if (inherits(cr, "error") || !(httr2::resp_status(cr) %in% 200:299))
    return(list(error = "couldn't create feedback-assets branch"))
  list(error = NULL)
}

# Upload a local file to <dest_path> on <branch> via the Contents API and
# return its raw download URL. dest_path MUST be unique (callers prefix a
# timestamp + random hex) so we never hit the "overwrite needs sha" 422.
# RAM-aware: the base64 buffer is freed immediately after the request.
github_upload_asset <- function(local_path, dest_path, branch = "feedback-assets") {
  or <- .gh_owner_repo()
  if (is.null(or)) return(list(download_url = NULL, error = "GitHub not configured"))
  token <- .gh_token()
  if (!nzchar(token)) return(list(download_url = NULL, error = "GitHub token not set"))

  ens <- github_ensure_branch(branch)
  if (!is.null(ens$error)) return(list(download_url = NULL, error = ens$error))

  sz <- file.info(local_path)$size
  if (is.na(sz) || sz <= 0) return(list(download_url = NULL, error = "empty or missing file"))

  raw <- readBin(local_path, "raw", n = sz)
  b64 <- jsonlite::base64_enc(raw)          # newline-free base64 — Contents API wants exactly this
  rm(raw); gc(FALSE)

  url <- sprintf("https://api.github.com/repos/%s/%s/contents/%s",
                 or$owner, or$repo, utils::URLencode(dest_path, reserved = TRUE))
  req <- .gh_req(url, token) |>
    httr2::req_body_json(list(
      message = paste("feedback asset", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
      content = b64,
      branch  = branch)) |>
    httr2::req_method("PUT")
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  rm(b64); gc(FALSE)

  if (inherits(resp, "error"))
    return(list(download_url = NULL, error = paste("network:", conditionMessage(resp))))
  st <- httr2::resp_status(resp)
  if (!(st %in% 200:299)) {
    msg <- tryCatch(httr2::resp_body_json(resp)$message, error = function(e) "")
    return(list(download_url = NULL,
                error = sprintf("asset upload HTTP %d — %s", st, msg %||% "")))
  }
  body <- httr2::resp_body_json(resp)
  list(download_url = body$content$download_url, error = NULL)
}

# ----- Admin email (SendGrid) ----------------------------------------------

.fb_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  gsub(">", "&gt;",  x, fixed = TRUE)
}

# Notify the admin of new feedback. Best-effort (returns TRUE on 2xx).
# Modeled on auth_notify_admin_of_request (R/auth_magic_link.R). When
# issue_url is NULL the body still carries the full feedback text so the
# email alone preserves the report.
feedback_notify_admin <- function(admin_email = Sys.getenv("ADMIN_EMAIL", unset = ""),
                                  from_email  = Sys.getenv("MAGIC_LINK_FROM",
                                                            unset = "noreply@cattle-uncertainty.app"),
                                  subject, text, issue_url = NULL) {
  if (!nzchar(admin_email)) return(FALSE)
  sg_key <- Sys.getenv("SENDGRID_API_KEY", unset = "")
  if (!nzchar(sg_key)) return(FALSE)

  has_link  <- !is.null(issue_url) && nzchar(issue_url)
  link_txt  <- if (has_link) paste0("\n\nGitHub issue: ", issue_url) else ""
  link_html <- if (has_link)
    sprintf("<p>GitHub issue: <a href=\"%s\">%s</a></p>", issue_url, issue_url) else ""

  body <- list(
    personalizations = list(list(
      to      = list(list(email = admin_email)),
      subject = subject
    )),
    from    = list(email = from_email, name = "IPCC Cattle GHG Tool"),
    content = list(
      list(type = "text/plain", value = paste0(text, link_txt)),
      list(type = "text/html",
            value = paste0(
              "<pre style=\"white-space:pre-wrap;font-family:inherit;\">",
              .fb_html_escape(text), "</pre>", link_html))
    )
  )
  req <- httr2::request("https://api.sendgrid.com/v3/mail/send") |>
    httr2::req_headers(`Authorization` = paste("Bearer", sg_key),
                        `Content-Type`  = "application/json") |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(20) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) return(FALSE)
  httr2::resp_status(resp) %in% 200:299
}

# ----- Orchestrator ---------------------------------------------------------

# Keep only filesystem-safe characters and cap the length.
.fb_sanitize <- function(name) {
  name <- basename(name %||% "file")
  name <- gsub("[^A-Za-z0-9._-]", "_", name)
  if (!nzchar(name)) name <- "file"
  substr(name, 1, 80)
}

# Submit one piece of feedback. Returns:
#   list(ok, issue_url, issue_error, mailed, notes, user_message)
# user_message is what the UI shows the user. ok=TRUE means it was captured
# somewhere (issue and/or email), so the modal can close.
feedback_submit <- function(text, category = "Question", reporter_email = "",
                            page = "", attachment_path = NULL, attachment_name = NULL,
                            user_agent = "", app_version = "") {
  text <- trimws(text %||% "")
  if (!nzchar(text))
    return(list(ok = FALSE, issue_url = NULL, issue_error = NULL, mailed = FALSE,
                notes = "", user_message = "Please enter some feedback text."))

  tryCatch({
    if (!(category %in% c("Bug", "Idea", "Question"))) category <- "Question"
    reporter_email <- trimws(reporter_email %||% "")
    email_ok <- nzchar(reporter_email) &&
      grepl("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", reporter_email, perl = TRUE)
    reporter_disp <- if (!nzchar(reporter_email)) "(not provided)"
                     else if (email_ok) reporter_email
                     else paste0(reporter_email, " (unverified)")

    notes     <- character(0)
    attach_md <- ""

    # ---- attachment → embed in issue --------------------------------------
    if (!is.null(attachment_path) && file.exists(attachment_path)) {
      sz <- file.info(attachment_path)$size
      if (!is.na(sz) && sz <= 8 * 1024^2) {
        safe <- .fb_sanitize(attachment_name %||% basename(attachment_path))
        dest <- sprintf("assets/%s-%s-%s",
                        format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"),
                        sprintf("%08x", sample.int(.Machine$integer.max, 1)),
                        safe)
        up <- github_upload_asset(attachment_path, dest)
        if (is.null(up$error) && !is.null(up$download_url)) {
          ext <- tolower(tools::file_ext(safe))
          attach_md <- if (ext %in% c("png", "jpg", "jpeg", "gif", "webp"))
            sprintf("\n\n![attachment](%s)", up$download_url)
          else
            sprintf("\n\n[Download attachment: %s](%s)", safe, up$download_url)
        } else {
          notes <- c(notes, paste("attachment not embedded:", up$error %||% "unknown"))
          attach_md <- sprintf("\n\n_Attachment \"%s\" could not be uploaded._",
                               attachment_name %||% safe)
        }
      } else {
        notes <- c(notes, "attachment skipped (>8 MB)")
        attach_md <- "\n\n_Attachment skipped (larger than 8 MB)._"
      }
    }

    # ---- build issue ------------------------------------------------------
    one_line <- gsub("\\s+", " ", text)
    short <- substr(one_line, 1, 70)
    if (nchar(one_line) > 70) short <- paste0(short, "…")
    title <- sprintf("[Feedback: %s] %s", category, short)

    body <- paste0(
      text, "\n\n---\n",
      "**Submitted via in-app feedback**\n",
      sprintf("- Category: %s\n", category),
      sprintf("- Reporter: %s\n", reporter_disp),
      sprintf("- Page / tab: %s\n", if (nzchar(page)) page else "(unknown)"),
      sprintf("- App version: %s\n", if (nzchar(app_version)) app_version else "(unset)"),
      sprintf("- User agent: %s\n", if (nzchar(user_agent)) user_agent else "(unknown)"),
      sprintf("- Time (UTC): %s\n", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
      attach_md
    )
    iss <- github_create_issue(title, body, labels = c("feedback", tolower(category)))

    # ---- email the admin (always) -----------------------------------------
    admin_text <- paste0(
      "New in-app feedback\n\n",
      "Category: ", category, "\n",
      "Reporter: ", reporter_disp, "\n",
      "Page/tab: ", if (nzchar(page)) page else "(unknown)", "\n\n",
      "Message:\n", text,
      if (length(notes)) paste0("\n\nNotes: ", paste(notes, collapse = "; ")) else ""
    )
    mailed <- feedback_notify_admin(subject = sprintf("Cattle GHG feedback [%s]", category),
                                    text = admin_text, issue_url = iss$url)

    ok <- is.null(iss$error) || isTRUE(mailed)
    user_message <-
      if (is.null(iss$error) && isTRUE(mailed))
        sprintf("Thanks! Your feedback was logged (issue #%s) and the team was notified.", iss$number)
      else if (is.null(iss$error))
        sprintf("Thanks! Your feedback was logged (issue #%s).", iss$number)
      else if (isTRUE(mailed))
        "Thanks! We couldn't file it automatically, but the team has been emailed your feedback."
      else
        sprintf("Sorry — we couldn't send your feedback right now. Please email %s directly.",
                Sys.getenv("ADMIN_EMAIL", unset = "the administrator"))

    list(ok = ok, issue_url = iss$url, issue_error = iss$error, mailed = mailed,
         notes = paste(notes, collapse = "; "), user_message = user_message)
  },
  error = function(e) {
    # Last-ditch: try to email the admin so the feedback isn't lost.
    mailed <- tryCatch(
      feedback_notify_admin(subject = "Cattle GHG feedback (error path)",
                            text = text, issue_url = NULL),
      error = function(e2) FALSE)
    list(ok = FALSE, issue_url = NULL, issue_error = conditionMessage(e),
         mailed = mailed, notes = "exception",
         user_message = if (isTRUE(mailed))
           "Thanks — we hit a hiccup filing it, but the team has been emailed your feedback."
         else
           "Sorry — we couldn't send your feedback right now. Please email the administrator directly.")
  })
}
