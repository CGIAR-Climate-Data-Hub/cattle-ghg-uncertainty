# Per-user conversation history for the in-app AI translator.
#
# Stores the chat transcript on disk so the user can close the tab,
# reload the page (we have a persistent sign-in cookie now), and resume
# where they left off — instead of starting from a blank chat.
#
# Caveats:
#
#   * On shinyapps.io free/starter tiers the container is recycled when
#     idle and the on-disk history is wiped along with everything else.
#     This is best-effort persistence, not durable storage. A user who
#     comes back after a container restart will see an empty chat.
#
#   * Storage is one JSON file per user, named with a SHA-256 of the
#     email so listing the directory doesn't reveal user identities.
#     The file content does carry the email (and the chat content) in
#     the clear — anyone with shell access to the container could read
#     it. Acceptable for the pilot (data is non-sensitive UNFCCC
#     reporting); not acceptable for production.

.history_dir <- function() {
  override <- Sys.getenv("TRANSLATOR_HISTORY_DIR", unset = "")
  if (nzchar(override)) return(override)
  getwd()
}

.history_path <- function(user_email) {
  e <- tolower(trimws(user_email %||% ""))
  if (!nzchar(e)) return(NULL)
  digest <- substr(paste(as.character(openssl::sha256(charToRaw(e))),
                          collapse = ""), 1, 32)
  file.path(.history_dir(), paste0("translator_history_", digest, ".json"))
}

# Save the current `messages` list (the same shape used by chat_ui.R's
# state$messages: list of list(role, content, display)) to disk. Capped
# at the most recent 200 messages so the file stays small.
conversation_save <- function(user_email, messages) {
  path <- .history_path(user_email)
  if (is.null(path)) return(invisible(FALSE))
  if (length(messages) > 200) messages <- tail(messages, 200)
  payload <- list(
    user_email = tolower(trimws(user_email)),
    saved_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    messages   = messages
  )
  tryCatch(
    jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = FALSE,
                          force = TRUE, null = "null"),
    error = function(e) {
      message("conversation_save failed: ", conditionMessage(e))
      FALSE
    })
  invisible(TRUE)
}

# Load the saved conversation. Returns a list of message records, or
# an empty list if no history exists or the file is unreadable.
conversation_load <- function(user_email) {
  path <- .history_path(user_email)
  if (is.null(path) || !file.exists(path)) return(list())
  payload <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE),
                       error = function(e) NULL)
  if (is.null(payload) || is.null(payload$messages)) return(list())
  # Defensive: drop anything that doesn't have a role + content pair.
  Filter(function(m) {
    !is.null(m$role) && !is.null(m$content) && nzchar(m$content)
  }, payload$messages)
}

# Delete the user's saved history (used by the "Reset conversation"
# button).
conversation_delete <- function(user_email) {
  path <- .history_path(user_email)
  if (is.null(path) || !file.exists(path)) return(invisible(FALSE))
  tryCatch(file.remove(path), error = function(e) FALSE)
  invisible(TRUE)
}
