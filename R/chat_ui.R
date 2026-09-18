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
    login_status = NULL,      # one-line message under the login form
    # 2026-06-11: resumable batches. The batched emission path in
    # .translator_force_template() caches each per-aggregation-level
    # batch's parsed JSON here keyed by aggregation_level. On a retry
    # after a failed batch, successful batches are reused without firing
    # a fresh API call (saves the output-token cost — Anthropic only
    # caches inputs, not outputs). Cleared on successful merge / Reset
    # conversation / new file upload. Since 2026-09-17 a part is cached
    # only after the merge has validated it, and the cache is persisted in
    # the conversation file so a Stop (page reload) keeps it (plan A3, F5).
    batch_parts = list(),
    # 2026-09-17: an upload waiting for the user to pick sheets (plan F8).
    pending_upload = NULL,
    # 2026-09-17: TRUE when the saved conversation was held under a
    # different system prompt (the defaults or the template changed since).
    # Emission is refused until a new upload is explored under the live
    # prompt (plan B5).
    prompt_stale = FALSE
  )
}

# Save the conversation together with everything that must survive a page
# reload: the prompt hash the conversation was held under and the validated
# per-batch parts.
.translator_persist <- function(state) {
  tryCatch(conversation_save(
    state$user_email, state$messages,
    prompt_hash = tryCatch(translator_system_prompt_hash(), error = function(e) NULL),
    extra = list(batch_parts = if (length(state$batch_parts)) state$batch_parts else NULL)),
    error = function(e) NULL)
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
      saved <- tryCatch(conversation_load_full(restored),
                        error = function(e) list(messages = list()))
      if (length(saved$messages) > 0) {
        state$messages <- saved$messages
        # Restore validated batch parts (plan F5) so a Stop mid-emission
        # does not throw away the batches already paid for.
        bp <- saved$extra$batch_parts
        if (is.list(bp) && length(bp) > 0) state$batch_parts <- bp
        # Prompt staleness (plan B5): the defaults or the template changed
        # since this conversation was held. The model's earlier replies
        # quote the old numbers, so emission from this transcript would
        # bake them into the workbook. Hold emission until a new upload.
        live_hash <- tryCatch(translator_system_prompt_hash(), error = function(e) NULL)
        if (!is.null(live_hash) && !identical(saved$prompt_hash, live_hash)) {
          state$prompt_stale <- TRUE
          state$messages[[length(state$messages) + 1]] <- list(
            role = "assistant", source = "server_notice",
            content = "(prompt changed notice)",
            display = paste(
              "The IPCC defaults or the template layout changed since this",
              "conversation was held, so the values discussed above may be",
              "out of date. Please upload your file again before producing",
              "a template; the Produce button stays off until you do."))
        }
      }
    }
  }, once = TRUE, ignoreInit = FALSE)

  # ---- One-shot URL-token consumption on app start --------------------------
  observeEvent(session$clientData$url_search, {
    qs <- shiny::parseQueryString(session$clientData$url_search %||% "")
    tok <- qs$token
    if (is.null(tok) || !nzchar(tok)) return()
    email <- auth_token_consume(tok)
    if (is.null(email)) {
      state$login_status <- sprintf("Sign-in link was invalid or has expired (links are valid for %s). Please request a new one.", .auth_link_validity_text())
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
        "Sent! Check ", email, " for a sign-in link (valid ", .auth_link_validity_text(), "). ",
        "If you don't see it, check spam.")
    } else {
      state$login_status <- paste0(
        "We couldn't send the sign-in email: the email service returned an ",
        "error, which has been logged on the server. Please contact the ",
        "administrator, who can also send you the sign-in link directly.")
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

  # ---- File upload: parse, let the user choose sheets, then send ----------
  #
  # 2026-09-17 (plan F7, F8). The upload used to go straight to the model
  # with every non-empty sheet. It now parses (memoised by file hash, so a
  # re-upload after Reset costs nothing and yields byte-identical JSON,
  # which is what lets the prompt cache hit), shows one checkbox per sheet
  # with its size in tokens, and sends only the ticked sheets when the user
  # clicks "Send to the AI". For the Zambia file, leaving the Coefficients
  # sheet unticked when the user has no country coefficients removes ~17K
  # tokens from every call of the run.
  observeEvent(input$translator_file, {
    req(state$user_email)
    fi <- input$translator_file
    if (is.null(fi)) return()
    # New file = fresh emission. Drop any cached per-batch parts so we
    # don't reuse rows from a previous file's conversation, and clear any
    # prompt-staleness hold: the new upload will be explored under the
    # live prompt.
    state$batch_parts <- list()
    state$prompt_stale <- FALSE
    parsed <- tryCatch(
      .translator_read_upload_memo(fi$datapath, fi$name),
      error = function(e) {
        state$last_error <- paste0("Couldn't read the uploaded file: ",
                                    conditionMessage(e))
        NULL
      }
    )
    if (is.null(parsed)) { state$pending_upload <- NULL; return() }
    state$last_error <- NULL
    state$pending_upload <- list(parsed = parsed, name = fi$name,
                                 hash = parsed$file_hash)
  })

  # The sheet picker. Rendered only while an upload is waiting to be sent.
  output$translator_sheet_picker <- renderUI({
    pu <- state$pending_upload
    if (is.null(pu)) return(NULL)
    sheets <- pu$parsed$sheets
    labels <- vapply(seq_along(sheets), function(i) {
      s <- sheets[[i]]
      nm <- if (is.na(s$name) || !nzchar(s$name %||% "")) "(file contents)" else s$name
      shown <- if (s$n_rows > nrow(s$preview))
        sprintf("%d rows (first %d sent)", s$n_rows, nrow(s$preview))
      else sprintf("%d rows", s$n_rows)
      sprintf("%s: %s x %d cols, ~%s tokens", nm, shown, s$n_cols,
              format(s$est_tokens, big.mark = ","))
    }, character(1))
    choices <- setNames(as.character(seq_along(sheets)), labels)
    total <- sum(vapply(sheets, function(s) s$est_tokens, numeric(1)))
    tags$div(
      style = "margin: 6px 0 12px 0; padding: 10px 14px; background:#F1F8F4;
               border:1px solid #C8E6C9; border-radius:8px; font-size:0.88rem;",
      tags$div(style = "font-weight:600; margin-bottom:6px;",
               sprintf("%s: %d sheet%s read (~%s tokens in total). Untick reference or lookup sheets the AI does not need, then send.",
                       pu$name, length(sheets), if (length(sheets) == 1L) "" else "s",
                       format(total, big.mark = ","))),
      checkboxGroupInput("translator_sheets", label = NULL, choices = choices,
                         selected = as.character(seq_along(sheets)), width = "100%"),
      actionButton("translator_send_sheets", "Send to the AI (Step 1 of 3: explore)",
                   class = "btn-success", style = "font-size:0.85rem;"))
  })

  observeEvent(input$translator_send_sheets, {
    req(state$user_email)
    pu <- state$pending_upload
    if (is.null(pu)) return()
    idx <- suppressWarnings(as.integer(input$translator_sheets))
    idx <- idx[!is.na(idx) & idx >= 1L & idx <= length(pu$parsed$sheets)]
    if (length(idx) == 0L) {
      showNotification("Tick at least one sheet to send.", type = "warning", duration = 4)
      return()
    }
    parsed <- pu$parsed
    parsed$sheets <- parsed$sheets[idx]
    parsed$n_total_sheets <- length(idx)
    state$pending_upload <- NULL
    # Inline typing-indicator in the conversation while we wait for the
    # AI's first reply; cleared by translatorStreamStart.
    session$sendCustomMessage("translatorAppendTypingBubble", "")
    built <- .translator_build_upload_message(parsed, pu$name)
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user", content = built$content, display = built$display,
           # Server-injected text. The coverage scan skips messages that
           # carry a `source`, so the sub-category examples in the
           # exploration contract no longer count as "mentioned in chat".
           source = "server_upload", file_hash = pu$hash)
    .translator_persist(state)
    .translator_send(state, session, stage = "explore")
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
    .translator_persist(state)
    # 2026-06-12: text-trigger emission removed. Previously, phrases like
    # "produce the template" or "go ahead" routed directly to
    # .translator_force_template, which was firing emission on its own
    # mid-conversation and confusing the user. New rule: ONLY the green
    # "Produce template now" button starts emission. Every typed message
    # goes through the normal chat path, and the system prompt instructs
    # the AI to explicitly tell the user to click the button when it
    # thinks it has enough information.
    #
    # Three-dot typing indicator inline in the conversation while we
    # wait for the AI's first chunk. Cleared by translatorStreamStart
    # which wipes stream_target before painting the live AI bubble.
    session$sendCustomMessage("translatorAppendTypingBubble", "")
    .translator_send(state, session)
  })

  # ---- Reset conversation: wipe history + saved file -----------------------
  observeEvent(input$translator_reset, {
    req(state$user_email)
    state$messages           <- list()
    state$last_template_json <- NULL
    state$last_error         <- NULL
    # Drop any cached per-batch parts so a fresh conversation starts
    # with no resume state.
    state$batch_parts        <- list()
    state$pending_upload     <- NULL
    state$prompt_stale       <- FALSE
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
  # The green button is the ONLY emission trigger (typed phrases stopped
  # triggering on 2026-06-12; the detector was deleted on 2026-09-17).
  # Refused while the saved conversation predates the live prompt (plan B5).
  observeEvent(input$translator_force_template, {
    req(state$user_email)
    if (length(state$messages) < 2L) {
      showNotification(
        "Upload a file and answer the AI's clarifying questions before producing the template.",
        type = "warning", duration = 5)
      return()
    }
    if (isTRUE(state$prompt_stale)) {
      showNotification(
        "The IPCC defaults or the template changed since this conversation started. Upload your file again first, so the template is built from the current values.",
        type = "warning", duration = 8)
      return()
    }
    session$sendCustomMessage("translatorAppendInfoBubble",
      "Generating the full template now. A small inventory takes 1 to 3 minutes; a large one with several production systems takes 10 to 40 minutes, one production system at a time, and this panel stays busy throughout. The Download button appears when it finishes.")
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
      summary_label <- "Show structure / details"
      if (identical(m$role, "assistant")) {
        split <- .translator_split_visible_hidden(m$content, m$display,
                                                  payload = m$payload)
        visible <- split$visible
        hidden  <- split$hidden
        summary_label <- split$summary %||% summary_label
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
              summary_label),
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
    # 2026-09-17: sheet picker shown between parse and send (plan F8).
    uiOutput("translator_sheet_picker"),

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

# ---------------------------------------------------------------------------
# Helpers added 2026-09-17 (plan A, B, C, F)
# ---------------------------------------------------------------------------

# sha256 of a file's bytes; the key for the parse memo and the stamp.
.translator_file_hash <- function(path) {
  tryCatch(paste(as.character(openssl::sha256(file(path, "rb"))), collapse = ""),
           error = function(e) {
             con <- file(path, "rb"); on.exit(close(con))
             paste(as.character(openssl::sha256(readBin(con, "raw", file.info(path)$size))), collapse = "")
           })
}

# Parse memo (plan F7): one parse per distinct file per process, so a
# re-upload after Reset is instant and, more importantly, produces the same
# bytes for the model, which is what lets the prompt cache hit.
.TRANSLATOR_PARSE_MEMO <- new.env(parent = emptyenv())
.translator_read_upload_memo <- function(path, name) {
  h <- .translator_file_hash(path)
  key <- paste(h, tolower(tools::file_ext(name)), sep = "|")
  if (!is.null(.TRANSLATOR_PARSE_MEMO[[key]])) return(.TRANSLATOR_PARSE_MEMO[[key]])
  parsed <- .translator_read_upload(path, name)
  parsed$file_hash <- h
  for (i in seq_along(parsed$sheets)) {
    j <- .translator_table_to_json(parsed$sheets[[i]]$preview, sheet_name = parsed$sheets[[i]]$name)
    parsed$sheets[[i]]$json <- j
    parsed$sheets[[i]]$est_tokens <- as.integer(ceiling(nchar(j, type = "bytes") / 3.6))
  }
  # Keep at most a handful; each holds the sheet previews.
  if (length(ls(.TRANSLATOR_PARSE_MEMO)) >= 6L) rm(list = ls(.TRANSLATOR_PARSE_MEMO)[1], envir = .TRANSLATOR_PARSE_MEMO)
  .TRANSLATOR_PARSE_MEMO[[key]] <- parsed
  parsed
}

# Canonical spelling of a production-system label, for comparing the label
# the server asked for with the one the model echoed (plan A3): case,
# surrounding blanks and the separator characters are folded away.
.translator_norm_level <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_+|_+$", "", x)
}

# Region from the country name (plan A4). Used only when the model did not
# set region; the fallback is "global", never a continent the herd may not
# be on.
.translator_region_from_country <- function(country) {
  c0 <- tolower(trimws(as.character(country %||% "")))
  if (nzchar(c0) && exists("COUNTRY_TO_REGION") && c0 %in% names(COUNTRY_TO_REGION))
    return(unname(COUNTRY_TO_REGION[[c0]]))
  "global"
}

# Response memo for the deterministic tool calls (plan F6). Discovery and
# batch calls run at temperature 0 against a fixed prefix; an unchanged
# conversation re-emitted (the user clicks Produce twice, or reloads after
# a Stop) returns the stored reply instead of paying for it again. Keyed on
# the prompt, the messages and the tool block, so a changed default or a
# new clarification is a miss. Lives beside the conversation files, so it
# is as durable as they are (wiped with the container).
.translator_memo_path <- function(key) {
  file.path(.history_dir(), paste0("translator_memo_", substr(key, 1, 32), ".json"))
}
.translator_memo_call <- function(msgs, tools_sig, fn) {
  key <- tryCatch(.tp_sha256(c(jsonlite::toJSON(msgs, auto_unbox = TRUE), tools_sig)),
                  error = function(e) NULL)
  if (!is.null(key)) {
    p <- .translator_memo_path(key)
    if (file.exists(p)) {
      hit <- tryCatch(jsonlite::read_json(p, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(hit) && !is.null(hit$reply) && nzchar(hit$reply)) {
        message("translator: response memo hit for ", substr(key, 1, 12))
        return(list(reply = hit$reply, usage = list(prompt_tokens = 0L, completion_tokens = 0L,
                    cached_tokens = 0L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L,
                    total_tokens = 0L), model = hit$model %||% "memo", cost_usd = 0,
                    error = NULL, latency_sec = 0, memo_hit = TRUE))
      }
    }
  }
  resp <- fn()
  if (!is.null(key) && is.null(resp$error) && !is.null(resp$reply) && nzchar(resp$reply) &&
      .translator_template_json_parses(resp$reply)) {
    tryCatch(jsonlite::write_json(list(reply = resp$reply, model = resp$model,
                                       saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                                  .translator_memo_path(key), auto_unbox = TRUE),
             error = function(e) NULL)
  }
  resp
}
.translator_template_json_parses <- function(txt) {
  !is.null(tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL))
}

# What the one shared tool must carry in each mode (plan F1). The schema can
# no longer require different fields per mode, so the server checks.
.translator_validate_piece <- function(parsed, mode) {
  if (is.null(parsed)) return("the reply was not JSON")
  miss <- switch(mode,
    enumerate = setdiff(c("aggregation_levels", "inventory_metadata"), names(parsed)),
    batch     = setdiff(c("aggregation_level", "parameters", "parameter_timeseries"), names(parsed)),
    full      = setdiff(c("parameters"), names(parsed)),
    character(0))
  if (length(miss)) sprintf("the reply omitted %s", paste(miss, collapse = ", ")) else NULL
}

# Provenance stamp written into the workbook's Notes (plan B6).
.translator_stamp_text <- function(model = NULL) {
  ph <- tryCatch(substr(translator_system_prompt_hash(), 1, 8), error = function(e) "unknown")
  mh <- tryCatch(substr(translator_prompt_inputs_hash()$master_sha256, 1, 8), error = function(e) "unknown")
  av <- Sys.getenv("APP_VERSION", unset = "")
  sprintf("translator: app %s, prompt %s, master %s, model %s, %s",
          if (nzchar(av)) av else "dev", ph, mh, model %||% .ANTHROPIC_DEFAULT_MODEL,
          format(Sys.Date(), "%Y-%m-%d"))
}

# Build the Explore user message from a parsed upload (the sheets the user
# ticked). Returns list(content = what the model sees, display = what the
# user sees in their own bubble).
.translator_build_upload_message <- function(parsed, file_name) {
  sheet_json_objs <- lapply(parsed$sheets, function(s) {
    s$json %||% .translator_table_to_json(s$preview, sheet_name = s$name)
  })
  sheets_json <- paste0("[", paste(sheet_json_objs, collapse = ","), "]")
  # Compact per-sheet header block so the AI sees sheet dimensions up
  # front. Says explicitly when a sheet was cut at the row cap (plan C5).
  sheet_headers <- vapply(parsed$sheets, function(s) {
    sheet_label <- if (is.na(s$name) || !nzchar(s$name %||% ""))
      "(file contents)" else sprintf("Sheet \"%s\"", s$name)
    if (s$n_rows > nrow(s$preview))
      sprintf("- %s: %d rows × %d columns. ONLY THE FIRST %d ROWS ARE IN THE JSON; rows %d to %d were cut. Tell the user if they look needed.",
              sheet_label, s$n_rows, s$n_cols, nrow(s$preview), nrow(s$preview) + 1L, s$n_rows)
    else
      sprintf("- %s: %d rows × %d columns (all in the JSON)", sheet_label, s$n_rows, s$n_cols)
  }, character(1))
  # Server-side scan (plan C3): which parameter families appear anywhere in
  # the file, with the sheet and row of the first hit, so the model cannot
  # skip them and the user can cross-check.
  detected <- .translator_scan_param_labels(parsed$sheets)
  detect_block <- if (length(detected) == 0) "" else paste0(
    "## Parameter labels DETECTED IN THIS FILE (server-side scan)\n\n",
    "These IPCC parameters appear somewhere in the file (first hit shown as sheet!row). ",
    "Find them in the structured-JSON sheet objects below (look up the row by its ",
    "row-number key under `sheets[<sheet>].rows`) and map EVERY one. If you cannot ",
    "find the row a label refers to, ask before defaulting to IPCC values:\n\n",
    paste0("- ", detected, collapse = "\n"),
    "\n\nDo NOT substitute IPCC defaults for any parameter on this ",
    "list — the user's file has a value for it.\n\n---\n\n")
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
    "List every IPCC catalogue parameter that is NOT in the file. These will need IPCC defaults at emission time. Be exhaustive — ",
    paste(PARAM_CATALOGUE$parameter, collapse = " / "),
    ", minus what's in section B.\n\n",
    "### D. Ambiguities to ask the user\n\n",
    "Enumerate every ambiguity you'd like the user to resolve before ",
    "emission. Don't propose answers — just list the questions. ",
    "Common ambiguities to look for:\n",
    "- Sub-category vocabulary mapping (raw label → template controlled vocabulary)\n",
    "- Unit conversions (kg vs lb, % vs fraction, L vs kg of milk, °C vs °F)\n",
    "- Biological zeros (does the file's Milk row apply only to lactating cows?)\n",
    "- MMS code meanings (PIT → liquid slurry or solid storage?)\n",
    "- Breed disaggregation (Local vs Cross — treat together or split?)\n",
    "- Sheet purpose (is Sheet2 a separate dataset or a calc behind Sheet1?)\n",
    "- Per-sub-cat vs herd-wide allocations (MMS rows apply to everyone or per group?)\n\n",
    "End with a one-line prompt to the user: \"Please answer the section D questions, then click **Produce template now** when ready.\"\n\n",
    "---\n\n")
  file_block <- paste0(
    "## File contents (pre-parsed)\n\n",
    "Sheets in this file:\n",
    paste(sheet_headers, collapse = "\n"),
    "\n\nThe full sheet data is in the JSON object below. Use it as ",
    "your source of truth: `sheets[i].sheet` is the sheet name, ",
    "`sheets[i].headers` is the column header row, and ",
    "`sheets[i].rows[\"<excel_row_number>\"]` gives you each row of ",
    "data keyed by its actual Excel row number (row 1 = header, ",
    "data starts at row 2). NA cells are dropped from each row object.\n\n",
    "```json\n",
    "{\n  \"file\": \"", file_name, "\",\n  \"sheets\": ", sheets_json, "\n}\n",
    "```\n\n---\n\n")
  content <- sprintf(
    "I have uploaded a file (%s) with %d sheet%s.\n\n%s%s%s",
    file_name, parsed$n_total_sheets,
    if (parsed$n_total_sheets == 1L) "" else "s",
    exploration_block, detect_block, file_block)
  display <- if (parsed$n_total_sheets == 1L)
    sprintf("Uploaded %s (%d rows × %d columns sent). Step 1 of 3 — the AI will now explore your file and report what it found.",
            file_name, nrow(parsed$sheets[[1]]$preview), ncol(parsed$sheets[[1]]$preview))
  else
    sprintf("Uploaded %s (%d sheets sent: %s). Step 1 of 3 — the AI will now explore your file and report what it found.",
            file_name, parsed$n_total_sheets,
            paste(sapply(parsed$sheets, `[[`, "name"), collapse = ", "))
  list(content = content, display = display)
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
  # 2026-06-10 (Andy's 26-sub-cat Zambia case): bumped 200 → 1000.
  # A full Zambian inventory has 282+ rows in one sheet (26 sub-categories
  # × several production-system blocks). The 200-row cap silently cut off
  # the last 6+ sub-categories, and the AI confessed it could not see
  # row 282 when asked about an extensive-system heifer value. 1000 rows
  # comfortably fits the biggest realistic spreadsheets we expect; if a
  # file is genuinely bigger, the header line now says exactly which rows
  # were cut (n_rows is the TRUE sheet length since 2026-09-17, plan C5).
  ROW_CAP <- 1000L
  ext <- tolower(tools::file_ext(name))
  if (ext == "csv") {
    df <- .translator_read_csv_sniffed(path)
    return(list(
      kind   = "csv",
      sheets = list(list(name = NA_character_,
                         n_rows = nrow(df), n_cols = ncol(df),
                         preview = utils::head(df, ROW_CAP))),
      n_total_sheets = 1L
    ))
  }
  sheet_names <- readxl::excel_sheets(path)
  out <- list()
  for (s in sheet_names) {
    df <- tryCatch(readxl::read_excel(path, sheet = s), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0 || ncol(df) == 0) next
    # Drop sheets that have zero non-NA cells — pure empty placeholders.
    if (sum(!is.na(df)) == 0) next
    out[[length(out) + 1]] <- list(
      name    = s,
      n_rows  = nrow(df),
      n_cols  = ncol(df),
      preview = utils::head(df, ROW_CAP)
    )
  }
  if (length(out) == 0)
    stop("No readable sheet found in ", name)
  list(kind = "xlsx", sheets = out, n_total_sheets = length(out))
}

# CSV with the separator and decimal mark sniffed from the first lines
# (plan C4). Francophone exports use ';' with ',' decimals; read.csv's
# defaults collapsed such a file into one column.
.translator_read_csv_sniffed <- function(path) {
  head_lines <- tryCatch(readLines(path, n = 20L, warn = FALSE, encoding = "UTF-8"),
                         error = function(e) character(0))
  head_lines <- head_lines[nzchar(trimws(head_lines))]
  count <- function(ch) if (length(head_lines)) stats::median(lengths(regmatches(head_lines, gregexpr(ch, head_lines, fixed = TRUE)))) else 0
  n_semi <- count(";"); n_comma <- count(","); n_tab <- count("\t")
  sep <- if (n_semi > n_comma && n_semi >= n_tab) ";" else if (n_tab > n_comma) "\t" else ","
  # With ';' or tab as separator, a comma inside numbers is a decimal mark.
  dec <- if (sep != "," && any(grepl("[0-9],[0-9]", head_lines))) "," else "."
  enc <- if (any(vapply(head_lines, function(l) !validUTF8(l), logical(1)))) "latin1" else "UTF-8"
  utils::read.csv(path, sep = sep, dec = dec, stringsAsFactors = FALSE,
                  check.names = FALSE, fileEncoding = enc)
}

# Scan every sheet of the uploaded file for known parameter labels and
# return a deduplicated, human-readable list. Appended to the AI's first
# user message so the model has a structured ground-truth checklist
# even if the markdown-preview table truncates further down. Catches
# the failure mode where the AI silently skips DE / CP / Fat / Hours /
# MMS allocation because they sit further down a long sheet.
#
# 2026-09-17 (plan C3): the scan now covers EVERY column of every sheet, not
# the headers plus the first three columns, and matches the prose labels
# real files use ("Coefficients for Net Energy for Maintenance (Cfi)", "Bo,
# Maximum methane producing capacity", "Digestibility of feed (%)"). On the
# Zambia stress file the old patterns found 5 parameter families; the new
# ones find the manure coefficients as well. Each hit reports the sheet and
# Excel row of its first occurrence so the model and the user can go there.
.translator_scan_param_labels <- function(sheets) {
  patterns <- list(
    "N (population / head count)"     = c("^n$", "head_?count", "\\bpopulation", "cattle_?pop", "\\bnumber of (animals|cattle|head)", "\\beffectif"),
    "BW (live body weight, kg)"       = c("^bw$", "^lw$", "live_?weight", "live_?wt", "body_?weight", "\\bliveweight", "poids vif", "\\bweight\\b.*\\bkg"),
    "MW (mature weight, kg)"          = c("^mw$", "mature_?weight", "mature_?wt", "mature body", "poids adulte"),
    "WG (daily weight gain, kg/d)"    = c("^wg$", "^adg$", "weight_?gain", "daily_?gain", "\\bgain\\b.*\\bkg", "gain de poids"),
    "Milk (milk yield, kg/d)"         = c("^milk", "milk_?yield", "milk production", "^my\\b", "\\blait\\b", "my_?offtake"),
    "Fat (milk fat %)"                = c("^fat$", "milk_?fat", "fat content", "fat\\s*\\(", "mati[eè]re grasse"),
    "pct_pregnant (fraction)"         = c("%\\s*preg", "pct_?preg", "pregnan", "calving rate", "pct_?lactating", "gestant"),
    "DE (digestible energy %)"        = c("^de$", "^de\\s*(pct|%|\\()", "digestib", "digestible_?energy"),
    "CP (crude protein %)"            = c("^cp$", "^cp\\s*(pct|%|\\()", "crude_?protein", "diet\\s*cp", "prot[eé]ine brute"),
    "Ym (methane conversion %)"       = c("^ym\\b", "methane_?conv", "\\bym\\b.*(%|percent|factor)"),
    "Bo (methane producing capacity)" = c("^bo\\b", "maximum methane", "methane producing capacity", "\\bb0\\b"),
    "ASH (ash fraction)"              = c("^ash\\b", "ash content"),
    "UE (urinary energy fraction)"    = c("^ue\\b", "urinary energy"),
    "Cfi (maintenance coefficient)"   = c("\\bcfi\\b", "net energy for maintenance", "maintenance coefficient"),
    "Ca (activity coefficient)"       = c("\\bca\\b.*(activity|coefficient)", "coefficients? for activity", "activity coefficient"),
    "C (growth coefficient)"          = c("coefficients? for growth", "growth coefficient", "\\b_c\\b"),
    "hours (work hours / draught)"    = c("^hours?$", "work_?hours", "hours.*(work|day)", "draught|draft", "heures"),
    "Tw (winter temperature)"         = c("^tw\\b", "winter temp", "temp[eé]rature.*hiver"),
    "MMS allocation (manure mgmt %)"  = c("^mms\\b", "manure_?management", "manure management system", "syst[eè]me.*gestion", "manure_?system", "mms activity"),
    "MCF (methane conversion factor, manure)" = c("\\bmcf\\b", "methane conversion factor"),
    "EF3 (direct N2O EF, manure)"     = c("\\bef3\\b", "direct n2o", "emission factor for direct"),
    "Frac_GasMS (volatilisation)"     = c("frac_?gas", "volatilis", "volatiliz", "nh3 or nox"),
    "Frac_LeachMS (leaching)"         = c("frac_?leach", "leaching", "lixiviation"),
    "EF3_PRP (pasture N2O EF)"        = c("ef3_?prp", "pasture.*n2o", "range.*paddock"),
    "EF4 / EF5 (indirect N2O EFs)"    = c("\\bef4\\b", "\\bef5\\b", "indirect n2o")
  )
  found <- character(0); where <- character(0)
  for (sheet in sheets) {
    df <- sheet$preview
    if (is.null(df) || nrow(df) == 0) next
    sheet_label <- if (is.na(sheet$name) || !nzchar(sheet$name %||% "")) "(file)" else sheet$name
    # Header row (Excel row 1) then every cell of every column, remembering
    # the Excel row (data starts at row 2).
    cand <- data.frame(text = tolower(trimws(names(df))), row = 1L, stringsAsFactors = FALSE)
    for (col_idx in seq_len(ncol(df))) {
      v <- df[[col_idx]]
      if (is.numeric(v) || inherits(v, "Date") || inherits(v, "POSIXt")) next
      v <- as.character(v)
      ok <- !is.na(v) & nzchar(trimws(v)) & !grepl("^[-+]?[0-9.,eE ]+%?$", v)
      if (!any(ok)) next
      cand <- rbind(cand, data.frame(text = tolower(trimws(v[ok])),
                                     row = which(ok) + 1L, stringsAsFactors = FALSE))
    }
    if (nrow(cand) == 0) next
    for (pname in names(patterns)) {
      if (pname %in% found) next
      for (pat in patterns[[pname]]) {
        hit <- grepl(pat, cand$text, perl = TRUE)
        if (any(hit)) {
          found <- c(found, pname)
          where <- c(where, sprintf("%s!%d", sheet_label, cand$row[which(hit)[1]]))
          break
        }
      }
    }
  }
  if (length(found)) paste0(found, "  (first seen at ", where, ")") else found
}

# Render a small data.frame as a markdown table the LLM can read.
# DEPRECATED 2026-06-11: superseded by .translator_table_to_json() below.
# Kept for reference / fallback; no longer called from the upload handler.
.translator_table_to_md <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("(empty data)")
  hdr <- paste("|", paste(names(df), collapse = " | "), "|")
  sep <- paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|")
  # 2026-06-10: matches the 1000-row preview cap in .translator_read_upload.
  # Truncating here below the read cap would silently drop rows the AI was
  # meant to see — defeats the point of the higher preview limit.
  rows <- vapply(seq_len(min(nrow(df), 1000L)), function(i) {
    paste("|", paste(sapply(df[i, ], function(x) {
      v <- if (is.na(x)) "" else as.character(x)
      gsub("\\|", "/", v)
    }), collapse = " | "), "|")
  }, character(1))
  paste(c(hdr, sep, rows), collapse = "\n")
}

# Render a sheet as a structured JSON object the LLM can navigate by
# (sheet, row, column). Replaces the markdown table because Andy's Zambia
# inventory (26 sub-categories) was losing rows in the flat markdown
# representation — the model couldn't reliably look up a specific row by
# number once the sheet exceeded ~30 rows.
#
# Output shape (one sheet):
#
#   {
#     "sheet": "Sheet1",
#     "n_rows": 45,
#     "n_cols": 38,
#     "headers": ["Parameter", "Sub-category", ...],
#     "rows": {
#       "2": {"Parameter": "BW", "Sub-category": "Cows", "Cows Mean": 312.78, ...},
#       "3": {...}
#     }
#   }
#
# Row keys are the Excel row numbers (starting at 2 because row 1 is the
# header that became `headers`). NA cells are dropped from each row object
# to keep the JSON compact and the meaningful values visible. The
# upload-handler call (around chat_ui.R:200) wraps the per-sheet JSON in a
# single ```json``` fenced block under the EXPLORATION instruction.
#
# 2026-06-11: 1000-row cap matches .translator_read_upload's ROW_CAP so we
# never silently truncate below what the reader produced.
.translator_table_to_json <- function(df, sheet_name = NA_character_) {
  if (is.null(df) || nrow(df) == 0) {
    return(jsonlite::toJSON(list(
      sheet = sheet_name,
      n_rows = 0L, n_cols = 0L,
      headers = character(0),
      rows = setNames(list(), character(0))
    ), auto_unbox = TRUE, na = "null", pretty = FALSE))
  }
  headers <- names(df)
  n <- min(nrow(df), 1000L)
  # Row keys = Excel row numbers (header is row 1, data starts at row 2).
  # Drop NA cells so the JSON stays compact and only the meaningful values
  # are in front of the model.
  row_keys <- as.character(seq_len(n) + 1L)  # +1 because row 1 = headers
  row_vals <- lapply(seq_len(n), function(i) {
    cells <- as.list(df[i, , drop = FALSE])
    # Convert each cell to a scalar (jsonlite would otherwise wrap
    # length-1 atomic vectors as JSON arrays).
    cells <- lapply(cells, function(x) if (length(x) == 1) unname(x) else x)
    keep <- vapply(cells, function(x)
      !(length(x) == 0 || (length(x) == 1 && (is.na(x) ||
        (is.character(x) && !nzchar(x))))), logical(1))
    cells[keep]
  })
  # Drop fully-empty rows (every cell NA/blank): they would serialise as
  # "<row>": {} and carry zero information, yet this prefix is paid on every
  # cold cache-write. Keep the Excel row-number keys for the surviving rows
  # (sparse keys are already the design — the model looks rows up by number
  # rather than iterating, so omitting blanks changes nothing it relies on).
  nonempty <- vapply(row_vals, function(x) length(x) > 0L, logical(1))
  rows <- setNames(row_vals[nonempty], row_keys[nonempty])
  jsonlite::toJSON(list(
    sheet = sheet_name,
    n_rows = nrow(df),
    n_cols = ncol(df),
    headers = headers,
    rows = rows
  ), auto_unbox = TRUE, na = "null", pretty = FALSE)
}

# Make the API call from the current message stack, stream the reply
# into the browser, then append it to the chat history. All this state
# lives on `state`. Requires `session` so the streaming chunks can be
# pushed to the active browser tab via sendCustomMessage.
.translator_send <- function(state, session, stage = "clarify") {
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
    # With MONTHLY_BUDGET_CAP_USD set to a sentinel "no cap" value
    # (0/none/unlimited/unset), this branch never fires. Kept as a
    # safety net for the case where an administrator explicitly sets
    # a numeric cap and wants the in-app gate.
    state$last_error <- paste0(
      "The AI translator is temporarily unavailable. ",
      "We've been notified and will restore service shortly — ",
      "please try again later or contact the administrator.")
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

  # The tool block rides along on every chat turn with tool_choice = none
  # (plan F1): the prompt-cache prefix is tools -> system -> messages, so a
  # chat turn without the tool and an emission call with it can never share
  # a cache entry. The model cannot call the tool here; rule 9 tells it not
  # to try.
  resp <- anthropic_chat_stream(
    msgs,
    on_chunk = function(text) {
      session$sendCustomMessage("translatorStreamChunk", text)
    },
    tools       = anthropic_translator_tools(),
    tool_choice = .ANTHROPIC_TOOL_CHOICE_NONE
  )

  if (!is.null(resp$error)) {
    state$last_error <- resp$error
    # If we got at least some text before the error, still save it.
    if (!is.null(resp$reply) && nzchar(resp$reply)) {
      err_display <- .translator_extract_numbered_questions(resp$reply) %||%
                     resp$reply
      state$messages[[length(state$messages) + 1]] <-
        list(role = "assistant", content = resp$reply, display = err_display)
    }
    return()
  }

  # Log the spend — Anthropic prompt caching has 90% off on cache reads
  # and a 25% surcharge on cache writes (first turn only).
  # See R/anthropic_client.R::anthropic_cost_usd.
  .translator_log_usage(state, resp, stage = stage,
                        expect_warm = !identical(stage, "explore"))

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
  #
  # Numbered-question display filter: when the AI's reply is dominated
  # by a numbered list (e.g. "Section D — Ambiguities" with 4-10
  # clarification questions wrapped in 200 words of preamble +
  # postamble), set display to just the numbered items. The full reply
  # stays in `content` so the chat-bubble expander surfaces it on
  # demand.
  display_text <- .translator_extract_numbered_questions(resp$reply) %||%
                  resp$reply
  state$messages[[length(state$messages) + 1]] <-
    list(role = "assistant",
          content = resp$reply,
          display = display_text)

  # If a valid template-ready block came through in this reply, post a
  # separate small AI message pointing the user at the green Download
  # button. The previous reply mixed natural-language with the JSON, so
  # the user can miss the "click to download" cue — this dedicated
  # message is the clear next step.
  if (template_just_ready) .translator_append_download_hint(state)

  # Persist so a refresh / reload resumes where we left off.
  .translator_persist(state)
}

# One place to log a call's usage (plan F11). `stage` names the pipeline
# step; `expect_warm` marks stages that should be reading a warm cache.
.translator_log_usage <- function(state, resp, stage, expect_warm = FALSE) {
  if (is.null(resp) || is.null(resp$usage)) return(invisible(NULL))
  usage_log_append(
    user_email            = state$user_email,
    model                 = resp$model,
    prompt_tokens         = resp$usage$prompt_tokens,
    completion_tokens     = resp$usage$completion_tokens,
    cached_tokens         = resp$usage$cached_tokens %||% 0L,
    cache_write_tokens    = resp$usage$cache_write_tokens %||% 0L,
    cache_write_1h_tokens = resp$usage$cache_write_1h_tokens %||% 0L,
    cost_usd              = resp$cost_usd,
    latency_sec           = resp$latency_sec,
    stage                 = stage,
    expect_warm           = expect_warm)
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
# whether it thinks it has enough info.
#
# 2026-06-11 (Lolita's full Zambia run): this is now a DISPATCHER. It
# does a small Stage 1 discovery call to enumerate the aggregation_level
# labels in the conversation; for ≤2 aggregation_levels it hands off to
# .translator_force_template_single() (the previous monolithic path,
# unchanged); for >2 it fires one tool_use call per aggregation_level,
# merges the per-batch JSON pieces, and writes one .xlsx. The
# monolithic path stays in place because its three retry loops
# (parse / coverage / defaults-only) are correct on small inventories
# and would add unnecessary complexity to split per-batch.
#
# Why: Sonnet 4.6's tool_use input_json_delta streaming runs at ~30-40
# tokens/sec via the Anthropic API. A 27-sub-cat × 25-param emission =
# ~34K output tokens = >900s wall-clock, which exceeds the Shiny
# WebSocket heartbeat tolerance and breaks the session. Splitting into
# 5 per-aggregation-level calls of ~6K tokens each (~60-90s each)
# keeps every individual call well inside any timeout.
.translator_force_template <- function(state, session) {
  state$pending <- TRUE
  state$last_error <- NULL
  on.exit({
    state$pending <- FALSE
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
              error = function(e) NULL)
  })

  if (budget_would_exceed()) {
    state$last_error <- paste0(
      "The AI translator is temporarily unavailable. ",
      "We've been notified and will restore service shortly — ",
      "please try again later or contact the administrator.")
    return()
  }

  system_prompt <- tryCatch(assemble_translator_system_prompt(),
                             error = function(e) NULL)
  if (is.null(system_prompt)) {
    state$last_error <- "Couldn't load the translator instructions."
    return()
  }
  tools_sig <- tryCatch(jsonlite::toJSON(anthropic_translator_tools(), auto_unbox = TRUE),
                        error = function(e) "tools")

  # Stream-aware progress callback shared across discovery + batch calls.
  total_chars <- 0L
  on_chunk_cb <- function(text) {
    total_chars <<- total_chars + nchar(text)
    tryCatch(session$sendCustomMessage("translatorProgressTick",
                                         list(chars = total_chars)),
              error = function(e) NULL)
  }
  # Keep-alive for tool_use streams (input_json_delta events): the text
  # path never fires during emission, so this keeps the typing bubble alive.
  on_tick_cb <- function() {
    tryCatch(session$sendCustomMessage("translatorStreamTick", ""),
              error = function(e) NULL)
  }
  info <- function(txt) tryCatch(session$sendCustomMessage("translatorAppendInfoBubble", txt),
                                 error = function(e) NULL)

  # ---- Stage 1: discovery call ------------------------------------------
  # Cheap (~200 output tokens). mode = enumerate. Memoised on the exact
  # conversation (plan F6): a second click on Produce with nothing changed
  # costs nothing.
  info("Analysing your inventory structure...")
  discovery_request <- paste(
    "STEP 3 OF 3 — EMISSION SETUP. Before producing the filled template,",
    "the in-app handler needs you to enumerate two things from this",
    "conversation:",
    "",
    "  1. The distinct aggregation_level labels for this inventory, in",
    "     snake_case, lowercase (e.g. \"commercial_dairy\",",
    "     \"emergent_dairy\", \"commercial_beef\", \"emergent_beef\",",
    "     \"extensive_trad\"). One entry per production system the user",
    "     has confirmed.",
    "  2. The inventory_metadata object: country, region (the continent,",
    "     from the country), year (integer), species (cattle_dairy /",
    "     cattle_non_dairy / cattle_mixed), ipcc_version (2006 /",
    "     2019_refinement), prepared_by (string), notes (string — include",
    "     any caveats from the conversation).",
    "",
    "Call the emit_inventory_piece tool exactly once with mode = 'enumerate'.",
    "Do NOT emit any parameters, manure_management, or time-series rows",
    "here — those come in per-aggregation-level follow-up calls.",
    sep = "\n")
  discovery_msgs <- anthropic_build_messages(
    system_prompt, history = state$messages,
    new_user_message = discovery_request)
  enum_resp <- .translator_memo_call(discovery_msgs, tools_sig, function()
    anthropic_chat_enumerate_aggregation_levels(
      discovery_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb))

  if (!is.null(enum_resp$error)) {
    # Discovery itself failed — fall back to the monolithic path.
    message("translator: discovery call failed (", enum_resp$error,
            "), falling back to monolithic emission")
    .translator_force_template_single(state, session)
    return()
  }
  if (!isTRUE(enum_resp$memo_hit))
    .translator_log_usage(state, enum_resp, stage = "enumerate", expect_warm = TRUE)

  enum_parsed <- tryCatch(
    jsonlite::fromJSON(enum_resp$reply, simplifyVector = TRUE),
    error = function(e) NULL)
  bad <- .translator_validate_piece(enum_parsed, "enumerate")
  if (!is.null(bad)) {
    message("translator: discovery reply incomplete (", bad, "); using single-call path")
    .translator_force_template_single(state, session)
    return()
  }
  # Distinct, non-blank labels (plan C7): a duplicate would have re-used
  # the cached part and doubled every row; a blank would have keyed the
  # cache on "".
  agg_levels <- unique(trimws(as.character(enum_parsed$aggregation_levels)))
  agg_levels <- agg_levels[!is.na(agg_levels) & nzchar(agg_levels)]
  inventory_metadata <- enum_parsed$inventory_metadata

  # Decision: fall back to the monolithic path when batching wouldn't
  # buy us anything (small inventories, or empty enumeration).
  if (length(agg_levels) <= 2L) {
    message(sprintf("translator: discovery returned %d aggregation_level(s); using single-call path",
                     length(agg_levels)))
    .translator_force_template_single(state, session)
    return()
  }

  # ---- Stage 2: per-aggregation-level batch emission ---------------------
  # state$batch_parts holds parts that a PREVIOUS merge validated (plan
  # A3); the memo (plan F6) covers the "same call, same answer" case. Both
  # survive a Stop, because the parts are persisted with the conversation
  # (plan F5) and the memo is on disk.
  cached_levels <- intersect(agg_levels, names(state$batch_parts))
  fresh_levels  <- setdiff(agg_levels, cached_levels)
  if (length(cached_levels) > 0)
    message(sprintf("translator: reusing %d validated batch(es): %s",
                     length(cached_levels), paste(cached_levels, collapse = ", ")))
  message(sprintf("translator: dispatching %d force-template call(s): %s",
                   length(fresh_levels), paste(fresh_levels, collapse = ", ")))

  # Did the user upload a file with values? Drives the per-batch
  # defaults-only check (plan C1).
  file_was_uploaded <- any(vapply(state$messages, function(m)
    identical(m$source, "server_upload") ||
      grepl("Parameter labels DETECTED IN THIS FILE", m$content %||% "", fixed = TRUE),
    logical(1)))
  count_user_rows <- function(pj) {
    if (is.null(pj) || !is.data.frame(pj$parameters)) return(0L)
    ds <- pj$parameters$data_source
    if (is.null(ds)) return(0L)
    sum(grepl("^user[_ ]?(file|chat)$", ds, ignore.case = TRUE), na.rm = TRUE)
  }

  parts <- list()
  for (i in seq_along(agg_levels)) {
    level <- agg_levels[i]

    if (!is.null(state$batch_parts[[level]])) {
      info(sprintf("Reusing %d of %d: %s (validated on a previous attempt)...",
                   i, length(agg_levels), level))
      parts[[i]] <- state$batch_parts[[level]]
      next
    }

    info(sprintf("Processing %d of %d: %s...", i, length(agg_levels), level))
    total_chars <- 0L

    batch_nudge <- sprintf(paste(
      "STEP 3 OF 3 — BATCH %d OF %d (aggregation_level = '%s').",
      "",
      "Emit ONLY the parameters, manure_management, and",
      "parameter_timeseries rows for aggregation_level = '%s'. Do NOT",
      "include rows for any other aggregation_level. Do NOT emit",
      "inventory_metadata (the server has it from the discovery call).",
      "",
      "Call the emit_inventory_piece tool exactly once with mode = 'batch'.",
      "Set its `aggregation_level` field to '%s', spelled exactly like",
      "that, so the server can verify no cross-contamination at merge",
      "time. Put the same label on every row.",
      "",
      "parameter_timeseries is REQUIRED in this call. If the source file",
      "has multi-year activity data for '%s' (e.g. population counts,",
      "milk yield, body weight by year), you MUST emit one",
      "parameter_timeseries row per (sub_category, year). If the file is a",
      "single-year snapshot, emit one row per sub_category for the",
      "inventory year. Return an empty array [] only if the file genuinely",
      "has no activity-data fields at all.",
      "",
      "Within those year rows, fill ONLY the parameter columns that",
      "CHANGE across years. Leave a column blank wherever its value",
      "is the same in every year — that constant value is already on",
      "the Parameters sheet, and the app's correlation step discards",
      "flat (zero-variance) series, so repeating it adds cost with no",
      "effect. Keep the year rows; carry only the columns with real",
      "year-over-year movement.",
      "",
      "All other emission rules from the system prompt still apply:",
      "source-of-truth hierarchy (user_file > user_chat >",
      "ipcc_default), data_source on every row, asymmetric bounds where",
      "the file provides them, %d parameters per sub-category, biological",
      "zeros with distribution='constant'.",
      sep = "\n"),
      i, length(agg_levels), level, level, level, level, nrow(PARAM_CATALOGUE))
    batch_msgs <- anthropic_build_messages(
      system_prompt, history = state$messages,
      new_user_message = batch_nudge)
    batch_resp <- .translator_memo_call(batch_msgs, tools_sig, function()
      anthropic_chat_batch_template_force(
        batch_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb))

    if (!is.null(batch_resp$error)) {
      state$last_error <- sprintf(
        "Batch %d of %d (%s) failed: %s. Click 'Produce template now' to retry — the %d batch(es) that already succeeded are kept and won't be re-billed.",
        i, length(agg_levels), level, batch_resp$error, length(state$batch_parts))
      return()
    }
    if (!isTRUE(batch_resp$memo_hit))
      .translator_log_usage(state, batch_resp, stage = "batch", expect_warm = TRUE)

    batch_parsed <- tryCatch(
      jsonlite::fromJSON(batch_resp$reply, simplifyVector = TRUE),
      error = function(e) NULL)
    bad <- .translator_validate_piece(batch_parsed, "batch")
    if (!is.null(bad)) {
      state$last_error <- sprintf(
        "Batch %d (%s) came back incomplete (%s). Click 'Produce template now' to retry — the %d batch(es) that already succeeded are kept and won't be re-billed.",
        i, level, bad, length(state$batch_parts))
      return()
    }

    # Per-batch defaults-only check (plan C1): a file was uploaded, this
    # level's rows carry no user_file / user_chat provenance at all, so the
    # model has fallen back to the catalogue for a whole production system.
    # One retry with the rejection message; only the nudge changes, so the
    # prefix is a cache read.
    if (file_was_uploaded && count_user_rows(batch_parsed) == 0L &&
        is.data.frame(batch_parsed$parameters) && nrow(batch_parsed$parameters) > 0) {
      message("translator: batch '", level, "' has ZERO user_file rows; retrying once")
      info(sprintf("Batch %s came back with catalogue defaults only; asking the AI to use the file values...", level))
      retry_msgs <- c(batch_msgs, list(list(role = "user", content = paste0(
        "REJECTED — every parameters row you emitted for '", level, "' is tagged ",
        "data_source = 'ipcc_default' or lacks the tag, yet the uploaded file ",
        "carries values for this production system. Re-emit the batch for '",
        level, "' now: for every parameter present in the file use the file's ",
        "value with data_source = 'user_file' (and its bounds if given), use ",
        "catalogue defaults ONLY for parameters the file does not supply, and ",
        "biological_zero where it applies. Same tool, mode = 'batch', same ",
        "aggregation_level."))))
      retry_resp <- anthropic_chat_batch_template_force(
        retry_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb)
      if (is.null(retry_resp$error)) {
        .translator_log_usage(state, retry_resp, stage = "retry_defaults_only", expect_warm = TRUE)
        rp <- tryCatch(jsonlite::fromJSON(retry_resp$reply, simplifyVector = TRUE), error = function(e) NULL)
        if (is.null(.translator_validate_piece(rp, "batch")) && count_user_rows(rp) > 0L)
          batch_parsed <- rp
      }
    }

    batch_parsed$.requested_aggregation_level <- level
    parts[[i]] <- batch_parsed
  }

  # ---- Stage 3: merge + validate + store --------------------------------
  info("Assembling final template...")
  merged <- .translator_merge_batches(inventory_metadata, parts, agg_levels)
  merge_warnings <- merged$warnings %||% character(0)
  merged$warnings <- NULL

  # Species strip and manure coverage on the MERGED result (plan C2); the
  # monolithic path had these, the batched path did not.
  species <- .translator_scalar(merged$inventory_metadata$species %||% NA)
  if (is.data.frame(merged$parameters) && !is.na(species)) {
    drop_sc <- if (identical(species, "cattle_non_dairy")) "dairy_cows"
               else if (identical(species, "cattle_dairy")) .translator_non_dairy_subcats()
               else character(0)
    drop_sc <- intersect(drop_sc, unique(merged$parameters$sub_category))
    if (length(drop_sc)) {
      message("translator: stripping sub-cats incompatible with species=", species, ": ",
              paste(drop_sc, collapse = ", "))
      merged$parameters <- merged$parameters[!merged$parameters$sub_category %in% drop_sc, , drop = FALSE]
      if (is.data.frame(merged$manure_management))
        merged$manure_management <-
          merged$manure_management[!merged$manure_management$sub_category %in% drop_sc, , drop = FALSE]
    }
  }
  if (is.data.frame(merged$parameters)) {
    key_p <- unique(paste(merged$parameters$aggregation_level, merged$parameters$sub_category))
    key_m <- if (is.data.frame(merged$manure_management))
      unique(paste(merged$manure_management$aggregation_level, merged$manure_management$sub_category)) else character(0)
    miss_mm <- setdiff(key_p, key_m)
    if (length(miss_mm) && length(key_m))
      merge_warnings <- c(merge_warnings, sprintf(
        "Manure_Management has no rows for %d group(s): %s. Their manure CH4 and N2O will be zero unless you add the rows.",
        length(miss_mm), paste(utils::head(miss_mm, 6), collapse = "; ")))
  }

  merged$.model <- enum_resp$model
  merged_json <- jsonlite::toJSON(merged, auto_unbox = TRUE, na = "null", null = "null",
                                  dataframe = "rows", digits = NA)

  if (!.translator_template_is_well_formed(merged_json)) {
    # Nothing is cached from a failed merge (plan A3): the parts that
    # produced it must not be replayed on the retry.
    state$batch_parts <- list()
    .translator_persist(state)
    state$last_error <- paste(
      "Merged template failed the well-formedness check: the batches",
      "returned JSON but the merge produced an empty parameters array.",
      if (length(merge_warnings)) paste(merge_warnings, collapse = " ") else "",
      "Click 'Produce template now' to retry.")
    return()
  }

  # Validated: cache every part for a later retry (plan A3, F5).
  for (p in parts) if (!is.null(p$.requested_aggregation_level))
    state$batch_parts[[p$.requested_aggregation_level]] <- p

  state$last_template_json <- merged_json
  state$last_error <- if (length(merge_warnings)) paste(merge_warnings, collapse = " ") else NULL

  n_params <- if (is.data.frame(merged$parameters)) nrow(merged$parameters) else 0L
  n_mms <- if (is.data.frame(merged$manure_management)) nrow(merged$manure_management) else 0L
  n_ts <- if (is.data.frame(merged$parameter_timeseries)) nrow(merged$parameter_timeseries) else 0L
  if (n_ts == 0L && length(agg_levels) >= 2L) {
    info(paste("Heads up: the AI emitted 0 time-series rows. If your source",
               "file has multi-year activity data, this means the AI didn't",
               "extract it. The downloaded template will still work but the",
               "calculator won't be able to run correlation-based",
               "uncertainty modes. Click 'Produce template now' to retry —",
               "the batches that already succeeded won't be re-billed."))
  }
  download_hint <- sprintf(paste(
    "Template ready. Emitted %d parameter rows, %d manure_management",
    "rows, and %d time-series rows across %d aggregation_levels (%s).",
    "Click the green Download button below to save the .xlsx, then",
    "upload it on the 1. Data Input tab.",
    "\n\nNote on defaults: any parameter your file did not supply is filled",
    "with the IPCC default for that animal sub-category and flagged as",
    "'ipcc_default' in the data_source column. Manure MCF values are the",
    "one exception to sub-category matching: they depend on climate zone,",
    "which the template does not yet record, so a gap-filled MCF assumes a",
    "TROPICAL zone (IPCC Table 10.17). Check the MCF_pct column in the",
    "Manure_Management sheet and edit it if your inventory is temperate or",
    "boreal."),
    n_params, n_mms, n_ts, length(agg_levels),
    paste(agg_levels, collapse = ", "))
  state$messages[[length(state$messages) + 1L]] <-
    list(role = "assistant", content = download_hint, display = download_hint)
  # The merge succeeded, so the parts are no longer needed for a retry;
  # keep them anyway until the next upload or Reset (a re-run after a
  # clarification builds new messages, so the memo misses and the batch is
  # re-emitted from the new transcript; the cache is keyed by level only
  # as a resume aid, and cleared when the conversation changes shape).
  .translator_persist(state)
}

# Legacy single-call force-template path. Used by .translator_force_template()
# above when the discovery stage returns ≤2 aggregation_levels (or fails).
# The three retry loops (parse / coverage / defaults-only) and the sub-
# category strip post-processing are correct on small inventories — kept
# unchanged here.
.translator_force_template_single <- function(state, session) {
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
    # With MONTHLY_BUDGET_CAP_USD set to a sentinel "no cap" value
    # (0/none/unlimited/unset), this branch never fires. Kept as a
    # safety net for the case where an administrator explicitly sets
    # a numeric cap and wants the in-app gate.
    state$last_error <- paste0(
      "The AI translator is temporarily unavailable. ",
      "We've been notified and will restore service shortly — ",
      "please try again later or contact the administrator.")
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
    "   Call the emit_inventory_piece tool exactly once with mode = 'full'.",
    "",
    "2. SUB-CATEGORIES. Emit EXACTLY the sub-categories the user mapped",
    sprintf("   in chat — not the canonical %d from the catalogue. If the user",
            length(.translator_subcategory_vocab())),
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
    sprintf("4. For each sub-category, fill ALL %d parameters from the IPCC", nrow(PARAM_CATALOGUE)),
    paste0("   catalogue (", paste(PARAM_CATALOGUE$parameter, collapse = ", "), ")"),
    "   — but honour rule 1: user-supplied values OVERRIDE defaults.",
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
  .translator_log_usage(state, resp, stage = "full", expect_warm = TRUE)

  if (!.translator_template_is_well_formed(resp$reply)) {
    # Both attempts produced unparseable / incomplete JSON. Don't set
    # last_template_json — the download button stays hidden, so the user
    # never gets the malformed .json file with the warning toast.
    # Diagnostic hint: if completion_tokens is near the 64K tool-output
    # ceiling, the response was almost certainly truncated.
    near_cap <- (resp$usage$completion_tokens %||% 0L) >= 60000L
    hint <- if (near_cap)
      paste0(" The response hit the output-size ceiling (~", resp$usage$completion_tokens,
             " tokens): the inventory is too large for one response. ",
             "Reset the conversation and translate the dairy sub-categories ",
             "first, then start a new conversation for the beef ones (or ",
             "vice versa). The two .xlsx files can be merged by hand afterwards.")
    else
      " Click 'Produce template now' again — this is sometimes a transient AI-service hiccup."
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
    history_subcats <- setdiff(history_subcats, .translator_non_dairy_subcats())
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
      .translator_log_usage(state, resp2, stage = "retry_coverage", expect_warm = TRUE)
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
      .translator_log_usage(state, resp_v, stage = "retry_defaults_only", expect_warm = TRUE)
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
  NON_DAIRY_SC <- .translator_non_dairy_subcats()
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

  # Record the model that produced it, for the workbook stamp (plan B6).
  parsed_stamp <- tryCatch(jsonlite::fromJSON(resp$reply, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.null(parsed_stamp)) {
    parsed_stamp$.model <- resp$model
    resp$reply <- jsonlite::toJSON(parsed_stamp, auto_unbox = TRUE, na = "null",
                                   null = "null", dataframe = "rows", digits = NA)
  }
  state$last_template_json <- resp$reply
  # Two messages: a short one whose `payload` carries the raw JSON for the
  # expander (kept OUT of `content`, so it is never re-sent to the API on
  # later turns, plan C6), and a separate guidance bubble pointing at the
  # green Download button.
  state$messages[[length(state$messages) + 1]] <-
    list(role    = "assistant",
         content = sprintf("Template generated: %d parameter rows, %d manure rows.",
                           if (is.data.frame(parsed_check$parameters)) nrow(parsed_check$parameters) else 0L,
                           if (is.data.frame(parsed_check$manure_management)) nrow(parsed_check$manure_management) else 0L),
         display = "Template generated.",
         payload = resp$reply)
  .translator_append_download_hint(state)
  .translator_persist(state)
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

  # Run the official writer under a calling handler so a thrown error
  # captures the FULL call stack (R function names + line numbers) into
  # shinyapps.io logs. The previous tryCatch only logged
  # conditionMessage(), which on the Zambia run produced just "no such
  # index at level 1" with no clue where it came from — local repros
  # of the same input data succeeded. The withCallingHandlers below
  # snapshots sys.calls() at the throw site BEFORE control unwinds to
  # the tryCatch's error handler, so the next failure pinpoints the
  # exact line. Kept in permanently — silent on the happy path,
  # informative on regression.
  writer_trace <- NULL
  ok <- tryCatch(
    withCallingHandlers(
      { .translator_write_official_template(parsed, file_path); TRUE },
      error = function(e) {
        # Capture the active call stack at the throw site. sys.calls()
        # returns the deparsed chain; we drop the noisy outermost
        # frames (tryCatch/withCallingHandlers/this handler) and keep
        # the innermost ~25 frames where the actual failure lives.
        cs <- sys.calls()
        depth <- length(cs)
        keep <- max(1L, depth - 25L):depth
        writer_trace <<- paste(vapply(cs[keep], function(call)
          paste(deparse(call, nlines = 2L), collapse = " "),
          character(1)), collapse = "\n  > ")
      }
    ),
    error = function(e) {
      message("translator: official-template write failed: ",
              conditionMessage(e),
              " — falling back to simple xlsx.\n",
              "Writer call stack (innermost last):\n  > ",
              writer_trace %||% "(no stack captured)")
      FALSE
    }
  )
  if (!ok) .translator_write_simple_xlsx(parsed, file_path)
  invisible(NULL)
}

# Primary writer — overlays AI values onto the official blank template.
.translator_write_official_template <- function(parsed, file_path) {
  if (!exists("generate_template_openxlsx") || !exists("PARAM_CATALOGUE"))
    stop("template-generation helpers not available")

  # Defense-in-depth: if the merge produced list-of-records (heterogeneous
  # schema across batches), coerce to data.frames here too — the writer's
  # is.data.frame() gates would otherwise drop those sheets silently.
  parsed$parameters           <- .translator_records_to_df(parsed$parameters)
  parsed$manure_management    <- .translator_records_to_df(parsed$manure_management)
  parsed$parameter_timeseries <- .translator_records_to_df(parsed$parameter_timeseries)

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
    val <- .translator_scalar(val)
    if (is.na(val) || (is.character(val) && !nzchar(val))) return()
    openxlsx::writeData(wb, "Inventory_Metadata", val,
                        startRow = row, startCol = 3, colNames = FALSE)
  }
  country <- .translator_scalar(md$country %||% md$country_region)
  # Region (plan A4): the tool schema now asks for it; when absent, derive
  # it from the country, and fall back to "global", never to a continent.
  # Every translator workbook used to be stamped "africa" here.
  region <- .translator_scalar(md$region %||% md$continental_region)
  if (is.na(region) || !nzchar(as.character(region)))
    region <- .translator_region_from_country(country)
  # Provenance stamp (plan B6): app version, prompt hash, master hash,
  # model and date, appended to whatever notes the model supplied.
  stamp <- .translator_stamp_text(parsed$.model)
  prior_notes <- .translator_scalar(md$notes)
  md$notes <- if (is.na(prior_notes) || !nzchar(as.character(prior_notes))) stamp
              else paste(as.character(prior_notes), stamp, sep = " | ")
  .put_meta(2, country)
  .put_meta(3, region)
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
    # Fill the key columns ROW BY ROW (plan A2). The previous code applied
    # the NA-aware `%||%` to the whole column, which replaced every level
    # with "all" whenever the FIRST row was blank, collapsing distinct
    # production systems onto one key so that first-match-wins silently
    # dropped the others. A blank cattle_type follows the sub-category.
    fill_col <- function(v, default) {
      v <- as.character(v)
      bad <- is.na(v) | !nzchar(trimws(v))
      v[bad] <- default[bad]
      v
    }
    if (!"cattle_type" %in% names(params)) params$cattle_type <- NA_character_
    if (!"aggregation_level" %in% names(params)) params$aggregation_level <- NA_character_
    params$cattle_type <- fill_col(params$cattle_type,
      ifelse(params$sub_category == "dairy_cows", "dairy", "non_dairy"))
    params$aggregation_level <- fill_col(params$aggregation_level, rep("all", nrow(params)))
    sub_keys <- unique(paste(params$cattle_type, params$aggregation_level,
                             params$sub_category, sep = "||"))

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
        # Find AI's row matching this (cattle_type, agg_level, sub_cat,
        # parameter). Earlier this mask only filtered on
        # (sub_category, parameter) — which silently contaminated rows
        # whenever the same sub_category code appeared in multiple
        # aggregation_levels (e.g. `dairy_cows` in both commercial_dairy
        # and emergent_dairy; `other_cows` in all three beef systems).
        # The first-match-wins behaviour wrote commercial_dairy values
        # into emergent_dairy's rows and commercial_beef values into
        # both emergent_beef and extensive_trad. Identified 2026-06-15
        # in QA against the Zambia source file: 9/56 spot-checked
        # values were contaminated.
        mask <- params$sub_category == sub_cat &
                params$parameter    == p_name &
                (is.na(params$aggregation_level) |
                  params$aggregation_level == agg_level) &
                (is.na(params$cattle_type) |
                  params$cattle_type == cattle_type)
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
        .put_param <- function(col_idx, v) {
          v <- .translator_scalar(v)
          if (is.na(v) || (is.character(v) && !nzchar(v))) return()
          openxlsx::writeData(wb, "Parameters", v,
                              startRow = r, startCol = col_idx,
                              colNames = FALSE)
        }
        if (!is.null(ai)) {
          # Clear the skeleton's cells first (plan A1). The blank template
          # pre-fills block 1 with catalogue values AND numeric lower/upper
          # computed from them; an AI row carrying mean + uncertainty_pct
          # but no bounds left those stale bounds in place, so a user Ym of
          # 8.0 came back bracketed by the catalogue's 5.2 to 7.8.
          openxlsx::deleteData(wb, "Parameters", cols = c(7:13, 16), rows = r,
                               gridExpand = TRUE)
          v_mean <- .translator_scalar(ai$mean %||% ai$value)
          v_unc  <- .translator_scalar(ai$uncertainty_pct)
          v_lo   <- .translator_scalar(ai$lower_bound %||% ai$lower)
          v_hi   <- .translator_scalar(ai$upper_bound %||% ai$upper)
          v_dist <- .translator_scalar(ai$distribution)
          .put_param(7,  v_mean)
          .put_param(8,  v_unc)
          .put_param(11, v_dist)
          # Bounds the simulator reads (cols 12/13). Explicit bounds win;
          # otherwise derive them from the percentage, as the gap-fill
          # branch and the template's own formula do; a constant row
          # brackets itself.
          num <- function(x) suppressWarnings(as.numeric(x))
          if (!is.na(v_lo)) .put_param(12, v_lo)
          else if (!is.na(num(v_mean)) && !is.na(num(v_unc))) .put_param(12, num(v_mean) * (1 - num(v_unc) / 100))
          else if (identical(tolower(as.character(v_dist)), "constant")) .put_param(12, v_mean)
          if (!is.na(v_hi)) .put_param(13, v_hi)
          else if (!is.na(num(v_mean)) && !is.na(num(v_unc))) .put_param(13, num(v_mean) * (1 + num(v_unc) / 100))
          else if (identical(tolower(as.character(v_dist)), "constant")) .put_param(13, v_mean)
          .put_param(16, ai$data_source %||% "AI translator")
        } else {
          # Gap parameter — the AI/overlay didn't supply this (parameter,
          # sub-category). Backfill the IPCC catalogue default so the row is a
          # valid "ipcc_default" entry instead of a blank cell that upload
          # validation rejects with "Invalid distribution:".
          #
          # Why fill EVERY block (not just k>1): the blank-template skeleton
          # only pre-fills the FIRST sub-category block, and for asymmetric
          # params it writes an Excel FORMULA into the simulator-read cols
          # 12/13 that carries no cached value until the file is opened in
          # Excel — so an unopened file would sample NA bounds. Writing
          # explicit NUMBERS here (idempotent for block 1) makes all blocks
          # uniform and simulator-safe: value + uncertainty% + distribution,
          # plus concrete lower/upper — asymmetric params take the catalogue's
          # explicit bounds, symmetric params take value ± uncertainty%.
          # Use the SUB-CATEGORY-AWARE default, not the bare catalogue row.
          # resolve_subcat_default() knows each sub-category's sex and age, so
          # it returns the bull/ox/calf-specific central value AND the
          # biological zeros (Milk/Fat/MilkPR for males, pct_pregnant for
          # males and calves, hours for anything that is not oxen). Filling
          # PARAM_CATALOGUE$ipcc_default here instead gave bulls Milk = 3.5
          # kg/day, which feeds NEl -> GE and inflates enteric CH4, VS and
          # Nex for the group. Audit check F31 covers this.
          #
          # The resolver keeps the catalogue's distribution, uncertainty and
          # bounds and overrides the central value only; all 9 sub-categories
          # x 25 parameters were checked to confirm every overridden value
          # still sits inside its catalogue bounds, so the run-time
          # bounds-bracket check cannot trip on these.
          rs  <- tryCatch(resolve_subcat_default(sub_cat, p_name, ipcc_version),
                          error = function(e) NULL)
          dv  <- if (!is.null(rs)) rs$value           else PARAM_CATALOGUE$ipcc_default[i]
          unc <- if (!is.null(rs)) rs$uncertainty_pct else PARAM_CATALOGUE$suggested_uncertainty_pct[i]
          lb  <- if (!is.null(rs)) rs$lower           else PARAM_CATALOGUE$suggested_lower_bound[i]
          ub  <- if (!is.null(rs)) rs$upper           else PARAM_CATALOGUE$suggested_upper_bound[i]
          dst <- if (!is.null(rs)) rs$distribution    else PARAM_CATALOGUE$suggested_distribution[i]
          src <- if (!is.null(rs)) rs$data_source     else "ipcc_default"
          .put_param(7,  dv)
          .put_param(8,  unc)
          .put_param(9,  lb)
          .put_param(10, ub)
          .put_param(11, dst)
          if (!is.na(lb))                     .put_param(12, lb)
          else if (!is.na(dv) && !is.na(unc)) .put_param(12, dv * (1 - unc / 100))
          if (!is.na(ub))                     .put_param(13, ub)
          else if (!is.na(dv) && !is.na(unc)) .put_param(13, dv * (1 + unc / 100))
          .put_param(16, src)
        }
      }
    }
  }

  # ---------- Manure_Management ---------------------------------------------
  mm <- parsed$manure_management
  mm_gapfilled_mcf <- FALSE   # set below if any MCF had to be defaulted
  if (is.data.frame(mm) && nrow(mm) > 0) {
    MM_DATA_START <- 4L   # template puts banner @ row 1, headers @ 2, hints @ 3
    for (i in seq_len(nrow(mm))) {
      r <- MM_DATA_START + i - 1L
      .put_mm <- function(col_idx, v) {
        v <- .translator_scalar(v)
        if (is.na(v) || (is.character(v) && !nzchar(v))) return()
        openxlsx::writeData(wb, "Manure_Management", v,
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
      #
      # Gap-fill: the translator often supplies only mms_type + fraction_pct.
      # Previously the coefficient columns were then left BLANK, parsed back
      # as NA, and NA propagated through calc_manure_ch4() (VS * 365 * Bo *
      # 0.67 * mcf * frac) to an NA emission. Fill IPCC defaults instead, so
      # the row is a usable "ipcc_default" entry the compiler can override.
      # Audit check F31 covers this.
      #
      # CLIMATE ZONE: MCF is climate-zone dependent (IPCC Table 10.17), but
      # Inventory_Metadata carries no climate_zone field, so a gap-filled MCF
      # here ASSUMES TROPICAL. That assumption is stated in the sheet banner
      # (see below) and in the post-generation chat message so the compiler
      # can change it. TODO: add climate_zone to Inventory_Metadata and key
      # this off it instead of assuming.
      mms_id  <- .translator_scalar(mm$mms_type[i])
      mms_row <- MMS_DEFAULTS[MMS_DEFAULTS$id == mms_id, , drop = FALSE]
      d_mcf   <- if (nrow(mms_row)) mms_row$mcf_tropical[1] else NA_real_
      d_ef3   <- if (nrow(mms_row)) mms_row$ef3[1]          else NA_real_
      d_fr    <- tryCatch(mms_frac_defaults_2019(mms_id), error = function(e) NULL)
      # MMS_FRAC_DEFAULTS_2019 holds FRACTIONS; these columns are PERCENTAGES.
      d_gas   <- if (!is.null(d_fr)) d_fr$frac_gas   * 100 else NA_real_
      d_leach <- if (!is.null(d_fr)) d_fr$frac_leach * 100 else NA_real_
      # Did we have to invent an MCF for this row? Drives the banner note.
      # (`for` does not open a new scope in R, so a plain <- is correct here.)
      # A lowercase `mcf` key is the legacy output-convention example's
      # spelling, where the value was a FRACTION. The column is percent;
      # scale it when it can only be a fraction (plan A5).
      mcf_in <- .translator_scalar(mm$MCF_pct[i] %||% NA)
      if (is.na(mcf_in)) {
        legacy <- suppressWarnings(as.numeric(.translator_scalar(mm$mcf[i] %||% NA)))
        if (!is.na(legacy)) {
          mcf_in <- if (legacy > 0 && legacy <= 1) {
            message("translator: manure row ", i, " gave mcf=", legacy, " as a fraction; scaled to percent")
            legacy * 100
          } else legacy
        }
      }
      if (is.na(mcf_in) && !is.na(d_mcf))
        mm_gapfilled_mcf <- TRUE

      .put_mm(9,  mcf_in %||% d_mcf)
      .put_mm(10, mm$lower_mcf[i])
      .put_mm(11, mm$upper_mcf[i])
      .put_mm(12, mm$distribution_mcf[i])
      .put_mm(13, mm$ef3[i]              %||% mm$EF3[i] %||% d_ef3)
      .put_mm(14, mm$lower_ef3[i])
      .put_mm(15, mm$upper_ef3[i])
      .put_mm(16, mm$distribution_ef3[i])
      .put_mm(17, mm$Frac_GasMS_pct[i]   %||% mm$frac_gasms_pct[i] %||%
                   mm$Frac_GasMS[i] %||% d_gas)
      .put_mm(18, mm$lower_frac_gas[i]   %||%
                   if (!is.null(d_fr)) d_fr$frac_gas_low  * 100 else NA_real_)
      .put_mm(19, mm$upper_frac_gas[i]   %||%
                   if (!is.null(d_fr)) d_fr$frac_gas_high * 100 else NA_real_)
      .put_mm(20, mm$distribution_frac_gas[i])
      .put_mm(21, mm$Frac_LeachMS_pct[i] %||% mm$frac_leachms_pct[i] %||%
                   mm$Frac_LeachMS[i] %||% d_leach)
      .put_mm(22, mm$lower_frac_leach[i] %||%
                   if (!is.null(d_fr)) d_fr$frac_leach_low  * 100 else NA_real_)
      .put_mm(23, mm$upper_frac_leach[i] %||%
                   if (!is.null(d_fr)) d_fr$frac_leach_high * 100 else NA_real_)
      .put_mm(24, mm$distribution_frac_leach[i])
    }
  }

  # Make the tropical MCF assumption visible IN THE FILE, not just in the
  # chat. Written into Inventory_Metadata > Notes (row 8), appended to
  # whatever notes the source already carried, so it travels with the
  # workbook to anyone who opens it later.
  if (isTRUE(mm_gapfilled_mcf)) {
    .mcf_note <- paste(
      "MCF gap-fill: MCF values missing from the source data were filled with",
      "IPCC Table 10.17 defaults for a TROPICAL climate zone (the template has",
      "no climate-zone field yet). If your inventory is temperate or boreal,",
      "review and edit the MCF_pct column in the Manure_Management sheet.")
    .prior <- .translator_scalar(md$notes)
    .prior <- if (is.na(.prior) || !nzchar(as.character(.prior))) ""
              else paste0(as.character(.prior), " | ")
    openxlsx::writeData(wb, "Inventory_Metadata", paste0(.prior, .mcf_note),
                        startRow = 8, startCol = 3, colNames = FALSE)
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
        v <- .translator_scalar(v)
        if (is.na(v) || (is.character(v) && !nzchar(v))) return()
        openxlsx::writeData(wb, "Parameter_TimeSeries", v,
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
  # Same list-of-records → data.frame coercion as the official writer,
  # so the simple fallback also writes Parameters / Manure_Management /
  # Parameter_TimeSeries sheets when the merge degraded their shape.
  parsed$parameters           <- .translator_records_to_df(parsed$parameters)
  parsed$manure_management    <- .translator_records_to_df(parsed$manure_management)
  parsed$parameter_timeseries <- .translator_records_to_df(parsed$parameter_timeseries)
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

# Extract just the numbered clarification items from an AI reply, when
# the reply is dominated by a numbered list (e.g. "Section D —
# Ambiguities" with 4-10 questions wrapped in 200 words of preamble and
# postamble). Returns the extracted block, or NULL when the filter
# decides the reply is mostly prose and should display as-is.
#
# Heuristic gates (all must pass for filtering to engage):
#   - At least 2 numbered items found (`^\s*\d+\.\s+...`).
#   - The matched-block character count is >= 30% of the total reply.
#     Prevents one-off mentions like "see step 1." from triggering.
#
# Each numbered block captures the leading "1." line plus any
# continuation lines (indented, blank, or starting with a "-" / "*"
# bullet) until the next numbered item or two consecutive blank lines.
.translator_extract_numbered_questions <- function(content) {
  if (is.null(content) || !nzchar(content)) return(NULL)
  total_chars <- nchar(content)
  if (total_chars < 80L) return(NULL)  # too short to need filtering
  lines <- strsplit(content, "\n", fixed = TRUE)[[1]]
  is_numbered <- grepl("^\\s{0,3}\\d+\\.\\s+\\S", lines, perl = TRUE)
  if (sum(is_numbered) < 2L) return(NULL)
  # Walk through lines and assemble blocks: each block starts at a
  # numbered line and extends to (but not including) the next numbered
  # line OR a run of >=2 blank lines, whichever comes first.
  blocks <- list()
  in_block <- FALSE
  cur <- character(0)
  blank_streak <- 0L
  for (i in seq_along(lines)) {
    ln <- lines[i]
    if (is_numbered[i]) {
      if (in_block && length(cur) > 0) {
        blocks[[length(blocks) + 1L]] <- paste(cur, collapse = "\n")
      }
      in_block <- TRUE
      cur <- ln
      blank_streak <- 0L
    } else if (in_block) {
      if (!nzchar(trimws(ln))) {
        blank_streak <- blank_streak + 1L
        if (blank_streak >= 2L) {
          blocks[[length(blocks) + 1L]] <- paste(cur, collapse = "\n")
          in_block <- FALSE
          cur <- character(0)
          blank_streak <- 0L
        } else {
          cur <- c(cur, ln)
        }
      } else {
        blank_streak <- 0L
        cur <- c(cur, ln)
      }
    }
  }
  if (in_block && length(cur) > 0L) {
    blocks[[length(blocks) + 1L]] <- paste(cur, collapse = "\n")
  }
  if (length(blocks) < 2L) return(NULL)
  joined <- paste(vapply(blocks, function(b) trimws(b), character(1)),
                  collapse = "\n\n")
  # 30% gate: extracted block must be substantial relative to the full
  # reply. Otherwise the AI is mostly explaining and the numbered list
  # is incidental — show the full prose instead.
  if (nchar(joined) < 0.30 * total_chars) return(NULL)
  joined
}

# Split an assistant message into a clean "visible" part and a hidden
# "details/structure" part.
#
# Four cases the message bubble UI cares about:
#
#   1. Force-template path  : m$content is pure JSON (json_schema mode),
#                              m$display is "Template ready..." text.
#                              -> visible = m$display, hidden = m$content.
#
#   2. Normal reply with ```template-ready ... ``` fence inline:
#                              -> visible = the prose with the fence
#                                 stripped out, hidden = the JSON.
#
#   3. Numbered-question filter (added 2026-06-11): m$display is the
#                              extracted numbered items, m$content is
#                              the full prose+questions reply.
#                              -> visible = m$display,
#                                 hidden  = m$content (full reply
#                                           surfaced via expander).
#
#   4. Normal reply, no fence:
#                              -> visible = m$content (or m$display),
#                                 hidden = NULL (no expander shown).
#
# Returns a list with $visible (character) and $hidden (character or NULL).
.translator_split_visible_hidden <- function(content, display = NULL, payload = NULL) {
  fallback <- list(visible = display %||% content %||% "",
                   hidden  = NULL, summary = "Show structure / details")
  # Case 0 (2026-09-17, plan C6): the emitted JSON is kept out of the
  # message content (so it is never re-sent to the API) and carried in
  # `payload` for the expander instead.
  if (!is.null(payload) && nzchar(payload)) {
    return(list(visible = display %||% content %||% "", hidden = trimws(payload),
                summary = "Show structure / details"))
  }
  if (is.null(content) || !nzchar(content)) return(fallback)

  # Case 1: pure-JSON body + a separate display message. Detected when
  # display differs from content AND content looks like a JSON object.
  if (!is.null(display) && nzchar(display) && !identical(display, content)) {
    trimmed <- trimws(content)
    if (startsWith(trimmed, "{") && endsWith(trimmed, "}")) {
      return(list(visible = display, hidden = trimmed,
                   summary = "Show structure / details"))
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
                hidden = trimws(inner),
                summary = "Show structure / details"))
  }

  # Case 3: display is the numbered-question extract, content is the
  # full prose reply. Surface the full reply in the expander so the
  # user can read the preamble / postamble on demand.
  if (!is.null(display) && nzchar(display) && !identical(display, content)) {
    return(list(visible = display, hidden = trimws(content),
                 summary = "Show full reply"))
  }

  fallback
}

# (The typed-phrase emission trigger, .translator_is_generate_trigger, was
# removed 2026-09-17. It had been dead code since 2026-06-12, when the green
# button became the only trigger.)

# Scan the conversation history for canonical sub-category names and
# return the de-duplicated set. Used by .translator_force_template to
# detect when the AI silently dropped sub-categories from its output
# (a common failure mode — the AI emits one "representative" sub-cat
# and ignores the rest, even when the chat clearly listed all 8). The
# controlled vocabulary comes from translator_prompts/template_schema.md.
#
# 2026-09-17 (plan A6, A7): the vocabulary is the app's ANIMAL_SUBCATEGORIES
# (the literal list here omitted feedlot_cattle and named a growing_females
# that does not exist), and messages the SERVER injected are skipped: the
# exploration contract itself contains "other_cows" and "dairy_cows" as
# examples, so both were always "mentioned in chat" and a mixed inventory
# lacking one triggered a paid re-emission and a spurious warning.
.translator_subcategory_vocab <- function() {
  if (exists("ANIMAL_SUBCATEGORIES")) ANIMAL_SUBCATEGORIES else
    c("dairy_cows", "other_cows", "bulls", "oxen", "heifers", "growing_males",
      "calves_female", "calves_male", "feedlot_cattle")
}
.translator_non_dairy_subcats <- function() setdiff(.translator_subcategory_vocab(), "dairy_cows")
#
# Only what the USER typed counts (2026-09-17, after the first paid smoke
# test): the model's own clarifying question "castrated steers or intact
# bulls?" put the word bulls into an assistant turn, the scan read it as a
# discussed sub-category, and the retry fabricated a bulls block with a
# placeholder population. The user's confirmations are the mapping; the
# model's musings are not.
.translator_detect_subcategories_in_history <- function(messages) {
  if (length(messages) == 0) return(character(0))
  keep <- Filter(function(m) is.null(m$source) && identical(m$role, "user"), messages)
  text <- paste(vapply(keep, function(m) {
    paste(as.character(m$content %||% ""),
          as.character(m$display %||% ""), sep = " ")
  }, character(1)), collapse = "\n")
  if (!nzchar(text)) return(character(0))
  vocab <- .translator_subcategory_vocab()
  found <- vapply(vocab, function(s) grepl(paste0("\\b", s, "\\b"), text), logical(1))
  unname(vocab[found])
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

# Concatenate per-aggregation-level batch outputs into one filled-template
# JSON envelope. Used by .translator_force_template()'s batch path.
#
# parts is a list of parsed JSON objects (one per batch call), each
# containing some subset of parameters / manure_management /
# parameter_timeseries plus a .requested_aggregation_level tag injected
# by the dispatcher. inventory_metadata comes from the discovery call
# and is used as-is.
#
# Each batch's rows are filtered to keep only those whose
# aggregation_level matches the requested one. This guards against
# Sonnet drift (the per-batch nudge asks for one level only, but if the
# model returns rows for other levels too they'd duplicate across
# batches and the merged output would be wrong).
#
# 2026-09-17 (plan A2, A3). Two silent data-loss paths were closed:
#   * rows whose aggregation_level the model left blank were kept and later
#     collapsed onto one key by the writer, so two production systems became
#     one and the second one's values vanished. They now take the requested
#     level BEFORE binding.
#   * the echoed level was compared by exact string; "Commercial_Dairy" for
#     "commercial_dairy" dropped the whole batch with only a stderr line.
#     Labels are now compared in canonical form, and when EVERY row of a
#     batch mismatches, the rows are kept and relabelled (the model answered
#     the right question under the wrong spelling) and a user-visible
#     warning is returned in $warnings.
.translator_merge_batches <- function(inventory_metadata, parts,
                                       agg_levels = NULL) {
  warnings_out <- character(0)
  collect_field <- function(field) {
    pieces <- lapply(parts, function(p) {
      rows <- .translator_records_to_df(p[[field]])
      if (is.null(rows)) return(NULL)
      requested <- p$.requested_aggregation_level
      if (!is.null(requested) && nzchar(requested)) {
        if (!"aggregation_level" %in% names(rows)) rows$aggregation_level <- NA_character_
        ag <- as.character(rows$aggregation_level)
        blank <- is.na(ag) | !nzchar(trimws(ag))
        same  <- !blank & .translator_norm_level(ag) == .translator_norm_level(requested)
        if (any(blank)) {
          message(sprintf("translator: %d %s row(s) in batch '%s' had no aggregation_level; set to the requested level",
                          sum(blank), field, requested))
          ag[blank] <- requested
        }
        # Same level under another spelling ("Emergent Dairy"): keep the
        # canonical label so every batch's rows key identically.
        ag[same] <- requested
        mism <- !blank & !same
        if (any(mism) && all(mism | blank)) {
          # Every labelled row carries another spelling: relabel, keep.
          warnings_out <<- c(warnings_out, sprintf(
            "The AI labelled the %s rows for '%s' as '%s'; they were kept under '%s'. Check the aggregation_level column.",
            field, requested, unique(ag[mism])[1], requested))
          ag[mism] <- requested
          mism[] <- FALSE
        }
        if (any(mism)) {
          message(sprintf("translator: dropped %d cross-contaminated %s row(s) from batch '%s' (labelled %s)",
                          sum(mism), field, requested, paste(unique(ag[mism]), collapse = ", ")))
          warnings_out <<- c(warnings_out, sprintf(
            "%d %s row(s) the AI emitted while producing '%s' belonged to another production system and were dropped.",
            sum(mism), field, requested))
        }
        rows$aggregation_level <- ag
        rows <- rows[!mism, , drop = FALSE]
      }
      if (nrow(rows) == 0) NULL else rows
    })
    pieces <- pieces[!vapply(pieces, is.null, logical(1))]
    if (length(pieces) == 0) return(NULL)
    .translator_rbind_fill(pieces)
  }

  list(
    inventory_metadata    = inventory_metadata,
    parameters            = collect_field("parameters"),
    manure_management     = collect_field("manure_management"),
    parameter_timeseries  = collect_field("parameter_timeseries"),
    warnings              = warnings_out
  )
}

# Coerce any JSON-roundtripped value to a length-1 atomic safe to hand
# to openxlsx::writeData. Handles every shape we've seen from
# jsonlite::fromJSON(simplifyVector=TRUE): NULL, NA, length-0 vector,
# scalar, length>N vector (we keep the first element), list-of-1,
# nested list, even a 1-row data.frame fragment. The writeData call
# below used to throw "no such index at level 1" when a cell value
# was a list-column (production-only — local repros couldn't trigger
# it because the local data came from a flattened simple_xlsx).
.translator_scalar <- function(v) {
  if (is.null(v))           return(NA)
  if (length(v) == 0L)      return(NA)
  if (is.data.frame(v))     return(.translator_scalar(v[1, 1]))
  if (is.list(v))           return(.translator_scalar(v[[1]]))
  v[[1]]
}

# Convert a list-of-records (named lists, one per row) into a data.frame
# with NA-filled missing fields. Pass-through if already a data.frame.
# Returns NULL on empty / unrecognized input.
#
# Why: jsonlite::fromJSON(simplifyVector = TRUE) does not always simplify
# a JSON array-of-objects into a data.frame — if the objects have a
# heterogeneous key set (one batch has lower_mcf, another doesn't), the
# result stays a list-of-named-lists. Downstream writers gate sheet
# emission on is.data.frame() so list-of-records meant the sheet was
# silently dropped. This helper guarantees a data.frame.
.translator_records_to_df <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) {
    if (nrow(x) == 0) return(NULL)
    return(x)
  }
  if (!is.list(x) || length(x) == 0) return(NULL)
  all_names <- unique(unlist(lapply(x, function(r) {
    if (is.list(r) && !is.null(names(r))) names(r) else character(0)
  })))
  if (length(all_names) == 0) return(NULL)
  rows <- lapply(x, function(r) {
    if (!is.list(r) || is.null(names(r))) return(NULL)
    vals <- setNames(vector("list", length(all_names)), all_names)
    for (nm in all_names) vals[[nm]] <- .translator_scalar(r[[nm]])
    as.data.frame(vals, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) return(NULL)
  do.call(rbind, c(rows, list(make.row.names = FALSE)))
}

# rbind a list of data.frames with NA-fill for missing columns. base R's
# rbind throws on column-name mismatch; this aligns columns first.
.translator_rbind_fill <- function(dfs) {
  if (length(dfs) == 0) return(NULL)
  all_cols <- unique(unlist(lapply(dfs, names)))
  do.call(rbind, c(lapply(dfs, function(df) {
    miss <- setdiff(all_cols, names(df))
    for (col in miss) df[[col]] <- NA
    df[, all_cols, drop = FALSE]
  }), list(make.row.names = FALSE)))
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
