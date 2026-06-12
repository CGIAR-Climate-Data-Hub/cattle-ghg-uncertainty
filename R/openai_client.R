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
# Reuses the same .md files already in translator_prompts/ that the
# user-facing translator kit ships, so the in-app translator and the
# downloadable kit share a single source of truth.
#
# Returns a single character string ready to be sent as the first message
# in the conversation (role = "system"). At repo root the assembled
# prompt is roughly 12-15K tokens.
assemble_translator_system_prompt <- function(asset_dir = "translator_prompts") {
  files <- c("system_instructions.md", "param_catalogue.md",
             "template_schema.md", "mapping_examples.md",
             "worked_example.md", "questionnaire.md")
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
    "  ],",
    "  \"parameter_timeseries\": [",
    "    {",
    "      \"cattle_type\": \"dairy\",",
    "      \"aggregation_level\": \"all\",",
    "      \"sub_category\": \"dairy_cows\",",
    "      \"year\": 2018,",
    "      \"N\": 240000,",
    "      \"BW\": 432,",
    "      \"Milk\": 9.1,",
    "      \"DE\": 64",
    "    }",
    "    /* OPTIONAL — one row per (group, year). Cattle/agg/sub columns",
    "       may be blank to apply to all groups. Only emit when the source",
    "       file has >=5 years of activity data; otherwise omit the array",
    "       or send []. The app uses this to compute the AD correlation",
    "       matrix automatically. NEVER fabricate years that aren't in",
    "       the source. */",
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
    "* `parameter_timeseries` is OPTIONAL. Only emit rows when the user's",
    "  source file has multi-year activity data. Emit an empty array",
    "  (or omit the field) for single-year inventories. Allowed numeric",
    "  columns: N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, CP, MilkPR.",
    "  `year` is the only required column.",
    "",
    "### CRITICAL — JSON strictness rules",
    "",
    "The block must be valid RFC-8259 JSON parseable by jsonlite::fromJSON.",
    "Common failure modes that produce an UNUSABLE template (no download",
    "button appears for the user) — DO NOT do any of these:",
    "",
    "* NO comments anywhere. Not `// like this`, not `/* like this */`.",
    "  JSON has no comments. The schema example above is the ONLY place",
    "  any `/* */` text appears; do not copy that style into your output.",
    "* NO expressions or formulas. Write `4.644`, NEVER `4.5*1.032`. Do",
    "  every arithmetic step yourself and emit the resulting literal.",
    "* NO placeholder text like `\"...\"`, `\"see above\"`, `\"repeat for",
    "  each sub-category\"`, `\"for brevity not shown\"`. Emit every row",
    "  in full. If the inventory has 8 sub-categories and you intend to",
    "  fill all 25 parameters of the catalogue, the `parameters` array",
    "  must contain 8 × 25 = 200 rows. List them all. The user gets no",
    "  download otherwise.",
    "* NO trailing commas after the last item of an array or object.",
    "* NO single quotes around keys or string values — JSON requires",
    "  double quotes only.",
    "* NO unquoted keys.",
    "* When in doubt about the JSON size, prefer truncating the inventory",
    "  by HALF (e.g. only dairy sub-categories, ask user to start a new",
    "  conversation for the beef ones) over emitting a partial / commented",
    "  block. Both halves emitted correctly is infinitely better than one",
    "  whole emitted as a comment-stub.",
    "",
    "Do NOT emit the `template-ready` block, EVER, in any chat reply.",
    "While you are still gathering information, respond in plain text.",
    "When you have enough information, end with one short sentence",
    "directing the user to click the green Produce template now button",
    "below the chat (see in-app presentation rule 9 — that's the ONLY",
    "way emission starts; typed phrases like 'go ahead' are no longer",
    "a trigger). Inlining JSON in chat is forbidden: multi-sub-category",
    "templates hit the streaming token cap and the parser rejects the",
    "truncated block, leaving the user with no download.",
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
    "8. **NEVER stall.** Forbidden phrases include 'Please wait while I",
    "   generate the output', 'I will now prepare the filled template',",
    "   'Generating now…', 'One moment…', 'Working on it…', or any",
    "   variant that implies you're about to do something IN A FOLLOW-UP",
    "   REPLY. This is a single-shot streaming chat: you have ONE",
    "   response to do the work and then stop talking.",
    "",
    "9. **NEVER emit the template yourself, EVER. The button is the only",
    "   way to start emission (updated 2026-06-12).** A complete filled",
    "   inventory is 200-1000+ JSON rows; it does not fit in the",
    "   streaming chat's token budget and gets truncated mid-array. The",
    "   in-app server runs the emission as a separate, batched,",
    "   tool_use-strict process that is ONLY triggered when the user",
    "   clicks the green Produce template now button below the chat.",
    "",
    "   Typed phrases like 'go ahead' / 'produce the template' /",
    "   'generate' / 'yes do it' are NO LONGER a trigger and never were",
    "   meant to be a deferral substitute. Treat them as a request to",
    "   confirm readiness, not a request to start emission. The correct",
    "   reply to any such phrase is one short sentence directing the",
    "   user to the button, e.g.: 'Great — everything's confirmed. To",
    "   start emission, click the green Produce template now button",
    "   below the chat. The server runs ~5 minutes of batched calls",
    "   and shows the Download button when done.'",
    "",
    "   When you finish a clarification round and have enough",
    "   information, ALWAYS end the reply with this same one-line",
    "   instruction — never inline JSON, never start emission yourself,",
    "   never promise to 'generate the template now'. The ONE exception",
    "   has been removed: even for tiny single-sub-category inventories,",
    "   the user clicks the button.",
    "",
    "10. **Explore reply must be SHORT — Section D only, with a 3-5",
    "    line orientation, and NO Section A / B / C table dumps.**",
    "    (Added 2026-06-12 after Lolita's $7.73 Zambia run logged",
    "    16,000 output tokens of repeated structured tables on the",
    "    Explore reply alone — the user uploaded the file, they know",
    "    what's in it, they don't need it recited back.)",
    "",
    "    For the FIRST reply after a file upload (the EXPLORE step in",
    "    the system prompt's workflow), emit ONLY:",
    "      - one short orientation line: \"I read your file: N sheets,",
    "        M production systems with K sub-categories total, parameters",
    "        found: <param list>. Inventory year inferred as YYYY.\"",
    "      - any gaps in one line: \"Missing from file (will use IPCC",
    "        defaults): <param list>.\"",
    "      - the Section D numbered ambiguity questions, in full.",
    "      - the one-line direction to the button if you have everything",
    "        already; otherwise end after the questions and wait.",
    "",
    "    DO NOT emit Section A (file shape) — the orientation line",
    "    covers it. DO NOT emit Section B (the per-row inventory of",
    "    values) — you have it internally for emission via the batched",
    "    tool_use path; the user does not need it printed in chat. DO",
    "    NOT emit Section C (gaps detail) beyond the one-line summary.",
    "",
    "    If the user explicitly asks 'show me what you found' or 'list",
    "    the BWs you have', then and only then emit the relevant slice",
    "    of B — but as a 5-15-row excerpt, not the full dump.",
    "",
    "Concrete first-response templates, for reference:",
    "",
    "  SHORT EXPLORE REPLY (preferred — typical):",
    "    I read your file: 6 sheets, 5 production systems, 26",
    "    sub-categories, parameters found: N, BW, MW, WG, pct_pregnant,",
    "    hours, Milk, Fat, DE, CP, Cfi, Ca, C, Ym, Bo, EF3_PRP, EF4,",
    "    EF5, Frac_GASM_PRP, Frac_LEACH_PRP. Inventory year inferred",
    "    as 2022 (2023-2024 look like projections).",
    "    Missing from file (will use IPCC defaults): Tw, MilkPR, Cp,",
    "    ASH, UE.",
    "",
    "    Before I can produce the template, please answer:",
    "",
    "    1. Year: confirm 2022 as the point-estimate year?",
    "    2. Calves are pooled in the file — split 50/50 to calves_male",
    "       and calves_female with identical parameters?",
    "    3. MoE column (e.g. 0.35) — read as a fraction (=±35%)?",
    "    4. Milk units: kg/head/day (the MoE header 'kg/head/year' is",
    "       a typo)?",
    "    5. Emergent beef DE: mean 55.5987 falls below the MoE lower",
    "       bound 56 — widen the bound to 55 to encompass the mean?",
    "",
    "  CLARIFICATION REPLY (after user answers some of the questions):",
    "    Confirmed. One more: <next ambiguity>?",
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
                         max_tokens = 16000,
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
                                max_tokens = 16000,
                                temperature = 0.2,
                                timeout_sec = 180,
                                max_retries = 2,
                                response_format = NULL) {
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
  # Optional response_format (e.g. json_schema strict mode). Streaming
  # supports it — chunks arrive with delta.content fragments of the
  # JSON, accumulated they form the complete validated payload. Lets
  # the force-template path share this streaming machinery and avoid
  # the 180s timeout that hit the old non-streaming call.
  if (!is.null(response_format)) body$response_format <- response_format

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
      # Stall detector: if the stream sends < 1 byte/sec for 45 seconds,
      # treat the call as dead and abort. This is the right knob for a
      # streaming API — wall-clock timeouts kill calls that are still
      # legitimately progressing (e.g. a 6MB response that legitimately
      # takes 4 minutes to fully stream). curl options are exposed via
      # req_options() and map directly to CURLOPT_LOW_SPEED_*.
      httr2::req_options(low_speed_time = 45L, low_speed_limit = 1L) |>
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
                                        on_chunk = function(text) {},
                                        model = .OPENAI_DEFAULT_MODEL,
                                        max_tokens = 32000,  # GPT-4.1 max output is 32768
                                        timeout_sec = 600) {  # 10-min wall-clock — actual progress check is the stall detector in openai_chat_stream
  # Build the json_schema response_format, then delegate to
  # openai_chat_stream so we get streaming (no 180s timeout) + the
  # built-in retry logic for free. The on_chunk callback lets the
  # caller observe progress as JSON streams in — useful for updating
  # the progress bubble on the client.
  schema_body <- list(
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
                  # Optional bounds on the allocation fraction. The
                  # simulator samples these when present; an absent or
                  # equal-to-central value degenerates to deterministic.
                  lower_fraction    = list(type = c("number", "null")),
                  upper_fraction    = list(type = c("number", "null")),
                  distribution_fraction = list(type = c("string", "null")),
                  MCF_pct           = list(type = c("number", "null")),
                  # Optional bounds on the IPCC coefficients — populate
                  # from user-supplied data when available, otherwise
                  # leave null and the catalogue defaults are used.
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
            )
          ),
          required = I(c("parameters"))  # I() preserves single-element vector as a JSON array; without it jsonlite auto-unboxes to "required":"parameters" which OpenAI rejects ("parameters is not of type 'array'")
        )  # closes schema
      )    # closes json_schema
    )      # closes schema_body
  # (one trailing close bracket removed — was a leftover from the old non-streaming wrapper)

  openai_chat_stream(
    messages        = messages,
    on_chunk        = on_chunk,
    model           = model,
    max_tokens      = max_tokens,
    temperature     = 0,
    timeout_sec     = timeout_sec,
    response_format = schema_body
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
