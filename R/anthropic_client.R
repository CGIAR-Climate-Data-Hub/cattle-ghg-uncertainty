# Anthropic Claude API client for the in-app AI translator.
# Thin httr2 wrapper around https://api.anthropic.com/v1/messages.
#
# 2026-06 vendor swap: GPT-4.1 quality on real African inventory uploads
# was not good enough — Lolita's review found the model hallucinated
# parameter mappings on multi-sheet templates. Switched to Claude Opus 4.8
# (the current latest Opus per Anthropic's 2026 pricing page).
#
# Surface mirrors R/openai_client.R so chat_ui.R only needs find/replace
# `openai_` -> `anthropic_`. See that file for the function contracts.
#
# Configuration: ANTHROPIC_API_KEY env var (set in .Renviron). The key
# NEVER appears in source. See R/usage_log.R for the per-call spend
# ledger and the monthly cap that gates this client.

# Pricing for Anthropic Claude models as of 2026-06 (per 1M tokens, USD).
# input  = regular input tokens (non-cached)
# output = output tokens
# cache_read  = cache hits (90% discount on input price)
# cache_write = cache creation (25% surcharge on input price)
# Verify against https://www.anthropic.com/pricing if prices change.
.ANTHROPIC_PRICING <- list(
  "claude-opus-4-8"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75),
  "claude-opus-4-7"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75),
  "claude-opus-4-6"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75),
  "claude-sonnet-4-6" = list(input = 3.00,  output = 15.00,
                                cache_read = 0.30, cache_write = 3.75),
  "claude-haiku-4-5-20251001" = list(input = 1.00, output = 5.00,
                                         cache_read = 0.10, cache_write = 1.25)
)
# 2026-06-11: switched from Opus 4.8 to Sonnet 4.6 after Andy's 26-sub-cat
# Zambia file timed out at 900s on Opus and a 10-sub-cat fallback returned
# only 2 of 10 sub-categories. Same task ran fine on claude.ai web (Sonnet).
# Sonnet 4.6 is ~2x faster, 5x cheaper, and at least as disciplined as Opus
# on schema-bound emission. Chat reasoning quality is slightly less than
# Opus but acceptable for this protocol-following workflow. Flip back to
# Opus 4.8 if real-world quality drops noticeably.
.ANTHROPIC_DEFAULT_MODEL <- "claude-sonnet-4-6"
.ANTHROPIC_ENDPOINT      <- "https://api.anthropic.com/v1/messages"
.ANTHROPIC_VERSION       <- "2023-06-01"

# --- Message-list normalisation --------------------------------------------
#
# chat_ui.R + openai_build_messages prepend a {role:"system", content:...}
# message to the conversation. Anthropic's API takes the system prompt as
# a separate top-level `system` field — it is NOT a member of `messages`.
# This helper splits an OpenAI-shaped message list into:
#   $system   character — the system prompt content (or "")
#   $messages list of {role, content} with only user/assistant turns
.anthropic_split_system <- function(messages) {
  if (length(messages) == 0) return(list(system = "", messages = list()))
  system_text <- ""
  out <- list()
  for (m in messages) {
    role <- m$role %||% ""
    if (identical(role, "system")) {
      # Concatenate any additional system messages (rare but defensible).
      if (nzchar(system_text)) system_text <- paste0(system_text, "\n\n")
      system_text <- paste0(system_text, m$content %||% "")
    } else if (identical(role, "user") || identical(role, "assistant")) {
      out[[length(out) + 1]] <- list(role = role, content = m$content %||% "")
    }
  }
  list(system = system_text, messages = out)
}

# Build the `system` payload for Anthropic. When the system prompt is
# non-trivial (>= 1024 chars — Anthropic's cache eligibility threshold),
# wrap it in a content block with cache_control: ephemeral so the long
# translator prompt gets cached and re-billed at 10% on subsequent calls.
.anthropic_system_payload <- function(system_text) {
  if (!nzchar(system_text)) return(NULL)
  # Ephemeral cache only kicks in for blocks >= ~1024 tokens. Below that
  # we just send the text and skip the cache_control overhead.
  if (nchar(system_text) < 4096) return(system_text)
  list(list(
    type = "text",
    text = system_text,
    cache_control = list(type = "ephemeral")
  ))
}

