# Mistral AI client — throwaway A/B test of the AI translator on Mistral.
#
# This is a MINIMAL, REVERSIBLE provider switch. The translator (R/chat_ui.R)
# only ever calls the anthropic_chat* family, and every forced-template path
# funnels through anthropic_chat_stream(). So routing is done in ONE place:
# anthropic_chat_stream() / anthropic_chat() check .is_mistral_model(model)
# and, when true, delegate here. Flip the whole translator to Mistral by
# setting TRANSLATOR_MODEL=mistral-large-latest (+ MISTRAL_API_KEY) in
# .Renviron; revert by setting TRANSLATOR_MODEL back to a claude-* id. No
# call-site changes, Claude path untouched.
#
# Mistral's API is OpenAI-compatible (POST /v1/chat/completions, SSE
# streaming, JSON mode). For the forced-template calls we use JSON mode
# (response_format=json_object) + content streaming rather than tool-calling:
# it streams the JSON as plain text (so the existing on_chunk UI + the
# downstream fromJSON / .translator_template_is_well_formed work unchanged),
# and the template structure is carried by the (already very detailed) system
# prompt. The Claude path enforces the schema via a tool; here it's
# prompt-enforced + validated downstream, which is the fair "can Mistral do it
# from the same prompt" test.
#
# Returns the SAME list shape as anthropic_chat_stream so chat_ui.R is none
# the wiser: list(reply, usage=list(prompt_tokens, completion_tokens,
# cached_tokens, cache_write_tokens, total_tokens), model, cost_usd, error,
# latency_sec).

.MISTRAL_ENDPOINT <- "https://api.mistral.ai/v1/chat/completions"

# Per-MTok USD. Approximate — verify against https://mistral.ai/pricing before
# trusting the cost column. mistral-large-latest as of 2026: ~$2 in / $6 out.
.MISTRAL_PRICING <- list(
  "mistral-large-latest"  = list(input = 2.00, output = 6.00),
  "mistral-large-2512"    = list(input = 2.00, output = 6.00),
  "mistral-medium-latest" = list(input = 0.40, output = 2.00),
  "magistral-medium-latest" = list(input = 2.00, output = 5.00)
)

# A model id this client should handle. Anything Mistral-family routes here.
.is_mistral_model <- function(model) {
  is.character(model) && length(model) == 1 &&
    grepl("^(mistral|magistral|ministral|codestral|devstral|open-mistral)", model)
}

mistral_cost_usd <- function(input_tokens, output_tokens, model) {
  p <- .MISTRAL_PRICING[[model]]
  if (is.null(p)) p <- list(input = 2.00, output = 6.00)   # sensible default for the test
  (input_tokens / 1e6) * p$input + (output_tokens / 1e6) * p$output
}

.mistral_api_key <- function() Sys.getenv("MISTRAL_API_KEY", unset = "")

# Convert the translator's messages (list(role, content) strings, incl. a
# leading "system" entry) straight through — Mistral accepts the same shape.
.mistral_messages <- function(messages) {
  lapply(messages, function(m) list(role = m$role, content = m$content))
}

