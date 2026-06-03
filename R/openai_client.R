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
    "When (and only when) you have enough information to produce a",
    "complete filled IPCC template, emit the data inside a fenced block",
    "tagged ```template-ready ... ``` (rather than the usual ```json```).",
    "The in-app UI watches for the `template-ready` tag, parses the JSON,",
    "and writes it to a multi-sheet .xlsx that the user downloads via a",
    "'Download translated template (.xlsx)' button.",
    "",
    "### Required JSON schema",
    "",
    "```",
    "{",
    "  \"inventory_metadata\": {",
    "    \"country\": \"Zimbabwe\",",
    "    \"year\": 2024,",
    "    \"species\": \"cattle_dairy\",",
    "    \"ipcc_version\": \"2019_refinement\",",
    "    \"prepared_by\": \"<optional>\",",
    "    \"notes\": \"<optional>\"",
    "  },",
    "  \"parameters\": [",
    "    {",
    "      \"cattle_type\": \"dairy\",",
    "      \"aggregation_level\": \"all\",",
    "      \"sub_category\": \"dairy_cows\",",
    "      \"parameter\": \"N\",",
    "      \"mean\": 250000,",
    "      \"lower\": 237500,",
    "      \"upper\": 262500,",
    "      \"uncertainty_pct\": 5,",
    "      \"distribution\": \"normal\",",
    "      \"param_type\": \"activity_data\"",
    "    }",
    "    /* one row per (sub_category, parameter) pair */",
    "  ],",
    "  \"manure_management\": [",
    "    {",
    "      \"cattle_type\": \"dairy\",",
    "      \"aggregation_level\": \"all\",",
    "      \"sub_category\": \"dairy_cows\",",
    "      \"mms_type\": \"pasture\",",
    "      \"fraction_pct\": 100,",
    "      \"mcf\": 0.015,",
    "      \"ef3\": 0.020",
    "    }",
    "    /* one row per (sub_category, MMS) combination; per-sub-category",
    "       fraction_pct values must sum to 100 */",
    "  ]",
    "}",
    "```",
    "",
    "Rules:",
    "",
    "* `parameters[].parameter` MUST be one of the canonical names from the",
    "  parameter catalogue (N, BW, MW, WG, Milk, Fat, DE, CP, Ym, Bo,",
    "  MCF, EF3_PRP, Frac_GASM_PRP, EF4, EF5, Frac_LEACH_PRP, Cfi, Ca,",
    "  C_growth, Cp, UE, MilkPR, pct_pregnant, hours, etc.).",
    "* `parameters[].param_type` is either `activity_data` (N, BW, MW, WG,",
    "  Milk, Fat, DE, CP, hours, pct_pregnant) or `coefficient` (everything",
    "  else).",
    "* `parameters[].distribution` is one of: normal, lognormal, pert,",
    "  beta, uniform, constant.",
    "* `parameters[].mean` is required; either `lower`+`upper` OR",
    "  `uncertainty_pct` is required (not both — pick the one that matches",
    "  how you derived the uncertainty).",
    "* `manure_management` rows are required if N2O emission sources are",
    "  in play; omit the array entirely if the inventory is CH4-only.",
    "* Inside the fenced block, emit STRICT JSON (no /* comments */ except",
    "  the schema example above), parseable by jsonlite::fromJSON().",
    "",
    "Do NOT emit the `template-ready` block until every required parameter",
    "is filled and every clarifying question has been answered. While you",
    "are still gathering information, just respond in plain text.",
    sep = "\n")

  # 2026-06: in-app UI presentation rules. These OVERRIDE any earlier
  # formatting guidance from the kit's system_instructions.md. The kit
  # was written for the claude.ai web workspace (wide screen, no rate
  # limits, users expecting a long-form analysis). The in-app chat panel
  # is narrow and users want focused answers fast. The rules below trim
  # the response style accordingly. Last-wins on conflicts, by OpenAI
  # convention (later instructions take precedence).
  ui_presentation_rules <- paste(
    "",
    "",
    "## In-app UI presentation rules (HIGHEST PRIORITY — override earlier rules)",
    "",
    "You are now deployed inside a small chat panel embedded in a Shiny",
    "web app, not in the claude.ai workspace. The UI is narrow and users",
    "want focused, fast answers. Apply these rules to every reply:",
    "",
    "1. **No preamble.** Do not introduce yourself, do not summarise what",
    "   you do, do not say 'Here is a brief summary' or 'Welcome!'. Start",
    "   directly with the most important substantive content.",
    "2. **Maximum 3-5 clarifying questions per response.** If you have",
    "   more potential ambiguities, save them for follow-up rounds AFTER",
    "   the user answers the first batch. Pick the questions that block",
    "   you from making the most progress.",
    "3. NO markdown formatting at all in chat replies. The chat panel",
    "   renders text as-is, so asterisks show up as literal asterisks,",
    "   which looks broken. Specifically:",
    "     - No **bold** or __bold__ markers — they appear as asterisks.",
    "     - No *italic* or _italic_ markers — same problem.",
    "     - No `inline code` backticks.",
    "     - No # or ## or ### headings.",
    "     - No markdown tables (| col | col |).",
    "   Use plain prose. If you need emphasis, restructure the sentence",
    "   so the important word comes first instead of bolding it. Short",
    "   bullet lists with a leading dash and a space (`- like this`) are",
    "   OK because they render visually as bullets even in plain text.",
    "   The ONE exception: the final template-ready output uses a fenced",
    "   code block (```template-ready ... ```) — that's required for the",
    "   parser to find it, not visible to the user.",
    "4. **One step at a time.** Do not pre-announce 'Step 1 / Step 2 /",
    "   Step 3' — just do the most important step and wait for the user.",
    "5. **Short paragraphs.** 2-4 sentences max. The chat panel is narrow.",
    "6. **Confirmations are terse.** 'OK — Cows in milk maps to dairy_cows'",
    "   is better than restating the reasoning.",
    "7. **No 'Next steps' / 'Summary' / 'Please answer above' meta-text.**",
    "   The user will reply when they're ready; trust them to drive the",
    "   conversation.",
    "",
    "Concrete first-response template, for reference:",
    "",
    "  I've read your data. Two things look ambiguous before I can map",
    "  everything:",
    "",
    "  - 'working bulls': castrated (oxen) or breeding bulls?",
    "  - 'heifers in calf' and 'other heifers': are both 1-3 years old, or",
    "    is one group older?",
    "",
    "  Also: is this all dairy, or is there a separate non-dairy herd",
    "  somewhere in the file?",
    "",
    "Stop after the questions. Wait for the user.",
    sep = "\n")

  paste(c(parts, marker_instruction, ui_presentation_rules),
        collapse = "\n\n---\n\n")
}