# Add cache_control: ephemeral to the LAST entry of the messages array
# so the conversation prefix is cached too. Without this, each new turn
# re-pays the full input cost for every prior user + assistant message
# (15 USD/M for Opus 4.8). With this, every subsequent turn within 5
# minutes reads the prior history at 10% of input price — typical 90%
# saving on multi-turn conversations.
#
# Anthropic accepts up to 4 cache breakpoints per request. We're using
# one on the system prompt and one here on the last message — leaves
# two spare for future use.
#
# IMPORTANT: the cache_control marker MUST be present on every request
# that wants to read the cache. Anthropic only consults the cache at a
# block flagged with cache_control. The 1024-token minimum applies to
# the CUMULATIVE prefix (system + messages up to the marked block), NOT
# to the marked block alone — so we mark the last message regardless of
# its size. Short final messages (a one-word reply like "go") still let
# the cache for all prior turns hit. Skipping the marker on short
# messages was the bug in the first attempt — turn 2 missed the cache
# entirely.
#
# The content of the marked message must be a content-block array
# {type:"text", text:..., cache_control:...}. Anthropic accepts both
# string and block-array forms for input messages; we convert the
# marked one.
.anthropic_cache_last_message <- function(messages) {
  n <- length(messages)
  if (n == 0) return(messages)
  last <- messages[[n]]
  content <- last$content %||% ""
  if (!is.character(content)) return(messages)  # already a block array
  if (!nzchar(content)) return(messages)
  messages[[n]]$content <- list(list(
    type = "text",
    text = content,
    cache_control = list(type = "ephemeral")
  ))
  messages
}

# Cost in USD for a usage tuple, taking Anthropic's prompt-cache discount
# into account. Usage shape (from the API response):
#   $input_tokens                 — non-cached input
#   $cache_creation_input_tokens  — tokens written to cache this turn
#   $cache_read_input_tokens      — tokens read from cache this turn
#   $output_tokens                — generated output
anthropic_cost_usd <- function(input_tokens, output_tokens,
                                model = .ANTHROPIC_DEFAULT_MODEL,
                                cache_read_tokens = 0L,
                                cache_write_tokens = 0L) {
  p <- .ANTHROPIC_PRICING[[model]]
  if (is.null(p)) {
    warning(sprintf("Unknown Anthropic model '%s'; cost reported as NA.",
                     model), call. = FALSE)
    return(NA_real_)
  }
  (max(input_tokens %||% 0L, 0L)        / 1e6) * p$input       +
  (max(output_tokens %||% 0L, 0L)       / 1e6) * p$output      +
  (max(cache_read_tokens %||% 0L, 0L)   / 1e6) * p$cache_read  +
  (max(cache_write_tokens %||% 0L, 0L)  / 1e6) * p$cache_write
}

# Map a status code to a user-friendly message. Used by both the
# blocking and streaming variants.
.anthropic_status_msg <- function(status, error_body_msg = NULL) {
  # Log the raw API message regardless of how we choose to surface it.
  if (!is.null(error_body_msg) && nzchar(error_body_msg))
    message("Anthropic error body: ", error_body_msg)

  # "Out of credits" detection. Anthropic returns either 400 or 402 with
  # body wording like "Your credit balance is too low" / "billing" /
  # "credits exhausted". Show a friendly user-facing message that does
  # NOT reveal the dollar amount or that there's a per-app cap — the
  # user just needs to know the AI service is temporarily unavailable
  # and the admin will deal with it.
  is_billing <- !is.null(error_body_msg) && nzchar(error_body_msg) &&
    grepl("credit\\s*balance|insufficient\\s*credit|billing|credits\\s*exhausted|out\\s*of\\s*credit",
          error_body_msg, ignore.case = TRUE, perl = TRUE)
  if (is_billing) {
    return(paste0(
      "The AI translator is temporarily unavailable. ",
      "We've been notified and will restore service shortly — ",
      "please try again in a few hours, or contact the administrator ",
      "if it persists."))
  }

  switch(as.character(status),
    "400" = if (!is.null(error_body_msg) && nzchar(error_body_msg))
              paste0("AI translator request was rejected by Anthropic: ",
                      error_body_msg, ". Please contact the administrator.")
            else "AI translator request was rejected by Anthropic. Please try again or contact the administrator.",
    "401" = "AI translator authentication failed. The server's ANTHROPIC_API_KEY is missing or invalid — please contact the administrator.",
    "402" = "The AI translator is temporarily unavailable. We've been notified and will restore service shortly.",
    "403" = "AI translator is blocked by Anthropic. The administrator may need to add billing or remove a usage cap.",
    "404" = "AI translator endpoint or model is unavailable. Please contact the administrator.",
    "413" = "Your message is too large for the AI to process. Try splitting the file or removing very large sheets.",
    "429" = "Anthropic is rate-limiting requests. Try again in a minute.",
    "500" = "Anthropic is having trouble. Try again later.",
    "529" = "Anthropic is overloaded. Try again in a minute.",
    "502" = "Anthropic is having trouble. Try again later.",
    "503" = "Anthropic is having trouble. Try again later.",
    "504" = "Anthropic is having trouble. Try again later.",
    sprintf("Anthropic returned HTTP %d. Try again later.", status))
}

