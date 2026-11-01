# In-app AI translator chat: UI + server logic.
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
        t("ai_intro_signin_note")),
      # The translator has its own guide, built as a PDF from the same source
      # as the help page so the two cannot drift. It opens in a new tab from a
      # button, matching how the user guide and methodology are offered on the
      # Resources tab, rather than as an inline "find out more" link.
      tags$a(
        href = "ai_translator_guide.pdf",
        target = "_blank",
        rel = "noopener noreferrer",
        class = "btn btn-outline-success",
        style = "margin: 0 0 14px 0;",
        icon("book"), " ", t("btn_open_ai_guide")
      ),
      if (is_fr)
        tags$div(style = "margin: 0 0 14px 0; padding: 8px 12px;
                          background: #FEF3C7; border-left: 3px solid #F59E0B;
                          border-radius: 4px; font-size: 0.85rem; color: #5D4037;",
                 icon("circle-info"), " ", t("ai_fr_chat_note"))
      else NULL,
      # Workshop hold. Every translation is billed to the project, and the
      # review workshop needs the budget intact for its own sessions. The
      # notice is dated so it removes itself the day after the workshop ends
      # rather than becoming a stale banner nobody dares delete.
      if (Sys.Date() <= .TRANSLATOR_HOLD_UNTIL)
        tags$div(
          style = "margin: 0 0 16px 0; padding: 12px 16px;
                   background: #FFF7ED; border: 1px solid #FB923C;
                   border-left: 4px solid #EA580C; border-radius: 6px;",
          tags$div(style = "font-weight: 700; color: #9A3412; margin-bottom: 3px;",
                   icon("triangle-exclamation"), " ", t("ai_hold_title")),
          tags$div(style = "font-size: 0.9rem; color: #7C2D12; line-height: 1.5;",
                   t("ai_hold_body")))
      else NULL,
      uiOutput("translator_panel")
    )
  )
}

# ============================================================================
# SERVER: install with translator_chat_server(input, output, session, rv)
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
    # a fresh API call (saves the output-token cost: Anthropic only
    # caches inputs, not outputs). Cleared on successful merge / Reset
    # conversation / new file upload. Since 2026-09-17 a part is cached
    # only after the merge has validated it, and the cache is persisted in
    # the conversation file so a Stop (page reload) keeps it (plan A3, F5).
    batch_parts = list(),
    # 2026-10-22: the conversation the cached parts were validated against
    # (sha256 of the user messages and the prompt hash); see
    # .translator_emission_key().
    batch_parts_key = NULL,
    # 2026-10-22 (WP1): the decisions register (R/translator_register.R),
    # the questions waiting for an answer, put to the user one at a time,
    # the index of the current one, and whether Produce should start by
    # itself once the server's own questions are answered.
    register = list(),
    pending_questions = list(),
    recorded = list(),
    revising = FALSE,
    q_index = 1L,
    produce_after_answers = FALSE,
    reg_edit_topic = NULL,
    # 2026-10-22 (WP2): the AI's own list of the source file's categories
    # (label, system, mapped sub-category, mapped level, merge_into,
    # confidence), from the explore reply's source_categories block.
    source_categories = NULL,
    # 2026-10-31 (Stage 3): the explore reply's source_values block, the
    # sheets it is checked against, the gate's last findings, and whether
    # the one corrective round has been used
    source_values = NULL,
    source_sheets = NULL,
    source_gate = NULL,
    source_fix_done = FALSE,
    produce_after_fix = FALSE,
    # 2026-11-01: the one re-emit of the table when the inventory year
    # decided differs from the column it was built on
    year_fix_done = FALSE,
    # the check of the current table (key + result) and the key whose
    # result was posted in the chat
    source_check = NULL,
    source_posted = NULL,
    source_status = NULL,
    allset_posted = NULL,
    # 2026-10-22 (WP6): the job this session started or reconnected to,
    # and the folder the user chose for the results (Chrome/Edge).
    job_id = NULL,
    dir_chosen = NULL,
    # 2026-10-22: the delivery pop-up has been answered once this session
    # (a folder chosen, or Continue), and Produce is waiting on it.
    delivery_ack = FALSE,
    produce_after_ack = FALSE,
    # 2026-09-17: an upload waiting for the user to pick sheets (plan F8).
    pending_upload = NULL,
    precheck_key   = NULL,
    precheck       = NULL,
    template_file     = NULL,   # workbook built once at ready time
    template_file_key = NULL,
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
    extra = list(batch_parts = if (length(state$batch_parts)) state$batch_parts else NULL,
                 batch_parts_key = state$batch_parts_key,
                 register = if (length(state$register)) state$register else NULL,
                 pending_questions = if (length(state$pending_questions)) state$pending_questions else NULL,
                 recorded = if (length(state$recorded)) state$recorded else NULL,
                 revising = isTRUE(state$revising),
                 q_index = state$q_index,
                 source_categories = if (length(state$source_categories)) state$source_categories else NULL,
                 source_values = if (length(state$source_values)) state$source_values else NULL,
                 source_fix_done = isTRUE(state$source_fix_done),
                 last_template_json = state$last_template_json,
                 job_id = state$job_id)),
    error = function(e) NULL)
}

# The conversation a set of cached batch parts belongs to: the user's own
# messages (uploads, answers, decisions) and the prompt they were held under.
# Assistant turns and server notices are left out so that a download hint
# appended after a merge does not invalidate the parts it just validated.
.translator_emission_key_from <- function(messages, register = NULL) {
  user_txt <- vapply(messages, function(m) {
    if (!identical(m$role, "user")) return("")
    c_ <- m$content
    if (!is.character(c_)) c_ <- paste(vapply(c_, function(b) b$text %||% "", ""), collapse = " ")
    c_ %||% ""
  }, character(1))
  user_txt <- user_txt[nzchar(user_txt)]
  reg <- tryCatch(translator_register_digest(register), error = function(e) "")
  .tp_sha256(c(user_txt, tryCatch(translator_system_prompt_hash(), error = function(e) ""), reg %||% ""))
}
.translator_emission_key <- function(state)
  .translator_emission_key_from(state$messages, state$register)

