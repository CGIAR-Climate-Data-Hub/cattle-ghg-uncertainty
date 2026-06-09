# Round 8 — Contact / Feedback form via Web3Forms (client-side AJAX).
#
# Web3Forms is a free HTTP form-relay service that forwards POSTed form
# payloads to a verified email address. Their access keys are public-facing
# by design — abuse protection is captcha + rate limits, not key secrecy.
#
# Round 8 design note: the free tier of Web3Forms blocks server-side POSTs
# (responding with "use our API in client side or contact support"). So the
# form posts from the visitor's browser via fetch(). The Shiny server is
# bypassed entirely for the relay.
#
# Round 9 follow-up bug fix: the original implementation returned the form
# AND the <script> tag inside a single HTML() call. Browsers do NOT execute
# <script> tags inserted via innerHTML — so the submit handler was never
# defined, the onsubmit fired the form's default action (full POST + page
# nav), and nothing reached the visitor's inbox. Fix: split into form HTML
# + a tags$script() block so Shiny / htmltools render the script properly
# and the browser executes it.

.WEB3FORMS_DEFAULT_KEY <- "0303db40-85b2-491a-af64-a8c28972868f"
.WEB3FORMS_ENDPOINT    <- "https://api.web3forms.com/submit"

.web3forms_key <- function() {
  k <- Sys.getenv("WEB3FORMS_ACCESS_KEY", unset = "")
  if (nzchar(k)) k else .WEB3FORMS_DEFAULT_KEY
}