# Models that reject the `temperature` parameter. Claude Opus 4.8 (and
# likely later Opus releases) only accept the default; sending temperature
# at all returns 400 "temperature is deprecated for this model". Older
# models still accept it. Keep this list explicit so we don't silently
# strip temperature from models that expect it.
.ANTHROPIC_NO_TEMPERATURE_MODELS <- c("claude-opus-4-8")

# --- Main entry point: blocking ---------------------------------------------
#
# Same return shape as openai_chat(): list(reply, usage, model, cost_usd, error).
anthropic_chat <- function(messages,
                            model = .ANTHROPIC_DEFAULT_MODEL,
                            max_tokens = 16000,
                            temperature = 0.2,
                            timeout_sec = 90) {
  api_key <- Sys.getenv("ANTHROPIC_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the ANTHROPIC_API_KEY). Please contact the administrator."))
  }

  split <- .anthropic_split_system(messages)
  body <- list(
    model       = model,
    max_tokens  = max_tokens,
    messages    = .anthropic_cache_last_message(split$messages)
  )
  if (!(model %in% .ANTHROPIC_NO_TEMPERATURE_MODELS))
    body$temperature <- temperature
  sys_payload <- .anthropic_system_payload(split$system)
  if (!is.null(sys_payload)) body$system <- sys_payload

  req <- httr2::request(.ANTHROPIC_ENDPOINT) |>
    httr2::req_headers(
      `x-api-key`         = api_key,
      `anthropic-version` = .ANTHROPIC_VERSION,
      `Content-Type`      = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(reply = NULL,
                error = paste0("Could not reach Anthropic (",
                                conditionMessage(resp),
                                "). Try again in a minute.")))
  }

  status <- httr2::resp_status(resp)
  if (status >= 200 && status < 300) {
    parsed <- httr2::resp_body_json(resp)
    # Anthropic responses carry the assistant text inside content blocks of
    # type "text". Concatenate any text blocks; ignore tool_use blocks here
    # (the force-template path uses a separate extractor).
    reply <- ""
    if (length(parsed$content) > 0) {
      for (block in parsed$content) {
        if (identical(block$type, "text") && !is.null(block$text))
          reply <- paste0(reply, block$text)
      }
    }
    if (!nzchar(reply)) {
      return(list(reply = NULL,
                  error = "Anthropic returned an empty reply. Try again."))
    }
    usage <- parsed$usage %||% list()
    list(
      reply    = reply,
      usage    = list(
        prompt_tokens     = usage$input_tokens %||% 0L,
        completion_tokens = usage$output_tokens %||% 0L,
        cached_tokens     = usage$cache_read_input_tokens %||% 0L,
        cache_write_tokens = usage$cache_creation_input_tokens %||% 0L,
        total_tokens      = (usage$input_tokens %||% 0L) +
                            (usage$output_tokens %||% 0L) +
                            (usage$cache_read_input_tokens %||% 0L) +
                            (usage$cache_creation_input_tokens %||% 0L)),
      model    = parsed$model %||% model,
      cost_usd = anthropic_cost_usd(
        input_tokens       = usage$input_tokens %||% 0L,
        output_tokens      = usage$output_tokens %||% 0L,
        model              = parsed$model %||% model,
        cache_read_tokens  = usage$cache_read_input_tokens %||% 0L,
        cache_write_tokens = usage$cache_creation_input_tokens %||% 0L),
      error    = NULL
    )
  } else {
    body_msg <- tryCatch({
      b <- httr2::resp_body_json(resp)
      b$error$message %||% ""
    }, error = function(e) "")
    list(reply = NULL,
         error = .anthropic_status_msg(status, body_msg))
  }
}