translator_chat_server <- function(input, output, session) {
  state <- .translator_init_state()

  # ---- Session-restore from cookie (runs once on Shiny session start) ------
  # If the browser already has a valid translator_session cookie, the user
  # is signed back in immediately: no magic link required. The Cookie:
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
        if (is.list(bp) && length(bp) > 0) {
          state$batch_parts     <- bp
          state$batch_parts_key <- saved$extra$batch_parts_key
        }
        # 2026-10-22 (WP1): the register and an unfinished question round.
        rg <- saved$extra$register
        if (is.list(rg) && length(rg) > 0) state$register <- rg
        sc_ <- saved$extra$source_categories
        if (is.list(sc_) && length(sc_) > 0) state$source_categories <- sc_
        sv_ <- saved$extra$source_values
        if (is.list(sv_) && length(sv_) > 0) state$source_values <- sv_
        state$source_fix_done <- isTRUE(saved$extra$source_fix_done)
        # 2026-10-22 (WP6): a finished template and the job it came from
        # survive a reload; the job file says whether it is still running.
        ltj <- saved$extra$last_template_json
        if (is.character(ltj) && nzchar(ltj) && .translator_template_is_well_formed(ltj))
          state$last_template_json <- ltj
        jid <- saved$extra$job_id
        if (is.character(jid) && nzchar(jid)) {
          translator_job_mark_lost()
          jb <- translator_job_read(jid)
          if (!is.null(jb)) {
            state$job_id <- jid
            translator_job_register_session(jid, session)
          }
        }
        pq <- saved$extra$pending_questions
        if (is.list(pq) && length(pq) > 0) {
          state$pending_questions <- pq
          state$q_index <- max(1L, as.integer(saved$extra$q_index %||% 1L))
        }
        if (is.list(saved$extra$recorded)) state$recorded <- saved$extra$recorded
        state$revising <- isTRUE(saved$extra$revising)
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
      # 2026-10-14: land on the translator, not the home page. Someone who
      # has just clicked a sign-in link came for the translator, and until
      # now arrived at Home with no sign anything had happened. The panel
      # sits on the Resources tab, below the documents, so the tab switch
      # alone is not enough and the card is scrolled to as well.
      # Sent as one client-side instruction rather than nav_select() plus a
      # scroll. This observer runs on the first flush, before bslib's tab
      # binding is reliably listening, so nav_select() was being dropped and
      # the user landed on Home. The handler retries until the nav link
      # exists, so it no longer depends on which side initialises first.
      tryCatch({
        session$sendCustomMessage("openTranslator", "")
      }, error = function(e) {
        message("auth: couldn't open the translator tab: ", conditionMessage(e))
      })
    } else {
      state$user_email <- NULL
      state$login_status <- paste0(
        "Thanks: your request to access the AI translator (",
        email,
        ") has been forwarded to the administrator for approval. You'll receive an email once approved.")
      auth_notify_admin_of_request(email)
    }
    # Clean the token out of the URL so it doesn't sit in browser history.
    session$sendCustomMessage("scrubUrl", "?")
  }, once = TRUE, ignoreInit = FALSE)

  # ---- Login form: "send me a magic link" ----------------------------------
  # Stop. Sets the flag that a running stream polls on every chunk.
  #
  # This observer is reached in two ways. Normally, through the event loop
  # like any other. During a stream, through later::run_now() called by the
  # keep-alive, which is the only moment the blocked process can read the
  # socket. It therefore has to be cheap and must not touch reactive values:
  # a reactive write here would schedule a flush in the middle of a stream.
  observeEvent(input$translator_stop, {
    translator_cancel_request(session$userData$translator_tok)
    # 2026-10-31: after a page reload the session has no token of its own;
    # the job file carries the running job's token.
    jid <- isolate(state$job_id)
    if (!is.null(jid)) {
      jtok <- tryCatch(translator_job_read(jid)$cancel_token, error = function(e) NULL)
      if (is.character(jtok) && nzchar(jtok)) translator_cancel_request(jtok)
    }
    message("translator: stop requested by ", session$userData$email %||% "user")
  }, ignoreInit = TRUE)

  observeEvent(input$translator_submit, {
    email <- tolower(trimws(input$translator_email %||% ""))
    # perl = TRUE is required so `\s` inside the character class is parsed
    # as the whitespace shortcut. R's default TRE engine treats `\s` in
    # `[^@\s]` as the literal characters `\` and `s`, which rejected every
    # email containing the letter "s": CGIAR addresses (.../@cgiar.org)
    # happen to have no 's' before the @, so the bug only surfaced on
    # external addresses.
    if (!grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email, perl = TRUE)) {
      state$login_status <- "Please enter a valid email address."
      return()
    }
    # 2026-10-14: check approval BEFORE issuing a link. Until now every
    # address got a working sign-in email, including addresses with no
    # access, who then clicked it and were refused. That told them twice
    # that they were in ("Sent! Check your email", then a link that opens
    # the app) before telling them they were not, and it fired an admin
    # notification on every click rather than once on the request.
    if (!auth_is_approved(email)) {
      state$login_status <- paste0(
        "Thanks. ", email, " is not on the access list yet, so no sign-in ",
        "link has been sent. Your request has been forwarded to the ",
        "administrator, and you will receive an email once it is approved.")
      tryCatch(auth_notify_admin_of_request(email),
               error = function(e)
                 message("auth: couldn't notify admin: ", conditionMessage(e)))
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
    state$batch_parts_key <- NULL
    state$prompt_stale <- FALSE
    state$revising <- FALSE
    # 2026-10-22 (WP1): a new file keeps what the user decided and drops
    # what the model read from the previous file; an unfinished question
    # round belongs to that file and is dropped too.
    state$register <- translator_register_keep_user(state$register)
    state$pending_questions <- list()
    state$q_index <- 1L
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
    # Keep a fingerprint of the uploaded workbook: every number in it and the
    # parameter families the scan found. pending_upload is cleared once the
    # file is sent, and the emitted template is checked against the source
    # long after that (see translator_consistency_checks).
    # 2026-10-22 (WP7): a template produced by the tool, corrected by the
    # user and uploaded back. The checks run on it at once (no AI call);
    # the send handler then tells the AI it outranks the earlier answers.
    # 2026-10-23: in that case the source file's fingerprint and categories
    # are kept (the "past translation" button below does the same).
    sheet_names <- vapply(parsed$sheets, function(sh) as.character(sh$name %||% ""), character(1))
    is_template <- all(c("Parameters", "Inventory_Metadata") %in% sheet_names) &&
                   length(state$messages) > 1L
    if (!is_template) {
      state$source_categories <- NULL
      state$source_values <- NULL
      state$source_gate <- NULL
      state$source_fix_done <- FALSE
      state$source_check <- NULL
      state$source_posted <- NULL
      state$source_status <- NULL
      state$allset_posted <- NULL
      state$year_fix_done <- FALSE
      state$source_fp <- tryCatch(translator_source_fingerprint(parsed),
                                  error = function(e) NULL)
      # 2026-10-22 (WP1): a column whose header says percent while its values
      # sit in (0, 1], or the reverse, becomes a pending topic the user has to
      # settle before the template is produced.
      for (lab in tryCatch(.translator_detect_pct_conflicts(parsed), error = function(e) character(0)))
        state$register <- translator_register_add_pending(state$register, paste0("pct_vs_fraction:", lab))
    }
    pc_t <- if (is_template) tryCatch(.translator_precheck_file(fi$datapath, source = state$source_fp),
                                      error = function(e) NULL) else NULL
    state$pending_upload <- list(parsed = parsed, name = fi$name,
                                 hash = parsed$file_hash,
                                 is_template = is_template, precheck = pc_t)
  })

  # 2026-10-23: "Upload a past translation": a template from this tool,
  # corrected by the user, read next to the source file. The source file's
  # fingerprint and categories stay; the cached parts go (a new emission);
  # a template that was ready gives way to the conversation again.
  observeEvent(input$translator_past_file, {
    req(state$user_email)
    fi <- input$translator_past_file
    if (is.null(fi)) return()
    if (length(state$messages) < 2L) {
      showNotification(t("ai_past_needs_source"), type = "warning", duration = 6)
      return()
    }
    parsed <- tryCatch(.translator_read_upload_memo(fi$datapath, fi$name),
                       error = function(e) {
                         state$last_error <- paste0("Couldn't read the uploaded file: ", conditionMessage(e))
                         NULL
                       })
    if (is.null(parsed)) return()
    sheet_names <- vapply(parsed$sheets, function(sh) as.character(sh$name %||% ""), character(1))
    if (!all(c("Parameters", "Inventory_Metadata") %in% sheet_names)) {
      showNotification(t("ai_past_not_template"), type = "warning", duration = 8)
      return()
    }
    state$last_error <- NULL
    state$batch_parts <- list(); state$batch_parts_key <- NULL
    state$prompt_stale <- FALSE
    state$register <- translator_register_keep_user(state$register)
    state$pending_questions <- list(); state$q_index <- 1L
    state$last_template_json <- NULL
    pc_t <- tryCatch(.translator_precheck_file(fi$datapath, source = state$source_fp), error = function(e) NULL)
    state$pending_upload <- list(parsed = parsed, name = fi$name, hash = parsed$file_hash,
                                 is_template = TRUE, precheck = pc_t, past = TRUE)
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
    # Scale warning, shown here because this is the last screen before the
    # first billed call. See .translator_scale_check.
    sc <- .translator_scale_check(pu$parsed)
    scale_panel <- if (isTRUE(sc$warn)) {
      # The aggregation guidance is the SAME string the Data Input tab uses
      # (upload_too_many_groups_fix). The two warnings are about the same
      # decision, met at different moments, and a user who reads one and then
      # the other must not be told two different things.
      # Two different problems, and only the first is certain.
      #   1. Too many tokens. Measured, always true when this panel shows.
      #   2. Too many groups to simulate. A guess: a big file is OFTEN
      #      fine-grained, but it can equally be many years, many sheets or
      #      one wide table. So it is phrased as a condition and carries the
      #      aggregation guidance with it, rather than standing as a fact.
      # The untick advice is dropped for a single-sheet file, where there is
      # nothing to untick.
      lines <- c(
        sprintf(t("ai_scale_tokens"), .fmt_count(round(sc$tokens))),
        if (length(sc$heavy) && length(sheets) > 1L)
          sprintf(t("ai_scale_heavy"), paste(sc$heavy, collapse = ", ")) else NULL,
        paste(sprintf(t("ai_scale_groups"), .MAX_SIMULATED_GROUPS),
              t("upload_too_many_groups_fix")))
      tags$div(
        style = "margin: 6px 0 10px 0; padding: 12px 16px; background:#FEF2F2;
                 border:1px solid #FCA5A5; border-left:4px solid #C1121F;
                 border-radius:6px; font-size:0.88rem; color:#7F1D1D;",
        tags$div(style = "font-weight:700; color:#C1121F; margin-bottom:4px;",
                 icon("triangle-exclamation"), " ", t("ai_scale_title")),
        tags$ul(style = "margin:0 0 6px 0; padding-left:18px;",
                lapply(lines, tags$li)),
        tags$div(style = "font-style:italic;", t("ai_scale_footer")))
    } else NULL
    tags$div(
      style = "margin: 6px 0 12px 0; padding: 10px 14px; background:#F1F8F4;
               border:1px solid #C8E6C9; border-radius:8px; font-size:0.88rem;",
      scale_panel,
      tags$div(style = "font-weight:600; margin-bottom:6px;",
               sprintf("%s: %d sheet%s read (~%s tokens in total). Untick reference or lookup sheets the AI does not need, then send.",
                       pu$name, length(sheets), if (length(sheets) == 1L) "" else "s",
                       format(total, big.mark = ","))),
      checkboxGroupInput("translator_sheets", label = NULL, choices = choices,
                         selected = as.character(seq_along(sheets)), width = "100%"),
      # 2026-10-22 (WP7): context travels with the file, in one message.
      if (isTRUE(pu$is_template)) {
        pc <- pu$precheck; sm <- pc$summary
        tags$div(style = "margin:6px 0 8px 0; padding:8px 12px; background:#FEF9C3; border:1px solid #FDE68A; border-radius:6px; font-size:0.85rem; color:#713F12;",
                 sprintf(t("ai_upload_corrected"), sm$n_fail %||% 0L, sm$n_warn %||% 0L,
                         if (is.null(pc$issues)) 0L else nrow(pc$issues)))
      },
      # 2026-11-01: the inventory year and the country, asked before the
      # exploration. The year decides which column every value of the
      # AI's table is read from; asked afterwards it cost a second table
      # (the Zambia run of 1 November had 2022 in every entry).
      if (!isTRUE(pu$is_template)) tags$div(style = "font-size:0.85rem; margin:2px 0 6px 0;", t("ai_upload_fields_hint")),
      if (!isTRUE(pu$is_template)) tags$div(
        style = "display:flex; gap:12px; flex-wrap:wrap; margin-bottom:4px;",
        tags$div(style = "flex:0 0 220px;",
                 textInput("translator_upload_year",
                           tagList(t("ai_upload_year_label"), " ",
                                   bslib::tooltip(
                                     span(icon("circle-question"), style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                                     t("ai_upload_year_tip"), placement = "right")),
                           value = "", placeholder = t("ai_upload_year_placeholder"), width = "100%")),
        tags$div(style = "flex:1 1 220px;",
                 textInput("translator_upload_country", t("ai_upload_country_label"), value = "",
                           placeholder = t("ai_upload_country_placeholder"), width = "100%"))),
      textAreaInput("translator_upload_note", t("ai_upload_note_label"),
                    placeholder = t("ai_upload_note_placeholder"), rows = 2, width = "100%"),
      actionButton("translator_send_sheets",
                   if (isTRUE(pu$is_template)) t("btn_ai_send_corrected") else "Send to the AI (Step 1 of 3: explore)",
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
    # 2026-11-01: the inventory year (one year) and the country are
    # required for a raw file (the user's decision: the results are for one
    # year, and the AI reads the file for it). Checked before anything is
    # cleared, so the panel stays as it is.
    if (!isTRUE(pu$is_template) &&
        (!grepl("(19|20)[0-9]{2}", input$translator_upload_year %||% "") || !nzchar(trimws(input$translator_upload_country %||% "")))) {
      showNotification(t("ai_upload_fields_required"), type = "warning", duration = 6)
      return()
    }
    parsed <- pu$parsed
    parsed$sheets <- parsed$sheets[idx]
    parsed$n_total_sheets <- length(idx)
    state$pending_upload <- NULL
    # 2026-10-31 (Stage 3): the sheets as the model sees them, kept for the
    # source_values check at Produce (in memory only; after a restart the
    # check is skipped with a notice)
    if (!isTRUE(pu$is_template))
      state$source_sheets <- lapply(parsed$sheets, function(s)
        list(name = s$name, json = s$json, n_rows = s$n_rows))
    # Inline typing-indicator in the conversation while we wait for the
    # AI's first reply; cleared by translatorStreamStart.
    session$sendCustomMessage("translatorAppendTypingBubble", "")
    note <- trimws(input$translator_upload_note %||% "")
    # 2026-11-01: the inventory year and the country given at upload are
    # decisions from the start (the AI builds its table on that column and
    # does not ask), recorded in the register before the exploration.
    settings <- list(year = NULL, country = NULL)
    if (!isTRUE(pu$is_template)) {
      yr <- regmatches(input$translator_upload_year %||% "", regexpr("(19|20)[0-9]{2}", input$translator_upload_year %||% ""))
      if (length(yr) == 1L) settings$year <- yr
      ctry <- trimws(input$translator_upload_country %||% "")
      if (nzchar(ctry)) settings$country <- ctry
      if (!is.null(settings$year))
        state$register <- translator_register_set_user(state$register, "inventory_year", settings$year,
                                                       quote = "given at upload", msg_index = length(state$messages) + 1L)
      if (!is.null(settings$country))
        state$register <- translator_register_set_user(state$register, "country", settings$country,
                                                       quote = "given at upload", msg_index = length(state$messages) + 1L)
    }
    state$year_fix_done <- FALSE
    built <- .translator_build_upload_message(parsed, pu$name, note = note,
                                              corrected = isTRUE(pu$is_template),
                                              precheck = pu$precheck, settings = settings)
    if (isTRUE(pu$is_template)) {
      state$register <- translator_register_set_user(
        state$register, "corrected_template",
        sprintf("the corrected template %s uploaded by the user is the source of truth for every value it carries", pu$name),
        quote = note, msg_index = length(state$messages) + 1L)
    }
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user", content = built$content, display = built$display,
           # Server-injected text. The coverage scan skips messages that
           # carry a `source`, so the sub-category examples in the
           # exploration contract no longer count as "mentioned in chat".
           source = "server_upload", file_hash = pu$hash, ts = .translator_now())
    .translator_persist(state)
    .translator_send(state, session, stage = "explore")
  })

  # ---- Send button: user types something, click Send -----------------------
  # If the user's message looks like a trigger ('produce the template',
  # 'generate it', 'go ahead', etc.), AND the AI has been gathering
  # info for at least one round, we shortcut to the json_schema force-
  # template path: no separate button needed. Otherwise it's a normal
  # chat round (clarifying questions, mapping discussion).
  observeEvent(input$translator_send, {
    req(state$user_email)
    # 2026-10-31: one request at a time. A second Send while the AI is
    # answering used to start a second stream into the same state.
    if (isTRUE(state$pending)) {
      showNotification(t("ai_busy_notice"), type = "warning", duration = 5)
      return()
    }
    txt <- trimws(input$translator_input %||% "")
    if (!nzchar(txt)) return()
    updateTextAreaInput(session, "translator_input", value = "")
    # 2026-10-22: while a question is open in the conversation, the typed
    # text is its answer (kept locally until the round ends).
    if (length(state$pending_questions)) { .translator_answer_in_chat(txt); return() }
    state$messages[[length(state$messages) + 1]] <-
      list(role = "user", content = txt, display = txt, ts = .translator_now())
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
  # "Change something and produce again": keep the conversation, drop the
  # template so the chat controls come back (2026-09-18).
  observeEvent(input$translator_revise, {
    req(state$user_email)
    state$last_template_json <- NULL
    state$last_error <- NULL
    # 2026-10-23: the revision of a produced template is where a past
    # translation can be uploaded next to the source file
    state$revising <- TRUE
    showNotification(t("ai_revise_notice"), type = "message", duration = 8)
  })
  observeEvent(input$translator_reset_after, {
    req(state$user_email)
    .translator_do_reset(state, session)
  })
  observeEvent(input$translator_reset, {
    req(state$user_email)
    .translator_do_reset(state, session)
  })
  .translator_do_reset <- function(state, session) {
    state$messages           <- list()
    state$last_template_json <- NULL
    state$last_error         <- NULL
    state$revising           <- FALSE
    # Drop any cached per-batch parts so a fresh conversation starts
    # with no resume state.
    state$batch_parts        <- list()
    state$pending_upload     <- NULL
    state$prompt_stale       <- FALSE
    conversation_delete(state$user_email)
    # If the user clicked Reset while a request was mid-flight (or the
    # spinner got stuck for any other reason), drop it. translatorStreamEnd
    # also wipes the active streaming bubble reference: safe to call when
    # there's no active stream.
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
             error = function(e) NULL)
    showNotification("Conversation reset.", type = "message", duration = 3)
  }

  # ---- Produce template now: explicit emission trigger ---------------------
  # The green button is the ONLY emission trigger (typed phrases stopped
  # triggering on 2026-06-12; the detector was deleted on 2026-09-17).
  # Refused while the saved conversation predates the live prompt (plan B5).
  observeEvent(input$translator_force_template, {
    req(state$user_email)
    # 2026-10-31: a second click while a run is going used to start a
    # second chain into the same state (two templates assembled at once,
    # which is the out-of-memory crash seen on 30 October).
    if (isTRUE(state$pending)) {
      showNotification(t("ai_busy_notice"), type = "warning", duration = 5)
      return()
    }
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
    # 2026-10-22 (WP1): questions first. An unanswered round from the AI
    # must be answered; then every required topic without a decision, and
    # every conflict the upload scan found, is put to the user one at a
    # time. Produce starts by itself when the last one is confirmed.
    if (length(state$pending_questions)) {
      showNotification(t("ai_qa_answer_first"), type = "warning", duration = 5)
      return()
    }
    # what can be assumed is assumed (listed in the checks workbook and
    # sent to the AI as binding); only the rest is asked
    state$register <- translator_register_assume_defaults(state$register)$register
    missing <- translator_register_missing(state$register)
    if (length(missing)) {
      state$pending_questions <- lapply(seq_along(missing), function(k)
        list(id = k, kind = "server", topic = missing[k],
             text = .translator_topic_question(missing[k]), answer = NULL))
      state$produce_after_answers <- TRUE
      .translator_begin_round(state, sprintf(t("ai_q_gate_notice"), length(missing)))
      .translator_persist(state)
      return()
    }
    # 2026-10-31 (Stage 3): the source_values block against the file,
    # before the first batch is paid for (2026-11-01: normally already
    # checked when the table arrived; a notice covers the 30 s otherwise)
    if (length(state$source_values) && length(state$source_sheets) &&
        !identical(state$source_check$key, .translator_sv_key(state$source_values)))
      showNotification(t("ai_source_gate_checking"), type = "message", duration = 40)
    if (!.translator_source_gate()) return()
    .translator_produce_or_ask_delivery()
  })
  # The gate. TRUE when Produce may go on. On the first failure the entries
  # go back to the AI once (a corrective clarify call) and Produce resumes
  # by itself; on a second failure the list is shown with a "Produce
  # anyway" button.
  # 2026-11-01: the check runs once per table (a key per block) and its
  # result is kept for the click, which then only starts production.
  .translator_sv_key <- function(sv) tryCatch(digest::digest(sv, algo = "md5"), error = function(e) as.character(length(sv)))
  .translator_source_check_cached <- function() {
    sv <- state$source_values; sh <- state$source_sheets
    if (!length(sv) || !length(sh)) return(NULL)
    key <- .translator_sv_key(sv)
    cached <- state$source_check
    if (is.list(cached) && identical(cached$key, key)) return(cached$chk)
    chk <- tryCatch(translator_source_values_check(sv, sh), error = function(e) NULL)
    state$source_check <- list(key = key, chk = chk)
    if (!is.null(chk)) {
      bad <- chk[!chk$ok & !chk$cap, , drop = FALSE]
      message(sprintf("translator: source check: %d entries, %d do not match, %d beyond the rows sent",
                      nrow(chk), nrow(bad), sum(chk$cap)))
    }
    chk
  }
  # `auto` is the observer's call (a table has just arrived): it posts the
  # result, sends the correction only when no question is open, and never
  # starts production.
  .translator_source_gate <- function(auto = FALSE) {
    sv <- state$source_values; sh <- state$source_sheets
    if (!length(sv) || !length(sh)) {
      if (length(sv) && !length(sh) && !auto)
        showNotification(t("ai_source_gate_skipped"), type = "message", duration = 6)
      state$source_gate <- NULL
      return(TRUE)
    }
    chk <- .translator_source_check_cached()
    if (is.null(chk)) { state$source_gate <- NULL; return(TRUE) }
    bad <- chk[!chk$ok & !chk$cap, , drop = FALSE]
    key <- state$source_check$key
    # 2026-11-01, evening: the result is a status line under the chat
    # (output$translator_source_status), not a bubble: as a bubble it
    # landed between two questions
    post <- function(txt) state$source_status <- txt
    if (!nrow(bad)) {
      # 2026-11-01, evening: a clean check shows nothing; once the answers
      # are in, the conversation ends on one bubble that says what to do
      state$source_gate <- NULL
      state$source_status <- NULL
      if (!length(state$pending_questions) && !identical(state$allset_posted, key)) {
        state$allset_posted <- key
        state$messages[[length(state$messages) + 1L]] <- list(
          role = "assistant", source = "server_notice", content = "(all set)", display = t("ai_all_set"), ts = .translator_now())
        .translator_persist(state)
      }
      return(TRUE)
    }
    if (!isTRUE(state$source_fix_done)) {
      if (auto && length(state$pending_questions)) {
        # the correction waits for the answers (one exchange at a time)
        if (!identical(state$source_posted, key)) { state$source_posted <- key; post(sprintf(t("ai_source_gate_pending"), nrow(bad), nrow(chk))) }
        return(FALSE)
      }
      state$source_fix_done <- TRUE
      state$produce_after_fix <- !auto
      state$source_posted <- key
      msg <- .translator_source_fix_message(chk, sv)
      state$messages[[length(state$messages) + 1L]] <- list(
        role = "user", content = msg, source = "server_correction",
        display = sprintf(t("ai_source_gate_fixing"), nrow(bad), nrow(chk)), ts = .translator_now())
      .translator_persist(state)
      session$sendCustomMessage("translatorAppendTypingBubble", "")
      .translator_send(state, session, stage = "source_fix")
      return(FALSE)
    }
    state$source_gate <- bad
    if (!auto) showNotification(sprintf(t("ai_source_gate_failed"), nrow(bad)), type = "warning", duration = 8)
    FALSE
  }
  # Whenever a table arrives and the AI is idle: Produce resumes after a
  # correction the click asked for; otherwise the year check first (the
  # table re-read on the decided year's column, once, when no question is
  # open), then the source check of the new table.
  observeEvent({ state$source_values; state$pending }, {
    if (isTRUE(state$pending)) return()
    if (isTRUE(state$produce_after_fix)) {
      state$produce_after_fix <- FALSE
      if (.translator_source_gate()) .translator_produce_or_ask_delivery()
      return()
    }
    if (!length(state$source_values) || !length(state$source_sheets)) return()
    if (!length(state$pending_questions) && !isTRUE(state$year_fix_done)) {
      yfix <- tryCatch(.translator_year_fix_message(state$register, state$source_values), error = function(e) NULL)
      if (!is.null(yfix)) {
        state$year_fix_done <- TRUE
        state$messages[[length(state$messages) + 1L]] <- list(
          role = "user", content = yfix$text, source = "server_correction",
          display = sprintf(t("ai_year_fix_notice"), yfix$table_year, yfix$year), ts = .translator_now())
        message("translator: year check, table on ", yfix$table_year, ", inventory year ", yfix$year, "; re-emit requested")
        .translator_persist(state)
        session$sendCustomMessage("translatorAppendTypingBubble", "")
        .translator_send(state, session, stage = "source_fix")
        return()
      }
    }
    .translator_source_gate(auto = TRUE)
  }, ignoreInit = TRUE)
  output$translator_source_status <- renderUI({
    txt <- state$source_status
    if (is.null(txt) || !nzchar(txt) || isTRUE(state$pending)) return(NULL)
    okay <- grepl("^Source check: all|^Verification de la source : les", txt)
    tags$div(
      style = paste0("text-align:left; margin:0 auto 8px auto; max-width:720px; padding:8px 12px; border-radius:8px; font-size:0.85rem; ",
                     if (okay) "background:#F1F8F4; border:1px solid #C8E6C9; color:#1B4332;"
                     else "background:#FEF9C3; border:1px solid #FDE68A; color:#713F12;"),
      txt)
  })
  output$translator_source_gate <- renderUI({
    bad <- state$source_gate
    if (!is.data.frame(bad) || !nrow(bad)) return(NULL)
    sv <- state$source_values
    rows <- lapply(seq_len(min(nrow(bad), 40L)), function(k) {
      e <- sv[[bad$idx[k]]]
      tags$li(sprintf("%s!%s %s, %s (%s / %s): %s", e$sheet, e$row, e$col %||% "", e$parameter, e$system %||% "",
                      e$label %||% "", bad$what[k]))
    })
    tags$div(
      style = "text-align:left; margin:0 auto 10px auto; max-width:720px; padding:10px 14px; background:#FEF2F2; border:1px solid #FCA5A5; border-left:4px solid #DC2626; border-radius:8px; font-size:0.85rem; color:#7F1D1D;",
      tags$strong(sprintf(t("ai_source_gate_title"), nrow(bad))),
      tags$div(style = "margin:4px 0;", t("ai_source_gate_body")),
      tags$ul(style = "margin:6px 0 0 0; padding-left:18px; max-height:220px; overflow:auto;", rows),
      if (nrow(bad) > 40L) tags$div(sprintf("... %d more", nrow(bad) - 40L)),
      actionButton("translator_produce_anyway", t("ai_source_gate_anyway"), class = "btn-outline-danger btn-sm",
                   style = "margin-top:8px;"))
  })
  observeEvent(input$translator_produce_anyway, {
    req(state$user_email)
    if (isTRUE(state$pending)) return()
    state$source_gate <- NULL
    .translator_produce_or_ask_delivery()
  })
  # 2026-10-22: before the first run of a session, say where the files
  # will go and offer the folder choice; the run starts from the pop-up.
  # Every way into a run passes here (the button, and the end of a gate
  # round), so the pop-up is never skipped.
  .translator_produce_or_ask_delivery <- function() {
    if (!isTRUE(state$delivery_ack)) {
      state$produce_after_ack <- TRUE
      showModal(.translator_delivery_modal(state$user_email))
      return(invisible(NULL))
    }
    .translator_start_produce(state, session)
  }

  .translator_delivery_modal <- function(email) {
    modalDialog(
      title = t("ai_dlv_title"), easyClose = FALSE, size = "m",
      tags$p(t("ai_dlv_intro")),
      tags$ol(style = "padding-left:20px;",
              tags$li(tags$strong(t("ai_dlv_opt_folder_h")), " ", t("ai_dlv_opt_folder")),
              tags$li(tags$strong(t("ai_dlv_opt_download_h")), " ", t("ai_dlv_opt_download")),
              tags$li(tags$strong(t("ai_dlv_opt_email_h")), " ", sprintf(t("ai_dlv_opt_email"), email %||% ""))),
      tags$p(style = "font-size:0.85rem; color:#555;", t("ai_dlv_note")),
      tags$script(HTML("if (!window.showDirectoryPicker) { var b = document.getElementById('translator_dlv_pick'); if (b) b.style.display = 'none'; var n = document.getElementById('translator_dlv_nopick'); if (n) n.style.display = ''; }")),
      tags$div(id = "translator_dlv_nopick", style = "display:none; font-size:0.85rem; color:#7F1D1D;", t("ai_dlv_no_picker")),
      footer = tagList(
        tags$button(id = "translator_dlv_pick", type = "button", class = "btn btn-success",
                    onclick = "translatorPickDir()", tagList(icon("folder-open"), t("ai_dlv_btn_pick"))),
        actionButton("translator_dlv_continue", t("ai_dlv_btn_continue"), class = "btn-outline-secondary")))
  }
  .translator_after_ack <- function() {
    state$delivery_ack <- TRUE
    removeModal()
    if (isTRUE(state$produce_after_ack)) {
      state$produce_after_ack <- FALSE
      .translator_start_produce(state, session)
    }
  }
  observeEvent(input$translator_dlv_continue, .translator_after_ack())

  .translator_start_produce <- function(state, session) {
    if (isTRUE(state$pending)) {
      showNotification(t("ai_busy_notice"), type = "warning", duration = 5)
      return(invisible(NULL))
    }
    session$sendCustomMessage("translatorAppendInfoBubble",
      "Generating the full template now. A small inventory takes 1 to 3 minutes; a large one with several production systems takes 10 to 40 minutes, one production system at a time, and this panel stays busy throughout. The Download button appears when it finishes.")
    .translator_force_template(state, session)
  }

  # ---- 2026-10-22 (WP1, revised): questions in the conversation -------------
  # The AI's questions are posted one at a time as bubbles; the user answers
  # in the normal input and presses Send. Answers stay local until the last
  # one, then go back in ONE message and the AI reflects once. The server's
  # own questions (inventory year and calves when nothing settled them, and
  # the conflicts the upload scan found) use the same bubbles; their answers
  # go to the register and the transcript, with no AI call.
  .translator_answer_in_chat <- function(txt) {
    qs <- state$pending_questions
    i <- max(1L, min(as.integer(state$q_index %||% 1L), length(qs)))
    q <- qs[[i]]
    skip <- .translator_is_skip(txt)
    qs[[i]]$answer <- if (skip) "" else .translator_parse_choice(q, txt)
    state$pending_questions <- qs
    state$messages[[length(state$messages) + 1L]] <-
      list(role = "user", content = txt, display = txt, source = "user_answer", ts = .translator_now())
    # the answer is in the history now; the page's echo of it goes
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""), error = function(e) NULL)
    if (i < length(qs)) {
      state$q_index <- i + 1L
      .translator_q_bubble(state, i + 1L)
      .translator_persist(state)
    } else {
      .translator_finish_round()
    }
  }
  .translator_finish_round <- function() {
    qs <- state$pending_questions
    state$pending_questions <- list()
    state$q_index <- 1L
    srv_qs <- Filter(function(q) identical(q$kind, "server"), qs)
    ai_qs  <- Filter(function(q) identical(q$kind, "ai"), qs)
    for (q in srv_qs) {
      ans <- q$answer %||% ""
      if (!nzchar(ans)) {
        # skipped: the assumption, if the topic has one, else left open
        if (!is.null(.TRANSLATOR_ASSUMED[[q$topic]])) ans <- .TRANSLATOR_ASSUMED[[q$topic]]
        else if (identical(q$topic, "calves_handling")) ans <- "pooled"
        else if (identical(q$topic, "inventory_year")) next
        else ans <- "as the AI reads it"
      }
      state$register <- translator_register_set_user(state$register, q$topic, ans,
                                                     msg_index = length(state$messages) + 1L)
      txt <- sprintf("Decision: %s = %s", q$topic, ans)
      state$messages[[length(state$messages) + 1L]] <-
        list(role = "user", content = txt, display = "", source = "user_decision", ts = .translator_now())
    }
    if (length(ai_qs)) {
      txt <- .translator_answers_message(ai_qs)
      state$messages[[length(state$messages) + 1L]] <-
        list(role = "user", content = txt, display = t("ai_q_sent"), source = "answers_batch", ts = .translator_now())
      .translator_persist(state)
      .translator_send(state, session, stage = "clarify")
      return(invisible(NULL))
    }
    .translator_persist(state)
    if (isTRUE(state$produce_after_answers)) {
      state$produce_after_answers <- FALSE
      .translator_produce_or_ask_delivery()
    }
    invisible(NULL)
  }

  # ---- 2026-10-22 (WP6): the job panel, from the job file ----------------------
  job_poll <- reactivePoll(2000, session,
    checkFunc = function() {
      id <- isolate(state$job_id)
      if (is.null(id)) return("")
      p <- .translator_job_path(id)
      paste(id, if (file.exists(p)) as.numeric(file.mtime(p)) else "")
    },
    valueFunc = function() translator_job_read(isolate(state$job_id)))
  output$translator_job_panel <- renderUI({
    jb <- job_poll()
    if (is.null(jb)) return(NULL)
    if (identical(jb$status, "running")) {
      invalidateLater(1000, session)   # the clock ticks every second, whatever the file does
      pct <- round(100 * as.numeric(jb$progress %||% 0))
      eta <- jb$eta_sec
      eta_txt <- if (is.null(eta) || !is.finite(as.numeric(eta))) "" else if (as.numeric(eta) < 60) t("ai_job_eta_under_min") else sprintf(t("ai_job_eta_min"), ceiling(as.numeric(eta) / 60))
      if (isTRUE(jb$eta_over) && nzchar(eta_txt)) eta_txt <- paste0(eta_txt, " (", t("ai_job_eta_over"), ")")
      started <- as.POSIXct(jb$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      secs <- if (is.na(started)) NA else max(0, floor(as.numeric(difftime(Sys.time(), started, units = "secs"))))
      el <- if (is.na(secs)) "" else sprintf(t("ai_job_elapsed"), secs %/% 60, secs %% 60)
      lv <- unlist(jb$levels); li <- as.integer(jb$level_index %||% 0)
      # 2026-10-31: after the last system the panel names the stage
      # (assembly, review) instead of staying on "System 5 of 5".
      final_stage <- (jb$stage %||% "") %in% c("assemble", "review", "deliver")
      lab <- if (!final_stage && length(lv) && li >= 1) sprintf(t("ai_job_system"), li, length(lv), lv[min(li, length(lv))]) else (jb$stage_label %||% "")
      tags$div(style = "margin:8px 0; padding:10px 14px; background:#FFF8E1; border:1px solid #FFE082; border-radius:8px; font-size:0.85rem; color:#5D4037;",
        tags$div(style = "display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap;",
                 tags$strong(t("ai_job_running")), tags$span(paste(c(el, eta_txt), collapse = " · "))),
        tags$div(style = "height:8px; background:#FFE082; border-radius:4px; overflow:hidden; margin:6px 0;",
                 tags$div(style = sprintf("height:100%%; width:%d%%; background:#FF6F00;", pct))),
        tags$div(lab),
        tags$div(style = "font-size:0.78rem; color:#8D6E63; margin-top:4px;", t("ai_job_leave_note")))
    } else if (identical(jb$status, "failed") || identical(jb$status, "lost") || identical(jb$status, "stopped")) {
      tags$div(style = "margin:8px 0; padding:8px 12px; background:#FEF2F2; border:1px solid #FCA5A5; border-radius:8px; font-size:0.85rem; color:#7F1D1D;",
               jb$error %||% jb$stage_label %||% jb$status)
    } else NULL
  })
  # 2026-10-23: the past-translation button, only in the revision of a
  # produced template (after "Back to the conversation"): the first
  # conversation is about the source file; a past translation belongs to
  # its revision, read next to it.
  output$translator_past_upload <- renderUI({
    if (!isTRUE(state$revising) || !is.null(state$last_template_json) || length(state$messages) < 2L) return(NULL)
    tags$div(style = "margin-top:14px; padding:10px 12px 0 12px; border:1px dashed #A7F3D0; border-radius:8px; background:#F0FDF4;",
      fileInput("translator_past_file",
                label = tagList(tags$strong(t("ai_past_label")),
                                tags$span(style = "color:#52525B; font-weight:400;", t("ai_past_hint"))),
                accept = c(".xlsx", ".xlsm"), width = "100%"))
  })
  output$translator_delivery_line <- renderUI({
    d <- state$dir_chosen
    tags$div(style = "font-size:0.8rem; color:#555; margin-top:4px;",
             if (!is.null(d) && nzchar(d)) sprintf(t("ai_delivery_folder"), d) else t("ai_delivery_default"))
  })
  observeEvent(input$translator_dir_chosen, {
    v <- input$translator_dir_chosen
    if (isTRUE(v$ok) && nzchar(v$name %||% "")) {
      state$dir_chosen <- v$name
      showNotification(sprintf(t("ai_dir_chosen"), v$name), type = "message", duration = 5)
      # chosen from the pop-up: the run starts now
      if (isTRUE(state$produce_after_ack)) .translator_after_ack()
    } else {
      showNotification(t("ai_dir_failed"), type = "warning", duration = 12)
    }
  })
  observeEvent(input$translator_job_saved, {
    v <- input$translator_job_saved
    req(is.list(v), !is.null(v$id))
    message("translator: browser delivery for job ", v$id, ": mode ", v$mode %||% "?",
            ", ok ", isTRUE(v$ok), if (nzchar(v$error %||% "")) paste0(", error: ", v$error) else "")
    translator_job_update(v$id, delivery = list(mode = v$mode %||% "browser",
                                                browser_saved_at = .translator_now(),
                                                ok = isTRUE(v$ok), error = v$error %||% NULL))
    if (isTRUE(v$ok) && identical(v$mode, "folder"))
      showNotification(sprintf(t("ai_saved_to_folder"), state$dir_chosen %||% ""), type = "message", duration = 8)
    else if (!isTRUE(v$ok))
      showNotification(sprintf(t("ai_save_failed"), v$error %||% ""), type = "warning", duration = 15)
  })


  # ---- Render the message history ------------------------------------------
  # IMPORTANT: this output renders ONLY the completed-message bubbles.
  # The streaming bubble lives in #translator_stream_target which is a
  # STATIC sibling in .translator_chat_panel (NOT inside this renderUI).
  # That separation is critical: when state$messages changes (e.g. on
  # upload, the user msg gets appended), this output re-renders. If the
  # stream_target lived in here, the re-render would replace its DOM
  # while chunks were streaming into it: the bubble would be detached
  # mid-stream and the user would see 10 seconds of silence until the
  # final state$messages update brought everything back at once. By
  # keeping stream_target outside, the live bubble persists across
  # renders and the user sees the AI typing in real time.
  output$translator_messages <- renderUI({
    if (length(state$messages) == 0 && !isTRUE(state$pending))
      return(tags$p(style = "color:#888; font-style:italic;",
                    t("ai_empty_messages")))
    shown <- Filter(function(m) !identical(m$display, ""), state$messages)
    msgs <- lapply(shown, function(m) {
      # User vs AI bubble distinction: standard chat convention:
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
  # template JSON parses AND has a non-empty parameters array: so the
  # button never appears with a payload that would download as a
  # malformed .json.
  # 2026-10-31: not while a run is still going. The template is written
  # before the AI review and rewritten after it; the buttons used to appear
  # at the first write, so the user downloaded the unreviewed files.
  output$translator_template_ready <- reactive({
    !isTRUE(state$pending) && .translator_template_is_well_formed(state$last_template_json)
  })
  outputOptions(output, "translator_template_ready", suspendWhenHidden = FALSE)

  # 2026-09-18: quality preview above the Download button. The produced
  # workbook is written to a temp file, read back through the same parser
  # the Data Input tab uses, and run through run_qaqc() plus the relational
  # checks in translator_checks.R. The user sees what the QA/QC tab will
  # say before downloading. Memoised on the JSON hash: the writer takes a
  # few seconds on a 27-group inventory.
  output$translator_predownload_qa <- renderUI({
    js <- state$last_template_json
    if (isTRUE(state$pending) || !.translator_template_is_well_formed(js)) return(NULL)
    key <- tryCatch(.tp_sha256(js), error = function(e) NULL)
    pc  <- state$precheck
    if (is.null(key) || !identical(state$precheck_key, key) || is.null(pc)) {
      # Not built yet (the workbook writer takes about a minute on a large
      # inventory, too long for a render). Offer it as a click.
      return(tags$div(
        style = "text-align:left; margin:0 auto 14px auto; max-width:720px; padding:10px 14px; background:#fff; border:1px solid #CFD8DC; border-radius:8px; font-size:0.85rem; color:#333;",
        tags$strong(t("ai_precheck_title")), " ",
        actionLink("translator_precheck_run", t("ai_precheck_run"),
                   style = "color:#2D6A4F; font-weight:600;")))
    }
    tagList(.translator_decisions_ui(state$register), .translator_precheck_ui(pc))
  })

  observeEvent(input$translator_precheck_run, {
    js <- state$last_template_json
    if (!.translator_template_is_well_formed(js)) return()
    withProgress(message = t("ai_precheck_building"), value = 0.3, {
      .translator_finalise_template(state, js)
    })
  })

  # ---- Spend display REMOVED 2026-06 ---------------------------------------
  # The user-facing 'Your usage' line, the admin 'Pilot budget' line, and
  # the admin stats card have all been removed at user request: the local
  # CSV resets on every shinyapps.io container recycle, so the numbers
  # were misleading. Ground-truth spend lives in OpenAI's billing
  # dashboard at https://platform.openai.com/usage. The internal
  # budget_would_exceed() cap-check still runs in .translator_send() -
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
  download_name <- NULL
  # 2026-10-22 (WP4): <Country>_<year>_<what>_<stamp>, from the template's
  # own metadata.
  .translator_dl_name <- function(kind) {
    piece <- tryCatch(jsonlite::fromJSON(state$last_template_json, simplifyVector = TRUE),
                      error = function(e) NULL)
    tryCatch(translator_output_filename(piece, kind), error = function(e)
      paste0("translated_", kind, "_", format(Sys.time(), "%Y-%m-%d_%H%M"),
             if (kind == "conversation") ".docx" else ".xlsx"))
  }
  output$translator_download_template <- downloadHandler(
    filename = function() {
      download_name <<- .translator_dl_name("template")
      download_name
    },
    content = function(file) {
      j <- state$last_template_json
      key <- tryCatch(.tp_sha256(j), error = function(e) NULL)
      cached <- state$template_file
      jf <- .translator_job_output(state, "template")
      if (!is.null(jf)) {
        file.copy(jf, file, overwrite = TRUE)
      } else if (!is.null(key) && identical(state$template_file_key, key) &&
          !is.null(cached) && file.exists(cached)) {
        # Built at ready time by .translator_finalise_template.
        file.copy(cached, file, overwrite = TRUE)
      } else if (.translator_template_is_well_formed(j)) {
        .translator_write_template_xlsx(j, file)
      } else {
        # Should be unreachable: the button gate already validated.
        writeLines("{}", file)
      }
      # Tell the browser the file is written, so the amber "building"
      # bubble becomes a green "saved as <name>" that stays on screen.
      tryCatch(session$sendCustomMessage("translatorDownloadDone",
                                         list(file = download_name %||% "the template")),
               error = function(e) NULL)
    },
    contentType = NULL
  )

  # 2026-10-22 (WP6): a finished job's files are the ones delivered; they
  # survive a reload and a session change.
  .translator_job_output <- function(state, kind) {
    jb <- translator_job_read(state$job_id)
    if (is.null(jb) || !identical(jb$status, "done")) return(NULL)
    p <- jb$outputs[[kind]]
    if (is.null(p) || !file.exists(p)) return(NULL)
    p
  }
  output$translator_download_checks <- downloadHandler(
    filename = function() .translator_dl_name("checks"),
    content = function(file) {
      jf <- .translator_job_output(state, "checks")
      if (!is.null(jf)) { file.copy(jf, file, overwrite = TRUE); return(invisible(NULL)) }
      pc <- state$precheck
      if (is.null(pc)) {
        js <- state$last_template_json
        if (.translator_template_is_well_formed(js)) .translator_finalise_template(state, js)
        pc <- state$precheck
      }
      piece <- tryCatch(jsonlite::fromJSON(state$last_template_json, simplifyVector = TRUE),
                        error = function(e) NULL)
      translator_write_checks_xlsx(
        pc %||% list(), state$register, file,
        extra = list(model = .translator_scalar(piece$.model %||% ""),
                     prompt_hash = tryCatch(translator_system_prompt_hash(), error = function(e) ""),
                     register_digest = translator_register_digest(state$register)))
    },
    contentType = NULL
  )
  output$translator_download_conversation <- downloadHandler(
    filename = function() .translator_dl_name("conversation"),
    content = function(file) {
      jf <- .translator_job_output(state, "conversation")
      if (!is.null(jf)) file.copy(jf, file, overwrite = TRUE)
      else translator_write_conversation_docx(state$messages, file)
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
              # .xlsm added 2026-10-13: national calculators are commonly
              # macro workbooks, and readxl reads them exactly as .xlsx.
              # Without it the file picker would not even offer the
              # Colombian workbook, with no explanation to the user.
              accept = c(".xlsx", ".xlsm", ".xls", ".csv"),
              width = "100%"),
    # Filled and shown by the oversized-upload listener in app_ui.R. The
    # limit is read from the same option the server enforces, so the two
    # cannot drift apart.
    tags$div(id = "translator_upload_error",
             `data-msg` = t("ai_upload_too_big"),
             `data-limit` = as.character(
               max(1L, as.integer(getOption("shiny.maxRequestSize",
                                            8 * 1024^2) %/% (1024^2)))),
             style = "display:none; margin:-6px 0 12px 0; padding:12px 16px;
                      background:#FEF2F2; border:1px solid #FCA5A5;
                      border-left:4px solid #DC2626; border-radius:6px;
                      font-size:0.88rem; color:#7F1D1D;"),
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
    # state$messages changes: chunks stream into it visibly in real time.
    # See the long comment on output$translator_messages.
    tags$div(
      `data-translator-scroller` = "true",
      # 2026-10-14: a FIXED height, not max-height. With max-height the box
      # grew as the conversation did, so every reply reflowed the page and
      # moved the card under the reader. At a fixed height the card never
      # changes size, the page never moves, and only this box scrolls.
      # overflow-anchor is off because the browser's own scroll anchoring
      # fights the pin-to-bottom below when Shiny replaces the message list.
      style = "display:flex; flex-direction:column;
               height:60vh; min-height:320px;
               overflow-y:auto; overflow-anchor:none; padding:8px;",
      uiOutput("translator_messages",
                style = "display:flex; flex-direction:column;"),
      tags$div(id = "translator_stream_target",
                style = "display:flex; flex-direction:column;")
    ),

    tags$hr(style = "margin:14px 0;"),

    # 2026-09-18: when a template is ready, every other control disappears
    # and the download button is the only thing to click. Users could not
    # find it among Send / Produce / Reset / Stop. Two plain links below it
    # bring the controls back: revise (keeps the conversation, clears the
    # template) or start over.
    conditionalPanel(
      condition = "output.translator_template_ready",
      tags$div(
        style = "padding:16px 18px; background:#E8F5E9; border:2px solid #2D6A4F;
                 border-radius:12px; text-align:center;",
        tags$p(style = "margin:0 0 12px 0; color:#1B4332; font-size:0.95rem;",
               t("ai_ready_title")),
        uiOutput("translator_predownload_qa"),
        downloadButton("translator_download_template",
                       t("btn_ai_download"),
                       class = "btn-success btn-lg",
                       icon = icon("file-arrow-down"),
                       style = "font-size:1.05rem; padding:12px 28px;"),
        # 2026-10-22 (WP4): the checks to review and the questions and
        # answers, as files of their own.
        tags$div(style = "margin-top:10px; display:flex; gap:8px; justify-content:center; flex-wrap:wrap;",
                 downloadButton("translator_download_checks", t("btn_ai_download_checks"),
                                class = "btn-outline-success btn-sm", icon = icon("list-check")),
                 downloadButton("translator_download_conversation", t("btn_ai_download_conversation"),
                                class = "btn-outline-secondary btn-sm", icon = icon("comments"))),
        tags$div(style = "margin-top:6px; font-size:0.8rem; color:#374151;", t("ai_outputs_note")),
        tags$div(
          style = "margin-top:12px; font-size:0.85rem;",
          actionLink("translator_revise", t("btn_ai_revise"),
                     style = "color:#2D6A4F; margin-right:18px;"),
          actionLink("translator_reset_after", t("btn_ai_new"),
                     style = "color:#6B7280;")))),

    conditionalPanel(
      condition = "!output.translator_template_ready",
    # 2026-10-22 (WP1): the register and the current question sit above
    # the free-text row.
    uiOutput("translator_source_status"),
    uiOutput("translator_source_gate"),
    uiOutput("translator_job_panel"),
    uiOutput("translator_past_upload"),
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
    uiOutput("translator_delivery_line"),
    # Secondary action row: Produce | Reset | Stop | Download.
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
      # 2026-10-22 (WP6): Chrome and Edge let the page ask for a folder
      # now and write the files there when the run ends. Shown only where
      # the browser supports it (the script below runs when the panel is
      # inserted).
      tags$button(id = "translator_pick_dir", type = "button",
                  class = "btn btn-outline-secondary",
                  style = "font-size:0.82rem; display:none;",
                  onclick = "translatorPickDir()",
                  title = t("tip_ai_pick_dir"),
                  tagList(icon("folder-open"), t("btn_ai_pick_dir"))),
      tags$script(HTML("if (window.showDirectoryPicker) { var b = document.getElementById('translator_pick_dir'); if (b) b.style.display = ''; }")),
      # Stop button. Two things happen, in this order.
      #
      # It sets an input, which the server receives on the next pump of the
      # event loop from the stream keep-alive. The observer sets the cancel
      # flag, the stream callback reads it on the next chunk and closes the
      # connection, so the call stops and stops being billed.
      #
      # Then, after a short delay, it reloads the page. The reload is what
      # this button used to do on its own, and it is kept so the user gets
      # their UI back even if the signal does not land. The conversation is
      # persisted before the call starts, so nothing is lost either way.
      tags$button(
        type = "button",
        class = "btn btn-outline-danger",
        style = "font-size:0.82rem;",
        onclick = sprintf(
          paste0("if (confirm('%s')) { ",
                 "Shiny.setInputValue('translator_stop', Date.now(), {priority:'event'}); ",
                 "this.disabled = true; this.textContent = '%s'; ",
                 "setTimeout(function(){ window.location.reload(); }, 1500); }"),
          gsub("'", "\\\\'", t("ai_stop_confirm")),
          gsub("'", "\\\\'", t("ai_stopping"))),
        title = t("tip_ai_stop"),
        tagList(icon("ban"), t("btn_ai_stop"))
      )
    )),

    uiOutput("translator_last_error"))
}

# Date the workshop hold notice stops being shown. The review workshop runs
# 14 to 16 October 2026; the notice clears itself the day after.
.TRANSLATOR_HOLD_UNTIL <- as.Date("2026-10-16")

# Cancellation flag for a running translator call.
#
# R is single threaded. While a stream is being read, the Shiny event loop is
# blocked, so a Stop click cannot reach an observer by the usual route. The
# per-chunk keep-alive pumps the loop (later::run_now), which lets the click
# arrive and sets this flag; the stream callback reads it on the next chunk
# and aborts. A plain environment is used rather than a reactiveVal so that
# setting it inside the pumped loop cannot start a reactive flush mid-stream.
# Per-request cancellation: one flag per in-flight call, keyed by a token,
# rather than one flag for the whole R process.
#
# The old store was a single .TRANSLATOR_CANCEL$stop. That is safe only
# while a worker can host exactly one translation at a time. Two users
# sharing a worker could already cancel each other silently, and the async
# work in knowledge/20-async-translator.md makes overlapping calls normal
# rather than accidental, so this has to be fixed before any of it.
#
# It also closes a second hole. The old flag was reset by the Send and
# Revise observers only, never by "Send to the AI (Step 1 of 3)", so a Stop
# left it TRUE and the next exploration aborted on its first chunk with no
# explanation. A token minted per call cannot carry state forward.
# Which transport the translator uses.
#
# FALSE keeps anthropic_chat_stream(), which holds the R worker for the
# whole call: on 15 October 2026 one exploration held it for 153.9 seconds
# and nobody else in the room could render anything.
#
# TRUE uses anthropic_chat_stream_async(), which returns immediately and
# delivers the reply through a later() callback, so one worker serves many
# people.
#
# Proven: the process stays responsive during a live call (71 heartbeats
# against 1 synchronous); two concurrent live calls both complete; Stop
# cancels one without touching the other; the SSE parse survives a
# multi-byte character split across chunks; and a reactive write from the
# later() callback, wrapped in withReactiveDomain(), reaches Shiny and
# triggers a redraw.
#
# Still unproven, and the reason to test before deploying: two real
# browser sessions streaming at the same time over real websockets.
.TRANSLATOR_ASYNC <- TRUE

.TRANSLATOR_CANCEL <- new.env(parent = emptyenv())

translator_cancel_new <- function() {
  tok <- paste0("rq_", as.integer(Sys.time()), "_",
                paste(sample(c(letters, 0:9), 10L, replace = TRUE), collapse = ""))
  assign(tok, FALSE, envir = .TRANSLATOR_CANCEL)
  tok
}
translator_cancel_request <- function(tok) {
  if (!is.null(tok) && nzchar(tok)) assign(tok, TRUE, envir = .TRANSLATOR_CANCEL)
  invisible(NULL)
}
translator_cancelled <- function(tok) {
  if (is.null(tok) || !nzchar(tok)) return(FALSE)
  isTRUE(tryCatch(get(tok, envir = .TRANSLATOR_CANCEL, inherits = FALSE),
                  error = function(e) FALSE))
}
translator_cancel_clear <- function(tok) {
  if (!is.null(tok) && nzchar(tok) &&
      exists(tok, envir = .TRANSLATOR_CANCEL, inherits = FALSE))
    rm(list = tok, envir = .TRANSLATOR_CANCEL)
  invisible(NULL)
}

# The token for whichever call this session currently has in flight. Kept
# on session$userData, a plain environment, rather than in the module's
# reactiveValues: the Stop observer reads it, and a reactive read there
# would schedule a flush in the middle of a stream.
.translator_begin_request <- function(session) {
  tok <- translator_cancel_new()
  session$userData$translator_tok <- tok
  tok
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
# Asynchronous twin of .translator_memo_call(). A memo hit still arrives
# through the callback, so the chain has one completion path rather than
# an instant branch and a slow branch.
# 2026-10-31: the memo is written only when the reply passes the piece
# validation for its mode. It used to store anything that parsed as JSON,
# so a batch missing its time series (or an enumerate reply without
# levels) was replayed on every later click, at no cost and with no way
# out short of changing the conversation. The model id is in the key: a
# model change must not replay the previous model's reply.
.translator_memo_key <- function(msgs, tools_sig)
  tryCatch(.tp_sha256(c(jsonlite::toJSON(msgs, auto_unbox = TRUE), tools_sig,
                        .ANTHROPIC_DEFAULT_MODEL)), error = function(e) NULL)
.translator_memo_valid <- function(reply, mode) {
  if (is.null(reply) || !nzchar(reply)) return(FALSE)
  parsed <- tryCatch(jsonlite::fromJSON(reply, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(FALSE)
  if (is.null(mode)) return(TRUE)
  is.null(tryCatch(.translator_validate_piece(parsed, mode), error = function(e) "error"))
}
# A memo hit that fails validation downstream is removed, so the next click
# calls the API again.
.translator_memo_forget <- function(msgs, tools_sig) {
  key <- .translator_memo_key(msgs, tools_sig)
  if (!is.null(key)) unlink(.translator_memo_path(key))
  invisible(NULL)
}
.translator_memo_call_async <- function(msgs, tools_sig, start, on_result, mode = NULL) {
  key <- .translator_memo_key(msgs, tools_sig)
  if (!is.null(key)) {
    pth <- .translator_memo_path(key)
    if (file.exists(pth)) {
      hit <- tryCatch(jsonlite::read_json(pth, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(hit) && .translator_memo_valid(hit$reply, mode)) {
        message("translator: response memo hit for ", substr(key, 1, 12))
        return(on_result(list(
          reply = hit$reply,
          usage = list(prompt_tokens = 0L, completion_tokens = 0L,
                       cached_tokens = 0L, cache_write_tokens = 0L,
                       cache_write_1h_tokens = 0L, total_tokens = 0L),
          model = hit$model %||% "memo", cost_usd = 0, error = NULL,
          latency_sec = 0, memo_hit = TRUE)))
      }
      unlink(pth)
    }
  }
  start(function(resp) {
    if (!is.null(key) && is.null(resp$error) && !isTRUE(resp$truncated) &&
        .translator_memo_valid(resp$reply, mode)) {
      tryCatch(jsonlite::write_json(
        list(reply = resp$reply, model = resp$model %||% ""),
        .translator_memo_path(key), auto_unbox = TRUE),
        error = function(e) NULL)
    }
    on_result(resp)
  })
  invisible(NULL)
}

.translator_memo_call <- function(msgs, tools_sig, fn, mode = NULL) {
  key <- .translator_memo_key(msgs, tools_sig)
  if (!is.null(key)) {
    p <- .translator_memo_path(key)
    if (file.exists(p)) {
      hit <- tryCatch(jsonlite::read_json(p, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(hit) && .translator_memo_valid(hit$reply, mode)) {
        message("translator: response memo hit for ", substr(key, 1, 12))
        return(list(reply = hit$reply, usage = list(prompt_tokens = 0L, completion_tokens = 0L,
                    cached_tokens = 0L, cache_write_tokens = 0L, cache_write_1h_tokens = 0L,
                    total_tokens = 0L), model = hit$model %||% "memo", cost_usd = 0,
                    error = NULL, latency_sec = 0, memo_hit = TRUE))
      }
      unlink(p)
    }
  }
  resp <- fn()
  if (!is.null(key) && is.null(resp$error) && !isTRUE(resp$truncated) &&
      .translator_memo_valid(resp$reply, mode)) {
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

# Quality preview of a produced template (2026-09-18). Writes the official
# workbook to a temp file, parses it back and runs the app's QA/QC plus the
# relational checks. Returns list(qa, summary, issues, n_params, n_manure,
# error).
.translator_precheck <- function(json_text, source = NULL) {
  fail <- function(msg) list(qa = NULL, summary = NULL, issues = NULL, error = msg)
  parsed <- tryCatch(jsonlite::fromJSON(json_text, simplifyVector = TRUE),
                     error = function(e) NULL)
  if (is.null(parsed)) return(fail("the template JSON did not parse"))
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp), add = TRUE)
  werr <- tryCatch({ .translator_write_official_template(parsed, tmp); NULL },
                   error = function(e) conditionMessage(e))
  if (!is.null(werr)) return(fail(paste("the workbook could not be written:", werr)))
  .translator_precheck_file(tmp, source = source, piece = parsed)
}

# Same checks on a workbook that already exists (about 4 s for 800 rows).
.translator_precheck_file <- function(path, source = NULL, piece = NULL) {
  fail <- function(msg) list(qa = NULL, summary = NULL, issues = NULL, error = msg)
  if (is.null(path) || !file.exists(path)) return(fail("the workbook was not found"))
  pu <- tryCatch(suppressMessages(parse_uploaded_template(path)), error = function(e) NULL)
  if (is.null(pu) || is.null(pu$param_specs) || !nrow(pu$param_specs))
    return(fail("the workbook could not be read back"))
  region <- tryCatch(as.character(pu$metadata$region %||% ""), error = function(e) "")
  if (!length(region) || is.na(region[1]) || !nzchar(region[1])) region <- "global"
  qa <- tryCatch(run_qaqc(pu$param_specs, region = region[1], manure_data = pu$manure),
                 error = function(e) NULL)
  # 2026-10-23: the parsed metadata names the year `inventory_year`;
  # `year` was always NULL, so the Parameters-versus-time-series check
  # never ran and two 2022 populations in a 2024 template went unseen.
  yr <- suppressWarnings(as.integer(.translator_scalar(
    pu$metadata$inventory_year %||% pu$metadata$year %||% .translator_metadata_list(piece$inventory_metadata)$year %||% NA)))
  if ((is.null(yr) || is.na(yr)) && is.data.frame(pu$population) && "year" %in% names(pu$population))
    yr <- suppressWarnings(max(as.integer(pu$population$year), na.rm = TRUE))
  issues <- tryCatch(translator_consistency_checks(pu$param_specs, pu$manure,
                                                   source = source,
                                                   population = pu$population,
                                                   inventory_year = if (length(yr) && is.finite(yr)) yr else NA,
                                                   piece = piece),
                     error = function(e) NULL)
  list(qa = qa, summary = if (!is.null(qa)) qaqc_summary(qa) else NULL,
       issues = issues, n_params = nrow(pu$param_specs),
       n_manure = if (is.data.frame(pu$manure)) nrow(pu$manure) else 0L, error = NULL)
}

.translator_decisions_ui <- function(register) {
  register <- register %||% list()
  bad <- Filter(function(e) identical(e$applied, FALSE), register)
  if (!length(bad)) return(NULL)
  tags$div(
    style = "text-align:left; margin:0 auto 10px auto; max-width:720px; padding:10px 14px; background:#FEF2F2; border:1px solid #FCA5A5; border-left:4px solid #DC2626; border-radius:8px; font-size:0.85rem; color:#7F1D1D;",
    tags$strong(t("ai_decisions_not_applied")),
    tags$ul(style = "margin:6px 0 0 0; padding-left:18px;",
            lapply(bad, function(e) tags$li(
              tags$span(style = "font-weight:600;", .translator_topic_label(e$topic)), ": ", e$decision,
              if (nzchar(e$applied_note %||% "")) tags$span(style = "color:#991B1B;", paste0(" (", e$applied_note, ")"))))))
}

# The dots of the pre-download preview: stronger than the cell fills, so a
# failure reads as red at a glance (2026-10-23).
.TRANSLATOR_SEV_DOT <- c(fail = "#DC2626", warn = "#F59E0B", info = "#3B82F6")
.translator_sev_dot <- function(sev) {
  sev <- if (!is.null(sev) && sev %in% names(.TRANSLATOR_SEV_DOT)) sev else "warn"
  tags$span(style = sprintf("display:inline-block; width:8px; height:8px; border-radius:50%%; margin-right:6px; background:%s;", .TRANSLATOR_SEV_DOT[[sev]]))
}

.translator_precheck_ui <- function(pc) {
  box <- function(...) tags$div(
    style = "text-align:left; margin:0 auto 14px auto; max-width:720px; padding:10px 14px; background:#fff; border:1px solid #CFD8DC; border-radius:8px; font-size:0.85rem; color:#333;",
    ...)
  if (!is.null(pc$error))
    return(box(tags$strong(t("ai_precheck_title")), " ",
               sprintf(t("ai_precheck_error"), pc$error)))
  s <- pc$summary
  badge <- function(n, label, bg, fg) tags$span(
    style = sprintf("display:inline-block; padding:2px 10px; margin-right:6px; border-radius:4px; background:%s; color:%s; font-weight:600;", bg, fg),
    paste(n, label))
  fails <- if (!is.null(pc$qa)) pc$qa[pc$qa$status == "fail", , drop = FALSE] else NULL
  issues <- pc$issues
  n_issue <- if (is.null(issues)) 0L else nrow(issues)
  n_fail  <- if (is.null(fails)) 0L else nrow(fails)
  cap <- max(1L, n_fail, n_issue)   # 2026-10-22 (WP4): every row, scrollable
  box(
    tags$div(style = "margin-bottom:6px;", tags$strong(t("ai_precheck_title")), " ",
             sprintf(t("ai_precheck_rows"), pc$n_params %||% 0L, pc$n_manure %||% 0L)),
    tags$div(style = "margin-bottom:8px;",
             badge(s$n_pass %||% 0L, t("qa_badge_pass"), "#DCFCE7", "#166534"),
             badge(s$n_warn %||% 0L, t("qa_badge_warn"), "#FEF3C7", "#92400E"),
             badge(n_fail, t("qa_badge_fail"), "#FEE2E2", "#991B1B"),
             badge(n_issue, t("ai_precheck_issues_badge"), "#DBEAFE", "#1E40AF")),
    if (n_fail == 0L && n_issue == 0L)
      tags$div(style = "color:#166534;", t("ai_precheck_clean")),
    if (n_fail > 0L) tagList(
      tags$div(tags$strong(t("ai_precheck_fail_title")), " ", t("ai_precheck_fail_hint")),
      tags$ul(style = "margin:4px 0 8px 0; padding-left:18px; max-height:220px; overflow-y:auto;",
              lapply(seq_len(min(cap, n_fail)), function(i) tags$li(
                .translator_sev_dot("fail"),
                sprintf("%s%s, %s: %s", fails$group[i],
                        if (is.na(fails$level[i])) "" else paste0(" @", fails$level[i]),
                        fails$parameter[i], fails$message[i]))),
              if (n_fail > cap) tags$li(sprintf(t("ai_precheck_more"), n_fail - cap)))),
    if (n_issue > 0L) tagList(
      tags$div(tags$strong(t("ai_precheck_issues_title")), " ", t("ai_precheck_issues_hint")),
      tags$ul(style = "margin:4px 0 0 0; padding-left:18px; max-height:260px; overflow-y:auto;",
              lapply(seq_len(min(cap, n_issue)), function(i) tags$li(
                .translator_sev_dot(issues$severity[i] %||% "warn"),
                tags$span(style = "color:#555;", paste0(issues$where[i], ": ")), issues$issue[i])),
              if (n_issue > cap) tags$li(sprintf(t("ai_precheck_more"), n_issue - cap))))
  )
}

# Build the workbook ONCE when the template becomes ready (2026-09-18).
# The writer takes about a minute on a 27-group inventory; doing it here,
# while the emission progress bubbles are still on screen, makes the
# Download click instant and gives the quality preview something to read.
# Keyed on the JSON hash so a revised template rebuilds and a repeated
# call is free.
.translator_finalise_template <- function(state, json, notify = function(txt) NULL,
                                         extra_issues = NULL, force = FALSE) {
  # 2026-10-23: what the server can settle from the catalogue is settled
  # before anything is written (an uncertainty given as a fraction of 1)
  # 2026-10-30: with the source scan, so GE and DMI go when the file lacks them
  src_fp <- isolate(state$source_fp)
  fams <- if (!is.null(src_fp)) src_fp$families %||% character(0) else NULL
  fixed <- tryCatch(.translator_fix_piece_json(json, families = fams), error = function(e) NULL)
  # 2026-11-01: the time series of every group and parameter whose file
  # row the source check confirmed are copied from that row by the server
  # (R/translator_source.R, translator_rebuild_series)
  rebuilt <- tryCatch(translator_rebuild_series_json(fixed %||% json, isolate(state$source_values), isolate(state$source_sheets)),
                      error = function(e) NULL)
  if (!is.null(rebuilt)) fixed <- rebuilt
  # and the ranges and distributions the table carries for each row
  ranged <- tryCatch(translator_apply_table_ranges_json(fixed %||% json, isolate(state$source_values)), error = function(e) NULL)
  if (!is.null(ranged)) fixed <- ranged
  if (!is.null(fixed) && !identical(fixed, json)) {
    json <- fixed
    state$last_template_json <- fixed
  }
  key <- tryCatch(.tp_sha256(json), error = function(e) NULL)
  if (is.null(key)) return(invisible(NULL))
  cached <- isolate(state$template_file)
  if (!isTRUE(force) && identical(isolate(state$template_file_key), key) && !is.null(cached) &&
      file.exists(cached) && !is.null(isolate(state$precheck)))
    return(invisible(cached))
  tryCatch(notify("Building the workbook and running the quality checks..."),
           error = function(e) NULL)
  path <- file.path(tempdir(), paste0("translated_", substr(key, 1, 12), ".xlsx"))
  ok <- tryCatch({ .translator_write_template_xlsx(json, path); file.exists(path) },
                 error = function(e) FALSE)
  if (ok) {
    state$template_file     <- path
    state$template_file_key <- key
  }
  src <- isolate(state$source_fp)
  if (!is.null(src)) {
    src$source_categories <- isolate(state$source_categories)
    src$register          <- isolate(state$register)
  }
  piece <- tryCatch(jsonlite::fromJSON(json, simplifyVector = TRUE), error = function(e) NULL)
  state$precheck     <- if (ok) .translator_precheck_file(path, source = src, piece = piece)
  # 2026-10-30: what the AI review corrected, and what it explained as not
  # an error, is listed with the checks (see R/translator_review.R).
  # 2026-11-01 (Stage 4.7): what the writer changed without saying, read
  # back from the workbook and listed with the checks
  wdiff <- if (ok) tryCatch(.translator_writer_diff(piece, path), error = function(e) {
    message("translator: writer diff failed (", conditionMessage(e), ")"); NULL }) else NULL
  if (is.data.frame(wdiff) && nrow(wdiff))
    extra_issues <- if (is.data.frame(extra_issues) && nrow(extra_issues)) {
      for (cl in setdiff(names(extra_issues), names(wdiff))) wdiff[[cl]] <- NA
      for (cl in setdiff(names(wdiff), names(extra_issues))) extra_issues[[cl]] <- NA
      rbind(extra_issues, wdiff[, names(extra_issues), drop = FALSE])
    } else wdiff
  if (ok && is.data.frame(extra_issues) && nrow(extra_issues)) {
    pcx <- isolate(state$precheck)
    if (!is.null(pcx) && is.data.frame(pcx$issues)) {
      cols <- names(pcx$issues)
      for (cl in setdiff(cols, names(extra_issues))) extra_issues[[cl]] <- NA
      pcx$issues <- rbind(pcx$issues, extra_issues[, cols, drop = FALSE])
      state$precheck <- pcx
    }
  }
  # 2026-10-22 (WP4): the checks are written into the workbook itself
  # (filters, coloured cells, Check and Why columns) once they are known.
  if (ok) tryCatch(.translator_annotate_workbook(path, isolate(state$precheck)$issues, isolate(state$precheck)$qa),
                   error = function(e) message("translator: workbook annotation failed (", conditionMessage(e), ")"))
                        else list(qa = NULL, summary = NULL, issues = NULL,
                                  error = "the workbook could not be written")
  state$precheck_key <- key
  invisible(if (ok) path else NULL)
}

# Provenance stamp written into the workbook's Notes (plan B6).
.translator_stamp_text <- function(model = NULL, digest = NULL) {
  ph <- tryCatch(substr(translator_system_prompt_hash(), 1, 8), error = function(e) "unknown")
  mh <- tryCatch(substr(translator_prompt_inputs_hash()$master_sha256, 1, 8), error = function(e) "unknown")
  av <- Sys.getenv("APP_VERSION", unset = "")
  # 2026-10-22 (WP8): the digest of the decisions register, so a workbook
  # can be matched to the answers it was built from.
  dg <- if (!is.null(digest) && nzchar(digest)) paste0(", decisions ", digest) else ""
  sprintf("translator: app %s, prompt %s, master %s, model %s%s, %s",
          if (nzchar(av)) av else "dev", ph, mh, model %||% .ANTHROPIC_DEFAULT_MODEL, dg,
          format(Sys.Date(), "%Y-%m-%d"))
}

# ---------------------------------------------------------------------------
# Scale check (2026-10-13)
#
# The Colombian national calculator carries 1,121 municipalities x 9 animal
# categories. Nothing in the app or the prompt knew that is roughly 10,000
# groups against a server that manages 300 to 400, so the file would have been
# mapped in full, uploaded, and then exhausted memory at Simulate, after the
# translator spend and twenty minutes of the user's time.
#
# WHAT THIS CHECKS, AND WHAT IT DELIBERATELY DOES NOT.
#
# It checks the payload: the number of tokens actually about to be sent. That
# is exact, never a guess, and it is what makes an oversized file expensive
# before it is useless. Colombia measures about 3.4 million tokens, which no
# context window holds and which is billed on the way to failing.
#
# It does NOT try to find the geography column. Three attempts at that read
# a dry-matter-intake column as a list of places, and read the Zimbabwe
# template's vocabulary sheet as an inventory. Telling a municipality column
# from a measurement is a semantic judgement, the model has the column names
# and the data in front of it, and the Runnable-size rule in
# system_instructions.md puts the ceiling and the question in its hands. A
# warning that fires on correct files is worse than none, because users learn
# to click past it.
#
# .MAX_SIMULATED_GROUPS is stated to the model in that rule. Audit F64 fails
# if the two drift apart.
#
# This WARNS and never blocks. A user may be heading for a local run, or may
# intend to aggregate in the conversation. Refusing their data is not the
# tool's call.
# ---------------------------------------------------------------------------
# The group ceiling is .MAX_SIMULATED_GROUPS in R/utils_validation.R, shared
# with the template upload check so the two cannot state different numbers.
.TRANSLATOR_MAX_PAYLOAD_TOKENS <- 120000L  # above this no context window holds it

.translator_scale_check <- function(parsed) {
  empty <- list(warn = FALSE, tokens = 0, heavy = character(0))
  if (is.null(parsed) || !length(parsed$sheets)) return(empty)
  # est_tokens is set when the upload is read and is the same figure the
  # sheet picker shows. Recomputing it here would let the two disagree.
  tok <- vapply(parsed$sheets, function(s) as.numeric(s$est_tokens %||% 0), numeric(1))
  heavy <- vapply(seq_along(parsed$sheets), function(i) {
    s <- parsed$sheets[[i]]
    if (tok[i] > .TRANSLATOR_MAX_PAYLOAD_TOKENS / 4)
      (if (is.null(s$name) || is.na(s$name)) "(file)" else s$name) else NA_character_
  }, character(1))
  list(warn   = sum(tok) > .TRANSLATOR_MAX_PAYLOAD_TOKENS,
       tokens = sum(tok),
       heavy  = heavy[!is.na(heavy)])
}

# The same facts, phrased for the model, appended to the Explore message.
.translator_scale_note <- function(sc) {
  if (is.null(sc) || !isTRUE(sc$warn)) return("")
  paste0(
    "## Scale warning from the server (not from the file)

",
    sprintf(paste0(
      "- This file's data block is roughly %s tokens, which is more than the ",
      "conversation can carry. Name the sheets that are reference or lookup ",
      "tables rather than inventory data in section D, so the user can untick ",
      "them and send again%s.
"),
      format(round(sc$tokens), big.mark = ","),
      if (length(sc$heavy))
        paste0(" (the largest are: ", paste(sc$heavy, collapse = ", "), ")") else ""),
    sprintf(paste0(
      "- A file this size usually carries a finer geography than the app can ",
      "simulate, which is about %d groups. Apply the Runnable-size rule: ",
      "work out from the file how many (aggregation level, sub-category) ",
      "groups it implies, and if that exceeds the ceiling, raise the ",
      "geographic level as the FIRST question in section D, naming the ",
      "coarser level the file already contains.
"),
      .MAX_SIMULATED_GROUPS),
    "
---

")
}

# Build the Explore user message from a parsed upload (the sheets the user
# ticked). Returns list(content = what the model sees, display = what the
# user sees in their own bubble).
.translator_build_upload_message <- function(parsed, file_name, note = "",
                                             corrected = FALSE, precheck = NULL,
                                             settings = NULL) {
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
    "list: the user's file has a value for it.\n\n---\n\n")
  exploration_block <- paste0(
    "## STEP 1 OF 3: EXPLORATION (your task this turn)\n\n",
    "Your ONLY job in this turn is to produce a structured exploration ",
    "report describing what's in this file. **Do NOT produce a JSON ",
    "template.** Section B is the mapping; the user answers your section ",
    "D questions in Step 2 (Clarification), and only then starts Step 3 ",
    "(Emission). Producing a template now would be wrong: you don't have ",
    "the clarifications yet.\n\n",
    "Output the following FOUR sections, in order, with verbatim ",
    "section headers `### A.`, `### B.`, `### C.`, `### D.`:\n\n",
    "### A. File shape\n\n",
    "For each sheet, classify the layout pattern (pick one):\n",
    "- `column-oriented`: one row per sub-category, one column per parameter (e.g. row 1 = Cows; cols = N, BW, MW, …)\n",
    "- `wide-stacked`: one row per parameter, columns repeat across sub-categories and mean/lower/upper triples (e.g. row = LW; cols = Cows mean, Cows Lower CI, Cows Upper CI, Bulls mean, …)\n",
    "- `parameter-labeled`: a `parameter` column + `sub-category` column + mean/lower/upper triple\n",
    "- `reference-table`: vocab / dropdown lists / catalogues, NOT data to extract\n",
    "- `calc-sheet`: derived / computed (e.g. NRC calculations behind an aggregated value)\n\n",
    "### B. Inventory of values found\n\n",
    "Not a prose table: ONE fenced block labelled `source_values` holding a JSON array with one object per sub-category and ",
    "production system. Each object has `system` (the production-system label exactly as written in the file), `label` (the ",
    "sub-category label exactly as written on its rows), `sub_category` and `aggregation_level` (template codes) and `values`: ",
    "an array with one row per value you will emit from the file for the inventory year (one row per parameter and group; ",
    "the other years of a time series are not listed, the server checks them after production), one row per line, in this fixed order: ",
    "`[parameter, sheet, row, col, section, mean, lower, upper, unit, distribution]` where `parameter` is the catalogue code, ",
    "`sheet` the sheet name, `row` the JSON row key (an integer), `col` the header the mean was read from (the year header, ",
    "a header name from `headers`, or the Excel letter), `section` the row's `_section` copied verbatim, `mean`, `lower`, ",
    "`upper` numbers or null, `unit` a string or null, `distribution` as in the file or null. A lower/upper read from another ",
    "sheet (a margin-of-error sheet) adds two more elements: `bounds_sheet`, `bounds_row`. ",
    "Write one line of text before the block: \"source_values: N entries\" (N counts the value rows).\n\n",
    "The server checks every entry against the file cell by cell (sheet, row, column, value, `_section`, labels) and sends ",
    "back any that does not match. The production system and the block heading tell look-alike rows apart ",
    "(the same sub-category in several systems; the Weight, Mature weight and Weight gain blocks): take the ",
    "parameter of a value from its row's `_section`, never from a neighbouring row. Cover every parameter from the server-side ",
    "scan above. If you cannot find a row a label points to, say so ",
    "in section D rather than skipping silently.\n\n",
    "### C. Inventory of GAPS\n\n",
    "C1. Every IPCC catalogue parameter that is NOT in the file (these take IPCC defaults at emission). Be exhaustive: ",
    paste(PARAM_CATALOGUE$parameter[!PARAM_CATALOGUE$param_tier %in% "optional"], collapse = " / "),
    ", minus what's in section B. (GE and DMI are never gaps: they exist only when measured.)\n",
    "C2. Every value in section B that has no range (no lower, no upper, no percentage): list them by parameter and sub-category, ",
    "split into those with a catalogue default range and those the user must supply.\n\n",
    "### D. Ambiguities to ask the user\n\n",
    "Enumerate every ambiguity you'd like the user to resolve before ",
    "emission. Don't propose answers: just list the questions. ",
    "Common ambiguities to look for:\n",
    "- Which year column is the inventory year, when the file has several\n",
    "- Geographic or administrative level, when the file holds more than one\n",
    "- The region (continent) of the herd\n",
    "- Sub-category vocabulary mapping (raw label → template controlled vocabulary)\n",
    "- Unit conversions (kg vs lb, % vs fraction, L vs kg of milk, °C vs °F)\n",
    "- Biological zeros (does the file's Milk row apply only to lactating cows?)\n",
    "- MMS code meanings (PIT → liquid slurry or solid storage?)\n",
    "- Breed disaggregation (Local vs Cross: treat together or split?)\n",
    "- Sheet purpose (is Sheet2 a separate dataset or a calc behind Sheet1?)\n",
    "- Per-sub-cat vs herd-wide allocations (MMS rows apply to everyone or per group?)\n\n",
    "End with section D; the app shows the questions one at a time.\n\n",
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
    "`_section` is added by the server, not a column of the file: it is the nearest ",
    "heading row above that row, which names the parameter block the row belongs to ",
    "(for example Weight versus Mature weight, whose rows otherwise look the same). ",
    "Take the parameter of every value from its row's `_section`, never from nearby rows.\n\n",
    "```json\n",
    "{\n  \"file\": \"", file_name, "\",\n  \"sheets\": ", sheets_json, "\n}\n",
    "```\n\n---\n\n")
  # Scale note first, so the geographic level is the first thing the model
  # weighs rather than something it meets after mapping 10,000 groups.
  scale_block <- .translator_scale_note(.translator_scale_check(parsed))
  # 2026-10-22 (WP7): the user's own words about the file, and the
  # corrected-template header when the file is a template coming back.
  note_block <- if (nzchar(note)) paste0(
    "## NOTES FROM THE USER ABOUT THIS FILE\n\n", note,
    "\n\nThese notes are binding: record each point as a decision (basis user) in your decisions block, ",
    "and do not ask a question about anything they settle.\n\n---\n\n") else ""
  # 2026-11-01: the inventory year and the country given at upload
  settings_block <- if (!is.null(settings$year) || !is.null(settings$country)) paste0(
    "## SETTINGS GIVEN BY THE USER AT UPLOAD\n\n",
    if (!is.null(settings$year)) sprintf(paste0(
      "Inventory year: %s. Read every value of the source_values block from the %s column ",
      "(a parameter given once applies to it) and do not ask which year is the inventory year. "),
      settings$year, settings$year) else "",
    if (!is.null(settings$country)) sprintf("Country: %s. ", settings$country) else "",
    "\n\nThese are decisions already recorded (topics inventory_year and country): repeat them in your decisions block.\n\n---\n\n") else ""
  corrected_block <- if (isTRUE(corrected)) {
    sm <- precheck$summary
    paste0(
      "## CORRECTED TEMPLATE (version 2)\n\n",
      "The user has corrected the template this conversation produced and uploaded it back. ",
      "It is now the source of truth for every value it carries: use its rows as they are ",
      "(data_source = 'user_file' for values the user set, keep 'ipcc_default' where the file says so), ",
      "do not re-derive them from the original file or from earlier answers, and treat the user's ",
      "notes as binding. Do not run a full exploration again: confirm in a few lines what changed, ",
      "ask only about what is unclear, and end with the decisions block.",
      if (!is.null(sm)) sprintf("\n\nThe server's checks on this file: %d failures, %d warnings, %d consistency notes.",
                                sm$n_fail %||% 0L, sm$n_warn %||% 0L,
                                if (is.null(precheck$issues)) 0L else nrow(precheck$issues)) else "",
      "\n\n---\n\n")
  } else ""
  content <- sprintf(
    "I have uploaded a file (%s) with %d sheet%s.\n\n%s%s%s%s%s%s%s",
    file_name, parsed$n_total_sheets,
    if (parsed$n_total_sheets == 1L) "" else "s",
    scale_block, corrected_block, settings_block, note_block, exploration_block, detect_block, file_block)
  display <- if (parsed$n_total_sheets == 1L)
    sprintf("Uploaded %s (%d rows × %d columns sent). Step 1 of 3: the AI will now explore your file and report what it found.",
            file_name, nrow(parsed$sheets[[1]]$preview), ncol(parsed$sheets[[1]]$preview))
  else
    sprintf("Uploaded %s (%d sheets sent: %s). Step 1 of 3: the AI will now explore your file and report what it found.",
            file_name, parsed$n_total_sheets,
            paste(sapply(parsed$sheets, `[[`, "name"), collapse = ", "))
  if (isTRUE(corrected))
    display <- sprintf("Uploaded the corrected template %s. The AI will take its values as they are.", file_name)
  if (!is.null(settings$year) || !is.null(settings$country))
    display <- paste0(display, "\n\n",
                      if (!is.null(settings$year)) paste0("Inventory year: ", settings$year, ". ") else "",
                      if (!is.null(settings$country)) paste0("Country: ", settings$country, ".") else "")
  if (nzchar(note)) display <- paste0(display, "\n\nYour notes: ", note)
  list(content = content, display = display)
}

# Read an uploaded file and return a SUMMARY OF ALL SHEETS so the AI
# can see everything in one shot.
#
# Returns:
#   $kind          "csv" or "xlsx"
#   $sheets        list of list(name, n_rows, n_cols, preview): one
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
    # Drop sheets that have zero non-NA cells: pure empty placeholders.
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
    "N (population / head count)"     = c("^n$", "head_?count", "\\bpopulation", "cattle_?pop", "\\bnumber of (animals|cattle|head)", "\\beffectif", "cabezas", "poblaci", "n[uú]mero de (animales|bovinos|cabezas)"),
    "BW (live body weight, kg)"       = c("^bw$", "^lw$", "live_?weight", "live_?wt", "body_?weight", "\\bliveweight", "poids vif", "\\bweight\\b.*\\bkg", "peso vivo", "peso corporal"),
    "MW (mature weight, kg)"          = c("^mw$", "mature_?weight", "mature_?wt", "mature body", "poids adulte", "peso (adulto|madur)"),
    "WG (daily weight gain, kg/d)"    = c("^wg$", "^adg$", "weight_?gain", "daily_?gain", "\\bgain\\b.*\\bkg", "gain de poids", "ganancia", "^gdp$"),
    "Milk (milk yield, kg/d)"         = c("^milk", "milk_?yield", "milk production", "^my\\b", "\\blait\\b", "my_?offtake", "\\bleche\\b", "producci[oó]n de leche"),
    "Fat (milk fat %)"                = c("^fat$", "milk_?fat", "fat content", "fat\\s*\\(", "mati[eè]re grasse", "\\bgrasa\\b", "materia grasa"),
    "pct_pregnant (fraction)"         = c("%\\s*preg", "pct_?preg", "pregnan", "calving rate", "pct_?lactating", "gestant", "pre[nñ]ez", "gestaci"),
    "DE (digestible energy %)"        = c("^de$", "^de\\s*(pct|%|\\()", "digestib", "digestible_?energy", "energ[ií]a digestible"),
    "CP (crude protein %)"            = c("^cp$", "^cp\\s*(pct|%|\\()", "crude_?protein", "diet\\s*cp", "prot[eé]ine brute", "prote[ií]na (bruta|cruda)"),
    "Ym (methane conversion %)"       = c("^ym\\b", "methane_?conv", "\\bym\\b.*(%|percent|factor)"),
    "Bo (methane producing capacity)" = c("^bo\\b", "maximum methane", "methane producing capacity", "\\bb0\\b"),
    "ASH (ash fraction)"              = c("^ash\\b", "ash content", "^ceniza"),
    "UE (urinary energy fraction)"    = c("^ue\\b", "urinary energy", "energ[ií]a urinaria"),
    "Cfi (maintenance coefficient)"   = c("\\bcfi\\b", "net energy for maintenance", "maintenance coefficient"),
    "Ca (activity coefficient)"       = c("\\bca\\b.*(activity|coefficient)", "coefficients? for activity", "activity coefficient"),
    "C (growth coefficient)"          = c("coefficients? for growth", "growth coefficient", "\\b_c\\b"),
    "hours (work hours / draught)"    = c("^hours?$", "work_?hours", "hours.*(work|day)", "draught|draft", "heures"),
    "Tw (winter temperature)"         = c("^tw\\b", "winter temp", "temp[eé]rature.*hiver"),
    "MMS allocation (manure mgmt %)"  = c("^mms\\b", "manure_?management", "manure management system", "syst[eè]me.*gestion", "manure_?system", "mms activity"),
    "MCF (methane conversion factor, manure)" = c("\\bmcf", "methane conversion factor", "factor de conversi[oó]n de metano"),
    "EF3 (direct N2O EF, manure)"     = c("\\bef3\\b", "direct n2o", "emission factor for direct", "\\bfe\\b.*n2o", "n2o.*\\bfe\\b", "factor de emisi[oó]n.*n2o"),
    "Frac_GasMS (volatilisation)"     = c("frac_?gas", "volatilis", "volatiliz", "nh3 or nox", "fracci[oó]n.*volatil"),
    "Frac_LeachMS (leaching)"         = c("frac_?leach", "leaching", "lixiviation", "lixivia"),
    "EF3_PRP (pasture N2O EF)"        = c("ef3_?prp", "pasture.*n2o", "range.*paddock"),
    "EF4 / EF5 (indirect N2O EFs)"    = c("\\bef4\\b", "\\bef5\\b", "indirect n2o"),
    # 2026-10-30: measured intake, which may appear in the template only when
    # the file has it (.translator_drop_unsourced_intake, check C14)
    # By name or by unit (Lolita): MJ per head or per day for GE, except on a
    # net, metabolisable or digestible energy line; kg of dry matter for DMI.
    "GE (gross energy intake)"        = c("^ge$", "^ge\\s*\\(", "gross_?energy", "energ[ií]a bruta", "[eé]nergie brute",
                                          "^(?!.*\\b(net|ne[mgl]?|metaboli[sz]able|me|digestible|de)\\b).*\\bmj\\s*(/|per)\\s*(head|hd|animal|an|day|d)\\b",
                                          "^(?!.*\\b(net|ne[mgl]?|metaboli[sz]able|me|digestible|de)\\b).*\\bmj\\s*(head|hd|an)\\s*-?1"),
    "DMI (dry matter intake)"         = c("^dmi$", "^dmi\\s*\\(", "dry_?matter_?intake", "dry matter intake", "feed intake",
                                          "consumo de materia seca", "ingesti[oó]n de materia seca", "mati[eè]re s[eè]che ing",
                                          "\\bkg\\s*(of\\s*)?dm\\b", "kg\\s*(of\\s*)?dry\\s*matter", "\\bkg\\s*ms\\s*(/|per)")
  )
  found <- character(0); where <- character(0)
  for (sheet in sheets) {
    df <- sheet$preview
    if (is.null(df) || nrow(df) == 0) next
    sheet_label <- if (is.na(sheet$name) || !nzchar(sheet$name %||% "")) "(file)" else sheet$name
    # Header row (Excel row 1) then every cell of every column, remembering
    # the Excel row (data starts at row 2).
    cand <- data.frame(text = tolower(trimws(names(df))), row = 1L, stringsAsFactors = FALSE)
    # 2026-10-23: a sheet without numbers is a notes sheet, and a label on
    # it is not a value. The Zambia notes sheet lists ASH, UE and Tw as
    # MISSING, and the scan reported them present, which then flagged every
    # default as replacing a file value. (A label on a block-header row of
    # a data sheet still counts: the numbers sit on the rows below it.)
    num_mat <- vapply(seq_len(ncol(df)), function(j) {
      x <- df[[j]]
      if (is.numeric(x)) is.finite(x) & !is.na(x)
      else !is.na(x) & grepl("^[-+]?[0-9][0-9.,]*([eE][-+]?[0-9]+)?\\s*%?$", trimws(as.character(x)), perl = TRUE)
    }, logical(nrow(df)))
    if (sum(num_mat) < 1L) next
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
  # meant to see: defeats the point of the higher preview limit.
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
# representation: the model couldn't reliably look up a specific row by
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
# 2026-10-31: many inventory sheets name the parameter only in a heading
# row above a block ("Weight (kg)", then one row per sub-category), so the
# data rows of two blocks look identical. On the Zambia file the AI took the
# feedlot mature-weight range (MoE row 162) for the body-weight row (154),
# eight rows above. Each data row now carries the nearest heading above it
# as `_section`.
#
# No layout rule holds for every file, so a label is written only when the
# heading is unambiguous; a missing label leaves the AI where it was before,
# a wrong one would mislead it. Rows, in order:
# - data row: any cell is a number (or a number stored as text);
# - heading: text only, one distinct value (merged cells repeat it), under
#   a blank row, another heading or the column header;
# - kept inside a block: a row of column names straight under a heading,
#   and a row without values whose first cell matches the same column of
#   the row above (a group with no entry, Zambia MoE rows 35 to 38 and 94);
# - after a blank row the label carries on only for rows with the same
#   columns as the block above (Zambia Coefficients: one block per
#   parameter, a blank between production systems), so a different table
#   without a heading never inherits it;
# - anything else clears the label (a value-less label such as an unused
#   manure system, a heading with its unit in a second cell, a heading
#   straight under data).
# Checked on eight inventory files (Zambia, Zimbabwe, Burkina, Ethiopia,
# Kenya twice, Uganda, Colombia): no row was given a wrong label.
.translator_add_sections <- function(row_vals) {
  numberish <- function(x) is.numeric(x) || is.logical(x) ||
    (is.character(x) && is.finite(suppressWarnings(as.numeric(gsub(",", ".", trimws(x), fixed = TRUE)))))
  current <- NULL
  prev <- "blank"        # the column header row sits above the first row
  last_row <- NULL; last_cols <- NULL; after_blank <- FALSE
  for (i in seq_along(row_vals)) {
    cells <- row_vals[[i]]
    if (!length(cells)) { prev <- "blank"; after_blank <- TRUE; next }
    if (any(vapply(cells, numberish, logical(1)))) {
      if (after_blank && !identical(names(cells), last_cols)) current <- NULL
      if (!is.null(current)) row_vals[[i]] <- c(list(`_section` = current), cells)
      last_row <- cells; last_cols <- names(cells); prev <- "data"; after_blank <- FALSE; next
    }
    vals <- unique(trimws(unlist(cells)))
    if (length(vals) == 1L && nzchar(vals) && prev %in% c("blank", "heading")) {
      current <- gsub(" +", " ", vals); prev <- "heading"; after_blank <- FALSE
      last_cols <- NULL; next
    }
    first <- names(cells)[1]
    continues <- !is.null(last_row) && prev %in% c("data", "valueless", "colnames") &&
      !is.null(last_row[[first]]) && identical(trimws(as.character(last_row[[first]])),
                                               trimws(as.character(cells[[first]])))
    if (prev == "heading" && length(vals) > 1L) { last_row <- cells; prev <- "colnames"; next }
    if (continues && !after_blank) { last_row <- cells; prev <- "valueless"; next }
    current <- NULL; last_row <- cells; prev <- "other"; after_blank <- FALSE
  }
  row_vals
}

# 2026-06-11: 1000-row cap matches .translator_read_upload's ROW_CAP so we
# never silently truncate below what the reader produced.
.translator_table_to_json <- function(df, sheet_name = NA_character_) {
  if (is.null(df) || nrow(df) == 0) {
    return(jsonlite::toJSON(list(
      sheet = sheet_name,
      n_rows = 0L, n_cols = 0L,
      headers = character(0),
      rows = setNames(list(), character(0))
    ), auto_unbox = TRUE, na = "null", pretty = FALSE, digits = NA))
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
  # (sparse keys are already the design: the model looks rows up by number
  # rather than iterating, so omitting blanks changes nothing it relies on).
  nonempty <- vapply(row_vals, function(x) length(x) > 0L, logical(1))
  row_vals <- .translator_add_sections(row_vals)
  rows <- setNames(row_vals[nonempty], row_keys[nonempty])
  # digits = NA (2026-10-31): jsonlite's default of 4 decimals turned
  # 0.00004 into 0 and 0.00042 into 0.0004 before the AI saw the file.
  jsonlite::toJSON(list(
    sheet = sheet_name,
    n_rows = nrow(df),
    n_cols = ncol(df),
    headers = headers,
    rows = rows
  ), auto_unbox = TRUE, na = "null", pretty = FALSE, digits = NA)
}

# Make the API call from the current message stack, stream the reply
# into the browser, then append it to the chat history. All this state
# lives on `state`. Requires `session` so the streaming chunks can be
# pushed to the active browser tab via sendCustomMessage.
# Everything that happens once a reply has arrived, whichever transport
# brought it. Split out of .translator_send() so the synchronous and
# asynchronous paths cannot drift: under async this runs from a later()
# callback rather than inline, which is the only difference.
.translator_handle_result <- function(state, session, resp, stage) {
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

  # Log the spend: Anthropic prompt caching has 90% off on cache reads
  # and a 25% surcharge on cache writes (first turn only).
  # See R/anthropic_client.R::anthropic_cost_usd.
  .translator_log_usage(state, resp, stage = stage,
                        expect_warm = !identical(stage, "explore"))

  # Extract any `template-ready` fenced block from the reply, and only
  # promote it if it actually parses + has the expected shape. If the AI
  # emitted a block but it's malformed (JS-style comments, JS expressions
  # like `4.5*1.032`, `// for brevity not shown` placeholders, or
  # truncated mid-stream), don't promote: but DO tell the user, otherwise
  # they see the AI's confident "template-ready" reply and no download
  # button with no explanation.
  reply_text <- resp$reply
  json_block <- NULL
  if (isTRUE(resp$tool_used)) {
    # Unrequested tool call from a chat turn. Only a `full` piece can stand
    # in for the template; a batch or enumerate piece covers one production
    # system and would download as a truncated inventory.
    piece <- tryCatch(jsonlite::fromJSON(resp$reply, simplifyVector = TRUE),
                      error = function(e) NULL)
    mode  <- .translator_scalar(piece$mode %||% "full")
    if (identical(mode, "full") && .translator_template_is_well_formed(resp$reply)) {
      json_block <- resp$reply
      reply_text <- sprintf("Template generated: %d parameter rows, %d manure rows.",
                            if (is.data.frame(piece$parameters)) nrow(piece$parameters) else 0L,
                            if (is.data.frame(piece$manure_management)) nrow(piece$manure_management) else 0L)
    } else {
      reply_text <- paste0(
        "I started filling the template before you asked (a partial piece, mode '",
        mode, "'). Nothing was kept. When your answers are complete, click ",
        "'Produce template now' and the full template will be built in stages.")
    }
  } else {
    json_block <- .translator_extract_template_ready(resp$reply)
  }
  template_just_ready <- FALSE
  if (!is.null(json_block)) {
    if (.translator_template_is_well_formed(json_block)) {
      state$last_template_json <- json_block
      template_just_ready <- TRUE
      .translator_finalise_template(state, json_block, function(txt)
        session$sendCustomMessage("translatorAppendInfoBubble", txt))
    } else {
      state$last_error <- paste0(
        "The AI tried to emit a template but the format wasn't valid JSON ",
        "(usually because of JS-style comments, math expressions, or ",
        "'for brevity' placeholders inside the block). Click 'Produce ",
        "template now' below: that uses Anthropic's tool-input-schema mode and ",
        "is guaranteed to produce a downloadable .xlsx.")
    }
  }

  # Append assistant message to history. The renderUI for translator_messages
  # will redraw and the streaming bubble (still in the DOM from the JS
  # handler) gets replaced by the freshly-rendered history.
  #
  # Numbered-question display filter: when the AI's reply is dominated
  # by a numbered list (e.g. "Section D: Ambiguities" with 4-10
  # clarification questions wrapped in 200 words of preamble +
  # postamble), set display to just the numbered items. The full reply
  # stays in `content` so the chat-bubble expander surfaces it on
  # demand.
  # 2026-10-22 (WP1): the decisions block goes to the register and the
  # questions to the one-at-a-time loop. The full reply, block included,
  # stays in `content` so the model keeps seeing its own decisions.
  reg_before <- state$register
  decs <- if (!isTRUE(resp$tool_used)) .translator_extract_decisions(reply_text) else NULL
  if (!is.null(decs)) {
    state$register <- translator_register_merge(state$register, decs,
                                                msg_index = length(state$messages) + 1L)
  } else if (identical(stage, "clarify") && length(state$messages) &&
             identical(state$messages[[length(state$messages)]]$role, "user")) {
    # The reply to an answer came without its block: one cheap call asks
    # for the decisions alone (fallback, see translator_register.R).
    tryCatch(.translator_register_summarise_async(state, session),
             error = function(e) message("translator: summariser not started (", conditionMessage(e), ")"))
  }
  reply_vis <- .translator_strip_decisions(reply_text)
  # 2026-10-22 (WP2): the explore reply's list of source categories; a
  # low-confidence mapping becomes a question the user settles before
  # Produce (topic category:<label>).
  srcs <- if (!isTRUE(resp$tool_used)) .translator_extract_source_categories(reply_text) else NULL
  if (!is.null(srcs)) {
    state$source_categories <- srcs
    for (sc in srcs) if (identical(sc$confidence, "low"))
      state$register <- translator_register_add_pending(state$register, paste0("category:", sc$label),
                                                        note = sc$sub_category %||% "")
    reply_vis <- .translator_strip_source_categories(reply_vis)
  }
  # 2026-10-31 (Stage 3): the source_values block (section B). A block in
  # the corrective round replaces the previous one; the Produce observer
  # checks it against the file. 2026-11-01: a block in a continuation is
  # appended to the block it continues (it used to replace it: the Zambia
  # run of 1 November kept the continuation's 77 entries and lost the rest).
  users <- Filter(function(m) identical(m$role, "user"), state$messages)
  already_continued <- length(users) > 0 && identical(users[[length(users)]]$source, "user_continue")
  svals <- if (!isTRUE(resp$tool_used)) .translator_extract_source_values(reply_text) else NULL
  if (!is.null(svals)) {
    if (already_continued && length(state$source_values))
      svals <- .translator_merge_source_values(state$source_values, svals)
    state$source_values <- svals
    reply_vis <- .translator_strip_source_values(reply_vis)
    if (!nzchar(trimws(reply_vis %||% ""))) reply_vis <- sprintf(t("ai_source_values_noted"), length(svals))
    message("translator: source_values block with ", length(svals), " entries")
  }
  # 2026-10-23: a reply cut off by the output length limit is kept as it
  # is and one continuation is requested; its questions, incomplete, are
  # not put to the user, the continuation brings them.
  truncated <- identical(resp$stop_reason, "max_tokens") && !isTRUE(resp$tool_used) && !template_just_ready
  continue_now <- truncated && !already_continued
  qs <- if (!isTRUE(resp$tool_used) && !template_just_ready && !continue_now)
    .translator_question_list(reply_vis) else character(0)
  # 2026-10-22: a question the user has answered in this conversation is
  # not put again (a reply that repeats it would go round in circles), and
  # the closing "please answer the questions" line is dropped: the app
  # puts the questions one at a time.
  if (length(qs)) {
    seen <- .translator_question_seen(qs, .translator_answered_questions(state$messages))
    if (any(seen)) {
      reply_vis <- tryCatch(.translator_strip_question_blocks(reply_vis, qs[seen]), error = function(e) reply_vis)
      qs <- qs[!seen]
    }
  }
  if (length(qs)) {
    state$pending_questions <- lapply(seq_along(qs), function(i)
      list(id = i, kind = "ai", text = qs[i], answer = NULL))
    state$q_index <- 1L
    stripped <- .translator_strip_lead_ins(tryCatch(.translator_strip_question_blocks(reply_vis, qs), error = function(e) reply_vis))
    display_text <- if (nzchar(stripped)) stripped else t("ai_qa_bubble_only_questions")
  } else {
    display_text <- .translator_extract_numbered_questions(reply_vis) %||% reply_vis
  }
  if (!isTRUE(resp$tool_used)) {
    # the orientation lines and the questions; sections A to C go to the expander
    display_text <- .translator_reply_visible(.translator_strip_answer_prompt(display_text))
    if (!nzchar(trimws(display_text))) display_text <- t("ai_q_nothing_open")
  }
  state$messages[[length(state$messages) + 1]] <-
    if (isTRUE(resp$tool_used))
      list(role = "assistant", content = reply_text, display = display_text,
           payload = if (template_just_ready) resp$reply else NULL, ts = .translator_now())
    else
      list(role = "assistant", content = reply_text, display = display_text, ts = .translator_now())

  # 2026-10-22: what the reply settled, in one line; then the questions,
  # one bubble at a time, answered in the normal input.
  .translator_post_recorded(state, reg_before)
  if (length(qs)) .translator_begin_round(state, if (length(qs) == 1L) t("ai_q_notice_one") else sprintf(t("ai_q_notice"), length(qs)))
  if (continue_now) {
    state$messages[[length(state$messages) + 1L]] <-
      list(role = "assistant", content = t("ai_reply_cut"), display = t("ai_reply_cut"), source = "server_notice", ts = .translator_now())
    state$messages[[length(state$messages) + 1L]] <-
      list(role = "user", content = .TRANSLATOR_CONTINUE_TEXT, display = "", source = "user_continue", ts = .translator_now())
    .translator_persist(state)
    # after this callback has finished (it clears `pending` on its way out)
    later::later(function() shiny::withReactiveDomain(session, shiny::isolate(
      tryCatch(.translator_send(state, session, stage = stage),
               error = function(e) message("translator: continuation not sent (", conditionMessage(e), ")")))), 0.2)
  }

  # If a valid template-ready block came through in this reply, post a
  # separate small AI message pointing the user at the green Download
  # button. The previous reply mixed natural-language with the JSON, so
  # the user can miss the "click to download" cue: this dedicated
  # message is the clear next step.
  if (template_just_ready) .translator_append_download_hint(state)

  # (2026-11-01: the year check on the table and the automatic source
  # check run from the observer on {source_values, pending} in the server
  # function, once this callback has cleared `pending`.)

  # Persist so a refresh / reload resumes where we left off.
  .translator_persist(state)
  invisible(NULL)
}

# 2026-10-23: the explore reply carries the full table of values read
# (sections A to C) before its questions; at 16,000 output tokens the
# Zambia file's reply was cut off inside section D twice. 32,000 covers
# it, and a reply that still hits the limit gets one continuation request.
# 2026-10-31: 40,000 (was 32,000): section B is now a JSON block of about
# 500 entries, roughly twice the prose table it replaces.
.TRANSLATOR_CHAT_MAX_TOKENS <- 40000L
# 2026-11-01: the AI review of the flagged checks after assembly is off
# (the user's decision: the checks are for the compiler to settle). The
# code stays in R/translator_review.R.
.TRANSLATOR_AI_REVIEW <- FALSE
.TRANSLATOR_CONTINUE_TEXT <- paste(
  "Your previous reply was cut off by the output length limit. Do not repeat",
  "what you already wrote. If the source_values block was cut, continue it",
  "in a new source_values block: start with the group that was cut (its",
  "header object again, then only the value rows not yet written), then",
  "the remaining groups. Then section C if it was not written, then section",
  "D: every numbered question in full, numbered from 1, then the decisions",
  "block and the source_categories block.")

.translator_send <- function(state, session, stage = "clarify") {
  state$pending <- TRUE
  state$last_error <- NULL
  # One cancellation token per call, minted here rather than in the
  # observers so every entry point gets a fresh flag.
  tok <- .translator_begin_request(session)
  # Set once the call has been handed to the asynchronous transport, which
  # cleans up itself when the result arrives. Every early return below
  # still unwinds through on.exit as before.
  handed_off <- FALSE
  on.exit({
    if (!handed_off) {
      translator_cancel_clear(tok)
      state$pending <- FALSE
    # Always tell the browser to drop the active streaming bubble: the
    # server-side renderUI will replace it (or leave a blank when there's
    # an error). Safe to call even if the bubble was never created.
      tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
                error = function(e) NULL)
    }
  })

  # Cap check.
  if (budget_would_exceed()) {
    # With MONTHLY_BUDGET_CAP_USD set to a sentinel "no cap" value
    # (0/none/unlimited/unset), this branch never fires. Kept as a
    # safety net for the case where an administrator explicitly sets
    # a numeric cap and wants the in-app gate.
    state$last_error <- paste0(
      "The AI translator is temporarily unavailable. ",
      "We've been notified and will restore service shortly: ",
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

  msgs <- anthropic_build_messages(system_prompt, history = .translator_api_history(state$messages))

  # Create an empty bubble client-side, then stream tokens into it. The
  # final assistant message gets written into state$messages at the end so
  # the renderUI for the message history catches up.
  session$sendCustomMessage("translatorStreamStart", "")

  # The tool block rides along on every chat turn (plan F1): the
  # prompt-cache prefix is tools -> system -> messages, so a chat turn
  # without the tool and an emission call with it can never share a cache
  # entry. Since 2026-09-18 the tool_choice is `auto` here as well, the
  # same as the emission calls, because a change of tool_choice between
  # calls invalidates the cached message prefix. Rule 9 tells the model not
  # to call the tool from a chat reply; if it does anyway, the block below
  # promotes a complete piece and explains a partial one.
  # 2026-10-23: the live bubble shows what the finished bubble will show:
  # the orientation lines and section D as it arrives. Sections A to C
  # (the table of every value read) are replaced by a progress line while
  # they stream. The whole visible text is sent each time it changes.
  # 2026-11-01: at most four times a second. The visible-text filter walks
  # the whole accumulated reply; run on every chunk of a 160 KB reply it
  # held the process long enough for the websocket to drop (the Zambia
  # run of 1 November: "disconnected" in the middle of the exploration).
  # The finished bubble comes from on_result, so no final flush is needed.
  stream_acc <- ""; stream_last <- NULL; stream_at <- 0
  on_chunk_cb <- function(text) {
    stream_acc <<- paste0(stream_acc, text)
    # (2026-11-01, evening: once a second; at four times a second the page
    # still lagged while a 361-row table streamed)
    now <- as.numeric(Sys.time())
    if (now - stream_at < 1) return(invisible(NULL))
    stream_at <<- now
    vis <- tryCatch(.translator_reply_visible(stream_acc, live = TRUE), error = function(e) stream_acc)
    if (identical(vis, stream_last)) return(invisible(NULL))
    stream_last <<- vis
    tryCatch(session$sendCustomMessage("translatorStreamSet", vis), error = function(e) NULL)
  }
  # 2026-10-15: this path passed no should_stop at all, so Stop did nothing
  # during an exploration or a chat reply. It only ever worked on the
  # emission calls below.
  stopper <- function() translator_cancelled(tok)

  {
    # Hand off and return. The worker is free from here until Anthropic
    # answers, which is the whole point: a 154-second call no longer locks
    # every other user out of the app.
    handed_off <- TRUE
    anthropic_chat_stream_async(
      msgs,
      on_chunk    = on_chunk_cb,
      should_stop = stopper,
      tools       = anthropic_translator_tools(),
      tool_choice = .ANTHROPIC_TOOL_CHOICE_AUTO,
      max_tokens  = .TRANSLATOR_CHAT_MAX_TOKENS,
      on_result   = function(resp) {
        # withReactiveDomain: this runs from a later() callback, outside
        # any reactive context, so without it the writes to `state` below
        # belong to no session and Shiny never schedules a flush.
        # isolate (2026-10-22): reads of `state` are an error outside a
        # reactive consumer; the domain alone does not provide one.
        shiny::withReactiveDomain(session, shiny::isolate({
          tryCatch(.translator_handle_result(state, session, resp, stage),
                    error = function(e) {
                      state$last_error <- paste0(
                        "The reply arrived but could not be processed (",
                        conditionMessage(e), ").")
                    })
          translator_cancel_clear(tok)
          state$pending <- FALSE
          tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
                    error = function(e) NULL)
        }))
      })
    return(invisible(NULL))
  }

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
      "Your translated template is ready: click the green ",
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
      "tab: review those carefully too. The AI is a draft assistant, ",
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
# The per-batch instruction. Lifted out of the loop so the asynchronous
# chain builds exactly the same prompt; a difference here would silently
# change what the model is asked for.
# The discovery instruction. Extracted alongside .translator_batch_nudge()
# so the asynchronous chain asks for exactly the same thing.
.translator_discovery_request <- function(register = NULL) {
    block <- translator_register_block(register)
    paste(
    "STEP 3 OF 3: EMISSION SETUP. Before producing the filled template,",
    "the in-app handler needs you to enumerate three things from this",
    "conversation:",
    "",
    "  1. The distinct aggregation_level labels for this inventory, in",
    "     snake_case, lowercase (e.g. \"commercial_dairy\",",
    "     \"emergent_dairy\", \"commercial_beef\", \"emergent_beef\",",
    "     \"extensive_trad\"). One entry per production system the user",
    "     has confirmed.",
    "  2. sub_categories_by_level: an object mapping each aggregation_level",
    "     label to the array of sub-category codes it will carry (the",
    "     file's categories for that system, after vocabulary mapping).",
    "  3. The inventory_metadata object: country, region (the continent,",
    "     from the country), year (integer), species (cattle_dairy /",
    "     cattle_non_dairy / cattle_mixed), ipcc_version (2006 /",
    "     2019_refinement), prepared_by (string), notes (string: include",
    "     any caveats from the conversation).",
    "",
    "Call the emit_inventory_piece tool exactly once with mode = 'enumerate'.",
    "Do NOT emit any parameters, manure_management, or time-series rows",
    "here: those come in per-aggregation-level follow-up calls.",
    if (nzchar(block)) paste0("\n", block) else "",
    sep = "\n")
}

.translator_batch_nudge <- function(i, n_levels, level, register = NULL, scope = NULL) {
      block <- translator_register_block(register, level = level)
      out <- sprintf(paste(
      "STEP 3 OF 3: BATCH %d OF %d (aggregation_level = '%s').",
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
      "parameter_timeseries is REQUIRED in this call. When the file has",
      "more than one year column, emit one row per (sub_category, year)",
      "for EVERY year column of the file and EVERY sub-category of '%s',",
      "each year's value read from that year's own column, for every",
      "parameter that changes across the years (a parameter that is the",
      "same in every year may be left blank: the server drops constant",
      "columns). The source_values block lists the inventory-year values",
      "only: the series are read from the file's year columns regardless,",
      "for EVERY sub-category of '%s' whose value changes, including the",
      "groups that share one series with the cows (DE, CP) and the",
      "feedlot weights. A series cell is a cell of the file: copy each",
      "year's value as it is, never extend a trend, smooth, interpolate",
      "or round a series (the server copies the file row over yours and",
      "reports every difference). When the file has one year only,",
      "return [].",
      "",
      "A converted value (milk per lactating day to per head, lb to kg,",
      "L to kg) carries source_value, source_unit, conversion (and",
      "lactation_days or conversion_factor), and source_lower and",
      "source_upper when its bounds were converted with the same factor;",
      "every time-series cell of that parameter is converted the same way",
      "from its own year's value. The server recomputes all of them.",
      "",
      "All other emission rules from the system prompt still apply:",
      "source-of-truth hierarchy (user_file > user_chat >",
      "ipcc_default), data_source on every row, asymmetric bounds where",
      "the file provides them, %d parameters per sub-category (no GE or",
      "DMI row unless the file measured it), biological zeros with",
      "distribution='constant'.",
      sep = "\n"),
          i, n_levels, level, level, level, level, level,
          sum(!PARAM_CATALOGUE$param_tier %in% "optional"))
      # 2026-10-31: the system's rows (Stage 3), the checklist, then the
      # binding decisions. All sit in the nudge, the uncached tail of the
      # request, where the model weighs text most; the decisions stay last.
      sc_txt <- tryCatch(.translator_scope_text(scope), error = function(e) "")
      if (nzchar(sc_txt %||% "")) out <- paste0(out, "\n\n", sc_txt)
      out <- paste0(out, "\n\n", translator_emission_checklist())
      if (nzchar(block)) paste0(out, "\n\n", block) else out
}

# Stage 3 of the emission: merge the per-level pieces, validate, store and
# tell the user. Lifted out of .translator_force_template() so the
# synchronous loop and the asynchronous chain end the same way.
# Returns TRUE when a template was stored, FALSE when the merge was refused
# (2026-10-31; the caller used to test state$last_template_json, which could
# still hold an earlier run's template).
.translator_emit_finish <- function(state, session, inventory_metadata,
                                    parts, agg_levels, info, model_id = NULL, ctx = NULL) {
  # ---- Stage 3: merge + validate + store --------------------------------
  info("Assembling final template...")
  merged <- .translator_merge_batches(.translator_metadata_list(inventory_metadata), parts, agg_levels)
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

  # 2026-10-22: the model id is passed in. This line used to read
  # enum_resp$model, a variable of the caller that is not in scope here, so
  # every batched assembly (more than two production systems) failed with
  # "Assembling the template failed (object 'enum_resp' not found)" from
  # 80dacb1 (15 October) until this fix.
  merged$.model <- model_id %||% .ANTHROPIC_DEFAULT_MODEL
  merged$.register_digest <- translator_register_digest(state$register)
  merged_json <- jsonlite::toJSON(merged, auto_unbox = TRUE, na = "null", null = "null",
                                  dataframe = "rows", digits = NA)

  if (!.translator_template_is_well_formed(merged_json)) {
    # Nothing is cached from a failed merge (plan A3): the parts that
    # produced it must not be replayed on the retry.
    state$batch_parts <- list()
    state$batch_parts_key <- NULL
    .translator_persist(state)
    state$last_error <- paste(
      "Merged template failed the well-formedness check: the batches",
      "returned JSON but the merge produced an empty parameters array.",
      if (length(merge_warnings)) paste(merge_warnings, collapse = " ") else "",
      "Click 'Produce template now' to retry.")
    return(FALSE)
  }

  # Validated: cache every part for a later retry (plan A3, F5). The cache
  # is keyed by the conversation it was validated against (2026-10-22): a
  # later answer from the user, or a new upload, changes the key and the
  # next Produce discards these parts instead of replaying them. Until
  # then an answer given after a first template never reached a production
  # system that was already cached.
  # 2026-10-31: the key is taken from the run's snapshot (ctx), not from the
  # live state: a message typed during the run is not in the parts, so it
  # must not be in their key either. The register is part of the key, so an
  # edited decision without a chat message also invalidates the parts.
  for (p in parts) if (!is.null(p$.requested_aggregation_level))
    state$batch_parts[[p$.requested_aggregation_level]] <- p
  state$batch_parts_key <- tryCatch(
    if (!is.null(ctx)) .translator_emission_key_from(ctx$messages, ctx$register)
    else .translator_emission_key(state), error = function(e) NULL)

  state$last_template_json <- merged_json
  state$last_error <- if (length(merge_warnings)) paste(merge_warnings, collapse = " ") else NULL
  .translator_finalise_template(state, merged_json, info)

  n_params <- if (is.data.frame(merged$parameters)) nrow(merged$parameters) else 0L
  n_mms <- if (is.data.frame(merged$manure_management)) nrow(merged$manure_management) else 0L
  n_ts <- if (is.data.frame(merged$parameter_timeseries)) nrow(merged$parameter_timeseries) else 0L
  if (n_ts == 0L && length(agg_levels) >= 2L) {
    info(paste("Heads up: the AI emitted 0 time-series rows. If your source",
               "file has multi-year activity data, this means the AI didn't",
               "extract it. The downloaded template will still work but the",
               "calculator won't be able to run correlation-based",
               "uncertainty modes. Click 'Produce template now' to retry -",
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
  invisible(TRUE)
}

.translator_force_template <- function(state, session) {
  # 2026-10-22: cached batch parts are reused only when the conversation is
  # the one they were validated against (same user messages, same prompt).
  live_key <- tryCatch(.translator_emission_key(state), error = function(e) NULL)
  if (length(state$batch_parts) && !identical(state$batch_parts_key, live_key)) {
    message("translator: the conversation changed since the cached batches were validated; discarding them")
    state$batch_parts <- list()
    state$batch_parts_key <- NULL
  }
  .translator_force_template_async(state, session)
}

# Legacy single-call force-template path. Used by .translator_force_template()
# above when the discovery stage returns ≤2 aggregation_levels (or fails).
# The three retry loops (parse / coverage / defaults-only) and the sub-
# category strip post-processing are correct on small inventories: kept
# unchanged here.
# Asynchronous emission: the same three stages as
# .translator_force_template(), expressed as a chain so the R worker is
# free between calls instead of held for the whole 5 to 15 minutes.
#
# The stages are unchanged in substance. Discovery enumerates the
# aggregation levels; one batch call per level follows, in order, because
# each one is cached against the conversation prefix and firing them in
# parallel would multiply the cache writes; then the merge.
#
# Order matters and is preserved: run_level(i) only starts after level
# i-1 has been accepted. What changed is that waiting for a level no
# longer blocks anybody else.
.translator_force_template_async <- function(state, session) {
  if (isTRUE(state$pending)) {
    message("translator: a run is already in progress; the new request is ignored")
    return(invisible(NULL))
  }
  state$pending <- TRUE
  state$last_error <- NULL
  # 2026-10-31: a template left from an earlier run must not be delivered
  # as this run's result when the merge fails.
  state$last_template_json <- NULL
  tok <- .translator_begin_request(session)

  # 2026-10-22 (WP6): everything the run reads is taken now. Typing or
  # editing a decision during the run cannot change the prompt mid-run,
  # and the chain does not depend on the session being there.
  ctx <- list(messages = .translator_api_history(state$messages), register = state$register,
              batch_parts = state$batch_parts, user_email = state$user_email,
              source_fp = state$source_fp,
              # Stage 3: what each batch is told about its system
              source_values = state$source_values, source_categories = state$source_categories,
              source_sheets = state$source_sheets)
  job <- translator_job_new(state$user_email,
                            prompt_hash = tryCatch(translator_system_prompt_hash(), error = function(e) NULL),
                            emission_key = state$batch_parts_key)
  job_id <- job$id
  state$job_id <- job_id
  translator_job_register_session(job_id, session)
  translator_job_update(job_id, cancel_token = tok)
  .translator_persist(state)
  # progress bookkeeping (WP5)
  jlevels <- character(0); jest <- NULL; level_i <- 0L; level_bytes <- 0
  done_tokens <- 0; last_push <- Sys.time() - 10
  level_started <- NULL; level_secs <- numeric(0)   # measured durations (2026-10-23)
  level_ratios <- numeric(0)   # actual / estimated tokens of finished systems: calibrates the rest
  final_stage <- FALSE   # assembly and review: the estimator's progress no longer applies
  push_progress <- function(force = FALSE) {
    if (final_stage) return(invisible(NULL))
    if (!force && as.numeric(difftime(Sys.time(), last_push, units = "secs")) < 2) return(invisible(NULL))
    last_push <<- Sys.time()
    el <- if (is.null(level_started)) NA_real_ else as.numeric(difftime(Sys.time(), level_started, units = "secs"))
    sc <- if (length(level_ratios)) min(3, max(0.5, stats::median(level_ratios))) else 1
    pr <- translator_job_progress(jest, level_i, length(jlevels), done_tokens, level_bytes, scale = sc,
                                  level_elapsed = el, level_secs = level_secs)
    translator_job_update(job_id, progress = pr$progress, eta_sec = pr$eta_sec, eta_over = isTRUE(pr$over),
                          level_index = level_i, stage = if (length(jlevels)) "batch" else "discovery")
    tryCatch(session$sendCustomMessage("translatorJobProgress",
                                        list(progress = pr$progress, eta = pr$eta_text, label = pr$label)),
             error = function(e) NULL)
    invisible(NULL)
  }

  # 2026-10-31: while the server assembles, checks and reviews (minutes
  # without a tick from the API), the job file is touched every 60 s so a
  # reload does not mark the job lost.
  heartbeat_on <- FALSE
  heartbeat <- function() {
    if (!heartbeat_on) return(invisible(NULL))
    tryCatch(translator_job_update(job_id), error = function(e) NULL)
    later::later(heartbeat, 60)
    invisible(NULL)
  }
  done <- function() {
    heartbeat_on <<- FALSE
    translator_cancel_clear(tok)
    state$pending <- FALSE
    tryCatch(session$sendCustomMessage("translatorStreamEnd", ""),
              error = function(e) NULL)
    invisible(NULL)
  }
  fail <- function(msg) {
    state$last_error <- msg
    # 2026-10-31: a failed run left no trace in the server log.
    message("translator: job ", job_id, " ended without a template: ", msg)
    jb <- translator_job_read(job_id)
    if (!is.null(jb) && identical(jb$status, "running")) {
      stopped <- grepl("^Stopped", msg)
      translator_job_update(job_id, status = if (stopped) "stopped" else "failed",
                            error = msg, stage_label = msg)
      # nobody is watching: say so by email, as a finished run does
      if (!stopped && is.null(translator_job_open_session(job_id)))
        tryCatch(translator_job_email_failure(job_id, ctx$user_email, msg),
                 error = function(e) message("translator: failure email failed (", conditionMessage(e), ")"))
    }
    done()
  }
  # Every continuation runs from a later() callback, so each one has to
  # re-enter the session's reactive domain before touching `state`.
  # 2026-10-31: an error thrown inside a continuation used to vanish (the
  # transport only logs it): the run stayed "running", the spinner stayed
  # on, no email went out. It now ends the run through fail().
  inseq <- function(expr) shiny::withReactiveDomain(session, shiny::isolate(
    tryCatch(expr, error = function(e) {
      message("translator: continuation failed: ", conditionMessage(e))
      fail(paste0("Internal error: ", conditionMessage(e),
                  ". Click 'Produce template now' to retry; the batches already produced are kept."))
    })))

  if (budget_would_exceed())
    return(fail(paste0("The AI translator is temporarily unavailable. ",
                       "We've been notified and will restore service shortly: ",
                       "please try again later or contact the administrator.")))

  system_prompt <- tryCatch(assemble_translator_system_prompt(), error = function(e) NULL)
  if (is.null(system_prompt))
    return(fail("Couldn't load the translator instructions."))
  tools_sig <- tryCatch(jsonlite::toJSON(anthropic_translator_tools(), auto_unbox = TRUE),
                        error = function(e) "tools")

  total_chars <- 0L
  on_chunk_cb <- function(text) {
    total_chars <<- total_chars + nchar(text)
    tryCatch(session$sendCustomMessage("translatorProgressTick",
                                        list(chars = total_chars)),
              error = function(e) NULL)
  }
  # No later::run_now() here any more. The synchronous path needed it to
  # let a Stop click through a blocked loop; nothing is blocked now, so
  # this is only the typing-bubble keep-alive it was meant to be.
  # 2026-10-22 (WP5): the tick carries the bytes of tool JSON received,
  # which drives the real progress bar through the job file.
  on_tick_cb <- function(n = 0L) {
    level_bytes <<- level_bytes + as.numeric(n %||% 0)
    push_progress()
    tryCatch(session$sendCustomMessage("translatorStreamTick", ""),
              error = function(e) NULL)
  }
  # 2026-10-31: a retried call starts its output again, so the bytes of
  # the abandoned attempt leave the progress count; the user is told.
  on_retry_cb <- function(attempt, delay, why) {
    level_bytes <<- 0
    tryCatch(info(sprintf("The AI's connection was interrupted (%s). Retrying in %d seconds (attempt %d).",
                          why, as.integer(round(delay)), as.integer(attempt) + 1L)),
             error = function(e) NULL)
  }
  info <- function(txt) {
    translator_job_update(job_id, stage_label = txt)
    tryCatch(session$sendCustomMessage("translatorAppendInfoBubble", txt),
              error = function(e) NULL)
  }
  stopper <- function() translator_cancelled(tok)

  file_was_uploaded <- any(vapply(ctx$messages, function(m)
    identical(m$source, "server_upload") ||
      grepl("Parameter labels DETECTED IN THIS FILE", m$content %||% "", fixed = TRUE),
    logical(1)))
  count_user_rows <- function(pj) {
    if (is.null(pj) || !is.data.frame(pj$parameters)) return(0L)
    ds <- pj$parameters$data_source
    if (is.null(ds)) return(0L)
    sum(grepl("^user[_ ]?(file|chat)$", ds, ignore.case = TRUE), na.rm = TRUE)
  }

  # ---- Stage 3 entry -----------------------------------------------------
  finish <- function(inventory_metadata, parts, agg_levels, model_id = NULL) {
    final_stage <<- TRUE
    translator_job_update(job_id, stage = "assemble",
                          stage_label = "Assembling the template and running the checks (1 to 3 minutes)",
                          progress = 0.94)
    # 2026-10-29: the call stack is kept when assembly fails, in the server
    # log and in the job record, because "$ operator is invalid for atomic
    # vectors" on its own said nothing about where (a three-system run).
    stack_txt <- NULL
    heartbeat_on <<- TRUE; heartbeat()
    ok <- tryCatch(withCallingHandlers({
                     isTRUE(.translator_emit_finish(state, session, inventory_metadata,
                                                    parts, agg_levels, info, model_id = model_id,
                                                    ctx = ctx)) },
                     error = function(e) {
                       sc <- tryCatch(sys.calls(), error = function(.e) NULL)
                       if (!is.null(sc)) stack_txt <<- paste(utils::tail(vapply(sc, function(cl)
                         substr(paste(deparse(cl), collapse = " "), 1, 160), character(1)), 25), collapse = "
  ")
                     }),
                   error = function(e) {
                     state$last_error <- paste0("Assembling the template failed (",
                                                conditionMessage(e), ").")
                     message("translator: assembly failed: ", conditionMessage(e),
                             if (!is.null(stack_txt)) paste0("
  ", stack_txt) else "")
                     translator_job_update(job_id, status = "failed", error = state$last_error)
                     FALSE })
    if (ok && !is.null(state$last_template_json)) {
      # 2026-10-30: before the files are delivered, the flagged items go
      # back to the AI once (R/translator_review.R): it corrects them from
      # the file or explains why they are not errors.
      # 2026-11-01: switched off (.TRANSLATOR_AI_REVIEW). The user's
      # decision: the checks are listed for the compiler, who settles them
      # (their file can be the thing that is wrong); the files are
      # delivered right after the checks. The last live review was cut at
      # its output limit trying to rewrite whole series and applied nothing.
      wrapped <- FALSE
      wrap_up <- function() {
        if (wrapped) return(invisible(NULL))
        wrapped <<- TRUE
        .translator_persist(state)
        tryCatch(translator_job_finish(job_id, state, session),
                 error = function(e) message("translator: job finish failed (", conditionMessage(e), ")"))
        done()
      }
      if (!isTRUE(.TRANSLATOR_AI_REVIEW)) return(wrap_up())
      return(tryCatch(
        .translator_review_async(state, system_prompt, ctx$messages, ctx$register,
                                 on_chunk_cb, on_tick_cb, stopper, info, inseq, job_id,
                                 on_done = wrap_up),
        error = function(e) {
          message("translator: review step failed (", conditionMessage(e), "); delivering the template as it is")
          wrap_up()
        }))
    } else if (ok) {
      translator_job_update(job_id, status = "failed", error = state$last_error %||% "no template produced")
    } else if (!is.null(state$last_error)) {
      # the merge refused the parts (.translator_emit_finish returned FALSE)
      translator_job_update(job_id, status = "failed", error = state$last_error)
    }
    done()
  }

  # ---- Stage 2: one level at a time -------------------------------------
  run_levels <- function(agg_levels, inventory_metadata, model_id = NULL, subcats_by_level = NULL) {
    subcats_by_level <- subcats_by_level %||% list()
    parts <- vector("list", length(agg_levels))
    step <- function(i) {
      if (i > length(agg_levels)) return(finish(inventory_metadata, parts, agg_levels, model_id))
      level <- agg_levels[i]

      if (!is.null(ctx$batch_parts[[level]])) {
        info(sprintf("Reusing %d of %d: %s (validated on a previous attempt)...",
                     i, length(agg_levels), level))
        parts[[i]] <<- ctx$batch_parts[[level]]
        return(step(i + 1L))
      }

      level_i <<- i; level_bytes <<- 0; level_started <<- Sys.time()
      push_progress(TRUE)
      info(sprintf("Processing %d of %d: %s...", i, length(agg_levels), level))
      total_chars <<- 0L
      # 2026-10-31 (Stage 3): the file's rows and the expected
      # sub-categories of this system, from the run's snapshot
      scope <- tryCatch(translator_level_rows(level, ctx$source_values, ctx$source_categories, ctx$source_sheets,
                                             expected_subcats = subcats_by_level[[level]]),
                        error = function(e) NULL)
      batch_msgs <- anthropic_build_messages(
        system_prompt, history = ctx$messages,
        new_user_message = .translator_batch_nudge(i, length(agg_levels), level, ctx$register, scope = scope))

      accept_raw <- function(batch_parsed) {
        batch_parsed$.requested_aggregation_level <- level
        parts[[i]] <<- batch_parsed
        # what this system actually cost, for the estimate of the rest
        tk <- level_bytes / 3.6
        done_tokens <<- done_tokens + (if (!is.null(jest)) max(tk, 0) else 0)
        if (!is.null(level_started))
          level_secs <<- c(level_secs, as.numeric(difftime(Sys.time(), level_started, units = "secs")))
        est_lv <- suppressWarnings(as.numeric(jest$per_level_tokens[[level]] %||% NA))
        if (is.finite(est_lv) && est_lv > 0 && tk > 0) level_ratios <<- c(level_ratios, tk / est_lv)
        act <- translator_job_read(job_id)$actual %||% list()
        act$per_level_tokens[[level]] <- round(tk)
        translator_job_update(job_id, actual = act)
        push_progress(TRUE)
        step(i + 1L)
      }
      # 2026-10-22 (WP1 step 4): a batch that contradicts a decision in the
      # register is re-emitted once with the violated decision quoted; if it
      # still contradicts, the better of the two is kept and the decision is
      # marked "not applied" (shown above the download and in the checks).
      # 2026-10-31 (Stage 3): the batch's sub-categories against the
      # expected set; one re-emit on a mismatch, the better piece kept.
      accept_scope <- function(batch_parsed, retried = FALSE) {
        chk_s <- tryCatch(translator_level_subcats_check(batch_parsed, scope), error = function(e) NULL)
        if (is.null(scope) || is.null(chk_s) || isTRUE(chk_s$ok) || retried) {
          if (!is.null(chk_s) && !isTRUE(chk_s$ok))
            info(sprintf("Batch %s still has %d sub-categories where %d were expected; kept as it is and listed in the checks.",
                         level, chk_s$found, chk_s$expected))
          return(accept(batch_parsed))
        }
        message("translator: batch '", level, "' sub-categories differ from the expected set (missing: ",
                chk_s$missing, "; extra: ", chk_s$extra, "); re-emitting once")
        info(sprintf("Batch %s came back with %d sub-categories where %d were expected; asking the AI once more...",
                     level, chk_s$found, chk_s$expected))
        retry_msgs <- c(batch_msgs, list(list(role = "user", content = .translator_subcat_rejection(level, chk_s))))
        anthropic_chat_batch_template_force_async(
          retry_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb, should_stop = stopper, on_retry = on_retry_cb,
          on_result = function(rr) inseq({
            best <- batch_parsed
            if (is.null(rr$error)) {
              .translator_log_usage(state, rr, stage = "retry_scope", expect_warm = TRUE)
              rp <- tryCatch(jsonlite::fromJSON(rr$reply, simplifyVector = TRUE), error = function(e) NULL)
              if (is.null(.translator_validate_piece(rp, "batch"))) {
                c2 <- tryCatch(translator_level_subcats_check(rp, scope), error = function(e) NULL)
                n_bad <- function(c_) if (is.null(c_)) Inf else length(strsplit(c_$missing, ", ")[[1]][nzchar(strsplit(c_$missing, ", ")[[1]])]) +
                  length(strsplit(c_$extra, ", ")[[1]][nzchar(strsplit(c_$extra, ", ")[[1]])])
                if (n_bad(c2) < n_bad(chk_s)) best <- rp
              }
            }
            accept_scope(best, retried = TRUE)
          }))
      }
      accept <- function(batch_parsed, retried = FALSE) {
        chk <- tryCatch(translator_register_check(ctx$register, batch_parsed, level),
                        error = function(e) NULL)
        bad <- if (is.null(chk) || !nrow(chk)) NULL else chk[!chk$ok & chk$hard, , drop = FALSE]
        if (!is.null(chk) && nrow(chk))
          for (tp in unique(chk$topic[chk$ok]))
            if (is.null(bad) || !tp %in% bad$topic)
              state$register <- translator_register_mark(state$register, tp, TRUE)
        if (is.null(bad) || !nrow(bad)) return(accept_raw(batch_parsed))
        if (retried) {
          for (k in seq_len(nrow(bad)))
            state$register <- translator_register_mark(state$register, bad$topic[k], FALSE,
                                                       sprintf("%s: %s", bad$where[k], bad$found[k]))
          info(sprintf("The AI did not apply a decision for %s after one retry (%s); it is listed above the download.",
                       level, paste(unique(bad$topic), collapse = ", ")))
          return(accept_raw(batch_parsed))
        }
        message("translator: batch '", level, "' contradicts the register (",
                paste(unique(bad$topic), collapse = ", "), "); re-emitting once")
        info(sprintf("Batch %s did not follow a decision (%s); asking the AI once more...",
                     level, paste(unique(bad$topic), collapse = ", ")))
        retry_msgs <- c(batch_msgs, list(list(role = "user",
                                              content = .translator_decision_rejection(bad, level))))
        anthropic_chat_batch_template_force_async(
          retry_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb, should_stop = stopper,
          on_result = function(rr) inseq({
            best <- batch_parsed
            if (is.null(rr$error)) {
              .translator_log_usage(state, rr, stage = "retry_decision", expect_warm = TRUE)
              rp <- tryCatch(jsonlite::fromJSON(rr$reply, simplifyVector = TRUE), error = function(e) NULL)
              if (is.null(.translator_validate_piece(rp, "batch"))) {
                chk2 <- tryCatch(translator_register_check(ctx$register, rp, level), error = function(e) NULL)
                n2 <- if (is.null(chk2) || !nrow(chk2)) 0L else sum(!chk2$ok & chk2$hard)
                if (n2 < nrow(bad)) best <- rp
              }
            }
            accept(best, retried = TRUE)
          }))
      }

      .translator_memo_call_async(batch_msgs, tools_sig,
        start = function(cb) anthropic_chat_batch_template_force_async(
          batch_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb,
          should_stop = stopper, on_result = cb, on_retry = on_retry_cb),
        mode = "batch",
        on_result = function(batch_resp) inseq({
          if (isTRUE(batch_resp$stopped) || translator_cancelled(tok))
            return(fail(sprintf(
              "Stopped at your request during batch %d of %d (%s). The %d batch(es) already produced are kept and will not be re-billed; click 'Produce template now' to carry on from there.",
              i, length(agg_levels), level, length(state$batch_parts))))
          if (!is.null(batch_resp$error))
            return(fail(sprintf(
              "Batch %d of %d (%s) failed: %s. Click 'Produce template now' to retry, the %d batch(es) that already succeeded are kept and won't be re-billed.",
              i, length(agg_levels), level, batch_resp$error, length(state$batch_parts))))
          if (!isTRUE(batch_resp$memo_hit))
            .translator_log_usage(state, batch_resp, stage = "batch", expect_warm = TRUE)

          batch_parsed <- tryCatch(jsonlite::fromJSON(batch_resp$reply, simplifyVector = TRUE),
                                   error = function(e) NULL)
          bad <- .translator_validate_piece(batch_parsed, "batch")
          if (!is.null(bad)) {
            .translator_memo_forget(batch_msgs, tools_sig)
            # 2026-10-31: a reply cut at the output limit is named as such;
            # repeating the identical request would cut at the same place.
            if (isTRUE(batch_resp$truncated)) {
              # 2026-11-01 (Stage 4.3): the system is asked again in two
              # halves of its sub-categories, each in its own call; the two
              # pieces are merged and go through the same checks.
              subs <- as.character(scope$sub_categories %||% character(0))
              if (length(subs) >= 2L && !isTRUE(batch_resp$split)) {
                h1 <- subs[seq_len(ceiling(length(subs) / 2))]; h2 <- setdiff(subs, h1)
                info(sprintf("Batch %d (%s) was cut at the AI's output limit; asking for it in two halves (%d and %d sub-categories)...",
                             i, level, length(h1), length(h2)))
                message("translator: batch '", level, "' cut at max_tokens; split into ", length(h1), " + ", length(h2), " sub-categories")
                half_msgs <- function(h) c(batch_msgs, list(list(role = "user", content = paste0(
                  "SPLIT CALL: this call covers ONLY these sub-categories of '", level, "': ", paste(h, collapse = ", "),
                  ". Emit their parameters, manure_management and parameter_timeseries rows and nothing for the other sub-categories ",
                  "(they come in a separate call). mode = 'batch', aggregation_level = '", level, "'."))))
                merge_halves <- function(a, b) {
                  rb <- function(x, y) {
                    if (!is.data.frame(x) || !nrow(x)) return(y); if (!is.data.frame(y) || !nrow(y)) return(x)
                    for (cl in setdiff(names(x), names(y))) y[[cl]] <- NA
                    for (cl in setdiff(names(y), names(x))) x[[cl]] <- NA
                    rbind(x, y[names(x)])
                  }
                  out <- a
                  for (nm in c("parameters", "manure_management", "parameter_timeseries", "server_corrections"))
                    out[[nm]] <- rb(a[[nm]], b[[nm]])
                  out
                }
                anthropic_chat_batch_template_force_async(
                  half_msgs(h1), on_chunk = on_chunk_cb, on_tick = on_tick_cb, should_stop = stopper,
                  on_result = function(r1) inseq({
                    if (!is.null(r1$error) || isTRUE(r1$stopped))
                      return(fail(sprintf("Batch %d (%s), first half: %s.", i, level, r1$error %||% "stopped")))
                    .translator_log_usage(state, r1, stage = "batch_split", expect_warm = TRUE)
                    p1 <- tryCatch(jsonlite::fromJSON(r1$reply, simplifyVector = TRUE), error = function(e) NULL)
                    anthropic_chat_batch_template_force_async(
                      half_msgs(h2), on_chunk = on_chunk_cb, on_tick = on_tick_cb, should_stop = stopper,
                      on_result = function(r2) inseq({
                        if (!is.null(r2$error) || isTRUE(r2$stopped))
                          return(fail(sprintf("Batch %d (%s), second half: %s.", i, level, r2$error %||% "stopped")))
                        .translator_log_usage(state, r2, stage = "batch_split", expect_warm = TRUE)
                        p2 <- tryCatch(jsonlite::fromJSON(r2$reply, simplifyVector = TRUE), error = function(e) NULL)
                        if (is.null(p1) || is.null(p2))
                          return(fail(sprintf("Batch %d (%s): a half of the split call could not be read.", i, level)))
                        merged <- merge_halves(p1, p2)
                        bad2 <- .translator_validate_piece(merged, "batch")
                        if (!is.null(bad2)) return(fail(sprintf("Batch %d (%s) came back incomplete after the split (%s).", i, level, bad2)))
                        accept_scope(merged)
                      }))
                  }))
                return(invisible(NULL))
              }
              return(fail(sprintf(
                "Batch %d (%s) was cut at the AI's output limit (%s). This production system has too many rows for one call; please tell the administrator.",
                i, level, bad)))
            }
            return(fail(sprintf(
              "Batch %d (%s) came back incomplete (%s). Click 'Produce template now' to retry: the %d batch(es) that already succeeded are kept and won't be re-billed.",
              i, level, bad, length(state$batch_parts))))
          }

          # Defaults-only retry (plan C1): one more call, so one more
          # continuation rather than an inline second request.
          if (file_was_uploaded && count_user_rows(batch_parsed) == 0L &&
              is.data.frame(batch_parsed$parameters) && nrow(batch_parsed$parameters) > 0) {
            message("translator: batch '", level, "' has ZERO user_file rows; retrying once")
            info(sprintf("Batch %s came back with catalogue defaults only; asking the AI to use the file values...", level))
            retry_msgs <- c(batch_msgs, list(list(role = "user", content = paste0(
              "REJECTED: every parameters row you emitted for '", level, "' is tagged ",
              "data_source = 'ipcc_default' or lacks the tag, yet the uploaded file ",
              "carries values for this production system. Re-emit the batch for '",
              level, "' now: for every parameter present in the file use the file's ",
              "value with data_source = 'user_file' (and its bounds if given), use ",
              "catalogue defaults ONLY for parameters the file does not supply, and ",
              "biological_zero where it applies. Same tool, mode = 'batch', same ",
              "aggregation_level."))))
            return(anthropic_chat_batch_template_force_async(
              retry_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb,
              should_stop = stopper,
              on_result = function(retry_resp) inseq({
                if (is.null(retry_resp$error)) {
                  .translator_log_usage(state, retry_resp, stage = "retry_defaults_only",
                                        expect_warm = TRUE)
                  rp <- tryCatch(jsonlite::fromJSON(retry_resp$reply, simplifyVector = TRUE),
                                 error = function(e) NULL)
                  if (is.null(.translator_validate_piece(rp, "batch")) &&
                      count_user_rows(rp) > 0L)
                    batch_parsed <- rp
                }
                accept_scope(batch_parsed)
              })))
          }
          accept_scope(batch_parsed)
        }))
    }
    step(1L)
  }

  # ---- Stage 1: discovery ------------------------------------------------
  info("Analysing your inventory structure...")
  discovery_request <- .translator_discovery_request(ctx$register)
  discovery_msgs <- anthropic_build_messages(
    system_prompt, history = ctx$messages,
    new_user_message = discovery_request)

  .translator_memo_call_async(discovery_msgs, tools_sig,
    start = function(cb) anthropic_chat_enumerate_aggregation_levels_async(
      discovery_msgs, on_chunk = on_chunk_cb, on_tick = on_tick_cb,
      should_stop = stopper, on_result = cb, on_retry = on_retry_cb),
    mode = "enumerate",
    on_result = function(enum_resp) inseq({
      if (isTRUE(enum_resp$stopped) || translator_cancelled(tok))
        return(fail(enum_resp$error %||%
          "Stopped at your request. Nothing was produced from this call."))
      # 2026-10-28: one path for every file. A failed discovery (after the
      # transport's own retries) ends the run with the error instead of
      # switching to the single-request path, which held the process for
      # everyone until it finished.
      if (!is.null(enum_resp$error)) {
        message("translator: discovery call failed (", enum_resp$error, ")")
        return(fail(enum_resp$error))
      }
      if (!isTRUE(enum_resp$memo_hit))
        .translator_log_usage(state, enum_resp, stage = "enumerate", expect_warm = TRUE)

      enum_parsed <- tryCatch(jsonlite::fromJSON(enum_resp$reply, simplifyVector = TRUE),
                              error = function(e) NULL)
      bad <- .translator_validate_piece(enum_parsed, "enumerate")
      if (!is.null(bad)) {
        message("translator: discovery reply incomplete (", bad, ")")
        .translator_memo_forget(discovery_msgs, tools_sig)
        return(fail(paste0("The first step (reading the structure of the inventory) came back incomplete: ",
                           bad, ". Please click Produce again.")))
      }
      agg_levels <- unique(trimws(as.character(enum_parsed$aggregation_levels)))
      agg_levels <- agg_levels[!is.na(agg_levels) & nzchar(agg_levels)]
      # A file with no named production system is one system.
      if (!length(agg_levels)) agg_levels <- "national"
      # 2026-10-22 (WP1 step 4): year, species and edition come from the
      # register when the user decided them; corrected here, no re-call.
      enum_parsed$inventory_metadata <- .translator_metadata_list(enum_parsed$inventory_metadata)
      fix <- tryCatch(translator_register_apply_metadata(ctx$register, enum_parsed$inventory_metadata),
                      error = function(e) NULL)
      if (!is.null(fix)) {
        enum_parsed$inventory_metadata <- fix$metadata
        state$register <- fix$register
        if (length(fix$corrections))
          message("translator: discovery metadata corrected from the register: ",
                  paste(fix$corrections, collapse = ", "))
      }
      # 2026-10-22 (WP5): the estimate, from the systems found and the
      # usage history; the job file carries it for the progress panel.
      jlevels <<- agg_levels
      jest <<- tryCatch(translator_job_estimate(agg_levels, enum_parsed$sub_categories_by_level,
                                                tryCatch(usage_log_read(), error = function(e) NULL),
                                                n_years = length(ctx$source_fp$year_sums %||% list())),
                        error = function(e) NULL)
      translator_job_update(job_id, levels = as.list(agg_levels), estimate = jest, stage = "batch")
      cached_levels <- intersect(agg_levels, names(ctx$batch_parts))
      fresh_levels  <- setdiff(agg_levels, cached_levels)
      if (length(cached_levels) > 0)
        message(sprintf("translator: reusing %d validated batch(es): %s",
                        length(cached_levels), paste(cached_levels, collapse = ", ")))
      message(sprintf("translator: dispatching %d force-template call(s): %s",
                      length(fresh_levels), paste(fresh_levels, collapse = ", ")))
      run_levels(agg_levels, enum_parsed$inventory_metadata, enum_resp$model,
                 subcats_by_level = tryCatch(as.list(enum_parsed$sub_categories_by_level), error = function(e) list()))
    }))

  invisible(NULL)
}

# (2026-11-01, Stage 4.6: the synchronous emission path that lived here, .translator_force_template_single, was removed; every run goes through .translator_force_template_async.)

# Write the AI's template-ready JSON to an .xlsx that LOOKS LIKE THE
# OFFICIAL INPUT TEMPLATE: same column ordering, header colours,
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
#: acceptable tradeoff for now.
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
  # index at level 1" with no clue where it came from: local repros
  # of the same input data succeeded. The withCallingHandlers below
  # snapshots sys.calls() at the throw site BEFORE control unwinds to
  # the tryCatch's error handler, so the next failure pinpoints the
  # exact line. Kept in permanently: silent on the happy path,
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
              ": falling back to simple xlsx.\n",
              "Writer call stack (innermost last):\n  > ",
              writer_trace %||% "(no stack captured)")
      FALSE
    }
  )
  if (!ok) .translator_write_simple_xlsx(parsed, file_path)
  invisible(NULL)
}

# Primary writer: overlays AI values onto the official blank template.
.translator_write_official_template <- function(parsed, file_path) {
  if (!exists("generate_template_openxlsx") || !exists("PARAM_CATALOGUE"))
    stop("template-generation helpers not available")

  # Defense-in-depth: if the merge produced list-of-records (heterogeneous
  # schema across batches), coerce to data.frames here too: the writer's
  # is.data.frame() gates would otherwise drop those sheets silently.
  parsed$parameters           <- .translator_records_to_df(parsed$parameters)
  parsed$manure_management    <- .translator_records_to_df(parsed$manure_management)
  parsed$parameter_timeseries <- .translator_records_to_df(parsed$parameter_timeseries)

  ipcc_version <- .translator_metadata_list(parsed$inventory_metadata)$ipcc_version %||% "2019_refinement"
  ipcc_short <- if (grepl("2019|refinement", ipcc_version, ignore.case = TRUE))
    "2019_refinement" else "2006"

  tmp_blank <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_blank), add = TRUE)
  generate_template_openxlsx(tmp_blank, include_example = FALSE,
                              ipcc_version = ipcc_short)

  wb <- openxlsx::loadWorkbook(tmp_blank)

  # ---------- Inventory_Metadata --------------------------------------------
  md <- .translator_metadata_list(parsed$inventory_metadata)
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
  stamp <- .translator_stamp_text(parsed$.model, digest = parsed$.register_digest)
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
        # (sub_category, parameter): which silently contaminated rows
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

        # For sub-category blocks AFTER the first, the row is blank: we
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
        #   9  = lower_bound (catalogue reference: display only)
        #   10 = upper_bound (catalogue reference: display only)
        #   11 = distribution
        #   12 = lower (asymmetric override: what the simulator reads)
        #   13 = upper (asymmetric override: what the simulator reads)
        #   16 = data_source
        #
        # The AI's bounds MUST go into cols 12/13 so the simulator picks
        # them up. Previously they were written to 9/10 (the catalogue
        # display columns) and the simulator saw NA in 12/13: which the
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
        # 2026-10-30: a GE or DMI row the AI wrote with 0 (it does so since
        # about 22 October, tagged ipcc_default or biological_zero) is a gap,
        # not a measurement: written blank like an omitted row, below.
        if (!is.null(ai) && identical(PARAM_CATALOGUE$param_tier[i], "optional")) {
          ai_v <- suppressWarnings(as.numeric(.translator_scalar(ai$mean %||% ai$value)))
          if (length(ai_v) != 1L || is.na(ai_v) || ai_v <= 0) ai <- NULL
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
          # 2026-10-22 (WP3, C9): a value with no spread takes the catalogue's
          # range, and a missing distribution the catalogue's suggested one
          # (per sub-category where the resolver has one). Since 2026-10-30
          # the catalogue has a range only for the inputs with a defensible
          # default; for every other input the range stays blank and the app
          # fills a placeholder, tagged in data_source. Both cases are listed in the checks.
          num0 <- function(x) suppressWarnings(as.numeric(x))
          is_const <- identical(tolower(as.character(v_dist)), "constant")
          if (!is_const && !is.na(num0(v_mean))) {
            rs9 <- tryCatch(resolve_subcat_default(sub_cat, p_name, ipcc_version),
                            error = function(e) NULL)
            if (is.na(v_lo) && is.na(v_hi) && is.na(num0(v_unc)))
              v_unc <- .translator_scalar(rs9$uncertainty_pct %||% PARAM_CATALOGUE$suggested_uncertainty_pct[i])
            if (is.na(v_dist) || !nzchar(as.character(v_dist)))
              v_dist <- .translator_scalar(rs9$distribution %||% PARAM_CATALOGUE$suggested_distribution[i])
          }
          # 2026-10-30 (later): no range and no defensible default: a
          # placeholder range, tagged in data_source so the app, the report
          # and the exports can tell it from the country's own.
          ph_tag <- FALSE
          if (!is_const && is.finite(num0(v_mean)) && num0(v_mean) != 0 &&
              is.na(v_lo) && is.na(v_hi) && is.na(num0(v_unc)) &&
              is.null(default_range_for(p_name, num0(v_mean)))) {
            ph <- placeholder_range_for(p_name, num0(v_mean))
            if (!is.null(ph)) {
              if (!is.na(ph$pct)) v_unc <- ph$pct else { v_lo <- ph$lower; v_hi <- ph$upper }
              ph_tag <- TRUE
            }
          }
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
          .put_param(16, if (ph_tag) paste0(ai$data_source %||% "AI translator", "; ", .PLACEHOLDER_TAG)
                         else ai$data_source %||% "AI translator")
        } else if (identical(PARAM_CATALOGUE$param_tier[i], "optional")) {
          # Measured-intake parameters (GE, DMI) are the one kind of gap that
          # must STAY a gap. A blank cell is the signal that means "derive
          # gross energy from the energy balance", which is the correct and
          # overwhelmingly common answer. Backfilling them the way every other
          # parameter is backfilled would assert a measured intake the user
          # never made, and silently bypass the IPCC energy chain for every
          # sub-category of every AI-produced workbook.
          #
          # Everything EXCEPT the value and its bounds is still written: the
          # row stays present, self-explanatory and uniform with the other
          # blocks (which also keeps audit F31's row-count arithmetic
          # correct), and it carries a valid distribution so upload validation
          # does not reject it with "Invalid distribution:". The suggested
          # uncertainty is written too, so that a user who DOES fill the value
          # in later already has a sensible shape around it. Only cols 7
          # (value), 9/10 (bound overrides) and 12/13 (lower/upper) stay
          # empty, and a blank value is precisely the "not supplied" signal.
          .put_param(8,  PARAM_CATALOGUE$suggested_uncertainty_pct[i])
          .put_param(11, PARAM_CATALOGUE$suggested_distribution[i])
          .put_param(14, PARAM_CATALOGUE$param_type[i])
          .put_param(15, PARAM_CATALOGUE$ipcc_ref[i])
        } else {
          # Gap parameter: the AI/overlay didn't supply this (parameter,
          # sub-category). Backfill the IPCC catalogue default so the row is a
          # valid "ipcc_default" entry instead of a blank cell that upload
          # validation rejects with "Invalid distribution:".
          #
          # Why fill EVERY block (not just k>1): the blank-template skeleton
          # only pre-fills the FIRST sub-category block, and for asymmetric
          # params it writes an Excel FORMULA into the simulator-read cols
          # 12/13 that carries no cached value until the file is opened in
          # Excel: so an unopened file would sample NA bounds. Writing
          # explicit NUMBERS here (idempotent for block 1) makes all blocks
          # uniform and simulator-safe: value + uncertainty% + distribution,
          # plus concrete lower/upper: asymmetric params take the catalogue's
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
          # 2026-10-30 (later): a placeholder where there is no default range
          if (is.na(unc) && is.na(lb) && is.na(ub) && is.finite(suppressWarnings(as.numeric(dv))) &&
              !identical(tolower(as.character(dst)), "constant")) {
            ph <- placeholder_range_for(p_name, as.numeric(dv))
            if (!is.null(ph)) {
              if (!is.na(ph$pct)) unc <- ph$pct else { lb <- ph$lower; ub <- ph$upper }
              src <- paste0(src, "; ", .PLACEHOLDER_TAG)
            }
          }
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
      # Fraction bounds: col 6/7/8. Sampled by the simulator if present;
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

      # 2026-10-30: a blank range takes the IPCC range only where IPCC gives
      # one for this system's default value: EF3 a factor of 2 (IPCC 2019
      # Table 10.21, footnote 24) and the Table 10.22 fractions. MCF has no
      # IPCC range, so it gets none. Any other blank range stays blank; the
      # app lists it as Missing until the user adds one. (Replaces the
      # 2026-10-22 project assumptions: MCF +/-25% and EF3 x2 for any value.)
      numm <- function(x) suppressWarnings(as.numeric(.translator_scalar(x)))
      mcf_v <- numm(mcf_in %||% d_mcf)
      mcf_lo <- numm(mm$lower_mcf[i]); mcf_hi <- numm(mm$upper_mcf[i])
      mcf_dist <- .translator_scalar(mm$distribution_mcf[i])
      ef3_v <- numm(mm$ef3[i] %||% mm$EF3[i] %||% d_ef3)
      ef3_lo <- numm(mm$lower_ef3[i]); ef3_hi <- numm(mm$upper_ef3[i])
      ef3_dist <- .translator_scalar(mm$distribution_ef3[i])
      if (is.finite(ef3_v) && is.na(ef3_lo) && is.na(ef3_hi)) {
        r3 <- manure_default_range(mms_id, "EF3", ef3_v)
        if (!is.null(r3)) {
          ef3_lo <- r3$lower; ef3_hi <- r3$upper
          if (is.na(ef3_dist) || !nzchar(ef3_dist)) ef3_dist <- "lognormal"
        }
      }
      gas_v  <- numm(mm$Frac_GasMS_pct[i] %||% mm$frac_gasms_pct[i] %||% mm$Frac_GasMS[i] %||% d_gas)
      gas_lo <- numm(mm$lower_frac_gas[i]); gas_hi <- numm(mm$upper_frac_gas[i])
      if (is.finite(gas_v) && is.na(gas_lo) && is.na(gas_hi)) {
        rg <- manure_default_range(mms_id, "Frac_GasMS_pct", gas_v)
        if (!is.null(rg)) { gas_lo <- rg$lower; gas_hi <- rg$upper }
      }
      lea_v  <- numm(mm$Frac_LeachMS_pct[i] %||% mm$frac_leachms_pct[i] %||% mm$Frac_LeachMS[i] %||% d_leach)
      lea_lo <- numm(mm$lower_frac_leach[i]); lea_hi <- numm(mm$upper_frac_leach[i])
      if (is.finite(lea_v) && is.na(lea_lo) && is.na(lea_hi)) {
        rl <- manure_default_range(mms_id, "Frac_LeachMS_pct", lea_v)
        if (!is.null(rl)) { lea_lo <- rl$lower; lea_hi <- rl$upper }
      }
      .put_mm(9,  mcf_in %||% d_mcf)
      .put_mm(10, mcf_lo)
      .put_mm(11, mcf_hi)
      .put_mm(12, mcf_dist)
      .put_mm(13, mm$ef3[i]              %||% mm$EF3[i] %||% d_ef3)
      .put_mm(14, ef3_lo)
      .put_mm(15, ef3_hi)
      .put_mm(16, ef3_dist)
      .put_mm(17, mm$Frac_GasMS_pct[i]   %||% mm$frac_gasms_pct[i] %||%
                   mm$Frac_GasMS[i] %||% d_gas)
      .put_mm(18, gas_lo)
      .put_mm(19, gas_hi)
      .put_mm(20, mm$distribution_frac_gas[i])
      .put_mm(21, mm$Frac_LeachMS_pct[i] %||% mm$frac_leachms_pct[i] %||%
                   mm$Frac_LeachMS[i] %||% d_leach)
      .put_mm(22, lea_lo)
      .put_mm(23, lea_hi)
      .put_mm(24, mm$distribution_frac_leach[i])
      # 2026-10-30 (later): ranges still blank take a placeholder (MCF
      # +/-25 %, EF3 x2, fractions +/-50 %), listed in data_source (col 25)
      # so the app, the report and the exports know them.
      ph_cols <- character(0)
      share_i <- suppressWarnings(as.numeric(.translator_scalar(mm$fraction_pct[i])))
      if (is.finite(share_i) && share_i > 0) {
        for (cc in list(list(c = "MCF_pct", v = mcf_v, lo = mcf_lo, hi = mcf_hi, lc = 10, hc = 11),
                        list(c = "EF3", v = ef3_v, lo = ef3_lo, hi = ef3_hi, lc = 14, hc = 15),
                        list(c = "Frac_GasMS_pct", v = gas_v, lo = gas_lo, hi = gas_hi, lc = 18, hc = 19),
                        list(c = "Frac_LeachMS_pct", v = lea_v, lo = lea_lo, hi = lea_hi, lc = 22, hc = 23))) {
          if (!is.finite(cc$v) || cc$v == 0 || !is.na(cc$lo) || !is.na(cc$hi)) next
          if (identical(as.character(mms_id), "pasture") && cc$c != "MCF_pct") next
          p0 <- MANURE_PLACEHOLDER[[cc$c]]
          .put_mm(cc$lc, cc$v * p0$lo)
          .put_mm(cc$hc, if (cc$c == "EF3") cc$v * p0$hi else min(100, cc$v * p0$hi))
          ph_cols <- c(ph_cols, cc$c)
        }
      }
      if (length(ph_cols)) .put_mm(25, paste0(.PLACEHOLDER_TAG, ": ", paste(ph_cols, collapse = ", ")))
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
  # banner @ row 1, headers @ 2, desc @ 3, units @ 4: so data rows
  # start at row 5. Columns:
  #   1 cattle_type    2 aggregation_level    3 sub_category    4 year
  #   5 N    6 BW    7 MW    8 WG    9 Milk   10 Fat
  #  11 pct_pregnant   12 DE   13 CP   14 MilkPR
  ts <- parsed$parameter_timeseries
  # 2026-10-30: a row the AI left without cattle_type takes it from the
  # Parameters group with the same aggregation_level and sub_category. The
  # Zambia 2024 run left it blank for all commercial dairy rows: the trend
  # matched none of them, and one cell kept the blank template's note.
  if (is.data.frame(ts) && nrow(ts) > 0 && is.data.frame(parsed$parameters) &&
      all(c("aggregation_level", "sub_category") %in% names(ts)) &&
      all(c("cattle_type", "aggregation_level", "sub_category") %in% names(parsed$parameters))) {
    if (!"cattle_type" %in% names(ts)) ts$cattle_type <- NA_character_
    pk <- unique(parsed$parameters[, c("cattle_type", "aggregation_level", "sub_category")])
    pk <- pk[!is.na(pk$cattle_type) & nzchar(as.character(pk$cattle_type)), , drop = FALSE]
    blank_ct <- is.na(ts$cattle_type) | !nzchar(trimws(as.character(ts$cattle_type)))
    for (i in which(blank_ct)) {
      hit <- unique(pk$cattle_type[pk$aggregation_level %in% ts$aggregation_level[i] &
                                   pk$sub_category %in% ts$sub_category[i]])
      if (length(hit) != 1L)
        hit <- unique(pk$cattle_type[pk$aggregation_level %in% ts$aggregation_level[i]])
      if (length(hit) == 1L) ts$cattle_type[i] <- hit
    }
  }
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

# Fallback writer: used only when the official template builder errors
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
    md <- .translator_metadata_list(parsed$inventory_metadata)
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
# the reply is dominated by a numbered list (e.g. "Section D -
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
  # is incidental: show the full prose instead.
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

  # Case 1b (2026-10-23): the explore reply's sections A to C, the table
  # of every value the AI read, stay out of the bubble and are offered here.
  if (!is.null(display) && nzchar(display) && !identical(display, content)) {
    m_a <- regexpr("(?m)^#{2,4}\\s*A\\.", content, perl = TRUE)
    if (m_a > 0) {
      m_d <- regexpr("(?m)^#{2,4}\\s*D\\.", content, perl = TRUE)
      hid <- if (m_d > m_a) substr(content, m_a, m_d - 1L) else substr(content, m_a, nchar(content))
      hid <- sub("(?s)\\n```.*$", "", hid, perl = TRUE)
      return(list(visible = display, hidden = trimws(hid),
                  summary = "Show what the AI read from the file (sections A to C)"))
    }
  }

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
                            else "Template ready: click the green download button below to get the .xlsx.",
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
# (a common failure mode: the AI emits one "representative" sub-cat
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
      "calves_female", "calves_male", "calves", "feedlot_cattle")
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

# The discovery reply's inventory_metadata as a plain named list. The model
# has returned it as a JSON string inside the JSON (2026-10-29, a
# three-system file: "$ operator is invalid for atomic vectors" at
# assembly), jsonlite can hand back a one-row data frame, and a named
# character vector is possible; all three are accepted. Anything else is
# an empty list, which the writer fills from the register and the defaults.
.translator_metadata_list <- function(md) {
  if (is.null(md)) return(list())
  if (is.character(md) && length(md) == 1L) {
    # The string the model sent ended in "}}" (one brace too many), which
    # the strict parser calls trailing garbage: stray closing braces are
    # trimmed one at a time before giving up.
    txt <- trimws(md); parsed <- NULL
    for (k in 0:3) {
      parsed <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = TRUE), error = function(e) NULL)
      if (is.list(parsed) || !grepl("\\}\\s*$", txt)) break
      txt <- sub("\\}\\s*$", "", txt)
    }
    if (is.list(parsed)) md <- parsed
    else { message("translator: inventory_metadata string could not be parsed: ", substr(md, 1, 120)); return(list()) }
  }
  if (is.data.frame(md)) md <- if (nrow(md)) as.list(md[1L, , drop = FALSE]) else list()
  if (is.atomic(md)) { if (is.null(names(md))) return(list()); md <- as.list(md) }
  if (!is.list(md)) return(list())
  md
}

# Coerce any JSON-roundtripped value to a length-1 atomic safe to hand
# to openxlsx::writeData. Handles every shape we've seen from
# jsonlite::fromJSON(simplifyVector=TRUE): NULL, NA, length-0 vector,
# scalar, length>N vector (we keep the first element), list-of-1,
# nested list, even a 1-row data.frame fragment. The writeData call
# below used to throw "no such index at level 1" when a cell value
# was a list-column (production-only: local repros couldn't trigger
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
# a JSON array-of-objects into a data.frame: if the objects have a
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