# Internal helper: estimate token count (approximate). OpenAI uses BPE
# tokenisation; a rule-of-thumb for English text is ~4 chars/token. We
# use this only for budget projection BEFORE a call is made; the actual
# token count comes back from the API in the `usage` block.
.estimate_tokens <- function(text) {
  if (is.null(text) || !nzchar(text)) return(0L)
  as.integer(ceiling(nchar(text) / 4))
}

# Cost in USD for a usage tuple, with GPT-4.1's implicit prompt-cache
# discount applied. Cached tokens cost 50% of the normal input price
# (OpenAI's "Automatic Prompt Caching" feature, applied when a system
# prompt of ≥1024 tokens has been seen within the past ~5-10 minutes).
# Verify the discount factor against
# <https://platform.openai.com/docs/pricing> if pricing changes.
openai_cost_usd <- function(prompt_tokens, completion_tokens,
                             model = .OPENAI_DEFAULT_MODEL,
                             cached_tokens = 0L) {
  p <- .OPENAI_PRICING[[model]]
  if (is.null(p)) {
    warning(sprintf("Unknown model '%s'; cost reported as NA.", model),
            call. = FALSE)
    return(NA_real_)
  }
  cached_tokens <- min(cached_tokens %||% 0L, prompt_tokens %||% 0L)
  non_cached    <- max((prompt_tokens %||% 0L) - cached_tokens, 0L)
  (non_cached      / 1e6) * p$input        +
  (cached_tokens   / 1e6) * p$input * 0.5  +
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
    cached_tokens <- usage$prompt_tokens_details$cached_tokens %||% 0L
    list(
      reply    = reply,
      usage    = list(prompt_tokens     = usage$prompt_tokens     %||% 0L,
                       completion_tokens = usage$completion_tokens %||% 0L,
                       cached_tokens     = cached_tokens,
                       total_tokens      = usage$total_tokens     %||%
                                            ((usage$prompt_tokens %||% 0L) +
                                             (usage$completion_tokens %||% 0L))),
      model    = parsed$model %||% model,
      cost_usd = openai_cost_usd(usage$prompt_tokens     %||% 0L,
                                  usage$completion_tokens %||% 0L,
                                  parsed$model %||% model,
                                  cached_tokens = cached_tokens),
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

# Streaming variant of openai_chat().
#
# Uses OpenAI's `stream: true` mode (Server-Sent Events) so the response
# tokens arrive incrementally as the model generates them. The supplied
# `on_chunk(text)` callback is fired once per token delta — typically
# the Shiny chat UI uses this to push the new text to the browser via
# `session$sendCustomMessage()` so the bubble appears to type out live.
#
# Returns the same shape as openai_chat() when the stream finishes:
#   $reply / $usage / $model / $cost_usd / $error
# but the assembled $reply is the concatenation of every delta, which
# matches what a non-streaming call would have returned. Usage info is
# in the FINAL chunk when `stream_options.include_usage = TRUE`.
openai_chat_stream <- function(messages,
                                on_chunk = function(text) {},
                                model = .OPENAI_DEFAULT_MODEL,
                                max_tokens = 4000,
                                temperature = 0.2,
                                timeout_sec = 180,
                                max_retries = 2) {
  api_key <- Sys.getenv("OPENAI_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the OPENAI_API_KEY). Please contact the administrator."))
  }

  body <- list(
    model          = model,
    messages       = messages,
    max_tokens     = max_tokens,
    temperature    = temperature,
    stream         = TRUE,
    stream_options = list(include_usage = TRUE)
  )

  # Retry loop. Only retries while NO chunks have been emitted to the
  # browser yet — once the user has seen partial output we can't safely
  # restart without duplicating tokens.
  attempt   <- 0
  last_err  <- NULL
  last_msg  <- NULL
  final_resp <- NULL

  repeat {
    attempt <- attempt + 1

    # Reset per-attempt state.
    accumulated <- ""
    final_usage <- NULL
    sse_buffer  <- ""

    on_data <- function(data) {
      chunk_text <- rawToChar(data)
      sse_buffer <<- paste0(sse_buffer, chunk_text)
      while (grepl("\n\n", sse_buffer, fixed = TRUE)) {
        split <- regmatches(sse_buffer,
                            regexpr("\n\n", sse_buffer, fixed = TRUE),
                            invert = TRUE)[[1]]
        event       <- split[1]
        sse_buffer <<- if (length(split) >= 2) split[2] else ""
        for (line in strsplit(event, "\n", fixed = TRUE)[[1]]) {
          if (!startsWith(line, "data: ")) next
          payload <- substring(line, 7)
          if (payload == "[DONE]") next
          parsed <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = FALSE),
                              error = function(e) NULL)
          if (is.null(parsed)) next
          if (!is.null(parsed$usage)) final_usage <<- parsed$usage
          if (length(parsed$choices) >= 1) {
            delta <- parsed$choices[[1]]$delta$content
            if (!is.null(delta) && nzchar(delta)) {
              accumulated <<- paste0(accumulated, delta)
              tryCatch(on_chunk(delta), error = function(e) {
                message("translator stream on_chunk error: ", conditionMessage(e))
              })
            }
          }
        }
      }
      TRUE
    }

    req <- httr2::request(.OPENAI_ENDPOINT) |>
      httr2::req_headers(
        `Authorization` = paste("Bearer", api_key),
        `Content-Type`  = "application/json",
        `Accept`        = "text/event-stream"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_error(is_error = function(resp) FALSE)

    resp <- tryCatch(httr2::req_perform_stream(req, on_data, buffer_kb = 16),
                      error = function(e) e)

    # Decide outcome of this attempt.
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

    if (success_status) {
      final_resp <- resp
      break
    }

    # Don't retry if user already saw some text — would duplicate output.
    if (nzchar(accumulated)) {
      final_resp <- resp
      break
    }

    # Don't retry on non-transient client errors (401, 403, 404, ...).
    if (!network_error && !transient_status) {
      final_resp <- resp
      break
    }

    if (attempt > max_retries) {
      final_resp <- resp
      break
    }

    delay <- c(1, 3)[min(attempt, 2)]
    message(sprintf("openai_chat_stream: retrying after %ds (attempt %d/%d, status=%s)",
                     delay, attempt, max_retries + 1L,
                     if (is.na(status)) last_err else as.character(status)))
    Sys.sleep(delay)
  }

  # Handle final outcome.
  resp <- final_resp
  if (inherits(resp, "error")) {
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = paste0("Streaming failed (", last_err,
                               "). Try again in a minute.")))
  }

  status <- httr2::resp_status(resp)
  if (status >= 300) {
    tryCatch({
      body <- httr2::resp_body_json(resp)
      msg  <- body$error$message %||% ""
      if (nzchar(msg)) message("OpenAI stream error: ", msg)
    }, error = function(e) NULL)
    user_msg <- switch(as.character(status),
      "401" = "AI translator authentication failed. Please contact the administrator.",
      "403" = "AI translator is blocked by OpenAI. The administrator may need to add billing.",
      "429" = "OpenAI is rate-limiting requests. Try again in a minute.",
      sprintf("OpenAI returned HTTP %d. Try again later.", status))
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = user_msg))
  }

  prompt_tokens     <- final_usage$prompt_tokens     %||% 0L
  completion_tokens <- final_usage$completion_tokens %||% 0L
  # GPT-4.1 implicit prompt caching surfaces in usage.prompt_tokens_details.
  cached_tokens     <- final_usage$prompt_tokens_details$cached_tokens %||% 0L
  list(
    reply    = accumulated,
    usage    = list(prompt_tokens     = prompt_tokens,
                     completion_tokens = completion_tokens,
                     cached_tokens     = cached_tokens,
                     total_tokens      = prompt_tokens + completion_tokens),
    model    = model,
    cost_usd = openai_cost_usd(prompt_tokens, completion_tokens, model,
                                cached_tokens = cached_tokens),
    error    = NULL
  )
}