# Render the contact form. Returns a tagList(form HTML, <script>) so the
# script element is processed by htmltools as a real DOM element (and
# therefore actually executed by the browser) rather than smuggled inside
# innerHTML where browser security blocks it.
contact_form_html <- function() {
  key <- .web3forms_key()
  endpoint <- .WEB3FORMS_ENDPOINT
  form_html <- sprintf('
<form id="contact-form-w3" onsubmit="return submitContactFormW3(event)" style="display:flex; flex-direction:column; gap:10px;">
  <input type="hidden" name="access_key" value="%s">
  <input type="hidden" name="from_name"  value="Cattle GHG App contact form">
  <!-- Honeypot field per Web3Forms spec (https://web3forms.com/docs/spam-protection) -->
  <input type="checkbox" name="botcheck" style="display:none !important;" tabindex="-1" autocomplete="off">
  <div>
    <label for="cf-name" style="font-weight:600; font-size:0.9rem;">%s *</label>
    <input id="cf-name" type="text" name="name" required class="form-control"
           placeholder="%s" autocomplete="name">
  </div>
  <div>
    <label for="cf-affiliation" style="font-weight:600; font-size:0.9rem;">%s *</label>
    <input id="cf-affiliation" type="text" name="affiliation" required class="form-control"
           placeholder="%s" autocomplete="organization">
  </div>
  <div>
    <label for="cf-email" style="font-weight:600; font-size:0.9rem;">%s *</label>
    <input id="cf-email" type="email" name="email" required class="form-control"
           placeholder="you@example.org" autocomplete="email">
  </div>
  <div>
    <label for="cf-message" style="font-weight:600; font-size:0.9rem;">%s *</label>
    <textarea id="cf-message" name="message" rows="6" required class="form-control"
              placeholder="%s"></textarea>
  </div>
  <button type="submit" class="btn btn-primary w-100" id="cf-submit">
    <i class="fa fa-paper-plane"></i> %s
  </button>
  <div id="cf-status" style="font-size:0.85rem; color:#666; margin-top:6px;">
    <em>%s</em>
  </div>
</form>
', key,
   t("cf_name"), t("cf_name_ph"),
   t("cf_affiliation"), t("cf_affiliation_ph"),
   t("cf_email"),
   t("cf_message"), t("cf_message_ph"),
   t("btn_cf_send"), t("cf_status_init"))

  # Round 9 sent animation: a CSS-only checkmark that draws itself + a
  # success card that fades + slides in. Keyed off classes added by JS.
  styles <- '
<style>
@keyframes cf-fade-in {
  from { opacity: 0; transform: translateY(-6px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes cf-tick-draw {
  to { stroke-dashoffset: 0; }
}
@keyframes cf-circle-draw {
  to { stroke-dashoffset: 0; }
}
.cf-sent-card {
  background: linear-gradient(135deg, #D8F3DC 0%, #B7E4C7 100%);
  color: #1B4332;
  padding: 18px 16px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  gap: 14px;
  animation: cf-fade-in 0.4s ease-out;
  border-left: 4px solid #2D6A4F;
}
.cf-sent-card .cf-tick-svg {
  flex: 0 0 44px;
}
.cf-sent-card .cf-tick-circle {
  fill: none;
  stroke: #2D6A4F;
  stroke-width: 3;
  stroke-dasharray: 138;
  stroke-dashoffset: 138;
  animation: cf-circle-draw 0.5s ease-out 0.1s forwards;
}
.cf-sent-card .cf-tick-check {
  fill: none;
  stroke: #2D6A4F;
  stroke-width: 4;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-dasharray: 36;
  stroke-dashoffset: 36;
  animation: cf-tick-draw 0.35s ease-out 0.55s forwards;
}
.cf-sent-card .cf-sent-text {
  font-weight: 600;
  font-size: 0.95rem;
}
.cf-sent-card .cf-sent-sub {
  font-size: 0.82rem;
  font-weight: 400;
  margin-top: 2px;
  opacity: 0.85;
}
.cf-error-card {
  background: #FECACA;
  color: #7F1D1D;
  padding: 12px 14px;
  border-radius: 8px;
  border-left: 4px solid #C1121F;
  animation: cf-fade-in 0.3s ease-out;
}
</style>
'

  js <- sprintf('
async function submitContactFormW3(e) {
  e.preventDefault();
  var form = document.getElementById("contact-form-w3");
  var btn  = document.getElementById("cf-submit");
  var stat = document.getElementById("cf-status");
  if (form.botcheck && form.botcheck.checked) return false;
  btn.disabled = true;
  btn.innerHTML = "<i class=\\"fa fa-spinner fa-spin\\"></i> %s";
  stat.style.background = "transparent";
  stat.style.color      = "#666";
  stat.style.padding    = "0";
  stat.innerHTML  = "<em>%s</em>";

  var fd = new FormData(form);
  fd.set("subject", "[Cattle GHG App] Feedback from " + (form.name.value || "anonymous"));
  fd.set("replyto", form.email.value || "");

  try {
    var r = await fetch("%s", { method: "POST", body: fd });
    var j = await r.json();
    if (j.success) {
      stat.style.background = "transparent";
      stat.style.padding    = "0";
      stat.innerHTML = [
        "<div class=\\"cf-sent-card\\">",
        "  <svg class=\\"cf-tick-svg\\" viewBox=\\"0 0 52 52\\" width=\\"44\\" height=\\"44\\">",
        "    <circle class=\\"cf-tick-circle\\" cx=\\"26\\" cy=\\"26\\" r=\\"22\\"/>",
        "    <path class=\\"cf-tick-check\\" d=\\"M14 27 l8 8 l16 -18\\"/>",
        "  </svg>",
        "  <div>",
        "    <div class=\\"cf-sent-text\\">%s</div>",
        "    <div class=\\"cf-sent-sub\\">%s</div>",
        "  </div>",
        "</div>"
      ].join("");
      form.reset();
    } else {
      stat.innerHTML = "<div class=\\"cf-error-card\\"><i class=\\"fa fa-exclamation-triangle\\"></i> %s " +
        (j.message || "%s") + ". %s</div>";
    }
  } catch (err) {
    stat.innerHTML = "<div class=\\"cf-error-card\\"><i class=\\"fa fa-exclamation-triangle\\"></i> %s</div>";
  }
  btn.disabled = false;
  btn.innerHTML = "<i class=\\"fa fa-paper-plane\\"></i> %s";
  return false;
}
', t("cf_sending_btn"), t("cf_sending_msg"),
   endpoint,
   t("cf_sent_text"), t("cf_sent_sub"),
   t("cf_send_failed"), t("cf_unknown_error"), t("cf_try_again"),
   t("cf_network_error"),
   t("btn_cf_send"))

  # Return as a tagList: HTML form, <style>, then a separate script tag.
  # Splitting the script out is the bug fix — htmltools renders tags$script
  # as a real DOM element so the browser actually executes it, unlike script
  # tags smuggled inside an HTML() call (innerHTML doesn't run scripts).
  htmltools::tagList(
    htmltools::HTML(form_html),
    htmltools::HTML(styles),
    htmltools::tags$script(htmltools::HTML(js))
  )
}