# --- Streaming variant ------------------------------------------------------
#
# Same shape as openai_chat_stream(): on_chunk(text) callback fires for
# each incremental token. Returns the assembled reply + usage + cost.
#
# Anthropic SSE event shapes consumed:
#   event: message_start          { message: { usage: { input_tokens, ... } } }
#   event: content_block_start    { index, content_block: { type:"text"|"tool_use", ... } }
#   event: content_block_delta    { index, delta: { type:"text_delta", text }
#                                              | { type:"input_json_delta", partial_json } }
#   event: content_block_stop
#   event: message_delta          { usage: { output_tokens } }
#   event: message_stop
anthropic_chat_stream <- function(messages,
                                   on_chunk = function(text) {},
                                   model = .ANTHROPIC_DEFAULT_MODEL,
                                   max_tokens = 16000,
                                   temperature = 0.2,
                                   # 2026-06-11: raised from 180s to 900s
                                   # after Andy's 26-sub-cat Zambia file
                                   # produced an exploration response that
                                   # legitimately needed 5-8 minutes of
                                   # streaming output (5 production systems
                                   # x 7 sub-categories x 15 parameters =
                                   # ~600 rows in section B alone). The
                                   # low_speed_time=45 stall detector below
                                   # is still the safety net — wall-clock
                                   # only kills calls that are genuinely
                                   # making progress for over 15 minutes.
                                   timeout_sec = 900,
                                   max_retries = 2,
                                   tools = NULL,
                                   tool_choice = NULL) {
  api_key <- Sys.getenv("ANTHROPIC_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the ANTHROPIC_API_KEY). Please contact the administrator."))
  }

  split <- .anthropic_split_system(messages)
  body <- list(
    model       = model,
    max_tokens  = max_tokens,
    messages    = .anthropic_cache_last_message(split$messages),
    stream      = TRUE
  )
  if (!(model %in% .ANTHROPIC_NO_TEMPERATURE_MODELS))
    body$temperature <- temperature
  sys_payload <- .anthropic_system_payload(split$system)
  if (!is.null(sys_payload)) body$system <- sys_payload
  if (!is.null(tools)) body$tools <- tools
  if (!is.null(tool_choice)) body$tool_choice <- tool_choice

  attempt    <- 0
  last_err   <- NULL
  final_resp <- NULL

  # Per-attempt state, reset on each retry.
  accumulated   <- ""    # concatenated text deltas (the user-visible reply)
  tool_json_acc <- ""    # accumulated partial_json from input_json_delta
  tool_block    <- NULL  # captured tool_use content_block (name + initial input)
  usage_in      <- 0L
  usage_out     <- 0L
  cache_read    <- 0L
  cache_write   <- 0L
  sse_buffer    <- ""

  repeat {
    attempt <- attempt + 1
    accumulated <- ""; tool_json_acc <- ""; tool_block <- NULL
    usage_in <- 0L; usage_out <- 0L; cache_read <- 0L; cache_write <- 0L
    sse_buffer <- ""

    on_data <- function(data) {
      chunk_text <- rawToChar(data)
      sse_buffer <<- paste0(sse_buffer, chunk_text)
      while (grepl("\n\n", sse_buffer, fixed = TRUE)) {
        split2 <- regmatches(sse_buffer,
                              regexpr("\n\n", sse_buffer, fixed = TRUE),
                              invert = TRUE)[[1]]
        event       <- split2[1]
        sse_buffer <<- if (length(split2) >= 2) split2[2] else ""

        event_type <- NULL
        payload    <- NULL
        for (line in strsplit(event, "\n", fixed = TRUE)[[1]]) {
          if (startsWith(line, "event: ")) {
            event_type <- substring(line, 8)
          } else if (startsWith(line, "data: ")) {
            payload <- substring(line, 7)
          }
        }
        if (is.null(payload) || payload == "[DONE]") next

        parsed <- tryCatch(
          jsonlite::fromJSON(payload, simplifyVector = FALSE),
          error = function(e) NULL)
        if (is.null(parsed)) next

        # message_start carries initial usage incl. cache_read/cache_write.
        if (identical(event_type, "message_start") ||
            identical(parsed$type, "message_start")) {
          u <- parsed$message$usage %||% list()
          usage_in    <<- u$input_tokens               %||% usage_in
          usage_out   <<- u$output_tokens              %||% usage_out
          cache_read  <<- u$cache_read_input_tokens    %||% cache_read
          cache_write <<- u$cache_creation_input_tokens %||% cache_write
        }
        # content_block_start opens either a "text" or "tool_use" block.
        if (identical(parsed$type, "content_block_start")) {
          cb <- parsed$content_block %||% list()
          if (identical(cb$type, "tool_use")) {
            tool_block <<- list(
              id    = cb$id   %||% "",
              name  = cb$name %||% "",
              input = cb$input %||% list())
            tool_json_acc <<- ""
          }
        }
        # content_block_delta carries text or tool-input fragments.
        if (identical(parsed$type, "content_block_delta")) {
          d <- parsed$delta %||% list()
          if (identical(d$type, "text_delta") && !is.null(d$text)) {
            accumulated <<- paste0(accumulated, d$text)
            tryCatch(on_chunk(d$text), error = function(e) {
              message("translator stream on_chunk error: ",
                      conditionMessage(e))
            })
          } else if (identical(d$type, "input_json_delta") &&
                      !is.null(d$partial_json)) {
            tool_json_acc <<- paste0(tool_json_acc, d$partial_json)
          }
        }
        # message_delta carries final output_tokens (+ stop_reason).
        if (identical(parsed$type, "message_delta")) {
          u <- parsed$usage %||% list()
          if (!is.null(u$output_tokens)) usage_out <<- u$output_tokens
        }
      }
      TRUE
    }

    req <- httr2::request(.ANTHROPIC_ENDPOINT) |>
      httr2::req_headers(
        `x-api-key`         = api_key,
        `anthropic-version` = .ANTHROPIC_VERSION,
        `Content-Type`      = "application/json",
        `Accept`            = "text/event-stream"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(timeout_sec) |>
      # Stall detector — same rationale as the OpenAI client.
      httr2::req_options(low_speed_time = 45L, low_speed_limit = 1L) |>
      httr2::req_error(is_error = function(resp) FALSE)

    resp <- tryCatch(
      httr2::req_perform_stream(req, on_data, buffer_kb = 16),
      error = function(e) e)

    if (inherits(resp, "error")) {
      last_err <- conditionMessage(resp)
      status   <- NA_integer_
    } else {
      last_err <- NULL
      status   <- httr2::resp_status(resp)
    }

    success_status <- !is.na(status) && status >= 200 && status < 300
    transient_status <- !is.na(status) && (status == 429 || status >= 500)
    network_error    <- inherits(resp, "error")

    if (success_status) { final_resp <- resp; break }
    # Don't retry mid-stream — user already saw some text.
    if (nzchar(accumulated) || nzchar(tool_json_acc)) {
      final_resp <- resp; break
    }
    if (!network_error && !transient_status) { final_resp <- resp; break }
    if (attempt > max_retries) { final_resp <- resp; break }

    delay <- c(1, 3)[min(attempt, 2)]
    message(sprintf("anthropic_chat_stream: retrying after %ds (attempt %d/%d, status=%s)",
                     delay, attempt, max_retries + 1L,
                     if (is.na(status)) last_err else as.character(status)))
    Sys.sleep(delay)
  }

  resp <- final_resp
  if (inherits(resp, "error")) {
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = paste0("Streaming failed (", last_err,
                                "). Try again in a minute.")))
  }
  status <- httr2::resp_status(resp)
  if (status >= 300) {
    body_msg <- tryCatch({
      b <- httr2::resp_body_json(resp); b$error$message %||% ""
    }, error = function(e) "")
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = .anthropic_status_msg(status, body_msg)))
  }

  # If a tool_use block streamed in, surface its accumulated JSON as the
  # reply. The force-template caller hands this off to fromJSON; the
  # regular chat path never sets tools, so this branch only fires for the
  # "Produce template now" route.
  final_reply <- if (!is.null(tool_block) && nzchar(tool_json_acc)) {
    tool_json_acc
  } else {
    accumulated
  }

  list(
    reply    = final_reply,
    usage    = list(prompt_tokens      = usage_in,
                     completion_tokens  = usage_out,
                     cached_tokens      = cache_read,
                     cache_write_tokens = cache_write,
                     total_tokens       = usage_in + usage_out +
                                            cache_read + cache_write),
    model    = model,
    cost_usd = anthropic_cost_usd(
      input_tokens       = usage_in,
      output_tokens      = usage_out,
      model              = model,
      cache_read_tokens  = cache_read,
      cache_write_tokens = cache_write),
    error    = NULL
  )
}

