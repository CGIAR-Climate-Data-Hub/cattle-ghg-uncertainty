# =============================================================================
# i18n — single-shot English / French language switching
# =============================================================================
#
# Design (per plan): user clicks an EN | FR toggle in the navbar → client-side
# JS writes a `lang` cookie and reloads the page. On reload, the server reads
# the cookie via the request object and sets the package-level `.LANG_CURRENT`
# variable. Every `t("string_id")` call returns the matching language string
# from `.STRINGS`.
#
# No reactive language switching — one reload per toggle click. Avoids
# refactoring hundreds of static nav_panel(title=...) and card_header(...)
# calls into renderUI fragments.
#
# String ID convention: <category>_<short_descriptor>, snake_case. Categories:
#   tab_*   : top-level navbar tab titles
#   card_*  : card headers
#   btn_*   : button labels
#   tip_*   : tooltips / hover-only help
#   info_*  : info-panel paragraphs explaining a feature
#   notif_* : showNotification / modal text
#   qa_*    : QA/QC verdict messages
#   err_*   : error / validation messages
#
# To add a string: pick a stable ID, add an entry to .STRINGS below with both
# `en` and `fr` keys, then replace the literal string in the calling code
# with t("your_id"). Missing translations fall back to English; missing IDs
# render as "[?missing_id?]" so they're obvious during smoke-testing.

# Package-level current language. Set by .i18n_set_lang_from_request() once
# per Shiny session, and consulted by t() during UI construction and server
# rendering. Default = "en".
.LANG_CURRENT <- "en"

.SUPPORTED_LANGS <- c("en", "fr")

.LANG_COOKIE_NAME <- "app_lang"

# Read the language preference from the incoming Shiny request's Cookie:
# header. Called by app_ui(request) and app_server() at session start.
# Returns "en" by default if no cookie is present or the value isn't one
# of the supported languages.
i18n_lang_from_request <- function(request = NULL) {
  if (is.null(request)) return("en")
  cookie_hdr <- request$HTTP_COOKIE %||% ""
  if (!nzchar(cookie_hdr)) return("en")
  pairs <- strsplit(cookie_hdr, ";\\s*")[[1]]
  for (p in pairs) {
    eq <- regexpr("=", p, fixed = TRUE)
    if (eq < 1) next
    k <- trimws(substr(p, 1, eq - 1))
    if (identical(k, .LANG_COOKIE_NAME)) {
      v <- utils::URLdecode(substr(p, eq + 1, nchar(p)))
      if (v %in% .SUPPORTED_LANGS) return(v)
    }
  }
  "en"
}

# Set the package-level language. Called once per session — UI construction
# and all subsequent t() calls in that session use this value.
i18n_set_lang <- function(lang) {
  if (!(lang %in% .SUPPORTED_LANGS)) lang <- "en"
  # Assign in the global environment so all sourced files share state.
  # This mirrors the existing pattern used by other R/ helpers in the app.
  assign(".LANG_CURRENT", lang, envir = .GlobalEnv)
  invisible(lang)
}

# Lookup helper. Pass the string ID; current language is read from
# .LANG_CURRENT. The optional lang arg overrides for tests or for
# situations where one specific language is needed (e.g. emitting the
# canonical English ID in a log message regardless of UI language).
t <- function(id, lang = NULL) {
  if (is.null(lang)) lang <- get0(".LANG_CURRENT", envir = .GlobalEnv,
                                   ifnotfound = "en")
  s <- .STRINGS[[id]]
  if (is.null(s)) return(paste0("[?", id, "?]"))
  s[[lang]] %||% s[["en"]] %||% id
}

# =============================================================================
# String table
# =============================================================================
#
# Phase 1 set: the 11 navbar tab titles + the language toggle's hover hints.
# Subsequent phases extend this list. Per the plan, machine-translation
# seeds the French column for the long tail of strings; the user then
# reviews and shortens (idiomatic + concise principle).

