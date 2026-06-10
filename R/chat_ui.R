# In-app AI translator chat — UI + server logic.
#
# Renders inside the Resources tab. Two visible states:
#   (a) Logged out  -> magic-link login panel.
#   (b) Logged in   -> chat panel (file upload + message history + input box).
#
# Wires up the Anthropic client (R/anthropic_client.R), the spend ledger
# (R/usage_log.R), and the magic-link auth (R/auth_magic_link.R).

# ============================================================================
# UI
# ============================================================================

translator_chat_ui <- function() {
  is_fr <- identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                           ifnotfound = "en"), "fr")
  bslib::card(
    id = "ai-translator-card",
    style = "border-left: 4px solid #2D6A4F;",
    bslib::card_header(
      h4(t("ai_card_title"), style = "margin: 0;")
    ),
    bslib::card_body(
      tags$p(style = "margin: 0 0 14px 0; color: #475569; font-size: 0.92rem;
                       line-height: 1.5;",
        t("ai_intro_part1"), " ",
        tags$strong(t("ai_step1_label")), " ", t("ai_step1_body"), " ",
        tags$strong(t("ai_step2_label")), " ", t("ai_step2_body"), " ",
        tags$strong(t("ai_step3_label")), " ", t("ai_step3_body"), " ",
        t("ai_intro_signin_note"), " ",
        tags$a(href = "docs/ai_translator.html", target = "_blank",
               style = "color: #2D6A4F; font-weight: 600;
                        text-decoration: underline;",
               t("ai_find_out_more"))),
      if (is_fr)
        tags$div(style = "margin: 0 0 14px 0; padding: 8px 12px;
                          background: #FEF3C7; border-left: 3px solid #F59E0B;
                          border-radius: 4px; font-size: 0.85rem; color: #5D4037;",
                 icon("circle-info"), " ", t("ai_fr_chat_note"))
      else NULL,
      uiOutput("translator_panel")
    )
  )
}

# ============================================================================
# SERVER — install with translator_chat_server(input, output, session, rv)
#         from inside app_server().
# ============================================================================

# Reactive state private to the translator. Owned by the module, not by
# the rest of the app, so we set it up here instead of in app_server's
# main rv list.
.translator_init_state <- function() {
  shiny::reactiveValues(
    user_email = NULL,        # NULL until logged in
    messages   = list(),      # list of list(role, content) excluding system
    pending    = FALSE,       # TRUE while an API call is in flight
    last_template_json = NULL,  # most recent `template-ready` payload
    last_error = NULL,
    login_status = NULL       # one-line message under the login form
  )
}

