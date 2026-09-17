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
# cache_write_1h = the extended 1-hour cache write (2x input). Added
# 2026-09-17 when the 1-hour TTL was re-enabled for long prefixes (plan F2);
# the June objection to the 1-hour cache was only that this rate was
# missing and the log under-reported.
.ANTHROPIC_PRICING <- list(
  "claude-opus-4-8"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75, cache_write_1h = 30.00),
  "claude-opus-4-7"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75, cache_write_1h = 30.00),
  "claude-opus-4-6"   = list(input = 15.00, output = 75.00,
                                cache_read = 1.50, cache_write = 18.75, cache_write_1h = 30.00),
  "claude-sonnet-4-6" = list(input = 3.00,  output = 15.00,
                                cache_read = 0.30, cache_write = 3.75, cache_write_1h = 6.00),
  "claude-haiku-4-5-20251001" = list(input = 1.00, output = 5.00,
                                         cache_read = 0.10, cache_write = 1.25, cache_write_1h = 2.00),
  # Claude Mythos 5 (Project Glasswing). Same API surface as Fable 5;
  # $10/$50 per 1M. cache_read = 10% of input; cache_write = 5-min rate (1.25x).
  "claude-mythos-5"   = list(input = 10.00, output = 50.00,
                                cache_read = 1.00, cache_write = 12.50, cache_write_1h = 20.00)
)

# Prefix size above which the stable prefix is cached for one hour instead
# of five minutes (plan F2). A five-minute cache is lost whenever the user
# takes longer than that to answer a question, or a batch streams for longer
# than that, and the whole prefix is then re-written at 1.25x. Above this
# size a single 2x write at the start of the run is cheaper than the second
# 1.25x write, and every later stage reads at 10 %. Below it, a run finishes
# inside five minutes and the 1-hour write would be pure surcharge.
.ANTHROPIC_1H_PREFIX_TOKENS <- 40000L
.anthropic_est_tokens <- function(x) as.integer(ceiling(nchar(x, type = "bytes") / 3.6))
# 2026-06-11: switched from Opus 4.8 to Sonnet 4.6 after Andy's 26-sub-cat
# Zambia file timed out at 900s on Opus and a 10-sub-cat fallback returned
# only 2 of 10 sub-categories. Same task ran fine on claude.ai web (Sonnet).
# Sonnet 4.6 is ~2x faster, 5x cheaper, and at least as disciplined as Opus
# on schema-bound emission. Chat reasoning quality is slightly less than
# Opus but acceptable for this protocol-following workflow. Flip back to
# Opus 4.8 if real-world quality drops noticeably.
# Default model is overridable via the TRANSLATOR_MODEL env var (.Renviron) so an
# A/B run can flip the whole translator to e.g. claude-mythos-5 without code edits
# — every anthropic_chat* call site uses this default (none passes model=).
.ANTHROPIC_DEFAULT_MODEL <- Sys.getenv("TRANSLATOR_MODEL", unset = "claude-sonnet-4-6")
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

# Build a cache_control block. ttl = NULL uses Anthropic's default 5-minute
# ephemeral cache; ttl = "1h" requests the extended 1-hour cache (which needs
# the `anthropic-beta: extended-cache-ttl-2025-04-11` request header, added in
# anthropic_chat_stream when cache_ttl is set).
#
# Why the 1-hour option exists: in the batched-emission flow a single batch can
# take 5-17 min to stream, so the 5-minute cache expires BETWEEN batches and
# each batch re-pays the full cache-WRITE surcharge on the ~170K conversation
# prefix — the dominant cost per the 2026-06-12 Zambia logs ($4.78 of $7.73).
# A 1-hour TTL writes that prefix once (at 2x input price instead of 1.25x) and
# re-reads it at 10% for every later batch in the run, roughly halving per-run
# cost with NO change to the output.
.anthropic_cache_ctl <- function(ttl = NULL) {
  if (is.null(ttl)) list(type = "ephemeral")
  else list(type = "ephemeral", ttl = ttl)
}

