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
    preview_md <- .translator_table_to_md(parsed$preview)
    user_msg <- sprintf(
      "I have uploaded a file (%s). Here is the head of the data:\n\n%s\n\nPlease identify which columns map to which IPCC parameters and ask any clarifying questions you need.",
      fi$name, preview_md)
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user",
            content = user_msg,
            display = sprintf("Uploaded %s (%d rows × %d columns shown).",
                              fi$name, nrow(parsed$preview), ncol(parsed$preview)))
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
      tags$div(
        style = paste("max-width:80%; margin:6px 0; padding:10px 14px;",
                      "border-radius:12px; white-space:pre-wrap; font-size:0.92rem;",
                      "line-height:1.45;",
                      bubble_style),
        m$display %||% m$content
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

  # ---- Render the budget status line + last error --------------------------
  output$translator_budget_line <- renderText(budget_status_line())
  output$translator_last_error <- renderUI({
    if (!is.null(state$last_error))
      tags$div(style = "padding:8px 12px; margin-top:8px; background:#FED7D7;
                        border-radius:6px; font-size:0.85rem; color:#C53030;",
               state$last_error)
  })

  # ---- Download translated template ----------------------------------------
  # The AI emits a `template-ready` fenced block containing JSON. We expect
  # one of two shapes (see assemble_translator_system_prompt — Output
  # convention):
  #   { "parameters": [ {parameter, sub_category, value, ...}, ... ],
  #     "manure_management": [ {sub_category, mms_type, fraction_pct, ...}, ... ],
  #     "inventory_metadata": {country, year, species, ipcc_version} }
  # We write this to a multi-sheet .xlsx that mirrors the official template
  # structure (Inventory_Metadata / Parameters / Manure_Management). If
  # parsing fails (malformed JSON), we fall back to a raw .json download so
  # the user doesn't lose the AI's work.
  output$translator_download_template <- downloadHandler(
    filename = function() {
      paste0("translated_template_",
              format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
    },
    content = function(file) {
      .translator_write_template_xlsx(state$last_template_json, file)
    },
    contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
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
      tags$div(style = "font-size:0.82rem; color:#52525B;",
               textOutput("translator_budget_line", inline = TRUE))
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

# Read an uploaded file and return:
#   $sheet_name    chosen sheet (NA for csv)
#   $n_rows_total  total data rows
#   $n_cols_total  total columns
#   $preview       a data.frame of the first 100 rows of the chosen sheet
.translator_read_upload <- function(path, name) {
  ext <- tolower(tools::file_ext(name))
  if (ext == "csv") {
    df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    return(list(sheet_name = NA, n_rows_total = nrow(df), n_cols_total = ncol(df),
                preview = utils::head(df, 100)))
  }
  # Excel — pick the sheet with the most non-empty cells.
  sheets <- readxl::excel_sheets(path)
  best <- NULL
  best_density <- -1
  for (s in sheets) {
    df <- tryCatch(readxl::read_excel(path, sheet = s, n_max = 200),
                    error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) next
    density <- sum(!is.na(df)) / max(1, prod(dim(df)))
    if (density > best_density) {
      best <- list(sheet = s, df = df)
      best_density <- density
    }
  }
  if (is.null(best))
    stop("No readable sheet found in ", name)
  list(sheet_name   = best$sheet,
       n_rows_total = nrow(best$df),
       n_cols_total = ncol(best$df),
       preview      = utils::head(best$df, 100))
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

  # Log the spend.
  usage_log_append(
    user_email        = state$user_email,
    model             = resp$model,
    prompt_tokens     = resp$usage$prompt_tokens,
    completion_tokens = resp$usage$completion_tokens,
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
}

# Write the AI's template-ready JSON to a multi-sheet .xlsx mirroring the
# app's input template structure. Falls back to a JSON dump if the JSON
# is malformed (so the user never loses their work).
.translator_write_template_xlsx <- function(json_text, file_path) {
  if (is.null(json_text) || !nzchar(json_text)) {
    writeLines("{}", file_path)
    return(invisible(NULL))
  }
  parsed <- tryCatch(jsonlite::fromJSON(json_text, simplifyVector = TRUE),
                      error = function(e) NULL)
  if (is.null(parsed)) {
    # Malformed JSON — write the raw text with a .json sibling so the
    # user can still hand-fix it.
    writeLines(json_text, file_path)
    return(invisible(NULL))
  }

  # Build the sheets. Every sheet is optional — the AI may not have
  # gathered Manure_Management info, for instance.
  sheets <- list()

  if (!is.null(parsed$inventory_metadata)) {
    md <- parsed$inventory_metadata
    sheets[["Inventory_Metadata"]] <- data.frame(
      Field = c("Country / region", "Inventory year", "Livestock species",
                 "IPCC Guidelines version", "Prepared by", "Notes"),
      Value = c(md$country %||% "",
                 md$year %||% "",
                 md$species %||% "cattle_dairy",
                 md$ipcc_version %||% "2019_refinement",
                 md$prepared_by %||% "",
                 md$notes %||% ""),
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(parsed$parameters) && length(parsed$parameters) > 0) {
    df <- as.data.frame(parsed$parameters, stringsAsFactors = FALSE)
    sheets[["Parameters"]] <- df
  }

  if (!is.null(parsed$manure_management) && length(parsed$manure_management) > 0) {
    df <- as.data.frame(parsed$manure_management, stringsAsFactors = FALSE)
    sheets[["Manure_Management"]] <- df
  }

  if (length(sheets) == 0) {
    # JSON parsed but no recognised top-level keys — dump raw so the user
    # can still inspect.
    sheets[["RawOutput"]] <- data.frame(content = json_text,
                                          stringsAsFactors = FALSE)
  }

  writexl::write_xlsx(sheets, path = file_path)
  invisible(NULL)
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
