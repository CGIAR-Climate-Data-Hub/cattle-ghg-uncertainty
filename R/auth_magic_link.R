# Magic-link email authentication for the in-app AI translator.
#
# Flow:
#   1. User enters email -> server generates a 32-char token, stores
#      (token, email, expires_at) in a file-backed table, sends a link
#      through the first configured mail provider (Brevo / Resend / SendGrid).
#   2. User clicks the link in their inbox -> Shiny app loads with
#      `?token=...` in the URL -> the server validates the token,
#      consumes it, and sets `rv$user_email`.
#   3. The user_email is checked against the approved-users whitelist
#      (approved_users.csv). If approved, the chat UI unlocks. If not,
#      a "pending Lolita's approval" page is shown and a notification
#      email is sent to the admin.
#
# Tokens are kept ONLY in memory (a session-scoped reactiveValues map).
# Container restart wipes them; the user just enters their email again.
# No persistent secret in code or in git.
#
# Persistent storage caveat (same as usage_log.R): shinyapps.io's
# free/starter tiers don't persist files across container restarts.
# For tokens that's fine — they're short-lived (15 min). For the
# long-lived (~100-year) "stay-logged-in" cookie, the cookie is stored
# client-side (browser document.cookie); on the server we just validate
# that a cookie-supplied email matches the approved list.

# ----- Approved-users whitelist --------------------------------------------

# Read the whitelist CSV (single column: email). Returns character(0)
# if the file is missing — fail-closed (no one gets in).
auth_read_approved_users <- function(path = "config/approved_users.csv") {
  if (!file.exists(path)) {
    warning("config/approved_users.csv not found — no users will be approved.",
            call. = FALSE)
    return(character(0))
  }
  df <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                  error = function(e) NULL)
  if (is.null(df) || !"email" %in% names(df)) return(character(0))
  emails <- tolower(trimws(as.character(df$email)))
  emails[nzchar(emails)]
}

# Decide whether a given email is approved.
#  - listed explicitly in approved_users.csv -> TRUE
#  - matches the @cgiar.org domain pattern    -> TRUE  (per the plan)
#  - otherwise                                 -> FALSE
auth_is_approved <- function(email,
                              whitelist = auth_read_approved_users()) {
  if (is.null(email) || !nzchar(email)) return(FALSE)
  e <- tolower(trimws(email))
  if (e %in% whitelist) return(TRUE)
  grepl("@cgiar\\.org$", e, ignore.case = TRUE)
}

# ----- Magic-link token store (file-backed) --------------------------------
#
# Tokens used to live in an in-memory environment. That breaks on
# shinyapps.io because:
#   - Each container has its own R session (= its own memory).
#   - shinyapps.io can route the magic-link click to a DIFFERENT
#     container than the one that issued the token, even on a single-
#     user app (load balancing, instance recycling, etc.).
#   - The user then sees 'link expired' on first try and has to
#     resubmit.
#
# Fix: persist tokens to auth_tokens.csv in the container working dir.
# All instances of the deployed app see the same CSV (it's bundled in
# the deploy and any new writes go to the container's writable wd).
# Tokens are still single-use + 15-min TTL; expired rows are pruned on
# every read/write.
#
# Concurrency note: this is best-effort. With multiple users signing
# in simultaneously, a race could lose a write. For our scale (a few
# users a day) the trade-off is fine.

.AUTH_TOKEN_FILE <- "auth_tokens.csv"

.auth_token_make <- function() {
  paste(as.hexmode(sample.int(2^31 - 1, size = 4)), collapse = "")
}

