# Master UI Function
#
# Accepts `request` so we can read the `app_lang` cookie before building
# the UI. The current language is then stored in .LANG_CURRENT (see
# R/i18n.R) and every t("…") call during UI construction returns the
# matching language string. The language toggle in the navbar (defined
# below, right-side nav_item) writes the cookie + reloads the page; on
# reload, this function runs again with the new cookie value.
app_ui <- function(request = NULL) {
  i18n_set_lang(i18n_lang_from_request(request))
  bslib::page_navbar(
    id = "nav",
    # Round 9 follow-up: stacked header — big centered title row above the
    # tabs row. Title + subtitle live inside a flex column; CSS in
    # www/custom.css turns the navbar into vertical layout (title above
    # tabs) and centers both rows. The bg=transparent on .app-title keeps
    # the navbar's existing background.
    title = tags$div(
      class = "app-title-block",
      tags$div(class = "app-title", t("app_title")),
      tags$div(class = "app-subtitle", t("app_subtitle"))
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
         // 2026-06-11: persistent thinking-indicator watchdog. The dots
         // bubble painted by translatorAppendTypingBubble vanishes once
         // the first text chunk arrives, and the AI then often pauses
         // mid-message (Opus cache-write, network jitter, or tool_use
         // input_json_delta events that do not trigger the text-chunk
         // callback at all). If the user sees a static bubble for
         // >1.5s the work looks dead even when it is not.
         //
         // Solution: arm a timer on every chunk arrival. If no chunk in
         // 1.5s, append an inline animated 3-dot span at the end of
         // the current bubble. Remove the dots when the next chunk
         // arrives. The server also fires translatorStreamTick on
         // every tool_use input_json_delta event, which feeds this
         // same watchdog without exposing the JSON content.
         var _translatorWatchdogTimer = null;
         var _translatorWatchdogDots  = null;
         function _translatorMakeDotsSpan() {
           var span = document.createElement('span');
           span.setAttribute('data-translator-thinking-dots', '1');
           span.style.cssText = 'display:inline-flex; align-items:center;' +
             ' gap:4px; margin-left:6px; vertical-align:middle;';
           [0, 0.2, 0.4].forEach(function(delay) {
             var d = document.createElement('span');
             d.style.cssText = 'display:inline-block; width:5px; height:5px;' +
               ' background:#2D6A4F; border-radius:50%;' +
               ' animation: translatorDot 1.2s ease-in-out ' + delay + 's infinite;';
             span.appendChild(d);
           });
           return span;
         }
         function _translatorClearWatchdog() {
           if (_translatorWatchdogTimer) {
             clearTimeout(_translatorWatchdogTimer);
             _translatorWatchdogTimer = null;
           }
           if (_translatorWatchdogDots && _translatorWatchdogDots.parentNode) {
             _translatorWatchdogDots.parentNode.removeChild(_translatorWatchdogDots);
           }
           _translatorWatchdogDots = null;
         }
         function _translatorArmWatchdog() {
           _translatorClearWatchdog();
           _translatorWatchdogTimer = setTimeout(function() {
             if (!_translatorActiveBubble) return;
             _translatorWatchdogDots = _translatorMakeDotsSpan();
             _translatorActiveBubble.appendChild(_translatorWatchdogDots);
             var scroller = _translatorActiveBubble.closest('[data-translator-scroller]');
             if (scroller) scroller.scrollTop = scroller.scrollHeight;
           }, 1500);
         }
         // Server keep-alive ping. Fired on every Anthropic
         // input_json_delta event during tool_use streaming (the
         // force-template path is otherwise text-callback-silent for
         // its entire 5-15 min duration). No payload, just resets
         // the watchdog so the dots stay animated.
         Shiny.addCustomMessageHandler('translatorStreamTick', function(_unused) {
           // If the user is on the force-template path, there's no
           // _translatorActiveBubble yet (text chunks never arrive).
           // The dots ARE in the upstream typing-bubble in
           // #translator_stream_target — those animate on their own,
           // so we just rearm the watchdog so the bubble stays alive.
           _translatorArmWatchdog();
         });
         Shiny.addCustomMessageHandler('translatorStreamStart', function(_unused) {
           // 2026-06-10: with Claude Opus 4.8 + prompt-cache-write, the
           // gap between StreamStart and the first chunk is now 5-15s
           // (vs 1-3s on GPT-4.1). Wiping stream_target here would leave
           // the user staring at an empty bubble for that whole window
           // and the AI-is-working signal disappears.
           //
           // New rule: StreamStart only sets a flag. The first chunk does
           // the wipe + bubble creation. That way the dots typing-bubble
           // (painted by translatorAppendTypingBubble) animates the whole
           // way until real text is about to appear.
           _translatorActiveBubble = null;
         });
         Shiny.addCustomMessageHandler('translatorStreamChunk', function(text) {
           // First real token arrived — hide the pre-stream spinner now
           // (cheap no-op if it was already hidden).
           if (typeof _translatorHideSpinner === 'function') _translatorHideSpinner();
           // Lazy bubble creation on first chunk: wipes the typing-dots
           // bubble at the exact moment real text is ready to replace it,
           // not at StreamStart (which fires too early).
           if (!_translatorActiveBubble) {
             var container = document.getElementById('translator_stream_target');
             if (!container) return;
             container.innerHTML = '';
             var bubble = document.createElement('div');
             // Style MUST match the AI bubble style in chat_ui.R::output$translator_messages
             // so the streamed-live bubble looks identical to the rendered-
             // history bubble that replaces it once streaming ends.
             bubble.style.cssText = 'max-width:80%; margin:6px 0;' +
               'padding:10px 14px; border-radius:12px; white-space:pre-wrap;' +
               'font-size:0.92rem; line-height:1.45;' +
               'background:#E8F5E9; color:#1B4332; align-self:flex-start;' +
               'border:1px solid #C8E6C9;';
             container.appendChild(bubble);
             _translatorActiveBubble = bubble;
           }
           // Clear any inline thinking-dots before appending the new
           // text so they don't interleave with characters.
           _translatorClearWatchdog();
           _translatorActiveBubble.textContent += text;
           // auto-scroll the surrounding message-history div
           var scroller = _translatorActiveBubble.closest('[data-translator-scroller]');
           if (scroller) scroller.scrollTop = scroller.scrollHeight;
           // Rearm: if the next chunk takes >1.5s, dots reappear.
           _translatorArmWatchdog();
         });
         Shiny.addCustomMessageHandler('translatorStreamEnd', function(_unused) {
           // Streaming is done. Cancel the watchdog so no spurious dots
           // appear after the bubble is replaced by the rendered history.
           _translatorClearWatchdog();
           // Streaming is done. The canonical AI message is in state$messages
           // now and translator_messages has already re-rendered with it,
           // so the bubble we built up in #translator_stream_target is a
           // DUPLICATE. Clear the slot to avoid showing the same content
           // twice. (translator_stream_target is OUTSIDE the reactive
           // renderUI, so its contents persist across re-renders unless we
           // explicitly wipe them.)
           var container = document.getElementById('translator_stream_target');
           if (container) {
             // Cancel any progress-bar timers attached to bubbles we're
             // about to remove (force-template path uses these).
             Array.prototype.forEach.call(container.children, function(c) {
               if (c && c._translatorProgressInterval)
                 clearInterval(c._translatorProgressInterval);
             });
             container.innerHTML = '';
           }
           _translatorActiveBubble = null;
           // Also hide the pre-stream spinner — covers the non-streaming
           // force-template path where StreamStart never fires.
           if (typeof _translatorHideSpinner === 'function') _translatorHideSpinner();
         });
         // 2026-06: persistent sign-in. After magic-link consume, server
         // sends a signed cookie value here; we drop it into document.cookie
         // with a 100-year max-age — functionally permanent, so once an
         // email is approved the user stays signed in indefinitely on
         // this browser. On the next refresh the server reads the Cookie:
         // header (session$request$HTTP_COOKIE), HMAC-verifies it, and
         // restores the signed-in state without a fresh magic link.
         // Server-side ttl matches (auth_session_cookie_issue default).
         Shiny.addCustomMessageHandler('setTranslatorSession', function(value) {
           if (!value) return;
           var maxAge = 100 * 365 * 24 * 60 * 60;  // ~100 years in seconds
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
         // Simple typing-indicator bubble for the streaming chat wait
         // (~1-5 seconds between Enter and the first chunk). Replaces
         // the off-screen yellow pill that the user couldn't see during
         // long conversations. Cleared by translatorStreamStart (which
         // also wipes the stream_target before painting the live AI
         // bubble).
         Shiny.addCustomMessageHandler('translatorAppendTypingBubble', function(_unused) {
           var slot = document.getElementById('translator_stream_target');
           if (!slot) return;
           slot.innerHTML = '';
           var bubble = document.createElement('div');
           bubble.style.cssText = 'max-width:80%; margin:6px 0;' +
             'padding:10px 14px; border-radius:12px;' +
             'font-size:0.92rem; line-height:1.45;' +
             'background:#E8F5E9; color:#1B4332;' +
             'border:1px solid #C8E6C9; align-self:flex-start;' +
             'display:flex; align-items:center; gap:8px;';
           var dot1 = document.createElement('span');
           var dot2 = document.createElement('span');
           var dot3 = document.createElement('span');
           [dot1, dot2, dot3].forEach(function(d, i) {
             d.style.cssText = 'display:inline-block; width:6px; height:6px;' +
               'background:#2D6A4F; border-radius:50%;' +
               'animation: translatorDot 1.2s ease-in-out ' + (i * 0.2) + 's infinite;';
             bubble.appendChild(d);
           });
           slot.appendChild(bubble);
           var scroller = bubble.closest('[data-translator-scroller]');
           if (scroller) scroller.scrollTop = scroller.scrollHeight;
         });
         // Download click feedback — when the user clicks the green
         // Download button, the server takes 5-15 seconds to build the
         // multi-sheet .xlsx (style overlay + many cell writes). Without
         // feedback the user sees a frozen-looking app. Paint an inline
         // bubble in the conversation that auto-disappears after 20s
         // (or whenever the file actually downloads).
         document.addEventListener('click', function(e) {
           var t = e.target;
           if (!t) return;
           for (var i = 0; i < 4 && t; i++) {
             if (t.id === 'translator_download_template') {
               var slot = document.getElementById('translator_stream_target');
               if (!slot) return;
               slot.innerHTML = '';
               var bubble = document.createElement('div');
               bubble.style.cssText = 'max-width:90%; margin:6px 0;' +
                 'padding:12px 16px; border-radius:12px;' +
                 'font-size:0.92rem; line-height:1.45;' +
                 'background:#FFF8E1; color:#5D4037;' +
                 'border:1px solid #FFE082; align-self:flex-start;' +
                 'display:flex; align-items:flex-start; gap:10px;';
               var s = document.createElement('div');
               s.style.cssText = 'width:14px; height:14px; flex-shrink:0;' +
                 'margin-top:4px;' +
                 'border:2px solid #FFE082; border-top-color:#FF6F00;' +
                 'border-radius:50%;' +
                 'animation: translatorSpin 0.8s linear infinite;';
               bubble.appendChild(s);
               var label = document.createElement('div');
               label.style.cssText = 'display:flex; flex-direction:column; gap:6px;';
               var line1 = document.createElement('div');
               line1.innerHTML = '<strong>Building your .xlsx file</strong> — about 5 to 15 seconds. A save dialog will pop up in your browser when it is ready.';
               label.appendChild(line1);
               var line2 = document.createElement('div');
               line2.style.cssText = 'font-size:0.85rem; line-height:1.4;';
               line2.innerHTML = '<strong>Important:</strong> please open the file and check the AI\\'s work before uploading it on the 1. Data Input tab. Spot-check the populations, body weights, milk yields, sub-category labels, and any unit conversions against your original data. Any IPCC default values the AI applied will be flagged amber on the 2. QA/QC tab — review those carefully too. The AI is a draft assistant, not a verified source.';
               label.appendChild(line2);
               bubble.appendChild(label);
               slot.appendChild(bubble);
               var scroller = bubble.closest('[data-translator-scroller]');
               if (scroller) scroller.scrollTop = scroller.scrollHeight;
               // Auto-clear after 45 seconds — leaves enough time for
               // the user to actually read the 'spot-check before
               // uploading' guidance, but doesn't linger forever.
               setTimeout(function() {
                 if (slot.contains(bubble)) slot.removeChild(bubble);
               }, 45000);
               return;
             }
             t = t.parentElement;
           }
         }, false);
         // Progress tick from the server-side force-template stream.
         // Updates the inline info bubble's elapsed-label with a
         // 'chars received' counter so the user has TWO live signals:
         // wall-clock seconds + actual JSON characters arriving. Means
         // 'stuck on slow inference' vs 'actively streaming' is visible.
         Shiny.addCustomMessageHandler('translatorProgressTick', function(data) {
           var slot = document.getElementById('translator_stream_target');
           if (!slot) return;
           // Find the elapsed-label inside the active info bubble.
           var labels = slot.querySelectorAll('div');
           labels.forEach(function(l) {
             if (l.dataset && l.dataset.elapsedLabel === 'true' && data && data.chars) {
               var sec = Math.floor((Date.now() - (l._translatorStart || Date.now())) / 1000);
               l.textContent = sec + 's elapsed · ' + data.chars.toLocaleString() + ' chars received';
             }
           });
         });
         // Inline info bubble inside the conversation — used during the
         // force-template path (non-streaming, can take 60-120s). The
         // bubble lives in translator_stream_target so it's visible
         // alongside the conversation regardless of page scroll, and
         // gets cleared automatically by translatorStreamEnd when the
         // work completes.
         Shiny.addCustomMessageHandler('translatorAppendInfoBubble', function(text) {
           var slot = document.getElementById('translator_stream_target');
           if (!slot) return;
           slot.innerHTML = '';
           // Outer bubble — column flex so we can stack text + progress bar.
           var bubble = document.createElement('div');
           bubble.style.cssText = 'max-width:80%; margin:6px 0;' +
             'padding:12px 16px; border-radius:12px; white-space:pre-wrap;' +
             'font-size:0.92rem; line-height:1.45;' +
             'background:#FFF8E1; color:#5D4037;' +
             'border:1px solid #FFE082; align-self:flex-start;' +
             'display:flex; flex-direction:column; gap:8px;';
           // Top row: small spinner icon + the message text.
           var topRow = document.createElement('div');
           topRow.style.cssText = 'display:flex; align-items:center; gap:10px;';
           var spinner = document.createElement('div');
           spinner.style.cssText = 'width:14px; height:14px; flex-shrink:0;' +
             'border:2px solid #FFE082; border-top-color:#FF6F00;' +
             'border-radius:50%;' +
             'animation: translatorSpin 0.8s linear infinite;';
           topRow.appendChild(spinner);
           var txt = document.createElement('span');
           txt.textContent = text || 'Translator is working…';
           topRow.appendChild(txt);
           bubble.appendChild(topRow);
           // Progress bar — fake-determinate, animates 0 -> 90% over 60s.
           // Gives a tangible 'something is happening' feel during the
           // long non-streaming force-template call. Stays at 90% until
           // the work actually completes (translatorStreamEnd clears
           // the bubble). The label below the bar shows elapsed seconds.
           var barOuter = document.createElement('div');
           barOuter.style.cssText = 'height:6px; background:#FFE082;' +
             'border-radius:3px; overflow:hidden; width:100%;';
           var barFill = document.createElement('div');
           barFill.style.cssText = 'height:100%; width:0%;' +
             'background:#FF6F00; transition:width 0.5s linear;';
           barOuter.appendChild(barFill);
           bubble.appendChild(barOuter);
           var elapsedLabel = document.createElement('div');
           elapsedLabel.style.cssText = 'font-size:0.78rem; color:#8D6E63;';
           elapsedLabel.textContent = '0s elapsed';
           elapsedLabel.dataset.elapsedLabel = 'true';
           elapsedLabel._translatorStart = Date.now();
           bubble.appendChild(elapsedLabel);
           slot.appendChild(bubble);
           // Drive the progress bar from a JS timer.
           var startTime = Date.now();
           var targetSec = 60;
           var iv = setInterval(function() {
             var sec = Math.floor((Date.now() - startTime) / 1000);
             var pct = Math.min(90, (sec / targetSec) * 90);
             barFill.style.width = pct + '%';
             elapsedLabel.textContent = sec + 's elapsed' +
               (sec >= targetSec ? ' — still working, large inventories take longer' : '');
           }, 500);
           bubble._translatorProgressInterval = iv;
           var scroller = bubble.closest('[data-translator-scroller]');
           if (scroller) scroller.scrollTop = scroller.scrollHeight;
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
               // The 'AI is typing…' indicator is now painted inline by
               // the server-side observer via translatorAppendTypingBubble.
               _translatorOptimisticUserBubble(txt);
               _translatorClearInputDOM();
               return;
             }
             if (t.id === 'translator_submit') {
               _translatorShowSpinner('Sending sign-in link…');
               return;
             }
             t = t.parentElement;
           }
         }, false);

         // 2026-06-09: progress banner for the Word-summary downloads.
         // The docx build runs synchronously inside downloadHandler and can
         // take 30-120 seconds; without a visible cue the user thinks the
         // app is frozen. We catch clicks on the download buttons in the
         // capture phase (so we run BEFORE Shiny's own click handler fires
         // the download) and show a fixed-position banner with a spinner.
         // Auto-hides after 180s or on click anywhere on the banner.
         var _docxBannerTimer = null;
         function _docxShowBanner(label) {
           var el = document.getElementById('docx_download_banner');
           if (!el) {
             el = document.createElement('div');
             el.id = 'docx_download_banner';
             el.style.cssText = 'position:fixed; top:14px; left:50%;' +
               'transform:translateX(-50%); z-index:9999;' +
               'background:#FFF8E1; color:#1B4332;' +
               'border:1px solid #FFE082; border-left:4px solid #FF6F00;' +
               'border-radius:8px; padding:12px 16px;' +
               'box-shadow:0 4px 16px rgba(0,0,0,0.18);' +
               'font-size:0.92rem; line-height:1.4;' +
               'display:flex; align-items:center; gap:12px;' +
               'max-width:540px; cursor:pointer;';
             el.title = 'Click to dismiss';
             el.addEventListener('click', _docxHideBanner);
             // Spinner
             var sp = document.createElement('div');
             sp.style.cssText = 'width:18px; height:18px; flex-shrink:0;' +
               'border:3px solid #FFE082; border-top-color:#FF6F00;' +
               'border-radius:50%;' +
               'animation: translatorSpin 0.8s linear infinite;';
             el.appendChild(sp);
             var txt = document.createElement('div');
             txt.id = 'docx_download_banner_text';
             el.appendChild(txt);
             document.body.appendChild(el);
           }
           var txtEl = document.getElementById('docx_download_banner_text');
           if (txtEl) txtEl.innerHTML =
             '<strong>' + (label || 'Generating Word summary') + '</strong><br>' +
             'This usually takes 10 to 30 seconds. The file saves automatically ' +
             'when it is ready and this message closes on its own. ' +
             '(Click this banner to dismiss.)';
           el.style.display = 'flex';
           if (_docxBannerTimer) clearTimeout(_docxBannerTimer);
           _docxBannerTimer = setTimeout(_docxHideBanner, 180000);
         }
         function _docxHideBanner() {
           var el = document.getElementById('docx_download_banner');
           if (el) el.style.display = 'none';
           if (_docxBannerTimer) { clearTimeout(_docxBannerTimer);
                                    _docxBannerTimer = null; }
         }
         // 2026-06: native downloads give no 'finished' signal, so the banner
         // used to linger until its 180s timeout. Fetch the file via JS instead
         // — the promise resolves exactly when the build + transfer completes —
         // then save it as a blob, hide the banner and show a 'saved' toast. If
         // anything fails we fall back to the native navigation so the download
         // still happens.
         function _docxDoneToast() {
           _docxHideBanner();
           var t = document.createElement('div');
           t.innerHTML = '&#10003; Word report saved &mdash; check your browser ' +
             'download bar or your Downloads folder.';
           t.style.cssText = 'position:fixed; top:14px; left:50%;' +
             'transform:translateX(-50%); z-index:9999;' +
             'background:#D8F3DC; color:#1B4332;' +
             'border:1px solid #95D5B2; border-left:4px solid #2D6A4F;' +
             'border-radius:8px; padding:12px 16px;' +
             'box-shadow:0 4px 16px rgba(0,0,0,0.18);' +
             'font-size:0.92rem; max-width:540px; cursor:pointer;';
           t.title = 'Click to dismiss';
           t.addEventListener('click', function(){ if (t.parentNode) t.parentNode.removeChild(t); });
           document.body.appendChild(t);
           setTimeout(function(){ if (t.parentNode) t.parentNode.removeChild(t); }, 8000);
         }
         function _docxFetchDownload(href, label, fallbackName) {
           _docxShowBanner(label);
           fetch(href, { credentials: 'same-origin' }).then(function(resp) {
             if (!resp.ok) throw new Error('HTTP ' + resp.status);
             var cd = resp.headers.get('Content-Disposition') || '';
             var fname = '';
             var marker = 'filename=';
             var i = cd.indexOf(marker);
             if (i >= 0) {
               fname = cd.substring(i + marker.length).split(';')[0].trim();
               while (fname.length > 1 && (fname.charCodeAt(0) === 34 || fname.charCodeAt(0) === 39))
                 fname = fname.substring(1);
               while (fname.length > 1 && (fname.charCodeAt(fname.length - 1) === 34 ||
                       fname.charCodeAt(fname.length - 1) === 39))
                 fname = fname.substring(0, fname.length - 1);
             }
             if (!fname) fname = fallbackName;
             return resp.blob().then(function(b) { return { b: b, f: fname }; });
           }).then(function(o) {
             var u = URL.createObjectURL(o.b);
             var a = document.createElement('a');
             a.href = u; a.download = o.f;
             document.body.appendChild(a); a.click(); document.body.removeChild(a);
             setTimeout(function(){ URL.revokeObjectURL(u); }, 5000);
             _docxDoneToast();
           }).catch(function(err) {
             _docxHideBanner();
             window.location.assign(href);
           });
         }
         document.addEventListener('click', function(ev) {
           var t = ev.target;
           while (t && t !== document.body) {
             if (t.id === 'download_docx' || t.id === 'download_trend_docx') {
               var isTrend = (t.id === 'download_trend_docx');
               var label = isTrend ? 'Generating trend Word report' : 'Generating Word summary';
               var fallbackName = isTrend ? 'trend_report.docx' : 'uncertainty_summary.docx';
               var href = (t.tagName === 'A') ? t.getAttribute('href') : null;
               if (href && href !== '#' && href.length > 1) {
                 ev.preventDefault();
                 _docxFetchDownload(href, label, fallbackName);
               } else {
                 _docxShowBanner(label);
               }
               return;
             }
             t = t.parentElement;
           }
         }, true);

         // 2026-06-09: language toggle. Injected as a fixed-position
         // element in the top-right corner so it is bulletproof against
         // bslib's navbar event handling. Click sets the `app_lang`
         // cookie (100-year max-age) and reloads the page; on reload,
         // app_ui(request) reads the cookie and serves t('...') in the
         // requested language.
         function _readLangCookie() {
           var m = document.cookie.match(/(?:^|;)\\s*app_lang=([^;]+)/);
           return m ? decodeURIComponent(m[1]) : 'en';
         }
         // Read the currently-active navbar tab so we can restore it after
         // reload. We use the INDEX position (0..N-1) rather than the tab
         // title — titles are language-dependent, so a stored title from
         // one language won't match the tab name after switching language.
         // Indexing is stable because nav_panels are declared in the same
         // order regardless of language.
         function _activeTabIndex() {
           var links = document.querySelectorAll(
             '#nav > .navbar > .container-fluid .nav-link, ' +
             '#nav .nav-link');
           // De-duplicate (the selectors above can match the same elements);
           // bslib renders one .nav-link per panel.
           var seen = [];
           for (var i = 0; i < links.length; i++) {
             if (seen.indexOf(links[i]) === -1) seen.push(links[i]);
           }
           for (var j = 0; j < seen.length; j++) {
             if (seen[j].classList.contains('active')) return j;
           }
           return null;
         }
         // Translucent overlay shown the instant the user clicks EN/FR so
         // the change feels immediate. Removed automatically on the next
         // page load.
         function _showLangSwitchOverlay(target) {
           if (document.getElementById('lang-switch-overlay')) return;
           var o = document.createElement('div');
           o.id = 'lang-switch-overlay';
           o.style.cssText =
             'position:fixed; inset:0; z-index:99999;' +
             'background:rgba(255,255,255,0.78);' +
             'display:flex; align-items:center; justify-content:center;' +
             'flex-direction:column; gap:10px;' +
             'font-family:DM Sans, Arial, sans-serif;' +
             'opacity:0; transition:opacity 0.12s ease-out;';
           var spinner = document.createElement('div');
           spinner.style.cssText =
             'width:36px; height:36px; border-radius:50%;' +
             'border:4px solid #D8F3DC; border-top-color:#2D6A4F;' +
             'animation:langSpin 0.7s linear infinite;';
           var label = document.createElement('div');
           label.style.cssText =
             'font-weight:600; color:#1B4332; font-size:0.95rem;';
           label.textContent = target === 'fr'
             ? 'Passage en français…' : 'Switching to English…';
           o.appendChild(spinner);
           o.appendChild(label);
           if (!document.getElementById('lang-switch-keyframes')) {
             var s = document.createElement('style');
             s.id = 'lang-switch-keyframes';
             s.textContent =
               '@keyframes langSpin { from { transform:rotate(0deg); } ' +
               'to { transform:rotate(360deg); } }';
             document.head.appendChild(s);
           }
           document.body.appendChild(o);
           // Force a frame before fade so the transition runs.
           requestAnimationFrame(function(){ o.style.opacity = '1'; });
         }
         // 2026-06: preserve loaded data + results across the language switch.
         // The toggle reloads the page (a fresh Shiny session), so we ask the
         // server to stash the session state in a process cache keyed by a
         // per-browser token, then reload; the new session restores it.
         function _genToken() {
           if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
           return 'tok-' + Math.random().toString(36).slice(2) +
                  Date.now().toString(36);
         }
         function _ensureStateToken() {
           var m = document.cookie.match(/(?:^|;)\\s*app_state_token=([^;]+)/);
           if (m) return decodeURIComponent(m[1]);
           var tok = _genToken();
           document.cookie = 'app_state_token=' + tok +
             '; max-age=' + (7 * 24 * 60 * 60) + '; path=/; SameSite=Lax';
           return tok;
         }
         var _langReloadTimer = null;
         function _doLangReload() {
           if (_langReloadTimer) { clearTimeout(_langReloadTimer); _langReloadTimer = null; }
           window.location.reload();
         }
         function _registerLangReload() {
           if (window.Shiny && Shiny.addCustomMessageHandler)
             Shiny.addCustomMessageHandler('lang_do_reload', function(m){ _doLangReload(); });
         }
         if (window.Shiny && Shiny.addCustomMessageHandler) _registerLangReload();
         else document.addEventListener('shiny:connected', _registerLangReload);

         function _setLang(lang) {
           if (_readLangCookie() === lang) return;
           var maxAge = 100 * 365 * 24 * 60 * 60;  // ~100 years
           document.cookie = 'app_lang=' + lang +
             '; max-age=' + maxAge +
             '; path=/; SameSite=Lax';
           // Persist the active tab INDEX (0..N-1) — language-independent.
           var idx = _activeTabIndex();
           var hash = (idx !== null && idx !== undefined)
             ? '#tabidx=' + idx : '';
           _showLangSwitchOverlay(lang);
           try {
             history.replaceState(null, '', window.location.pathname +
               window.location.search + hash);
           } catch (e) { window.location.hash = hash; }
           // Ask the server to stash data + results, then reload via the
           // lang_do_reload message. Fall back to an immediate reload if Shiny
           // is unavailable or slow, so the switch can never hang.
           if (window.Shiny && Shiny.setInputValue) {
             _langReloadTimer = setTimeout(_doLangReload, 2500);
             Shiny.setInputValue('lang_save_request',
               { token: _ensureStateToken(), lang: lang, nonce: Date.now() },
               { priority: 'event' });
           } else {
             _doLangReload();
           }
         }
         // Restore the previously-active tab when the page comes back up.
         // Resolves the index against the freshly-rendered nav-links and
         // clicks the matching anchor (drives bslib's tab-show behaviour
         // natively, including Shiny's input binding).
         function _restoreActiveTab() {
           var m = (window.location.hash || '').match(/tabidx=(\\d+)/);
           if (!m) return;
           var want = parseInt(m[1], 10);
           if (isNaN(want)) return;
           function tryClick() {
             var links = document.querySelectorAll(
               '#nav > .navbar > .container-fluid .nav-link, ' +
               '#nav .nav-link');
             var seen = [];
             for (var i = 0; i < links.length; i++) {
               if (seen.indexOf(links[i]) === -1) seen.push(links[i]);
             }
             if (want < 0 || want >= seen.length || !seen[want]) return false;
             // If it's already the active tab, nothing to do.
             if (seen[want].classList.contains('active')) return true;
             seen[want].click();
             return true;
           }
           // bslib may finish wiring the navbar a tick or two after
           // shiny:connected fires; retry briefly until the click sticks
           // or we time out.
           var tries = 0;
           function attempt() {
             if (tryClick()) {
               // Clear the hash so a manual reload doesn't redundantly fire.
               try {
                 history.replaceState(null, '', window.location.pathname +
                   window.location.search);
               } catch (e) {}
               return;
             }
             if (++tries < 20) setTimeout(attempt, 50);
           }
           attempt();
         }
         function _installLangToggle() {
           if (document.getElementById('lang-toggle-floating')) return;
           var current = _readLangCookie();
           var wrap = document.createElement('div');
           wrap.id = 'lang-toggle-floating';
           wrap.style.cssText =
             'position:fixed; top:10px; right:14px; z-index:9999;' +
             'display:flex; align-items:center; gap:2px;' +
             'padding:3px; background:#FFFFFF; border:1px solid #2D6A4F;' +
             'border-radius:18px; box-shadow:0 2px 6px rgba(0,0,0,0.12);' +
             'font-family:DM Sans, Arial, sans-serif;';
           function makeBtn(lang, label) {
             var b = document.createElement('button');
             b.type = 'button';
             b.textContent = label;
             b.style.cssText =
               'border:0; cursor:pointer; padding:4px 12px;' +
               'border-radius:14px; font-weight:700; font-size:0.85rem;' +
               'transition:background 0.12s, color 0.12s;' +
               (current === lang
                 ? 'background:#2D6A4F; color:#FFFFFF;'
                 : 'background:transparent; color:#475569;');
             b.onclick = function() { _setLang(lang); };
             return b;
           }
           wrap.appendChild(makeBtn('en', 'EN'));
           wrap.appendChild(makeBtn('fr', 'FR'));
           document.body.appendChild(wrap);
         }
         if (document.readyState === 'loading') {
           document.addEventListener('DOMContentLoaded', _installLangToggle);
         } else {
           _installLangToggle();
         }
         // Restore tab after Shiny is connected. Shiny:connected fires once
         // per session, so this runs exactly when the server-side inputs
         // are ready to receive setInputValue.
         $(document).on('shiny:connected', function() {
           setTimeout(_restoreActiveTab, 50);
           // Feedback widget: hand the browser's user-agent to the server so
           // it can be recorded in the issue context block.
           if (Shiny.setInputValue) {
             Shiny.setInputValue('fb_user_agent', navigator.userAgent);
           }
         });"
      ))),
      # Floating "Feedback" button — fixed bottom-right, visible on every tab
      # AND on the pre-login screen (it lives in the navbar header, outside
      # every nav_panel). Opens the feedback modal (see R/app_server.R).
      actionButton(
        inputId = "fb_open",
        label   = tagList(icon("comment-dots"),
                          tags$span(class = "fb-label", t("fb_button"))),
        class   = "fb-fab"
      )
    ),
    fillable = FALSE,

    # ==================== HOME TAB ====================
    bslib::nav_panel(
      title = t("tab_home"),
      icon = icon("home"),
      div(
        style = "max-width: 960px; margin: 0 auto; padding: 24px;",

        # Hero section
        div(
          style = "background: linear-gradient(135deg, #1B4332 0%, #2D6A4F 50%, #40916C 100%);
                   color: white; border-radius: 16px; padding: 48px 40px; margin-bottom: 0;
                   position: relative; overflow: hidden;",
          h1(t("hero_title"),
             style = "font-size: 2rem; font-weight: 700; margin-bottom: 12px;"),
          p(t("hero_subtitle"),
            style = "font-size: 1.1rem; opacity: 0.9; margin-bottom: 8px;"),
          p(t("hero_credit"),
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
          tags$img(src = "climate_action_logo.png",
                   alt = "CGIAR Climate Action Programme",
                   style = "height:96px; max-width:320px; object-fit:contain;",
                   onerror = "this.style.display='none'; this.nextSibling.style.display='inline-block';"),
          tags$span("CGIAR Climate Action Programme",
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
          bslib::card_header(h4(t("card_what_does_title"), style = "margin: 0;")),
          bslib::card_body(
            p(t("what_does_intro")),
            tags$ol(
              tags$li(t("what_does_li1")),
              tags$li(t("what_does_li2")),
              tags$li(t("what_does_li3")),
              tags$li(t("what_does_li4")),
              tags$li(t("what_does_li5"))
            ),
            p(tags$strong(t("what_does_sources_label")),
              t("what_does_sources_body"))
          )
        ),

        # Workflow overview
        bslib::card(
          bslib::card_header(h4(t("workflow_title"), style = "margin: 0;")),
          bslib::card_body(
            p(t("workflow_intro")),
            tags$table(
              style = "width: 100%; border-collapse: collapse; margin-top: 8px;",
              tags$thead(
                tags$tr(style = "background: #D8F3DC; text-align: left;",
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", t("workflow_th_step")),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", t("workflow_th_tab")),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", t("workflow_th_what")),
                  tags$th(style = "padding: 10px; border: 1px solid #E0DDD5;", t("workflow_th_time"))
                )
              ),
              tags$tbody(
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "1"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row1_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row1_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "2"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row2_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row2_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "3"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row3_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row3_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "10 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "4"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row4_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row4_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row5_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row5_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5-7 min")
                ),
                tags$tr(style = "background: #FAFAF7;",
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "6"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row6_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row6_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "5 min")
                ),
                tags$tr(
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "7"),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5; font-weight: 600; color: #2D6A4F;", t("workflow_row7_tab")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", t("workflow_row7_what")),
                  tags$td(style = "padding: 8px; border: 1px solid #E0DDD5;", "2 min")
                )
              )
            ),
            br(),
            div(class = "info-panel", HTML(t("quick_start_html"))),
            br(),
            div(style = "text-align: center;",
                actionButton("goto_resources", t("btn_goto_resources"),
                             class = "btn btn-outline-success",
                             style = "font-size:0.95rem; padding: 10px 24px;"))
          )
        ),

        # T0.4: prerequisites & limitations
        bslib::card(
          bslib::card_header(h4(t("card_before_you_start_title"), style = "margin: 0;")),
          bslib::card_body(
            tags$p(tags$strong(t("before_you_will_need"))),
            tags$ul(
              tags$li(t("before_li1")),
              tags$li(HTML(t("before_li2_html"))),
              tags$li(t("before_li3"))
            ),
            tags$p(tags$strong(t("before_not_do_label"))),
            tags$ul(
              tags$li(t("not_do_li1")),
              tags$li(t("not_do_li2")),
              tags$li(t("not_do_li3"))
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
      title = t("tab_definitions"),
      icon = icon("book"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(paste0(t("info_definitions_label"), " ")),
          t("info_definitions_body"),
          tags$strong(t("info_definitions_software")),
          t("info_definitions_tail"))
      ,
      bslib::card(
        bslib::card_header(t("card_param_definitions")),
        bslib::card_body(DT::DTOutput("definitions_table"))
      )
    ),

    # ==================== USEFUL RESOURCES TAB (T0.2) ====================
    bslib::nav_panel(
      title = t("tab_resources"),
      icon = icon("book-open"),
      div(style = "max-width: 960px; margin: 0 auto; padding: 24px;",
        # FR-only inline note about English-only docs (shown only when the
        # current language is French; conditional rendering at UI-build time).
        if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                            ifnotfound = "en"), "fr"))
          div(class = "info-panel",
              style = "margin-bottom: 16px; background: #FEF3C7; border-left: 3px solid #F59E0B;",
              icon("circle-info"),
              tags$strong(" Note : "),
              t("resources_fr_only_note"))
        else NULL,
        # Tool-specific resources — methodology + user guide. Kept first so it
        # is the first thing users see in the Resources tab.
        # The id is the scroll target for the Home tab "Methodology, user
        # guide & downloads" button (see goto_resources in app_server.R).
        bslib::card(
          id = "downloads-card",
          bslib::card_header(h4(t("card_tool_resources"), style = "margin: 0;")),
          bslib::card_body(
            tags$h5(t("resources_how_it_works")),
            tags$ul(
              tags$li(t("resources_eq_chain")),
              tags$li(t("resources_mc")),
              tags$li(t("resources_sensitivity"))
            ),
            div(style = "margin-top: 16px; display: flex; gap: 12px; flex-wrap: wrap;",
              tags$a(
                href = "methodology.pdf",
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-success",
                icon("file-pdf"), " ", t("btn_open_methodology")
              ),
              tags$a(
                href = "user_guide.pdf",
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-outline-success",
                icon("book"), " ", t("btn_open_userguide")
              )
            )
          )
        ),
        # AI Translator kit — free, self-serve helper to turn the user's own
        # 2026-06: in-app AI translator. Backed by Lolita's OpenAI account
        # with a $10/month spending cap and gated by a magic-link login.
        # Replaces the earlier "Download translator kit, set up on
        # claude.ai" flow, which was confusing for first-time users and
        # ran into free-tier rate limits.
        translator_chat_ui(),

        bslib::card(
          bslib::card_header(h4(t("card_useful_resources"), style = "margin: 0;")),
          bslib::card_body(
            tags$h5(t("resources_method_foundations")),
            tags$p(style = "font-size: 0.9em; color: #555; margin-bottom: 8px;",
                   t("resources_method_intro")),
            tags$ul(
              tags$li(tags$strong(t("resources_vol4_livestock_label")),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_10_Ch10_Livestock.pdf",
                                       target = "_blank",
                                       t("resources_vol4_livestock_2006"))),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch10_Livestock.pdf",
                                       target = "_blank",
                                       t("resources_vol4_livestock_2019")))
                      )
              ),
              tags$li(tags$strong(t("resources_vol4_soils_label")),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_11_Ch11_N2O&CO2.pdf",
                                       target = "_blank",
                                       t("resources_vol4_soils_2006"))),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch11_Soils_N2O_CO2.pdf",
                                       target = "_blank",
                                       t("resources_vol4_soils_2019")))
                      )
              ),
              tags$li(tags$strong(t("resources_vol1_uncert_label")),
                      tags$ul(
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/1_Volume1/V1_3_Ch3_Uncertainties.pdf",
                                       target = "_blank",
                                       t("resources_vol1_uncert_2006"))),
                        tags$li(tags$a(href = "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/1_Volume1/19R_V1_Ch03_Uncertainties.pdf",
                                       target = "_blank",
                                       t("resources_vol1_uncert_2019")))
                      )
              )
            ),
            tags$h5(t("resources_ad_guidance")),
            tags$ul(
              tags$li(tags$a(href = "https://www.fao.org/livestock-systems/global-distributions/en/",
                             target = "_blank",
                             t("resources_fao_ladg"))),
              tags$li(t("resources_penman"))
            ),
            tags$h5(t("resources_dist_mc_title")),
            tags$ul(
              tags$li(t("resources_frey_rhodes")),
              tags$li(t("resources_gpg_2000"))
            ),
            tags$h5(t("resources_learning_title")),
            tags$ul(
              tags$li(tags$a(href = "https://elearning.fao.org/course/view.php?id=625",
                             target = "_blank",
                             t("resources_fao_elearn_uncert"))),
              tags$li(tags$a(href = "https://elearning.fao.org/course/view.php?id=531",
                             target = "_blank",
                             t("resources_fao_elearn_tier2"))),
              tags$li(tags$a(href = "https://unfccc.int/topics/science/workstreams/methodological-issues-under-the-convention",
                             target = "_blank",
                             t("resources_unfccc_webinar")))
            ),
            tags$h5(t("resources_case_studies")),
            tags$ul(
              tags$li(t("resources_monni")),
              tags$li(t("resources_karimi")),
              tags$li(t("resources_milne")),
              tags$li(tags$em(t("resources_more_to_come")))
            )
          )
        )
      )
    ),

    # ==================== TAB 1: DATA INPUT ====================
    bslib::nav_panel(
      title = t("tab_data_input"),
      icon = icon("upload"),
      # Andreas 2026-05 #3: analysis-mode toggle moved here from Home page.
      bslib::card(
        style = "margin: 16px;",
        bslib::card_header(h5(t("card_analysis_mode"), style = "margin: 0;")),
        bslib::card_body(
          radioButtons("analysis_mode",
            label = NULL,
            choiceNames = list(
              tagList(
                paste0(t("analysis_mode_single"), " "),
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  t("tip_analysis_mode_single"),
                  placement = "right"
                )
              ),
              tagList(
                paste0(t("analysis_mode_trend"), " "),
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  t("tip_analysis_mode_trend"),
                  placement = "right"
                )
              )
            ),
            choiceValues = c("single", "trend"),
            selected = character(0)),
          div(id = "analysis_mode_warning",
              style = "background:#FEF3C7; border-left:3px solid #F59E0B; padding:8px 10px; margin-top:8px; font-size:0.85rem; color:#92400E; border-radius:4px;",
              icon("exclamation-triangle"),
              tags$strong(paste0(" ", t("what_to_do_label"), " ")),
              t("analysis_mode_warning")),
          tags$p(tags$em(
            t("trend_explanation"),
            tags$br(), tags$br(),
            t("trend_ipcc_alignment"), " ",
            tags$strong(t("trend_base_year")),
            if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                                ifnotfound = "en"), "fr"))
              " et une " else " and a ",
            tags$strong(t("trend_current_year")),
            t("trend_explanation_2")),
            style = "color:#555; font-size:0.85rem; margin-top:8px;")
        )
      ),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(paste0(t("what_to_do_label"), " ")),
          t("info_data_input")),
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 320,
          h5(t("data_source_h")),
          selectInput("country", t("country_label"),
                      choices = setNames(
                        c("country_x", "country_y", "custom"),
                        c(t("country_x_label"),
                          t("country_y_label"),
                          t("country_custom_label")))),
          # B1: explicit hint when "Custom Upload" selected so the user knows the
          # dropdown registered (the example tables don't auto-load for "custom")
          conditionalPanel(
            condition = "input.country == 'custom'",
            div(style = "background:#FEF3C7; border-left:3px solid #F59E0B; padding:8px 10px; margin-top:8px; font-size:0.85rem; color:#92400E; border-radius:4px;",
                icon("info-circle"),
                t("custom_hint"))
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
            h5(t("data_h_pick_ipcc")),
            radioButtons("template_version", label = NULL,
                          choices = setNames(c("2006", "2019_refinement"),
                                              c(t("ipcc_2006"), t("ipcc_2019"))),
                          selected = character(0), inline = TRUE),
            div(style = "font-size:0.78rem; color:#666; margin-top:-6px; margin-bottom:8px;",
                tags$em(t("ipcc_version_note"))),
            h5(t("data_h_download_template")),
            # Active controls — visible only when an IPCC version is picked.
            conditionalPanel(
              condition = "input.template_version === '2006' || input.template_version === '2019_refinement'",
              downloadButton("download_template", "Download Blank Template",
                             class = "btn-outline-success btn-sm"),
              downloadButton("download_template_example", "Download Template with Example",
                             class = "btn-outline-primary btn-sm mt-2")
            ),
            # Greyed-out placeholder shown when no version is picked yet —
            # explains the gating instead of just hiding the buttons.
            conditionalPanel(
              condition = "input.template_version !== '2006' && input.template_version !== '2019_refinement'",
              div(style = "opacity:0.45; pointer-events:none;",
                tags$button(class = "btn btn-outline-success btn-sm",
                            type = "button", disabled = NA,
                            icon("download"), " Download Blank Template"),
                tags$button(class = "btn btn-outline-primary btn-sm mt-2",
                            type = "button", disabled = NA,
                            icon("download"), " Download Template with Example")),
              div(style = "font-size:0.82rem; color:#92400E; margin-top:6px;",
                  icon("circle-info"),
                  tags$em(t("ipcc_pick_first_unlock")))
            ),
            div(style = "margin-top: 10px; padding: 8px 10px; background:#E8F5E9; border-left:3px solid #2D6A4F; border-radius:4px; font-size:0.82rem;",
              icon("robot"),
              tags$strong(t("ai_inline_promo_title")),
              tags$br(),
              t("ai_inline_promo_body_pre"),
              tags$a(href = "#",
                     onclick = paste0(
                       # Click the actual Resources nav-tab. Shiny.setInputValue
                       # alone only updates the input value, it does not trigger
                       # the tab switch. bslib renders nav-links and the Resources
                       # one is identified by text content. Find it and click.
                       "var tab = null; ",
                       "var anchors = document.querySelectorAll('a.nav-link, button.nav-link'); ",
                       "for (var i = 0; i < anchors.length; i++) { ",
                       "  if (anchors[i].textContent.trim() === 'Resources') { ",
                       "    tab = anchors[i]; break; ",
                       "  } ",
                       "} ",
                       "if (tab) tab.click(); ",
                       "setTimeout(function() { ",
                       "  var el = document.getElementById('ai-translator-card'); ",
                       "  if (el) el.scrollIntoView({behavior:'smooth', block:'start'}); ",
                       "}, 300); ",
                       "return false;"),
                     t("ai_inline_promo_body_link")),
              t("ai_inline_promo_body_post")),
            hr(),
            h5(t("data_h_upload")),
            # Active upload — only after an IPCC version is picked.
            conditionalPanel(
              condition = "input.template_version === '2006' || input.template_version === '2019_refinement'",
              fileInput("data_upload", "Upload Excel Template (.xlsx)",
                        accept = ".xlsx")
            ),
            # Greyed-out upload placeholder when no version is picked.
            conditionalPanel(
              condition = "input.template_version !== '2006' && input.template_version !== '2019_refinement'",
              div(style = "opacity:0.45; pointer-events:none;",
                tags$label(class = "control-label", "Upload Excel Template (.xlsx)"),
                div(class = "input-group",
                    tags$label(class = "input-group-btn input-group-prepend",
                               tags$span(class = "btn btn-default btn-file",
                                          "Browse...", disabled = NA)),
                    tags$input(type = "text", class = "form-control",
                               placeholder = "No file selected", readonly = "readonly"))),
              div(style = "font-size:0.82rem; color:#92400E; margin-top:4px;",
                  icon("circle-info"),
                  tags$em(t("pick_ipcc_to_enable")))
            )
          ),
          hr(),
          h5(t("validation_h")),
          uiOutput("validation_status")
        ),
        conditionalPanel(
          condition = "output.has_imputed_params == true",
          uiOutput("imputed_params_notice_tab1")
        ),
        bslib::card(
          bslib::card_header(t("param_data_h")),
          bslib::card_body(DT::DTOutput("param_table"))
        )
      )
    ),

    # ==================== TAB 2: QA/QC ====================
    bslib::nav_panel(
      title = t("tab_qaqc"),
      icon = icon("check-square"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(paste0(t("what_to_do_label"), " ")),
          t("info_qaqc"),
          tags$br(), tags$br(),
          div(style = "display:flex; flex-direction:column; gap:7px; margin-bottom:10px;",
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#92400E; background:#FEF3C7; border:1px solid #F59E0B; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", t("qa_status_missing")),
              t("qa_missing_desc")
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#991B1B; background:#FEE2E2; border:1px solid #EF4444; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", t("qa_status_fail")),
              t("qa_fail_desc")
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#92400E; background:#FEF3C7; border:1px solid #F59E0B; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", t("qa_status_warn")),
              t("qa_warn_desc")
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#1E40AF; background:#DBEAFE; border:1px solid #3B82F6; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", t("qa_status_info")),
              t("qa_info_desc")
            ),
            div(
              tags$span(style = "display:inline-block; min-width:74px; font-weight:600; color:#166534; background:#DCFCE7; border:1px solid #22C55E; border-radius:4px; padding:1px 8px; margin-right:8px; text-align:center;", t("qa_status_pass")),
              t("qa_pass_desc")
            )
          ),
          t("qa_fix_fails"), tags$strong(t("qa_status_fail")), t("qa_before_sim"),
          tags$strong(t("qa_status_warn")), t("qa_warnings_advisory"),
          tags$br(), tags$br(),
          tags$strong(paste0(t("qa_autofilled_label"), " ")),
          t("qa_autofilled_intro"),
          tags$strong(t("qa_autofilled_panel_label")),
          t("qa_autofilled_outro")),
      conditionalPanel(
        condition = "output.has_imputed_params == true",
        div(style = "margin: 0 16px 16px 16px;",
            bslib::card(
              style = "border-left: 4px solid #F59E0B;",
              bslib::card_header(
                style = "background-color:#FEF3C7; color:#92400E; font-weight:600;",
                icon("triangle-exclamation"), " ", t("qa_autofilled_panel_label")
              ),
              bslib::card_body(uiOutput("imputed_params_card"))
            ))
      ),
      bslib::layout_columns(
        col_widths = c(3, 9),
        bslib::card(
          bslib::card_header(t("qa_summary_h")),
          bslib::card_body(
            uiOutput("qaqc_summary_ui"),
            hr(),
            p(style = "font-size:0.83rem; color:#555;",
              t("qa_checks_run"))
          )
        ),
        bslib::card(
          bslib::card_header(t("qa_results_h")),
          bslib::card_body(DT::DTOutput("qaqc_table"))
        )
      )
    ),

    # ==================== TAB 3: UNCERTAINTY ====================
    bslib::nav_panel(
      title = t("tab_uncertainty"),
      icon = icon("sliders-h"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$p(
            tags$strong(paste0(t("what_to_do_label"), " ")),
            t("info_unc_what")
          ),
          tags$p(
            tags$strong(paste0(t("info_unc_triangular_label"), " ")),
            tags$em(t("info_unc_triangular_body"))
          ),
          tags$p(
            tags$strong(t("info_unc_quickset_label")),
            t("info_unc_quickset_body")
          )),
      bslib::card(
        bslib::card_header(t("unc_table_h")),
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
                 tags$em(t("quickset_undo_note")))
        )
      )
    ),

    # ==================== TAB 4: CORRELATIONS ====================
    bslib::nav_panel(
      title = t("tab_correlations"),
      icon = icon("th"),
      # 2026-05 UX overhaul: two-block intro (replaces the previous wall of text).
      # Block 1: plain-language "what is this page about?". Block 2: a small
      # decision tree so a first-time user can pick the right option without
      # reading the bullets.
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(t("info_corr_about_label")), tags$br(),
          t("info_corr_about_body"),
          tags$br(), tags$br(),
          tags$strong(t("info_corr_quickguide")),
          tags$ul(style = "margin-top:6px; margin-bottom:0;",
            tags$li(t("info_corr_q1"),
                    tags$strong(t("info_corr_q1_ans")), "."),
            tags$li(t("info_corr_q2"),
                    tags$strong(t("info_corr_q2_ans")), "."),
            tags$li(t("info_corr_q3"),
                    tags$strong(t("info_corr_q3_ans")), "."),
            tags$li(t("info_corr_q4"), tags$strong(t("info_corr_no")),
                    t("info_corr_q4_post"))
          )),
      bslib::layout_columns(
        col_widths = c(6, 6),

        # --- Activity data correlations ---
        bslib::card(
          bslib::card_header(
            tags$div(
              style = "display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;",
              tags$span(t("card_ad_corr_h")),
              tags$a(
                href = "docs/correlations.html", target = "_blank",
                icon("circle-info"),
                tags$span(t("ai_find_out_more_long"), style = "margin-left:4px;"),
                style = paste("color:#2D6A4F; font-size:0.82rem; font-weight:500;",
                              "text-decoration:none; padding:4px 10px;",
                              "border:1px solid #2D6A4F; border-radius:14px;",
                              "background:#FFFFFF;")
              )
            )
          ),
          bslib::card_body(
            div(class = "info-panel",
                t("info_ad_corr"), tags$strong("Parameter_TimeSeries"),
                t("info_ad_corr_post")),
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
                  tags$strong(paste0(t("info_struct_defaults_label"), " ")),
                  t("info_struct_defaults_body"), " ",
                  tags$em(t("info_struct_defaults_note")),
                  t("info_struct_defaults_tail"))
            ),
            conditionalPanel(
              condition = "input.corr_mode == 'manual'",
              div(class = "info-panel",
                  tags$strong(paste0(t("info_manual_label"), " ")),
                  t("info_manual_body"), " ",
                  tags$strong(paste0(t("info_manual_zero_label"), " ")),
                  t("info_manual_zero_body")),
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
          bslib::card_header(t("card_ef_corr_h")),
          bslib::card_body(
            div(class = "info-panel",
                t("info_ef_corr")),
            radioButtons("ef_corr_mode",
                         label = tagList(
                           paste0(t("corr_mode_label"), " "),
                           bslib::tooltip(
                             span(icon("circle-question"),
                                  style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                             t("tip_ef_corr_mode"),
                             placement = "right"
                           )
                         ),
                         choices = setNames(c("none", "block"),
                                              c(t("corr_ef_mode_none"),
                                                t("corr_ef_mode_block")))),
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
      title = t("tab_simulate"),
      icon = icon("play"),
      value = "5. Simulate & Results",
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(paste0(t("what_to_do_label"), " ")),
          t("info_simulate"),
          tags$br(), tags$br(),
          tags$strong(t("info_simulate_results_switch")),
          " ", tags$em(t("info_simulate_back")),
          t("info_simulate_back_body"),
          tags$br(), tags$br(),
          tags$strong(paste0(t("info_simulate_n_label"), " ")),
          t("info_simulate_n_body")),
      # R1.5: view toggle — output.sim_view is "settings" or "results"
      conditionalPanel(
        condition = "output.sim_view != 'results'",
        bslib::layout_columns(
        col_widths = c(4, 8),
        bslib::card(
          bslib::card_header(t("card_sim_settings")),
          bslib::card_body(
            sliderInput("n_iter", t("sim_n_iter_label"),
              min = 1000, max = 50000, step = 1000,
              value = 10000, sep = ","),
            numericInput("seed",
              label = tagList(
                paste0(t("sim_seed_label"), " "),
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  t("tip_sim_seed"),
                  placement = "right"
                )
              ),
              value = 42),
            # Andreas 2026-05 follow-up: Dirichlet MMS-allocation control removed
            # (no IPCC citation). MMS% is now treated deterministically across
            # iterations, matching the IPCC Inventory Software's behaviour.
            selectInput("gwp_version",
              label = tagList(
                paste0(t("sim_gwp_label"), " "),
                bslib::tooltip(
                  span(icon("circle-question"),
                       style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
                  t("tip_sim_gwp"),
                  placement = "right"
                )
              ),
              choices = c("AR4 (CH₄=25)" = "AR4",
                          "AR5 (CH₄=28, N₂O=265)" = "AR5",
                          "AR6 (CH₄=27, N₂O=273)" = "AR6"),
              selected = "AR5"),
            checkboxGroupInput("emission_sources", t("sim_sources_label"),
                               choices = setNames(
                                 c("enteric_ch4", "manure_ch4",
                                   "manure_n2o_direct", "manure_n2o_indirect",
                                   "pasture_n2o_direct", "pasture_n2o_indirect"),
                                 c(t("src_enteric_ch4"), t("src_manure_ch4"),
                                   t("src_manure_n2o_d"), t("src_manure_n2o_i"),
                                   t("src_pasture_n2o_d"), t("src_pasture_n2o_i"))),
                               selected = character(0)),
            uiOutput("select_all_btn"),
            div(style = "font-size:0.78rem; color:#92400E; background:#FEF3C7; padding:8px 10px; border-radius:6px; margin-bottom:8px; margin-top:4px;",
                icon("exclamation-triangle"),
                tags$strong(paste0(" ", t("sim_must_tick_one"))),
                t("sim_must_tick_body")),
            hr(),
            # Round 9: single-year-only options (decomposition + comparison).
            # Trend mode doesn't use these — the trend's IPCC-§3.7 framework
            # already separates AD vs coefficient via the year_corr radio.
            conditionalPanel(
              condition = "input.analysis_mode != 'trend'",
              checkboxInput("run_decomposition", t("sim_run_decomp"),
                            value = TRUE),
              # Set expectations: the AD/EF split runs two extra full
              # simulations on top of the main one. On a large inventory this
              # roughly triples the run time. Users who only need the headline
              # result + sensitivity can untick it for a much faster run.
              tags$small(
                style = "display:block; margin:-6px 0 8px 24px; color:#6B6B6B;",
                t("sim_run_decomp_hint")),
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
              actionButton("run_sim", t("btn_run_sim"),
                           class = "run-btn w-100", icon = icon("play"))
            ),
            conditionalPanel(
              condition = "input.analysis_mode == 'trend'",
              actionButton("run_trend", t("btn_run_trend"),
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
            actionButton("show_settings_btn",
                         HTML(paste0("&#8592; ", t("res_back_to_settings"))),
                         class = "btn-outline-secondary",
                         icon = icon("arrow-left"))),
        h3(t("res_sim_results_h"), style = "margin: 8px 16px;"),

        conditionalPanel(
          condition = "input.analysis_mode != 'trend'",
          bslib::layout_columns(
            col_widths = NULL,
            bslib::value_box(title = t("res_vb_enteric_ch4_t"),
                              value = textOutput("vb_enteric_ch4"),
                              showcase = icon("fire"), theme = "success"),
            bslib::value_box(title = t("res_vb_manure_ch4_t"),
                              value = textOutput("vb_manure_ch4"),
                              showcase = icon("recycle"), theme = "success"),
            bslib::value_box(title = t("res_vb_manure_n2o_t"),
                              value = textOutput("vb_manure_n2o"),
                              p(t("res_vb_direct_indirect")),
                              showcase = icon("cloud"), theme = "primary"),
            bslib::value_box(title = t("res_vb_pasture_n2o_t"),
                              value = textOutput("vb_pasture_n2o"),
                              p(t("res_vb_direct_indirect")),
                              showcase = icon("seedling"), theme = "primary"),
            bslib::value_box(title = t("res_vb_total_moe_pct"),
                              value = textOutput("vb_moe_total"),
                              p(t("res_vb_total_moe_sub")),
                              showcase = icon("percent"), theme = "warning")
          ),
          div(style = "padding: 0 12px 8px; color: #555; font-size: 0.85rem;",
              tags$em(paste0(t("res_inline_total_co2e"), " ")),
              textOutput("vb_co2e_inline", inline = TRUE),
              tags$em(paste0(" · ", t("res_inline_moe"), " ")),
              textOutput("vb_moe", inline = TRUE),
              tags$em(paste0(" · ", t("res_inline_total_ch4"), " ")),
              textOutput("vb_ch4", inline = TRUE),
              tags$em(paste0(" · ", t("res_inline_total_n2o"), " ")),
              textOutput("vb_n2o", inline = TRUE)),
          # Andreas 28/5/26 #7.1: headline split by cattle_type so dairy and
          # non-dairy contributions are visible without having to drill into
          # the aggregation-level selector below. Only rendered when the
          # inventory has more than one cattle_type.
          conditionalPanel(
            condition = "output.has_multi_cattle_type == true",
            bslib::card(
              bslib::card_header(t("res_headline_by_cattle_h")),
              bslib::card_body(
                p(tags$em(style = "color:#555; font-size:0.85rem;",
                          t("res_headline_by_cattle_note"))),
                DT::DTOutput("results_headline_by_cattle_type")
              )
            )
          ),
          bslib::layout_columns(
            col_widths = c(6, 6),
            bslib::card(
              bslib::card_header(t("res_emission_dist_h")),
              bslib::card_body(plotly::plotlyOutput("results_histogram"))
            ),
            bslib::card(
              bslib::card_header(t("res_decomp_h")),
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

          div(style = "padding: 0 16px 8px; display: flex; align-items: center; gap: 12px;",
              tags$strong(paste0(t("res_agg_level_label"), " ")),
              selectInput("results_aggregation_level", label = NULL,
                          choices = setNames(
                            c("cattle_type", "aggregation_level", "sub_category"),
                            c(t("res_agg_cattle_type"),
                              t("res_agg_production_system"),
                              t("res_agg_sub_category"))),
                          selected = "cattle_type",
                          width = "260px"),
              tags$em(style = "color:#666; font-size:0.85rem;",
                      t("res_agg_level_note"))),
          bslib::card(
            bslib::card_header(t("res_by_system_h")),
            bslib::card_body(DT::DTOutput("results_by_system"))
          ),
          bslib::card(
            bslib::card_header(t("res_by_category_h")),
            bslib::card_body(
              p(t("res_by_category_note")),
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
            bslib::value_box(title = t("res_vb_trend_delta"),
                              value = textOutput("vb_trend_delta"),
                              p(textOutput("vb_trend_delta_sub", inline = TRUE)),
                              showcase = icon("arrow-trend-up"), theme = "primary"),
            bslib::value_box(title = t("res_vb_trend_slope_short"),
                              value = textOutput("vb_trend_slope"),
                              p(textOutput("vb_trend_slope_sub", inline = TRUE)),
                              showcase = icon("chart-line"), theme = "success"),
            bslib::value_box(title = t("res_vb_trend_latest_short"),
                              value = textOutput("vb_trend_latest"),
                              p(textOutput("vb_trend_latest_sub", inline = TRUE)),
                              showcase = icon("calendar-days"), theme = "info"),
            bslib::value_box(title = t("res_vb_trend_yoy_largest"),
                              value = textOutput("vb_trend_yoy"),
                              p(textOutput("vb_trend_yoy_sub", inline = TRUE)),
                              showcase = icon("bolt"), theme = "warning")
          ),
          div(style = "padding: 0 12px 8px; color: #555; font-size: 0.85rem;",
              tags$em(textOutput("vb_trend_inline", inline = TRUE))),
          bslib::layout_columns(
            col_widths = c(7, 5),
            bslib::card(
              bslib::card_header(t("card_trend_chart_h")),
              bslib::card_body(plotly::plotlyOutput("trend_plot", height = "360px"))
            ),
            bslib::card(
              bslib::card_header(t("res_trend_yoy_h")),
              bslib::card_body(plotly::plotlyOutput("trend_yoy_chart", height = "360px"))
            )
          ),
          bslib::card(
            bslib::card_header(t("res_trend_delta_hist_h")),
            bslib::card_body(
              p(tags$em(t("res_trend_delta_hist_note"))),
              plotly::plotlyOutput("trend_delta_histogram", height = "300px")
            )
          ),
          bslib::card(
            bslib::card_header(t("card_trend_table_h")),
            bslib::card_body(
              p(tags$em(t("trend_table_note"))),
              DT::DTOutput("trend_table")
            )
          ),
          div(style = "margin: 8px 16px; font-size:0.85rem; color:#555;",
              tags$em(t("res_trend_footer_note")))
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
      title = t("tab_sensitivity"),
      icon = icon("bullseye"),

      # ---------- Single-year sensitivity ----------
      conditionalPanel(
        condition = "input.analysis_mode != 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong(paste0(t("what_to_do_label"), " ")),
            t("info_sens_what"),
            tags$br(), tags$br(),
            tags$strong(paste0(t("info_sens_note_label"), " ")),
            tags$em(t("info_sens_note_body")),
            tags$em(tags$strong(t("info_sens_note_uncertainty"))),
            tags$em(t("info_sens_note_tail")),
            tags$br(),
            tags$strong(paste0(t("info_sens_action_label"), " ")),
            t("info_sens_action_body"),
            tags$br(), tags$br(),
            tags$strong(paste0(t("info_sens_methods_label"), " ")),
            tags$strong(t("info_sens_src_label")),
            t("info_sens_src_body"), " ",
            tags$strong(t("info_sens_prcc_label")),
            t("info_sens_prcc_body")),
        uiOutput("sens_view_toggle"),
        div(style = "margin: 0 16px 12px 16px; display: flex; gap: 20px; flex-wrap: wrap; align-items: flex-end;",
            selectInput("sens_source", t("sens_output_var"),
                        choices = setNames(
                          c("total_co2e", "enteric_ch4_total", "manure_ch4_total",
                            "direct_n2o_mm_total", "indirect_n2o_mm_total",
                            "direct_n2o_prp_total", "indirect_n2o_prp_total"),
                          c(t("sens_total_co2e"), t("src_enteric_ch4"),
                            t("src_manure_ch4"), t("src_manure_n2o_d"),
                            t("src_manure_n2o_i"), t("src_pasture_n2o_d"),
                            t("src_pasture_n2o_i"))),
                        selected = "total_co2e", width = "340px"),
            uiOutput("sens_group_filter_ui")
        ),
        bslib::layout_columns(
          col_widths = c(6, 6),
          bslib::card(
            bslib::card_header(t("card_tornado_h")),
            bslib::card_body(
              uiOutput("tornado_note"),
              plotly::plotlyOutput("tornado_chart"))
          ),
          bslib::card(
            bslib::card_header(t("card_sens_rankings")),
            bslib::card_body(
              selectInput("sens_method", t("sens_method"),
                          choices = setNames(c("src", "prcc"),
                                              c(t("sens_method_src"),
                                                t("sens_method_prcc")))),
              DT::DTOutput("sensitivity_table")
            )
          )
        )
      ),

      # ---------- Trend sensitivity ----------
      conditionalPanel(
        condition = "input.analysis_mode == 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong(paste0(t("what_to_do_label"), " ")),
            t("info_trend_sens_what"),
            tags$strong(t("info_trend_sens_per_year_label")),
            t("info_trend_sens_per_year_body"),
            tags$strong(t("info_trend_sens_delta_label")),
            t("info_trend_sens_delta_body"),
            tags$strong(t("info_trend_sens_user_red")),
            t("info_trend_sens_legend"),
            tags$span(style = "color:#2D6A4F;font-weight:bold;", "■ ",
                      if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                                          ifnotfound = "en"), "fr"))
                        "vert" else "green"),
            t("info_trend_sens_green_note"),
            tags$span(style = "color:#78909C;font-weight:bold;", "■ ",
                      if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                                          ifnotfound = "en"), "fr"))
                        "gris" else "grey"),
            t("info_trend_sens_grey_note"),
            tags$br(), tags$br(),
            tags$strong(paste0(t("info_sens_action_label"), " ")),
            t("info_trend_sens_action")),
        h4(t("trend_sens_per_year_h"),
            style = "color:#1B4332; margin: 8px 16px 4px;"),
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            bslib::card_header(t("tornado_top10")),
            bslib::card_body(plotly::plotlyOutput("trend_tornado_per_year_sens",
                                                   height = "420px"))
          ),
          bslib::card(
            bslib::card_header(t("trend_rankings_top15")),
            bslib::card_body(DT::DTOutput("trend_sens_per_year_table"))
          )
        ),
        h4(t("trend_sens_delta_h"),
            style = "color:#1B4332; margin: 16px 16px 4px;"),
        div(style = "margin: 0 16px 8px; font-size:0.82rem; color:#666;",
            tags$em(t("trend_combined_note"))),
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            bslib::card_header(t("tornado_top10")),
            bslib::card_body(plotly::plotlyOutput("trend_tornado_delta_sens",
                                                   height = "420px"))
          ),
          bslib::card(
            bslib::card_header(t("trend_rankings_top15")),
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
      title = t("tab_ipcc_report"),
      icon = icon("file-alt"),

      # ---------- Single-year report layout ----------
      conditionalPanel(
        condition = "input.analysis_mode != 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong(paste0(t("what_to_do_label"), " ")),
            t("info_ipcc_report_intro"), " ",
            t("info_ipcc_three_cols"),
            tags$strong(t("col_ad_uncert")), ", ",
            tags$strong(t("col_ef_uncert")),
            if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                                ifnotfound = "en"), "fr"))
              ", et " else ", and ",
            tags$strong(t("col_combined_uncert")),
            if (identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                                ifnotfound = "en"), "fr"))
              " — toutes exprimées en " else " — all expressed as ",
            tags$strong(t("info_ipcc_pct_label")),
            t("info_ipcc_pct_body"),
            " ", t("info_ipcc_click_label"),
            tags$strong(t("info_ipcc_xlsx_label")),
            t("info_ipcc_xlsx_body"),
            tags$strong(t("info_ipcc_csv_label")),
            t("info_ipcc_csv_body")),
        div(style = "margin: 0 16px 12px; font-size:0.82rem; color:#1B4332; background:#D8F3DC; border-left:3px solid #2D6A4F; padding:10px 12px; border-radius:4px;",
            tags$strong(paste0(t("ad_ef_convention_label"), " ")),
            t("ad_ef_convention_body")),
        bslib::card(
          bslib::card_header(t("card_ipcc_table_h")),
          bslib::card_body(
            uiOutput("ipcc_table_notice"),
            DT::DTOutput("ipcc_table")
          )
        ),
        bslib::card(
          style = "border-left: 4px solid #2D6A4F;",
          bslib::card_header(t("card_downloads_h")),
          bslib::card_body(
            p(style = "margin: 0 0 12px 0; color: #475569; font-size: 0.92rem;",
              t("downloads_intro")),
            fluidRow(
              column(4, downloadButton("download_xlsx",
                                        t("btn_download_xlsx"),
                                        class = "btn-success",
                                        style = "width:100%;")),
              column(4, downloadButton("download_csv",
                                        t("btn_download_csv"),
                                        class = "btn-outline-success",
                                        style = "width:100%;")),
              column(4, downloadButton("download_docx",
                                        t("btn_download_docx"),
                                        class = "btn-primary",
                                        style = "width:100%;"))
            )
          )
        ),
        bslib::card(
          bslib::card_header(t("card_dist_per_source")),
          bslib::card_body(
            p(t("body_dist_per_source"),
              tags$strong(t("xrange_label")),
              t("body_dist_per_source_mid"),
              tags$strong(t("count_label")),
              t("body_dist_per_source_tail")),
            plotly::plotlyOutput("report_source_histograms", height = "420px")
          )
        ),
        bslib::card(
          bslib::card_header(t("card_top_drivers")),
          bslib::card_body(
            p(t("body_top_drivers")),
            plotly::plotlyOutput("report_tornado", height = "380px")
          )
        ),
        bslib::card(
          bslib::card_header(t("card_input_dists")),
          bslib::card_body(
            p(t("body_input_dists")),
            plotly::plotlyOutput("report_input_densities", height = "780px")
          )
        ),
        bslib::card(
          bslib::card_header(t("card_inputs_doc")),
          bslib::card_body(
            p(t("body_inputs_doc")),
            DT::DTOutput("inputs_doc_table")
          )
        )
      ),

      # ---------- Trend report layout ----------
      conditionalPanel(
        condition = "input.analysis_mode == 'trend'",
        div(class = "info-panel", style = "margin: 16px;",
            tags$strong(paste0(t("what_to_do_label"), " ")),
            t("info_trend_report_what")),
        bslib::card(
          bslib::card_header(t("card_trend_downloads")),
          bslib::card_body(
            p(tags$em(t("trend_downloads_note"))),
            fluidRow(
              column(3, downloadButton("download_trend_xlsx", t("btn_download_xlsx"),
                                        class = "btn-success")),
              column(3, downloadButton("download_trend_csv", t("btn_download_csv"),
                                        class = "btn-outline-success")),
              column(3, downloadButton("download_trend_docx", t("btn_download_docx"),
                                        class = "btn-primary"))
            )
          )
        ),
        bslib::card(
          bslib::card_header(t("card_trend_chart_h")),
          bslib::card_body(plotly::plotlyOutput("trend_plot_report", height = "400px"))
        ),
        bslib::card(
          bslib::card_header(t("card_trend_table_h")),
          bslib::card_body(
            p(tags$em(t("trend_table_note"))),
            DT::DTOutput("trend_table_report")
          )
        ),
        bslib::card(
          bslib::card_header(t("card_trend_sens_h")),
          bslib::card_body(
            p(tags$em(t("trend_sens_note"))),
            bslib::layout_columns(
              col_widths = c(6, 6),
              div(
                h6(t("info_trend_sens_per_year_label"), style = "color:#1B4332;"),
                plotly::plotlyOutput("trend_tornado_per_year_report", height = "320px")
              ),
              div(
                h6(t("info_trend_sens_delta_label"), style = "color:#1B4332;"),
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
      title = t("tab_contact"),
      icon = icon("envelope"),
      div(class = "info-panel", style = "margin: 16px;",
          tags$strong(t("contact_intro_label")),
          tags$br(), tags$br(),
          t("contact_intro_body")),
      bslib::layout_columns(
        col_widths = c(6, 6),
        bslib::card(
          bslib::card_header(t("card_contact_send")),
          bslib::card_body(contact_form_html())
        ),
        bslib::card(
          bslib::card_header(t("card_contact_helps")),
          bslib::card_body(
            tags$ul(
              tags$li(tags$strong(t("contact_bug_label")),
                      t("contact_bug_body")),
              tags$li(tags$strong(t("contact_method_label")),
                      t("contact_method_body")),
              tags$li(tags$strong(t("contact_feat_label")),
                      t("contact_feat_body")),
              tags$li(tags$strong(t("contact_doc_label")),
                      t("contact_doc_body"))
            ),
            hr(),
            div(style = "font-size:0.8rem; color:#666;",
                tags$em(t("contact_privacy_note")))
          )
        )
      )
    ),

    # Footer
    bslib::nav_spacer(),
    bslib::nav_item(
      tags$span(style = "color: #6B6B6B; font-size: 0.85rem;",
                t("footer_credit"))
    )
  )
}