# --- Force-template variant (tool_use schema) -------------------------------
#
# Same contract as openai_chat_template_force(): the model is forced to
# emit a single tool_use call whose `input` matches the filled-template
# schema. The streaming SSE collects the partial_json fragments and
# returns the assembled JSON string as $reply — exactly what the
# downstream .translator_template_is_well_formed() / write_template_xlsx
# pipeline expects.
anthropic_chat_template_force <- function(messages,
                                            on_chunk = function(text) {},
                                            model = .ANTHROPIC_DEFAULT_MODEL,
                                            # 2026-06-10: 64K (probed up
                                            # to 128K on Opus 4.8). 32K was
                                            # tight for ~26-sub-cat inventories
                                            # where parameters+manure_management
                                            # +parameter_timeseries can hit
                                            # ~30K tokens. 64K gives 2x
                                            # headroom; truncation here
                                            # produces a non-parseable JSON
                                            # blob and the user gets no
                                            # download with no obvious cause.
                                            max_tokens = 64000,
                                            # 2026-06-11: bumped 900 -> 1800
                                            # after Lolita's full Zambia run
                                            # (27 sub-categories x 25 params =
                                            # 675 rows) was still streaming
                                            # past the 900s ceiling. tool_use
                                            # input_json_delta is empirically
                                            # slower than text streaming
                                            # (~8000 individual JSON fragments
                                            # for this output). 1800s gives
                                            # headroom up to roughly the
                                            # shinyapps.io WebSocket-tolerance
                                            # ceiling; beyond this, the real
                                            # fix is server-side batch
                                            # emission across aggregation_level.
                                            timeout_sec = 1800) {
  # Same schema as the OpenAI version, surfaced as an Anthropic tool with
  # input_schema. Anthropic uses JSON Schema for tool inputs; the structure
  # is the same as OpenAI's json_schema mode minus the strict envelope.
  input_schema <- list(
    type = "object",
    properties = list(
      inventory_metadata = list(
        type = "object",
        properties = list(
          country      = list(type = "string"),
          year         = list(type = c("integer", "string")),
          species      = list(type = "string"),
          ipcc_version = list(type = "string"),
          prepared_by  = list(type = "string"),
          notes        = list(type = "string")
        )
      ),
      parameters = list(
        type  = "array",
        items = list(
          type = "object",
          properties = list(
            cattle_type       = list(type = "string"),
            aggregation_level = list(type = "string"),
            sub_category      = list(type = "string"),
            parameter         = list(type = "string"),
            mean              = list(type = "number"),
            uncertainty_pct   = list(type = c("number", "null")),
            lower             = list(type = c("number", "null")),
            upper             = list(type = c("number", "null")),
            distribution      = list(type = "string"),
            param_type        = list(type = "string")
          ),
          required = c("sub_category", "parameter", "mean",
                        "distribution", "param_type")
        )
      ),
      manure_management = list(
        type  = "array",
        items = list(
          type = "object",
          properties = list(
            cattle_type       = list(type = "string"),
            aggregation_level = list(type = "string"),
            sub_category      = list(type = "string"),
            mms_type          = list(type = "string"),
            fraction_pct      = list(type = "number"),
            lower_fraction    = list(type = c("number", "null")),
            upper_fraction    = list(type = c("number", "null")),
            distribution_fraction = list(type = c("string", "null")),
            MCF_pct           = list(type = c("number", "null")),
            lower_mcf         = list(type = c("number", "null")),
            upper_mcf         = list(type = c("number", "null")),
            distribution_mcf  = list(type = c("string", "null")),
            EF3               = list(type = c("number", "null")),
            lower_ef3         = list(type = c("number", "null")),
            upper_ef3         = list(type = c("number", "null")),
            distribution_ef3  = list(type = c("string", "null")),
            Frac_GasMS_pct    = list(type = c("number", "null")),
            lower_frac_gas    = list(type = c("number", "null")),
            upper_frac_gas    = list(type = c("number", "null")),
            distribution_frac_gas = list(type = c("string", "null")),
            Frac_LeachMS_pct  = list(type = c("number", "null")),
            lower_frac_leach  = list(type = c("number", "null")),
            upper_frac_leach  = list(type = c("number", "null")),
            distribution_frac_leach = list(type = c("string", "null"))
          ),
          required = c("sub_category", "mms_type", "fraction_pct",
                        "MCF_pct", "EF3",
                        "Frac_GasMS_pct", "Frac_LeachMS_pct")
        )
      ),
      # 2026-06-10: Parameter_TimeSeries. Optional. One row per
      # (group, year). The 10 correlated parameters from
      # param_catalogue.md "Sex-and-physiology" section. Emit only when
      # the user's source file has multi-year activity data (≥ 5 years
      # ideally; the app's correlation step needs at least 4 with first-
      # difference detrending). Leave the array empty when no multi-year
      # data exists — emitting fabricated time series is a hallucination.
      parameter_timeseries = list(
        type  = "array",
        items = list(
          type = "object",
          properties = list(
            cattle_type       = list(type = c("string", "null")),
            aggregation_level = list(type = c("string", "null")),
            sub_category      = list(type = c("string", "null")),
            year              = list(type = "integer"),
            N                 = list(type = c("number", "null")),
            BW                = list(type = c("number", "null")),
            MW                = list(type = c("number", "null")),
            WG                = list(type = c("number", "null")),
            Milk              = list(type = c("number", "null")),
            Fat               = list(type = c("number", "null")),
            pct_pregnant      = list(type = c("number", "null")),
            DE                = list(type = c("number", "null")),
            CP                = list(type = c("number", "null")),
            MilkPR            = list(type = c("number", "null"))
          ),
          # I() preserves the length-1 character vector as a JSON array.
          # Without it jsonlite auto-unboxes to "required":"year" which
          # Anthropic rejects with "JSON schema is invalid (must match
          # JSON Schema draft 2020-12)". Same bug pattern as the top-level
          # required = I(c("parameters")) below — applies to every `required`
          # whose value is a length-1 character vector.
          required = I(c("year"))
        )
      )
    ),
    # I() preserves the single-element vector as a JSON array — same
    # reason as the OpenAI version. Anthropic also rejects scalar string
    # for the schema-level `required`.
    required = I(c("parameters"))
  )

  tool_def <- list(list(
    name         = "produce_filled_inventory_template",
    description  = "Emit the user's filled IPCC inventory template as JSON.",
    input_schema = input_schema
  ))
  tool_choice <- list(type = "tool",
                       name = "produce_filled_inventory_template")

  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = tool_def,
    tool_choice = tool_choice
  )
}