translator_chat_server <- function(input, output, session) {
  state <- .translator_init_state()

  # ---- Session-restore from cookie (runs once on Shiny session start) ------
  # If the browser already has a valid translator_session cookie, the user
  # is signed back in immediately — no magic link required. The Cookie:
  # header is on session$request$HTTP_COOKIE; we parse + HMAC-verify it
  # in pure R (no JS round-trip needed for restore).
  observeEvent(session$clientData$url_protocol, {
    if (!is.null(state$user_email)) return()  # already signed in this session
    cookie_value <- auth_cookie_lookup(
      cookie_header = session$request$HTTP_COOKIE,
      name          = "translator_session")
    if (is.null(cookie_value)) return()
    restored <- auth_session_cookie_verify(cookie_value)
    if (!is.null(restored) && auth_is_approved(restored)) {
      state$user_email <- restored
      # 2026-06: also restore the saved conversation history so the user
      # picks up where they left off.
      hist <- tryCatch(conversation_load(restored), error = function(e) list())
      if (length(hist) > 0) state$messages <- hist
    }
  }, once = TRUE, ignoreInit = FALSE)

  # ---- One-shot URL-token consumption on app start --------------------------
  observeEvent(session$clientData$url_search, {
    qs <- shiny::parseQueryString(session$clientData$url_search %||% "")
    tok <- qs$token
    if (is.null(tok) || !nzchar(tok)) return()
    email <- auth_token_consume(tok)
    if (is.null(email)) {
      state$login_status <- "Sign-in link was invalid or has expired (links are valid for 15 minutes). Please request a new one."
    } else if (auth_is_approved(email)) {
      state$user_email <- email
      state$login_status <- NULL
      # Drop a long-lived (~100-year) signed cookie so the next refresh
      # keeps the user signed in without another magic-link round-trip.
      # Functionally permanent; user can sign out via Clear site data.
      tryCatch({
        sess_cookie <- auth_session_cookie_issue(email)
        session$sendCustomMessage("setTranslatorSession", sess_cookie)
      }, error = function(e) {
        message("auth: couldn't issue session cookie: ", conditionMessage(e))
      })
    } else {
      state$user_email <- NULL
      state$login_status <- paste0(
        "Thanks — your request to access the AI translator (",
        email,
        ") has been forwarded to the administrator for approval. You'll receive an email once approved.")
      auth_notify_admin_of_request(email)
    }
    # Clean the token out of the URL so it doesn't sit in browser history.
    session$sendCustomMessage("scrubUrl", "?")
  }, once = TRUE, ignoreInit = FALSE)

  # ---- Login form: "send me a magic link" ----------------------------------
  observeEvent(input$translator_submit, {
    email <- tolower(trimws(input$translator_email %||% ""))
    # perl = TRUE is required so `\s` inside the character class is parsed
    # as the whitespace shortcut. R's default TRE engine treats `\s` in
    # `[^@\s]` as the literal characters `\` and `s`, which rejected every
    # email containing the letter "s" — CGIAR addresses (.../@cgiar.org)
    # happen to have no 's' before the @, so the bug only surfaced on
    # external addresses.
    if (!grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email, perl = TRUE)) {
      state$login_status <- "Please enter a valid email address."
      return()
    }
    tok <- auth_token_issue(email)
    ok  <- auth_send_magic_link(email, tok)
    if (ok) {
      state$login_status <- paste0(
        "Sent! Check ", email, " for a sign-in link (valid 15 minutes). ",
        "If you don't see it, check spam.")
    } else {
      state$login_status <- paste0(
        "We couldn't send the sign-in email (the email service is not yet ",
        "configured on the server). Please contact the administrator.")
    }
  })

  # ---- Login-state UI router ------------------------------------------------
  output$translator_panel <- renderUI({
    if (is.null(state$user_email)) {
      tagList(
        auth_login_panel(id_prefix = "translator"),
        if (!is.null(state$login_status))
          tags$div(style = "max-width:480px; margin:8px auto; padding:10px 14px;
                            background:#FEF3C7; border-radius:6px; font-size:0.85rem;",
                   state$login_status)
        else NULL
      )
    } else {
      .translator_chat_panel(state)
    }
  })

  # Reactive: re-render login status when it changes.
  output$translator_status <- renderUI({
    if (!is.null(state$login_status))
      tags$div(style = "margin-top:10px; padding:8px 12px; font-size:0.85rem;
                        background:#FEF3C7; border-radius:6px;",
               state$login_status)
  })

  # ---- File upload: convert to a markdown table + queue as user msg --------
  observeEvent(input$translator_file, {
    req(state$user_email)
    fi <- input$translator_file
    if (is.null(fi)) return()
    # Inline typing-indicator in the conversation while we read the
    # uploaded file + wait for the AI's first reply. Visible alongside
    # the conversation regardless of scroll position; cleared by
    # translatorStreamStart when the AI starts streaming.
    session$sendCustomMessage("translatorAppendTypingBubble", "")
    parsed <- tryCatch(
      .translator_read_upload(fi$datapath, fi$name),
      error = function(e) {
        state$last_error <- paste0("Couldn't read the uploaded file: ",
                                    conditionMessage(e))
        NULL
      }
    )
    if (is.null(parsed)) {
      # Parse failed — hide the spinner we just showed, otherwise it
      # spins forever with no AI reply coming.
      tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
               error = function(e) NULL)
      return()
    }
    # Build a single user-message that includes a preview of EVERY
    # non-empty sheet. For multi-sheet files this is the only way the
    # AI gets to see all the data on the first round.
    sheet_blocks <- lapply(parsed$sheets, function(s) {
      sheet_label <- if (is.na(s$name) || !nzchar(s$name %||% ""))
        "(file contents)" else sprintf("Sheet \"%s\"", s$name)
      sprintf("### %s (%d rows × %d columns, first %d shown)\n\n%s",
              sheet_label, s$n_rows, s$n_cols, nrow(s$preview),
              .translator_table_to_md(s$preview))
    })
    # Server-side scan: explicitly tell the AI which canonical parameters
    # appear ANYWHERE in the file. Defense against the previous failure
    # mode where the AI mapped only the first parameter block (LW / WG /
    # MW / % preg / Milk) and skipped DE / CP / Fat / Hours / MMS%
    # because they sat further down the same sheet.
    detected <- .translator_scan_param_labels(parsed$sheets)
    detect_block <- if (length(detected) == 0) "" else paste0(
      "## Parameter labels DETECTED IN THIS FILE (server-side scan)\n\n",
      "These IPCC parameters appear somewhere in the file — search the ",
      "preview tables below for them and map EVERY one. If you cannot ",
      "find the row a label refers to, ask before defaulting to IPCC ",
      "values:\n\n",
      paste0("- ", detected, collapse = "\n"),
      "\n\nDo NOT substitute IPCC defaults for any parameter on this ",
      "list — the user's file has a value for it.\n\n---\n\n")
    # STEP 1 OF 3 — EXPLORATION contract. The AI's first response after
    # upload MUST be a structured exploration of what's in the file
    # (sections A-D below), not a mapping proposal and not a JSON
    # template. This persistent artifact is what the force-template
    # path re-injects at emission time — preventing the "AI drops file
    # values and emits catalogue defaults" failure mode.
    exploration_block <- paste0(
      "## STEP 1 OF 3 — EXPLORATION (your task this turn)\n\n",
      "Your ONLY job in this turn is to produce a structured exploration ",
      "report describing what's in this file. **Do NOT propose final ",
      "mappings yet. Do NOT produce a JSON template.** The user will ",
      "answer your section D questions in Step 2 (Clarification), and ",
      "only then click Produce template now for Step 3 (Emission). ",
      "Producing a template now would be wrong — you don't have the ",
      "clarifications yet.\n\n",
      "Output the following FOUR sections, in order, with verbatim ",
      "section headers `### A.`, `### B.`, `### C.`, `### D.`:\n\n",
      "### A. File shape\n\n",
      "For each sheet, classify the layout pattern (pick one):\n",
      "- `column-oriented` — one row per sub-category, one column per parameter (e.g. row 1 = Cows; cols = N, BW, MW, …)\n",
      "- `wide-stacked` — one row per parameter, columns repeat across sub-categories and mean/lower/upper triples (e.g. row = LW; cols = Cows mean, Cows Lower CI, Cows Upper CI, Bulls mean, …)\n",
      "- `parameter-labeled` — a `parameter` column + `sub-category` column + mean/lower/upper triple\n",
      "- `reference-table` — vocab / dropdown lists / catalogues, NOT data to extract\n",
      "- `calc-sheet` — derived / computed (e.g. NRC calculations behind an aggregated value)\n\n",
      "### B. Inventory of values found\n\n",
      "For EVERY (parameter, sub-category) pair you can identify, list:\n",
      "`parameter | sub-category (raw label as in file) | sheet | row | col | mean | lower (if present) | upper (if present) | units | qualifier (e.g. 'Local breed only', or blank)`.\n\n",
      "Use a markdown table. Cover every parameter from the server-side ",
      "scan above. If you cannot find a row a label points to, say so ",
      "in section D rather than skipping silently.\n\n",
      "### C. Inventory of GAPS\n\n",
      "List every IPCC catalogue parameter that is NOT in the file. These will need IPCC defaults at emission time. Be exhaustive — N / BW / MW / WG / Milk / Fat / pct_pregnant / DE / Cfi / Ca / C / Cp / hours / CP / Ym / Bo / ASH / UE / EF3_PRP / EF4 / EF5 / Frac_GASM_PRP / Frac_LEACH_PRP / MilkPR / Tw, minus what's in section B.\n\n",
      "### D. Ambiguities to ask the user\n\n",
      "Enumerate every ambiguity you'd like the user to resolve before ",
      "emission. Don't propose answers — just list the questions. ",
      "Common ambiguities to look for:\n",
      "- Sub-category vocabulary mapping (raw label → template controlled vocab, e.g. \"Cows\" → `other_cows` or `dairy_cows`?)\n",
      "- Unit conversions (kg vs lb, % vs fraction, L vs kg of milk, °C vs °F)\n",
      "- Biological zeros (does the file's Milk row apply only to lactating cows?)\n",
      "- MMS code meanings (PIT → liquid_slurry or solid_storage?)\n",
      "- Breed disaggregation (Local vs Cross — treat together or split?)\n",
      "- Sheet purpose (is Sheet2 a separate dataset or a calc behind Sheet1?)\n",
      "- Per-sub-cat vs herd-wide allocations (MMS rows apply to everyone or per group?)\n\n",
      "End with a one-line prompt to the user: \"Please answer the section D questions, then click **Produce template now** when ready.\"\n\n",
      "---\n\n")
    user_msg <- sprintf(
      "I have uploaded a file (%s) with %d sheet%s. The contents are below.\n\n%s%s%s",
      fi$name,
      parsed$n_total_sheets,
      if (parsed$n_total_sheets == 1L) "" else "s",
      exploration_block,
      detect_block,
      paste(sheet_blocks, collapse = "\n\n---\n\n"))
    # The on-screen "display" stays terse — the user doesn't want a wall
    # of markdown tables in their own bubble; only the AI needs that.
    # We also tell the user what's coming next so the AI's exploration
    # output isn't a surprise.
    display_summary <- if (parsed$n_total_sheets == 1L)
      sprintf("Uploaded %s (%d rows × %d columns shown). Step 1 of 3 — the AI will now explore your file and report what it found.",
              fi$name, nrow(parsed$sheets[[1]]$preview),
              ncol(parsed$sheets[[1]]$preview))
    else
      sprintf("Uploaded %s (%d sheets: %s). Step 1 of 3 — the AI will now explore your file and report what it found.",
              fi$name, parsed$n_total_sheets,
              paste(sapply(parsed$sheets, `[[`, "name"),
                    collapse = ", "))
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user",
            content = user_msg,
            display = display_summary)
    tryCatch(conversation_save(state$user_email, state$messages),
              error = function(e) NULL)
    .translator_send(state, session)
  })

  # ---- Send button: user types something, click Send -----------------------
  # If the user's message looks like a trigger ('produce the template',
  # 'generate it', 'go ahead', etc.), AND the AI has been gathering
  # info for at least one round, we shortcut to the json_schema force-
  # template path — no separate button needed. Otherwise it's a normal
  # chat round (clarifying questions, mapping discussion).
  observeEvent(input$translator_send, {
    req(state$user_email)
    txt <- trimws(input$translator_input %||% "")
    if (!nzchar(txt)) return()
    updateTextAreaInput(session, "translator_input", value = "")
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user", content = txt, display = txt)
    # Persist BEFORE the AI call. If the user clicks Stop/reload
    # mid-call, this ensures their typed message survives the reload.
    tryCatch(conversation_save(state$user_email, state$messages),
              error = function(e) NULL)
    if (.translator_is_generate_trigger(txt) && length(state$messages) >= 2) {
      # Paint an inline 'working…' bubble with a fake-determinate
      # progress bar for the non-streaming force-template call (30-
      # 120s). Cleared by translatorStreamEnd when work completes.
      session$sendCustomMessage("translatorAppendInfoBubble",
        "Generating the full template now — please wait, this can take 30 to 120 seconds for an inventory with many sub-categories. The Download button will appear right after.")
      .translator_force_template(state, session)
    } else {
      # Three-dot typing indicator inline in the conversation while we
      # wait for the AI's first chunk. Cleared by translatorStreamStart
      # which wipes stream_target before painting the live AI bubble.
      session$sendCustomMessage("translatorAppendTypingBubble", "")
      .translator_send(state, session)
    }
  })

  # ---- Reset conversation: wipe history + saved file -----------------------
  observeEvent(input$translator_reset, {
    req(state$user_email)
    state$messages           <- list()
    state$last_template_json <- NULL
    state$last_error         <- NULL
    conversation_delete(state$user_email)
    # If the user clicked Reset while a request was mid-flight (or the
    # spinner got stuck for any other reason), drop it. translatorStreamEnd
    # also wipes the active streaming bubble reference — safe to call when
    # there's no active stream.
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
             error = function(e) NULL)
    showNotification("Conversation reset.", type = "message", duration = 3)
  })

  # ---- Produce template now: explicit emission trigger ---------------------
  # The chat-trigger detection (.translator_is_generate_trigger) still works
  # for users who type natural language, but this button gives explicit
  # control — recommended path now that the workflow is 3-pass
  # (Explore → Clarify → Emit). Calls the same .translator_force_template
  # function as the trigger detection.
  observeEvent(input$translator_force_template, {
    req(state$user_email)
    if (length(state$messages) < 2L) {
      showNotification(
        "Upload a file and answer the AI's clarifying questions before producing the template.",
        type = "warning", duration = 5)
      return()
    }
    session$sendCustomMessage("translatorAppendInfoBubble",
      "Generating the full template now — please wait, this can take 30 to 120 seconds for an inventory with many sub-categories. The Download button will appear right after.")
    .translator_force_template(state, session)
  })

  # ---- Render the message history ------------------------------------------
  # IMPORTANT: this output renders ONLY the completed-message bubbles.
  # The streaming bubble lives in #translator_stream_target which is a
  # STATIC sibling in .translator_chat_panel (NOT inside this renderUI).
  # That separation is critical: when state$messages changes (e.g. on
  # upload, the user msg gets appended), this output re-renders. If the
  # stream_target lived in here, the re-render would replace its DOM
  # while chunks were streaming into it — the bubble would be detached
  # mid-stream and the user would see 10 seconds of silence until the
  # final state$messages update brought everything back at once. By
  # keeping stream_target outside, the live bubble persists across
  # renders and the user sees the AI typing in real time.
  output$translator_messages <- renderUI({
    if (length(state$messages) == 0 && !isTRUE(state$pending))
      return(tags$p(style = "color:#888; font-style:italic;",
                    t("ai_empty_messages")))
    msgs <- lapply(state$messages, function(m) {
      # User vs AI bubble distinction — standard chat convention:
      #   user  : light blue, right-aligned
      #   AI    : light green (CGIAR brand), left-aligned
      bubble_style <- if (m$role == "user")
        "background:#DCEFFB; color:#1A3A5C; align-self:flex-end;
         border:1px solid #BFDCEE;"
      else
        "background:#E8F5E9; color:#1B4332; align-self:flex-start;
         border:1px solid #C8E6C9;"
      # For assistant messages, split the response into a clean visible
      # part and an optional "structure / thinking" part containing any
      # template-ready JSON or pure-JSON force-template output. The
      # visible part is what the user actually wants to read; the
      # technical detail goes behind a collapsible <details> element.
      visible <- m$display %||% m$content
      hidden  <- NULL
      if (identical(m$role, "assistant")) {
        split <- .translator_split_visible_hidden(m$content, m$display)
        visible <- split$visible
        hidden  <- split$hidden
      }
      tags$div(
        style = paste("max-width:80%; margin:6px 0; padding:10px 14px;",
                      "border-radius:12px; white-space:pre-wrap; font-size:0.92rem;",
                      "line-height:1.45;",
                      bubble_style),
        visible,
        if (!is.null(hidden) && nzchar(hidden))
          tags$details(
            style = "margin-top:10px; font-size:0.82rem; color:#2D6A4F;",
            tags$summary(
              style = "cursor:pointer; user-select:none; font-weight:500;",
              "Show structure / details"),
            tags$pre(
              style = "background:#FFFFFF; border:1px solid #C8E6C9;
                       padding:8px 10px; border-radius:6px; margin-top:6px;
                       font-size:0.78rem; max-height:280px; overflow:auto;
                       white-space:pre-wrap; color:#1B4332;",
              hidden)
          )
      )
    })
    tags$div(
      style = "display:flex; flex-direction:column;",
      msgs,
      if (isTRUE(state$pending))
        tags$div(style = "padding:8px; color:#2D6A4F; font-size:0.85rem;",
                 icon("spinner", class = "fa-spin"),
                 " Translator is thinking…")
    )
  })

  # Reactive flag the conditionalPanel watches to decide whether to show
  # the "Download translated template" button. TRUE only when the saved
  # template JSON parses AND has a non-empty parameters array — so the
  # button never appears with a payload that would download as a
  # malformed .json.
  output$translator_template_ready <- reactive({
    .translator_template_is_well_formed(state$last_template_json)
  })
  outputOptions(output, "translator_template_ready", suspendWhenHidden = FALSE)

  # ---- Spend display REMOVED 2026-06 ---------------------------------------
  # The user-facing 'Your usage' line, the admin 'Pilot budget' line, and
  # the admin stats card have all been removed at user request — the local
  # CSV resets on every shinyapps.io container recycle, so the numbers
  # were misleading. Ground-truth spend lives in OpenAI's billing
  # dashboard at https://platform.openai.com/usage. The internal
  # budget_would_exceed() cap-check still runs in .translator_send() —
  # see usage_log.R. It's a best-effort soft cap; the real hard ceiling
  # is set on the OpenAI account.

  output$translator_last_error <- renderUI({
    if (!is.null(state$last_error))
      tags$div(style = "padding:8px 12px; margin-top:8px; background:#FED7D7;
                        border-radius:6px; font-size:0.85rem; color:#C53030;",
               state$last_error)
  })

  # ---- Download translated template ----------------------------------------
  # The download button only appears when state$last_template_json holds a
  # well-formed payload (gated by output$translator_template_ready above,
  # which uses .translator_template_is_well_formed()). So by the time we
  # reach this handler, the JSON parses and we can always produce an .xlsx.
  # The defensive write-raw-text branch is kept as belt-and-suspenders in
  # case the JSON somehow becomes invalid between gate and click (e.g.
  # Reset fired mid-click), but it should never fire in practice.
  output$translator_download_template <- downloadHandler(
    filename = function() {
      paste0("translated_template_",
             format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
    },
    content = function(file) {
      j <- state$last_template_json
      if (.translator_template_is_well_formed(j)) {
        .translator_write_template_xlsx(j, file)
      } else {
        # Should be unreachable — the button gate already validated.
        writeLines("{}", file)
      }
    },
    contentType = NULL
  )

  # Expose the state to the caller in case the rest of app_server wants to
  # know if the translator is "in use" (e.g. don't reload data while
  # logged in).
  invisible(state)
}

