# In-app AI translator chat — UI + server logic.
#
# Renders inside the Resources tab. Two visible states:
#   (a) Logged out  -> magic-link login panel.
#   (b) Logged in   -> chat panel (file upload + message history + input box).
#
# Wires up the OpenAI client (R/openai_client.R), the spend ledger
# (R/usage_log.R), and the magic-link auth (R/auth_magic_link.R).

# ============================================================================
# UI
# ============================================================================

translator_chat_ui <- function() {
  bslib::card(
    id = "ai-translator-card",
    style = "border-left: 4px solid #2D6A4F;",
    bslib::card_header(
      h4("AI Translator — turn your raw cattle data into the tool's template",
         style = "margin: 0;")
    ),
    bslib::card_body(
      tags$p(style = "margin: 0 0 14px 0; color: #475569; font-size: 0.92rem;
                       line-height: 1.5;",
        "Drop in your raw cattle data file (.xlsx or .csv). The AI reads ",
        "every sheet, asks any clarifying questions in plain English, ",
        "then produces a downloadable .xlsx in the exact format the Data ",
        "Input tab expects. No setup — sign in once with your email and ",
        "you're ready."),
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
      # Drop a 30-day signed cookie so the next refresh keeps the user
      # signed in without another magic-link round-trip.
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
    if (!grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) {
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
    user_msg <- sprintf(
      "I have uploaded a file (%s) with %d sheet%s. Below is the head of each sheet. Please identify which columns map to which IPCC parameters across all the sheets, and ask any clarifying questions you need.\n\n%s",
      fi$name,
      parsed$n_total_sheets,
      if (parsed$n_total_sheets == 1L) "" else "s",
      paste(sheet_blocks, collapse = "\n\n---\n\n"))
    # The on-screen "display" stays terse — the user doesn't want a wall
    # of markdown tables in their own bubble; only the AI needs that.
    display_summary <- if (parsed$n_total_sheets == 1L)
      sprintf("Uploaded %s (%d rows × %d columns shown).",
              fi$name, nrow(parsed$sheets[[1]]$preview),
              ncol(parsed$sheets[[1]]$preview))
    else
      sprintf("Uploaded %s (%d sheets: %s).",
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

  # The old translator_force_template button has been removed. Users
  # now trigger generation by typing a natural-language phrase like
  # 'produce the template' or 'go ahead' (detected by
  # .translator_is_generate_trigger, which is called inline from
  # observeEvent(input$translator_send) above). The hard-requirements
  # user message that the old observer prepended is now built inside
  # .translator_force_template itself so both paths use it.

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
                    "Upload your raw cattle data above or type a question to get started."))
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
        tags$strong("Signed in: "),
        tags$code(state$user_email)
      )
    ),
    tags$hr(style = "margin:10px 0;"),

    fileInput("translator_file",
              label = tagList(
                tags$strong("1.  Upload your raw cattle data"),
                tags$span(style = "color:#52525B; font-weight:400;",
                          " (.xlsx or .csv) — the AI reads it and starts the conversation.")
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
                       "Translator is working — calling the AI, waiting for the first reply…")),
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
                        label = "2.  Your reply to the AI",
                        placeholder = "Answer the AI's questions, or ask your own…",
                        rows = 2, width = "100%")),
      actionButton("translator_send", "Send", class = "btn-success",
                   style = "min-width:80px; height:42px;")
    ),
    # Secondary action row — reset + download. The 'Produce template
    # now' button was removed; users now trigger generation by saying
    # 'produce the template' / 'go ahead' / etc. in chat, and the
    # server auto-calls the same code path. See observeEvent for
    # translator_send and the .translator_is_generate_trigger helper.
    tags$div(
      style = "display:flex; gap:8px; margin-top:6px; flex-wrap:wrap; align-items:center;",
      actionButton("translator_reset",
                   tagList(icon("rotate-left"),
                            " Reset conversation"),
                   class = "btn-outline-secondary",
                   style = "font-size:0.82rem;",
                   title = "Clear the chat and start over from scratch."),
      conditionalPanel(
        condition = "output.translator_template_ready",
        downloadButton("translator_download_template",
                        "Download template (.xlsx)",
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
                         preview = utils::head(df, 100))),
      n_total_sheets = 1L
    ))
  }
  sheet_names <- readxl::excel_sheets(path)
  out <- list()
  for (s in sheet_names) {
    df <- tryCatch(readxl::read_excel(path, sheet = s, n_max = 200),
                    error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0 || ncol(df) == 0) next
    # Drop sheets that have zero non-NA cells — pure empty placeholders.
    if (sum(!is.na(df)) == 0) next
    out[[length(out) + 1]] <- list(
      name    = s,
      n_rows  = nrow(df),
      n_cols  = ncol(df),
      preview = utils::head(df, 40)   # cap per-sheet preview at 40 rows
                                       # to keep the prompt size reasonable
                                       # for multi-sheet uploads
    )
  }
  if (length(out) == 0)
    stop("No readable sheet found in ", name)
  list(kind = "xlsx", sheets = out, n_total_sheets = length(out))
}

