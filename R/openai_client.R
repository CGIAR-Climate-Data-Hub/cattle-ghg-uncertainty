# OpenAI API client for the in-app AI translator.
# Thin httr2 wrapper around https://api.openai.com/v1/chat/completions.
#
# Vendor + model picked per the June 2026 review: OpenAI GPT-4.1, the
# OpenAI flagship that matches Claude Sonnet's quality on structured
# data-mapping tasks (Excel column headers -> IPCC parameter names).
# Vendor swap is one function in this file.
#
# Configuration is via environment variables; the key NEVER appears in
# source. See R/usage_log.R for the per-call spend ledger and the
# monthly cap that gates this client.

# Pricing for GPT-4.1 as of 2026-06. Update when OpenAI changes prices.
# (Cost per 1M tokens, USD.)
.OPENAI_PRICING <- list(
  "gpt-4.1"     = list(input = 2.00, output = 8.00),
  "gpt-4o"      = list(input = 2.50, output = 10.00),
  "gpt-4o-mini" = list(input = 0.15, output = 0.60)
)
.OPENAI_DEFAULT_MODEL <- "gpt-4.1"
.OPENAI_ENDPOINT      <- "https://api.openai.com/v1/chat/completions"

# Assemble the system prompt from the four translator-kit asset files.
# Reuses the same .md files already in claude_project_assets/ that the
# user-facing translator kit ships, so the in-app translator and the
# downloadable kit share a single source of truth.
#
# Returns a single character string ready to be sent as the first message
# in the conversation (role = "system"). At repo root the assembled
# prompt is roughly 12-15K tokens.
assemble_translator_system_prompt <- function(asset_dir = "claude_project_assets") {
  files <- c("system_instructions.md", "param_catalogue.md",
             "template_schema.md", "mapping_examples.md", "questionnaire.md")
  parts <- lapply(files, function(f) {
    p <- file.path(asset_dir, f)
    if (!file.exists(p)) {
      warning(sprintf("Translator-kit asset missing: %s — skipping.", p),
              call. = FALSE)
      return(NULL)
    }
    paste0("# ", tools::file_path_sans_ext(f), "\n\n",
           paste(readLines(p, warn = FALSE), collapse = "\n"))
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0)
    stop("No translator-kit asset files found in ", asset_dir, call. = FALSE)

  # Sentinel marker the chat UI watches for so it knows when to surface
  # the "Download translated template" button. The system prompt tells
  # the model to emit this marker once a complete IPCC-template-shaped
  # JSON is in its response.
  marker_instruction <- paste(
    "",
    "",
    "## Output convention",
    "",
    "When you have enough information to produce a complete filled",
    "IPCC template, emit the JSON inside a fenced block tagged",
    "```template-ready ... ``` (rather than the usual ```json ... ```).",
    "The in-app UI watches for the `template-ready` tag and uses it to",
    "show a 'Download translated template' button. Do NOT emit the tag",
    "until every required parameter is filled and every clarifying",
    "question has been answered.",
    sep = "\n")

  paste(c(parts, marker_instruction), collapse = "\n\n---\n\n")
}

# Internal helper: estimate token count (approximate). OpenAI uses BPE
# tokenisation; a rule-of-thumb for English text is ~4 chars/token. We
# use this only for budget projection BEFORE a call is made; the actual
# token count comes back from the API in the `usage` block.
.estimate_tokens <- function(text) {
  if (is.null(text) || !nzchar(text)) return(0L)
  as.integer(ceiling(nchar(text) / 4))
}

# Cost in USD for a (prompt_tokens, completion_tokens, model) triple.
openai_cost_usd <- function(prompt_tokens, completion_tokens,
                             model = .OPENAI_DEFAULT_MODEL) {
  p <- .OPENAI_PRICING[[model]]
  if (is.null(p)) {
    warning(sprintf("Unknown model '%s'; cost reported as NA.", model),
            call. = FALSE)
    return(NA_real_)
  }
  (prompt_tokens     / 1e6) * p$input  +
  (completion_tokens / 1e6) * p$output
}

# Main entry point.
#
# `messages` is a list of lists, each shaped like
#   list(role = "system"|"user"|"assistant", content = "<text>").
# The function adds the OpenAI auth header from the env var, posts the
# request, and returns a list with three named slots:
#
#   $reply              character — the assistant's reply text
#   $usage              list      — prompt_tokens, completion_tokens, total_tokens
#   $model              character — the model name OpenAI confirmed
#   $cost_usd           numeric   — estimated USD cost of this call
#
# On any non-2xx response, returns a list with $error set to a
# user-friendly message and $reply = NULL. The caller (the Shiny chat
# observer) is responsible for surfacing the error to the user.
openai_chat <- function(messages,
                         model = .OPENAI_DEFAULT_MODEL,
                         max_tokens = 4000,
                         temperature = 0.2,
                         timeout_sec = 90) {
  api_key <- Sys.getenv("OPENAI_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the OPENAI_API_KEY). Please contact the administrator."))
  }

  body <- list(
    model       = model,
    messages    = messages,
    max_tokens  = max_tokens,
    temperature = temperature
  )

  req <- httr2::request(.OPENAI_ENDPOINT) |>
    httr2::req_headers(
      `Authorization` = paste("Bearer", api_key),
      `Content-Type`  = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)  # we'll inspect ourselves

  resp <- tryCatch(httr2::req_perform(req),
                    error = function(e) e)

  if (inherits(resp, "error")) {
    return(list(reply = NULL,
                error = paste0("Could not reach OpenAI (", conditionMessage(resp),
                               "). Try again in a minute.")))
  }

  status <- httr2::resp_status(resp)
  if (status >= 200 && status < 300) {
    parsed <- httr2::resp_body_json(resp)
    reply <- tryCatch(parsed$choices[[1]]$message$content,
                       error = function(e) NULL)
    if (is.null(reply) || !nzchar(reply)) {
      return(list(reply = NULL,
                  error = "OpenAI returned an empty reply. Try again."))
    }
    usage <- parsed$usage %||% list(prompt_tokens = 0L,
                                     completion_tokens = 0L,
                                     total_tokens = 0L)
    list(
      reply    = reply,
      usage    = usage,
      model    = parsed$model %||% model,
      cost_usd = openai_cost_usd(usage$prompt_tokens %||% 0L,
                                  usage$completion_tokens %||% 0L,
                                  parsed$model %||% model),
      error    = NULL
    )
  } else {
    # Map common error statuses to user-friendly messages.
    user_msg <- switch(as.character(status),
      "401" = "AI translator authentication failed. The server's OPENAI_API_KEY is missing or invalid — please contact the administrator.",
      "403" = "AI translator is blocked by OpenAI. The administrator may need to add billing or remove a usage cap.",
      "429" = "OpenAI is rate-limiting requests. Try again in a minute.",
      "500" = "OpenAI is having trouble. Try again later.",
      "502" = "OpenAI is having trouble. Try again later.",
      "503" = "OpenAI is having trouble. Try again later.",
      "504" = "OpenAI is having trouble. Try again later.",
      sprintf("OpenAI returned an unexpected error (HTTP %d). Try again later.", status)
    )
    # Try to surface the API's own error_message for diagnostics — but
    # don't show it to the user (could leak request internals); log via
    # message() so it lands in the Shiny server log.
    tryCatch({
      body <- httr2::resp_body_json(resp)
      msg  <- body$error$message %||% ""
      if (nzchar(msg)) message("OpenAI error body: ", msg)
    }, error = function(e) NULL)
    list(reply = NULL, error = user_msg)
  }
}

# Convenience: build the message list for the chat UI from
# (system_prompt, history, new_user_message).
openai_build_messages <- function(system_prompt, history = list(),
                                   new_user_message = NULL) {
  msgs <- list(list(role = "system", content = system_prompt))
  for (m in history) {
    if (!is.null(m$role) && !is.null(m$content) && nzchar(m$content))
      msgs[[length(msgs) + 1]] <- list(role = m$role, content = m$content)
  }
  if (!is.null(new_user_message) && nzchar(new_user_message))
    msgs[[length(msgs) + 1]] <- list(role = "user", content = new_user_message)
  msgs
}