# ============================================================================
# Internal helpers
# ============================================================================

# The post-login chat panel.
.translator_chat_panel <- function(state) {
  tagList(
    tags$div(
      style = "display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;",
      tags$div(
        tags$strong(paste0(t("ai_signed_in"), " ")),
        tags$code(state$user_email)
      )
    ),
    tags$hr(style = "margin:10px 0;"),

    fileInput("translator_file",
              label = tagList(
                tags$strong(t("ai_upload_label")),
                tags$span(style = "color:#52525B; font-weight:400;",
                          t("ai_upload_hint"))
              ),
              accept = c(".xlsx", ".xls", ".csv"),
              width = "100%"),

    # 2026-06: pre-stream loading spinner. Hidden by default; shown by JS
    # when the user clicks Send / Force-template / triggers an upload;
    # hidden again as soon as translatorStreamStart fires (or the
    # force-template call returns via translatorStreamEnd).
    tags$div(id = "translator_spinner",
             style = "display:none; align-items:center; gap:10px;
                      padding:10px 14px; margin:8px 0;
                      background:#FFF8E1; border:1px solid #FFE082;
                      border-radius:8px; color:#5D4037; font-size:0.88rem;
                      position:sticky; top:8px; z-index:50;",
             tags$div(style = "width:18px; height:18px;
                                border:3px solid #FFE082;
                                border-top-color:#FF6F00;
                                border-radius:50%;
                                animation: translatorSpin 0.8s linear infinite;"),
             # The text inside is overwritten by JS to give context-aware
             # labels (Analyzing your file… / Producing the final template… /
             # Sending sign-in link… / default working message).
             tags$span(`data-translator-spinner-label` = "true",
                       t("ai_spinner_default"))),
    # Inline keyframes for the spinner's rotation (avoids needing a
    # custom CSS file just for this).
    tags$head(tags$style(HTML(
      "@keyframes translatorSpin {
         from { transform: rotate(0deg); }
         to   { transform: rotate(360deg); }
       }
       @keyframes translatorDot {
         0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
         40%           { opacity: 1.0; transform: scale(1.2); }
       }"
    ))),

    # Static scroller wraps both the reactive message list AND the
    # streaming target. translator_stream_target lives OUTSIDE
    # output$translator_messages so it survives re-renders triggered by
    # state$messages changes — chunks stream into it visibly in real time.
    # See the long comment on output$translator_messages.
    tags$div(
      `data-translator-scroller` = "true",
      style = "display:flex; flex-direction:column; max-height:480px;
               overflow-y:auto; padding:8px;",
      uiOutput("translator_messages",
                style = "display:flex; flex-direction:column;"),
      tags$div(id = "translator_stream_target",
                style = "display:flex; flex-direction:column;")
    ),

    tags$hr(style = "margin:14px 0;"),

    tags$div(
      style = "display:flex; gap:8px; align-items:flex-end;",
      div(style = "flex:1;",
          textAreaInput("translator_input",
                        label = t("ai_reply_label"),
                        placeholder = t("ai_reply_placeholder"),
                        rows = 2, width = "100%")),
      actionButton("translator_send", t("btn_ai_send"), class = "btn-success",
                   style = "min-width:80px; height:42px;")
    ),
    # Secondary action row — Produce | Reset | Stop | Download.
    # The chat-trigger detection ("produce the template", "go ahead",
    # etc.) still works, but the explicit button gives the user clear
    # control over when emission fires and prevents accidental triggers
    # mid-clarification.
    tags$div(
      style = "display:flex; gap:8px; margin-top:6px; flex-wrap:wrap; align-items:center;",
      actionButton("translator_force_template",
                   tagList(icon("file-arrow-down"),
                            t("btn_ai_produce")),
                   class = "btn-primary",
                   style = "font-size:0.82rem;",
                   title = t("tip_ai_produce")),
      actionButton("translator_reset",
                   tagList(icon("rotate-left"),
                            t("btn_ai_reset")),
                   class = "btn-outline-secondary",
                   style = "font-size:0.82rem;",
                   title = t("tip_ai_reset")),
      # Stop button — escape hatch when the AI is generating a template
      # and the Shiny event loop is blocked on the OpenAI call. Plain
      # JS onclick (window.location.reload) bypasses the blocked R
      # session entirely. The OpenAI call continues in the background
      # but its result is discarded; the user gets their UI back
      # immediately. Conversation history is persisted to disk before
      # the call starts, so the user sees their messages on reload.
      tags$button(
        type = "button",
        class = "btn btn-outline-danger",
        style = "font-size:0.82rem;",
        onclick = sprintf("if (confirm('%s')) { window.location.reload(); }",
                          gsub("'", "\\\\'", t("ai_stop_confirm"))),
        title = t("tip_ai_stop"),
        tagList(icon("ban"), t("btn_ai_stop"))
      ),
      conditionalPanel(
        condition = "output.translator_template_ready",
        downloadButton("translator_download_template",
                        t("btn_ai_download"),
                        class = "btn-success",
                        icon = icon("file-arrow-down"),
                        style = "font-size:0.82rem;")
      )
    ),

    uiOutput("translator_last_error"))
}

# Set a flag the conditionalPanel above can react to. Called from
# the OpenAI-response parser.
.translator_set_template_ready <- function(session, ready) {
  session$sendCustomMessage("setOutputBindingValue",
                            list(id = "translator_template_ready",
                                 value = isTRUE(ready)))
}

# Read an uploaded file and return a SUMMARY OF ALL SHEETS so the AI
# can see everything in one shot.
#
# Returns:
#   $kind          "csv" or "xlsx"
#   $sheets        list of list(name, n_rows, n_cols, preview) — one
#                  entry per non-empty sheet (or one entry for csv)
#   $n_total_sheets  count of non-empty sheets found
#
# The 2026-06 stress-test upload (Burkina-style file with 6 sheets)
# surfaced a real problem with the previous "send only the densest
# sheet" heuristic: it picked the compact metadata sheet and dropped
# the actual cattle data on the floor. The AI then had nothing to map.
# Now every non-trivial sheet is summarised and forwarded to the AI.
.translator_read_upload <- function(path, name) {
  ext <- tolower(tools::file_ext(name))
  if (ext == "csv") {
    df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    return(list(
      kind   = "csv",
      sheets = list(list(name = NA_character_,
                         n_rows = nrow(df), n_cols = ncol(df),
                         preview = utils::head(df, 200))),
      n_total_sheets = 1L
    ))
  }
  sheet_names <- readxl::excel_sheets(path)
  out <- list()
  for (s in sheet_names) {
    df <- tryCatch(readxl::read_excel(path, sheet = s, n_max = 300),
                    error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0 || ncol(df) == 0) next
    # Drop sheets that have zero non-NA cells — pure empty placeholders.
    if (sum(!is.na(df)) == 0) next
    out[[length(out) + 1]] <- list(
      name    = s,
      n_rows  = nrow(df),
      n_cols  = ncol(df),
      # 2026-06-08 (Zambia case): bumped from 40 → 200 because a real
      # survey-data file had parameters (DE, CP, Fat, Hours, MMS%)
      # spread across rows 5-45, and the 40-row cap silently dropped
      # everything past the LW/WG/MW/% preg blocks. Sending more rows
      # costs a few hundred extra prompt tokens — negligible vs. the
      # cost of producing a template that's missing key parameters.
      preview = utils::head(df, 200)
    )
  }
  if (length(out) == 0)
    stop("No readable sheet found in ", name)
  list(kind = "xlsx", sheets = out, n_total_sheets = length(out))
}