# Streaming chat — the workhorse. tools!=NULL signals a forced-template call,
# which we serve via JSON mode + content streaming (see file header).
mistral_chat_stream <- function(messages,
                                on_chunk = function(text) {},
                                on_tick  = function() {},
                                model = "mistral-large-latest",
                                max_tokens = 16000,
                                temperature = 0.2,
                                timeout_sec = 900,
                                max_retries = 2,
                                tools = NULL,
                                tool_choice = NULL,
                                cache_ttl = NULL) {
  t0  <- Sys.time()
  key <- .mistral_api_key()
  if (!nzchar(key))
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing MISTRAL_API_KEY). Please contact the administrator."))

  mm <- .mistral_messages(messages)
  force_json <- !is.null(tools)
  if (force_json) {
    # Nudge toward bare JSON; the "JSON" keyword is also required to enable
    # Mistral's json_object response_format.
    mm[[length(mm) + 1]] <- list(
      role = "system",
      content = paste("Respond with ONLY a single valid JSON object that fills the",
                      "template described above. No markdown fences, no prose — JSON only."))
  }

  body <- list(model = model, messages = mm, max_tokens = max_tokens,
               temperature = temperature, stream = TRUE,
               stream_options = list(include_usage = TRUE))
  if (force_json) body$response_format <- list(type = "json_object")

  accumulated <- ""
  usage_in <- 0L; usage_out <- 0L
  buf <- ""

  on_data <- function(chunk) {
    text <- rawToChar(chunk); Encoding(text) <- "UTF-8"
    buf <<- paste0(buf, text)
    lines <- strsplit(buf, "\n", fixed = TRUE)[[1]]
    # Keep a trailing partial line in the buffer for the next callback.
    if (!endsWith(buf, "\n") && length(lines) > 0) {
      buf <<- lines[length(lines)]; lines <- lines[-length(lines)]
    } else {
      buf <<- ""
    }
    for (line in lines) {
      line <- trimws(line)
      if (!nzchar(line) || !startsWith(line, "data:")) next
      payload <- trimws(sub("^data:", "", line))
      if (identical(payload, "[DONE]")) next
      obj <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = FALSE),
                      error = function(e) NULL)
      if (is.null(obj)) next
      if (length(obj$choices) > 0) {
        delta <- obj$choices[[1]]$delta$content
        if (!is.null(delta) && nzchar(delta)) {
          accumulated <<- paste0(accumulated, delta)
          on_chunk(delta); on_tick()
        }
      }
      if (!is.null(obj$usage)) {
        usage_in  <<- obj$usage$prompt_tokens     %||% usage_in
        usage_out <<- obj$usage$completion_tokens %||% usage_out
      }
    }
    TRUE
  }

  req <- httr2::request(.MISTRAL_ENDPOINT) |>
    httr2::req_headers(`Authorization` = paste("Bearer", key),
                        `Content-Type`  = "application/json",
                        `Accept`        = "text/event-stream") |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform_stream(req, on_data, buffer_kb = 16),
                   error = function(e) e)

  if (inherits(resp, "error"))
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = paste0("Mistral streaming failed (", conditionMessage(resp),
                               "). Try again in a minute.")))
  status <- httr2::resp_status(resp)
  if (status >= 300) {
    emsg <- tryCatch(jsonlite::fromJSON(buf)$message, error = function(e) NULL)
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = sprintf("Mistral API error (HTTP %d)%s.", status,
                                if (!is.null(emsg)) paste0(" — ", emsg) else "")))
  }

  list(
    reply    = accumulated,
    usage    = list(prompt_tokens      = usage_in,
                     completion_tokens  = usage_out,
                     cached_tokens      = 0L,
                     cache_write_tokens = 0L,
                     total_tokens       = usage_in + usage_out),
    model    = model,
    cost_usd = mistral_cost_usd(usage_in, usage_out, model),
    error    = NULL,
    latency_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  )
}

# Non-streaming chat — for the anthropic_chat() entry point (used by any
# direct, short, non-streamed call). Same return contract.
mistral_chat <- function(messages,
                         model = "mistral-large-latest",
                         max_tokens = 16000,
                         temperature = 0.2,
                         timeout_sec = 90) {
  t0  <- Sys.time()
  key <- .mistral_api_key()
  if (!nzchar(key))
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing MISTRAL_API_KEY). Please contact the administrator."))

  body <- list(model = model, messages = .mistral_messages(messages),
               max_tokens = max_tokens, temperature = temperature)
  req <- httr2::request(.MISTRAL_ENDPOINT) |>
    httr2::req_headers(`Authorization` = paste("Bearer", key),
                        `Content-Type`  = "application/json") |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error"))
    return(list(reply = NULL, error = paste0("Network error: ", conditionMessage(resp))))
  status <- httr2::resp_status(resp)
  if (!(status %in% 200:299)) {
    emsg <- tryCatch(httr2::resp_body_json(resp)$message, error = function(e) "")
    return(list(reply = NULL, error = sprintf("Mistral API error (HTTP %d) — %s", status, emsg %||% "")))
  }
  b <- httr2::resp_body_json(resp)
  reply    <- b$choices[[1]]$message$content %||% ""
  usage_in <- b$usage$prompt_tokens %||% 0L
  usage_out<- b$usage$completion_tokens %||% 0L
  list(
    reply    = reply,
    usage    = list(prompt_tokens = usage_in, completion_tokens = usage_out,
                     cached_tokens = 0L, cache_write_tokens = 0L,
                     total_tokens = usage_in + usage_out),
    model    = model,
    cost_usd = mistral_cost_usd(usage_in, usage_out, model),
    error    = NULL,
    latency_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  )
}