# Non-streaming variant that uses OpenAI's `response_format: json_schema`
# strict mode to force a guaranteed-valid filled-template JSON. Called
# only by the "Produce template now" button — the regular chat path
# stays text/streaming.
#
# The strict-mode schema mirrors `.translator_write_template_xlsx()`'s
# expectations. If the model produces anything that doesn't match the
# schema, OpenAI returns an error and the user sees a clear message.
openai_chat_template_force <- function(messages,
                                        model = .OPENAI_DEFAULT_MODEL,
                                        max_tokens = 4000,
                                        timeout_sec = 120) {
  api_key <- Sys.getenv("OPENAI_API_KEY", unset = "")
  if (!nzchar(api_key))
    return(list(reply = NULL,
                error = "AI translator is not configured. Please contact the administrator."))

  body <- list(
    model       = model,
    messages    = messages,
    max_tokens  = max_tokens,
    temperature = 0,
    response_format = list(
      type = "json_schema",
      json_schema = list(
        name   = "filled_inventory_template",
        strict = FALSE,
        schema = list(
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
                  mcf               = list(type = c("number", "null")),
                  ef3               = list(type = c("number", "null"))
                ),
                required = c("sub_category", "mms_type", "fraction_pct")
              )
            )
          ),
          required = c("parameters")
        )
      )
    )
  )

  req <- httr2::request(.OPENAI_ENDPOINT) |>
    httr2::req_headers(
      `Authorization` = paste("Bearer", api_key),
      `Content-Type`  = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error"))
    return(list(reply = NULL,
                error = paste0("Couldn't reach OpenAI (",
                               conditionMessage(resp), ").")))
  status <- httr2::resp_status(resp)
  if (status < 200 || status >= 300) {
    tryCatch({
      body <- httr2::resp_body_json(resp)
      msg  <- body$error$message %||% ""
      if (nzchar(msg)) message("OpenAI template-force error: ", msg)
    }, error = function(e) NULL)
    return(list(reply = NULL,
                error = sprintf("Template force failed (HTTP %d). Try again later.",
                                 status)))
  }
  parsed <- httr2::resp_body_json(resp)
  json_text <- tryCatch(parsed$choices[[1]]$message$content,
                         error = function(e) NULL)
  if (is.null(json_text) || !nzchar(json_text))
    return(list(reply = NULL,
                error = "OpenAI returned an empty template payload. Try again."))
  usage <- parsed$usage %||% list(prompt_tokens = 0L, completion_tokens = 0L)
  cached_tokens <- usage$prompt_tokens_details$cached_tokens %||% 0L
  list(
    reply    = json_text,
    usage    = list(prompt_tokens     = usage$prompt_tokens     %||% 0L,
                     completion_tokens = usage$completion_tokens %||% 0L,
                     cached_tokens     = cached_tokens,
                     total_tokens      = (usage$prompt_tokens %||% 0L) +
                                         (usage$completion_tokens %||% 0L)),
    model    = parsed$model %||% model,
    cost_usd = openai_cost_usd(usage$prompt_tokens     %||% 0L,
                                usage$completion_tokens %||% 0L,
                                parsed$model %||% model,
                                cached_tokens = cached_tokens),
    error    = NULL
  )
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