# Build the `system` payload for Anthropic. When the system prompt is
# non-trivial (>= 1024 chars — Anthropic's cache eligibility threshold),
# wrap it in a content block with cache_control: ephemeral so the long
# translator prompt gets cached and re-billed at 10% on subsequent calls.
.anthropic_system_payload <- function(system_text, ttl = NULL) {
  if (!nzchar(system_text)) return(NULL)
  # Ephemeral cache only kicks in for blocks >= ~1024 tokens. Below that
  # we just send the text and skip the cache_control overhead.
  if (nchar(system_text) < 4096) return(system_text)
  list(list(
    type = "text",
    text = system_text,
    cache_control = .anthropic_cache_ctl(ttl)
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
.anthropic_cache_last_message <- function(messages, ttl = NULL) {
  n <- length(messages)
  if (n == 0) return(messages)
  last <- messages[[n]]
  content <- last$content %||% ""
  if (!is.character(content)) return(messages)  # already a block array
  if (!nzchar(content)) return(messages)
  messages[[n]]$content <- list(list(
    type = "text",
    text = content,
    cache_control = .anthropic_cache_ctl(ttl)
  ))
  messages
}

# Add TWO cache breakpoints to the messages array:
#  (1) on the last message (same as anthropic_cache_last_message)
#  (2) on the SECOND-TO-LAST message (i.e. the last message that's
#      identical across a batched-emission loop)
#
# Why: in the batched-emission flow, the per-batch user message
# (batch_nudge) differs on every batch — so a cache_control marker
# placed only on the last message creates a fresh cache key each
# batch and re-writes the entire ~170K conversation history every
# time. Production logs from the 2026-06-12 Zambia run showed all
# 5 batches paying $1.0-1.2 each, with $4.78 of the $7.73 total
# being cache-write surcharges (171K × $3.75/M × 5 batches).
#
# By ALSO marking the second-to-last message — which IS identical
# across all batches (it's the last item of state$messages, the
# user's prior confirmation) — the prefix UP TO that point gets
# cached once on batch 1 and re-read at 10% cost on batches 2-5.
# Anthropic supports up to 4 cache breakpoints per request; we use
# 3 (system prompt + 2 here), leaving 1 spare.
#
# Falls back to single-breakpoint behaviour when messages has < 2
# entries.
.anthropic_cache_stable_and_last <- function(messages, ttl = NULL) {
  n <- length(messages)
  if (n < 2L) return(.anthropic_cache_last_message(messages, ttl = ttl))
  # Mark message n-1 first (the stable, batch-invariant prefix). This is the
  # block that should carry the 1-hour TTL in the batch flow — it is identical
  # across all batches, so it's written once and re-read on every later batch.
  prev <- messages[[n - 1L]]
  prev_content <- prev$content %||% ""
  if (is.character(prev_content) && nzchar(prev_content)) {
    messages[[n - 1L]]$content <- list(list(
      type = "text",
      text = prev_content,
      cache_control = .anthropic_cache_ctl(ttl)
    ))
  }
  # Then mark message n (the batch-specific nudge). It changes every batch and
  # is never re-read, so it keeps the cheap default 5-minute ephemeral write
  # regardless of `ttl` — paying the 2x 1-hour write surcharge on a throwaway
  # block would be pure waste.
  .anthropic_cache_last_message(messages)
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
                                cache_write_tokens = 0L,
                                cache_write_1h_tokens = 0L) {
  p <- .ANTHROPIC_PRICING[[model]]
  if (is.null(p)) {
    warning(sprintf("Unknown Anthropic model '%s'; cost reported as NA.",
                     model), call. = FALSE)
    return(NA_real_)
  }
  (max(input_tokens %||% 0L, 0L)        / 1e6) * p$input       +
  (max(output_tokens %||% 0L, 0L)       / 1e6) * p$output      +
  (max(cache_read_tokens %||% 0L, 0L)   / 1e6) * p$cache_read  +
  (max(cache_write_tokens %||% 0L, 0L)  / 1e6) * p$cache_write +
  (max(cache_write_1h_tokens %||% 0L, 0L) / 1e6) * (p$cache_write_1h %||% (2 * p$input))
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
.ANTHROPIC_NO_TEMPERATURE_MODELS <- c("claude-opus-4-8", "claude-mythos-5")

# Resolve the API key for a given model. Claude Mythos 5 is on a separate
# Project Glasswing account, so it uses MYTHOS_API_KEY when set; everything
# else uses ANTHROPIC_API_KEY. Falls back to ANTHROPIC_API_KEY if MYTHOS_API_KEY
# is unset (e.g. the org's main key also has Mythos access).
.anthropic_api_key_for <- function(model) {
  if (identical(model, "claude-mythos-5")) {
    k <- Sys.getenv("MYTHOS_API_KEY", unset = "")
    if (nzchar(k)) return(k)
  }
  Sys.getenv("ANTHROPIC_API_KEY", unset = "")
}

# --- Main entry point: blocking ---------------------------------------------
#
# Same return shape as openai_chat(): list(reply, usage, model, cost_usd, error).
anthropic_chat <- function(messages,
                            model = .ANTHROPIC_DEFAULT_MODEL,
                            max_tokens = 16000,
                            temperature = 0.2,
                            timeout_sec = 90) {
  # Provider switch (throwaway A/B test): a Mistral model id routes to the
  # Mistral client (R/mistral_client.R). Claude path untouched otherwise.
  if (.is_mistral_model(model))
    return(mistral_chat(messages = messages, model = model,
                        max_tokens = max_tokens, temperature = temperature,
                        timeout_sec = timeout_sec))
  t0 <- Sys.time()
  api_key <- .anthropic_api_key_for(model)
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
      error    = NULL,
      latency_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
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
                                   # Optional keep-alive callback fired on
                                   # every input_json_delta event during a
                                   # tool_use stream. Text streams call
                                   # on_chunk for every token (which is
                                   # already a heartbeat). Tool_use streams
                                   # accumulate JSON silently — without
                                   # on_tick the user sees a frozen UI for
                                   # the entire 5-15 min force-template
                                   # emission. Default: no-op.
                                   on_tick = function() {},
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
                                   tool_choice = NULL,
                                   # cache_ttl: "auto" (default) picks the
                                   # 1-hour cache for the stable prefix when
                                   # the prefix exceeds .ANTHROPIC_1H_PREFIX_
                                   # TOKENS, and the 5-minute cache otherwise
                                   # (plan F2). "1h" / NULL force either.
                                   cache_ttl = "auto") {
  # Provider switch (throwaway A/B test): a Mistral model id routes the whole
  # streaming path — including every forced-template call that funnels through
  # here (template_force / enumerate / batch) — to the Mistral client
  # (R/mistral_client.R). Claude path untouched otherwise.
  if (.is_mistral_model(model))
    return(mistral_chat_stream(messages = messages, on_chunk = on_chunk,
                               on_tick = on_tick, model = model,
                               max_tokens = max_tokens, temperature = temperature,
                               timeout_sec = timeout_sec, max_retries = max_retries,
                               tools = tools, tool_choice = tool_choice,
                               cache_ttl = cache_ttl))
  t0 <- Sys.time()
  api_key <- .anthropic_api_key_for(model)
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the ANTHROPIC_API_KEY). Please contact the administrator."))
  }

  split <- .anthropic_split_system(messages)
  # Resolve "auto": measure the stable prefix (system + every message but
  # the last) and take the 1-hour cache above the threshold. Anthropic
  # requires 1-hour breakpoints to precede 5-minute ones; the helpers below
  # mark the system block and message n-1 with the chosen TTL and message n
  # with the 5-minute default, which satisfies that ordering.
  if (identical(cache_ttl, "auto")) {
    n_msg <- length(split$messages)
    prefix_chars <- nchar(split$system, type = "bytes") +
      sum(vapply(split$messages[seq_len(max(0L, n_msg - 1L))], function(m) {
        cc <- m$content
        if (is.character(cc)) nchar(cc, type = "bytes") else
          sum(vapply(cc, function(b) nchar(b$text %||% "", type = "bytes"), integer(1)))
      }, integer(1)))
    cache_ttl <- if (ceiling(prefix_chars / 3.6) > .ANTHROPIC_1H_PREFIX_TOKENS) "1h" else NULL
  }
  # When tools are present, this is a batched / discovery / force-template
  # call — the LAST message varies per batch (different aggregation_level
  # nudge) while the SECOND-TO-LAST message is the stable, batch-invariant
  # conversation history. Use the two-breakpoint cache helper so the long
  # ~170K conversation prefix is cached once on batch 1 and re-read at 10%
  # cost on batches 2-5. Production cost driver per 2026-06-12 logs.
  # Since 2026-09-17 every translator call carries the tool block (plan F1),
  # so this is the branch chat turns take as well.
  cache_msgs <- if (is.null(tools))
    .anthropic_cache_last_message(split$messages, ttl = cache_ttl)
  else
    .anthropic_cache_stable_and_last(split$messages, ttl = cache_ttl)
  body <- list(
    model       = model,
    max_tokens  = max_tokens,
    messages    = cache_msgs,
    stream      = TRUE
  )
  if (!(model %in% .ANTHROPIC_NO_TEMPERATURE_MODELS))
    body$temperature <- temperature
  sys_payload <- .anthropic_system_payload(split$system, ttl = cache_ttl)
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
  cache_write   <- 0L    # 5-minute cache writes
  cache_write1h <- 0L    # 1-hour cache writes (billed at 2x input)
  sse_buffer    <- ""

  repeat {
    attempt <- attempt + 1
    accumulated <- ""; tool_json_acc <- ""; tool_block <- NULL
    usage_in <- 0L; usage_out <- 0L; cache_read <- 0L; cache_write <- 0L
    cache_write1h <- 0L
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
          # The API splits cache creation by TTL when the 1-hour cache is in
          # play (usage.cache_creation.ephemeral_5m_input_tokens /
          # ephemeral_1h_input_tokens). Prefer that breakdown; without it,
          # attribute the total to whichever TTL this request asked for.
          cc <- u$cache_creation
          if (is.list(cc) && (!is.null(cc$ephemeral_5m_input_tokens) ||
                              !is.null(cc$ephemeral_1h_input_tokens))) {
            cache_write   <<- cc$ephemeral_5m_input_tokens %||% 0L
            cache_write1h <<- cc$ephemeral_1h_input_tokens %||% 0L
          } else {
            tot <- u$cache_creation_input_tokens %||% 0L
            if (identical(cache_ttl, "1h")) cache_write1h <<- tot else cache_write <<- tot
          }
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
            # Keep-alive: tool_use streams produce no on_chunk callback,
            # so without this the UI freezes for the entire emission.
            tryCatch(on_tick(), error = function(e) {
              message("translator stream on_tick error: ",
                      conditionMessage(e))
            })
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
    # Extended (1-hour) prompt cache requires this beta header. Only sent when
    # cache_ttl is set, so default 5-minute calls are unchanged. req_headers
    # merges with the headers already set above.
    if (!is.null(cache_ttl))
      req <- httr2::req_headers(req,
                                `anthropic-beta` = "extended-cache-ttl-2025-04-11")

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
                     cache_write_1h_tokens = cache_write1h,
                     total_tokens       = usage_in + usage_out +
                                            cache_read + cache_write + cache_write1h),
    model    = model,
    cache_ttl = cache_ttl %||% "5m",
    cost_usd = anthropic_cost_usd(
      input_tokens       = usage_in,
      output_tokens      = usage_out,
      model              = model,
      cache_read_tokens  = cache_read,
      cache_write_tokens = cache_write,
      cache_write_1h_tokens = cache_write1h),
    error    = NULL,
    latency_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  )
}

# --- The translator's ONE tool ------------------------------------------------
#
# 2026-09-17 (plan F1). Until now the discovery call, the per-level batch
# call and the monolithic call each defined a different tool. Anthropic builds
# the prompt-cache prefix as tools -> system -> messages, so every stage
# started a fresh cache and the same ~120K-token conversation prefix was
# written three to seven times per run: about 60 % of a Zambia run's cost.
#
# There is now a single tool, `emit_inventory_piece`, whose input carries a
# `mode` field. The tool block is byte-identical from the first chat turn
# onwards (chat calls carry it with tool_choice = none), so discovery and
# every batch READ the prefix instead of writing it.
#
# What this trades away: the old batch schema could REQUIRE
# parameter_timeseries, and the old monolithic schema could require
# parameters. One schema cannot require different fields per mode without
# JSON-Schema conditionals, which we do not send because we cannot test the
# API's acceptance of them without a paid call. The per-mode requirements are
# stated in each property's description and in the nudge text, and the
# server validates presence after the call (see .translator_validate_piece
# in chat_ui.R). If a future measured run shows the model dropping
# parameter_timeseries again, add an allOf/if/then block here and test it.
#
# Schema additions in the same change: `region` on inventory_metadata (plan
# A4; every translator workbook used to be stamped "africa") and a
# `data_source` enum on parameter rows (plan A9; the prompt demanded it but
# the schema let the model omit it, and the defaults-only guard depends on
# it).
.ANTHROPIC_TOOL_NAME <- "emit_inventory_piece"

.ANTHROPIC_DATA_SOURCES <- c("user_file", "user_chat", "ipcc_default",
                             "biological_zero", "placeholder")
.ANTHROPIC_REGIONS <- c("africa", "asia", "europe", "americas", "oceania", "global")

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
    param_type        = list(type = "string", enum = I(c("activity_data", "coefficient"))),
    data_source       = list(type = "string", enum = I(.ANTHROPIC_DATA_SOURCES),
                             description = paste(
                               "Where the mean came from: user_file (uploaded file),",
                               "user_chat (typed in chat), ipcc_default (catalogue),",
                               "biological_zero (structural zero), placeholder."))
  ),
  required = I(c("sub_category", "parameter", "mean", "distribution",
                 "param_type", "data_source"))
)

