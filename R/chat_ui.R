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
    bslib::card_header("AI Translator — turn your raw cattle data into the tool's template"),
    bslib::card_body(
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
    parsed <- tryCatch(
      .translator_read_upload(fi$datapath, fi$name),
      error = function(e) {
        state$last_error <- paste0("Couldn't read the uploaded file: ",
                                    conditionMessage(e))
        NULL
      }
    )
    if (is.null(parsed)) return()
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
  observeEvent(input$translator_send, {
    req(state$user_email)
    txt <- trimws(input$translator_input %||% "")
    if (!nzchar(txt)) return()
    updateTextAreaInput(session, "translator_input", value = "")
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user", content = txt, display = txt)
    .translator_send(state, session)
  })

  # ---- Reset conversation: wipe history + saved file -----------------------
  observeEvent(input$translator_reset, {
    req(state$user_email)
    state$messages           <- list()
    state$last_template_json <- NULL
    state$last_error         <- NULL
    conversation_delete(state$user_email)
    showNotification("Conversation reset.", type = "message", duration = 3)
  })

  # ---- Force-template button: ask the AI to produce the final JSON now ----
  observeEvent(input$translator_force_template, {
    req(state$user_email)
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user",
           content = "Please produce the final filled template JSON now using IPCC defaults for any parameters where I haven't given country-specific data. Do not ask any more questions — just output the template-ready JSON matching the schema in your instructions.",
           display = "(Asked the AI to produce the final template now.)")
    .translator_force_template(state, session)
  })

  # ---- Render the message history ------------------------------------------
  # The history scroller has TWO regions:
  #   - .messages-static  : reactive uiOutput, redrawn whenever state$messages
  #                          changes. Holds completed messages.
  #   - #translator_stream_target : non-reactive DOM slot that the streaming
  #                                  JS handlers append to during a live
  #                                  response. Cleared / replaced when the
  #                                  stream finishes and the assistant
  #                                  message lands in state$messages.
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
      `data-translator-scroller` = "true",
      style = "display:flex; flex-direction:column; max-height:480px;
               overflow-y:auto; padding:8px;",
      msgs,
      # Streaming target — JS appends live response bubbles inside this slot.
      tags$div(id = "translator_stream_target",
               style = "display:flex; flex-direction:column;"),
      if (isTRUE(state$pending))
        tags$div(style = "padding:8px; color:#2D6A4F; font-size:0.85rem;",
                 icon("spinner", class = "fa-spin"),
                 " Translator is thinking…")
    )
  })

  # Reactive flag the conditionalPanel watches to decide whether to show
  # the "Download translated template" button. Becomes TRUE only when the
  # AI's latest response contained a successful template-ready JSON block.
  output$translator_template_ready <- reactive({
    !is.null(state$last_template_json) && nzchar(state$last_template_json)
  })
  outputOptions(output, "translator_template_ready", suspendWhenHidden = FALSE)

  # ---- Admin-only budget + usage stats -------------------------------------
  # The budget status line ("Pilot budget: $0.04 / $10.00 used") and a
  # small stats card are visible ONLY to the admin (defined by the
  # ADMIN_EMAIL env var). Regular signed-in users see nothing — they don't
  # need to think about the pilot budget.
  is_admin <- reactive({
    admin <- tolower(trimws(Sys.getenv("ADMIN_EMAIL", unset = "")))
    !is.null(state$user_email) && nzchar(admin) &&
      identical(tolower(state$user_email), admin)
  })

  output$translator_budget_line <- renderText({
    if (!isTRUE(is_admin())) return("")
    budget_status_line()
  })

  # Compact usage card surfaced to the admin: total spend this month,
  # total calls, unique users, latest 5 calls (timestamp + user + tokens
  # + cost). Cheap to render — reads the small CSV ledger.
  output$translator_admin_stats <- renderUI({
    if (!isTRUE(is_admin())) return(NULL)
    df <- tryCatch(usage_log_read(), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) {
      return(tags$div(
        style = "margin-top:14px; padding:10px 14px; background:#F1F5F9;
                 border:1px solid #CBD5E1; border-radius:6px;
                 font-size:0.85rem; color:#475569;",
        tags$strong("Admin: usage log"),
        tags$br(),
        "No translator calls logged yet this container session."))
    }
    total_calls <- nrow(df)
    total_cost  <- sum(as.numeric(df$cost_usd), na.rm = TRUE)
    unique_users <- length(unique(df$user_email))
    # Cache-hit ratio: cached_tokens / prompt_tokens across all calls.
    prompt_sum  <- sum(as.numeric(df$prompt_tokens %||% 0L), na.rm = TRUE)
    cached_sum  <- if ("cached_tokens" %in% names(df))
      sum(as.numeric(df$cached_tokens), na.rm = TRUE) else 0L
    cache_pct   <- if (prompt_sum > 0)
      sprintf("%.0f%%", 100 * cached_sum / prompt_sum) else "—"
    tail_n <- min(5, nrow(df))
    show_cols <- intersect(c("timestamp", "user_email", "prompt_tokens",
                              "completion_tokens", "cached_tokens",
                              "cost_usd"), names(df))
    recent <- tail(df[, show_cols], tail_n)
    if ("cost_usd" %in% names(recent))
      recent$cost_usd <- sprintf("$%.4f", as.numeric(recent$cost_usd))
    tags$div(
      style = "margin-top:14px; padding:10px 14px; background:#F1F5F9;
               border:1px solid #CBD5E1; border-radius:6px;
               font-size:0.82rem; color:#1E293B;",
      tags$div(style = "font-weight:600; margin-bottom:6px; color:#0F172A;",
               "Admin: translator usage (this container session)"),
      tags$div(
        style = "display:flex; gap:18px; flex-wrap:wrap; margin-bottom:8px;",
        tags$span(tags$strong("Calls: "), total_calls),
        tags$span(tags$strong("Spend: "), sprintf("$%.4f", total_cost)),
        tags$span(tags$strong("Unique users: "), unique_users),
        tags$span(title = "Share of prompt tokens served from OpenAI's implicit prompt cache (50% cheaper).",
                  tags$strong("Cache-hit: "), cache_pct)
      ),
      tags$div(style = "font-size:0.78rem; color:#475569; margin-bottom:4px;",
               sprintf("Last %d calls:", tail_n)),
      tags$pre(
        style = "background:#FFFFFF; padding:6px 10px; border-radius:4px;
                 font-size:0.78rem; max-height:160px; overflow-y:auto;
                 margin:0;",
        paste(apply(recent, 1, function(r) {
          paste(r["timestamp"], r["user_email"],
                sprintf("p=%s c=%s %s",
                        r["prompt_tokens"], r["completion_tokens"],
                        r["cost_usd"]))
        }), collapse = "\n")
      ),
      tags$div(style = "font-size:0.78rem; color:#64748B; margin-top:6px;",
               "Note: the usage log is held in the container's working dir ",
               "and resets when shinyapps.io recycles the container. ",
               "For permanent per-month tracking, OpenAI's dashboard at ",
               tags$a(href = "https://platform.openai.com/usage",
                      target = "_blank", "platform.openai.com/usage"),
               " is the source of truth.")
    )
  })

  output$translator_last_error <- renderUI({
    if (!is.null(state$last_error))
      tags$div(style = "padding:8px 12px; margin-top:8px; background:#FED7D7;
                        border-radius:6px; font-size:0.85rem; color:#C53030;",
               state$last_error)
  })

  # ---- Download translated template ----------------------------------------
  # The AI emits a `template-ready` JSON block. We try to write a multi-
  # sheet .xlsx mirroring the official input template (Inventory_Metadata /
  # Parameters / Manure_Management). If the JSON is malformed (commonly
  # because the model hit max_tokens and the response was truncated mid-
  # object), we fall back to writing the raw text as a .json file so the
  # user doesn't lose the AI's work. The filename + extension follow the
  # actual content type produced.
  #
  # Reactive: detect whether the saved JSON is parseable. The download
  # filename / extension is computed against this fresh, so the user sees
  # accurate context.
  .last_template_is_valid <- reactive({
    j <- state$last_template_json
    if (is.null(j) || !nzchar(j)) return(FALSE)
    parsed <- tryCatch(jsonlite::fromJSON(j, simplifyVector = TRUE),
                        error = function(e) NULL)
    !is.null(parsed)
  })

  output$translator_download_template <- downloadHandler(
    filename = function() {
      ext <- if (isTRUE(.last_template_is_valid())) "xlsx" else "json"
      paste0("translated_template_",
             format(Sys.time(), "%Y%m%d_%H%M%S"), ".", ext)
    },
    content = function(file) {
      j <- state$last_template_json
      if (is.null(j) || !nzchar(j)) {
        writeLines("{}", file)
        return(invisible(NULL))
      }
      if (isTRUE(.last_template_is_valid())) {
        .translator_write_template_xlsx(j, file)
      } else {
        # Truncated / malformed — write the raw text and surface a toast.
        writeLines(j, file)
        tryCatch(showNotification(
          paste0("The AI's template output appears truncated or malformed ",
                  "(saved as .json with the raw text). Try clicking ",
                  "'Produce template now' again — the increased token ",
                  "budget usually fixes this."),
          type = "warning", duration = 10),
          error = function(e) NULL)
      }
    },
    contentType = NULL  # let the browser sniff from the extension
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
      ),
      # 2026-06: only the admin sees the budget line. Regular users see
      # nothing in this slot — the spend is not their concern.
      tags$div(style = "font-size:0.82rem; color:#52525B;",
               textOutput("translator_budget_line", inline = TRUE))
    ),
    # Admin-only stats card (visible only when state$user_email matches
    # ADMIN_EMAIL). For non-admin users this renders to NULL.
    uiOutput("translator_admin_stats"),
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
                      border-radius:8px; color:#5D4037; font-size:0.88rem;",
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
       }"
    ))),

    uiOutput("translator_messages"),

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
    # Secondary action row — reset + force-template. Kept compact and
    # styled as outline buttons so they don't compete with the primary
    # Send action above.
    tags$div(
      style = "display:flex; gap:8px; margin-top:6px; flex-wrap:wrap;",
      actionButton("translator_force_template",
                   tagList(icon("file-arrow-down"),
                            " Produce template now"),
                   class = "btn-outline-success",
                   style = "font-size:0.82rem;",
                   title = "Ask the AI to output the final filled template right now, using IPCC defaults for any remaining unknowns."),
      actionButton("translator_reset",
                   tagList(icon("rotate-left"),
                            " Reset conversation"),
                   class = "btn-outline-secondary",
                   style = "font-size:0.82rem;",
                   title = "Clear the chat and start over from scratch.")
    ),

    uiOutput("translator_last_error"),

    # Download button appears only when the AI has produced a complete
    # template (i.e. a `template-ready` fenced block was detected in its
    # last response and parsed into state$last_template_json).
    conditionalPanel(
      condition = "output.translator_template_ready",
      tags$div(style = "margin-top:14px; padding:12px; background:#E8F5E9;
                        border:1px solid #2D6A4F; border-radius:6px;",
               tags$strong("Your translated template is ready."),
               tags$br(),
               tags$span(style = "font-size:0.85rem; color:#52525B;",
                         "The AI has finished mapping your data. Download the result below."),
               tags$br(),
               downloadButton("translator_download_template",
                              "Download translated template (.xlsx)",
                              class = "btn-primary", style = "margin-top:8px;"))
    ),

    tags$hr(style = "margin:14px 0;"),

    tags$div(style = "font-size:0.82rem; color:#52525B;",
             "Prefer to use a free Claude.ai account instead? ",
             tags$a(href = "#downloads-card",
                    "Download the translator kit"),
             " and follow the setup guide in the Resources tab."))
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

  # Extract any `template-ready` fenced block from the reply.
  json_block <- .translator_extract_template_ready(resp$reply)
  if (!is.null(json_block)) state$last_template_json <- json_block

  # Append assistant message to history. The renderUI for translator_messages
  # will redraw and the streaming bubble (still in the DOM from the JS
  # handler) gets replaced by the freshly-rendered history.
  state$messages[[length(state$messages) + 1]] <-
    list(role = "assistant",
          content = resp$reply,
          display = resp$reply)

  # Persist so a refresh / reload resumes where we left off.
  tryCatch(conversation_save(state$user_email, state$messages),
           error = function(e) NULL)
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

  msgs <- openai_build_messages(system_prompt, history = state$messages)
  resp <- openai_chat_template_force(msgs)

  if (!is.null(resp$error)) {
    state$last_error <- resp$error
    return()
  }

  usage_log_append(
    user_email        = state$user_email,
    model             = resp$model,
    prompt_tokens     = resp$usage$prompt_tokens,
    completion_tokens = resp$usage$completion_tokens,
    cached_tokens     = resp$usage$cached_tokens %||% 0L,
    cost_usd          = resp$cost_usd
  )

  # The response IS the JSON — json_schema mode guarantees pure JSON,
  # no fenced block needed.
  state$last_template_json <- resp$reply
  state$messages[[length(state$messages) + 1]] <-
    list(role    = "assistant",
         content = resp$reply,
         display = "Template ready — click the green download button below to get the .xlsx.")
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
      # mcf / ef3 — match the official MM_COLS ordering
      .put_mm(9,  mm$mcf[i] %||% mm$MCF_pct[i])
      .put_mm(13, mm$ef3[i] %||% mm$EF3[i])
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