# --- Batch-emission helpers (Lolita's 2026-06-11 Zambia stress-test fix) ----
#
# Reusable item-schemas for the batch-emission tool. Same shapes as the
# monolithic anthropic_chat_template_force() above; factored out so the
# Stage-2 per-aggregation-level tool can reuse them verbatim without
# diverging. Touch these in ONE place when the template schema evolves.
.ANTHROPIC_PARAMETER_ITEM_SCHEMA <- list(
  type = "object",
  properties = list(
    cattle_type       = list(type = "string"),
    aggregation_level = list(type = "string"),
    sub_category      = list(type = "string"),
    parameter         = list(type = "string"),
    mean              = list(type = "number"),
    uncertainty_pct   = list(type = c("number", "null")),
    lower             = list(type = c("number", "null")),
    upper             = list(type = c("number", "null")),
    distribution      = list(type = "string"),
    param_type        = list(type = "string")
  ),
  required = c("sub_category", "parameter", "mean",
                "distribution", "param_type")
)

.ANTHROPIC_MANURE_ITEM_SCHEMA <- list(
  type = "object",
  properties = list(
    cattle_type       = list(type = "string"),
    aggregation_level = list(type = "string"),
    sub_category      = list(type = "string"),
    mms_type          = list(type = "string"),
    fraction_pct      = list(type = "number"),
    lower_fraction    = list(type = c("number", "null")),
    upper_fraction    = list(type = c("number", "null")),
    distribution_fraction = list(type = c("string", "null")),
    MCF_pct           = list(type = c("number", "null")),
    lower_mcf         = list(type = c("number", "null")),
    upper_mcf         = list(type = c("number", "null")),
    distribution_mcf  = list(type = c("string", "null")),
    EF3               = list(type = c("number", "null")),
    lower_ef3         = list(type = c("number", "null")),
    upper_ef3         = list(type = c("number", "null")),
    distribution_ef3  = list(type = c("string", "null")),
    Frac_GasMS_pct    = list(type = c("number", "null")),
    lower_frac_gas    = list(type = c("number", "null")),
    upper_frac_gas    = list(type = c("number", "null")),
    distribution_frac_gas = list(type = c("string", "null")),
    Frac_LeachMS_pct  = list(type = c("number", "null")),
    lower_frac_leach  = list(type = c("number", "null")),
    upper_frac_leach  = list(type = c("number", "null")),
    distribution_frac_leach = list(type = c("string", "null"))
  ),
  required = c("sub_category", "mms_type", "fraction_pct",
                "MCF_pct", "EF3",
                "Frac_GasMS_pct", "Frac_LeachMS_pct")
)