.ANTHROPIC_MANURE_ITEM_SCHEMA <- list(
  type = "object",
  properties = list(
    cattle_type       = list(type = "string"),
    aggregation_level = list(type = "string"),
    sub_category      = list(type = "string"),
    mms_type          = list(type = "string"),
    fraction_pct      = list(type = "number", description = "percent of manure to this system; per-group rows sum to 100"),
    lower_fraction    = list(type = c("number", "null")),
    upper_fraction    = list(type = c("number", "null")),
    distribution_fraction = list(type = c("string", "null")),
    MCF_pct           = list(type = c("number", "null"), description = "methane conversion factor in PERCENT (5 means 5 %)"),
    lower_mcf         = list(type = c("number", "null")),
    upper_mcf         = list(type = c("number", "null")),
    distribution_mcf  = list(type = c("string", "null")),
    EF3               = list(type = c("number", "null"), description = "direct N2O EF as a FRACTION (0.01)"),
    lower_ef3         = list(type = c("number", "null")),
    upper_ef3         = list(type = c("number", "null")),
    distribution_ef3  = list(type = c("string", "null")),
    Frac_GasMS_pct    = list(type = c("number", "null"), description = "volatilisation fraction in PERCENT (45 means 45 %)"),
    lower_frac_gas    = list(type = c("number", "null")),
    upper_frac_gas    = list(type = c("number", "null")),
    distribution_frac_gas = list(type = c("string", "null")),
    Frac_LeachMS_pct  = list(type = c("number", "null"), description = "leaching fraction in PERCENT (2 means 2 %)"),
    lower_frac_leach  = list(type = c("number", "null")),
    upper_frac_leach  = list(type = c("number", "null")),
    distribution_frac_leach = list(type = c("string", "null"))
  ),
  required = I(c("sub_category", "mms_type", "fraction_pct",
                 "MCF_pct", "EF3", "Frac_GasMS_pct", "Frac_LeachMS_pct"))
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
  # I() keeps the length-1 vector a JSON array; without it jsonlite unboxes
  # to "required":"year" and Anthropic rejects the schema (bug 31aaec1).
  required = I(c("year"))
)

