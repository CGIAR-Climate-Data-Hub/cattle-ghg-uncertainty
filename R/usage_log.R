# Token + spend ledger for the in-app AI translator.
#
# Each successful OpenAI call appends one row to a local CSV. A
# month-to-date spend check is run BEFORE every API call; if the cap is
# exceeded, the caller refuses the request and surfaces a "monthly cap
# reached" message to the user.
#
# IMPORTANT — shinyapps.io ephemerality:
#
# The shinyapps.io free/starter tiers do not have persistent storage.
# The container is recycled on idle and the local CSV resets to empty.
# This means the in-app cap is BEST-EFFORT only — a container restart
# resets the month-to-date counter.
#
# The REAL hard ceiling is set on OpenAI's side, by the account holder
# (Lolita), at <https://platform.openai.com/account/limits>. The plan
# recommends $20/month — a 2× buffer above this app's $10/month soft cap.
# OpenAI itself stops billing the account at the hard limit regardless
# of what the in-app log reports.
#
# If we later need a true persistent ledger, a Google Sheet via
# `googlesheets4` is the lightweight upgrade path. Out of scope for the
# pilot.

# Resolve a directory we can write to in any deployment context.
.usage_log_dir <- function() {
  # Honour an explicit override (used by tests / dev).
  override <- Sys.getenv("TRANSLATOR_LOG_DIR", unset = "")
  if (nzchar(override)) return(override)
  # On shinyapps.io the working dir IS writable (just ephemeral).
  # Locally we use the working dir too — keeps dev and prod identical.
  getwd()
}

.usage_log_path <- function() {
  file.path(.usage_log_dir(), "translator_usage_log.csv")
}

.usage_log_columns <- c(
  "timestamp", "user_email", "model",
  "prompt_tokens", "completion_tokens", "total_tokens",
  "cached_tokens",       # cache READ hits — Anthropic: 90% off / GPT-4.1: ~50% off
  "cache_write_tokens",  # cache WRITE on first turn — Anthropic only, +25% on input
  "cost_usd"
)

# Create the file with a header row if it doesn't already exist.
.usage_log_ensure <- function() {
  path <- .usage_log_path()
  if (!file.exists(path)) {
    df <- as.data.frame(matrix(character(0), ncol = length(.usage_log_columns),
                                dimnames = list(NULL, .usage_log_columns)))
    utils::write.csv(df, path, row.names = FALSE)
  }
  path
}

# Append one row.  Caller passes the OPenAI response shape from
# anthropic_chat() ($usage, $model, $cost_usd) plus the user_email.
usage_log_append <- function(user_email, model,
                              prompt_tokens, completion_tokens, cost_usd,
                              cached_tokens = 0L,
                              cache_write_tokens = 0L,
                              ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                                           tz = "UTC")) {
  path <- .usage_log_ensure()
  row  <- data.frame(
    timestamp         = ts,
    user_email        = user_email %||% "unknown",
    model             = model %||% NA_character_,
    prompt_tokens     = as.integer(prompt_tokens %||% 0L),
    completion_tokens = as.integer(completion_tokens %||% 0L),
    total_tokens      = as.integer((prompt_tokens %||% 0L) +
                                    (completion_tokens %||% 0L)),
    cached_tokens     = as.integer(cached_tokens %||% 0L),
    cache_write_tokens = as.integer(cache_write_tokens %||% 0L),
    cost_usd          = as.numeric(cost_usd %||% 0),
    stringsAsFactors  = FALSE
  )
  # Append without re-writing the header.
  utils::write.table(row, path, sep = ",",
                     append    = TRUE,
                     row.names = FALSE,
                     col.names = FALSE,
                     quote     = c(2, 3))    # quote user_email + model
  invisible(row)
}

# Read the log back as a data.frame; empty data.frame with the right
# schema when the file doesn't exist yet.
usage_log_read <- function() {
  path <- .usage_log_path()
  if (!file.exists(path) || file.info(path)$size == 0)
    return(data.frame(matrix(character(0), ncol = length(.usage_log_columns),
                              dimnames = list(NULL, .usage_log_columns)),
                       stringsAsFactors = FALSE))
  df <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                  error = function(e) NULL)
  if (is.null(df)) return(data.frame())
  df
}