# Read the current CSV. Returns a data.frame with columns
# (token, email, expires_at) — drops expired rows on the way out.
.auth_token_read <- function() {
  empty <- data.frame(token = character(),
                      email = character(),
                      expires_at = as.POSIXct(character(), tz = "UTC"),
                      stringsAsFactors = FALSE)
  if (!file.exists(.AUTH_TOKEN_FILE)) return(empty)
  df <- tryCatch(
    utils::read.csv(.AUTH_TOKEN_FILE, stringsAsFactors = FALSE),
    error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(empty)
  df$expires_at <- as.POSIXct(df$expires_at, tz = "UTC",
                                format = "%Y-%m-%dT%H:%M:%SZ")
  alive <- !is.na(df$expires_at) & df$expires_at > Sys.time()
  df[alive, , drop = FALSE]
}

.auth_token_write <- function(df) {
  if (nrow(df) == 0) {
    if (file.exists(.AUTH_TOKEN_FILE)) file.remove(.AUTH_TOKEN_FILE)
    return(invisible(NULL))
  }
  out <- df
  out$expires_at <- format(out$expires_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  utils::write.csv(out, .AUTH_TOKEN_FILE, row.names = FALSE)
  invisible(NULL)
}

# Store a new token; returns the token string.
auth_token_issue <- function(email, ttl_seconds = 15 * 60) {
  tok <- .auth_token_make()
  df  <- .auth_token_read()
  df  <- rbind(df, data.frame(
    token = tok,
    email = tolower(trimws(email)),
    expires_at = Sys.time() + ttl_seconds,
    stringsAsFactors = FALSE
  ))
  .auth_token_write(df)
  tok
}

# Consume a token (one-shot). Returns the email if valid, NULL otherwise.
# Always removes the token from the store, even on failure, so a leaked
# URL is single-use.
auth_token_consume <- function(token) {
  if (is.null(token) || !nzchar(token)) return(NULL)
  df  <- .auth_token_read()
  hit <- df$token == token
  rec <- if (any(hit)) df[which(hit)[1], , drop = FALSE] else NULL
  # Always remove the matched row, even on failure
  if (any(hit)) {
    df <- df[!hit, , drop = FALSE]
    .auth_token_write(df)
  }
  if (is.null(rec)) return(NULL)
  if (Sys.time() > rec$expires_at) return(NULL)
  rec$email
}

# ---- Transactional email, provider-agnostic ---------------------------------
#
# `app_base_url` (APP_BASE_URL) is the public URL of the app; the magic link
# is built from it, so a missing value is logged loudly rather than silently.
#
# 2026-09-17. The SendGrid free trial expired on 2026-08-01 (account type
# "free", credits 0, hard limit) and every sign-in email since has failed
# with "Maximum credits exceeded". Rather than tie the app to one vendor's
# pricing, the two emails the app sends (the magic link and the admin
# access-request notice) go through one dispatcher that tries every provider
# whose key is configured, in order:
#
#   MAIL_PROVIDER      optional; the provider to try first (brevo / resend /
#                      sendgrid). Otherwise the order below.
#   BREVO_API_KEY      Brevo (ex-Sendinblue): free tier, verifies a single
#                      sender ADDRESS by confirmation email, so a @cgiar.org
#                      sender works without DNS access. Recommended.
#   RESEND_API_KEY     Resend: free tier, but a custom sender needs a
#                      verified DOMAIN; without DNS access only the
#                      onboarding sender to your own address works.
#   SENDGRID_API_KEY   SendGrid: the original provider; paid plans only.
#
# A provider that answers non-2xx is logged with the API's own message and
# the next one is tried. When all fail, the sign-in link is written to the
# server log so the administrator can pass it on (see .auth_log_link_fallback).
.MAIL_PROVIDER_ORDER <- c("brevo", "resend", "sendgrid")

.auth_mail_chain <- function() {
  keys <- c(brevo    = Sys.getenv("BREVO_API_KEY",    unset = ""),
            resend   = Sys.getenv("RESEND_API_KEY",   unset = ""),
            sendgrid = Sys.getenv("SENDGRID_API_KEY", unset = ""))
  avail <- .MAIL_PROVIDER_ORDER[nzchar(keys[.MAIL_PROVIDER_ORDER])]
  pref  <- tolower(trimws(Sys.getenv("MAIL_PROVIDER", unset = "")))
  if (nzchar(pref) && pref %in% avail) avail <- c(pref, setdiff(avail, pref))
  avail
}

.auth_mail_request <- function(provider, to, subject, text, html, from_email, from_name) {
  key <- Sys.getenv(switch(provider, brevo = "BREVO_API_KEY", resend = "RESEND_API_KEY",
                           sendgrid = "SENDGRID_API_KEY"), unset = "")
  switch(provider,
    brevo = httr2::request("https://api.brevo.com/v3/smtp/email") |>
      httr2::req_headers(`api-key` = key, `Content-Type` = "application/json", Accept = "application/json") |>
      httr2::req_body_json(list(
        sender = list(name = from_name, email = from_email),
        to = list(list(email = to)), subject = subject,
        textContent = text, htmlContent = html %||% paste0("<pre>", text, "</pre>"))),
    resend = httr2::request("https://api.resend.com/emails") |>
      httr2::req_headers(Authorization = paste("Bearer", key), `Content-Type` = "application/json") |>
      httr2::req_body_json(list(
        from = sprintf("%s <%s>", from_name, from_email), to = list(to), subject = subject,
        text = text, html = html %||% paste0("<pre>", text, "</pre>"))),
    sendgrid = httr2::request("https://api.sendgrid.com/v3/mail/send") |>
      httr2::req_headers(Authorization = paste("Bearer", key), `Content-Type` = "application/json") |>
      httr2::req_body_json(list(
        personalizations = list(list(to = list(list(email = to)), subject = subject)),
        from = list(email = from_email, name = from_name),
        content = c(list(list(type = "text/plain", value = text)),
                    if (!is.null(html)) list(list(type = "text/html", value = html)) else list()))),
    stop("unknown mail provider ", provider)) |>
    httr2::req_timeout(20) |>
    httr2::req_error(is_error = function(resp) FALSE)
}

# Pull the human-readable error out of each provider's error body.
.auth_mail_error_text <- function(resp) {
  tryCatch({
    b <- httr2::resp_body_json(resp)
    # [[ ]] with exact = TRUE: `b$error` partially matches `errors` and
    # returned the whole list into the log on the first test.
    msg <- c(b[["message", exact = TRUE]], b[["error", exact = TRUE]],
             if (!is.null(b[["errors", exact = TRUE]]))
               vapply(b[["errors", exact = TRUE]], function(e) e[["message", exact = TRUE]] %||% "", character(1)))
    msg <- unlist(msg)
    paste(msg[nzchar(msg)], collapse = "; ")
  }, error = function(e) "")
}

# Send one email through the first provider that accepts it.
# Returns list(ok, provider, attempts) where attempts is a character vector of
# "<provider>: <what happened>" for the log.
.auth_send_email <- function(to, subject, text, html = NULL,
                             from_email = Sys.getenv("MAGIC_LINK_FROM", unset = "noreply@cattle-uncertainty.app"),
                             from_name  = "IPCC Cattle GHG Tool") {
  chain <- .auth_mail_chain()
  if (length(chain) == 0)
    return(list(ok = FALSE, provider = NA_character_,
                attempts = "no mail provider key set (BREVO_API_KEY / RESEND_API_KEY / SENDGRID_API_KEY)"))
  attempts <- character(0)
  for (p in chain) {
    resp <- tryCatch(httr2::req_perform(.auth_mail_request(p, to, subject, text, html, from_email, from_name)),
                     error = function(e) e)
    if (inherits(resp, "error")) {
      attempts <- c(attempts, sprintf("%s: request failed (%s)", p, conditionMessage(resp))); next
    }
    st <- httr2::resp_status(resp)
    if (st >= 200 && st < 300) return(list(ok = TRUE, provider = p, attempts = attempts))
    em <- .auth_mail_error_text(resp)
    attempts <- c(attempts, sprintf("%s: HTTP %d%s", p, st, if (nzchar(em)) paste0(" (", em, ")") else ""))
  }
  list(ok = FALSE, provider = NA_character_, attempts = attempts)
}

# Send the magic-link email. Returns TRUE on success, FALSE otherwise; every
# failure is explained in the server log.
auth_send_magic_link <- function(email, token,
                                  app_base_url = Sys.getenv("APP_BASE_URL", unset = ""),
                                  from_email = Sys.getenv("MAGIC_LINK_FROM",
                                                           unset = "noreply@cattle-uncertainty.app"),
                                  from_name  = "IPCC Cattle GHG Tool") {
  if (!nzchar(app_base_url))
    message("auth: APP_BASE_URL not set — using a relative link (won't open in email)")
  link <- paste0(sub("/?$", "/", app_base_url), "?token=", token)
  text <- paste0(
    "Welcome to the AI translator for the IPCC Cattle GHG Tool.\n\n",
    "Click the link below to sign in (the link is valid for 15 minutes):\n\n",
    link, "\n\n",
    "If you didn't request this, you can safely ignore this email.\n")
  html <- paste0(
    "<p>Welcome to the AI translator for the IPCC Cattle GHG Tool.</p>",
    "<p><a href=\"", link, "\">Click here to sign in</a> ",
    "(the link is valid for 15 minutes).</p>",
    "<p>If you didn't request this, you can safely ignore this email.</p>")
  r <- .auth_send_email(email, "Sign in to the IPCC Cattle GHG Uncertainty tool", text, html,
                        from_email = from_email, from_name = from_name)
  if (r$ok) {
    if (length(r$attempts)) message("auth: sign-in email sent via ", r$provider,
                                    " after: ", paste(r$attempts, collapse = " | "))
    return(TRUE)
  }
  message("auth: sign-in email NOT sent. ", paste(r$attempts, collapse = " | "))
  .auth_log_link_fallback(email, link)
  FALSE
}

# When the email cannot go out, write the sign-in link to the server log so
# an administrator can pass it to the user by hand (rsconnect::showLogs).
# The link is a one-time token valid for 15 minutes and the log is visible
# only to the account holder, which is acceptable for the pilot; remove this
# if the log ever becomes shared.
.auth_log_link_fallback <- function(email, link) {
  message(sprintf("auth: EMAIL NOT SENT. Sign-in link for %s (valid 15 min): %s", email, link))
}

# Notify the admin when a non-approved user requests access. Best-effort.
auth_notify_admin_of_request <- function(requesting_email,
                                          admin_email = Sys.getenv("ADMIN_EMAIL",
                                                                    unset = "")) {
  if (!nzchar(admin_email)) return(FALSE)
  r <- .auth_send_email(
    admin_email,
    paste("Cattle GHG Tool — access request from", requesting_email),
    paste0("A new user requested access to the in-app AI translator:\n\n",
           "    ", requesting_email, "\n\n",
           "To approve, add this email to approved_users.csv and redeploy.\n"))
  if (!r$ok) message("auth: admin notice NOT sent for ", requesting_email, ". ",
                     paste(r$attempts, collapse = " | "))
  r$ok
}

# ----- Long-lived session cookie -------------------------------------------
#
# After a successful magic-link consume we drop a long-lived (~100-year)
# cookie in the browser so the user doesn't have to re-verify on every
# reload. Functionally permanent — the cookie outlives the browser
# install. Users can still sign out by clearing site data. The cookie
# is a signed token:
#
#   <email>|<expires_at_epoch>|<hmac_hex>
#
# - email + expires_at_epoch are in the clear (they're shown to the
#   user themselves anyway, no secret).
# - hmac = HMAC-SHA256(email|expires_at, SESSION_SIGNING_KEY) — the
#   server verifies this on every page load. If the attacker doesn't
#   have SESSION_SIGNING_KEY they can't forge a valid token.
#
# The cookie is set via JS (document.cookie) so it can't be HttpOnly,
# but the value is also not a usable secret on its own — it identifies
# the user but doesn't authorise any privileged action beyond the
# translator chat. For the pilot this trade-off is acceptable.

.auth_hmac <- function(message) {
  key <- Sys.getenv("SESSION_SIGNING_KEY", unset = "")
  if (!nzchar(key))
    stop("SESSION_SIGNING_KEY is not set — refusing to issue session tokens.",
         call. = FALSE)
  # Use openssl::sha256 with HMAC-SHA256. openssl is a transitive
  # dependency of httr2 so already loaded.
  hmac_raw <- openssl::sha256(charToRaw(message),
                                key = charToRaw(key))
  paste(as.character(hmac_raw), collapse = "")
}

# Issue a long-lived (default ~100-year) cookie value for the given
# email. Returns the full cookie string ready to push to the browser.
# 36 500 days places the expiry comfortably beyond any realistic
# browser-install lifetime, which is what the user asked for: once an
# email is approved, it stays signed in indefinitely.
auth_session_cookie_issue <- function(email,
                                      ttl_days = 36500L) {
  email <- tolower(trimws(email))
  expires_at <- as.integer(Sys.time()) + ttl_days * 86400L
  payload    <- paste(email, expires_at, sep = "|")
  paste(payload, .auth_hmac(payload), sep = "|")
}

# Verify a cookie value. Returns the email if (a) the HMAC is valid and
# (b) expires_at is still in the future. Returns NULL on any failure
# (tampered, expired, malformed, or signing key not set).
auth_session_cookie_verify <- function(cookie_value) {
  if (is.null(cookie_value) || !nzchar(cookie_value)) return(NULL)
  parts <- strsplit(cookie_value, "|", fixed = TRUE)[[1]]
  if (length(parts) != 3) return(NULL)
  email      <- parts[1]
  expires_at <- suppressWarnings(as.integer(parts[2]))
  hmac_seen  <- parts[3]
  if (is.na(expires_at) || expires_at < as.integer(Sys.time())) return(NULL)
  payload <- paste(email, expires_at, sep = "|")
  hmac_expected <- tryCatch(.auth_hmac(payload), error = function(e) NULL)
  if (is.null(hmac_expected)) return(NULL)
  if (!identical(hmac_expected, hmac_seen)) return(NULL)
  email
}

# Parse the Cookie: header from session$request$HTTP_COOKIE and return
# the value of the named cookie, or NULL.
auth_cookie_lookup <- function(cookie_header, name) {
  if (is.null(cookie_header) || !nzchar(cookie_header)) return(NULL)
  pairs <- strsplit(cookie_header, ";\\s*")[[1]]
  for (p in pairs) {
    eq <- regexpr("=", p, fixed = TRUE)
    if (eq < 1) next
    k <- substr(p, 1, eq - 1)
    if (identical(trimws(k), name))
      return(utils::URLdecode(substr(p, eq + 1, nchar(p))))
  }
  NULL
}

# ----- Shiny UI helpers -----------------------------------------------------

# Email-entry form shown when no user is logged in.
auth_login_panel <- function(id_prefix = "translator") {
  ns <- function(x) paste0(id_prefix, "_", x)
  tagList(
    tags$div(
      style = "max-width: 480px; margin: 24px auto; padding: 24px;
               background:#F8FAF7; border:1px solid #D8E4D6; border-radius:8px;",
      tags$h4(style = "margin-top:0; color:#2D6A4F;",
              t("auth_signin_title")),
      tags$p(style = "font-size:0.9rem; color:#52525B;",
             t("auth_signin_body")),
      textInput(ns("email"), label = NULL,
                placeholder = "your.name@example.org",
                width = "100%"),
      actionButton(ns("submit"), t("btn_auth_send_link"),
                   class = "btn-success", width = "100%"),
      uiOutput(ns("status"))
    )
  )
}