.ANTHROPIC_METADATA_SCHEMA <- list(
  type = "object",
  properties = list(
    country      = list(type = "string"),
    region       = list(type = "string", enum = I(.ANTHROPIC_REGIONS),
                        description = "continent of the herd, from the country: Zimbabwe -> africa, India -> asia, Brazil -> americas"),
    year         = list(type = c("integer", "string")),
    species      = list(type = "string"),
    ipcc_version = list(type = "string"),
    prepared_by  = list(type = "string"),
    notes        = list(type = "string")
  ),
  required = I(c("country", "region", "species", "ipcc_version"))
)

.ANTHROPIC_TOOL_INPUT_SCHEMA <- list(
  type = "object",
  properties = list(
    mode = list(
      type = "string", enum = I(c("enumerate", "batch", "full")),
      description = paste(
        "Which piece the server asked for. enumerate: aggregation_levels +",
        "inventory_metadata only. batch: aggregation_level (echoed) +",
        "parameters + manure_management + parameter_timeseries for that one",
        "level. full: inventory_metadata + parameters + manure_management +",
        "parameter_timeseries for the whole inventory.")),
    inventory_metadata = .ANTHROPIC_METADATA_SCHEMA,
    aggregation_levels = list(
      type = "array", items = list(type = "string"),
      description = paste(
        "mode = enumerate only. The distinct production-system labels for",
        "this inventory, snake_case, lowercase, one per system the user",
        "confirmed.")),
    aggregation_level = list(
      type = "string",
      description = paste(
        "mode = batch only. The aggregation_level the user message asked",
        "for, echoed back exactly; the server drops rows that do not match.")),
    parameters = list(type = "array", items = .ANTHROPIC_PARAMETER_ITEM_SCHEMA,
      description = "mode = batch or full. One row per (sub_category, parameter), every catalogue parameter."),
    manure_management = list(type = "array", items = .ANTHROPIC_MANURE_ITEM_SCHEMA,
      description = "mode = batch or full. One row per (sub_category, mms_type)."),
    parameter_timeseries = list(type = "array", items = .ANTHROPIC_TIMESERIES_ITEM_SCHEMA,
      description = paste(
        "mode = batch or full. REQUIRED in those modes, [] when the file has",
        "no multi-year activity data. One row per (sub_category, year),",
        "filling only the columns that change across years."))
  ),
  required = I(c("mode"))
)