.ANTHROPIC_TIMESERIES_ITEM_SCHEMA <- list(
  type = "object",
  properties = list(
    cattle_type       = list(type = c("string", "null")),
    aggregation_level = list(type = c("string", "null")),
    sub_category      = list(type = c("string", "null")),
    year              = list(type = "integer"),
    N                 = list(type = c("number", "null")),
    BW                = list(type = c("number", "null")),
    MW                = list(type = c("number", "null")),
    WG                = list(type = c("number", "null")),
    Milk              = list(type = c("number", "null")),
    Fat               = list(type = c("number", "null")),
    pct_pregnant      = list(type = c("number", "null")),
    DE                = list(type = c("number", "null")),
    CP                = list(type = c("number", "null")),
    MilkPR            = list(type = c("number", "null"))
  ),
  required = I(c("year"))
)

.ANTHROPIC_METADATA_SCHEMA <- list(
  type = "object",
  properties = list(
    country      = list(type = "string"),
    year         = list(type = c("integer", "string")),
    species      = list(type = "string"),
    ipcc_version = list(type = "string"),
    prepared_by  = list(type = "string"),
    notes        = list(type = "string")
  )
)

# Stage 1 of the batched emission flow.
#
# Asks the model to enumerate the `aggregation_level` strings it has
# identified in the conversation AND populate the inventory_metadata
# object. Cheap (~200 output tokens, 5-10s). Output shape:
#
#   { aggregation_levels: ["commercial_dairy", ...],
#     inventory_metadata: { country, year, species, ... } }
#
# The caller passes this list to anthropic_chat_batch_template_force()
# below, once per aggregation_level. inventory_metadata is consumed
# only once (the per-batch calls don't emit it).
anthropic_chat_enumerate_aggregation_levels <- function(messages,
                                                          on_chunk = function(text) {},
                                                          model = .ANTHROPIC_DEFAULT_MODEL,
                                                          max_tokens = 4000,
                                                          timeout_sec = 120) {
  input_schema <- list(
    type = "object",
    properties = list(
      aggregation_levels = list(
        type  = "array",
        items = list(type = "string"),
        description = paste(
          "The distinct production-system / aggregation_level labels you",
          "have identified from this conversation, in the order they",
          "appear (e.g. ['commercial_dairy', 'emergent_dairy',",
          "'commercial_beef', 'emergent_beef', 'extensive_trad']). One",
          "entry per production system the user wants in the final",
          "template. Snake-case, lowercase.")
      ),
      inventory_metadata = .ANTHROPIC_METADATA_SCHEMA
    ),
    required = I(c("aggregation_levels"))
  )

  tool_def <- list(list(
    name        = "enumerate_aggregation_levels",
    description = paste(
      "Emit (a) the distinct aggregation_level labels for this inventory",
      "and (b) the inventory_metadata block (country, year, species, etc.).",
      "Do NOT emit any parameters, manure_management, or time-series rows",
      "here — those come in per-aggregation-level follow-up calls."),
    input_schema = input_schema
  ))
  tool_choice <- list(type = "tool",
                       name = "enumerate_aggregation_levels")

  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = tool_def,
    tool_choice = tool_choice
  )
}

