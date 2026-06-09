# Send a welcome email to anyone newly added to config/approved_users.csv
# since the last deploy.
#
# How it works:
#   - Snapshot of the previously-approved list lives in
#     .approved_users_snapshot.csv at the project root (gitignored).
#   - On each deploy, this script diffs the current CSV against the
#     snapshot, finds emails added since last run, and sends each one a
#     short welcome email via SendGrid.
#   - After the emails are sent, the snapshot is refreshed so subsequent
#     deploys only notify the genuinely-new approvers.
#
# Triggered from scripts/deploy.R BEFORE the rsconnect call, so the
# user gets their welcome email even if the deploy step fails later.
#
# Safe to re-run: if nothing changed, no email is sent. SendGrid
# failures are non-fatal — the deploy proceeds regardless.

if (basename(getwd()) == "scripts") setwd("..")

.notify_send_one <- function(to_email, sg_key, from_email, from_name, app_url) {
  body <- list(
    personalizations = list(list(
      to      = list(list(email = to_email)),
      subject = "You're approved — IPCC Tier 2 Livestock GHG Uncertainty Calculator"
    )),
    from    = list(email = from_email, name = from_name),
    content = list(list(
      type  = "text/plain",
      value = paste0(
        "Hello,\n\n",
        "You've been approved to use the AI Translator on the IPCC Tier 2 ",
        "Livestock GHG Uncertainty Calculator.\n\n",
        "To get started:\n\n",
        "  1. Open the app: ", app_url, "\n",
        "  2. Go to the Resources tab and find the AI Translator card.\n",
        "  3. Enter this email address (", to_email, ") and click 'Send ",
        "sign-in link'.\n",
        "  4. A one-time sign-in link will arrive in your inbox. Click it ",
        "to open the chat.\n",
        "  5. Upload your raw cattle data file. The AI reads it, asks any ",
        "clarifying questions, and produces a downloadable .xlsx ready to ",
        "upload to the Data Input tab.\n\n",
        "Once you sign in, it is remembered indefinitely on that ",
        "browser — you only do this once per browser. To sign out, ",
        "clear the site data in your browser settings.\n\n",
        "If you run into anything, just reply to this email.\n\n",
        "Thanks,\n",
        "Lolita (CGIAR Alliance, Climate Action Programme)\n"
      )
    ))
  )
  req <- httr2::request("https://api.sendgrid.com/v3/mail/send") |>
    httr2::req_headers(`Authorization` = paste("Bearer", sg_key),
                        `Content-Type`  = "application/json") |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(20) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  ok <- !inherits(resp, "error") &&
        httr2::resp_status(resp) >= 200 &&
        httr2::resp_status(resp) < 300
  if (ok) message("notify_approved: sent welcome → ", to_email)
  else    message("notify_approved: FAILED to send to ", to_email,
                   " (", if (inherits(resp, "error")) conditionMessage(resp)
                          else paste("HTTP", httr2::resp_status(resp)), ")")
  ok
}

# Load .Renviron secrets if not already set
if (!nzchar(Sys.getenv("SENDGRID_API_KEY", unset = ""))) {
  if (file.exists(".Renviron")) readRenviron(".Renviron")
}

current_csv  <- "config/approved_users.csv"
snapshot_csv <- ".approved_users_snapshot.csv"

if (!file.exists(current_csv)) {
  message("notify_approved: ", current_csv, " not found — skipping notify pass.")
} else {
  current_emails <- tolower(trimws(readLines(current_csv, warn = FALSE)))
  current_emails <- current_emails[nzchar(current_emails)]
  current_emails <- current_emails[!startsWith(current_emails, "#")]
  current_emails <- setdiff(current_emails, "email")  # drop a header row if present

  snapshot_emails <- if (file.exists(snapshot_csv))
    tolower(trimws(readLines(snapshot_csv, warn = FALSE))) else character(0)
  snapshot_emails <- snapshot_emails[nzchar(snapshot_emails)]

  new_emails <- setdiff(current_emails, snapshot_emails)

  if (length(new_emails) == 0) {
    message("notify_approved: no new approved users since last deploy — skipping.")
  } else {
    sg_key <- Sys.getenv("SENDGRID_API_KEY", unset = "")
    if (!nzchar(sg_key)) {
      message("notify_approved: SENDGRID_API_KEY not set — skipping welcome ",
              "emails. Would have notified: ",
              paste(new_emails, collapse = ", "))
    } else {
      from_email <- Sys.getenv("MAGIC_LINK_FROM",
                                unset = "noreply@cattle-uncertainty.app")
      from_name  <- "IPCC Cattle GHG Tool"
      app_url    <- Sys.getenv(
        "APP_BASE_URL",
        unset = "https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/")
      message("notify_approved: ", length(new_emails),
              " new approved user(s) — sending welcome emails…")
      for (e in new_emails) .notify_send_one(e, sg_key, from_email,
                                              from_name, app_url)
    }
  }

  # Refresh the snapshot so the NEXT deploy only notifies the next batch.
  # We snapshot the FULL current set (not just the new ones) so removals
  # also propagate.
  writeLines(current_emails, snapshot_csv)
}