# Scan every sheet of the uploaded file for known parameter labels and
# return a deduplicated, human-readable list. Appended to the AI's first
# user message so the model has a structured ground-truth checklist
# even if the markdown-preview table truncates further down. Catches
# the failure mode where the AI silently skips DE / CP / Fat / Hours /
# MMS allocation because they sit further down a long sheet.
.translator_scan_param_labels <- function(sheets) {
  patterns <- list(
    "N (population / head count)"     = c("^n$", "^head_?count", "^population", "^cattle_?pop"),
    "BW (body weight, kg)"            = c("^bw$", "^lw$", "^live_?weight", "^live_?wt", "^body_?weight"),
    "MW (mature weight, kg)"          = c("^mw$", "^mature_?weight", "^mature_?wt"),
    "WG (daily weight gain, kg/d)"    = c("^wg$", "^adg$", "^weight_?gain", "^daily_?gain"),
    "Milk (milk yield, kg/d)"         = c("^milk", "^my\\b", "^my\\s*-", "^lait", "^my_?offtake"),
    "Fat (milk fat %)"                = c("^fat$", "^milkfat", "^milk_?fat", "^fat\\s*\\("),
    "pct_pregnant (fraction)"         = c("^%\\s*preg", "^pct_?pregnant", "^pct_?preg", "^%\\s*pregnancy", "^pregnancy_?rate", "^pct_?lactating"),
    "DE (digestible energy %)"        = c("^de$", "^de\\s*pct", "^de\\s*%", "^digestibility", "^digestible_?energy"),
    "CP (crude protein %)"            = c("^cp$", "^cp\\s*pct", "^crude_?protein", "^diet\\s*cp"),
    "Ym (methane conversion %)"       = c("^ym$", "^ym\\s*pct", "^methane_?conv"),
    "Bo (methane potential)"          = c("^bo$"),
    "ASH (fraction)"                  = c("^ash$"),
    "UE (urinary energy fraction)"    = c("^ue$"),
    "hours (work hours / fraction)"   = c("^hours?$", "^work_?hours", "^heures"),
    "MMS allocation (manure mgmt %)"  = c("^mms", "^manure_?management", "^système.*gestion", "^systeme.*gestion", "^manure_?system")
  )
  found <- character(0)
  for (sheet in sheets) {
    df <- sheet$preview
    if (is.null(df) || nrow(df) == 0) next
    # Check up to first 3 columns + the column headers — that's where
    # parameter labels sit in typical wide-format survey spreadsheets.
    candidates <- character(0)
    candidates <- c(candidates, names(df))
    for (col_idx in seq_len(min(3L, ncol(df)))) {
      candidates <- c(candidates, as.character(df[[col_idx]]))
    }
    candidates <- candidates[!is.na(candidates) & nzchar(trimws(candidates))]
    cand_lower <- tolower(trimws(candidates))
    for (pname in names(patterns)) {
      if (pname %in% found) next
      for (pat in patterns[[pname]]) {
        if (any(grepl(pat, cand_lower, perl = TRUE))) {
          found <- c(found, pname); break
        }
      }
    }
  }
  found
}

# Render a small data.frame as a markdown table the LLM can read.
.translator_table_to_md <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("(empty data)")
  hdr <- paste("|", paste(names(df), collapse = " | "), "|")
  sep <- paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|")
  # 2026-06-08: bumped row cap 30 → 200 to match the preview cap. A
  # 30-row table dropped DE / CP / Fat / Hours / MMS rows that sit
  # further down typical survey spreadsheets.
  rows <- vapply(seq_len(min(nrow(df), 200)), function(i) {
    paste("|", paste(sapply(df[i, ], function(x) {
      v <- if (is.na(x)) "" else as.character(x)
      gsub("\\|", "/", v)
    }), collapse = " | "), "|")
  }, character(1))
  paste(c(hdr, sep, rows), collapse = "\n")
}

# Make the API call from the current message stack, stream the reply
# into the browser, then append it to the chat history. All this state
# lives on `state`. Requires `session` so the streaming chunks can be
# pushed to the active browser tab via sendCustomMessage.
.translator_send <- function(state, session) {
  state$pending <- TRUE
  state$last_error <- NULL
  on.exit({
    state$pending <- FALSE
    # Always tell the browser to drop the active streaming bubble — the
    # server-side renderUI will replace it (or leave a blank when there's
    # an error). Safe to call even if the bubble was never created.
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
              error = function(e) NULL)
  })

  # Cap check.
  if (budget_would_exceed()) {
    state$last_error <- paste0(
      "The monthly budget cap for the AI translator has been reached ",
      "($", sprintf("%.2f", monthly_budget_cap_usd()), "). ",
      "Please contact the administrator to raise it or wait until the ",
      "1st of next month.")
    return()
  }

  system_prompt <- tryCatch(
    assemble_translator_system_prompt(),
    error = function(e) {
      state$last_error <- paste0("Couldn't load the translator instructions: ",
                                  conditionMessage(e))
      NULL
    })
  if (is.null(system_prompt)) return()

  msgs <- anthropic_build_messages(system_prompt, history = state$messages)

  # Create an empty bubble client-side, then stream tokens into it. The
  # final assistant message gets written into state$messages at the end so
  # the renderUI for the message history catches up.
  session$sendCustomMessage("translatorStreamStart", "")

  resp <- anthropic_chat_stream(
    msgs,
    on_chunk = function(text) {
      session$sendCustomMessage("translatorStreamChunk", text)
    }
  )

  if (!is.null(resp$error)) {
    state$last_error <- resp$error
    # If we got at least some text before the error, still save it.
    if (!is.null(resp$reply) && nzchar(resp$reply)) {
      state$messages[[length(state$messages) + 1]] <-
        list(role = "assistant", content = resp$reply, display = resp$reply)
    }
    return()
  }

  # Log the spend — Anthropic prompt caching has 90% off on cache reads
  # and a 25% surcharge on cache writes (first turn only).
  # See R/anthropic_client.R::anthropic_cost_usd.
  usage_log_append(
    user_email         = state$user_email,
    model              = resp$model,
    prompt_tokens      = resp$usage$prompt_tokens,
    completion_tokens  = resp$usage$completion_tokens,
    cached_tokens      = resp$usage$cached_tokens %||% 0L,
    cache_write_tokens = resp$usage$cache_write_tokens %||% 0L,
    cost_usd           = resp$cost_usd
  )

  # Extract any `template-ready` fenced block from the reply, and only
  # promote it if it actually parses + has the expected shape. If the AI
  # emitted a block but it's malformed (JS-style comments, JS expressions
  # like `4.5*1.032`, `// for brevity not shown` placeholders, or
  # truncated mid-stream), don't promote — but DO tell the user, otherwise
  # they see the AI's confident "template-ready" reply and no download
  # button with no explanation.
  json_block <- .translator_extract_template_ready(resp$reply)
  template_just_ready <- FALSE
  if (!is.null(json_block)) {
    if (.translator_template_is_well_formed(json_block)) {
      state$last_template_json <- json_block
      template_just_ready <- TRUE
    } else {
      state$last_error <- paste0(
        "The AI tried to emit a template but the format wasn't valid JSON ",
        "(usually because of JS-style comments, math expressions, or ",
        "'for brevity' placeholders inside the block). Click 'Produce ",
        "template now' below — that uses Anthropic's tool-input-schema mode and ",
        "is guaranteed to produce a downloadable .xlsx.")
    }
  }

  # Append assistant message to history. The renderUI for translator_messages
  # will redraw and the streaming bubble (still in the DOM from the JS
  # handler) gets replaced by the freshly-rendered history.
  state$messages[[length(state$messages) + 1]] <-
    list(role = "assistant",
          content = resp$reply,
          display = resp$reply)

  # If a valid template-ready block came through in this reply, post a
  # separate small AI message pointing the user at the green Download
  # button. The previous reply mixed natural-language with the JSON, so
  # the user can miss the "click to download" cue — this dedicated
  # message is the clear next step.
  if (template_just_ready) .translator_append_download_hint(state)

  # Persist so a refresh / reload resumes where we left off.
  tryCatch(conversation_save(state$user_email, state$messages),
           error = function(e) NULL)
}

# Shared helper: append a friendly 'click the green Download button'
# message to the conversation. Called from both .translator_send (chat
# path, when a valid template-ready block lands) and
# .translator_force_template (forced-output path). Centralised so the
# wording stays identical in both places.
.translator_append_download_hint <- function(state) {
  state$messages[[length(state$messages) + 1]] <- list(
    role    = "assistant",
    content = "(download hint)",
    display = paste0(
      "Your translated template is ready — click the green ",
      "'Download template (.xlsx)' button below to get the file.\n\n",
      "Important: before uploading it on the 1. Data Input tab, ",
      "please open the .xlsx and spot-check the AI's work against ",
      "your original data:\n",
      "- populations, body weights, milk yields, and any unit ",
      "conversions are sensible\n",
      "- sub-category labels were mapped correctly\n",
      "- the manure-management percentages match what you intended\n\n",
      "Any IPCC default values the AI applied (when your raw data ",
      "didn't include them) will be flagged in amber on the 2. QA/QC ",
      "tab — review those carefully too. The AI is a draft assistant, ",
      "not a verified source."))
}