# The tool list sent on EVERY translator call, chat turns included, so the
# cache prefix never changes shape. Chat turns pass tool_choice = none.
anthropic_translator_tools <- function() {
  list(list(
    name         = .ANTHROPIC_TOOL_NAME,
    description  = paste(
      "Emit one piece of the user's filled IPCC cattle inventory template,",
      "as directed by the `mode` the server's message names. Called only",
      "when the server asks; never from a chat reply."),
    input_schema = .ANTHROPIC_TOOL_INPUT_SCHEMA))
}
.ANTHROPIC_TOOL_CHOICE_FORCE <- list(type = "tool", name = .ANTHROPIC_TOOL_NAME)
.ANTHROPIC_TOOL_CHOICE_NONE  <- list(type = "none")

# --- Force-template variant (tool_use) -----------------------------------------
#
# mode = full. The model is forced to call the tool once with the whole
# inventory. Streaming collects the partial_json fragments and returns the
# assembled JSON string as $reply, which the downstream
# .translator_template_is_well_formed() / write_template_xlsx pipeline expects.
anthropic_chat_template_force <- function(messages,
                                            on_chunk = function(text) {},
                                            on_tick  = function() {},
                                            model = .ANTHROPIC_DEFAULT_MODEL,
                                            # 2026-06-10: 64K. 32K truncated
                                            # ~26-sub-cat inventories into a
                                            # non-parseable blob with no
                                            # obvious cause.
                                            max_tokens = 64000,
                                            # 2026-06-11: 900 -> 1800 after a
                                            # 27 x 25 = 675-row emission was
                                            # still streaming past 900 s.
                                            # tool_use input_json_delta is
                                            # slower than text streaming.
                                            timeout_sec = 1800) {
  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    on_tick     = on_tick,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = anthropic_translator_tools(),
    tool_choice = .ANTHROPIC_TOOL_CHOICE_FORCE
  )
}