# Render a small data.frame as a markdown table the LLM can read.
.translator_table_to_md <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("(empty data)")
  hdr <- paste("|", paste(names(df), collapse = " | "), "|")
  sep <- paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|")
  rows <- vapply(seq_len(min(nrow(df), 30)), function(i) {
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

  msgs <- openai_build_messages(system_prompt, history = state$messages)

  # Create an empty bubble client-side, then stream tokens into it. The
  # final assistant message gets written into state$messages at the end so
  # the renderUI for the message history catches up.
  session$sendCustomMessage("translatorStreamStart", "")

  resp <- openai_chat_stream(
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

  # Log the spend (now including cached_tokens — 50% discount on the
  # cache-hit portion; see openai_client.R::openai_cost_usd).
  usage_log_append(
    user_email        = state$user_email,
    model             = resp$model,
    prompt_tokens     = resp$usage$prompt_tokens,
    completion_tokens = resp$usage$completion_tokens,
    cached_tokens     = resp$usage$cached_tokens %||% 0L,
    cost_usd          = resp$cost_usd
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
        "template now' below — that uses OpenAI's strict-schema mode and ",
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
    "Produce the final filled template JSON now.",
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
    "2. EVERY sub-category you identified in this conversation (after",
    "   the user's corrections) must appear in `parameters`. ONLY",
    "   those sub-categories — do not add canonical sub-categories",
    "   from the catalogue that the user doesn't have. If the user",
    "   corrected 'Cows' to map to `other_cows` (not `dairy_cows`),",
    "   `dairy_cows` MUST NOT appear in the output.",
    "",
    "3. For each sub-category, fill ALL 25 parameters from the IPCC",
    "   catalogue (N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, Cfi,",
    "   Ca, C, Cp, hours, CP, Ym, Bo, ASH, UE, EF3_PRP, EF4, EF5,",
    "   Frac_GASM_PRP, Frac_LEACH_PRP, MilkPR, Tw) — but honour rule 1:",
    "   user-supplied values OVERRIDE defaults.",
    "",
    "4. ASYMMETRIC BOUNDS. If the user's file has explicit lower /",
    "   upper bounds (Lower CI / Upper CI / lower / upper / ci_lower",
    "   / ci_upper / p2.5 / p97.5), USE those as `lower` and `upper`",
    "   directly, set `distribution = pert`, and leave",
    "   `uncertainty_pct` blank. Do NOT fall back to a symmetric",
    "   ±% from the catalogue.",
    "",
    "5. Manure_Management must contain rows for EVERY sub-category,",
    "   not just one. If the user's raw data has a single herd-wide",
    "   MMS allocation, copy that same allocation to every",
    "   sub-category. Each MMS row must have fraction_pct, MCF_pct,",
    "   EF3, Frac_GasMS_pct, AND Frac_LeachMS_pct filled.",
    "",
    "6. STRICT JSON: no comments, no expressions like 4.5*1.032, no",
    "   'for brevity not shown' placeholders, no trailing commas.",
    "",
    "Do not ask any more questions. Just emit the complete",
    "template-ready JSON matching the schema.",
    sep = "\n")
  msgs <- openai_build_messages(system_prompt, history = state$messages,
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
    resp <- openai_chat_template_force(msgs, on_chunk = on_chunk_cb)
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
      " Type 'go ahead' again — this is sometimes a transient OpenAI hiccup."
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
        " sub-categories. Use IPCC defaults for every cell. ",
        "Strict JSON, no comments, no shortcuts. List every row."))))
    resp2 <- openai_chat_template_force(msgs_retry)
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
          .put_param(9,  ai$lower_bound %||% ai$lower)
          .put_param(10, ai$upper_bound %||% ai$upper)
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
      # Coefficient columns — read both lowercase and CamelCase keys
      # because the AI is inconsistent. MM_COLS positions: 9=MCF_pct,
      # 13=EF3, 17=Frac_GasMS_pct, 21=Frac_LeachMS_pct.
      .put_mm(9,  mm$mcf[i] %||% mm$MCF_pct[i])
      .put_mm(13, mm$ef3[i] %||% mm$EF3[i])
      .put_mm(17, mm$Frac_GasMS_pct[i] %||% mm$frac_gasms_pct[i] %||%
                   mm$Frac_GasMS[i])
      .put_mm(21, mm$Frac_LeachMS_pct[i] %||% mm$frac_leachms_pct[i] %||%
                   mm$Frac_LeachMS[i])
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
  patterns <- c(
    "produce (the |a )?template",
    "generate (the |a )?(template|file|output|xlsx)",
    "create (the |a )?(template|file|output|xlsx)",
    "make (the |a )?(template|file|output|xlsx)",
    "build (the |a )?(template|file|output|xlsx)",
    "give me (the |a )?(template|file|output|xlsx)",
    "translate (the |my )?data",
    "go ahead",
    "do (it|as you think)",
    "you decide",
    "i'?m ready",
    "ready to (generate|produce|go|download)",
    "let'?s? go",
    "ok go",
    "yes( please)?,? (do|generate|produce|go)",
    "(produire|générer|créer) (le |la |un |une )?(template|fichier)"
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