# Force the AI to emit the final filled-template JSON now, regardless of
# whether it thinks it has enough info. Uses OpenAI's response_format
# json_schema mode so the output is GUARANTEED to be valid JSON matching
# .translator_write_template_xlsx()'s expected schema. Called only by
# the "Produce template now" button.
.translator_force_template <- function(state, session) {
  state$pending <- TRUE
  state$last_error <- NULL
  on.exit({
    state$pending <- FALSE
    # Hide the JS spinner — force-template is non-streaming so
    # translatorStreamStart never fires; we have to clear the spinner
    # explicitly. translatorStreamEnd is a safe no-op when there's no
    # active bubble.
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
              error = function(e) NULL)
  })

  if (budget_would_exceed()) {
    state$last_error <- paste0(
      "The monthly budget cap for the AI translator has been reached ",
      "($", sprintf("%.2f", monthly_budget_cap_usd()), "). ",
      "Please contact the administrator to raise it or wait until the ",
      "1st of next month.")
    return()
  }

  system_prompt <- tryCatch(assemble_translator_system_prompt(),
                             error = function(e) NULL)
  if (is.null(system_prompt)) {
    state$last_error <- "Couldn't load the translator instructions."
    return()
  }

  # Build the message list and inject the hard-requirements prompt as
  # the FINAL user turn (not stored in state$messages — keeps the chat
  # visible to the user clean, just nudges the API call). Includes the
  # explicit row-count + completeness + strict-JSON checklist that
  # previously lived in the (now-removed) force-template button's
  # observeEvent.
  hard_requirements <- paste(
    "STEP 3 OF 3 — EMISSION. Produce the final filled template JSON now.",
    "",
    "Earlier in this conversation you produced an exploration report",
    "with FOUR sections (A: file shape, B: inventory of values found,",
    "C: gaps, D: ambiguities to ask the user). The user has answered",
    "section D's questions in subsequent messages. NOW produce the JSON",
    "template as a MECHANICAL TRANSLATION of B + C + biological zeros —",
    "not a re-derivation from scratch.",
    "",
    "The translation rule, applied row-by-row:",
    "  (1) Every (parameter, sub-cat) pair in your section B inventory →",
    "      one row with: value = file mean, lower = file lower (if listed),",
    "      upper = file upper (if listed), distribution = pert,",
    "      data_source = 'user_file'. Apply the user's clarifications",
    "      from section D (e.g. unit conversions, sub-cat vocabulary",
    "      mapping, biological-zero overrides).",
    "  (2) Every (parameter, sub-cat) pair in your section C gaps →",
    "      one row with the catalogue default value + distribution,",
    "      data_source = 'ipcc_default'.",
    "  (3) Biological zeros confirmed by the user (Milk=0 in males,",
    "      hours=0 in non-oxen, pct_pregnant=0 in males, etc.) →",
    "      value = 0, distribution = constant,",
    "      data_source = 'biological_zero'.",
    "",
    "Total row count = |B| + |C| + |biological_zeros| per sub-category,",
    "summed across the sub-categories you mapped in section B. Do NOT",
    "skip rows. Do NOT substitute defaults for B-list entries.",
    "",
    "THIS IS NOT A STEP-5b DEFERRAL. The user pressed 'Produce template",
    "now' after explicit exploration + clarification. Their request is",
    "'emit the B/C/zero translation', NOT 'fill everything with catalogue",
    "defaults'. If you emit an all-IPCC-defaults grid, your output is",
    "REJECTED and the user gets a failure message — your work is wasted.",
    "",
    "HARD REQUIREMENTS — your output is rejected if any of these fail:",
    "",
    "1. SOURCE-OF-TRUTH HIERARCHY (most important rule). For every",
    "   parameter x sub-category, your `value` field MUST come from",
    "   exactly one of three places, in this priority order:",
    "     (a) the user's file (if it contains a value for that pair),",
    "     (b) a number the user typed in the chat (overrides the file",
    "         or fills in something the file is missing),",
    "     (c) an IPCC default from param_catalogue.md (ONLY when",
    "         neither the file nor the chat supplies a value).",
    "   The most common failure is: you confirm the user's data in",
    "   chat, then silently emit an IPCC default for the same",
    "   parameter. THIS IS NOT ACCEPTABLE. Before emitting each row,",
    "   ask yourself: did the user provide this value? If yes, am I",
    "   using their number, not a default? If no on the second",
    "   question, fix the row.",
    "",
    "   You MUST set `data_source` on EVERY parameters row to ONE of:",
    "     - \"user_file\"          (value from the uploaded file)",
    "     - \"user_chat\"          (value the user typed in chat)",
    "     - \"ipcc_default\"       (catalogue default — only when neither",
    "                              file nor chat provided a value)",
    "     - \"biological_zero\"    (e.g. Milk=0 for bulls, hours=0 for cows)",
    "     - \"placeholder\"        (e.g. N=1 for sub-categories the user",
    "                              hasn't supplied a population for)",
    "   An output where every row's data_source is \"ipcc_default\" or",
    "   missing/blank is automatically REJECTED.",
    "",
    "2. SUB-CATEGORIES. Emit EXACTLY the sub-categories the user mapped",
    "   in chat — not the canonical 8 from the catalogue. If the user",
    "   corrected 'Cows' to `other_cows` (not `dairy_cows`), then",
    "   `dairy_cows` MUST NOT appear anywhere in `parameters` or",
    "   `manure_management`. The post-processor strips dairy_cows from",
    "   any cattle_non_dairy inventory; the post-processor strips",
    "   non-dairy sub-cats from any cattle_dairy inventory. Match the",
    "   species you set in `inventory_metadata.species` to the",
    "   sub-categories you actually emit.",
    "",
    "3. SPECIES. Set `inventory_metadata.species` from the sub-cats:",
    "     - any `dairy_cows` mapped + any non-dairy sub-cat → cattle_mixed",
    "     - `dairy_cows` only                              → cattle_dairy",
    "     - NO `dairy_cows` (only non-dairy sub-cats)      → cattle_non_dairy",
    "   For beef-only and smallholder African inventories (no",
    "   dairy_cows) the answer is `cattle_non_dairy`. NEVER default to",
    "   `cattle_mixed` as a hedge.",
    "",
    "4. For each sub-category, fill ALL 25 parameters from the IPCC",
    "   catalogue (N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, Cfi,",
    "   Ca, C, Cp, hours, CP, Ym, Bo, ASH, UE, EF3_PRP, EF4, EF5,",
    "   Frac_GASM_PRP, Frac_LEACH_PRP, MilkPR, Tw) — but honour rule 1:",
    "   user-supplied values OVERRIDE defaults.",
    "",
    "5. ASYMMETRIC BOUNDS. If the user's file has explicit lower /",
    "   upper bounds (Lower CI / Upper CI / lower / upper / ci_lower",
    "   / ci_upper / p2.5 / p97.5), USE those as `lower` and `upper`",
    "   directly, set `distribution = pert`, and leave",
    "   `uncertainty_pct` blank. Do NOT fall back to a symmetric",
    "   ±% from the catalogue.",
    "",
    "6. Manure_Management must contain rows for EVERY sub-category,",
    "   not just one. If the user's raw data has a single herd-wide",
    "   MMS allocation, copy that same allocation to every",
    "   sub-category. Each MMS row must have fraction_pct, MCF_pct,",
    "   EF3, Frac_GasMS_pct, AND Frac_LeachMS_pct filled.",
    "",
    "   If the user's file gives BOUNDS for the MMS allocation (e.g.",
    "   'pasture 35% (range 28-42%)'), include them as lower_fraction /",
    "   upper_fraction with distribution_fraction='pert'. Without these,",
    "   MMS allocation contributes zero uncertainty to the simulation —",
    "   which silently throws away a real source of inventory",
    "   uncertainty. Same applies to the coefficients: if the user has",
    "   country-specific bounds for MCF, EF3, Frac_GasMS_pct, or",
    "   Frac_LeachMS_pct, include them as lower_mcf/upper_mcf,",
    "   lower_ef3/upper_ef3, lower_frac_gas/upper_frac_gas,",
    "   lower_frac_leach/upper_frac_leach with their respective",
    "   distribution_* fields. When the user has no bounds, leave the",
    "   bounds fields null and the catalogue defaults will be used.",
    "",
    "7. STRICT JSON: no comments, no expressions like 4.5*1.032, no",
    "   'for brevity not shown' placeholders, no trailing commas.",
    "",
    "Do not ask any more questions. Just emit the complete",
    "template-ready JSON matching the schema.",
    sep = "\n")
  msgs <- anthropic_build_messages(system_prompt, history = state$messages,
                                  new_user_message = hard_requirements)

  # Try once; if the JSON parses, use it. If not (truncation, schema
  # mismatch, etc.), retry ONCE before giving up. Two attempts is a
  # reasonable trade-off between robustness and budget — strict json_schema
  # mode almost always returns valid JSON; failures are usually max_tokens
  # truncation on very large inventories, which a retry won't fix but a
  # retry is cheap and catches transient OpenAI hiccups.
  # Stream-aware progress callback: forward each JSON chunk's size to
  # the client so the progress bubble's elapsed counter can also show
  # 'X chars received' — gives the user concrete feedback that the AI
  # is producing output (not stuck waiting on OpenAI).
  total_chars <- 0L
  on_chunk_cb <- function(text) {
    total_chars <<- total_chars + nchar(text)
    tryCatch(session$sendCustomMessage("translatorProgressTick",
                                         list(chars = total_chars)),
              error = function(e) NULL)
  }
  resp <- NULL
  for (attempt in seq_len(2)) {
    resp <- anthropic_chat_template_force(msgs, on_chunk = on_chunk_cb)
    if (!is.null(resp$error)) break  # hard error — don't retry
    if (.translator_template_is_well_formed(resp$reply)) break
    if (attempt == 1L)
      message("translator: force-template attempt 1 produced unparseable JSON, retrying once.")
  }

  if (!is.null(resp$error)) {
    state$last_error <- resp$error
    return()
  }

  # Log the spend regardless of whether the JSON parsed — we still paid
  # for the tokens.
  usage_log_append(
    user_email        = state$user_email,
    model             = resp$model,
    prompt_tokens     = resp$usage$prompt_tokens,
    completion_tokens = resp$usage$completion_tokens,
    cached_tokens     = resp$usage$cached_tokens %||% 0L,
    cost_usd          = resp$cost_usd
  )

  if (!.translator_template_is_well_formed(resp$reply)) {
    # Both attempts produced unparseable / incomplete JSON. Don't set
    # last_template_json — the download button stays hidden, so the user
    # never gets the malformed .json file with the warning toast.
    # Diagnostic hint: if completion_tokens is at the 16k ceiling, the
    # response was almost certainly truncated.
    near_cap <- (resp$usage$completion_tokens %||% 0L) >= 31000L
    hint <- if (near_cap)
      paste0(" The response hit the output-size ceiling (~", resp$usage$completion_tokens,
             " tokens). This is the GPT-4.1 hard maximum — the inventory ",
             "is too large to fit in a single response. Reset the ",
             "conversation and ask the AI to translate ONLY the dairy ",
             "sub-categories first, then start a new conversation for the ",
             "beef ones (or vice versa). The two .xlsx files can be merged ",
             "by hand afterwards.")
    else
      " Type 'go ahead' again — this is sometimes a transient AI-service hiccup."
    state$last_error <- paste0(
      "Couldn't produce a complete template from the AI's response.",
      hint)
    return()
  }

  # Valid JSON. Coverage check + auto-retry: the AI very often emits a
  # single representative sub-category (usually dairy_cows) and treats
  # the rest as "implied", even when the conversation listed all 8. We
  # scan the conversation history for canonical sub-category names, and
  # if the output is missing any that were discussed, do ONE extra
  # force-template call with an explicit list of the missing ones.
  parsed_check <- tryCatch(jsonlite::fromJSON(resp$reply, simplifyVector = TRUE),
                            error = function(e) NULL)
  history_subcats <- .translator_detect_subcategories_in_history(state$messages)
  # Filter history_subcats against the declared species. Without this,
  # a chat message saying "no dairy_cows" or "species = cattle_non_dairy"
  # would falsely flag dairy_cows as a missing sub-category, producing
  # the spurious "skipped dairy_cows" warning (and an unnecessary retry).
  # Same logic as the post-JSON sub-cat strip below.
  declared_species <- if (!is.null(parsed_check))
    parsed_check$inventory_metadata$species %||% "" else ""
  if (identical(declared_species, "cattle_non_dairy")) {
    history_subcats <- setdiff(history_subcats, "dairy_cows")
  } else if (identical(declared_species, "cattle_dairy")) {
    history_subcats <- setdiff(history_subcats,
      c("other_cows", "bulls", "oxen", "heifers", "growing_males",
        "calves_male", "calves_female"))
  }
  output_subcats <- if (!is.null(parsed_check) &&
                          is.data.frame(parsed_check$parameters))
    unique(parsed_check$parameters$sub_category) else character(0)
  missing_subcats <- setdiff(history_subcats, output_subcats)

  if (length(missing_subcats) > 0 && length(output_subcats) > 0) {
    message("translator: force-template missing sub-categories: ",
            paste(missing_subcats, collapse = ", "),
            " — retrying with explicit list.")
    # Push an extra user message that NAMES every missing sub-category.
    msgs_retry <- c(msgs, list(list(
      role    = "user",
      content = paste0(
        "You just emitted parameters for: ",
        paste(output_subcats, collapse = ", "),
        ". But this inventory has ", length(history_subcats),
        " sub-categories total: ",
        paste(history_subcats, collapse = ", "),
        ". You missed: ", paste(missing_subcats, collapse = ", "),
        ". Emit the COMPLETE template now with all ",
        length(history_subcats),
        " sub-categories × 25 parameters = ",
        25 * length(history_subcats),
        " parameter rows, plus manure_management for ALL ",
        length(history_subcats),
        " sub-categories. Use the user's file values for parameters ",
        "they supplied (data_source = 'user_file' on those rows); use ",
        "IPCC catalogue defaults ONLY for parameters the file does not ",
        "supply (data_source = 'ipcc_default' on those rows). ",
        "Strict JSON, no comments, no shortcuts. List every row."))))
    resp2 <- anthropic_chat_template_force(msgs_retry)
    if (is.null(resp2$error) && .translator_template_is_well_formed(resp2$reply)) {
      # Re-log the spend for the retry call.
      usage_log_append(
        user_email        = state$user_email,
        model             = resp2$model,
        prompt_tokens     = resp2$usage$prompt_tokens,
        completion_tokens = resp2$usage$completion_tokens,
        cached_tokens     = resp2$usage$cached_tokens %||% 0L,
        cost_usd          = resp2$cost_usd)
      resp <- resp2  # promote the better attempt
      parsed_check <- tryCatch(jsonlite::fromJSON(resp$reply,
                                                    simplifyVector = TRUE),
                                error = function(e) NULL)
      output_subcats <- if (!is.null(parsed_check) &&
                              is.data.frame(parsed_check$parameters))
        unique(parsed_check$parameters$sub_category) else character(0)
      missing_subcats <- setdiff(history_subcats, output_subcats)
    }
  }

  # NEW: defaults-only rejection. If a file was uploaded but the AI's
  # output has zero rows tagged data_source = "user_file" (or similar),
  # the AI did the Step-5b failure: emitted an all-IPCC-defaults grid
  # and threw away every value from the file. Retry ONCE with a stronger
  # error message, then surface the failure to the user if it persists.
  file_was_uploaded <- any(vapply(state$messages, function(m) {
    content <- m$content %||% ""
    grepl("Parameter labels DETECTED IN THIS FILE", content, fixed = TRUE)
  }, logical(1)))
  count_user_file_rows <- function(pj) {
    if (is.null(pj) || !is.data.frame(pj$parameters)) return(0L)
    ds <- pj$parameters$data_source
    if (is.null(ds)) return(0L)
    sum(grepl("^user[_ ]?(file|chat)$|^file$|^chat$", ds,
              ignore.case = TRUE), na.rm = TRUE)
  }
  user_file_rows <- count_user_file_rows(parsed_check)
  if (file_was_uploaded && user_file_rows == 0L &&
        length(output_subcats) > 0L) {
    message("translator: force-template emitted ZERO user_file rows ",
            "despite uploaded file — retrying with explicit demand.")
    msgs_retry_vals <- c(msgs, list(list(
      role    = "user",
      content = paste0(
        "REJECTED — your output has ZERO rows tagged ",
        "data_source = 'user_file'. The user uploaded a file with ",
        "specific values for parameters like BW / MW / WG / pct_pregnant ",
        "/ DE / CP / Milk / Fat / hours / MMS allocation. You did NOT ",
        "use any of those values — you emitted catalogue defaults across ",
        "the board. This is the Step-5b failure mode the system prompt ",
        "warns about. Re-emit the complete template-ready JSON now and: ",
        "(1) For EVERY parameter present in the user's uploaded file: ",
        "    - value = the file's mean value (NOT the catalogue default) ",
        "    - lower / upper = the file's Lower CI / Upper CI ",
        "    - distribution = 'pert' ",
        "    - data_source = 'user_file' ",
        "(2) For parameters the file does NOT supply: ",
        "    - use the catalogue default ",
        "    - data_source = 'ipcc_default' ",
        "(3) For biological zeros (Milk=0 for males/calves, hours=0 for ",
        "    non-oxen, etc.): data_source = 'biological_zero', ",
        "    distribution = 'constant'. ",
        "Strict JSON. No shortcuts. Every row must have data_source set."))))
    resp_v <- anthropic_chat_template_force(msgs_retry_vals)
    if (is.null(resp_v$error) &&
          .translator_template_is_well_formed(resp_v$reply)) {
      usage_log_append(
        user_email        = state$user_email,
        model             = resp_v$model,
        prompt_tokens     = resp_v$usage$prompt_tokens,
        completion_tokens = resp_v$usage$completion_tokens,
        cached_tokens     = resp_v$usage$cached_tokens %||% 0L,
        cost_usd          = resp_v$cost_usd)
      pcheck_v <- tryCatch(jsonlite::fromJSON(resp_v$reply,
                                              simplifyVector = TRUE),
                            error = function(e) NULL)
      if (count_user_file_rows(pcheck_v) > user_file_rows) {
        resp <- resp_v               # promote
        parsed_check <- pcheck_v
        output_subcats <- if (is.data.frame(parsed_check$parameters))
          unique(parsed_check$parameters$sub_category) else character(0)
        missing_subcats <- setdiff(history_subcats, output_subcats)
        user_file_rows <- count_user_file_rows(parsed_check)
      }
    }
  }

  # NEW: strip sub-categories that contradict the declared species. If
  # species = "cattle_non_dairy" then dairy_cows must not appear; if
  # species = "cattle_dairy" then beef sub-cats must not appear. The AI
  # frequently emits the full canonical 8-block grid regardless of what
  # the user mapped; this filter prevents the orphan blocks from
  # reaching the .xlsx.
  NON_DAIRY_SC <- c("other_cows", "bulls", "oxen", "heifers",
                     "growing_males", "calves_male", "calves_female")
  DAIRY_SC     <- c("dairy_cows")
  if (!is.null(parsed_check) && is.data.frame(parsed_check$parameters)) {
    species <- parsed_check$inventory_metadata$species %||% ""
    drop_subcats <- character(0)
    if (identical(species, "cattle_non_dairy")) {
      drop_subcats <- intersect(output_subcats, DAIRY_SC)
    } else if (identical(species, "cattle_dairy")) {
      drop_subcats <- intersect(output_subcats, NON_DAIRY_SC)
    }
    if (length(drop_subcats) > 0L) {
      message("translator: stripping sub-cats incompatible with species=",
              species, ": ", paste(drop_subcats, collapse = ", "))
      keep <- !(parsed_check$parameters$sub_category %in% drop_subcats)
      parsed_check$parameters <- parsed_check$parameters[keep, , drop = FALSE]
      if (is.data.frame(parsed_check$manure_management)) {
        keep_mm <- !(parsed_check$manure_management$sub_category %in%
                       drop_subcats)
        parsed_check$manure_management <-
          parsed_check$manure_management[keep_mm, , drop = FALSE]
      }
      resp$reply <- jsonlite::toJSON(parsed_check, auto_unbox = TRUE,
                                       na = "null", null = "null",
                                       dataframe = "rows")
      output_subcats <- unique(parsed_check$parameters$sub_category)
      missing_subcats <- setdiff(history_subcats, output_subcats)
    }
  }

  # Final coverage messages (after auto-retry). Only surface a warning
  # if something is STILL wrong — the retry may have fixed everything.
  coverage_msgs <- character(0)
  if (!is.null(parsed_check)) {
    if (length(missing_subcats) > 0)
      coverage_msgs <- c(coverage_msgs, paste0(
        "Heads up: the AI emitted parameters for ",
        paste(output_subcats, collapse = ", "),
        " but skipped ", paste(missing_subcats, collapse = ", "),
        " (mentioned earlier in the chat). The download is still valid ",
        "for what's present, but emissions for the missing sub-categories ",
        "will be zero. Hit 'Produce template now' again to retry, or ",
        "open the .xlsx and add the missing rows by hand."))

    sc_param <- output_subcats
    sc_mm <- if (is.data.frame(parsed_check$manure_management))
      unique(parsed_check$manure_management$sub_category) else character(0)
    missing_in_mm <- setdiff(sc_param, sc_mm)
    if (length(missing_in_mm) > 0 && length(sc_mm) > 0)
      coverage_msgs <- c(coverage_msgs, paste0(
        "Manure_Management only covers ", paste(sc_mm, collapse = ", "),
        " — manure CH4/N2O for ", paste(missing_in_mm, collapse = ", "),
        " will be zero. Retry 'Produce template now' or add the MMS ",
        "rows yourself."))
  }
  if (length(coverage_msgs) > 0)
    state$last_error <- paste(coverage_msgs, collapse = " ")

  state$last_template_json <- resp$reply
  # Two messages: the raw JSON (kept on state for replay / download) and
  # a separate, prominent guidance bubble pointing at the green
  # Download button. Same wording as the chat-path hint so the user's
  # mental model stays consistent.
  state$messages[[length(state$messages) + 1]] <-
    list(role    = "assistant",
         content = resp$reply,
         display = "Template generated.")
  .translator_append_download_hint(state)
  tryCatch(conversation_save(state$user_email, state$messages),
           error = function(e) NULL)
}

