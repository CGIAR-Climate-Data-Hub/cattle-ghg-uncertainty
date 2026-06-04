# Master UI Function
app_ui <- function() {
  bslib::page_navbar(
    id = "nav",
    # Round 9 follow-up: stacked header — big centered title row above the
    # tabs row. Title + subtitle live inside a flex column; CSS in
    # www/custom.css turns the navbar into vertical layout (title above
    # tabs) and centers both rows. The bg=transparent on .app-title keeps
    # the navbar's existing background.
    title = tags$div(
      class = "app-title-block",
      tags$div(class = "app-title",
                "IPCC Tier 2 Livestock GHG Uncertainty Calculator"),
      tags$div(class = "app-subtitle",
                "Approach 2 Monte Carlo · CGIAR Alliance / Bioversity-CIAT · funded by the Global Methane Hub")
    ),
    theme = bslib::bs_theme(
      version = 5,
      primary = "#2D6A4F",
      secondary = "#40916C",
      success = "#2D6A4F",
      bg = "#F7F5F0",
      fg = "#1A1A1A",
      base_font = bslib::font_google("DM Sans"),
      code_font = bslib::font_google("JetBrains Mono")
    ),
    header = tagList(
      tags$head(tags$link(rel = "stylesheet", href = "custom.css")),
      tags$head(tags$script(HTML(
        "Shiny.addCustomMessageHandler('scrollTo', function(id) {
           // setTimeout buffer: when scrollTo follows a nav_select, the target
           // tab needs a tick to render before its child elements become
           // measurable. 150ms is imperceptible to users but reliable.
           setTimeout(function() {
             var el = document.getElementById(id);
             if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
           }, 150);
         });
         // 2026-06: after the magic-link auth flow consumes a ?token=...
         // query parameter, server sends this to clean it out of the
         // browser URL so the token doesn't sit in browser history.
         Shiny.addCustomMessageHandler('scrubUrl', function(_unused) {
           if (history && history.replaceState) {
             history.replaceState({}, document.title,
                                   window.location.pathname);
           }
         });
         // 2026-06: in-app AI translator — Server-Sent-Events streaming.
         // server -> client message protocol:
         //   translatorStreamStart : create a fresh assistant bubble,
         //                            remember it as the active target.
         //   translatorStreamChunk : append text to the active bubble,
         //                            auto-scroll the message container.
         //   translatorStreamEnd   : drop the reference to the active
         //                            bubble (next round starts fresh).
         var _translatorActiveBubble = null;
         Shiny.addCustomMessageHandler('translatorStreamStart', function(_unused) {
           // NOTE: do NOT hide the spinner here. translatorStreamStart fires
           // BEFORE the API call returns the first token, so hiding now
           // leaves the user staring at an empty bubble for 3-5 seconds.
           // The spinner is hidden by translatorStreamChunk on the very
           // first chunk (see handler below) — that's the moment the user
           // actually has something to look at.
           var container = document.getElementById('translator_stream_target');
           if (!container) return;
           var bubble = document.createElement('div');
           // Style MUST match the AI bubble style in R/chat_ui.R's renderUI
           // so the streamed-live bubble looks identical to the rendered-
           // history bubble that replaces it once streaming ends.
           bubble.style.cssText = 'max-width:80%; margin:6px 0;' +
             'padding:10px 14px; border-radius:12px; white-space:pre-wrap;' +
             'font-size:0.92rem; line-height:1.45;' +
             'background:#E8F5E9; color:#1B4332; align-self:flex-start;' +
             'border:1px solid #C8E6C9;';
           container.appendChild(bubble);
           _translatorActiveBubble = bubble;
         });
         Shiny.addCustomMessageHandler('translatorStreamChunk', function(text) {
           // First real token arrived — hide the pre-stream spinner now
           // (cheap no-op if it was already hidden).
           if (typeof _translatorHideSpinner === 'function') _translatorHideSpinner();
           if (!_translatorActiveBubble) return;
           _translatorActiveBubble.textContent += text;
           // auto-scroll the surrounding message-history div
           var scroller = _translatorActiveBubble.closest('[data-translator-scroller]');
           if (scroller) scroller.scrollTop = scroller.scrollHeight;
         });
         Shiny.addCustomMessageHandler('translatorStreamEnd', function(_unused) {
           // Don't remove the bubble — the server about to swap it for a
           // properly-rendered one in the message history. Just drop the
           // reference so future chunks don't accidentally append.
           _translatorActiveBubble = null;
           // Also hide the pre-stream spinner — covers the non-streaming
           // force-template path where StreamStart never fires.
           if (typeof _translatorHideSpinner === 'function') _translatorHideSpinner();
         });
         // 2026-06: persistent sign-in. After magic-link consume, server
         // sends a signed cookie value here; we drop it into document.cookie
         // for 30 days. On the next refresh the server reads the Cookie:
         // header (session$request$HTTP_COOKIE), HMAC-verifies it, and
         // restores the signed-in state without a fresh magic link.
         Shiny.addCustomMessageHandler('setTranslatorSession', function(value) {
           if (!value) return;
           var maxAge = 30 * 24 * 60 * 60;  // 30 days in seconds
           document.cookie = 'translator_session=' + encodeURIComponent(value) +
             '; max-age=' + maxAge + '; path=/; SameSite=Lax; Secure';
         });
         // 2026-06: visible loading spinner with a context-aware label.
         // Without this the user clicks Send / uploads a file and sees
         // nothing for 1-5 seconds.
         var _translatorSpinnerDefault = 'Translator is working — calling the AI, waiting for the first reply…';
         function _translatorShowSpinner(label) {
           var el = document.getElementById('translator_spinner');
           if (!el) return;
           var lab = el.querySelector('[data-translator-spinner-label]');
           if (lab) lab.textContent = label || _translatorSpinnerDefault;
           el.style.display = 'flex';
         }
         function _translatorHideSpinner() {
           var el = document.getElementById('translator_spinner');
           if (el) el.style.display = 'none';
         }
         // Clear the chat textarea immediately on submit so the user
         // gets instant visual feedback that the message was accepted.
         // Shiny's cached input value for translator_input still holds
         // the original text (set during typing), so the server-side
         // observer reads it correctly even after we clear the DOM.
         function _translatorClearInputDOM() {
           var input = document.getElementById('translator_input');
           if (input) input.value = '';
         }
         // Optimistic-render: when the user submits a message, paint a
         // user-bubble in the conversation INSTANTLY (before the server
         // round-trip) so the user knows their message was accepted.
         // The server-side renderUI for translator_messages will swap it
         // for the canonical version once state$messages updates.
         function _translatorOptimisticUserBubble(text) {
           if (!text) return;
           var slot = document.getElementById('translator_stream_target');
           if (!slot) return;
           var bubble = document.createElement('div');
           // Matches the user-bubble styling in chat_ui.R::output$translator_messages
           bubble.style.cssText = 'max-width:80%; margin:6px 0;' +
             'padding:10px 14px; border-radius:12px; white-space:pre-wrap;' +
             'font-size:0.92rem; line-height:1.45;' +
             'background:#DCEFFB; color:#1A3A5C; align-self:flex-end;' +
             'border:1px solid #BFDCEE;';
           bubble.textContent = text;
           slot.appendChild(bubble);
           // Scroll the surrounding history into view so the bubble's visible.
           var scroller = bubble.closest('[data-translator-scroller]');
           if (scroller) scroller.scrollTop = scroller.scrollHeight;
         }
         // Server-driven: force the spinner visible. Belt-and-suspenders
         // for the case where client-side show fires but something
         // (re-render, focus change, browser quirk) hides it before the
         // first AI chunk arrives. The server sends this on every entry
         // into work that will keep the user waiting.
         Shiny.addCustomMessageHandler('translatorShowSpinner', function(label) {
           _translatorShowSpinner(label || _translatorSpinnerDefault);
         });

         // 2026-06: Enter-to-submit for the translator email + chat inputs.
         // Capture phase (third arg = true) so we beat any bubble-phase
         // keydown handler Shiny/Bootstrap may attach to the input.
         document.addEventListener('keydown', function(e) {
           if (e.key !== 'Enter' || e.shiftKey || e.ctrlKey || e.metaKey || e.altKey) return;
           var t = e.target;
           if (!t || !t.id) return;
           if (t.id === 'translator_email') {
             e.preventDefault();
             e.stopPropagation();
             _translatorShowSpinner('Sending sign-in link…');
             var btn = document.getElementById('translator_submit');
             if (btn) btn.click();
           } else if (t.id === 'translator_input') {
             e.preventDefault();
             e.stopPropagation();
             // Just trigger the Send button. The click handler (below)
             // reads the textarea value, pushes it to Shiny, paints the
             // optimistic bubble, clears the DOM, and shows the spinner —
             // all in one pass. Don't pre-clear here or the click handler
             // would re-read an empty value and clobber the typed text.
             var btn = document.getElementById('translator_send');
             if (btn) btn.click();
           }
         }, true);

         // Click handler: show the spinner with the right label and
         // clear the input on Send. Walks up a couple of levels because
         // the click target may be a child <i> icon of the button.
         document.addEventListener('click', function(e) {
           var t = e.target;
           if (!t) return;
           for (var i = 0; i < 3 && t; i++) {
             if (t.id === 'translator_send') {
               var input = document.getElementById('translator_input');
               var txt = (input && input.value) ? input.value : '';
               // Empty submit: server-side req() would no-op, but the
               // spinner would spin forever with nothing to clear it.
               // Bail without touching anything.
               if (!txt.replace(/\\s+/g, '').length) return;
               if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
                 Shiny.setInputValue('translator_input', txt,
                                      {priority: 'event'});
               }
               // Optimistic UI: paint the user's bubble in the conversation
               // BEFORE clearing the textarea — instant feedback that the
               // message was accepted. Server-side renderUI will replace
               // it with the canonical version when state$messages updates.
               _translatorOptimisticUserBubble(txt);
               _translatorClearInputDOM();
               _translatorShowSpinner();
               return;
             }
             if (t.id === 'translator_force_template') {
               _translatorShowSpinner('Producing the final template — this can take 20–40 seconds for a large inventory…');
               return;
             }
             if (t.id === 'translator_submit') {
               _translatorShowSpinner('Sending sign-in link…');
               return;
             }
             t = t.parentElement;
           }
         }, false);
         // File upload — different label so the user knows what's happening.
         // Capture phase + defensive id-contains match (in case Shiny ever
         // wraps the input or namespaces the id). Without capture, Shiny's
         // own change binding can stop propagation before we see the event.
         document.addEventListener('change', function(e) {
           var t = e.target;
           if (!t) return;
           var isTranslatorFile =
             t.id === 'translator_file' ||
             (t.type === 'file' && /translator_file/.test(t.id || ''));
           if (isTranslatorFile) {
             _translatorShowSpinner('Analyzing your file — reading sheets, building a preview to send to the AI…');
           }
         }, true);"
      )))
    ),
    fillable = FALSE,

    # ==================== HOME TAB ====================
    bslib::nav_panel(
      title = "Home",
      icon = icon("home"),
      div(
        style = "max-width: 960px; margin: 0 auto; padding: 24px;",

        # Hero section
        div(
          style = "background: linear-gradient(135deg, #1B4332 0%, #2D6A4F 50%, #40916C 100%);
                   color: white; border-radius: 16px; padding: 48px 40px; margin-bottom: 0;
                   position: relative; overflow: hidden;",
          h1("IPCC Tier 2 Livestock GHG Uncertainty Calculator",
             style = "font-size: 2rem; font-weight: 700; margin-bottom: 12px;"),
          p("Monte Carlo uncertainty analysis for national cattle methane and nitrous oxide inventories.",
            style = "font-size: 1.1rem; opacity: 0.9; margin-bottom: 8px;"),
          p("Developed by CGIAR Alliance of Bioversity International and CIAT | Funded by Global Methane Hub",
            style = "font-size: 0.9rem; opacity: 0.7;")
        ),
        # Logo bar: developer (Alliance Bioversity & CIAT) and funder (GMH).
        # Each img has an onerror fallback that swaps in the institution name
        # as text if the PNG is missing from www/.
        div(
          style = "display:flex; align-items:center; justify-content:center; gap:72px;
                   background:#FFFFFF; border: 1px solid #E0DDD5; border-top: none;
                   border-radius: 0 0 16px 16px; padding: 28px 24px; margin-bottom: 32px;",
          tags$img(src = "alliance_logo.png",
                   alt = "Alliance of Bioversity International and CIAT",
                   style = "height:96px; max-width:320px; object-fit:contain;",
                   onerror = "this.style.display='none'; this.nextSibling.style.display='inline-block';"),
          tags$span("Alliance Bioversity & CIAT",
                    style = "display:none; font-size:0.9rem; color:#444; font-weight:600;"),
          tags$img(src = "gmh_logo.png",
                   alt = "Global Methane Hub",
                   style = "height:96px; max-width:320px; object-fit:contain;",
                   onerror = "this.style.display='none'; this.nextSibling.style.display='inline-block';"),
          tags$span("Global Methane Hub",
                    style = "display:none; font-size:0.9rem; color:#444; font-weight:600;")
        ),

        # What this tool does
        bslib::card(
          bslib::card_header(h4("What does this tool do?", style = "margin: 0;")),
          bslib::card_body(
            p("When a country reports cattle greenhouse gas emissions under the Paris Agreement, every input parameter
              (animal populations, body weights, feed quality, emission factors) has some uncertainty. This tool:"),
            tags$ol(
              tags$li("Takes your country-specific input data aligned with the IPCC Tier 2 equations, with uncertainty ranges"),
              tags$li("Runs thousands of Monte Carlo simulations, varying all parameters according to their probability distributions"),
              tags$li("Produces the uncertainty range for your total emission estimate (95% confidence interval)"),
              tags$li("Identifies which parameters contribute most to the uncertainty (sensitivity analysis)"),
              tags$li("Formats results for IPCC inventory reporting (IPCC 2006 Vol. 1 Ch. 3, Table 3.3)")
            ),
            p(tags$strong("Emission sources covered:"),
              " Enteric fermentation CH₄, Manure management CH₄, Manure management N₂O (direct and indirect),
              and N₂O (direct and indirect) from dung and urine deposited on pasture.")
          )
        ),

        # Workflow overview
        bslib::card(
          bslib::card_header(h4("How to use this tool -- Step by step", style = "margin: 0;")),
          bslib::card_body(
            p("Work through the tabs from left to right. Each tab has instructions at the top explaining what to do."),
            tags$table(
              style = "width: 100%; border-collapse: collapse; margin-top: 8px;",
              tags$thead(
                tags$tr(style = "background: #D8F3DC; text-align: left;",
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", "Step"),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", "Tab"),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", "What you do"),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", "Time")
                )
              ),
              tags$tbody(
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "1"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "Data Input"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Load example data or upload your country data from the Excel template"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "2"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "QA/QC"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Review automated quality checks -- fix any fails and document large deviations from IPCC defaults"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "3"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "Uncertainty"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Review and adjust probability distributions and uncertainty ranges for each parameter"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "10 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "4"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "Correlations"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "(Optional) Upload population time series or manually define correlations between activity data"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "Simulate"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Choose number of iterations, GWP version, and click Run — results (emission distributions, 95% CI, decomposition) appear in the same tab"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5-7 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "6"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "Sensitivity"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Identify which parameters contribute most to uncertainty (tornado chart)"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "7"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", "IPCC Report"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "Download results formatted as IPCC Table 3.3 for your inventory submission"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "2 min")
                )
              )
            ),
            br(),
            div(class = "info-panel",
                tags$strong("Quick start: "),
                "To try the tool immediately, go to ",
                tags$strong("1. Data Input"), ", select 'Country X (hypothetical dairy)', then go to ",
                tags$strong("5. Simulate"), " and click 'Run Monte Carlo Simulation'."),
            br(),
            div(style = "text-align: center;",
                actionButton("goto_resources", "Methodology, user guide & downloads →",
                             class = "btn btn-outline-success",
                             style = "font-size:0.95rem; padding: 10px 24px;"))
          )
        ),

        # T0.4: prerequisites & limitations
        bslib::card(
          bslib::card_header(h4("Before you start", style = "margin: 0;")),
          bslib::card_body(
            tags$p(tags$strong("You will need:")),
            tags$ul(
              tags$li("A Tier 2 input dataset for the inventory year(s) you wish to assess: ",
                      "animal sub-categories with population, body weights, feed quality, and manure-management shares."),
              tags$li("A defensible estimate of the uncertainty in each input (typically ±% half-width of the 95 % CI, or ",
                      "lower / upper bounds for asymmetric parameters). The tool ", tags$strong("does not"),
                      " estimate input uncertainties for you."),
              tags$li("Optional but recommended: multi-year time series of activity data, used to compute correlations automatically.")
            ),
            tags$p(tags$strong("What this tool does NOT do:")),
            tags$ul(
              tags$li("It does not collect data or estimate input uncertainties — those must be supplied by the user."),
              tags$li("It does not produce Tier 1 estimates and is not designed for uncertainty analysis of country-specific Tier 2 methods — the IPCC Tier 2 equation chain is required."),
              tags$li("It does not validate your country's IPCC categorisation choices — sub-category structure is the user's responsibility."),
              tags$li("Cross-block correlations between activity data and emission factors are not yet supported (planned for v3.0).")
            )
          )
        ),
        # Andreas 2026-05 #3: analysis-mode toggle moved to top of Data Input
        # tab (see below). Card removed from Home page so the workflow start
        # is more visible.
      )
    ),

    # ==================== DEFINITIONS TAB (T1.4 + R1.7 + R1.8) ====================
    bslib::nav_panel(
      title = "Definitions",
      icon = icon("book"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("Parameter glossary. "),
          "All parameters used in the IPCC Tier 2 calculations, with their plain-language ",
          "definition, unit, IPCC default value, suggested distribution, level (core / advanced), ",
          "IPCC framing (activity data vs coefficient), and IPCC reference table or equation. ",
          "Variable names are aligned with the ", tags$strong("IPCC Inventory Software"),
          " (v2.95) and the symbols used in the IPCC 2006 Vol.4 Ch.10 / Ch.11 equations.")
      ,
      bslib::card(
        bslib::card_header("Parameter definitions"),
        bslib::card_body(DT::DTOutput("definitions_table"))
      )
    ),

    # ==================== USEFUL RESOURCES TAB (T0.2) ====================
    bslib::nav_panel(
      title = "Resources",
      icon = icon("book-open"),
      div(style = "max-width: 960px; margin: 0 auto; padding: 24px;",
        # Tool-specific resources — methodology + user guide. Kept first so it
        # is the first thing users see in the Resources tab.
        # The id is the scroll target for the Home tab "Methodology, user
        # guide & downloads" button (see goto_resources in app_server.R).
        bslib::card(
          id = "downloads-card",
          bslib::card_header(h4("Tool-specific resources", style = "margin: 0;")),
          bslib::card_body(
            tags$h5("How this tool works"),
            tags$ul(
              tags$li("Equation chain: IPCC 2006 Vol 4 Ch 10 (Eq 10.1–10.34) and Ch 11 for the per-head emission factor; population × EF for the per-sub-category total."),
              tags$li("Monte Carlo: Approach 2 from IPCC 2006 Vol 1 Ch 3. Correlations are sampled via the rank-correlation-preserving restricted-pairing procedure per IPCC Vol 1 Ch 3 §3.2.3.2 — the same method is used for every correlated path (time-series, preset, manual, structural defaults)."),
              tags$li("Sensitivity: Standardised regression coefficients (SRC) and partial rank correlation (PRCC) on the sampled inputs vs each output.")
            ),
            div(style = "margin-top: 16px; display: flex; gap: 12px; flex-wrap: wrap;",
              tags$a(
                href = "methodology.pdf",
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-success",
                icon("file-pdf"), " Open full methodology (PDF)"
              ),
              tags$a(
                href = "user_guide.pdf",
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-outline-success",
                icon("book"), " Open user guide (PDF)"
              )
            )
          )
        ),
        # AI Translator kit — free, self-serve helper to turn the user's own
        # Excel/CSV files into the strict app template via a pre-built Claude.ai
        # Project. Placed below Tool-specific resources so the canonical docs
        # are the first thing users see. See claude_project_assets/README.md.
        # 2026-06: in-app AI translator. Replaces the previous "Sign up for
        # claude.ai, paste these files, set up a Project" guide with a
        # direct in-app chat behind a magic-link login. Backed by Lolita's
        # OpenAI account with a $10/month spending cap. The downloadable
        # kit and the free-tier flow remain available below as a fallback.
        translator_chat_ui(),

        # Fallback: downloadable kit for users who don't want to sign in.
        bslib::card(
          style = "border-left: 4px solid #94A3B8;",
          bslib::card_header(h4("Or — use the free downloadable kit on claude.ai",
                                 style = "margin: 0;")),
          bslib::card_body(
            tags$p(style = "margin-bottom: 12px;",
              "Prefer to keep everything inside your own free Claude.ai account ",
              "(no sign-in here, but you handle the setup yourself)? Download ",
              "the kit and follow the short setup guide. Two minutes the first time, ",
              "then reusable for every inventory."),
            div(style = "margin-top: 4px; display: flex; gap: 10px; flex-wrap: wrap;",
              tags$a(
                href = "translator_kit.zip",
                download = "translator_kit.zip",
                class = "btn btn-outline-success",
                icon("box-archive"), " Download Translator kit (.zip)"
              ),
              tags$a(
                href = "getting_started.pdf",
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-outline-success",
                icon("file-pdf"), " Getting started (full guide)"
              ),
              tags$a(
                href = "questionnaire.docx",
                target = "_blank",
                download = "questionnaire.docx",
                class = "btn btn-outline-success",
                icon("clipboard-list"), " Pre-flight questionnaire (.docx)"
              )
            )
          )
        ),

        bslib::card(
          bslib::card_header(h4("Useful resources", style = "margin: 0;")),
          bslib::card_body(
            tags$h5("Methodological foundations"),
            tags$p(style = "font-size: 0.9em; color: #555; margin-bottom: 8px;",
                   "The six IPCC chapters that underpin the calculations and uncertainty methodology of this tool. Links open the official PDFs on the IPCC-NGGIP site."),
            tags$ul(
              tags$li(tags$strong("Vol. 4 (AFOLU) — Livestock & Manure Management:"),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_10_Ch10_Livestock.pdf",
                                       target = "_blank",
                                       "IPCC 2006 Guidelines — Vol. 4, Chapter 10 (Emissions from Livestock and Manure Management)")),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch10_Livestock.pdf",
                                       target = "_blank",
                                       "2019 Refinement — Vol. 4, Chapter 10 (Updated livestock equations, MMS table 10.17, Bo table 10.16a, Ym table 10.12)"))
                      )
              ),
              tags$li(tags$strong("Vol. 4 (AFOLU) — Managed Soils (N₂O from soils, including PRP):"),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_11_Ch11_N2O&CO2.pdf",
                                       target = "_blank",
                                       "IPCC 2006 Guidelines — Vol. 4, Chapter 11 (N₂O Emissions from Managed Soils, CO₂ from Lime/Urea)")),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch11_Soils_N2O_CO2.pdf",
                                       target = "_blank",
                                       "2019 Refinement — Vol. 4, Chapter 11 (Updated EF3_PRP table 11.1, EF4/EF5/FracGASM/FracLEACH-(H) table 11.3)"))
                      )
              ),
              tags$li(tags$strong("Vol. 1 — Uncertainty methodology (Approach 1 vs Approach 2):"),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/1_Volume1/V1_3_Ch3_Uncertainties.pdf",
                                       target = "_blank",
                                       "IPCC 2006 Guidelines — Vol. 1, Chapter 3 (Uncertainties)")),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/1_Volume1/19R_V1_Ch03_Uncertainties.pdf",
                                       target = "_blank",
                                       "2019 Refinement — Vol. 1, Chapter 3 (Uncertainties; including §3.2.2.4 on temporal correlation of EFs)"))
                      )
              )
            ),
            tags$h5("Activity data guidance"),
            tags$ul(
              tags$li(tags$a(href = "https://www.fao.org/livestock-systems/global-distributions/en/",
                             target = "_blank",
                             "FAO Livestock Activity Data Guidance (L-ADG)")),
              tags$li("Penman et al. (2000) — Good Practice Guidance and Uncertainty Management in National Greenhouse Gas Inventories")
            ),
            tags$h5("Distributions and Monte Carlo references"),
            tags$ul(
              tags$li("Frey & Rhodes (1998) — Characterizing, simulating, and analyzing variability and uncertainty"),
              tags$li("IPCC GPG 2000 §6 — Quantifying uncertainties in practice (Approach 1 vs Approach 2)")
            ),
            tags$h5("Learning resources"),
            tags$ul(
              tags$li(tags$a(href = "https://elearning.fao.org/course/view.php?id=625",
                             target = "_blank",
                             "FAO e-learning — Assessing uncertainty in the land sector")),
              tags$li(tags$a(href = "https://elearning.fao.org/course/view.php?id=531",
                             target = "_blank",
                             "FAO e-learning — Tier 2 inventory for livestock")),
              tags$li(tags$a(href = "https://unfccc.int/topics/science/workstreams/methodological-issues-under-the-convention",
                             target = "_blank",
                             "UNFCCC webinar notes — Uncertainty analysis for GHG inventories"))
            ),
            tags$h5("Case studies"),
            tags$ul(
              tags$li("Monni et al. (2007) — Uncertainty in agricultural CH₄ and N₂O emissions from Finland"),
              tags$li("Karimi-Zindashty et al. (2012) — Sources of uncertainty in livestock emission inventories: Canadian case study"),
              tags$li("Milne et al. (2014) — Estimating uncertainty in pasture-based dairy CH₄ emissions"),
              tags$li(tags$em("Additional national-inventory examples to be added."))
            )
          )
        )
      )
    ),

    # ==================== TAB 1: DATA INPUT ====================
    bslib::nav_panel(
      title = "1. Data Input",
      icon = icon("upload"),
      # Andreas 2026-05 #3: analysis-mode toggle moved here from Home page.
      bslib::card(
        style = "margin: 16px;",
        bslib::card_header(h5("Choose your analysis mode", style = "margin: 0;")),
        bslib::card_body(
          radioButtons("analysis_mode",
            label = NULL,
            choiceNames = list(
              tagList(
                "Single year — quantify uncertainty in one inventory year ",
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  "Use this mode to estimate the uncertainty for one specific inventory year. All parameters are sampled independently for each iteration. This is the most common mode and is sufficient for IPCC Table 3.3 reporting. Choose Trend if you also want to assess whether emission changes over time are statistically significant.",
                  placement = "right"
                )
              ),
              tagList(
                "Trend — compare uncertainty across multiple years ",
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  "Use this mode when you have activity data for several inventory years and want to assess whether the trend (change over time) is statistically distinguishable from zero. IPCC Vol 1 Ch 3 §3.7 recommends reporting trend uncertainty for inventory series. Requires a Parameter_TimeSeries sheet in your upload template, or use one of the built-in example datasets.",
                  placement = "right"
                )
              )
            ),
            choiceValues = c("single", "trend"),
            selected = character(0)),
          div(id = "analysis_mode_warning",
              style = "background:#FEF3C7; border-left:3px solid #F59E0B; padding:8px 10px; margin-top:8px; font-size:0.85rem; color:#92400E; border-radius:4px;",
              icon("exclamation-triangle"),
              tags$strong(" Selection required: "),
              "pick Single year or Trend before moving on. The Run button on Tab 5 will block until a mode is chosen."),
          tags$p(tags$em(
            "What 'Trend' does in this tool: a full Monte Carlo uncertainty run ",
            "is performed independently for every year present in your time-series ",
            "upload, and the uncertainty on the trend itself is taken as the ",
            "distribution of (Year_N − Year_1) — the absolute change in ",
            "CO₂eq between the last and first year. ",
            tags$br(), tags$br(),
            "IPCC alignment: IPCC 2006 Vol.1 Ch.3 §3.7 (“Uncertainty in ",
            "trends”) defines the trend as the change between a ",
            tags$strong("base year"), " and a ", tags$strong("current year"),
            ". The first / last years of the time series you upload are used ",
            "as those base and current years respectively. §3.7 covers both ",
            "Approach 1 (error-propagation, Eq. 3.1–3.2) and Approach 2 ",
            "(Monte Carlo) for the trend; this tool implements the Approach 2 ",
            "version. Use 'Trend' if you have multi-year data; use 'Single year' ",
            "for a one-off uncertainty estimate."),
            style = "color:#555; font-size:0.85rem; margin-top:8px;")
        )
      ),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("What to do: "),
          "Select an example country dataset from the dropdown, or upload your own data using the Excel template. ",
          "The parameter table on the right shows the loaded data -- ",
          "you can click on any cell to edit values directly. Check the validation panel at the bottom left to ",
          "ensure your data is complete and valid before proceeding to the next tab."),
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 320,
          h5("Data Source"),
          selectInput("country", "Country / Example Data",
                      choices = c("Country X (hypothetical dairy)" = "country_x",
                                  "Country Y (hypothetical pastoral)" = "country_y",
                                  "Custom Upload" = "custom")),
          # B1: explicit hint when "Custom Upload" selected so the user knows the
          # dropdown registered (the example tables don't auto-load for "custom")
          conditionalPanel(
            condition = "input.country == 'custom'",
            div(style = "background:#FEF3C7; border-left:3px solid #F59E0B; padding:8px 10px; margin-top:8px; font-size:0.85rem; color:#92400E; border-radius:4px;",
                icon("info-circle"),
                " Custom mode selected. Pick an IPCC version, download the matching template, fill it in, then upload below.")
          ),
          # Andreas 2026-05 follow-up: the IPCC version picker, template
          # downloads and upload section only apply to the Custom Upload
          # path — hide them entirely for the built-in example datasets so
          # the sidebar isn't cluttered.
          conditionalPanel(
            condition = "input.country == 'custom'",
            hr(),
            # Round 7.1: IPCC version picker drives the downloaded template's
            # MMS dropdown (filtered to systems valid for that version) and
            # the Inventory_Metadata `ipcc_version` cell.
            h5("1. Pick an IPCC Guidelines version"),
            radioButtons("template_version", label = NULL,
                          choices = c("IPCC 2006" = "2006",
                                      "IPCC 2019 Refinement" = "2019_refinement"),
                          selected = character(0), inline = TRUE),
            div(style = "font-size:0.78rem; color:#666; margin-top:-6px; margin-bottom:8px;",
                tags$em("The MMS dropdown in the downloaded template will be filtered to manure systems valid for the version you pick here.")),
            h5("2. Download a template"),
            downloadButton("download_template", "Download Blank Template",
                           class = "btn-outline-success btn-sm"),
            downloadButton("download_template_example", "Download Template with Example",
                           class = "btn-outline-primary btn-sm mt-2"),
            div(style = "font-size:0.78rem; color:#666; margin-top:6px;",
                tags$em("If no IPCC version is picked, the download is blocked and the app will prompt you to select one.")),
            div(style = "margin-top: 10px; padding: 8px 10px; background:#E8F5E9; border-left:3px solid #2D6A4F; border-radius:4px; font-size:0.82rem;",
              icon("robot"),
              tags$strong(" Don't have the template filled yet?"),
              tags$br(),
              "Download the free ",
              tags$a(href = "translator_kit.zip", download = "translator_kit.zip",
                     "AI Translator kit"),
              " and set up your own Claude.ai assistant in ~2 minutes. ",
              tags$a(href = "getting_started.pdf", target = "_blank",
                     rel = "noopener noreferrer", "Getting started (PDF)"),
              " · ",
              tags$a(href = "questionnaire.docx", target = "_blank",
                     download = "questionnaire.docx", "Questionnaire (.docx)"),
              " · see the Resources tab for the full walkthrough."),
            hr(),
            h5("3. Upload your filled template"),
            fileInput("data_upload", "Upload Excel Template (.xlsx)",
                      accept = ".xlsx")
          ),
          hr(),
          h5("Validation"),
          uiOutput("validation_status")
        ),
        conditionalPanel(
          condition = "output.has_imputed_params == true",
          uiOutput("imputed_params_notice_tab1")
        ),
        bslib::card(
          bslib::card_header("Parameter Data"),
          bslib::card_body(DT::DTOutput("param_table"))
        )
      )
    ),

    # ==================== TAB 2: QA/QC ====================
    bslib::nav_panel(
      title = "2. QA/QC",
      icon = icon("check-square"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("What to do: "),
          "After loading data, review these automated quality checks. Each row flags a specific check for one parameter.",
          tags$br(), tags$br(),
          div(style = "display:flex; flex-direction:column; gap:7px; margin-bottom:10px;",
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#92400E; background:#FEF3C7; border:1px solid #F59E0B; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", "Missing"),
              tags$strong("(amber)"), " — the parameter was not in your upload and was auto-filled from the IPCC default. Verify or replace with country-specific data."
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#991B1B; background:#FEE2E2; border:1px solid #EF4444; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", "Fail"),
              tags$strong("(red)"), " — the value or bounds will likely cause an error in the simulation."
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#92400E; background:#FEF3C7; border:1px solid #F59E0B; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", "Warn"),
              tags$strong("(amber)"), " — the value is unusual compared with IPCC defaults or Penman/Monni uncertainty references. Investigate and document."
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#1E40AF; background:#DBEAFE; border:1px solid #3B82F6; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", "Info"),
              tags$strong("(blue)"), " — informational only. Typically for emission factor parameters (EF3, EF4, EF5, Frac_*) where country-specific overrides are expected and the IPCC benchmark is a Monni-2007 / Penman-2000 mid-point, not a fixed table value. No action required unless the deviation is very large."
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#166534; background:#DCFCE7; border:1px solid #22C55E; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", "Pass"),
              tags$strong("(green)"), " — check satisfied."
            )
          ),
          "Fix any ", tags$strong("Fails"), " before running the simulation. ",
          tags$strong("Warnings"), " are advisory — document your justification for large deviations from IPCC defaults.",
          tags$br(), tags$br(),
          tags$strong("Auto-filled parameters: "),
          "If any parameters were absent from your upload, an ",
          tags$strong("Auto-filled parameters"),
          " panel appears above the results table showing which values were substituted from IPCC defaults. ",
          "Review these and replace with country-specific data in your template where possible."),
      conditionalPanel(
        condition = "output.has_imputed_params == true",
        div(style = "margin: 0 16px 16px 16px;",
            bslib::card(
              style = "border-left: 4px solid #F59E0B;",
              bslib::card_header(
                style = "background-color:#FEF3C7; color:#92400E; font-weight:600;",
                icon("triangle-exclamation"), " Auto-filled parameters"
              ),
              bslib::card_body(uiOutput("imputed_params_card"))
            ))
      ),
      bslib::layout_columns(
        col_widths = c(3, 9),
        bslib::card(
          bslib::card_header("Summary"),
          bslib::card_body(
            uiOutput("qaqc_summary_ui"),
            hr(),
            p(style = "font-size:0.83rem; color:#555;",
              "Checks run: bounds order, non-negative bounds, ",
              "valid ranges (DE_pct, Ym_pct, fractions), ",
              "distribution suitability (beta/lognormal/tnorm_0_1), ",
              "benchmark deviation vs. IPCC defaults (>50% = warn, >200% = fail), ",
              "and asymmetric-distribution warning for EF3/EF4/EF5/Frac_LEACH.")
          )
        ),
        bslib::card(
          bslib::card_header("QA/QC Results"),
          bslib::card_body(DT::DTOutput("qaqc_table"))
        )
      )
    ),

    # ==================== TAB 3: UNCERTAINTY ====================
    bslib::nav_panel(
      title = "3. Uncertainty",
      icon = icon("sliders-h"),
      div(class = "info-panel", style = "margin: 16px;",
          # A2: paragraphs cleanly separated to avoid mid-sentence break
          tags$p(
            tags$strong("What to do: "),
            "Review and adjust each parameter's probability distribution and uncertainty range. ",
            "Click any cell in the table below to edit the distribution type ",
            "(normal, lognormal, beta, triangular, pert, uniform, constant), ",
            "the uncertainty percentage, or the lower/upper bounds."
          ),
          tags$p(
            tags$strong("Note on triangular distributions: "),
            tags$em(
              "triangular is most often used when only the minimum, most-likely (mode), and maximum are known. ",
              "The tool treats lower/upper as ", tags$strong("absolute min/max"),
              ", not 95% CI bounds — for triangular, those are usually the same. ",
              "If you have a 95% CI but want a triangular shape, use PERT instead ",
              "(PERT uses the 95% bounds and a most-likely value)."
            )
          ),
          tags$p(
            tags$strong("Quick-set buttons"),
            " at the bottom of the table apply common settings to all parameters of one type ",
            "(e.g. 'Set all activity data to Normal ±15%')."
          )),
      bslib::card(
        bslib::card_header("Distribution & Uncertainty Specification"),
        bslib::card_body(DT::DTOutput("uncertainty_table")),
        # R2.1: quick-set buttons moved into card_footer so they remain visible
        # regardless of how tall the DT grows (pageLength = 20 was pushing them
        # below the fold). Labels rewritten in IPCC-aligned wording.
        bslib::card_footer(
          fluidRow(
            column(5, actionButton(
              "set_all_normal",
              label = textOutput("quickset_normal_label", inline = TRUE),
              class = "btn-outline-success btn-sm w-100")),
            column(5, actionButton(
              "set_all_pert",
              label = textOutput("quickset_pert_label", inline = TRUE),
              class = "btn-outline-primary btn-sm w-100"))
          ),
          tags$p(style = "font-size:0.78rem; color:#666; margin-top:6px;",
                 tags$em("Click a preset to apply; click the same button again to undo and restore your previous values."))
        )
      )
    ),

    # ==================== TAB 4: CORRELATIONS ====================
    bslib::nav_panel(
      title = "4. Correlations",
      icon = icon("th"),
      # 2026-05 UX overhaul: two-block intro (replaces the previous wall of text).
      # Block 1: plain-language "what is this page about?". Block 2: a small
      # decision tree so a first-time user can pick the right option without
      # reading the bullets.
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("What is this page about?"), tags$br(),
          "Real-world uncertainties don't usually live in separate boxes. If your body-weight estimate ",
          "is off because the census missed some animals, your population estimate is probably off too. ",
          "Telling the tool which parameters move together — ",
          tags$em("when you have evidence"), " — gives a more honest uncertainty range. ",
          "If you don't have evidence, leave everything on ",
          tags$strong("\"No correlations\""), ": that gives a conservative, defensible answer.",
          tags$br(), tags$br(),
          tags$strong("Quick guide — which option do I pick?"),
          tags$ul(style = "margin-top:6px; margin-bottom:0;",
            tags$li("Do you have ≥5 years of national time-series data in your upload? → ",
                    tags$strong("From template (auto, time-series)"), "."),
            tags$li("No time series, but you want to capture well-known biological linkages ",
                    "(BW ↔ MW, Milk ↔ Fat, DE ↔ Ym, …)? → ",
                    tags$strong("Structural defaults (expert-elicited)"), "."),
            tags$li("You have your own correlation matrix from a study or expert elicitation? → ",
                    tags$strong("Advanced — manual entry"), "."),
            tags$li("None of the above? → leave ", tags$strong("No correlations"),
                    " (the default; conservative and defensible).")
          )),
      bslib::layout_columns(
        col_widths = c(6, 6),

        # --- Activity data correlations ---
        bslib::card(
          bslib::card_header(
            tags$div(
              style = "display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;",
              tags$span("Activity Data Correlations"),
              # Lolita 2026-06-03 / Pete request: "Find out more" deep-link
              # to the topic page with worked examples. Opens in a new tab
              # so the user keeps their app session.
              tags$a(
                href = "docs/correlations.html", target = "_blank",
                icon("circle-info"),
                tags$span("Find out more", style = "margin-left:4px;"),
                style = paste("color:#2D6A4F; font-size:0.82rem; font-weight:500;",
                              "text-decoration:none; padding:4px 10px;",
                              "border:1px solid #2D6A4F; border-radius:14px;",
                              "background:#FFFFFF;")
              )
            )
          ),
          bslib::card_body(
            div(class = "info-panel",
                "Activity-data correlations describe how your input parameters move together. ",
                "If you have a multi-year ", tags$strong("Parameter_TimeSeries"),
                " sheet in your upload, the tool can learn the relationships from your own data. ",
                "If not, pick a preset or skip."),
            # 2026-06 Andreas review: the corr_mode radio is now rendered
            # server-side so that modes whose prerequisites are missing (TS
            # sheet empty / no manual CSV uploaded) appear visibly disabled.
            # Prevents the silent no-op that fooled Andreas' ZIM run.
            uiOutput("corr_mode_ui"),
            conditionalPanel(
              condition = "input.corr_mode == 'timeseries'",
              # 2026-06: the "Treatment of trends" select was removed. It
              # exposed three Spearman-detrending alternatives (first
              # differences / linear / raw) to the user, but the recommended
              # default ("first differences") is the right call almost every
              # time, and the choice is not something an Excel-fluent inventory
              # compiler should be asked to make. First differences is now
              # hardcoded in .compute_corr_now() — see R/app_server.R.
              uiOutput("corr_ts_status")
            ),
            conditionalPanel(
              condition = "input.corr_mode == 'preset'",
              div(class = "info-panel",
                  tags$strong("Structural defaults (expert-elicited): "),
                  "applies a sparse correlation matrix with seven well-documented structural pairs ",
                  "(BW ↔ MW, BW ↔ WG, Milk ↔ Fat, Milk ↔ BW, Milk ↔ DE, DE ↔ CP, DE ↔ Ym). ",
                  tags$em("Note: these values reflect documented biological/statistical relationships from the IPCC equations and the livestock literature — they are not IPCC-published correlation coefficients."),
                  " All other pairs are zero. Hover any non-zero cell in the heatmap for the per-pair source citation; full provenance and revision history are in the Methodology document.")
            ),
            conditionalPanel(
              condition = "input.corr_mode == 'manual'",
              div(class = "info-panel",
                  tags$strong("Advanced — manual matrix entry. "),
                  "Upload a CSV with parameter names as both column headers and the first column. ",
                  "Values must be in [-1, 1] with the diagonal = 1. ",
                  "Don't write the matrix from scratch — download one of the templates below, ",
                  "edit cells in Excel, save as CSV, and re-upload. ",
                  tags$strong("Missing parameters are assumed to have zero correlation: "),
                  "any parameter whose row/column is absent from the uploaded matrix (or whose name doesn't match the canonical list) is treated as independent of every other parameter — the simulation runs but no correlation is applied for that parameter."),
              # Lolita 2026-06-02 review: provide a concrete starting CSV so
              # users don't have to hand-type parameter names (typos would be
              # silently dropped downstream).
              div(style = "margin-bottom: 12px; display: flex; gap: 8px; flex-wrap: wrap;",
                  downloadButton("download_corr_template",
                                 "Download blank matrix template",
                                 class = "btn-outline-success btn-sm"),
                  downloadButton("download_corr_template_example",
                                 "Download matrix with example values",
                                 class = "btn-outline-primary btn-sm")),
              fileInput("corr_matrix_upload", "Upload correlation matrix (.csv)",
                        accept = ".csv")
            ),
            plotly::plotlyOutput("corr_heatmap", height = "350px")
          )
        ),

        # --- Emission factor correlations ---
        bslib::card(
          bslib::card_header("Coefficient Correlations (per-head EF inputs)"),
          bslib::card_body(
            div(class = "info-panel",
                "Emission factors can share systematic bias if they come from the same measurement literature. ",
                "The IPCC default is to treat them as independent. Pick block-structured if you suspect one ",
                "literature is biased — for example, all your energy-equation coefficients come from the same ",
                "regional database."),
            radioButtons("ef_corr_mode",
                         label = tagList(
                           "Mode ",
                           bslib::tooltip(
                             span(icon("circle-question"),
                                  style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                             "Should emission factors share systematic bias? The IPCC default is independence. Pick block-structured if you suspect one literature is biased (e.g. all your Ym-equation coefficients come from the same regional database).",
                             placement = "right"
                           )
                         ),
                         choices = c("No EF correlations (default)" = "none",
                                     "Block-structured EF correlation" = "block")),
            div(class = "small text-muted",
                style = "margin-top:-4px; margin-bottom:8px; font-size:0.82rem; line-height:1.45;",
                tags$ul(style = "padding-left:18px; margin:0;",
                  tags$li(tags$strong("No EF correlations (default)"),
                          " — emission factors are treated as independent. Standard IPCC Approach 2 assumption; ",
                          "appropriate when each EF comes from its own study."),
                  tags$li(tags$strong("Block-structured EF correlation"),
                          " — pick this when coefficients within the same measurement literature share bias ",
                          "(e.g. all rumen-fermentation coefficients from one regional database) but the three literatures ",
                          "are independent of one another.")
                )),
            conditionalPanel(
              condition = "input.ef_corr_mode == 'block'",
              # 2026-05 UX overhaul: directional tooltips per slider so a
              # non-statistician understands what moving the slider does.
              # Each slider has a live "Currently:" caption below it
              # (driven by output$ef_rho_*_interp in app_server.R).
              sliderInput("ef_rho_energy",
                          label = tagList(
                            "Within-block ρ — Energy-equation coefficients (Cfi, Ca, C, Cp, Ym) ",
                            bslib::tooltip(
                              span(icon("circle-question"),
                                   style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                              "Move the slider toward 0.5 if you believe your energy-equation coefficients (Cfi, Ca, Ym, …) share a common bias — e.g. all derived from the same regional rumen-fermentation database. Move toward 0 if you treat them as independent. ρ = 0.3 means: if Ym is sampled at its 80th percentile in one iteration, the others are nudged up to about their 60th percentile on average.",
                              placement = "right"
                            )
                          ),
                          min = 0.0, max = 0.5, value = 0.0, step = 0.05),
              div(style = "font-size:0.78rem; color:#2D6A4F; margin-top:-6px; margin-bottom:10px;",
                  textOutput("ef_rho_energy_interp", inline = TRUE)),

              sliderInput("ef_rho_manureCH",
                          label = tagList(
                            "Within-block ρ — Manure-CH₄ coefficients (Bo, MCF, ASH) ",
                            bslib::tooltip(
                              span(icon("circle-question"),
                                   style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                              "Move toward 0.5 if Bo, MCF, ASH likely share systematic bias — e.g. all from one country's BMP / lagoon-temperature database. Move toward 0 if independent. ρ = 0.3 means: a high Bo iteration tends to come with a slightly high MCF.",
                              placement = "right"
                            )
                          ),
                          min = 0.0, max = 0.5, value = 0.0, step = 0.05),
              div(style = "font-size:0.78rem; color:#2D6A4F; margin-top:-6px; margin-bottom:10px;",
                  textOutput("ef_rho_manureCH_interp", inline = TRUE)),

              sliderInput("ef_rho_manureN",
                          label = tagList(
                            "Within-block ρ — Manure-N coefficients (EF3_PRP, EF4, EF5, Frac_GASM_PRP, Frac_LEACH_PRP, UE) ",
                            bslib::tooltip(
                              span(icon("circle-question"),
                                   style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                              "Move toward 0.5 if EF3_PRP, EF4, EF5, Frac_GASM_PRP, Frac_LEACH_PRP all come from the same NH₃ / N₂O volatilisation programme. Move toward 0 if independent. ρ = 0.3 means moderate shared bias.",
                              placement = "right"
                            )
                          ),
                          min = 0.0, max = 0.5, value = 0.0, step = 0.05),
              div(style = "font-size:0.78rem; color:#2D6A4F; margin-top:-6px; margin-bottom:10px;",
                  textOutput("ef_rho_manureN_interp", inline = TRUE)),

              div(style = "font-size:0.82rem; color:#555; margin-top:4px;",
                  "These sliders only matter when you want to capture systematic measurement bias ",
                  tags$em("within"), " one literature. Cross-block correlation is always zero — ",
                  "the three coefficient groups come from independent measurement programmes."),
              # 2026-06: warn when all three sliders are at 0 — selecting
              # block-structured then leaving the sliders at zero is a silent
              # no-op exactly like the AD-side empty-TS issue.
              uiOutput("ef_rho_all_zero_warning")
            ),
            plotly::plotlyOutput("ef_corr_heatmap", height = "350px")
          )
        )
      )
    ),

    # ==================== TAB 5: SIMULATE & RESULTS (merged, B2) ====================
    bslib::nav_panel(
      title = "5. Simulate & Results",
      icon = icon("play"),
      value = "5. Simulate & Results",
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("What to do: "),
          "Configure simulation settings on the left, then click ",
          tags$strong("'Run Monte Carlo Simulation'"),
          " at the bottom of the left-hand panel. ",
          "The tool will sample all parameters from their distributions and run the IPCC equation chain ",
          "thousands of times. 10,000+ iterations recommended; check convergence by re-running with a different seed (1,000 is fine for quick testing). ",
          tags$br(), tags$br(),
          tags$strong("Once the simulation completes, this tab switches to the results view automatically."),
          " Use the ", tags$em("Back to settings"), " button at the top of the results to change inputs and re-run — the next run will switch back to results when it finishes. ",
          "Tab 7 (Sensitivity) and Tab 8 (IPCC Report) provide deeper drill-downs.",
          tags$br(), tags$br(),
          tags$strong("How many iterations to use: "),
          "Use ", tags$strong("1,000 only for a quick test run"),
          " to check that the model runs. Use a ", tags$strong("minimum of 10,000 iterations"),
          " for any result you intend to use — convergence is not guaranteed below 10,000. ",
          "Higher is always better: 25,000–30,000 is recommended for final reporting, especially when correlations are enabled or you have many sub-categories. ",
          "To verify convergence, re-run with a different random seed: if the 95% MoE changes by more than ~2 percentage points, increase the number of iterations."),
      # R1.5: view toggle — output.sim_view is "settings" or "results"
      conditionalPanel(
        condition = "output.sim_view != 'results'",
        bslib::layout_columns(
        col_widths = c(4, 8),
        bslib::card(
          bslib::card_header("Simulation Settings"),
          bslib::card_body(
            sliderInput("n_iter", "Number of Iterations",
              min = 1000, max = 50000, step = 1000,
              value = 10000, sep = ","),
            numericInput("seed",
              label = tagList(
                "Random Seed (for reproducibility) ",
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  "Fixing the seed makes results exactly reproducible — anyone using the same data, settings, and seed will get the same numbers. To check convergence, re-run with a different seed (e.g. 123 or 456): if the 95% MoE changes by more than ~2 percentage points, increase the number of iterations.",
                  placement = "right"
                )
              ),
              value = 42),
            # Andreas 2026-05 follow-up: Dirichlet MMS-allocation control removed
            # (no IPCC citation). MMS% is now treated deterministically across
            # iterations, matching the IPCC Inventory Software's behaviour.
            selectInput("gwp_version",
              label = tagList(
                "GWP Assessment Report ",
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  "GWP (Global Warming Potential) converts CH₄ and N₂O emissions to CO₂ equivalent for reporting. AR5 (CH₄=28, N₂O=265) is the most commonly required for current IPCC submissions. AR6 (CH₄=27, N₂O=273) is the latest IPCC assessment. Use whichever version your national reporting guidelines specify.",
                  placement = "right"
                )
              ),
              choices = c("AR4 (CH₄=25)" = "AR4",
                          "AR5 (CH₄=28, N₂O=265)" = "AR5",
                          "AR6 (CH₄=27, N₂O=273)" = "AR6"),
              selected = "AR5"),
            # T1.12 / R1.4: emission source selector — none ticked by default,
            # forcing the user to make an explicit choice before running.
            checkboxGroupInput("emission_sources", "Emission sources to include",
                               choices = c(
                                 "Enteric fermentation CH₄"            = "enteric_ch4",
                                 "Manure management CH₄"               = "manure_ch4",
                                 "Manure management N₂O direct"        = "manure_n2o_direct",
                                 "Manure management N₂O indirect"      = "manure_n2o_indirect",
                                 "Pasture deposition N₂O direct"       = "pasture_n2o_direct",
                                 "Pasture deposition N₂O indirect"     = "pasture_n2o_indirect"
                               ),
                               selected = character(0)),
            uiOutput("select_all_btn"),
            div(style = "font-size:0.78rem; color:#92400E; background:#FEF3C7; padding:8px 10px; border-radius:6px; margin-bottom:8px; margin-top:4px;",
                icon("exclamation-triangle"),
                tags$strong(" Tick at least one source above"),
                " — the simulation cannot run without an explicit selection. ",
                tags$em("(Most users tick all 6 for a full inventory.)")),
            hr(),
            # Round 9: single-year-only options (decomposition + comparison).
            # Trend mode doesn't use these — the trend's IPCC-§3.7 framework
            # already separates AD vs coefficient via the year_corr radio.
            conditionalPanel(
              condition = "input.analysis_mode != 'trend'",
              checkboxInput("run_decomposition", "Run uncertainty decomposition (AD/EF/Combined)",
                            value = TRUE),
              # Round 6a #5: rendered server-side so we can grey it out when no
              # correlations are selected on Tab 4 (the comparison would be
              # identical, so the toggle is meaningless).
              uiOutput("run_comparison_ui")
            ),
            # Round 9: trend-only settings (year-correlation mode).
            # Visible only when 'trend' is picked on Home.
            # 2026-05 UX overhaul: the "optional separate CSV override" section
            # was removed — the Parameter_TimeSeries sheet in the main upload is
            # now the single source of trend data. Each radio choice carries
            # its own tooltip with concrete "when to pick this" guidance.
            conditionalPanel(
              condition = "input.analysis_mode == 'trend'",
              hr(),
              radioButtons("year_corr",
                            label = tagList(
                              "Year-to-year correlation ",
                              bslib::tooltip(
                                span(icon("circle-question"),
                                     style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                                "How should the IPCC coefficients (Cfi, Ca, Ym, Bo, MCF, EF3, EF4, EF5, …) move from one year to the next within a single Monte Carlo iteration? IPCC V1 Ch3 §3.2.3 (Trend section) says emission factors are typically estimated once and reused across years, so the default is full correlation. Activity data (N, BW, Milk, …) are always re-estimated each year regardless of this setting.",
                                placement = "right"
                              )
                            ),
                            choices = c(
                              "Fully correlated coefficients (IPCC 2019 default)" = "full",
                              "Partial (AR(1), ρ=0.7)"                       = "partial",
                              "Independent (no year-to-year correlation)"         = "none"),
                            selected = "full"),
              div(class = "small text-muted",
                  style = "margin-top:-4px; margin-bottom:8px; font-size:0.82rem; line-height:1.45;",
                  tags$ul(style = "padding-left:18px; margin:0;",
                    tags$li(tags$strong("Fully correlated coefficients (IPCC 2019 default)"),
                            " — same coefficient draw is reused for every year within one Monte Carlo iteration. ",
                            "Trend uncertainty then reflects only the year-to-year changes in your activity data ",
                            "(N, BW, Milk, …); coefficient uncertainty cancels because Ym is the same in 2010 and 2022. ",
                            tags$em("Pick this if your emission factors are IPCC defaults or come from a single estimation programme reused across the whole inventory series.")),
                    tags$li(tags$strong("Partial (AR(1), ρ=0.7)"),
                            " — coefficient draws drift slowly between years (last year's value gets 70% weight, a fresh draw 30%). ",
                            tags$em("Pick this if your emission factors are re-estimated periodically but neighbouring years share most of the same observational basis "),
                            "— e.g. your country reviewed Ym every 5 years and the value drifted slightly each time."),
                    tags$li(tags$strong("Independent (no year-to-year correlation)"),
                            " — coefficient draws are sampled fresh each year. Maximises the EF contribution to trend uncertainty. ",
                            tags$em("Pick this only if you genuinely re-measured every emission factor every year with fully new field data "),
                            "— rarely realistic for a national inventory.")
                  )),
              div(style = "font-size:0.78rem; color:#92400E; background:#FEF3C7; padding:6px 10px; border-radius:4px; margin-bottom:8px;",
                  icon("info-circle"),
                  tags$em(" Trend mode runs n_iter simulations ", tags$strong("per year"),
                          " — total compute = n_iter × number of years."))
            ),
            hr(),
            # Round 9: route the Run button by mode. Single-year shows the
            # MC button (existing handler), trend shows Run Trend (existing
            # observeEvent(input$run_trend) handler).
            conditionalPanel(
              condition = "input.analysis_mode != 'trend'",
              actionButton("run_sim", "Run Monte Carlo Simulation",
                           class = "run-btn w-100", icon = icon("play"))
            ),
            conditionalPanel(
              condition = "input.analysis_mode == 'trend'",
              actionButton("run_trend", "Run Trend Analysis",
                           class = "run-btn w-100", icon = icon("play")),
              hr(),
              uiOutput("trend_status")
            ),
            hr(),
            uiOutput("sim_status")
          )
        ),
        bslib::card(
          bslib::card_header("Simulation Log"),
          bslib::card_body(
            verbatimTextOutput("sim_log")
          )
        )
      )
      ),  # close R1.5 conditionalPanel for settings

      # ==== Results section (merged into Tab 5 per B2 / R1.5) ====
      conditionalPanel(
        condition = "output.sim_view == 'results'",
        div(style = "margin: 12px 16px;",
            actionButton("show_settings_btn", HTML("&#8592; Back to settings"),
                         class = "btn-outline-secondary",
                         icon = icon("arrow-left"))),
        h3("Simulation results", style = "margin: 8px 16px;"),

        # Round 9: single-year results layout (visible when mode != trend)
        # Andreas 2026-05 C1: headline value-boxes by IPCC source category
        # instead of total CH₄ / N₂O. CV and Margin of Error moved into the
        # inline footnote alongside Total CO₂eq.
        conditionalPanel(
          condition = "input.analysis_mode != 'trend'",
          bslib::layout_columns(
            col_widths = NULL,
            bslib::value_box(title = "Enteric CH₄ (t)",
                              value = textOutput("vb_enteric_ch4"),
                              showcase = icon("fire"), theme = "success"),
            bslib::value_box(title = "Manure CH₄ (t)",
                              value = textOutput("vb_manure_ch4"),
                              showcase = icon("recycle"), theme = "success"),
            bslib::value_box(title = "Manure N₂O (t)",
                              value = textOutput("vb_manure_n2o"),
                              p("Direct + indirect"),
                              showcase = icon("cloud"), theme = "primary"),
            bslib::value_box(title = "Pasture N₂O (t)",
                              value = textOutput("vb_pasture_n2o"),
                              p("Direct + indirect"),
                              showcase = icon("seedling"), theme = "primary"),
            # Andreas 28/5/26 #6: the headline uncertainty bubble now shows
            # 95% MoE (the IPCC reporting convention per Vol.1 Ch.3 Table 3.3)
            # instead of CV. CV is still available alongside MoE in the
            # by-system / by-category tables further down the page.
            bslib::value_box(title = "Total 95% MoE (%)",
                              value = textOutput("vb_moe_total"),
                              p("± half-width of 95% CI / mean — IPCC convention"),
                              showcase = icon("percent"), theme = "warning")
          ),
          div(style = "padding: 0 12px 8px; color: #555; font-size: 0.85rem;",
              tags$em("Total CO₂eq: "), textOutput("vb_co2e_inline", inline = TRUE),
              tags$em(" · 95% MoE: "), textOutput("vb_moe", inline = TRUE),
              tags$em(" · Total CH₄: "), textOutput("vb_ch4", inline = TRUE),
              tags$em(" · Total N₂O: "), textOutput("vb_n2o", inline = TRUE)),
          # Andreas 28/5/26 #7.1: headline split by cattle_type so dairy and
          # non-dairy contributions are visible without having to drill into
          # the aggregation-level selector below. Only rendered when the
          # inventory has more than one cattle_type.
          conditionalPanel(
            condition = "output.has_multi_cattle_type == true",
            bslib::card(
              bslib::card_header("Headline by cattle type (dairy / other)"),
              bslib::card_body(
                p(tags$em(style = "color:#555; font-size:0.85rem;",
                  "One row per cattle_type from the Parameters sheet. ",
                  "Per-source means are inventory-summed across iterations; ± is the 95 % margin of error (MoE).")),
                DT::DTOutput("results_headline_by_cattle_type")
              )
            )
          ),
          bslib::layout_columns(
            col_widths = c(6, 6),
            bslib::card(
              bslib::card_header("Emission Distribution (Total CO₂eq)"),
              bslib::card_body(plotly::plotlyOutput("results_histogram"))
            ),
            bslib::card(
              bslib::card_header("Uncertainty Decomposition"),
              bslib::card_body(
                plotly::plotlyOutput("decomposition_plot")
              )
            )
          ),

          # ---- Diagnostic trigger button (appears after simulation runs) ----
          conditionalPanel(
            condition = "output.has_diagnostics == true",
            div(style = "text-align:center; margin: 12px 0 4px 0;",
              actionButton("toggle_diagnostics",
                           label = tagList(icon("magnifying-glass"), " Run Diagnostic"),
                           class = "btn btn-danger",
                           style = "font-weight:600; padding:8px 28px; font-size:0.95rem;")
            )
          ),

          # ---- Collapsible diagnostic panel ----
          conditionalPanel(
            condition = "output.show_diagnostics == true",
            bslib::card(
              style = "border:2px solid #EF4444; margin-bottom:4px;",
              bslib::card_header(
                div(style = "display:flex; align-items:center; gap:8px;",
                    icon("magnifying-glass", style = "color:#EF4444;"),
                    tags$strong("Simulation Diagnostics"),
                    tags$span(
                      style = paste0("font-size:0.75rem; color:#6B6B6B; background:#F3F4F6;",
                                     "border:1px solid #E0DDD5; border-radius:4px; padding:1px 8px;"),
                      "Monte Carlo quality checks"
                    )
                )
              ),
              bslib::card_body(
                div(class = "info-panel",
                    icon("circle-info"),
                    " These checks tell you whether your simulation ran long enough to produce trustworthy results. ",
                    "All three quality checks should be ", tags$strong("green (Pass)"),
                    " before submitting results. If any show ",
                    tags$strong("Warn"), " or ", tags$strong("Fail"),
                    ", go back to the Simulate tab, increase the number of iterations, and re-run.",
                    tags$br(),
                    tags$em(style = "color:#555; font-size:0.85rem;",
                            icon("circle-info", style = "font-size:0.8rem;"),
                            " Note: this tool uses ", tags$strong("independent Monte Carlo"), " — not MCMC. ",
                            "Each iteration is drawn independently, so there are no chains, no warmup, and no burn-in. ",
                            "The diagnostics above replace the multi-chain Gelman-Rubin checks used in Bayesian MCMC.")),
                div(style = "margin-top:14px;",
                    uiOutput("diag_badges")),
                bslib::card(
                  style = "margin-top:18px; border:1px solid #E0DDD5;",
                  bslib::card_header(
                    div(style = "display:flex; align-items:center; gap:6px;",
                        "Convergence trace",
                        bslib::tooltip(
                          span(icon("circle-question"), style = "color:#6B6B6B; cursor:help;"),
                          paste0("This plot shows how the running mean (dark green) and the 95% confidence interval bounds (blue dashes) ",
                                 "evolve as more iterations are added. If the lines flatten out well before the last iteration, ",
                                 "the simulation has converged. If the lines are still changing near the right edge of the plot, ",
                                 "you need more iterations."),
                          placement = "right"
                        )
                    )
                  ),
                  bslib::card_body(
                    plotly::plotlyOutput("convergence_plot", height = "260px")
                  )
                )
              )
            )
          ),

          # Andreas 2026-05 #32, C2: aggregation level selector — default to
          # cattle_type (IPCC reporting convention: dairy / other cattle), with
          # optional drill-down to aggregation_level (production system) or
          # sub_category for advanced users.
          div(style = "padding: 0 16px 8px; display: flex; align-items: center; gap: 12px;",
              tags$strong("Aggregation level:"),
              selectInput("results_aggregation_level", label = NULL,
                          choices = c(
                            "Cattle type (dairy / other)"  = "cattle_type",
                            "Production system"            = "aggregation_level",
                            "Sub-category"                 = "sub_category"),
                          selected = "cattle_type",
                          width = "260px"),
              tags$em(style = "color:#666; font-size:0.85rem;",
                      "Tables below aggregate per-iteration results at this level.")),
          bslib::card(
            bslib::card_header("By-System Breakdown"),
            bslib::card_body(DT::DTOutput("results_by_system"))
          ),
          bslib::card(
            bslib::card_header("By Reporting Category (IPCC Table 3.3 layout)"),
            bslib::card_body(
              p("Each row is one IPCC inventory reporting line (group × source). ",
                "Rows match the granularity used in IPCC Volume 1 Chapter 3 uncertainty reporting."),
              DT::DTOutput("results_by_category")
            )
          ),
          uiOutput("comparison_card")
        ),

        # Round 9 follow-up: trend results layout — mirrors single-year's
        # value-boxes-then-charts pattern but with trend-specific metrics.
        conditionalPanel(
          condition = "input.analysis_mode == 'trend'",
          bslib::layout_columns(
            col_widths = c(3, 3, 3, 3),
            bslib::value_box(title = "Δ vs base year",
                              value = textOutput("vb_trend_delta"),
                              p(textOutput("vb_trend_delta_sub", inline = TRUE)),
                              showcase = icon("arrow-trend-up"), theme = "primary"),
            bslib::value_box(title = "Trend slope",
                              value = textOutput("vb_trend_slope"),
                              p(textOutput("vb_trend_slope_sub", inline = TRUE)),
                              showcase = icon("chart-line"), theme = "success"),
            bslib::value_box(title = "Latest year",
                              value = textOutput("vb_trend_latest"),
                              p(textOutput("vb_trend_latest_sub", inline = TRUE)),
                              showcase = icon("calendar-days"), theme = "info"),
            bslib::value_box(title = "Largest YoY change",
                              value = textOutput("vb_trend_yoy"),
                              p(textOutput("vb_trend_yoy_sub", inline = TRUE)),
                              showcase = icon("bolt"), theme = "warning")
          ),
          div(style = "padding: 0 12px 8px; color: #555; font-size: 0.85rem;",
              tags$em(textOutput("vb_trend_inline", inline = TRUE))),
          bslib::layout_columns(
            col_widths = c(7, 5),
            bslib::card(
              bslib::card_header("Trend chart — Total CO₂eq with 95% CI band"),
              bslib::card_body(plotly::plotlyOutput("trend_plot", height = "360px"))
            ),
            bslib::card(
              bslib::card_header("Year-over-year % change"),
              bslib::card_body(plotly::plotlyOutput("trend_yoy_chart", height = "360px"))
            )
          ),
          bslib::card(
            bslib::card_header("Distribution of Δ Y_N − Y_1 — uncertainty on the trend itself"),
            bslib::card_body(
              p(tags$em("This histogram shows the Monte Carlo distribution of the absolute change in CO₂eq between the first and last year. The dashed red lines mark the 95% CI; the dotted line marks zero. If zero falls inside the CI, the trend is not statistically distinguishable from no change at this confidence level.")),
              plotly::plotlyOutput("trend_delta_histogram", height = "300px")
            )
          ),
          bslib::card(
            bslib::card_header("Trend table"),
            bslib::card_body(
              p(tags$em("Year-by-year mean, 95% CI bounds, 95% MoE, Δ vs. base year, and year-over-year change.")),
              DT::DTOutput("trend_table")
            )
          ),
          div(style = "margin: 8px 16px; font-size:0.85rem; color:#555;",
              tags$em("Sensitivity drivers (per-year + Δ Y_N − Y_1) are on Tab 6 (Sensitivity). Word / Excel / CSV trend reports are on Tab 7 (IPCC Report)."))
        )
      ),
      # R1.5: placeholder removed — settings panel itself shows when sim_view is settings
    ),

    # ==================== TAB 6: SENSITIVITY ====================
    # Round 9 follow-up: branches by analysis_mode like Tab 5 / Tab 7.
    # Single mode shows the existing single-year sensitivity (tornado +
    # rankings table); trend mode shows the per-year + Δ tornadoes
    # previously displayed inside Tab 5's results panel.
    bslib::nav_panel(
      title = "6. Sensitivity",
      icon = icon("bullseye"),

      # ---------- Single-year sensitivity ----------
      conditionalPanel(
        condition = "input.analysis_mode != 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong("What to do: "),
            "This page shows which input parameters contribute most to the overall emission uncertainty. ",
            "The ", tags$strong("tornado chart"), " on the left ranks parameters by their influence -- ",
            "longer bars mean more influential parameters. Green bars indicate a positive relationship ",
            "(higher value = higher emissions) and red bars indicate a negative relationship. ",
            "Use the dropdown on the right to switch between SRC (linear influence) and PRCC (rank-based, more robust). ",
            tags$br(), tags$br(),
            tags$strong("Note: "),
            tags$em("These rankings show which parameters drive the "),
            tags$em(tags$strong("uncertainty")),
            tags$em(" of total emissions, not the absolute emission level."),
            tags$br(),
            tags$strong("Action item: "), "Focus your data improvement efforts on the top 3-5 parameters ",
            "to get the biggest reduction in overall inventory uncertainty.",
            tags$br(), tags$br(),
            tags$strong("Sensitivity methods explained: "),
            tags$strong("SRC (Standardized Regression Coefficients)"),
            " — fits a linear model between each input parameter and the output; fast and easy to interpret. ",
            "A positive SRC means higher values of that input produce higher emissions. ",
            tags$strong("PRCC (Partial Rank Correlation Coefficients)"),
            " — rank-based method, more robust when the input-output relationship is non-linear or when the output distribution is skewed. ",
            "For most livestock inventories both methods give similar rankings. ",
            "Use PRCC as a cross-check when SRC rankings seem counterintuitive or when distributions are highly asymmetric."),
        uiOutput("sens_view_toggle"),
        div(style = "margin: 0 16px 12px 16px; display: flex; gap: 20px; flex-wrap: wrap; align-items: flex-end;",
            selectInput("sens_source", "Output variable",
                        choices = c(
                          "Total CO₂eq (all sources)"             = "total_co2e",
                          "Enteric fermentation CH₄"              = "enteric_ch4_total",
                          "Manure management CH₄"                 = "manure_ch4_total",
                          "Manure management N₂O direct"          = "direct_n2o_mm_total",
                          "Manure management N₂O indirect"        = "indirect_n2o_mm_total",
                          "Pasture deposition N₂O direct"         = "direct_n2o_prp_total",
                          "Pasture deposition N₂O indirect"       = "indirect_n2o_prp_total"
                        ),
                        selected = "total_co2e", width = "340px"),
            uiOutput("sens_group_filter_ui")
        ),
        bslib::layout_columns(
          col_widths = c(6, 6),
          bslib::card(
            bslib::card_header("Tornado Chart - Top Parameters"),
            bslib::card_body(plotly::plotlyOutput("tornado_chart"))
          ),
          bslib::card(
            bslib::card_header("Sensitivity Rankings"),
            bslib::card_body(
              selectInput("sens_method", "Method",
                          choices = c("Standardized Regression (SRC)" = "src",
                                      "Partial Rank Correlation (PRCC)" = "prcc")),
              DT::DTOutput("sensitivity_table")
            )
          )
        )
      ),

      # ---------- Trend sensitivity ----------
      conditionalPanel(
        condition = "input.analysis_mode == 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong("What to do: "),
            "Trend sensitivity has two complementary views. ",
            tags$strong("Per-year (latest)"),
            " — which parameters dominate the uncertainty in the most recent year. ",
            tags$strong("Trend driver (Δ Y_N − Y_1)"),
            " — which parameters drive the change between the first and last year (per IPCC Vol 1 Ch 3 §3.7). ",
            "Bars are coloured by ", tags$strong("user-reducibility"),
            " (same scheme as the single-year tornado): ",
            tags$span(style = "color:#2D6A4F;font-weight:bold;", "■ green"),
            " = the user can improve uncertainty on this parameter with better local data; ",
            tags$span(style = "color:#78909C;font-weight:bold;", "■ grey"),
            " = IPCC coefficient (requires dedicated measurement research to improve). ",
            tags$br(), tags$br(),
            tags$strong("Action item: "),
            "Focus your data improvement efforts on green-coloured parameters in the top 5 — those give you the biggest uncertainty reduction with locally-collectible data."),
        h4("Per-year drivers (latest year)",
            style = "color:#1B4332; margin: 8px 16px 4px;"),
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            bslib::card_header("Tornado — top 10"),
            bslib::card_body(plotly::plotlyOutput("trend_tornado_per_year_sens",
                                                   height = "420px"))
          ),
          bslib::card(
            bslib::card_header("Rankings — top 15 (SRC + PRCC)"),
            bslib::card_body(DT::DTOutput("trend_sens_per_year_table"))
          )
        ),
        h4("Trend driver (Δ Y_N − Y_1)",
            style = "color:#1B4332; margin: 16px 16px 4px;"),
        div(style = "margin: 0 16px 8px; font-size:0.82rem; color:#666;",
            tags$em("Combined Y_1 + Y_N inputs are sensitivity-tested against the per-iteration ΔCO₂eq. Suffixes _y1 / _yN distinguish the same parameter at different years.")),
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            bslib::card_header("Tornado — top 10"),
            bslib::card_body(plotly::plotlyOutput("trend_tornado_delta_sens",
                                                   height = "420px"))
          ),
          bslib::card(
            bslib::card_header("Rankings — top 15 (SRC + PRCC)"),
            bslib::card_body(DT::DTOutput("trend_sens_delta_table"))
          )
        )
      )
    ),

    # ==================== TAB 7: IPCC REPORT (last app tab) ====================
    # Round 8 moved this to last position. Round 9 collapses the standalone
    # Trend tab into here: content swaps based on input$analysis_mode, so the
    # report a user sees matches the route they picked on Home (single year vs
    # trend). The downloads on each side are mode-specific too.
    bslib::nav_panel(
      title = "7. IPCC Report",
      icon = icon("file-alt"),

      # ---------- Single-year report layout ----------
      conditionalPanel(
        condition = "input.analysis_mode != 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong("What to do: "),
            "This page shows your uncertainty results formatted as IPCC Table 3.3, ready for your national ",
            "inventory submission. ",
            "The table has three uncertainty columns — ",
            tags$strong("AD uncertainty (%)"), ", ",
            tags$strong("EF uncertainty (%)"), ", and ",
            tags$strong("Combined uncertainty (%)"),
            " — all expressed as ", tags$strong("% uncertainty"), " (half-width of the 95% CI ÷ mean × 100), ",
            "following IPCC 2006 Vol. 1 Ch. 3 Table 3.3 conventions. ",
            "AD = population/activity-data uncertainty only; EF = per-head emission factor uncertainty driven by the 23 IPCC coefficients; Combined = both sources together. ",
            "Click ", tags$strong("'Download Excel Report'"), " to get a complete workbook with all results, ",
            "sensitivity rankings, run settings, and metadata. Click ", tags$strong("'Download CSV'"), " for a simpler file ",
            "with uncertainty metrics only."),
        div(style = "margin: 0 16px 12px; font-size:0.82rem; color:#1B4332; background:#D8F3DC; border-left:3px solid #2D6A4F; padding:10px 12px; border-radius:4px;",
            tags$strong("AD vs EF column convention: "),
            "in this version, ", tags$em("AD"),
            " = population uncertainty only (N), and ", tags$em("EF"),
            " = the per-head emission factor uncertainty driven by the IPCC coefficients (live weight, feed quality, ",
            "Ym, Bo, EF3_PRP, etc.). This matches IPCC Volume 1 Chapter 3 reporting conventions."),
        bslib::card(
          bslib::card_header("IPCC Table 3.3 - Uncertainty Report"),
          bslib::card_body(
            uiOutput("ipcc_table_notice"),
            DT::DTOutput("ipcc_table"),
            hr(),
            fluidRow(
              column(3, downloadButton("download_xlsx", "Download Excel Report",
                                        class = "btn-success")),
              column(3, downloadButton("download_csv", "Download CSV",
                                        class = "btn-outline-success")),
              column(3, downloadButton("download_docx", "Download Word summary",
                                        class = "btn-primary"))
            )
          )
        ),
        bslib::card(
          bslib::card_header("Uncertainty distributions per emission source"),
          bslib::card_body(
            p("Histograms of the Monte Carlo output for each emission source. ",
              "Useful for third-party QA review of which sources contribute the most variance. ",
              "When you hover over a bar, the tooltip shows two numbers: ",
              "the ", tags$strong("x-range"), " (e.g. '37k–38k') is the emission value interval for that bin in tonnes — ",
              "the width of this interval reflects the spread of the distribution for that source; ",
              "the ", tags$strong("count"), " (e.g. '530') is the number of Monte Carlo iterations that fell in that bin. ",
              "A narrow x-range with a tall peak indicates low uncertainty; a wide x-range with a flat histogram indicates high uncertainty."),
            plotly::plotlyOutput("report_source_histograms", height = "420px")
          )
        ),
        bslib::card(
          bslib::card_header("Top sensitivity drivers (Total CO₂eq)"),
          bslib::card_body(
            p("Standardised regression coefficients for the top 10 input parameters driving total uncertainty."),
            plotly::plotlyOutput("report_tornado", height = "380px")
          )
        ),
        bslib::card(
          bslib::card_header("Input distributions used"),
          bslib::card_body(
            p("Density plots of each input parameter's fitted distribution — confirms each ",
              "parameter was sampled with the marginal distribution specified in the input table."),
            plotly::plotlyOutput("report_input_densities", height = "520px")
          )
        ),
        bslib::card(
          bslib::card_header("Input parameters used in this run"),
          bslib::card_body(
            p("Full record of every parameter value, distribution, and bounds ",
              "used in the simulation — included for inventory documentation and ",
              "third-party QA review."),
            DT::DTOutput("inputs_doc_table")
          )
        )
      ),

      # ---------- Trend report layout ----------
      conditionalPanel(
        condition = "input.analysis_mode == 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong("What to do: "),
            "This page presents the trend results — year-by-year totals, the trend slope and Δ across years with their own 95% CIs, and the sensitivity drivers per IPCC Vol 1 Ch 3 §3.7. ",
            "Use the downloads below to export the trend report as Excel (multi-sheet workbook), CSV (table only), or Word (full IPCC-style narrative report including the executive summary and methodological notes on the year-correlation mode you chose)."),
        bslib::card(
          bslib::card_header("Trend report — downloads"),
          bslib::card_body(
            p(tags$em("Available after a successful trend run on the Simulate tab. Filename includes the year-correlation mode you picked.")),
            fluidRow(
              column(3, downloadButton("download_trend_xlsx", "Download Excel Report",
                                        class = "btn-success")),
              column(3, downloadButton("download_trend_csv", "Download CSV",
                                        class = "btn-outline-success")),
              column(3, downloadButton("download_trend_docx", "Download Word summary",
                                        class = "btn-primary"))
            )
          )
        ),
        bslib::card(
          bslib::card_header("Trend chart — Total CO₂eq with 95% CI band"),
          bslib::card_body(plotly::plotlyOutput("trend_plot_report", height = "400px"))
        ),
        bslib::card(
          bslib::card_header("Trend table"),
          bslib::card_body(
            p(tags$em("Year-by-year mean, 95% CI bounds, CV%, MoE%, Δ vs. base year, and year-over-year change.")),
            DT::DTOutput("trend_table_report")
          )
        ),
        bslib::card(
          bslib::card_header("Sensitivity drivers (per-year + trend)"),
          bslib::card_body(
            p(tags$em("Per-year tornado shows drivers of the latest year; Δ Y_N − Y_1 tornado shows what drives the change between the first and last year (per IPCC Vol 1 Ch 3 §3.7).")),
            bslib::layout_columns(
              col_widths = c(6, 6),
              div(
                h6("Per-year (latest)", style = "color:#1B4332;"),
                plotly::plotlyOutput("trend_tornado_per_year_report", height = "320px")
              ),
              div(
                h6("Trend driver (Δ Y_N − Y_1)", style = "color:#1B4332;"),
                plotly::plotlyOutput("trend_tornado_delta_report", height = "320px")
              )
            )
          )
        )
      )
    ),

    # ==================== TAB 9: CONTACT / FEEDBACK ====================
    # Round 8: client-side Web3Forms submission. The form HTML below posts
    # directly from the visitor's browser to https://api.web3forms.com/submit
    # — Web3Forms restrict server-side POST on the free tier, so we use their
    # recommended client-side fetch() pattern. The Shiny server is bypassed
    # for the actual relay; the access key (which is public-facing by design,
    # see R/utils_contact.R) is embedded in the form.
    bslib::nav_panel(
      title = "Contact / Feedback",
      icon = icon("envelope"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong("We welcome feedback, bug reports, feature suggestions, and methodology questions."),
          tags$br(), tags$br(),
          "Submissions are sent to the development team. We aim to reply within a few working days."),
      bslib::layout_columns(
        col_widths = c(6, 6),
        bslib::card(
          bslib::card_header("Send us a message"),
          # Round 9 follow-up: contact_form_html() returns a tagList (form HTML
          # + <style> + <script>). Pass it directly — wrapping in HTML() would
          # re-stringify the script and break the submit handler again.
          bslib::card_body(contact_form_html())
        ),
        bslib::card(
          bslib::card_header("What kind of feedback helps most"),
          bslib::card_body(
            tags$ul(
              tags$li(tags$strong("Bug reports"),
                      " — with steps to reproduce, the example dataset or your upload, and the error message."),
              tags$li(tags$strong("Methodology questions"),
                      " — e.g. how a particular IPCC equation is implemented, or whether your country's data fits the assumptions."),
              tags$li(tags$strong("Feature requests"),
                      " — missing parameters, additional emission sources, integration with national inventory tools."),
              tags$li(tags$strong("Documentation gaps"),
                      " — if a tab or label was confusing, tell us where you got stuck.")
            ),
            hr(),
            div(style = "font-size:0.8rem; color:#666;",
                tags$em("Privacy note: messages are relayed via Web3Forms, an HTTPS form-relay service. We don't store your message; we don't share your email."))
          )
        )
      )
    ),

    # Footer
    bslib::nav_spacer(),
    bslib::nav_item(
      tags$span(style = "color: #6B6B6B; font-size: 0.85rem;",
                "Developed by CIAT/CGIAR Alliance | Funded by Global Methane Hub")
    )
  )
}