# Sum of cost_usd since the start of the current month (UTC).
# Returns 0 if the log is empty or unreadable. Used to gate against the
# monthly cap.
month_to_date_spend <- function() {
  df <- usage_log_read()
  if (nrow(df) == 0 || !"cost_usd" %in% names(df)) return(0)
  ts <- suppressWarnings(as.POSIXct(df$timestamp, tz = "UTC",
                                      format = "%Y-%m-%dT%H:%M:%SZ"))
  month_start <- as.POSIXct(format(Sys.time(), "%Y-%m-01 00:00:00", tz = "UTC"),
                             tz = "UTC")
  current <- !is.na(ts) & ts >= month_start
  sum(as.numeric(df$cost_usd[current]), na.rm = TRUE)
}

# Read the monthly cap from the env var (set on shinyapps.io).
# Sentinels for "no cap" (added 2026-06-10 after Andy hit the $30 cap
# mid-conversation and we decided to let the Anthropic billing console be
# the only ceiling): if the env var is unset, empty, "0", "none", "off",
# or "unlimited", the in-app cap is treated as infinite — every call goes
# through and the only "out of credits" surface is Anthropic's own 400
# (handled in .anthropic_status_msg).
monthly_budget_cap_usd <- function() {
  raw <- tolower(trimws(Sys.getenv("MONTHLY_BUDGET_CAP_USD", unset = "")))
  if (!nzchar(raw) || raw %in% c("0", "none", "off", "unlimited", "inf"))
    return(Inf)
  cap <- suppressWarnings(as.numeric(raw))
  if (!is.finite(cap) || cap <= 0) return(Inf)
  cap
}

# Returns TRUE if the next API call would push us over the cap.
# Conservative: assumes the next call costs as much as the LARGEST call
# we've seen this month (so the very first call of the month always goes
# through). The actual per-call estimate from the chat UI takes
# precedence if it's supplied. Always returns FALSE when the cap is Inf
# (i.e. the env var sentinel "no cap" is in effect).
budget_would_exceed <- function(estimated_next_cost = NULL) {
  cap <- monthly_budget_cap_usd()
  if (!is.finite(cap)) return(FALSE)
  spent <- month_to_date_spend()
  if (is.null(estimated_next_cost)) {
    df <- usage_log_read()
    estimated_next_cost <- if (nrow(df) > 0) max(as.numeric(df$cost_usd),
                                                  na.rm = TRUE) else 0
  }
  (spent + estimated_next_cost) > cap
}

# Human-friendly status string for display under the chat panel
# ("Pilot budget: $1.42 / $10.00 used this month"). This is the GLOBAL
# spend across all users — shown to the admin only.
budget_status_line <- function() {
  cap <- monthly_budget_cap_usd()
  if (!is.finite(cap))
    sprintf("Pilot spend (all users): $%.2f this month — no in-app cap (Anthropic billing console controls the ceiling)",
            month_to_date_spend())
  else
    sprintf("Pilot budget (all users): $%.2f / $%.2f used this month",
            month_to_date_spend(), cap)
}

# Per-user spend — month-to-date and lifetime. Case-insensitive email
# match. Returns 0 if log is empty / unreadable / email NULL.
#
# IMPORTANT: shinyapps.io recycles the container on idle, which resets
# the local CSV. So "lifetime" really means "since this container last
# booted." The container has been up for `<unknown>` time — the user
# should treat these numbers as best-effort. The authoritative number
# lives in OpenAI's billing dashboard.
.user_spend_filter <- function(df, email) {
  if (nrow(df) == 0 || is.null(email) || !nzchar(email)) return(df[0, , drop = FALSE])
  match <- !is.na(df$user_email) &
            tolower(trimws(df$user_email)) == tolower(trimws(email))
  df[match, , drop = FALSE]
}

user_spend_month <- function(email) {
  df <- .user_spend_filter(usage_log_read(), email)
  if (nrow(df) == 0) return(0)
  ts <- suppressWarnings(as.POSIXct(df$timestamp, tz = "UTC",
                                      format = "%Y-%m-%dT%H:%M:%SZ"))
  month_start <- as.POSIXct(format(Sys.time(), "%Y-%m-01 00:00:00", tz = "UTC"),
                             tz = "UTC")
  current <- !is.na(ts) & ts >= month_start
  sum(as.numeric(df$cost_usd[current]), na.rm = TRUE)
}

user_spend_lifetime <- function(email) {
  df <- .user_spend_filter(usage_log_read(), email)
  if (nrow(df) == 0) return(0)
  sum(as.numeric(df$cost_usd), na.rm = TRUE)
}

# "Your usage — $0.34 this month / $1.78 lifetime"
# Returns "" when email is missing (e.g. user not signed in yet).
user_spend_status_line <- function(email) {
  if (is.null(email) || !nzchar(email)) return("")
  sprintf("Your usage — $%.2f this month / $%.2f lifetime",
          user_spend_month(email), user_spend_lifetime(email))
}