# Write the AI's template-ready JSON to an .xlsx that LOOKS LIKE THE
# OFFICIAL INPUT TEMPLATE — same column ordering, header colours,
# tab colours, sheet names, README / Vocab / _Lists sheets.
#
# Strategy: call the existing generate_template_openxlsx() helper to
# produce a blank-but-styled official template, then load the workbook
# and OVERWRITE the data cells with the AI's values. This preserves
# every bit of styling, dropdowns, formulas, and supporting sheets
# without us having to re-implement them.
#
# Multi-sub-category handling: the blank template ships with ONE
# pre-formatted sub-category block in the Parameters sheet (one row
# per IPCC parameter, ordered by PARAM_CATALOGUE). For each
# sub-category in the AI's JSON we either overwrite that block (first
# sub-category) or append a new block below (subsequent sub-categories).
# Appended blocks share the column structure but only get basic styling
# — acceptable tradeoff for now.
#
# Falls back to a raw .json dump if the JSON is malformed (so the user
# never loses the AI's work). The download handler checks JSON validity
# beforehand and uses the .json extension in that case.
.translator_write_template_xlsx <- function(json_text, file_path) {
  if (is.null(json_text) || !nzchar(json_text)) {
    writeLines("{}", file_path); return(invisible(NULL))
  }
  parsed <- tryCatch(jsonlite::fromJSON(json_text, simplifyVector = TRUE),
                      error = function(e) NULL)
  if (is.null(parsed)) {
    writeLines(json_text, file_path); return(invisible(NULL))
  }

  ok <- tryCatch({
    .translator_write_official_template(parsed, file_path); TRUE
  }, error = function(e) {
    message("translator: official-template write failed: ",
            conditionMessage(e), " — falling back to simple xlsx.")
    FALSE
  })
  if (!ok) .translator_write_simple_xlsx(parsed, file_path)
  invisible(NULL)
}