.STRINGS <- list(

  # ---- Navbar tab titles -------------------------------------------------
  # Length budget: 1-2 words. Must not wrap in the navbar.
  tab_home          = list(en = "Home",
                            fr = "Accueil"),
  tab_definitions   = list(en = "Definitions",
                            fr = "Définitions"),
  tab_resources     = list(en = "Resources",
                            fr = "Ressources"),
  tab_data_input    = list(en = "1. Data Input",
                            fr = "1. Données"),
  tab_qaqc          = list(en = "2. QA/QC",
                            fr = "2. QA/QC"),
  tab_uncertainty   = list(en = "3. Uncertainty",
                            fr = "3. Incertitude"),
  tab_correlations  = list(en = "4. Correlations",
                            fr = "4. Corrélations"),
  tab_simulate      = list(en = "5. Simulate & Results",
                            fr = "5. Simuler & Résultats"),
  tab_sensitivity   = list(en = "6. Sensitivity",
                            fr = "6. Sensibilité"),
  tab_ipcc_report   = list(en = "7. IPCC Report",
                            fr = "7. Rapport IPCC"),
  tab_contact       = list(en = "Contact / Feedback",
                            fr = "Contact"),

  # ---- Navbar — language toggle + footer --------------------------------
  tip_lang_toggle_en = list(en = "Switch to English (reloads the page)",
                              fr = "Passer en anglais (recharge la page)"),
  tip_lang_toggle_fr = list(en = "Switch to French (reloads the page)",
                              fr = "Passer en français (recharge la page)"),

  footer_credit = list(
    en = "Developed by CIAT/CGIAR Alliance | Funded by Global Methane Hub",
    fr = "Développé par CIAT/Alliance CGIAR | Financé par Global Methane Hub"
  ),

  # ---- App-wide title strip (top of navbar) -----------------------------
  app_title = list(
    en = "IPCC Tier 2 Livestock GHG Uncertainty Calculator",
    fr = "Calculateur d'incertitude GES Bétail IPCC Niveau 2"
  ),
  app_subtitle = list(
    en = "Approach 2 Monte Carlo · CGIAR Alliance / Bioversity-CIAT · funded by the Global Methane Hub",
    fr = "Monte Carlo Approche 2 · Alliance CGIAR / Bioversity-CIAT · financé par le Global Methane Hub"
  ),

  # ---- Home tab — hero section -----------------------------------------
  hero_title    = list(en = "IPCC Tier 2 Livestock GHG Uncertainty Calculator",
                       fr = "Calculateur d'incertitude GES Bétail IPCC Niveau 2"),
  hero_subtitle = list(en = "Monte Carlo uncertainty analysis for national cattle methane and nitrous oxide inventories.",
                       fr = "Analyse Monte Carlo de l'incertitude pour les inventaires nationaux de méthane et de protoxyde d'azote du bétail."),
  hero_credit   = list(en = "Developed by CGIAR Alliance of Bioversity International and CIAT | Funded by Global Methane Hub",
                       fr = "Développé par l'Alliance CGIAR Bioversity International et CIAT | Financé par Global Methane Hub"),

  # ---- Home tab — "What does this tool do?" card -----------------------
  card_what_does_title = list(en = "What does this tool do?",
                                fr = "À quoi sert cet outil ?"),

  # ---- Home tab — "Before you start" card ------------------------------
  card_before_you_start_title = list(en = "Before you start",
                                       fr = "Avant de commencer"),

  # ---- Home tab — "Three-step workflow" card ---------------------------
  card_workflow_title = list(en = "The three-step workflow",
                               fr = "Le flux en trois étapes"),

  # ---- Resources tab — top intro --------------------------------------
  resources_intro_title = list(en = "Resources & documentation",
                                 fr = "Ressources & documentation"),

  # ---- French-mode help-docs note (Resources tab) ----------------------
  resources_fr_only_note = list(
    en = "",  # never shown in English mode (conditional rendering)
    fr = "La documentation détaillée (guide utilisateur, méthodologie, pages d'aide) est disponible en anglais uniquement pour le moment. Si vous lisez l'anglais, ces documents fournissent les équations, les références IPCC et des explications complètes."
  )
)