# Stage 1 of the batched emission flow: mode = enumerate. Cheap (~200 output
# tokens). Returns { mode, aggregation_levels: [...], inventory_metadata: {...} }.
anthropic_chat_enumerate_aggregation_levels <- function(messages,
                                                          on_chunk = function(text) {},
                                                          on_tick  = function() {},
                                                          model = .ANTHROPIC_DEFAULT_MODEL,
                                                          max_tokens = 4000,
                                                          timeout_sec = 120) {
  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    on_tick     = on_tick,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = anthropic_translator_tools(),
    tool_choice = .ANTHROPIC_TOOL_CHOICE_FORCE
  )
}

# Stage 2 of the batched emission flow: mode = batch, one call per
# aggregation_level. The caller's nudge names the level; the model echoes it
# in `aggregation_level` for merge-time drift detection.
#
# max_tokens 48000: the 2026-06-11 extensive_trad batch (6 sub-cats x 25
# params + 48 MMS + 33-year x 6 x ~5 TS params) truncated at 24K.
# timeout 900 s: that batch at ~35 tok/s is ~1000 s at its cap.
anthropic_chat_batch_template_force <- function(messages,
                                                  on_chunk = function(text) {},
                                                  on_tick  = function() {},
                                                  model = .ANTHROPIC_DEFAULT_MODEL,
                                                  max_tokens = 48000,
                                                  timeout_sec = 900) {
  anthropic_chat_stream(
    messages    = messages,
    on_chunk    = on_chunk,
    on_tick     = on_tick,
    model       = model,
    max_tokens  = max_tokens,
    temperature = 0,
    timeout_sec = timeout_sec,
    tools       = anthropic_translator_tools(),
    tool_choice = .ANTHROPIC_TOOL_CHOICE_FORCE
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