# Primary writer — overlays AI values onto the official blank template.
.translator_write_official_template <- function(parsed, file_path) {
  if (!exists("generate_template_openxlsx") || !exists("PARAM_CATALOGUE"))
    stop("template-generation helpers not available")

  ipcc_version <- parsed$inventory_metadata$ipcc_version %||% "2019_refinement"
  ipcc_short <- if (grepl("2019|refinement", ipcc_version, ignore.case = TRUE))
    "2019_refinement" else "2006"

  tmp_blank <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_blank), add = TRUE)
  generate_template_openxlsx(tmp_blank, include_example = FALSE,
                              ipcc_version = ipcc_short)

  wb <- openxlsx::loadWorkbook(tmp_blank)

  # ---------- Inventory_Metadata --------------------------------------------
  md <- parsed$inventory_metadata %||% list()
  # Row order matches meta_fields in generate_template_openxlsx:
  #   row 2 Country / row 3 Region / row 4 Year / row 5 Species /
  #   row 6 IPCC version / row 7 Prepared by / row 8 Notes
  .put_meta <- function(row, val) {
    if (is.null(val) || (is.character(val) && !nzchar(val))) return()
    openxlsx::writeData(wb, "Inventory_Metadata", val,
                        startRow = row, startCol = 3, colNames = FALSE)
  }
  .put_meta(2, md$country %||% md$country_region)
  .put_meta(3, md$region %||% md$continental_region %||% "africa")
  .put_meta(4, md$inventory_year %||% md$year)
  .put_meta(5, md$species %||% "cattle_dairy")
  .put_meta(6, md$ipcc_version %||% ipcc_short)
  .put_meta(7, md$prepared_by)
  .put_meta(8, md$notes)

  # ---------- Parameters ----------------------------------------------------
  params <- parsed$parameters
  if (is.data.frame(params) && nrow(params) > 0) {
    n_params  <- nrow(PARAM_CATALOGUE)
    DATA_START <- 4L
    # Build the per-sub-category key in the AI's data.
    if (!"sub_category" %in% names(params))
      stop("AI template missing 'sub_category' column in parameters[]")
    sub_keys <- unique(paste(
      params$cattle_type       %||% rep("dairy", nrow(params)),
      params$aggregation_level %||% rep("all",   nrow(params)),
      params$sub_category,
      sep = "||"))

    for (k in seq_along(sub_keys)) {
      parts <- strsplit(sub_keys[k], "||", fixed = TRUE)[[1]]
      cattle_type <- parts[1]
      agg_level   <- parts[2]
      sub_cat     <- parts[3]

      # Block of rows for this sub-category, in PARAM_CATALOGUE order.
      block_start <- DATA_START + (k - 1L) * n_params

      for (i in seq_len(n_params)) {
        r      <- block_start + i - 1L
        p_name <- PARAM_CATALOGUE$parameter[i]
        # Find AI's row matching this sub_cat + parameter (may be missing).
        mask <- params$sub_category == sub_cat & params$parameter == p_name
        mask[is.na(mask)] <- FALSE
        ai   <- if (any(mask)) params[which(mask)[1], , drop = FALSE] else NULL

        # Column 1-3: cattle_type / aggregation_level / sub_category
        openxlsx::writeData(wb, "Parameters", cattle_type, startRow = r,
                            startCol = 1, colNames = FALSE)
        openxlsx::writeData(wb, "Parameters", agg_level,   startRow = r,
                            startCol = 2, colNames = FALSE)
        openxlsx::writeData(wb, "Parameters", sub_cat,     startRow = r,
                            startCol = 3, colNames = FALSE)

        # For sub-category blocks AFTER the first, the row is blank — we
        # need to write the static info cells (parameter / definition /
        # unit / param_type / ipcc_ref) too.
        if (k > 1L) {
          openxlsx::writeData(wb, "Parameters", p_name,
                              startRow = r, startCol = 4, colNames = FALSE)
          openxlsx::writeData(wb, "Parameters",
                              PARAM_CATALOGUE$definition[i],
                              startRow = r, startCol = 5, colNames = FALSE)
          openxlsx::writeData(wb, "Parameters",
                              PARAM_CATALOGUE$unit[i],
                              startRow = r, startCol = 6, colNames = FALSE)
          openxlsx::writeData(wb, "Parameters",
                              PARAM_CATALOGUE$param_type[i],
                              startRow = r, startCol = 14, colNames = FALSE)
          openxlsx::writeData(wb, "Parameters",
                              PARAM_CATALOGUE$ipcc_ref[i],
                              startRow = r, startCol = 15, colNames = FALSE)
        }

        # If the AI provided this parameter for this sub-cat, write its
        # value / uncertainty / bounds / distribution.
        #
        # Column layout in the official template:
        #   7  = value (yellow user-data cell)
        #   8  = uncertainty_pct (symmetric ±% input)
        #   9  = lower_bound (catalogue reference — display only)
        #   10 = upper_bound (catalogue reference — display only)
        #   11 = distribution
        #   12 = lower (asymmetric override — what the simulator reads)
        #   13 = upper (asymmetric override — what the simulator reads)
        #   16 = data_source
        #
        # The AI's bounds MUST go into cols 12/13 so the simulator picks
        # them up. Previously they were written to 9/10 (the catalogue
        # display columns) and the simulator saw NA in 12/13 — which the
        # NA-bounds guard in sample_distribution() turned into NA samples
        # for every row, eventually crashing the quantile() convergence
        # check on total_co2e. Cols 9/10 keep the catalogue default
        # values that the blank template pre-fills.
        if (!is.null(ai)) {
          .put_param <- function(col_idx, v) {
            if (is.null(v) || length(v) == 0) return()
            if (is.na(v[1]) || (is.character(v[1]) && !nzchar(v[1]))) return()
            openxlsx::writeData(wb, "Parameters", v[1],
                                startRow = r, startCol = col_idx,
                                colNames = FALSE)
          }
          .put_param(7,  ai$mean %||% ai$value)
          .put_param(8,  ai$uncertainty_pct)
          .put_param(12, ai$lower_bound %||% ai$lower)
          .put_param(13, ai$upper_bound %||% ai$upper)
          .put_param(11, ai$distribution)
          .put_param(16, ai$data_source %||% "AI translator")
        }
      }
    }
  }

  # ---------- Manure_Management ---------------------------------------------
  mm <- parsed$manure_management
  if (is.data.frame(mm) && nrow(mm) > 0) {
    MM_DATA_START <- 4L   # template puts banner @ row 1, headers @ 2, hints @ 3
    for (i in seq_len(nrow(mm))) {
      r <- MM_DATA_START + i - 1L
      .put_mm <- function(col_idx, v) {
        if (is.null(v) || length(v) == 0) return()
        if (is.na(v[1]) || (is.character(v[1]) && !nzchar(v[1]))) return()
        openxlsx::writeData(wb, "Manure_Management", v[1],
                            startRow = r, startCol = col_idx,
                            colNames = FALSE)
      }
      .put_mm(1, mm$cattle_type[i]       %||% "dairy")
      .put_mm(2, mm$aggregation_level[i] %||% "all")
      .put_mm(3, mm$sub_category[i])
      .put_mm(4, mm$mms_type[i])
      .put_mm(5, mm$fraction_pct[i])
      # Fraction bounds — col 6/7/8. Sampled by the simulator if present;
      # absent/equal-to-central → deterministic. The user often has
      # uncertainty on the MMS allocation in the source file; this row
      # propagates it through.
      .put_mm(6, mm$lower_fraction[i])
      .put_mm(7, mm$upper_fraction[i])
      .put_mm(8, mm$distribution_fraction[i] %||% "pert")
      # Coefficient columns + their bounds. Each block is [value, lower,
      # upper, distribution] at consecutive positions:
      #   MCF_pct        @ 9   (10 lower, 11 upper, 12 distribution)
      #   EF3            @ 13  (14 lower, 15 upper, 16 distribution)
      #   Frac_GasMS_pct @ 17  (18 lower, 19 upper, 20 distribution)
      #   Frac_LeachMS_pct@ 21 (22 lower, 23 upper, 24 distribution)
      # The AI can be inconsistent on key case; tolerate both.
      .put_mm(9,  mm$mcf[i]              %||% mm$MCF_pct[i])
      .put_mm(10, mm$lower_mcf[i])
      .put_mm(11, mm$upper_mcf[i])
      .put_mm(12, mm$distribution_mcf[i])
      .put_mm(13, mm$ef3[i]              %||% mm$EF3[i])
      .put_mm(14, mm$lower_ef3[i])
      .put_mm(15, mm$upper_ef3[i])
      .put_mm(16, mm$distribution_ef3[i])
      .put_mm(17, mm$Frac_GasMS_pct[i]   %||% mm$frac_gasms_pct[i] %||%
                   mm$Frac_GasMS[i])
      .put_mm(18, mm$lower_frac_gas[i])
      .put_mm(19, mm$upper_frac_gas[i])
      .put_mm(20, mm$distribution_frac_gas[i])
      .put_mm(21, mm$Frac_LeachMS_pct[i] %||% mm$frac_leachms_pct[i] %||%
                   mm$Frac_LeachMS[i])
      .put_mm(22, mm$lower_frac_leach[i])
      .put_mm(23, mm$upper_frac_leach[i])
      .put_mm(24, mm$distribution_frac_leach[i])
    }
  }

  # ---------- Parameter_TimeSeries -----------------------------------------
  # Optional multi-year activity-data table. The blank template puts
  # banner @ row 1, headers @ 2, desc @ 3, units @ 4 — so data rows
  # start at row 5. Columns:
  #   1 cattle_type    2 aggregation_level    3 sub_category    4 year
  #   5 N    6 BW    7 MW    8 WG    9 Milk   10 Fat
  #  11 pct_pregnant   12 DE   13 CP   14 MilkPR
  ts <- parsed$parameter_timeseries
  if (is.data.frame(ts) && nrow(ts) > 0) {
    TS_DATA_START <- 5L
    for (i in seq_len(nrow(ts))) {
      r <- TS_DATA_START + i - 1L
      .put_ts <- function(col_idx, v) {
        if (is.null(v) || length(v) == 0) return()
        if (is.na(v[1]) || (is.character(v[1]) && !nzchar(v[1]))) return()
        openxlsx::writeData(wb, "Parameter_TimeSeries", v[1],
                            startRow = r, startCol = col_idx,
                            colNames = FALSE)
      }
      .put_ts(1,  ts$cattle_type[i])
      .put_ts(2,  ts$aggregation_level[i])
      .put_ts(3,  ts$sub_category[i])
      .put_ts(4,  ts$year[i])
      .put_ts(5,  ts$N[i])
      .put_ts(6,  ts$BW[i])
      .put_ts(7,  ts$MW[i])
      .put_ts(8,  ts$WG[i])
      .put_ts(9,  ts$Milk[i])
      .put_ts(10, ts$Fat[i])
      .put_ts(11, ts$pct_pregnant[i])
      .put_ts(12, ts$DE[i])
      .put_ts(13, ts$CP[i])
      .put_ts(14, ts$MilkPR[i])
    }
  }

  openxlsx::saveWorkbook(wb, file_path, overwrite = TRUE)
}

