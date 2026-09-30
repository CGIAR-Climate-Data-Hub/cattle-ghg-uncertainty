# Send a welcome email to anyone newly added to config/approved_users.csv
# since the last deploy.
#
# How it works:
#   - Snapshot of the previously-approved list lives in
#     runtime/.approved_users_snapshot.csv (gitignored).
#   - On each deploy, this script diffs the current CSV against the
#     snapshot, finds emails added since last run, and sends each one a
#     short welcome email.
#   - Only addresses that were SENT SUCCESSFULLY enter the snapshot, so a
#     failed send is retried on the next deploy instead of being forgotten.
#
# Sending goes through .auth_send_email() in R/auth_magic_link.R, the same
# provider chain (Brevo, then Resend, then SendGrid) the app itself uses for
# magic-link sign-in. This script used to call SendGrid directly, which meant
# it kept using an expired trial key after the app had moved to Brevo: the
# welcome emails failed with HTTP 401 while sign-in worked fine, and because
# the snapshot was refreshed regardless, nobody was ever retried.
#
# Triggered from scripts/deploy.R BEFORE the rsconnect call, so the
# user gets their welcome email even if the deploy step fails later.
#
# Safe to re-run: if nothing changed, no email is sent. Send failures are
# non-fatal, the deploy proceeds regardless, and the address is retried.

if (basename(getwd()) == "scripts") setwd("..")

.notify_send_one <- function(to_email, from_email, from_name, app_url) {
  text <- paste0(
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
        "browser: you only do this once per browser. To sign out, ",
        "clear the site data in your browser settings.\n\n",
        "If you run into anything, just reply to this email.\n\n",
        "Thanks,\n",
        "Lolita (CGIAR Alliance, Climate Action Programme)\n"
      )
  res <- .auth_send_email(
    to      = to_email,
    subject = "You're approved: IPCC Tier 2 Livestock GHG Uncertainty Calculator",
    text    = text,
    from_email = from_email, from_name = from_name)
  if (isTRUE(res$ok))
    message("notify_approved: sent welcome -> ", to_email, " via ", res$provider)
  else
    message("notify_approved: FAILED to send to ", to_email, " (",
            paste(res$attempts, collapse = "; "), ")")
  isTRUE(res$ok)
}

# Load .Renviron secrets if not already set, then the shared sender.
if (!nzchar(Sys.getenv("BREVO_API_KEY", unset = "")) &&
    !nzchar(Sys.getenv("RESEND_API_KEY", unset = "")) &&
    !nzchar(Sys.getenv("SENDGRID_API_KEY", unset = ""))) {
  if (file.exists(".Renviron")) readRenviron(".Renviron")
}
source("R/auth_magic_link.R")

current_csv  <- "config/approved_users.csv"
snapshot_csv <- "runtime/.approved_users_snapshot.csv"
if (!dir.exists("runtime")) dir.create("runtime")

if (!file.exists(current_csv)) {
  message("notify_approved: ", current_csv, " not found, skipping notify pass.")
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
    message("notify_approved: no new approved users since last deploy, skipping.")
  } else {
    if (length(.auth_mail_chain()) == 0) {
      message("notify_approved: no mail provider key set, skipping welcome ",
              "emails. Would have notified: ",
              paste(new_emails, collapse = ", "))
      sent_ok <- character(0)
    } else {
      from_email <- Sys.getenv("MAGIC_LINK_FROM",
                                unset = "noreply@cattle-uncertainty.app")
      from_name  <- "IPCC Cattle GHG Tool"
      app_url    <- Sys.getenv(
        "APP_BASE_URL",
        unset = "https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/")
      message("notify_approved: ", length(new_emails),
              " new approved user(s): sending welcome emails...")
      ok <- vapply(new_emails,
                   function(e) .notify_send_one(e, from_email, from_name, app_url),
                   logical(1))
      sent_ok <- new_emails[ok]
    }
  }

  # Refresh the snapshot so the NEXT deploy only notifies the next batch.
  # The FULL current set is snapshotted, minus any address whose welcome
  # email failed, so removals propagate while a failed send is retried next
  # time. Writing the whole set unconditionally is what previously turned one
  # 401 into two people silently never hearing they had been approved.
  if (!exists("sent_ok")) sent_ok <- new_emails   # nothing to send this run
  keep <- setdiff(current_emails, setdiff(new_emails, sent_ok))
  if (length(keep) < length(current_emails))
    message("notify_approved: ",
            length(current_emails) - length(keep),
            " address(es) held back for retry on the next deploy.")
  writeLines(keep, snapshot_csv)
}