# Stage 2 of the batched emission flow.
#
# Asks the model to emit ONLY the parameters / manure_management /
# parameter_timeseries rows for ONE aggregation_level. The caller is
# responsible for injecting "emit ONLY <aggregation_level>" into the
# user message (we don't do it here so the caller can attach extra
# context like the row-count assertion). The schema requires the
# returned `aggregation_level` field to match the request — used for
# server-side drift detection at merge time.
#
# max_tokens = 24000 is enough for ~5-6 sub-categories x 25 params + ~30
# MMS rows + ~33 time-series rows = ~6-8K output tokens, with 3x
# headroom for verbose descriptions / data_source tags.
#
# timeout_sec = 300 is enough for ~5 minutes per batch. If a batch
# legitimately takes longer than that, the inventory is too dense for
# the batch path and the user should split the file further upstream.
anthropic_chat_batch_template_force <- function(messages,
                                                  on_chunk = function(text) {},
                                                  model = .ANTHROPIC_DEFAULT_MODEL,
                                                  # 2026-06-11 bump: was 24000.
                                                  # Lolita's extensive_trad batch
                                                  # (6 sub-cats x 25 params + 48
                                                  # MMS + 33-year x 6 sub-cat x
                                                  # ~5 TS params = ~40K output
                                                  # tokens) truncated at 24K and
                                                  # produced unparseable JSON.
                                                  # 48K covers the largest
                                                  # realistic single-aggregation
                                                  # level emission with 2x
                                                  # headroom.
                                                  max_tokens = 48000,
                                                  # 2026-06-11 bump: was 300s.
                                                  # extensive_trad's ~40K output
                                                  # at Sonnet's ~35 tok/sec is
                                                  # ~1000s. 900s allowed the
                                                  # other 4 batches to finish
                                                  # but starved extensive_trad
                                                  # if it got close to its cap.
                                                  timeout_sec = 900) {
  input_schema <- list(
    type = "object",
    properties = list(
      aggregation_level = list(
        type        = "string",
        description = paste(
          "The aggregation_level you are emitting in this call. MUST",
          "match the aggregation_level the user message asked you to",
          "produce. The server validates this at merge time and drops",
          "rows that don't match.")),
      parameters        = list(type = "array",
                                items = .ANTHROPIC_PARAMETER_ITEM_SCHEMA),
      manure_management = list(type = "array",
                                items = .ANTHROPIC_MANURE_ITEM_SCHEMA),
      parameter_timeseries = list(type = "array",
                                    items = .ANTHROPIC_TIMESERIES_ITEM_SCHEMA)
    ),
    required = I(c("aggregation_level", "parameters"))
  )

  tool_def <- list(list(
    name        = "produce_aggregation_level_template",
    description = paste(
      "Emit ONLY the parameters / manure_management / parameter_timeseries",
      "rows for the aggregation_level named in the user message. Do NOT",
      "emit inventory_metadata (the server already has it from the",
      "discovery call). Do NOT emit rows for any other aggregation_level."),
    input_schema = input_schema
  ))
  tool_choice <- list(type = "tool",
                       name = "produce_aggregation_level_template")

  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = tool_def,
    tool_choice = tool_choice
  )
}

# --- Build OpenAI-style message list (system + history + new user) ----------
#
# Returns the same OpenAI-shaped list that openai_build_messages() does.
# The Anthropic functions above split the system message out internally
# on the way to the API. This means chat_ui.R doesn't need to change
# its build-then-call pattern.
anthropic_build_messages <- function(system_prompt, history = list(),
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