# Fallback writer — used only when the official template builder errors
# (missing helper, dependency problem, etc.). Produces a 3-sheet xlsx
# with the AI's data but no styling. Better than nothing.
.translator_write_simple_xlsx <- function(parsed, file_path) {
  sheets <- list()
  if (!is.null(parsed$inventory_metadata)) {
    md <- parsed$inventory_metadata
    sheets[["Inventory_Metadata"]] <- data.frame(
      Field = c("Country", "Continental region", "Inventory year",
                "Livestock species", "IPCC Guidelines version",
                "Prepared by", "Notes"),
      Value = c(md$country %||% "",
                md$region  %||% "africa",
                md$inventory_year %||% md$year %||% "",
                md$species %||% "cattle_dairy",
                md$ipcc_version %||% "2019_refinement",
                md$prepared_by %||% "",
                md$notes %||% ""),
      stringsAsFactors = FALSE)
  }
  if (is.data.frame(parsed$parameters) && nrow(parsed$parameters) > 0)
    sheets[["Parameters"]] <- as.data.frame(parsed$parameters,
                                              stringsAsFactors = FALSE)
  if (is.data.frame(parsed$manure_management) &&
      nrow(parsed$manure_management) > 0)
    sheets[["Manure_Management"]] <- as.data.frame(parsed$manure_management,
                                                    stringsAsFactors = FALSE)
  if (is.data.frame(parsed$parameter_timeseries) &&
      nrow(parsed$parameter_timeseries) > 0)
    sheets[["Parameter_TimeSeries"]] <- as.data.frame(
      parsed$parameter_timeseries, stringsAsFactors = FALSE)
  if (length(sheets) == 0)
    sheets[["RawOutput"]] <- data.frame(
      content = jsonlite::toJSON(parsed, auto_unbox = TRUE, pretty = TRUE),
      stringsAsFactors = FALSE)
  writexl::write_xlsx(sheets, path = file_path)
}

# Split an assistant message into a clean "visible" part and a hidden
# "details/structure" part.
#
# Three cases the message bubble UI cares about:
#
#   1. Force-template path  : m$content is pure JSON (json_schema mode),
#                              m$display is "Template ready..." text.
#                              -> visible = m$display, hidden = m$content.
#
#   2. Normal reply with ```template-ready ... ``` fence inline:
#                              -> visible = the prose with the fence
#                                 stripped out, hidden = the JSON.
#
#   3. Normal reply, no fence:
#                              -> visible = m$content (or m$display),
#                                 hidden = NULL (no expander shown).
#
# Returns a list with $visible (character) and $hidden (character or NULL).
.translator_split_visible_hidden <- function(content, display = NULL) {
  fallback <- list(visible = display %||% content %||% "",
                   hidden  = NULL)
  if (is.null(content) || !nzchar(content)) return(fallback)

  # Case 1: pure-JSON body + a separate display message. Detected when
  # display differs from content AND content looks like a JSON object.
  if (!is.null(display) && nzchar(display) && !identical(display, content)) {
    trimmed <- trimws(content)
    if (startsWith(trimmed, "{") && endsWith(trimmed, "}")) {
      return(list(visible = display, hidden = trimmed))
    }
  }

  # Case 2: inline ```template-ready ... ``` fenced block. Strip the
  # whole block from the visible text and surface its inner JSON in the
  # expander. Leading/trailing whitespace from the strip is cleaned up.
  m <- regexpr("```template-ready\\s*\\n([\\s\\S]*?)\\n```",
               content, perl = TRUE)
  if (m > 0) {
    fence <- regmatches(content, m)
    inner <- sub("^```template-ready\\s*\\n", "", fence, perl = TRUE)
    inner <- sub("\\n```$", "", inner)
    visible <- sub("```template-ready\\s*\\n[\\s\\S]*?\\n```",
                   "", content, perl = TRUE)
    # Collapse the >2 blank lines the strip might leave behind.
    visible <- gsub("\\n{3,}", "\n\n", trimws(visible))
    return(list(visible = if (nzchar(visible)) visible
                            else "Template ready — click the green download button below to get the .xlsx.",
                hidden = trimws(inner)))
  }

  fallback
}

# Detect when a user's typed message is asking the AI to generate the
# final template (instead of continuing the clarifying-questions
# conversation). Triggers the json_schema force-template path. Matches
# common phrasings in English + a couple of French / Spanish variants
# the typical user might type. Whole-word matching so 'go' doesn't
# match 'cargo' etc.
.translator_is_generate_trigger <- function(txt) {
  if (is.null(txt) || !nzchar(txt)) return(FALSE)
  t <- tolower(trimws(txt))
  # Length guard. The trigger detection used to match any message
  # containing "produce template" or "go ahead" ANYWHERE in the text —
  # which mis-fired on long instruction messages like "answer X, Y, Z
  # then I'll click Produce template now." Real "go" commands from
  # users are short — typically under 80 chars and 15 words. If the
  # message is longer than that, it's an instruction or answer, not a
  # generate command, even if it mentions the phrase. Users who really
  # want to trigger generation from a long message can always click the
  # "Produce template now" button instead.
  n_chars <- nchar(t)
  n_words <- length(strsplit(t, "\\s+")[[1]])
  if (n_chars > 80L || n_words > 15L) return(FALSE)
  patterns <- c(
    # Anchored to start (^) where possible — prevents matches inside
    # quoted phrases or instruction sentences mid-message.
    "^(please |now |ok |okay |yes,? )?produce (the |a )?template",
    "^(please |now |ok |okay |yes,? )?generate (the |a )?(template|file|output|xlsx)",
    "^(please |now |ok |okay |yes,? )?create (the |a )?(template|file|output|xlsx)",
    "^(please |now |ok |okay |yes,? )?make (the |a )?(template|file|output|xlsx)",
    "^(please |now |ok |okay |yes,? )?build (the |a )?(template|file|output|xlsx)",
    "^(please |now |ok |okay |yes,? )?give me (the |a )?(template|file|output|xlsx)",
    "^(please |now |ok |okay |yes,? )?translate (the |my )?data",
    "^go ahead\\b",
    "^do (it|as you think)\\b",
    "^you decide\\b",
    "^i'?m ready\\b",
    "^ready to (generate|produce|go|download)\\b",
    "^let'?s? go\\b",
    "^ok go\\b",
    "^yes( please)?,? (do|generate|produce|go)\\b",
    "^(produire|générer|créer) (le |la |un |une )?(template|fichier)"
  )
  any(vapply(patterns, function(p) grepl(p, t, perl = TRUE), logical(1)))
}

# Scan the conversation history for canonical sub-category names and
# return the de-duplicated set. Used by .translator_force_template to
# detect when the AI silently dropped sub-categories from its output
# (a common failure mode — the AI emits one "representative" sub-cat
# and ignores the rest, even when the chat clearly listed all 8). The
# controlled vocabulary comes from translator_prompts/template_schema.md.
.TRANSLATOR_SUBCATEGORY_VOCAB <- c(
  "dairy_cows", "other_cows", "bulls", "oxen",
  "heifers", "growing_males", "growing_females",
  "calves_male", "calves_female"
)
.translator_detect_subcategories_in_history <- function(messages) {
  if (length(messages) == 0) return(character(0))
  text <- paste(vapply(messages, function(m) {
    paste(as.character(m$content %||% ""),
          as.character(m$display %||% ""), sep = " ")
  }, character(1)), collapse = "\n")
  if (!nzchar(text)) return(character(0))
  found <- vapply(.TRANSLATOR_SUBCATEGORY_VOCAB, function(s) {
    grepl(paste0("\\b", s, "\\b"), text, fixed = FALSE)
  }, logical(1))
  unname(.TRANSLATOR_SUBCATEGORY_VOCAB[found])
}

# Validate that a template JSON string parses AND has the expected shape
# (a non-empty `parameters` array). Used to gate whether the download
# button appears and whether the force-template path retries.
# Returns TRUE / FALSE.
.translator_template_is_well_formed <- function(json_text) {
  if (is.null(json_text) || !nzchar(json_text)) return(FALSE)
  parsed <- tryCatch(jsonlite::fromJSON(json_text, simplifyVector = TRUE),
                      error = function(e) NULL)
  if (is.null(parsed)) return(FALSE)
  if (is.null(parsed$parameters)) return(FALSE)
  if (is.data.frame(parsed$parameters) && nrow(parsed$parameters) == 0)
    return(FALSE)
  if (is.list(parsed$parameters) && !is.data.frame(parsed$parameters) &&
      length(parsed$parameters) == 0)
    return(FALSE)
  TRUE
}

# Look for ```template-ready ... ``` and return the inner JSON; NULL if
# none. The sentinel marker is documented in the system prompt
# (assemble_translator_system_prompt()).
.translator_extract_template_ready <- function(reply) {
  if (is.null(reply) || !nzchar(reply)) return(NULL)
  m <- regmatches(reply,
                   regexpr("```template-ready\\s*\\n([\\s\\S]*?)\\n```",
                           reply, perl = TRUE))
  if (length(m) == 0 || !nzchar(m)) return(NULL)
  inner <- sub("^```template-ready\\s*\\n", "", m, perl = TRUE)
  inner <- sub("\\n```$", "", inner)
  trimws(inner)
}
