# =============================================================================
# i18n: single-shot English / French language switching
# =============================================================================
#
# Design (per plan): user clicks an EN | FR toggle in the navbar → client-side
# JS writes a `lang` cookie and reloads the page. On reload, the server reads
# the cookie via the request object and sets the package-level `.LANG_CURRENT`
# variable. Every `t("string_id")` call returns the matching language string
# from `.STRINGS`.
#
# No reactive language switching: one reload per toggle click. Avoids
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

# Set the package-level language. Called once per session: UI construction
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
# Cross-reload state cache (used by the language switch)
# =============================================================================
# Switching language reloads the page, which starts a fresh Shiny session and
# would otherwise wipe the user's loaded inventory + results. The R *process*
# survives the reload (it serves every session on the worker), so we stash the
# session state in a process-level environment keyed by a per-browser token
# cookie just before the reload, and the fresh session restores it. Entries are
# one-shot (removed on restore) and age-pruned as a backstop against tabs that
# never come back. Keyed per browser, so concurrent users never collide.
.LANG_STATE_CACHE <- new.env(parent = emptyenv())

lang_state_save <- function(token, state, max_age_s = 900) {
  if (is.null(token) || !nzchar(token)) return(invisible(FALSE))
  now <- as.numeric(Sys.time())
  for (k in ls(.LANG_STATE_CACHE, all.names = TRUE)) {
    e <- get(k, envir = .LANG_STATE_CACHE)
    if (is.null(e$ts) || (now - e$ts) > max_age_s)
      rm(list = k, envir = .LANG_STATE_CACHE)
  }
  assign(token, list(ts = now, state = state), envir = .LANG_STATE_CACHE)
  invisible(TRUE)
}

# One-shot read: returns the saved state list (or NULL) and removes the entry.
lang_state_take <- function(token) {
  if (is.null(token) || !nzchar(token)) return(NULL)
  if (!exists(token, envir = .LANG_STATE_CACHE, inherits = FALSE)) return(NULL)
  e <- get(token, envir = .LANG_STATE_CACHE)
  rm(list = token, envir = .LANG_STATE_CACHE)
  e$state
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
  tab_correlations  = list(en = "3. Correlations",
                            fr = "3. Corrélations"),
  tab_simulate      = list(en = "4. Simulate & Results",
                            fr = "4. Simuler & Résultats"),
  tab_sensitivity   = list(en = "5. Sensitivity",
                            fr = "5. Sensibilité"),
  tab_ipcc_report   = list(en = "6. IPCC Report",
                            fr = "6. Rapport IPCC"),
  tab_contact       = list(en = "Contact / Feedback",
                            fr = "Contact"),

  # ---- Navbar: language toggle + footer --------------------------------
  tip_lang_toggle_en = list(en = "Switch to English (reloads the page)",
                              fr = "Passer en anglais (recharge la page)"),
  tip_lang_toggle_fr = list(en = "Switch to French (reloads the page)",
                              fr = "Passer en français (recharge la page)"),

  footer_version = list(en = "Version", fr = "Version"),
  footer_licence = list(en = "MIT licence", fr = "Licence MIT"),
  footer_github = list(en = "Source code", fr = "Code source"),

  # ---- App-wide title strip (top of navbar) -----------------------------
  app_title = list(
    en = "IPCC Tier 2 Cattle GHG Uncertainty Calculator",
    fr = "Calculateur d'incertitude GES Bovins IPCC Niveau 2"
  ),
  app_subtitle = list(
    en = "Approach 2 Monte Carlo · CGIAR Alliance / Bioversity-CIAT · funded by the Global Methane Hub",
    fr = "Monte Carlo Approche 2 · Alliance CGIAR / Bioversity-CIAT · financé par le Global Methane Hub"
  ),

  # ---- Cross-group coefficient sharing (2026-09) -----------------------
  crossgroup_label = list(
    en = "Inputs shared between groups",
    fr = "Entrées partagées entre groupes"),
  crossgroup_shared = list(
    en = "Treat a shared value as one estimate",
    fr = "Traiter une valeur partagée comme une seule estimation"),
  crossgroup_shared_help = list(
    en = "Where several groups carry the same number for a coefficient, it is one estimate applied several times, so its error moves every group in the same direction at once. This is the IPCC treatment and it keeps the reported uncertainty independent of how finely you split the inventory.",
    fr = "Lorsque plusieurs groupes portent le même nombre pour un coefficient, il s'agit d'une seule estimation appliquée plusieurs fois : son erreur déplace donc tous les groupes dans le même sens en même temps. C'est le traitement IPCC, et il rend l'incertitude rapportée indépendante de la finesse du découpage de l'inventaire."),
  crossgroup_independent = list(
    en = "Treat every group independently (default)",
    fr = "Traiter chaque groupe indépendamment (par défaut)"),
  crossgroup_independent_help = list(
    en = "Each group redraws every coefficient on its own. Correct only if each group's values were estimated separately. On a shared estimate this understates the uncertainty, and increasingly so the more groups there are.",
    fr = "Chaque groupe retire lui-même chaque coefficient. Correct uniquement si les valeurs de chaque groupe ont été estimées séparément. Sur une estimation partagée, cela sous-estime l'incertitude, d'autant plus que les groupes sont nombreux."),
  crossgroup_detected_none = list(
    en = "No coefficient is shared between groups in this inventory, so this setting changes nothing.",
    fr = "Aucun coefficient n'est partagé entre les groupes de cet inventaire : ce réglage ne change donc rien."),
  crossgroup_exclusive = list(
    en = "For a coefficient that is shared, sharing takes the place of the correlation mode chosen above: a value cannot be drawn once for every group and separately correlated inside each one at the same time. Coefficients that are not shared, and the activity data, still follow the mode above. Sharing is the larger of the two effects, which is why it takes precedence.",
    fr = "Pour un coefficient partagé, le partage remplace le mode de corrélation choisi ci-dessus : une valeur ne peut pas être tirée une seule fois pour tous les groupes et corrélée séparément à l'intérieur de chacun en même temps. Les coefficients non partagés, ainsi que les données d'activité, suivent toujours le mode ci-dessus. Le partage est le plus important des deux effets, d'où sa priorité."),
  crossgroup_detected_pre = list(
    en = "Detected: ", fr = "Détecté : "),
  crossgroup_detected_body = list(
    en = "%d coefficients are used identically across groups in this inventory (%s). They will be drawn once and applied to every group that shares them.",
    fr = "%d coefficients sont utilisés à l'identique entre groupes dans cet inventaire (%s). Ils seront tirés une fois puis appliqués à chaque groupe qui les partage."),


  # ---- Measured-intake route (GE / DMI), 2026-09 -----------------------
  # Route labels. These appear in the results table and in every export, so
  # a reader can tell how each group reached gross energy without opening
  # the input file.
  route_energy_balance = list(en = "Energy balance",
                                fr = "Bilan énergétique"),
  route_measured_ge    = list(en = "Measured GE", fr = "EB mesurée"),
  route_measured_dmi   = list(en = "Measured DMI", fr = "IMS mesurée"),
  route_mixed          = list(en = "Mixed", fr = "Mixte"),
  res_col_intake_route = list(en = "Intake route", fr = "Voie d'ingestion"),


  # ---- SEO head strings (browser tab title, meta description) ----------
  # The window title deliberately says "Cattle" (the search phrase people
  # use) while the on-page app_title keeps the formal IPCC "Livestock" name.
  seo_window_title = list(
    en = "Cattle GHG Uncertainty Calculator | IPCC Tier 2 Monte Carlo (free web tool)",
    fr = "Calculateur d'incertitude GES bovins | IPCC Niveau 2 Monte Carlo (outil web gratuit)"
  ),
  seo_meta_description = list(
    en = "Free web tool for national GHG inventory teams: Monte Carlo (IPCC Approach 2) uncertainty analysis for Tier 2 cattle emissions, with IPCC Table 3.3 outputs.",
    fr = "Outil web gratuit pour les équipes d'inventaire national de GES : analyse d'incertitude Monte Carlo (Approche 2 IPCC) des émissions bovines Niveau 2, sorties au format Tableau 3.3 IPCC."
  ),

  # ---- Home tab: hero section -----------------------------------------
  hero_title    = list(en = "IPCC Tier 2 Cattle GHG Uncertainty Calculator",
                       fr = "Calculateur d'incertitude GES Bovins IPCC Niveau 2"),
  hero_subtitle = list(en = "Monte Carlo uncertainty analysis for national cattle methane and nitrous oxide inventories.",
                       fr = "Analyse Monte Carlo de l'incertitude pour les inventaires nationaux de méthane et de protoxyde d'azote des bovins."),
  hero_credit   = list(en = "Developed by CGIAR Alliance of Bioversity International and CIAT | Funded by Global Methane Hub",
                       fr = "Développé par l'Alliance CGIAR Bioversity International et CIAT | Financé par Global Methane Hub"),

  # ---- Home tab: "What does this tool do?" card -----------------------
  card_what_does_title = list(en = "What does this tool do?",
                                fr = "À quoi sert cet outil ?"),

  # ---- Home tab: "Before you start" card ------------------------------
  card_before_you_start_title = list(en = "Before you start",
                                       fr = "Avant de commencer"),

  # ---- Home tab: "Three-step workflow" card ---------------------------
  card_workflow_title = list(en = "The three-step workflow",
                               fr = "Le flux en trois étapes"),

  # ---- Resources tab: top intro --------------------------------------
  resources_intro_title = list(en = "Resources & documentation",
                                 fr = "Ressources & documentation"),

  # ---- French-mode help-docs note (Resources tab) ----------------------
  resources_fr_only_note = list(
    en = "",  # never shown in English mode (conditional rendering)
    fr = "La documentation détaillée (guide utilisateur, méthodologie, pages d'aide) est disponible en anglais uniquement pour le moment. Si vous lisez l'anglais, ces documents fournissent les équations, les références IPCC et des explications complètes."
  ),

  # =====================================================================
  # HOME TAB: full content
  # =====================================================================

  # "What does this tool do?" card body
  what_does_intro = list(
    en = "When a country reports cattle greenhouse gas emissions under the Paris Agreement, every input parameter (animal populations, body weights, feed quality, emission factors) has some uncertainty. This tool:",
    fr = "Lorsqu'un pays déclare ses émissions de gaz à effet de serre du bétail dans le cadre de l'Accord de Paris, chaque paramètre d'entrée (populations animales, poids vifs, qualité de l'alimentation, facteurs d'émission) comporte une incertitude. Cet outil :"
  ),
  what_does_li1 = list(en = "Takes your country-specific input data aligned with the IPCC Tier 2 equations, with uncertainty ranges",
                        fr = "Prend vos données nationales alignées sur les équations IPCC Niveau 2, avec leurs plages d'incertitude"),
  what_does_li2 = list(en = "Runs thousands of Monte Carlo simulations, varying all parameters according to their probability distributions",
                        fr = "Exécute des milliers de simulations Monte Carlo en faisant varier tous les paramètres selon leurs distributions de probabilité"),
  what_does_li3 = list(en = "Produces the uncertainty range for your total emission estimate (95% confidence interval)",
                        fr = "Produit la plage d'incertitude de votre estimation totale d'émissions (intervalle de confiance à 95 %)"),
  what_does_li4 = list(en = "Identifies which parameters contribute most to the uncertainty (sensitivity analysis)",
                        fr = "Identifie les paramètres qui contribuent le plus à l'incertitude (analyse de sensibilité)"),
  what_does_li5 = list(en = "Formats results for IPCC inventory reporting (IPCC 2006 Vol. 1 Ch. 3, Table 3.3)",
                        fr = "Met en forme les résultats pour le rapport d'inventaire IPCC (IPCC 2006 Vol. 1 Ch. 3, Tableau 3.3)"),
  what_does_sources_label = list(en = "Emission sources covered:",
                                   fr = "Sources d'émissions couvertes :"),
  what_does_sources_body = list(
    en = " Enteric fermentation CH₄, Manure management CH₄, Manure management N₂O (direct and indirect), and N₂O (direct and indirect) from dung and urine deposited on pasture.",
    fr = " Fermentation entérique CH₄, Gestion du fumier CH₄, Gestion du fumier N₂O (direct et indirect), et N₂O (direct et indirect) issus des excréments et urines déposés sur les pâturages."
  ),

  # "How to use this tool: step by step" card
  workflow_title = list(en = "How to use this tool -- Step by step",
                          fr = "Comment utiliser cet outil : étape par étape"),
  workflow_intro = list(en = "Work through the tabs from left to right. Each tab has instructions at the top explaining what to do.",
                          fr = "Parcourez les onglets de gauche à droite. Chaque onglet comporte des instructions en haut expliquant ce qu'il faut faire."),
  workflow_th_step = list(en = "Step", fr = "Étape"),
  workflow_th_tab  = list(en = "Tab",  fr = "Onglet"),
  workflow_th_what = list(en = "What you do", fr = "Action"),
  workflow_th_time = list(en = "Time", fr = "Durée"),
  workflow_row1_tab  = list(en = "Data Input", fr = "Saisie"),
  workflow_row1_what = list(en = "Load example data or upload your country data from the Excel template",
                              fr = "Charger les données d'exemple ou téléverser vos données nationales depuis le modèle Excel"),
  workflow_row2_tab  = list(en = "QA/QC", fr = "QA/QC"),
  workflow_row2_what = list(en = "Review automated quality checks -- fix any fails and document large deviations from IPCC defaults",
                              fr = "Examiner les vérifications de qualité automatiques : corriger les échecs et documenter les écarts importants par rapport aux valeurs par défaut IPCC"),
  workflow_row3_tab  = list(en = "Correlations", fr = "Corrélations"),
  workflow_row3_what = list(en = "(Optional) Upload population time series or manually define correlations between activity data",
                              fr = "(Facultatif) Téléverser des séries temporelles de populations ou définir manuellement les corrélations entre données d'activité"),
  workflow_row4_tab  = list(en = "Simulate", fr = "Simulation"),
  workflow_row4_what = list(en = "Choose number of iterations, GWP version, and click Run: results (emission distributions, 95% CI, decomposition) appear in the same tab",
                              fr = "Choisir le nombre d'itérations, la version de GWP, puis cliquer sur Lancer : les résultats (distributions d'émissions, IC à 95 %, décomposition) apparaissent dans le même onglet"),
  workflow_row5_tab  = list(en = "Sensitivity", fr = "Sensibilité"),
  workflow_row5_what = list(en = "Identify which parameters contribute most to uncertainty (tornado chart)",
                              fr = "Identifier les paramètres qui contribuent le plus à l'incertitude (graphique tornade)"),
  workflow_row6_tab  = list(en = "IPCC Report", fr = "Rapport IPCC"),
  workflow_row6_what = list(en = "Download results formatted as IPCC Table 3.3 for your inventory submission",
                              fr = "Télécharger les résultats au format IPCC Tableau 3.3 pour votre soumission d'inventaire"),

  # Quick-start info panel (HTML with embedded <strong> for tab references)
  quick_start_html = list(
    en = "<strong>Quick start: </strong>To try the tool immediately, go to <strong>1. Data Input</strong>, select 'Country X (hypothetical dairy)', then go to <strong>4. Simulate</strong> and click 'Run Monte Carlo Simulation'.",
    fr = "<strong>Démarrage rapide : </strong>Pour essayer l'outil immédiatement, allez dans <strong>1. Données</strong>, sélectionnez « Pays X (laitier hypothétique) », puis allez dans <strong>4. Simulation</strong> et cliquez sur « Lancer la simulation Monte Carlo »."
  ),

  btn_goto_resources = list(en = "Methodology, user guide & downloads →",
                              fr = "Méthodologie, guide utilisateur & téléchargements →"),

  # "Before you start" card
  # Reframed 2026-09-29: this was a "You will need" list mirrored by a
  # "What this tool does NOT do" list, which repeated the same boundaries
  # twice and read like boilerplate. Same three limits, folded into the
  # bullet each one belongs to, as a division of labour.
  before_you_will_need = list(en = "What you bring:",
                                fr = "Ce que vous apportez :"),
  before_li1 = list(
    en = "Your Tier 2 dataset for the inventory year or years you want to assess: animal sub-categories with population, body weights, feed quality and manure-management shares. The calculation follows the IPCC Tier 2 equation chain, so Tier 1 inventories and country-specific methods fall outside what it can analyse.",
    fr = "Votre jeu de données Niveau 2 pour la ou les années d'inventaire à évaluer : sous-catégories animales avec population, poids vifs, qualité de l'alimentation et répartition de la gestion du fumier. Le calcul suit l'enchaînement d'équations IPCC Niveau 2 ; les inventaires Niveau 1 et les méthodes nationales spécifiques sortent donc de son champ d'analyse."
  ),
  before_li2_html = list(
    en = "An uncertainty range for each input, usually the ±% half-width of the 95 % CI, or explicit lower and upper bounds for asymmetric parameters. Judging those ranges depends on your data and its sources, so that call stays with you: the tool <strong>propagates the uncertainty you give it</strong> rather than estimating it.",
    fr = "Une plage d'incertitude pour chaque entrée, généralement la demi-largeur ±% de l'IC à 95 %, ou des bornes inférieure et supérieure explicites pour les paramètres asymétriques. Juger ces plages dépend de vos données et de leurs sources : cette décision vous revient. L'outil <strong>propage l'incertitude que vous lui fournissez</strong>, il ne l'estime pas."
  ),
  before_li3 = list(
    en = "Your own sub-category structure. The tool simulates whatever grouping you define and reports against it; how your herd is split into categories stays your decision.",
    fr = "Votre propre structure de sous-catégories. L'outil simule le découpage que vous définissez et produit ses résultats en conséquence ; la répartition de votre cheptel en catégories reste votre décision."
  ),
  before_li4 = list(
    en = "Optionally, a multi-year time series of activity data. Supply one and the tool derives the parameter correlations for you.",
    fr = "Facultativement, une série temporelle pluriannuelle de données d'activité. Si vous en fournissez une, l'outil en déduit les corrélations entre paramètres."
  ),

  # =====================================================================
  # RESOURCES TAB
  # =====================================================================

  card_tool_resources = list(en = "Tool-specific resources",
                              fr = "Ressources de l'outil"),
  resources_how_it_works = list(en = "How this tool works",
                                  fr = "Comment fonctionne cet outil"),
  resources_eq_chain = list(
    en = "Equation chain: IPCC 2006 Vol 4 Ch 10 (Eq 10.1–10.34) and Ch 11 for the per-head emission factor; population × EF for the per-sub-category total.",
    fr = "Enchaînement d'équations : IPCC 2006 Vol 4 Ch 10 (Éq 10.1–10.34) et Ch 11 pour le facteur d'émission par tête ; population × FE pour le total par sous-catégorie."
  ),
  resources_mc = list(
    en = "Monte Carlo: Approach 2 from IPCC 2006 Vol 1 Ch 3. Correlations are sampled via the rank-correlation-preserving restricted-pairing procedure per IPCC Vol 1 Ch 3 §3.2.3.2, the same method is used for every correlated path (time-series, preset, manual, structural defaults).",
    fr = "Monte Carlo : Approche 2 de l'IPCC 2006 Vol 1 Ch 3. Les corrélations sont échantillonnées via la procédure de pairage restreint préservant les corrélations de rang (IPCC Vol 1 Ch 3 §3.2.3.2), la même méthode est utilisée pour chaque voie corrélée (séries temporelles, préréglée, manuelle, valeurs par défaut structurelles)."
  ),
  resources_sensitivity = list(
    en = "Sensitivity: Standardised regression coefficients (SRC) on the sampled inputs vs each output.",
    fr = "Sensibilité : coefficients de régression standardisés (SRC) sur les entrées échantillonnées par rapport à chaque sortie."
  ),
  btn_open_methodology = list(en = "Open full methodology (PDF)",
                                fr = "Ouvrir la méthodologie complète (PDF)"),
  btn_open_userguide = list(en = "Open user guide (PDF)",
                              fr = "Ouvrir le guide utilisateur (PDF)"),
  btn_open_definitions = list(en = "Definitions and glossary",
                               fr = "Définitions et glossaire"),
  def_back_to_resources = list(en = "Back to Resources", fr = "Retour aux ressources"),

  card_useful_resources = list(en = "Useful resources",
                                 fr = "Ressources utiles"),
  resources_method_foundations = list(en = "Methodological foundations",
                                        fr = "Fondements méthodologiques"),
  resources_method_intro = list(
    en = "The six IPCC chapters that underpin the calculations and uncertainty methodology of this tool. Links open the official PDFs on the IPCC-NGGIP site.",
    fr = "Les six chapitres IPCC qui sous-tendent les calculs et la méthodologie d'incertitude de cet outil. Les liens ouvrent les PDF officiels sur le site IPCC-NGGIP."
  ),
  resources_vol4_livestock_label = list(en = "Vol. 4 (AFOLU): Livestock & Manure Management:",
                                          fr = "Vol. 4 (AFOLU) : Élevage & gestion du fumier :"),
  resources_vol4_livestock_2006 = list(
    en = "IPCC 2006 Guidelines: Vol. 4, Chapter 10 (Emissions from Livestock and Manure Management)",
    fr = "Lignes directrices IPCC 2006 : Vol. 4, Chapitre 10 (Émissions de l'élevage et de la gestion du fumier)"
  ),
  resources_vol4_livestock_2019 = list(
    en = "2019 Refinement: Vol. 4, Chapter 10 (Updated livestock equations, MMS table 10.17, Bo table 10.16a, Ym table 10.12)",
    fr = "Raffinement 2019 : Vol. 4, Chapitre 10 (équations mises à jour, tableau MMS 10.17, Bo tableau 10.16a, Ym tableau 10.12)"
  ),
  resources_vol4_soils_label = list(en = "Vol. 4 (AFOLU): Managed Soils (N₂O from soils, including PRP):",
                                       fr = "Vol. 4 (AFOLU) : Sols gérés (N₂O des sols, y compris PRP) :"),
  resources_vol4_soils_2006 = list(
    en = "IPCC 2006 Guidelines: Vol. 4, Chapter 11 (N₂O Emissions from Managed Soils, CO₂ from Lime/Urea)",
    fr = "Lignes directrices IPCC 2006 : Vol. 4, Chapitre 11 (Émissions de N₂O des sols gérés, CO₂ chaux/urée)"
  ),
  resources_vol4_soils_2019 = list(
    en = "2019 Refinement: Vol. 4, Chapter 11 (Updated EF3_PRP table 11.1, EF4/EF5/FracGASM/FracLEACH-(H) table 11.3)",
    fr = "Raffinement 2019 : Vol. 4, Chapitre 11 (EF3_PRP mis à jour tableau 11.1, EF4/EF5/FracGASM/FracLEACH-(H) tableau 11.3)"
  ),
  resources_vol1_uncert_label = list(en = "Vol. 1: Uncertainty methodology (Approach 1 vs Approach 2):",
                                       fr = "Vol. 1 : Méthodologie d'incertitude (Approche 1 vs Approche 2) :"),
  resources_vol1_uncert_2006 = list(
    en = "IPCC 2006 Guidelines: Vol. 1, Chapter 3 (Uncertainties)",
    fr = "Lignes directrices IPCC 2006 : Vol. 1, Chapitre 3 (Incertitudes)"
  ),
  resources_vol1_uncert_2019 = list(
    en = "2019 Refinement: Vol. 1, Chapter 3 (Uncertainties; including §3.2.2.4 on temporal correlation of EFs)",
    fr = "Raffinement 2019 : Vol. 1, Chapitre 3 (Incertitudes ; y compris §3.2.2.4 sur la corrélation temporelle des FE)"
  ),
  resources_ad_guidance = list(en = "Activity data guidance",
                                 fr = "Guides sur les données d'activité"),
  resources_fao_ladg = list(en = "FAO Livestock Activity Data Guidance (L-ADG)",
                              fr = "Guide FAO sur les données d'activité d'élevage (L-ADG)"),
  resources_penman = list(
    en = "Penman et al. (2000): Good Practice Guidance and Uncertainty Management in National Greenhouse Gas Inventories",
    fr = "Penman et al. (2000) : Guide des bonnes pratiques et gestion de l'incertitude dans les inventaires nationaux de gaz à effet de serre"
  ),
  resources_dist_mc_title = list(en = "Distributions and Monte Carlo references",
                                   fr = "Distributions et références Monte Carlo"),
  resources_frey_rhodes = list(
    en = "Frey & Rhodes (1998): Characterizing, simulating, and analyzing variability and uncertainty",
    fr = "Frey & Rhodes (1998) : Caractérisation, simulation et analyse de la variabilité et de l'incertitude"
  ),
  resources_gpg_2000 = list(
    en = "IPCC GPG 2000 §6: Quantifying uncertainties in practice (Approach 1 vs Approach 2)",
    fr = "IPCC GPG 2000 §6 : Quantifier les incertitudes en pratique (Approche 1 vs Approche 2)"
  ),
  resources_learning_title = list(en = "Learning resources",
                                    fr = "Ressources de formation"),
  resources_fao_elearn_uncert = list(en = "FAO e-learning: Assessing uncertainty in the land sector",
                                       fr = "Cours en ligne FAO : Évaluer l'incertitude dans le secteur des terres"),
  resources_fao_elearn_tier2 = list(en = "FAO e-learning: Tier 2 inventory for livestock",
                                      fr = "Cours en ligne FAO : Inventaire Niveau 2 pour l'élevage"),
  resources_unfccc_webinar = list(en = "UNFCCC webinar notes: Uncertainty analysis for GHG inventories",
                                    fr = "Notes des webinaires CCNUCC : Analyse d'incertitude pour les inventaires GES"),
  resources_case_studies = list(en = "Case studies",
                                  fr = "Études de cas"),
  resources_monni = list(
    en = "Monni et al. (2007): Uncertainty in agricultural CH₄ and N₂O emissions from Finland",
    fr = "Monni et al. (2007) : Incertitude des émissions agricoles de CH₄ et N₂O en Finlande"
  ),
  resources_karimi = list(
    en = "Karimi-Zindashty et al. (2012): Sources of uncertainty in livestock emission inventories: Canadian case study",
    fr = "Karimi-Zindashty et al. (2012) : Sources d'incertitude dans les inventaires d'émissions d'élevage : étude de cas canadienne"
  ),
  resources_milne = list(
    en = "Milne et al. (2014): Estimating uncertainty in pasture-based dairy CH₄ emissions",
    fr = "Milne et al. (2014) : Estimation de l'incertitude des émissions de CH₄ laitières au pâturage"
  ),
  resources_more_to_come = list(en = "Additional national-inventory examples to be added.",
                                  fr = "D'autres exemples d'inventaires nationaux seront ajoutés."),

  # =====================================================================
  # AI TRANSLATOR CARD (wrapper UI only: chat content stays English)
  # =====================================================================

  ai_card_title = list(
    en = "AI Translator: turn your raw cattle data into the tool's template",
    fr = "Traducteur IA : convertir vos données brutes en modèle de l'outil"
  ),
  ai_intro_part1 = list(en = "Drop in your raw cattle data file (.xlsx or .csv). The AI works in three short steps:",
                          fr = "Déposez votre fichier de données brutes (.xlsx ou .csv). L'IA travaille en trois étapes courtes :"),
  ai_step1_label = list(en = "(1) Explore", fr = "(1) Explorer"),
  ai_step1_body  = list(en = ": it reads every sheet and reports back what it found (which parameters live where, units, ambiguities).",
                          fr = " : elle lit chaque feuille et rapporte ce qu'elle a trouvé (quels paramètres sont où, unités, ambiguïtés)."),
  ai_step2_label = list(en = "(2) Clarify", fr = "(2) Clarifier"),
  ai_step2_body  = list(en = ": you answer its questions in plain English.",
                          fr = " : vous répondez à ses questions en anglais simple."),
  ai_step3_label = list(en = "(3) Emit", fr = "(3) Générer"),
  ai_step3_body  = list(en = ": click Produce template now and download the .xlsx in the exact format the Data Input tab expects.",
                          fr = " : cliquez sur « Générer le modèle » et téléchargez le .xlsx au format attendu par l'onglet Données."),
  ai_intro_signin_note = list(en = "No setup: sign in once with your email and you're ready.",
                                fr = "Aucune configuration : connectez-vous une fois avec votre e-mail, c'est prêt."),
  # Tutorial video. One recording, linked from each tab at the timestamp
  # that covers that tab.
  video_watch_tab = list(en = "Watch this tab explained",
                           fr = "Voir l'explication de cet onglet"),
  video_full_title = list(en = "Technical walkthrough (video)",
                            fr = "Présentation technique (vidéo)"),
  video_full_body = list(
    en = "A 23-minute walkthrough of the whole tool: every tab and control, the Excel input template sheet by sheet, and the Country X worked example run from data entry to the IPCC report. Each tab of the app also links to the point in the video that covers it.",
    fr = "Une présentation de 23 minutes de l'ensemble de l'outil : chaque onglet et chaque commande, le modèle Excel feuille par feuille, et l'exemple Country X traité de la saisie jusqu'au rapport IPCC. Chaque onglet de l'application renvoie aussi au passage de la vidéo qui le concerne."),
  # "Monte Carlo in motion", linked from the Simulate tab. It explains the
  # method, not the app, so the label says so.
  video_learn_mc = list(en = "Learn how Monte Carlo works",
                          fr = "Comprendre la méthode de Monte-Carlo"),
  btn_open_video = list(en = "Watch the walkthrough",
                          fr = "Voir la présentation"),

  # ---- Home page, rewritten 2026-10-12 --------------------------------
  # Replaces the five-bullet description of the mechanism and the
  # seven-row workflow table. Headings name their content; sentences
  # state facts. No contrasts for emphasis, no fragments.
  status_title = list(
    en = "Version 1, in review",
    fr = "Version 1, en cours de revue"),
  status_body = list(
    en = "This version is being reviewed with national inventory teams before its public release. Access is limited to the review group for now.",
    fr = "Cette version est en cours de revue avec des équipes nationales d'inventaire avant sa publication. L'accès est pour l'instant réservé au groupe de revue."),

  video_overview_title = list(
    en = "Start with the five-minute overview",
    fr = "Commencer par la présentation de cinq minutes"),
  video_overview_body = list(
    en = "What the tool is for, what it produces, and the five steps of a run. It uses a worked example, so the figures on screen are real output.",
    fr = "À quoi sert l'outil, ce qu'il produit, et les cinq étapes d'une exécution. La présentation s'appuie sur un exemple complet : les chiffres à l'écran sont de vrais résultats."),
  btn_watch_overview = list(en = "Watch the overview", fr = "Voir la présentation"),

  what_problem = list(
    en = "The IPCC asks countries to report how uncertain their emission estimates are. For a Tier 2 cattle inventory this means propagating the uncertainty of around thirty parameters through the full equation chain. In practice the step is often done with generic default ranges, or omitted, because the calculation is laborious and few teams have a suitable tool.",
    fr = "L'IPCC demande aux pays de rapporter le degré d'incertitude de leurs estimations d'émissions. Pour un inventaire bovin de niveau 2, cela suppose de propager l'incertitude d'une trentaine de paramètres à travers toute la chaîne d'équations. En pratique, cette étape est souvent réalisée avec des plages par défaut, ou omise, car le calcul est laborieux et peu d'équipes disposent d'un outil adapté."),

  benefit1_title = list(en = "Country-specific inputs", fr = "Données propres au pays"),
  benefit1_body = list(
    en = "The calculation runs on the parameter values and uncertainty estimates from your own inventory. Where a value is not available, the tool applies the IPCC default and marks the row so you can see which figures are yours.",
    fr = "Le calcul utilise les valeurs et les estimations d'incertitude de votre propre inventaire. Lorsqu'une valeur manque, l'outil applique la valeur IPCC par défaut et signale la ligne, afin que vous puissiez distinguer vos chiffres."),
  benefit2_title = list(en = "Results in reporting format", fr = "Résultats au format de rapportage"),
  benefit2_body = list(
    en = "Output is produced in the layout of IPCC Table 3.3 and the UNFCCC Common Reporting Tables, so the figures can be carried across into an inventory submission without rework.",
    fr = "Les résultats sont produits selon la présentation du tableau 3.3 de l'IPCC et des tableaux de rapportage communs de la CCNUCC, et peuvent donc être repris directement dans une soumission d'inventaire."),
  benefit3_title = list(en = "Ranking of influential inputs", fr = "Classement des paramètres influents"),
  benefit3_body = list(
    en = "A sensitivity analysis ranks the parameters by how much each one contributes to the total uncertainty. This indicates where better data would reduce the uncertainty most.",
    fr = "Une analyse de sensibilité classe les paramètres selon leur contribution à l'incertitude totale. Cela indique où de meilleures données réduiraient le plus l'incertitude."),
  benefit4_title = list(en = "Runs in a browser", fr = "Fonctionne dans un navigateur"),
  benefit4_body = list(
    en = "Data are entered through an Excel template. There is no software to install and no programming involved.",
    fr = "Les données sont saisies dans un modèle Excel. Aucun logiciel à installer et aucune programmation requise."),

  trust_open = list(
    en = "Free to use, open source under the MIT licence.",
    fr = "Gratuit, code ouvert sous licence MIT."),
  trust_reviewed = list(
    en = "Reviewed by FAO, the UNFCCC secretariat and the Global Research Alliance on Agricultural Greenhouse Gases.",
    fr = "Examiné par la FAO, le secrétariat de la CCNUCC et la Global Research Alliance on Agricultural Greenhouse Gases."),
  trust_built = list(
    en = "Built by the Alliance of Bioversity International and CIAT under the CGIAR Climate Action Programme, funded by the Global Methane Hub.",
    fr = "Développé par l'Alliance of Bioversity International and CIAT dans le cadre du CGIAR Climate Action Programme, avec le financement du Global Methane Hub."),

  steps_title = list(en = "How a run works", fr = "Déroulement d'une exécution"),
  step1_title = list(en = "Prepare the data", fr = "Préparer les données"),
  step1_body = list(
    en = "Load one of the worked examples, or your own inventory through the Excel template. The tool checks every parameter and reports what is missing, unusual or invalid.",
    fr = "Chargez l'un des exemples fournis, ou votre propre inventaire via le modèle Excel. L'outil vérifie chaque paramètre et signale ce qui est manquant, inhabituel ou invalide."),
  step2_title = list(en = "Describe the uncertainty and run", fr = "Décrire l'incertitude et lancer"),
  step2_body = list(
    en = "Each input carries a distribution and a range from the template. State any correlations between inputs, then run the Monte Carlo simulation.",
    fr = "Chaque entrée porte une distribution et une plage issues du modèle. Indiquez les corrélations éventuelles entre entrées, puis lancez la simulation de Monte-Carlo."),
  step3_title = list(en = "Read and report the results", fr = "Lire et rapporter les résultats"),
  step3_body = list(
    en = "Read the confidence interval for each emission source and the ranking of influential inputs, then download the results in IPCC Table 3.3 format as Excel, CSV or Word.",
    fr = "Consultez l'intervalle de confiance de chaque source d'émission et le classement des paramètres influents, puis téléchargez les résultats au format du tableau 3.3 de l'IPCC, en Excel, CSV ou Word."),

  # Workshop hold notice. Shown until 16 October 2026, then it retires
  # itself (see .TRANSLATOR_HOLD_UNTIL in R/chat_ui.R).
  # Scale warning on upload (2026-10-13). Shown before the first billed
  # call when a file implies more groups than the server can simulate.
  # Template upload: more groups than this deployment can simulate.
  # The message has to carry the fix, because the user meets it at the one
  # moment when aggregating is still cheap.
  upload_too_many_groups = list(
    en = "This file describes %s groups, and this server can simulate about %d. A run is likely to stop partway through with a memory error.",
    fr = "Ce fichier décrit %s groupes, et ce serveur peut en simuler environ %d. Une simulation risque de s'interrompre en cours d'exécution faute de mémoire."),
  upload_too_many_groups_fix = list(
    en = "Combine your data to a coarser level before running: add the populations together and take population-weighted averages of the other parameters. Do not split the file and run the parts separately, because the confidence intervals of the parts cannot be added back together correctly. See the user guide, \"How many groups the tool can run\".",
    fr = "Regroupez vos données à un niveau plus agrégé avant de lancer la simulation : additionnez les effectifs et calculez des moyennes pondérées par les effectifs pour les autres paramètres. Ne divisez pas le fichier pour en simuler les parties séparément : les intervalles de confiance des parties ne peuvent pas être recombinés correctement. Voir le guide d'utilisation, section \"Nombre de groupes que l'outil peut traiter\"."),

  ai_scale_title = list(
    en = "This file may be too large to simulate",
    fr = "Ce fichier est peut-être trop volumineux pour être simulé"),
  ai_scale_tokens = list(
    en = "The data about to be sent is roughly %s tokens, which is more than the conversation can carry.",
    fr = "Les données sur le point d'être envoyées représentent environ %s jetons, ce qui dépasse ce que la conversation peut contenir."),
  ai_scale_heavy = list(
    en = "Most of it is in: %s. Untick any sheet that is a reference or lookup table rather than inventory data.",
    fr = "L'essentiel provient de : %s. Décochez toute feuille qui est une table de référence ou de correspondance plutôt que des données d'inventaire."),
  # Conditional by design. A file can be too large in tokens for reasons that
  # have nothing to do with geography: many years, many sheets, one very wide
  # table. Stating the group advice as a fact would misdirect those users, so
  # it opens with "If".
  ai_scale_groups = list(
    en = "If your inventory describes more than about %d groups (one group is an aggregation level times an animal sub-category) it will also be too large to simulate, so decide the level before translating rather than after: aggregating afterwards means translating the file a second time.",
    fr = "Si votre inventaire décrit plus d'environ %d groupes (un groupe est un niveau d'agrégation multiplié par une sous-catégorie animale), il sera également trop volumineux pour être simulé. Décidez donc du niveau avant la traduction plutôt qu'après : agréger ensuite oblige à traduire le fichier une seconde fois."),
  ai_scale_footer = list(
    en = "You can send it anyway. This is a warning, not a block: it is here so the cost is known before the call, not after.",
    fr = "Vous pouvez l'envoyer malgré tout. Il s'agit d'un avertissement et non d'un blocage : il est affiché pour que le coût soit connu avant l'appel, et non après."),
  ai_upload_too_big = list(
    en = "That file is %s MB. The upload limit is %d MB, so it was not sent. Save the sheets the inventory needs as a separate .xlsx and upload that: a national calculator usually carries large feed or lookup tables the tool does not read.",
    fr = "Ce fichier fait %s Mo. La limite de téléversement est de %d Mo, il n'a donc pas été envoyé. Enregistrez les feuilles nécessaires à l'inventaire dans un fichier .xlsx séparé et téléversez celui-ci : un calculateur national contient souvent de grandes tables d'aliments ou de correspondance que l'outil ne lit pas."),

  # ---- AI translator: questions one at a time, decisions register (2026-10-22)
  ai_q_notice = list(en = "I will ask these %d questions one at a time. Type your answer below and press Send.",
                     fr = "Je vais poser ces %d questions une à la fois. Tapez votre réponse ci-dessous et appuyez sur Envoyer."),
  ai_stream_questions = list(en = "Preparing the questions: %d so far...",
                             fr = "Préparation des questions : %d jusqu'ici..."),
  ai_stream_reading = list(en = "Reading the file: %d values noted so far...",
                           fr = "Lecture du fichier : %d valeurs relevées jusqu'ici..."),
  ai_reply_cut = list(en = "The reply was cut off at the length limit. Asking the AI for the rest.",
                      fr = "La réponse a été coupée à la limite de longueur. Demande de la suite à l'IA."),
  ai_q_notice_one = list(en = "One question. Type your answer below and press Send.",
                         fr = "Une question. Tapez votre réponse ci-dessous et appuyez sur Envoyer."),
  ai_q_gate_notice = list(en = "Before I produce the template, %d quick question(s). Answer below; the template starts by itself after the last one.",
                          fr = "Avant de produire le modèle, %d question(s) rapide(s). Répondez ci-dessous ; le modèle démarre de lui-même après la dernière."),
  ai_q_bubble = list(en = "Question %d of %d: %s", fr = "Question %d sur %d : %s"),
  ai_q_choices = list(en = "Reply with one of: %s", fr = "Répondez par l'un de : %s"),
  ai_q_recorded = list(en = "Recorded: %s. Reply to correct any of these.",
                       fr = "Enregistré : %s. Répondez pour corriger l'un de ces points."),
  ai_q_sent = list(en = "(your answers were sent to the AI)", fr = "(vos réponses ont été envoyées à l'IA)"),
  ai_q_recorded_more = list(en = "and %d more", fr = "et %d de plus"),
  ai_q_nothing_open = list(en = "Nothing else is open. Press Produce template now when you are ready.",
                           fr = "Plus rien n'est en attente. Appuyez sur Produire le modèle quand vous êtes prêt."),
  ai_q_generic = list(en = "What should I use for %s?", fr = "Que dois-je utiliser pour %s ?"),
  ai_qa_title = list(en = "Question %d of %d", fr = "Question %d sur %d"),
  ai_qa_server_intro = list(en = "Before the template is produced, please confirm. ",
                            fr = "Avant de produire le modèle, merci de confirmer. "),
  ai_qa_answer_placeholder = list(en = "Your answer", fr = "Votre réponse"),
  ai_qa_back = list(en = "Back", fr = "Retour"),
  ai_qa_skip = list(en = "I do not know, use the IPCC default", fr = "Je ne sais pas, utiliser la valeur GIEC par défaut"),
  ai_qa_next = list(en = "Next", fr = "Suivant"),
  ai_qa_send = list(en = "Send all answers", fr = "Envoyer toutes les réponses"),
  ai_qa_confirm = list(en = "Confirm", fr = "Confirmer"),
  ai_qa_need_answer = list(en = "Please choose or type an answer.", fr = "Merci de choisir ou de saisir une réponse."),
  ai_qa_gate_notice = list(
    en = "A few points need your confirmation before the template is produced. Answer them above, one at a time; the template starts by itself after the last one.",
    fr = "Quelques points doivent être confirmés avant de produire le modèle. Répondez ci-dessus, un à la fois ; le modèle démarre de lui-même après le dernier."),
  ai_qa_answer_first = list(en = "Please answer the questions above first.", fr = "Merci de répondre d'abord aux questions ci-dessus."),
  ai_qa_bubble_only_questions = list(en = "Please answer the questions below, one at a time.",
                                     fr = "Merci de répondre aux questions ci-dessous, une à la fois."),
  ai_reg_title = list(en = "What the AI will apply", fr = "Ce que l'IA appliquera"),
  ai_reg_note = list(
    en = "Each line is a decision the template will follow. Edit a line if it is wrong: the AI is told to apply it over the file and the defaults.",
    fr = "Chaque ligne est une décision que le modèle suivra. Modifiez une ligne si elle est fausse : l'IA doit l'appliquer avant le fichier et les valeurs par défaut."),
  ai_reg_edit = list(en = "edit", fr = "modifier"),
  ai_reg_basis_user = list(en = "you said", fr = "vous avez dit"),
  ai_reg_basis_file = list(en = "from the file", fr = "du fichier"),
  ai_reg_basis_default = list(en = "IPCC default", fr = "défaut GIEC"),
  ai_reg_basis_assumed = list(en = "assumed", fr = "supposé"),
  ai_reg_basis_server = list(en = "detected", fr = "détecté"),
  ai_reg_status_pending = list(en = "not decided yet", fr = "pas encore décidé"),
  ai_reg_status_unclear = list(en = "unclear, will be asked", fr = "incertain, sera demandé"),
  ai_reg_applied = list(en = "applied", fr = "appliqué"),
  ai_reg_not_applied = list(en = "not applied", fr = "non appliqué"),
  ai_reg_modal_note = list(en = "Producing again after this change re-runs the AI for every production system.",
                           fr = "Produire à nouveau après ce changement relance l'IA pour chaque système de production."),
  ai_reg_save = list(en = "Save", fr = "Enregistrer"),
  btn_ai_download_checks = list(en = "Download the checks (Excel)", fr = "Télécharger les vérifications (Excel)"),
  btn_ai_download_conversation = list(en = "Download the conversation (Word)", fr = "Télécharger la conversation (Word)"),
  ai_outputs_note = list(
    en = "Three files: the data workbook (flagged cells are coloured, with a Check and a Why column at the right of each sheet, and filters on every column), the list of checks to review, and the questions and answers.",
    fr = "Trois fichiers : le classeur de données (cellules signalées en couleur, avec une colonne Check et une colonne Why à droite de chaque feuille, et des filtres sur chaque colonne), la liste des vérifications à relire, et les questions et réponses."),
  ai_job_running = list(en = "Producing the template", fr = "Production du modèle en cours"),
  ai_job_eta_under_min = list(en = "less than a minute left", fr = "moins d'une minute restante"),
  ai_job_eta_min = list(en = "about %d min left", fr = "environ %d min restantes"),
  ai_job_elapsed = list(en = "%d min %02d s elapsed", fr = "%d min %02d s écoulées"),
  ai_job_eta_over = list(en = "running longer than estimated", fr = "plus long que prévu"),
  ai_save_failed = list(en = "The files could not be saved to the folder (%s). Use the download buttons below instead.",
                        fr = "Les fichiers n'ont pas pu être enregistrés dans le dossier (%s). Utilisez plutôt les boutons de téléchargement ci-dessous."),
  ai_job_system = list(en = "System %d of %d: %s", fr = "Système %d sur %d : %s"),
  ai_job_leave_note = list(
    en = "You can leave this page. When the files are ready they are saved to your chosen folder or downloaded; if this page is closed, they are emailed to you.",
    fr = "Vous pouvez quitter cette page. Quand les fichiers sont prêts, ils sont enregistrés dans le dossier choisi ou téléchargés ; si la page est fermée, ils vous sont envoyés par courriel."),
  btn_ai_pick_dir = list(en = "Choose where to save", fr = "Choisir où enregistrer"),
  tip_ai_pick_dir = list(en = "Pick a folder now; the three files are written there when the run ends (Chrome and Edge).",
                         fr = "Choisissez un dossier maintenant ; les trois fichiers y seront écrits à la fin (Chrome et Edge)."),
  ai_delivery_default = list(
    en = "When ready, the data workbook downloads by itself and the other two files get a button. If this page is closed before then, the three files are emailed to you.",
    fr = "Quand ils sont prêts, le classeur de données se télécharge de lui-même et les deux autres fichiers ont un bouton. Si cette page est fermée avant, les trois fichiers vous sont envoyés par courriel."),
  ai_delivery_folder = list(en = "When ready, the three files are saved to the folder \"%s\". If this page is closed before then, they are emailed to you.",
                            fr = "Quand ils sont prêts, les trois fichiers sont enregistrés dans le dossier « %s ». Si cette page est fermée avant, ils vous sont envoyés par courriel."),
  ai_dir_chosen = list(en = "Results will be saved to \"%s\".", fr = "Les résultats seront enregistrés dans « %s »."),
  ai_dir_failed = list(en = "No folder was chosen. If Chrome said the folder contains system files, make a new sub-folder (for example Downloads > GHG tool outputs) and choose that one, or press Continue to download the files instead.",
                       fr = "Aucun dossier choisi. Si Chrome a dit que le dossier contient des fichiers système, créez un nouveau sous-dossier (par exemple Téléchargements > Sorties outil GES) et choisissez-le, ou appuyez sur Continuer pour télécharger les fichiers."),
  ai_saved_to_folder = list(en = "The three files were saved to \"%s\".", fr = "Les trois fichiers ont été enregistrés dans « %s »."),
  ai_dlv_title = list(en = "Where should the files go?", fr = "Où envoyer les fichiers ?"),
  ai_dlv_intro = list(
    en = "The template takes a few minutes for a small inventory and up to half an hour for a large one, one production system at a time. Three files come out: the data workbook, the list of checks to review, and the questions and answers. You can leave this page while it runs. When the files are ready:",
    fr = "Le modèle prend quelques minutes pour un petit inventaire et jusqu'à une demi-heure pour un grand, un système de production à la fois. Trois fichiers en sortent : le classeur de données, la liste des vérifications à relire, et les questions et réponses. Vous pouvez quitter cette page pendant le calcul. Quand les fichiers sont prêts :"),
  ai_dlv_opt_folder_h = list(en = "Saved to a folder you choose now.", fr = "Enregistrés dans un dossier que vous choisissez maintenant."),
  ai_dlv_opt_folder = list(en = "Click \"Choose a folder\" below (Chrome and Edge). The three files are written there by themselves, even if you are doing something else. Choose or make a plain sub-folder, for example Downloads > GHG tool outputs: the browser refuses the top of your user folder, the OneDrive root and the system folders (\"contains system files\").",
                           fr = "Cliquez sur « Choisir un dossier » ci-dessous (Chrome et Edge). Les trois fichiers y seront écrits d'eux-mêmes, même si vous faites autre chose. Choisissez ou créez un simple sous-dossier, par exemple Téléchargements > Sorties outil GES : le navigateur refuse la racine de votre dossier utilisateur, la racine OneDrive et les dossiers système (« contient des fichiers système »)."),
  ai_dlv_opt_download_h = list(en = "Or downloaded.", fr = "Ou téléchargés."),
  ai_dlv_opt_download = list(en = "Click \"Continue\": the data workbook downloads by itself to your browser's download folder, and the other two files get a button.",
                             fr = "Cliquez sur « Continuer » : le classeur de données se télécharge de lui-même dans le dossier de téléchargement du navigateur, et les deux autres fichiers ont un bouton."),
  ai_dlv_opt_email_h = list(en = "Or emailed.", fr = "Ou envoyés par courriel."),
  ai_dlv_opt_email = list(en = "If this page is closed before the end, the three files are sent to %s.",
                          fr = "Si cette page est fermée avant la fin, les trois fichiers sont envoyés à %s."),
  ai_dlv_note = list(en = "You are asked this once per session.", fr = "Cette question est posée une fois par session."),
  ai_dlv_no_picker = list(en = "Your browser cannot save to a chosen folder; the files will download instead.",
                          fr = "Votre navigateur ne peut pas enregistrer dans un dossier choisi ; les fichiers seront téléchargés."),
  ai_dlv_btn_pick = list(en = "Choose a folder and start", fr = "Choisir un dossier et démarrer"),
  ai_dlv_btn_continue = list(en = "Continue (download when ready)", fr = "Continuer (téléchargement à la fin)"),
  ai_decisions_not_applied = list(en = "Decisions the AI did not apply (check these rows in the file):",
                                  fr = "Décisions que l'IA n'a pas appliquées (vérifiez ces lignes dans le fichier) :"),
  ai_reg_cancel = list(en = "Cancel", fr = "Annuler"),
  ai_topic_species = list(en = "Species", fr = "Espèce"),
  ai_topic_ipcc_edition = list(en = "IPCC edition", fr = "Édition GIEC"),
  ai_topic_inventory_year = list(en = "Inventory year", fr = "Année d'inventaire"),
  ai_topic_aggregation_level = list(en = "Production systems kept", fr = "Systèmes de production retenus"),
  ai_topic_mms_split_source = list(en = "Manure system shares", fr = "Parts des systèmes de gestion du fumier"),
  ai_topic_calves_handling = list(en = "Calves", fr = "Veaux"),
  ai_topic_uncertainty_source = list(en = "Uncertainty ranges", fr = "Plages d'incertitude"),
  ai_topic_pct_vs_fraction = list(en = "Percent or fraction", fr = "Pourcentage ou fraction"),
  ai_topic_category = list(en = "Category", fr = "Catégorie"),
  ai_q_species = list(en = "Which cattle does this inventory cover?", fr = "Quels bovins cet inventaire couvre-t-il ?"),
  ai_q_ipcc_edition = list(en = "Which IPCC edition should the template follow?", fr = "Quelle édition du GIEC le modèle doit-il suivre ?"),
  ai_q_inventory_year = list(en = "Which year is the inventory for? This is the single year the Parameters sheet describes.",
                             fr = "Pour quelle année est l'inventaire ? C'est l'année unique décrite par la feuille Parameters."),
  ai_q_aggregation_level = list(en = "Which production systems should the template keep? List them, or write 'all'.",
                                fr = "Quels systèmes de production le modèle doit-il garder ? Listez-les, ou écrivez « tous »."),
  ai_q_mms_split_source = list(en = "Where do the manure management shares come from?",
                               fr = "D'où viennent les parts des systèmes de gestion du fumier ?"),
  ai_q_calves_handling = list(
    en = "How should calves be handled? One source category becomes one template category; a male and female split is used only if your file has it.",
    fr = "Comment traiter les veaux ? Une catégorie source devient une catégorie du modèle ; une séparation mâles et femelles n'est utilisée que si votre fichier la contient."),
  ai_q_uncertainty_source = list(en = "Where do the uncertainty ranges come from?", fr = "D'où viennent les plages d'incertitude ?"),
  ai_q_pct_vs_fraction = list(
    en = "In the column %s, the header says one thing and the values suggest another. Are the values percentages (6 = 6%%) or fractions (0.06 = 6%%)?",
    fr = "Dans la colonne %s, l'en-tête dit une chose et les valeurs en suggèrent une autre. Les valeurs sont-elles des pourcentages (6 = 6 %%) ou des fractions (0,06 = 6 %%) ?"),
  ai_q_category = list(
    en = "The source category '%s' is ambiguous. Which template category should it become, or should it be merged, and with which?",
    fr = "La catégorie source « %s » est ambiguë. Quelle catégorie du modèle doit-elle devenir, ou faut-il la fusionner, et avec laquelle ?"),
  ai_q_choice_cattle_dairy = list(en = "Dairy cattle only", fr = "Bovins laitiers uniquement"),
  ai_q_choice_cattle_non_dairy = list(en = "Non-dairy cattle only (beef and other)", fr = "Bovins non laitiers uniquement (viande et autres)"),
  ai_q_choice_cattle_mixed = list(en = "Both dairy and non-dairy", fr = "Laitiers et non laitiers"),
  ai_q_choice_2006 = list(en = "IPCC 2006 Guidelines", fr = "Lignes directrices GIEC 2006"),
  ai_q_choice_2019_refinement = list(en = "2019 Refinement", fr = "Affinement 2019"),
  ai_q_choice_herd_wide_from_file = list(en = "One split for the whole herd, from the file", fr = "Une répartition pour tout le cheptel, issue du fichier"),
  ai_q_choice_per_subcategory_from_file = list(en = "A split per sub-category, from the file", fr = "Une répartition par sous-catégorie, issue du fichier"),
  ai_q_choice_ipcc_default_split = list(en = "The IPCC default split", fr = "La répartition GIEC par défaut"),
  ai_q_choice_pooled = list(en = "Keep calves as one category per system, as in the file", fr = "Garder les veaux en une seule catégorie par système, comme dans le fichier"),
  ai_q_choice_split_as_in_file = list(en = "Male and female calves, because the file has both", fr = "Veaux mâles et femelles, car le fichier contient les deux"),
  ai_q_choice_file_bounds = list(en = "From the file (lower and upper bounds, or plus or minus %)", fr = "Du fichier (bornes basse et haute, ou plus ou moins %)"),
  ai_q_choice_catalogue_ranges = list(en = "From the IPCC catalogue ranges", fr = "Des plages du catalogue GIEC"),
  ai_q_choice_mixed = list(en = "From the file where given, IPCC ranges elsewhere", fr = "Du fichier quand il les donne, plages GIEC ailleurs"),
  ai_q_choice_percent = list(en = "Percentages (6 means 6%)", fr = "Pourcentages (6 signifie 6 %)"),
  ai_q_choice_fraction = list(en = "Fractions (0.06 means 6%)", fr = "Fractions (0,06 signifie 6 %)"),

  ai_hold_title = list(
    en = "Please hold until the review workshop, 14 to 16 October",
    fr = "Merci d'attendre l'atelier de revue, du 14 au 16 octobre"),
  ai_hold_body = list(
    en = "Each translation is charged to the project, and the budget is reserved for the review workshop sessions. Please do not run translations before then unless it has been agreed with the project team. The rest of the tool is unaffected and can be used normally.",
    fr = "Chaque traduction est facturée au projet, et le budget est réservé aux sessions de l'atelier de revue. Merci de ne pas lancer de traduction avant cette date, sauf accord préalable avec l'équipe projet. Le reste de l'outil n'est pas concerné et peut être utilisé normalement."),

  btn_open_ai_guide = list(en = "Open AI translator guide (PDF)",
                             fr = "Ouvrir le guide du traducteur IA (PDF)"),

  ai_fr_chat_note = list(
    en = "",
    fr = "Note : l'IA répond en anglais et utilise les codes IPCC standards. Vous pouvez lui écrire en français, elle comprend, mais répond en anglais."
  ),

  ai_signed_in = list(en = "Signed in:", fr = "Connecté :"),
  ai_past_label = list(en = "Upload a past translation", fr = "Téléverser une traduction précédente"),
  ai_past_hint = list(en = " (a template produced by this tool that you corrected). It is read next to your source file; say in the box what you changed. The AI takes the corrected values as the truth and produces the template again from them.",
                      fr = " (un modèle produit par cet outil que vous avez corrigé). Il est lu à côté de votre fichier source ; dites dans la case ce que vous avez changé. L'IA prend les valeurs corrigées pour vraies et reproduit le modèle à partir d'elles."),
  ai_revise_notice = list(en = "Type your change below, or upload a corrected template with the button above the reply box, then click Produce template now again.",
                          fr = "Tapez votre modification ci-dessous, ou téléversez un modèle corrigé avec le bouton au-dessus de la zone de réponse, puis cliquez de nouveau sur Produire le modèle."),
  ai_past_not_template = list(en = "This file is not a template produced by the tool (no Parameters and Inventory_Metadata sheets). Upload it in the raw data box instead.",
                              fr = "Ce fichier n'est pas un modèle produit par l'outil (pas de feuilles Parameters et Inventory_Metadata). Téléversez-le plutôt dans la case des données brutes."),
  ai_past_needs_source = list(en = "Upload your raw data first; a past translation is read next to it.",
                              fr = "Téléversez d'abord vos données brutes ; une traduction précédente est lue à côté d'elles."),
  ai_upload_label = list(en = "1.  Upload your raw cattle data",
                           fr = "1.  Téléverser vos données brutes"),
  ai_upload_hint = list(
    en = " (.xlsx or .csv): the AI reads it and starts the conversation.",
    fr = " (.xlsx ou .csv) : l'IA le lit et entame la conversation."
  ),
  ai_reply_label = list(en = "2.  Your reply to the AI",
                          fr = "2.  Votre réponse à l'IA"),
  ai_reply_placeholder = list(en = "Answer the AI's questions, or ask your own…",
                                fr = "Répondez aux questions de l'IA, ou posez les vôtres…"),
  btn_ai_send = list(en = "Send", fr = "Envoyer"),
  btn_ai_produce = list(en = " Produce template now", fr = " Générer le modèle"),
  tip_ai_produce = list(
    en = "Emit the JSON template from your section B + C exploration. Use this when you've finished answering the AI's section D clarifications.",
    fr = "Générer le modèle JSON à partir de votre exploration section B + C. Utilisez-le après avoir répondu aux clarifications section D de l'IA."
  ),
  btn_ai_reset = list(en = " Reset conversation", fr = " Réinitialiser"),
  tip_ai_reset = list(en = "Clear the chat and start over from scratch.",
                        fr = "Effacer la conversation et recommencer."),
  btn_ai_stop = list(en = " Stop / reload", fr = " Arrêter / recharger"),
  ai_stop_confirm = list(
    en = "Stop the AI now? The current call is cancelled and the page reloads. Your conversation is saved: you will not lose it.",
    fr = "Arrêter l'IA maintenant ? L'appel en cours est annulé et la page se recharge. Votre conversation est sauvegardée : vous ne la perdrez pas."
  ),
  ai_stopping = list(en = "Stopping...", fr = "Arrêt en cours..."),
  tip_ai_stop = list(
    en = "Stops the call that is running. The connection to the AI is closed within a second or two, so nothing further is generated or billed, and the page then reloads to give you a clean screen. Your conversation history is preserved.",
    fr = "Arrête l'appel en cours. La connexion à l'IA est fermée en une ou deux secondes, donc plus rien n'est généré ni facturé, puis la page se recharge pour repartir sur un écran propre. Votre historique est préservé."
  ),
  btn_ai_download = list(en = "Download template (.xlsx)",
                           fr = "Télécharger le modèle (.xlsx)"),
  # 2026-09-18: the "template ready" state hides every other control.
  # Pre-download quality preview (2026-09-18)
  ai_precheck_title = list(en = "Quality preview of this template.", fr = "Aperçu qualité de ce modèle."),
  ai_precheck_rows = list(en = "%d parameter rows, %d manure rows.", fr = "%d lignes de paramètres, %d lignes de fumier."),
  ai_precheck_error = list(en = "The preview could not run: %s. You can still download and check on the QA/QC tab.",
                           fr = "L'aperçu n'a pas pu s'exécuter : %s. Vous pouvez tout de même télécharger et vérifier dans l'onglet QA/QC."),
  ai_precheck_issues_badge = list(en = "consistency notes", fr = "notes de cohérence"),
  ai_precheck_clean = list(en = "No failures and no consistency notes. The QA/QC tab will show the same result after upload.",
                           fr = "Aucun échec et aucune note de cohérence. L'onglet QA/QC affichera le même résultat après téléversement."),
  ai_precheck_fail_title = list(en = "Checks that will fail after upload.", fr = "Contrôles qui échoueront après téléversement."),
  ai_precheck_fail_hint = list(en = "Fix the value in your source file and ask the AI to revise, or upload and tick Ignore next to each one on the QA/QC tab.",
                               fr = "Corrigez la valeur dans votre fichier source et demandez une révision à l'IA, ou téléversez et cochez Ignorer à côté de chacun dans l'onglet QA/QC."),
  ai_precheck_issues_title = list(en = "Consistency notes to check against your file.", fr = "Notes de cohérence à vérifier dans votre fichier."),
  ai_precheck_issues_hint = list(en = "These compare rows with each other. Each one is a place where the AI may have copied or invented a value.",
                                 fr = "Ces notes comparent les lignes entre elles. Chacune signale un endroit où l'IA a pu copier ou inventer une valeur."),
  ai_precheck_more = list(en = "and %d more", fr = "et %d de plus"),
  ai_precheck_run = list(en = "Run the quality preview (about one minute).",
                         fr = "Lancer l'aperçu qualité (environ une minute)."),
  ai_precheck_building = list(en = "Building the workbook and running the checks...",
                              fr = "Construction du classeur et exécution des contrôles..."),
  ai_ready_title = list(
    en = "Your template is ready. Click the green button to save it, then open it and check the AI's work before uploading it on the 1. Data Input tab.",
    fr = "Votre modèle est prêt. Cliquez sur le bouton vert pour l'enregistrer, puis ouvrez-le et vérifiez le travail de l'IA avant de le charger dans l'onglet 1. Saisie des données."),
  btn_ai_revise = list(en = "Back to the conversation (your answers are kept)",
                         fr = "Retour à la conversation (vos réponses sont conservées)"),
  ai_upload_note_label = list(en = "Anything the AI should know about this file? (optional)",
                              fr = "Quelque chose que l'IA doit savoir sur ce fichier ? (facultatif)"),
  ai_upload_note_placeholder = list(en = "For example: the MoE column is a fraction; calves are one group; the inventory year is 2022.",
                                    fr = "Par exemple : la colonne MoE est une fraction ; les veaux forment un seul groupe ; l'année d'inventaire est 2022."),
  ai_upload_corrected = list(
    en = "This file looks like a template produced by the tool. The checks were run on it: %d failures, %d warnings, %d notes. Add your comments below and send it as the corrected version; its values will then be used as they are.",
    fr = "Ce fichier ressemble à un modèle produit par l'outil. Les vérifications ont été faites : %d échecs, %d avertissements, %d notes. Ajoutez vos commentaires ci-dessous et envoyez-le comme version corrigée ; ses valeurs seront alors utilisées telles quelles."),
  btn_ai_send_corrected = list(en = "Send the corrected template to the AI", fr = "Envoyer le modèle corrigé à l'IA"),
  btn_ai_new = list(en = "Start a new translation",
                      fr = "Commencer une nouvelle traduction"),
  ai_spinner_default = list(
    en = "Translator is working: calling the AI, waiting for the first reply…",
    fr = "Le traducteur travaille : appel de l'IA, attente de la première réponse…"
  ),
  ai_empty_messages = list(en = "No messages yet. Upload a file or send a message to begin.",
                             fr = "Aucun message pour le moment. Téléversez un fichier ou envoyez un message pour commencer."),

  # Magic-link sign-in (Resources tab: AI translator)
  auth_signin_title = list(en = "Sign in to the AI translator",
                            fr = "Se connecter au traducteur IA"),
  auth_signin_body = list(
    en = "Enter your email address. We will send you a one-time sign-in link. No password required. Every address is reviewed by the administrator before it is approved, usually the same working day. You only need approval once.",
    fr = "Entrez votre adresse e-mail. Nous vous enverrons un lien de connexion à usage unique. Pas de mot de passe. Chaque adresse est examinée par l'administrateur avant approbation, en général le jour ouvré même. L'approbation n'est nécessaire qu'une seule fois."
  ),
  btn_auth_send_link = list(en = "Send sign-in link",
                              fr = "Envoyer le lien de connexion"),

  # Feedback widget (floating button + modal: every page, incl. pre-login)
  fb_button = list(en = "Feedback", fr = "Commentaires"),
  fb_title = list(en = "Send feedback", fr = "Envoyer un commentaire"),
  fb_category = list(en = "Type", fr = "Type"),
  fb_cat_bug = list(en = "Bug", fr = "Anomalie"),
  fb_cat_idea = list(en = "Idea", fr = "Idée"),
  fb_cat_question = list(en = "Question", fr = "Question"),
  fb_text_label = list(en = "Your feedback",
                        fr = "Votre commentaire"),
  fb_text_placeholder = list(
    en = "What happened, what you expected, or an idea to improve the tool…",
    fr = "Ce qui s'est passé, ce que vous attendiez, ou une idée d'amélioration…"),
  fb_email_label = list(en = "Your email", fr = "Votre e-mail"),
  fb_email_label_anon = list(en = "Your email (so we can follow up)",
                              fr = "Votre e-mail (pour le suivi)"),
  fb_file_label = list(en = "Attach a screenshot or file (optional)",
                        fr = "Joindre une capture d'écran ou un fichier (facultatif)"),
  fb_file_hint = list(
    en = "Max 8 MB. Images appear in the report; other files are linked.",
    fr = "Max 8 Mo. Les images apparaissent dans le rapport ; les autres fichiers sont liés."),
  fb_cancel = list(en = "Cancel", fr = "Annuler"),
  fb_send = list(en = "Send", fr = "Envoyer"),
  fb_empty_text = list(en = "Please enter some feedback text.",
                        fr = "Veuillez saisir un commentaire."),

  # =====================================================================
  # DATA INPUT TAB
  # =====================================================================

  card_analysis_mode = list(en = "Choose your analysis mode",
                              fr = "Choisir votre mode d'analyse"),
  analysis_mode_single = list(
    en = "Single year: quantify uncertainty in one inventory year",
    fr = "Année unique : quantifier l'incertitude d'une année d'inventaire"
  ),
  tip_analysis_mode_single = list(
    en = "One inventory year. Gives the uncertainty of that year's emissions, as IPCC Table 3.3 asks.",
    fr = "Une année d'inventaire. Donne l'incertitude des émissions de cette année, comme le demande le Tableau 3.3 du GIEC."
  ),
  analysis_mode_trend = list(
    en = "Trend: compare uncertainty across multiple years",
    fr = "Tendance : comparer l'incertitude entre plusieurs années"
  ),
  tip_analysis_mode_trend = list(
    en = "Several years. Gives the uncertainty of each year and of the change between the base year and the year you report (IPCC Vol. 1, Ch. 3, §3.7). Needs a Parameter_TimeSeries sheet, or an example dataset.",
    fr = "Plusieurs années. Donne l'incertitude de chaque année et du changement entre l'année de base et l'année déclarée (GIEC Vol. 1, Ch. 3, §3.7). Nécessite une feuille Parameter_TimeSeries, ou un jeu d'exemple."
  ),
  analysis_mode_warning = list(
    en = "Selection required: pick Single year or Trend before moving on. The Run button on Tab 4 will block until a mode is chosen.",
    fr = "Sélection requise : choisissez Année unique ou Tendance avant de continuer. Le bouton Lancer de l'onglet 4 sera bloqué tant qu'un mode n'est pas choisi."
  ),
  trend_base_year = list(en = "base year", fr = "année de base"),

  info_data_input = list(
    en = "Pick an example country, or upload your own filled Excel template. The table on the right shows what was loaded. To change a value, edit the Excel file and upload it again.",
    fr = "Choisissez un pays d'exemple, ou téléversez votre modèle Excel rempli. La table à droite montre ce qui a été chargé. Pour changer une valeur, modifiez le fichier Excel et téléversez-le de nouveau."
  ),
  info_data_input_ai_pre = list(
    en = "To put your data in the right format, use the ",
    fr = "Pour mettre vos données au bon format, utilisez le "
  ),
  info_data_input_ai_link = list(
    en = "AI translator",
    fr = "traducteur IA"
  ),
  info_data_input_ai_post = list(
    en = ". Otherwise download the Excel template on the left, fill it in and upload it.",
    fr = ". Sinon, téléchargez le modèle Excel à gauche, remplissez-le et téléversez-le."
  ),
  what_to_do_label = list(en = "What to do:", fr = "Marche à suivre :"),
  needs_run_msg = list(
    en = "No results yet. Run the Monte Carlo simulation on the 'Simulate and results' tab first.",
    fr = "Pas encore de résultats. Lancez d'abord la simulation Monte Carlo dans l'onglet « Simulation et résultats »."
  ),

  data_source_h = list(en = "Data Source", fr = "Source des données"),
  country_label = list(en = "Country / Example Data", fr = "Pays / données d'exemple"),
  country_placeholder = list(en = "Select your dataset", fr = "Choisissez votre jeu de données"),
  country_x_label = list(en = "Country X (hypothetical dairy)",
                          fr = "Pays X (laitier hypothétique)"),
  country_y_label = list(en = "Country Y (hypothetical pastoral)",
                          fr = "Pays Y (pastoral hypothétique)"),
  country_custom_label = list(en = "Custom Upload", fr = "Téléversement personnalisé"),
  custom_hint = list(
    en = " Custom mode selected. Pick an IPCC version, download the matching template, fill it in, then upload below.",
    fr = " Mode personnalisé sélectionné. Choisissez une version IPCC, téléchargez le modèle correspondant, remplissez-le, puis téléversez-le ci-dessous."
  ),

  data_h_pick_ipcc = list(en = "1. Pick an IPCC Guidelines version",
                            fr = "1. Choisir une version des lignes directrices IPCC"),
  ipcc_2006 = list(en = "IPCC 2006", fr = "IPCC 2006"),
  ipcc_2019 = list(en = "IPCC 2019 Refinement", fr = "Raffinement IPCC 2019"),
  ipcc_version_note = list(
    en = "The MMS dropdown in the downloaded template will be filtered to manure systems valid for the version you pick here.",
    fr = "Le menu MMS dans le modèle téléchargé sera filtré pour ne montrer que les systèmes de gestion du fumier valides pour la version choisie ici."
  ),
  data_h_download_template = list(en = "2. Download a template",
                                    fr = "2. Télécharger un modèle"),
  ipcc_pick_first_unlock = list(
    en = " Pick an IPCC version above first: then these buttons unlock.",
    fr = " Choisissez d'abord une version IPCC ci-dessus : les boutons se débloqueront."
  ),
  ai_inline_promo_title = list(en = " Don't have the template filled yet?",
                                  fr = " Vous n'avez pas encore rempli le modèle ?"),
  ai_inline_promo_body_pre = list(en = "Use the AI Translator on the ",
                                    fr = "Utilisez le traducteur IA sur la "),
  ai_inline_promo_body_link = list(en = "AI Translator card on the Resources tab",
                                     fr = "carte Traducteur IA de l'onglet Ressources"),
  ai_inline_promo_body_post = list(en = ": upload your raw data file and the AI produces a ready-to-upload .xlsx.",
                                     fr = " : téléversez votre fichier brut et l'IA produit un .xlsx prêt à l'emploi."),
  data_h_upload = list(en = "3. Upload your filled template",
                         fr = "3. Téléverser votre modèle rempli"),
  pick_ipcc_to_enable = list(
    en = " Pick an IPCC version above first to enable upload.",
    fr = " Choisissez d'abord une version IPCC ci-dessus pour activer le téléversement."
  ),
  validation_h = list(en = "Validation", fr = "Validation"),
  param_data_h = list(en = "Parameter Data", fr = "Données des paramètres"),

  # =====================================================================
  # QA/QC TAB
  # =====================================================================

  info_qaqc = list(
    en = "Read the checks on your data. Click a status tile to filter the table. Fix every Fail in your Excel file and upload it again. Warn means check the value; Missing means an IPCC default was used.",
    fr = "Lisez les vérifications de vos données. Cliquez sur une vignette de statut pour filtrer le tableau. Corrigez chaque Échec dans votre fichier Excel et téléversez-le de nouveau. Attention signifie vérifier la valeur ; Manquant signifie qu'une valeur GIEC par défaut a été utilisée."
  ),
  qa_status_missing = list(en = "Missing", fr = "Manquant"),
  qa_status_fail = list(en = "Fail", fr = "Échec"),
  qa_status_warn = list(en = "Warn", fr = "Attention"),
  qa_status_info = list(en = "Info", fr = "Info"),
  qa_status_pass = list(en = "Pass", fr = "OK"),
  qa_fix_fails = list(en = "Fix any ", fr = "Corrigez tous les "),
  qa_before_sim = list(en = " before running the simulation. ",
                         fr = " avant de lancer la simulation. "),
  # QA ignore / repair (2026-09-18)
  qa_tile_all = list(en = "All checks", fr = "Toutes"),
  qa_table_hint = list(
    en = "Click a status to keep only the parameters concerned. One row per parameter: open it to read each finding with its message.",
    fr = "Cliquez sur un statut pour ne garder que les paramètres concernés. Une ligne par paramètre : ouvrez-la pour lire chaque constat avec son message."),
  qa_expand_all = list(en = "Open all", fr = "Tout ouvrir"),
  qa_collapse_all = list(en = "Close all", fr = "Tout fermer"),
  qa_par_sheet = list(en = "Sub-category keys (manure sheet)", fr = "Clés de sous-catégorie (feuille fumier)"),
  qa_none_for_status = list(en = "No finding with this status.", fr = "Aucun constat avec ce statut."),
  qa_col_ignore = list(en = "Ignore", fr = "Ignorer"),
  qa_ignore_label = list(en = "Ignore", fr = "Ignorer"),
  qa_not_ignorable = list(en = "Cannot be ignored", fr = "Ne peut pas être ignoré"),
  qa_repaired_tag = list(en = "Repaired", fr = "Réparé"),
  qa_ignore_modal_title = list(en = "Ignore this QA/QC check?", fr = "Ignorer ce contrôle QA/QC ?"),
  qa_ignore_modal_body = list(
    en = "Running with ignored checks may produce unreliable results. Where a failure would crash the simulation (bounds that do not bracket the mean, or a beta or lognormal distribution outside its valid range) the tool applies the smallest repair instead and records it. Every ignored or repaired check is shown on the results page and listed in the Excel, CSV and Word exports.",
    fr = "Lancer la simulation avec des contrôles ignorés peut donner des résultats peu fiables. Lorsqu'un échec ferait planter la simulation (bornes qui n'encadrent pas la moyenne, ou distribution bêta ou log-normale hors de son domaine), l'outil applique la plus petite réparation possible et l'enregistre. Chaque contrôle ignoré ou réparé est affiché sur la page des résultats et listé dans les exports Excel, CSV et Word."),
  qa_ignore_confirm = list(en = "Ignore and continue", fr = "Ignorer et continuer"),
  qa_ignore_cancel = list(en = "Cancel", fr = "Annuler"),
  qa_gate_blocked = list(
    en = "Cannot run: %d QA/QC failure(s) remain. Correct the values in your Excel file and upload it again.",
    fr = "Impossible de lancer : %d échec(s) QA/QC subsistent. Corrigez les valeurs dans votre fichier Excel et téléversez-le de nouveau."),
  qa_banner = list(en = "%d QA/QC check(s) ignored or repaired.", fr = "%d contrôle(s) QA/QC ignoré(s) ou réparé(s)."),
  qa_banner_detail = list(
    en = "Results may be unreliable. This list is included in every export.",
    fr = "Les résultats peuvent être peu fiables. Cette liste figure dans chaque export."),
  qa_repaired_notice = list(en = "Input repaired so the simulation can run:",
                            fr = "Entrée réparée pour permettre la simulation :"),
  qa_autofilled_panel_label = list(en = "Auto-filled parameters",
                                      fr = "Paramètres remplis automatiquement"),
  qa_checks_run_label = list(en = "What is checked", fr = "Ce qui est vérifié"),
  qa_checks_run = list(
    en = "On every row: bounds enclose the mean and give a spread; lower bound not negative; percentage or fraction unit (DE, Ym, Fat, CP, MilkPR in %; pct_pregnant, ASH, UE, Frac_* as fractions); usual range with its IPCC source; distribution usable as the sampler reads it (beta, lognormal, tnorm_0_1); fractions under an unbounded distribution; body weight against the IPCC Annex 10A weight of the animal class (above 50% = warn); symmetric bounds where IPCC gives a skewed range (EF3_PRP, Frac_LEACH_PRP, info); Parameters sub-categories against the Manure_Management sheet.",
    fr = "Sur chaque ligne : les bornes encadrent la moyenne et donnent une dispersion ; borne inférieure non négative ; unité pourcentage ou fraction (DE, Ym, Fat, CP, MilkPR en % ; pct_pregnant, ASH, UE, Frac_* en fractions) ; plage usuelle avec sa source IPCC ; distribution utilisable telle que lue par l'échantillonneur (beta, lognormal, tnorm_0_1) ; fractions sous une distribution non bornée ; poids vif contre le poids IPCC Annexe 10A de la classe animale (au-delà de 50 % = attention) ; bornes symétriques là où l'IPCC donne une plage asymétrique (EF3_PRP, Frac_LEACH_PRP, info) ; sous-catégories Parameters contre la feuille Manure_Management."
  ),
  qa_results_h = list(en = "QA/QC Results", fr = "Résultats QA/QC"),

  # =====================================================================
  # DISTRIBUTION NOTES (Data Input tab; the Uncertainty tab was removed
  # on 2026-10-28 after the Nairobi review)
  # =====================================================================


  # =====================================================================
  # CORRELATIONS TAB
  # =====================================================================

  info_corr_about_label = list(en = "What is this page about?", fr = "De quoi parle cette page ?"),
  info_corr_about_body = list(
    en = "Some inputs move together. Telling the tool which ones gives a more realistic uncertainty range. With no evidence, keep 'No correlations'.",
    fr = "Certaines entrées varient ensemble. Indiquer lesquelles à l'outil donne une plage d'incertitude plus réaliste. Sans preuve, gardez « Pas de corrélations »."
  ),

  # The second idea, kept out of the "which option do I pick?" list below
  # because that list is about choosing an activity-data mode, whereas this
  # is a separate switch with a different and usually larger effect.
  info_corr_shared_label = list(
    en = "The other kind: one estimate used in several groups",
    fr = "L'autre type : une seule estimation utilisée dans plusieurs groupes"),
  info_corr_shared_body = list(
    en = "One IPCC default or one regional value used in many groups is a single estimate. If it is wrong, every group is wrong together. 'Inputs shared between groups' accounts for this. The uncertainty goes up when it is on; that is expected.",
    fr = "Une valeur GIEC par défaut ou une valeur régionale utilisée dans plusieurs groupes reste une seule estimation. Si elle est fausse, tous les groupes sont faux ensemble. « Entrées partagées entre groupes » en tient compte. L'incertitude augmente quand l'option est active ; c'est attendu."
  ),
  info_corr_quickguide = list(en = "Quick guide: which option do I pick?",
                                fr = "Guide rapide : quelle option choisir ?"),
  info_corr_q1 = list(
    en = "Five or more years in your Parameter_TimeSeries sheet: ",
    fr = "Cinq années ou plus dans votre feuille Parameter_TimeSeries : "
  ),
  info_corr_q1_ans = list(
    en = "From template",
    fr = "Depuis le modèle"
  ),
  info_corr_q2 = list(
    en = "No time series, but you want the known biological links (weight, milk, digestibility): ",
    fr = "Pas de série temporelle, mais vous voulez les liens biologiques connus (poids, lait, digestibilité) : "
  ),
  info_corr_q2_ans = list(
    en = "Structural defaults",
    fr = "Valeurs structurelles par défaut"
  ),
  info_corr_q3 = list(
    en = "Your own matrix from a study: ",
    fr = "Votre propre matrice issue d'une étude : "
  ),
  info_corr_q3_ans = list(
    en = "Manual entry",
    fr = "Saisie manuelle"
  ),
  info_corr_q4 = list(
    en = "None of these: ",
    fr = "Aucun de ces cas : "
  ),
  info_corr_no = list(en = "No correlations",
                        fr = "Pas de corrélations"),
  info_corr_q4_post = list(
    en = ".",
    fr = "."
  ),

  card_ad_corr_h = list(en = "Activity Data Correlations",
                          fr = "Corrélations des données d'activité"),
  ai_find_out_more_long = list(en = "Find out more", fr = "En savoir plus"),
  info_ad_corr = list(
    en = "If your file has a ",
    fr = "Si votre fichier contient une feuille "
  ),
  info_ad_corr_post = list(
    en = " sheet, the tool can read the correlations from it. Otherwise pick a preset or skip.",
    fr = ", l'outil peut y lire les corrélations. Sinon, choisissez une option prédéfinie ou passez."
  ),
  info_struct_defaults_label = list(en = "Structural defaults (literature-based):",
                                       fr = "Valeurs structurelles par défaut (fondées sur la littérature) :"),
  info_struct_defaults_body = list(
    en = "seven pairs taken from the livestock literature (weight, milk, digestibility, methane conversion). They are not IPCC-published values. All other pairs are zero. Hover a cell for its source.",
    fr = "sept paires tirées de la littérature sur l'élevage (poids, lait, digestibilité, conversion en méthane). Ce ne sont pas des valeurs publiées par le GIEC. Toutes les autres paires sont à zéro. Survolez une cellule pour voir sa source."
  ),
  info_manual_label = list(en = "Advanced: manual matrix entry.",
                              fr = "Avancé : saisie manuelle de la matrice."),
  info_manual_body = list(
    en = "Download a template below, edit it in Excel, save as CSV, upload. Values between -1 and 1, diagonal 1. A parameter missing from the file is treated as independent.",
    fr = "Téléchargez un modèle ci-dessous, modifiez-le dans Excel, enregistrez en CSV, téléversez. Valeurs entre -1 et 1, diagonale à 1. Un paramètre absent du fichier est traité comme indépendant."
  ),

  # =====================================================================
  # SIMULATE TAB
  # =====================================================================

  info_simulate = list(
    en = "Set the options on the left and click 'Run Monte Carlo simulation'. The results open on this tab when the run finishes. Use 'Back to settings' to change something and run again. Tabs 5 and 6 go deeper.",
    fr = "Réglez les options à gauche et cliquez sur « Lancer la simulation Monte Carlo ». Les résultats s'ouvrent sur cet onglet à la fin du calcul. Utilisez « Retour aux réglages » pour changer quelque chose et relancer. Les onglets 5 et 6 vont plus loin."
  ),
  info_simulate_repro_label = list(en = "If you get disconnected:", fr = "En cas de déconnexion :"),
  info_simulate_repro_body = list(
    en = "with the same file, settings and seed, the results are identical. If the session drops, upload the file again and run with the same seed.",
    fr = "avec le même fichier, les mêmes réglages et la même graine, les résultats sont identiques. Si la session se coupe, téléversez le fichier de nouveau et relancez avec la même graine."
  ),
  info_simulate_n_label = list(en = "How many iterations to use:",
                                  fr = "Combien d'itérations utiliser :"),
  info_simulate_n_body = list(
    en = "1,000 for a quick test. 10,000 or more for any result you use. To check convergence, run again with another seed: if the 95% margin changes by more than 2 points, increase the number.",
    fr = "1 000 pour un test rapide. 10 000 ou plus pour tout résultat que vous utilisez. Pour vérifier la convergence, relancez avec une autre graine : si la marge à 95 % change de plus de 2 points, augmentez le nombre."
  ),
  card_sim_settings = list(en = "Simulation Settings", fr = "Paramètres de simulation"),
  sim_n_iter_label = list(en = "Number of Iterations", fr = "Nombre d'itérations"),
  sim_seed_label = list(en = "Random Seed (for reproducibility)",
                          fr = "Graine aléatoire (pour la reproductibilité)"),
  tip_sim_seed = list(
    en = "Fixing the seed makes results exactly reproducible: anyone using the same data, settings, and seed will get the same numbers. To check convergence, re-run with a different seed (e.g. 123 or 456): if the 95% MoE changes by more than ~2 percentage points, increase the number of iterations.",
    fr = "Fixer la graine rend les résultats exactement reproductibles : toute personne utilisant les mêmes données, paramètres et graine obtiendra les mêmes chiffres. Pour vérifier la convergence, relancez avec une autre graine (par exemple 123 ou 456) : si la marge d'erreur 95 % change de plus de ~2 points, augmentez le nombre d'itérations."
  ),
  sim_gwp_label = list(en = "GWP Assessment Report",
                         fr = "Rapport d'évaluation GWP"),
  tip_sim_gwp = list(
    en = "GWP (Global Warming Potential) converts CH₄ and N₂O emissions to CO₂ equivalent for reporting. AR5 (CH₄=28, N₂O=265) is the most commonly required for current IPCC submissions. AR6 (CH₄=27, N₂O=273) is the latest IPCC assessment. Use whichever version your national reporting guidelines specify.",
    fr = "Le GWP (Potentiel de Réchauffement Global) convertit les émissions de CH₄ et N₂O en équivalent CO₂ pour le rapport. AR5 (CH₄=28, N₂O=265) est le plus couramment demandé pour les soumissions IPCC actuelles. AR6 (CH₄=27, N₂O=273) est la dernière évaluation IPCC. Utilisez la version spécifiée par vos lignes directrices nationales."
  ),
  sim_sources_label = list(en = "Emission sources to include",
                              fr = "Sources d'émissions à inclure"),
  src_enteric_ch4 = list(en = "Enteric fermentation CH₄", fr = "Fermentation entérique CH₄"),
  src_manure_ch4  = list(en = "Manure management CH₄", fr = "Gestion du fumier CH₄"),
  src_manure_n2o_d = list(en = "Manure management N₂O direct",
                            fr = "Gestion du fumier N₂O direct"),
  src_manure_n2o_i = list(en = "Manure management N₂O indirect",
                            fr = "Gestion du fumier N₂O indirect"),
  src_pasture_n2o_d = list(en = "Pasture deposition N₂O direct",
                             fr = "Dépôts au pâturage N₂O direct"),
  src_pasture_n2o_i = list(en = "Pasture deposition N₂O indirect",
                             fr = "Dépôts au pâturage N₂O indirect"),
  sim_must_tick_one = list(en = "Tick at least one source above",
                              fr = "Cochez au moins une source ci-dessus"),
  sim_must_tick_body = list(
    en = ": the simulation cannot run without an explicit selection. (Most users tick all 6 for a full inventory.)",
    fr = " : la simulation ne peut pas démarrer sans une sélection explicite. (La plupart des utilisateurs cochent les 6 pour un inventaire complet.)"
  ),
  sim_run_decomp = list(en = "Run uncertainty decomposition (AD/EF/Combined)",
                          fr = "Lancer la décomposition d'incertitude (AD/EF/Combinée)"),
  sim_run_decomp_hint = list(
    en = "Runs two extra full simulations (~3× the run time on a large inventory). Untick for a faster run if you only need the headline result and sensitivity.",
    fr = "Lance deux simulations complètes supplémentaires (~3× le temps de calcul sur un grand inventaire). Décochez pour un calcul plus rapide si vous n'avez besoin que du résultat principal et de la sensibilité."),
  btn_run_sim = list(en = "Run Monte Carlo Simulation",
                       fr = "Lancer la simulation Monte Carlo"),
  trend_n_iter_label = list(
    en = "Iterations per year (trend)",
    fr = "Itérations par année (tendance)"),
  trend_n_iter_help = list(
    en = "Each year is a full simulation. 2,000 is enough for the chart and the slope.",
    fr = "Chaque année est une simulation complète. 2 000 suffisent pour le graphique et la pente."
  ),
  trend_n_iter_pair_label = list(
    en = "Draws for the base year and year t",
    fr = "Tirages pour l'année de base et l'année t"),
  trend_n_iter_pair_help = list(
    en = "The two reported years are run again at this count for the headline figures and the IPCC table. 10,000 matches a single-year run.",
    fr = "Les deux années déclarées sont recalculées à ce nombre pour les chiffres clés et le tableau GIEC. 10 000 correspond à un calcul d'année unique."
  ),
  btn_run_trend = list(en = "Run Trend Analysis",
                         fr = "Lancer l'analyse de tendance"),

  # =====================================================================
  # DEFINITIONS TAB
  # =====================================================================

  info_definitions_body = list(
    en = "Every parameter of the Tier 2 calculation: definition, unit, IPCC default, suggested distribution, and the IPCC table or equation it comes from. Names follow the IPCC Inventory Software (v2.95).",
    fr = "Chaque paramètre du calcul de niveau 2 : définition, unité, valeur GIEC par défaut, distribution suggérée, et le tableau ou l'équation GIEC d'origine. Les noms suivent le logiciel d'inventaire GIEC (v2.95)."
  ),
  card_param_definitions = list(en = "Parameter definitions",
                                  fr = "Définitions des paramètres"),
  card_stat_glossary = list(en = "Statistical terms in plain language",
                              fr = "Termes statistiques en langage clair"),
  info_stat_glossary = list(
    en = "The terms used across the Simulate, Sensitivity and IPCC Report tabs, explained without assuming a statistics background. For a fuller treatment, see the Methodology document on the Resources tab and IPCC 2006 Vol. 1 Ch. 3.",
    fr = "Les termes utilisés dans les onglets Simulation, Sensibilité et Rapport IPCC, expliqués sans supposer de bagage statistique. Pour un traitement plus complet, voir le document de méthodologie dans l'onglet Ressources et IPCC 2006 Vol. 1 Ch. 3."
  ),
  stat_col_term = list(en = "Term", fr = "Terme"),
  stat_col_def  = list(en = "Plain-language definition", fr = "Définition en langage clair"),
  stat_mc_term = list(en = "Monte Carlo simulation", fr = "Simulation Monte Carlo"),
  stat_mc_def = list(
    en = "Recalculating the whole inventory thousands of times, each time drawing a fresh value for every parameter from its probability distribution. The spread of the resulting totals shows how uncertain the inventory is.",
    fr = "Recalculer l'inventaire entier des milliers de fois, en tirant à chaque fois une nouvelle valeur de chaque paramètre selon sa distribution de probabilité. La dispersion des totaux obtenus montre l'incertitude de l'inventaire."
  ),
  stat_iter_term = list(en = "Iteration", fr = "Itération"),
  stat_iter_def = list(
    en = "One complete recalculation of the inventory with one set of sampled parameter values. 10,000 iterations = 10,000 alternative versions of your inventory.",
    fr = "Un recalcul complet de l'inventaire avec un jeu de valeurs échantillonnées. 10 000 itérations = 10 000 versions alternatives de votre inventaire."
  ),
  stat_dist_term = list(en = "Probability distribution", fr = "Distribution de probabilité"),
  stat_dist_def = list(
    en = "A description of which values a parameter can take and how likely each one is. Normal is the symmetric bell curve; lognormal is skewed with a long upper tail (common for emission factors); beta, triangular and PERT are bounded shapes built from a minimum, most-likely and maximum; uniform treats every value between the bounds as equally likely; constant means no uncertainty at all.",
    fr = "Une description des valeurs qu'un paramètre peut prendre et de leur probabilité. Normale : la courbe en cloche symétrique ; lognormale : asymétrique avec une longue queue supérieure (courant pour les facteurs d'émission) ; beta, triangulaire et PERT : des formes bornées construites à partir d'un minimum, d'un mode et d'un maximum ; uniforme : toutes les valeurs entre les bornes sont également probables ; constante : aucune incertitude."
  ),
  stat_mean_term = list(en = "Mean / median", fr = "Moyenne / médiane"),
  stat_mean_def = list(
    en = "The mean is the average across all iterations; the median is the middle value (half the iterations fall below it). For skewed distributions such as lognormal they differ, and the tool treats the entered central value of a lognormal as the median, per IPCC good-practice guidance.",
    fr = "La moyenne est la valeur moyenne sur toutes les itérations ; la médiane est la valeur du milieu (la moitié des itérations sont en dessous). Pour les distributions asymétriques comme la lognormale, elles diffèrent, et l'outil traite la valeur centrale saisie d'une lognormale comme la médiane, conformément aux bonnes pratiques IPCC."
  ),
  stat_sd_term = list(en = "Standard deviation (SD)", fr = "Écart-type"),
  stat_sd_def = list(
    en = "A measure of spread: how far values typically fall from the mean. In this tool the lower and upper bounds you enter are read as the 95% interval, which corresponds to roughly ±1.96 standard deviations for a normal distribution.",
    fr = "Une mesure de dispersion : à quelle distance de la moyenne les valeurs tombent typiquement. Dans cet outil, les bornes inférieure et supérieure saisies sont lues comme l'intervalle à 95 %, soit environ ±1,96 écart-type pour une distribution normale."
  ),
  stat_ci_term = list(en = "95% confidence interval (CI)", fr = "Intervalle de confiance à 95 % (IC)"),
  stat_ci_def = list(
    en = "The range that contains 95% of the simulated inventory totals, from the 2.5th to the 97.5th percentile. Read it as: given the stated input uncertainties, the true total is very likely inside this range.",
    fr = "La plage qui contient 95 % des totaux simulés, du percentile 2,5 au percentile 97,5. À lire ainsi : compte tenu des incertitudes d'entrée déclarées, le vrai total se trouve très probablement dans cette plage."
  ),
  stat_moe_term = list(en = "Margin of error (95% MoE %)", fr = "Marge d'erreur (MoE 95 % %)"),
  stat_moe_def = list(
    en = "The headline uncertainty metric of this tool and of IPCC Table 3.3: half the width of the 95% confidence interval, expressed as a percentage of the mean. A MoE of ±20% means the 95% CI spans from roughly 20% below to 20% above the central estimate.",
    fr = "La métrique d'incertitude principale de cet outil et du Tableau 3.3 IPCC : la demi-largeur de l'intervalle de confiance à 95 %, en pourcentage de la moyenne. Une MoE de ±20 % signifie que l'IC 95 % s'étend d'environ 20 % en dessous à 20 % au-dessus de l'estimation centrale."
  ),
  stat_pctile_term = list(en = "Percentile", fr = "Percentile"),
  stat_pctile_def = list(
    en = "The value below which a given share of iterations fall. The 2.5th percentile has 2.5% of iterations below it; the 97.5th has 97.5% below it. Together they bound the 95% CI.",
    fr = "La valeur en dessous de laquelle tombe une part donnée des itérations. Le percentile 2,5 a 2,5 % des itérations en dessous ; le percentile 97,5 en a 97,5 %. Ensemble, ils bornent l'IC 95 %."
  ),
  stat_corr_term = list(en = "Correlation", fr = "Corrélation"),
  stat_corr_def = list(
    en = "A measure (from -1 to +1) of how two parameters move together. A positive correlation means high values of one tend to come with high values of the other; sampling correlated parameters together usually widens the overall uncertainty. The tool uses rank (Spearman) correlations.",
    fr = "Une mesure (de -1 à +1) de la façon dont deux paramètres varient ensemble. Une corrélation positive signifie que des valeurs élevées de l'un accompagnent souvent des valeurs élevées de l'autre ; échantillonner ensemble des paramètres corrélés élargit généralement l'incertitude globale. L'outil utilise des corrélations de rang (Spearman)."
  ),
  stat_sens_term = list(en = "Sensitivity analysis / tornado chart", fr = "Analyse de sensibilité / graphique tornade"),
  stat_sens_def = list(
    en = "Ranks the input parameters by how much each one drives the uncertainty of the result. The tornado chart displays the ranking as horizontal bars, longest (most influential) on top.",
    fr = "Classe les paramètres d'entrée selon leur contribution à l'incertitude du résultat. Le graphique tornade affiche ce classement en barres horizontales, la plus longue (la plus influente) en haut."
  ),
  stat_src_term = list(en = "SRC (Standardised Regression Coefficient)", fr = "SRC (coefficient de régression standardisé)"),
  stat_src_def = list(
    en = "A sensitivity score from a linear model: how many standard deviations the output moves when the input moves by one standard deviation. Positive means higher input, higher emissions.",
    fr = "Un score de sensibilité issu d'un modèle linéaire : de combien d'écarts-types la sortie bouge quand l'entrée bouge d'un écart-type. Positif : entrée plus élevée, émissions plus élevées."
  ),
  stat_adef_term = list(en = "AD / EF decomposition", fr = "Décomposition AD / FE"),
  stat_adef_def = list(
    en = "Splits the combined uncertainty into the share coming from activity data (AD: the animal population) and the share from emission factors (EF: the per-head coefficients), by re-running the simulation with one group held fixed at a time. This is the AD/EF split IPCC Table 3.3 reports.",
    fr = "Sépare l'incertitude combinée entre la part venant des données d'activité (AD : la population animale) et la part venant des facteurs d'émission (FE : les coefficients par tête), en relançant la simulation avec un groupe fixé à la fois. C'est la répartition AD/FE du Tableau 3.3 IPCC."
  ),
  stat_seed_term = list(en = "Random seed", fr = "Graine aléatoire"),
  stat_seed_def = list(
    en = "The starting point of the random number generator. Fixing it makes the whole simulation exactly reproducible: same data, same settings, same seed, same numbers.",
    fr = "Le point de départ du générateur de nombres aléatoires. La fixer rend toute la simulation exactement reproductible : mêmes données, mêmes réglages, même graine, mêmes chiffres."
  ),
  stat_conv_term = list(en = "Convergence", fr = "Convergence"),
  stat_conv_def = list(
    en = "Whether you ran enough iterations for the results to be stable. Check it by re-running with a different seed: if the 95% MoE moves by more than about 2 percentage points, increase the number of iterations.",
    fr = "Le fait d'avoir exécuté assez d'itérations pour que les résultats soient stables. Vérifiez-la en relançant avec une autre graine : si la MoE 95 % bouge de plus d'environ 2 points, augmentez le nombre d'itérations."
  ),

  # =====================================================================
  # SENSITIVITY TAB
  # =====================================================================

  info_sens_what = list(
    en = "The tornado chart ranks the inputs by their effect on the uncertainty. Green bars are inputs you can improve with national data; blue bars are IPCC coefficients. Focus your data work on the top green ones.",
    fr = "Le graphique tornade classe les entrées selon leur effet sur l'incertitude. Les barres vertes sont des entrées améliorables avec des données nationales ; les barres bleues sont des coefficients GIEC. Concentrez votre travail de données sur les premières barres vertes."
  ),
  sens_output_var = list(en = "Output variable", fr = "Variable de sortie"),
  sens_total_co2e = list(en = "Total CO₂eq (all sources)",
                           fr = "CO₂éq total (toutes sources)"),
  card_tornado_h = list(en = "Tornado Chart - Top Parameters",
                          fr = "Graphique tornade : paramètres principaux"),
  card_sens_rankings = list(en = "Sensitivity Rankings",
                              fr = "Classements de sensibilité"),
  info_trend_sens_what = list(
    en = "Two charts. 'Latest year' ranks the inputs behind that year's uncertainty. 'Change between first and last year' ranks the inputs behind the trend. Green bars are inputs you can improve with national data; grey bars are IPCC coefficients. Focus on the green ones in the top five.",
    fr = "Deux graphiques. « Dernière année » classe les entrées derrière l'incertitude de cette année. « Variation entre la première et la dernière année » classe les entrées derrière la tendance. Les barres vertes sont des entrées améliorables avec des données nationales ; les barres grises sont des coefficients GIEC. Concentrez-vous sur les vertes du top 5."
  ),
  trend_sens_per_year_h = list(en = "What drives the uncertainty in the latest year",
                                  fr = "Ce qui pilote l'incertitude de la dernière année"),
  trend_sens_delta_h = list(en = "What drives the change between the first and last year",
                              fr = "Ce qui pilote la variation entre la première et la dernière année"),
  tornado_top10 = list(en = "Tornado: top 10", fr = "Tornado, top 10"),
  trend_rankings_top15 = list(en = "Rankings: top 15 (SRC)",
                                fr = "Classements : top 15 (SRC)"),
  trend_combined_note = list(
    en = "Combined Y_1 + Y_N inputs are sensitivity-tested against the per-iteration ΔCO₂eq. Suffixes _y1 / _yN distinguish the same parameter at different years.",
    fr = "Les entrées combinées Y_1 + Y_N sont testées en sensibilité contre le ΔCO₂éq par itération. Les suffixes _y1 / _yN distinguent le même paramètre à différentes années."
  ),

  # =====================================================================
  # IPCC REPORT TAB
  # =====================================================================

  info_ipcc_report_intro = list(
    en = "Your results in the IPCC Table 3.3 format. AD uncertainty comes from the population, EF uncertainty from the emission factor, Combined from both. All are the half-width of the 95% interval as a percentage of the mean. For the IPCC Inventory Software, copy the AD and EF columns of the matching category rows; both are filled when decomposition was ticked on Tab 4.",
    fr = "Vos résultats au format du Tableau 3.3 du GIEC. L'incertitude AD vient de la population, l'incertitude FE du facteur d'émission, Combinée des deux. Toutes sont la demi-largeur de l'intervalle à 95 % en pourcentage de la moyenne. Pour le logiciel d'inventaire GIEC, copiez les colonnes AD et FE des lignes de catégorie correspondantes ; les deux sont remplies si la décomposition était cochée à l'onglet 4."
  ),
  col_ad_uncert = list(en = "AD uncertainty (%)", fr = "Incertitude AD (%)"),
  col_ef_uncert = list(en = "EF uncertainty (%)", fr = "Incertitude FE (%)"),
  col_combined_uncert = list(en = "Combined uncertainty (%)",
                                fr = "Incertitude combinée (%)"),
  card_ipcc_table_h = list(en = "IPCC Table 3.3 - Uncertainty Report",
                              fr = "Tableau IPCC 3.3 : Rapport d'incertitude"),
  card_downloads_h = list(en = "Download reports", fr = "Télécharger les rapports"),
  downloads_intro = list(
    en = "Excel: all results and settings. CSV: the table only. Word: the full report with charts, ready to adapt for your inventory document.",
    fr = "Excel : tous les résultats et réglages. CSV : le tableau seul. Word : le rapport complet avec graphiques, prêt à adapter pour votre document d'inventaire."
  ),
  card_dist_per_source = list(en = "Uncertainty distributions per emission source",
                                fr = "Distributions d'incertitude par source d'émission"),
  body_dist_per_source = list(
    en = "Histograms of the Monte Carlo output for each emission source. Useful for third-party QA review of which sources contribute the most variance. When you hover over a bar, the tooltip shows two numbers: the ",
    fr = "Histogrammes de la sortie Monte Carlo pour chaque source d'émission. Utile pour la revue QA tierce des sources qui contribuent le plus à la variance. Quand vous survolez une barre, l'info-bulle affiche deux chiffres : la "
  ),
  xrange_label = list(en = "x-range", fr = "plage x"),
  body_dist_per_source_mid = list(
    en = " (e.g. '37k–38k') is the emission value interval for that bin in tonnes: the width of this interval reflects the spread of the distribution for that source; the ",
    fr = " (par ex. « 37k–38k ») est l'intervalle de valeurs d'émission pour ce bac en tonnes : la largeur de cet intervalle reflète l'étendue de la distribution pour cette source ; le "
  ),
  count_label = list(en = "count", fr = "compte"),
  body_dist_per_source_tail = list(
    en = " (e.g. '530') is the number of Monte Carlo iterations that fell in that bin. A narrow x-range with a tall peak indicates low uncertainty; a wide x-range with a flat histogram indicates high uncertainty.",
    fr = " (par ex. « 530 ») est le nombre d'itérations Monte Carlo dans ce bac. Une plage x étroite avec un pic haut indique une faible incertitude ; une plage x large avec un histogramme plat indique une incertitude élevée."
  ),
  card_top_drivers = list(en = "Top sensitivity drivers (Total CO₂eq)",
                            fr = "Principaux pilotes de sensibilité (CO₂éq total)"),
  body_top_drivers = list(
    en = "Standardised regression coefficients for the top 10 input parameters driving total uncertainty.",
    fr = "Coefficients de régression standardisés pour les 10 principaux paramètres d'entrée pilotant l'incertitude totale."
  ),
  card_input_dists = list(en = "Input distributions used",
                            fr = "Distributions d'entrée utilisées"),
  body_input_dists = list(
    en = "Density plots of each input parameter's fitted distribution: confirms each parameter was sampled with the marginal distribution specified in the input table.",
    fr = "Graphiques de densité de la distribution ajustée de chaque paramètre d'entrée : confirme que chaque paramètre a été échantillonné avec la distribution marginale spécifiée dans la table d'entrée."
  ),
  card_inputs_doc = list(en = "Input parameters used in this run",
                           fr = "Paramètres d'entrée utilisés dans cette exécution"),
  body_inputs_doc = list(
    en = "Full record of every parameter value, distribution, and bounds used in the simulation: included for inventory documentation and third-party QA review.",
    fr = "Enregistrement complet de chaque valeur de paramètre, distribution et bornes utilisées dans la simulation : inclus pour la documentation d'inventaire et la revue QA tierce."
  ),
  btn_download_xlsx = list(en = "Download Excel Report",
                              fr = "Télécharger le rapport Excel"),
  btn_download_csv = list(en = "Download CSV", fr = "Télécharger en CSV"),
  btn_download_docx = list(en = "Download Word summary",
                              fr = "Télécharger le résumé Word"),
  info_trend_report_what = list(
    en = "What you report for several years: the base year and year t in plain sentences, the IPCC table for those two years, every year's total with its uncertainty, and what drives it. Pick the two years below. Downloads: Excel, CSV or Word.",
    fr = "Ce que vous déclarez pour plusieurs années : l'année de base et l'année t en phrases simples, le tableau GIEC pour ces deux années, le total de chaque année avec son incertitude, et ce qui la pilote. Choisissez les deux années ci-dessous. Téléchargements : Excel, CSV ou Word."
  ),
  # ---- Trend: what to report (2026-10-22) ----------------------------------
  trend_report_h = list(en = "What to report", fr = "Ce qu'il faut déclarer"),
  trend_report_intro = list(
    en = "IPCC asks for two years: the base year and the year you are reporting (year t). Pick them here. The sentences, the comparison table and the IPCC reporting table follow your choice.",
    fr = "Le GIEC demande deux années : l'année de base et l'année déclarée (année t). Choisissez-les ici. Les phrases, le tableau de comparaison et le tableau de déclaration GIEC suivent votre choix."),
  trend_base_year_label = list(en = "Base year", fr = "Année de base"),
  trend_year_t_label = list(en = "Year to report (year t)", fr = "Année à déclarer (année t)"),
  trend_word_base_year = list(en = "Base year", fr = "Année de base"),
  trend_word_year_t = list(en = "Year t", fr = "Année t"),
  trend_line_year = list(
    en = "%s %d: %s t CO₂eq, plus or minus %s%% (95%% range %s to %s t).",
    fr = "%s %d : %s t CO₂éq, plus ou moins %s %% (plage à 95 %% de %s à %s t)."),
  trend_line_change = list(
    en = "Change from %d to %d: %s%%. The 95%% range of this change is %s%% to %s%%, that is %s to %s percentage points around the trend.",
    fr = "Variation de %d à %d : %s %%. La plage à 95 %% de cette variation va de %s %% à %s %%, soit %s à %s points de pourcentage autour de la tendance."),
  trend_line_zero_in = list(
    en = "This range includes zero: at 95%, the inventory cannot tell an increase from a decrease.",
    fr = "Cette plage inclut zéro : à 95 %, l'inventaire ne permet pas de distinguer une hausse d'une baisse."),
  trend_line_zero_out = list(
    en = "This range does not include zero: the direction of the change is clear at 95%.",
    fr = "Cette plage n'inclut pas zéro : le sens de la variation est clair à 95 %."),
  trend_line_where = list(
    en = "The IPCC reporting table for these two years is on the IPCC Report tab and in the downloads. Every other year is in the table further down.",
    fr = "Le tableau de déclaration GIEC pour ces deux années se trouve dans l'onglet Rapport GIEC et dans les téléchargements. Toutes les autres années sont dans le tableau plus bas."),
  trend_line_draws_pair = list(
    en = "Base year and year t: %s draws each, paired. The series: %s draws per year.",
    fr = "Année de base et année t : %s tirages chacune, en paire. La série : %s tirages par année."),
  trend_line_draws_series = list(
    en = "Both years from the series at %s draws per year.",
    fr = "Les deux années proviennent de la série à %s tirages par année."),
  trend_compare_h = list(en = "The two years side by side, by emission source",
                         fr = "Les deux années côte à côte, par source d'émission"),
  trend_compare_note = list(
    en = "Mean and 95% uncertainty of each source in both years, the change between the years and its 95% range. The last column shows which sources drive the uncertainty of year t; the six sources add up to 1.",
    fr = "Moyenne et incertitude à 95 % de chaque source pour les deux années, la variation entre les années et sa plage à 95 %. La dernière colonne montre quelles sources pilotent l'incertitude de l'année t ; les six sources totalisent 1."),
  trend_col_source = list(en = "Emission source", fr = "Source d'émission"),
  trend_col_base_mean = list(en = "Base year (t CO₂eq)", fr = "Année de base (t CO₂éq)"),
  trend_col_base_moe = list(en = "Base year ± %", fr = "Année de base ± %"),
  trend_col_t_mean = list(en = "Year t (t CO₂eq)", fr = "Année t (t CO₂éq)"),
  trend_col_t_moe = list(en = "Year t ± %", fr = "Année t ± %"),
  trend_col_change = list(en = "Change (%)", fr = "Variation (%)"),
  trend_col_change_range = list(en = "Change, 95% range (%)", fr = "Variation, plage à 95 % (%)"),
  trend_col_contrib = list(en = "Share of year t variance", fr = "Part de la variance de l'année t"),
  trend_year_detail_h = list(en = "One year in detail, by group", fr = "Une année en détail, par groupe"),
  trend_year_detail_label = list(en = "Year", fr = "Année"),
  trend_year_detail_note = list(
    en = "Mean total and 95% range for each group in the selected year, as a single-year run shows them.",
    fr = "Total moyen et plage à 95 % pour chaque groupe de l'année choisie, comme dans une exécution sur une seule année."),
  trend_col_group = list(en = "Group", fr = "Groupe"),
  trend_col_year_mean = list(en = "Mean (t CO₂eq)", fr = "Moyenne (t CO₂éq)"),
  trend_col_year_moe = list(en = "± %", fr = "± %"),
  trend_col_year_lo = list(en = "95% lower (t)", fr = "Borne basse 95 % (t)"),
  trend_col_year_hi = list(en = "95% upper (t)", fr = "Borne haute 95 % (t)"),
  trend_ipcc_h = list(en = "IPCC reporting table (Table 3.3) for the two years",
                      fr = "Tableau de déclaration GIEC (tableau 3.3) pour les deux années"),
  trend_ipcc_note = list(
    en = "The general reporting table for uncertainty from IPCC 2006 Vol. 1 Ch. 3, filled with Approach 2 (Monte Carlo). Values are in t CO₂eq; divide by 1,000 for Gg. The base year and year t come from their own paired run at the reporting draw count, which also fills the activity data and emission factor columns. After choosing other years, use the button to run them the same way.",
    fr = "Le tableau général de déclaration de l'incertitude du GIEC 2006 Vol. 1 Ch. 3, rempli avec l'approche 2 (Monte Carlo). Valeurs en t CO₂éq ; diviser par 1 000 pour des Gg. L'année de base et l'année t proviennent de leur propre exécution en paire avec le nombre de tirages de déclaration, qui remplit aussi les colonnes données d'activité et facteurs d'émission. Après avoir choisi d'autres années, utilisez le bouton pour les exécuter de la même façon."),
  trend_adef_btn = list(en = "Run these two years at the reporting draw count",
                        fr = "Lancer ces deux années avec le nombre de tirages de déclaration"),
  trend_adef_running = list(en = "Running base year %d and year t %d at %s draws...",
                            fr = "Exécution de l'année de base %d et de l'année t %d avec %s tirages..."),
  trend_adef_done = list(en = "Base year %d and year t %d: %s draws each, paired; activity data and emission factor columns filled.",
                         fr = "Année de base %d et année t %d : %s tirages chacune, en paire ; colonnes données d'activité et facteurs d'émission remplies."),
  trend_adef_empty = list(en = "These two years are shown from the %s-draw series. Press the button to run them at %s draws with the activity data and emission factor columns.",
                          fr = "Ces deux années proviennent de la série à %s tirages. Utilisez le bouton pour les exécuter avec %s tirages et les colonnes données d'activité et facteurs d'émission."),
  card_trend_downloads = list(en = "Trend report: downloads",
                                fr = "Rapport de tendance : téléchargements"),
  trend_downloads_note = list(
    en = "Available after a successful trend run on the Simulate tab. Filename includes the year-correlation mode you picked.",
    fr = "Disponible après une exécution de tendance réussie sur l'onglet Simulation. Le nom de fichier inclut le mode de corrélation inter-années choisi."
  ),
  card_trend_chart_h = list(en = "Total CO₂eq per year with its 95% range",
                              fr = "CO₂éq total par année avec sa plage à 95 %"),
  card_trend_table_h = list(en = "Every year: total and 95% range", fr = "Chaque année : total et plage à 95 %"),
  trend_table_note = list(
    en = "One row per year: mean total, lower and upper bound of the 95% range, uncertainty as ± % of the mean, change since the base year, change from the previous year.",
    fr = "Une ligne par année : total moyen, bornes basse et haute de la plage à 95 %, incertitude en ± % de la moyenne, variation depuis l'année de base, variation par rapport à l'année précédente."
  ),
  card_trend_sens_h = list(en = "What drives the uncertainty",
                              fr = "Ce qui pilote l'incertitude"),
  trend_sens_note = list(
    en = "Per-year tornado shows drivers of the latest year; Δ Y_N − Y_1 tornado shows what drives the change between the first and last year (per IPCC Vol 1 Ch 3 §3.7).",
    fr = "Le tornado par année montre les pilotes de l'année la plus récente ; le tornado Δ Y_N − Y_1 montre ce qui pilote le changement entre la première et la dernière année (selon IPCC Vol 1 Ch 3 §3.7)."
  ),

  # =====================================================================
  # CONTACT TAB
  # =====================================================================

  contact_intro_body = list(
    en = "Send feedback, bug reports or methodology questions. The team replies within a few working days.",
    fr = "Envoyez vos retours, signalements de bogues ou questions de méthode. L'équipe répond sous quelques jours ouvrés."
  ),
  card_contact_send = list(en = "Send us a message", fr = "Envoyez-nous un message"),
  card_contact_helps = list(en = "What kind of feedback helps most",
                              fr = "Quel type de retour est le plus utile"),
  contact_bug_label = list(en = "Bug reports", fr = "Signalements de bugs"),
  contact_bug_body = list(en = ": with steps to reproduce, the example dataset or your upload, and the error message.",
                            fr = " : avec les étapes pour reproduire, le jeu de données d'exemple ou votre téléversement, et le message d'erreur."),
  contact_method_label = list(en = "Methodology questions",
                                fr = "Questions méthodologiques"),
  contact_method_body = list(
    en = ": e.g. how a particular IPCC equation is implemented, or whether your country's data fits the assumptions.",
    fr = " : par exemple comment une équation IPCC est implémentée, ou si les données de votre pays correspondent aux hypothèses."
  ),
  contact_feat_label = list(en = "Feature requests", fr = "Demandes de fonctionnalités"),
  contact_feat_body = list(
    en = ": missing parameters, additional emission sources, integration with national inventory tools.",
    fr = " : paramètres manquants, sources d'émission supplémentaires, intégration avec les outils d'inventaire nationaux."
  ),
  contact_doc_label = list(en = "Documentation gaps", fr = "Lacunes documentaires"),
  contact_doc_body = list(en = ": if a tab or label was confusing, tell us where you got stuck.",
                            fr = " : si un onglet ou une étiquette était confus, dites-nous où vous avez été bloqué."),
  contact_privacy_note = list(
    en = "Privacy note: messages are relayed via Web3Forms, an HTTPS form-relay service. We don't store your message; we don't share your email.",
    fr = "Note de confidentialité : les messages sont relayés via Web3Forms, un service de relais de formulaire HTTPS. Nous ne stockons pas votre message ; nous ne partageons pas votre e-mail."
  ),

  cf_name = list(en = "Your name", fr = "Votre nom"),
  cf_name_ph = list(en = "First Last", fr = "Prénom Nom"),
  cf_affiliation = list(en = "Affiliation", fr = "Affiliation"),
  cf_affiliation_ph = list(en = "Organisation / project / institution",
                              fr = "Organisation / projet / institution"),
  cf_email = list(en = "Email", fr = "E-mail"),
  cf_message = list(en = "Message", fr = "Message"),
  cf_message_ph = list(
    en = "Tell us what you would like to share: a bug, a feature idea, a methodology question, anything.",
    fr = "Dites-nous ce que vous voulez partager : un bug, une idée de fonctionnalité, une question méthodologique, n'importe quoi."
  ),
  btn_cf_send = list(en = "Send message", fr = "Envoyer le message"),
  cf_status_init = list(
    en = "Submissions go directly to the development team. We aim to reply within a few working days.",
    fr = "Les soumissions vont directement à l'équipe de développement. Nous visons à répondre dans quelques jours ouvrables."
  ),
  cf_sending_btn = list(en = "Sending…", fr = "Envoi…"),
  cf_sending_msg = list(en = "Sending your message…", fr = "Envoi de votre message…"),
  cf_sent_text = list(en = "Message sent: thank you!",
                        fr = "Message envoyé : merci !"),
  cf_sent_sub = list(en = "We aim to reply within a few working days.",
                       fr = "Nous visons à répondre dans quelques jours ouvrables."),
  cf_send_failed = list(en = "Send failed:", fr = "Échec de l'envoi :"),
  cf_unknown_error = list(en = "unknown error", fr = "erreur inconnue"),
  cf_try_again = list(en = "Please try again in a moment.",
                        fr = "Veuillez réessayer dans un instant."),
  cf_network_error = list(en = "Network error. Please try again.",
                            fr = "Erreur réseau. Veuillez réessayer."),

  # =====================================================================
  # DEFINITIONS TABLE: column headers + categorical values
  # =====================================================================

  def_col_variable = list(en = "Variable name", fr = "Nom de variable"),
  def_col_definition = list(en = "Definition", fr = "Définition"),
  def_col_unit = list(en = "Unit", fr = "Unité"),
  def_col_ipcc_default = list(en = "IPCC default", fr = "Valeur IPCC par défaut"),
  def_col_basis = list(en = "Basis of the default",
                       fr = "Base de la valeur par défaut"),
  basis_panel_title = list(en = "What the defaults assume",
                           fr = "Hypothèses des valeurs par défaut"),
  basis_panel_intro = list(
    en = "Every IPCC default below is one cell of a much larger table. Reaching it means choosing a region, a productivity class, a climate and, for manure, a specific system variant. Those choices are listed here. Where one does not describe your herd, override the parameters it governs with country-specific values.",
    fr = "Chaque valeur IPCC par défaut ci-dessous est une cellule d'un tableau beaucoup plus vaste. Y parvenir suppose de choisir une région, une classe de productivité, un climat et, pour le fumier, une variante de système. Ces choix sont listés ici. Lorsqu'un choix ne décrit pas votre troupeau, remplacez les paramètres concernés par des valeurs nationales."),
  basis_col_dimension = list(en = "Choice", fr = "Choix"),
  basis_col_chosen = list(en = "This tool uses", fr = "Cet outil utilise"),
  basis_col_alternatives = list(en = "IPCC also publishes",
                                fr = "L'IPCC publie aussi"),
  basis_col_governs = list(en = "Affects", fr = "Concerne"),
  basis_col_source = list(en = "IPCC source", fr = "Source IPCC"),
  basis_col_why = list(en = "Why, and what to do otherwise",
                       fr = "Pourquoi, et que faire sinon"),
  def_col_dist = list(en = "Suggested distribution",
                       fr = "Distribution suggérée"),
  def_col_level = list(en = "Level", fr = "Niveau"),
  def_col_ipcc_framing = list(en = "IPCC framing", fr = "Cadrage IPCC"),
  def_col_ipcc_ref = list(en = "IPCC reference", fr = "Référence IPCC"),

  def_framing_ad = list(en = "Activity data (population)",
                          fr = "Donnée d'activité (population)"),
  def_framing_coef = list(en = "Coefficient (combines into EF)",
                            fr = "Coefficient (entre dans le FE)"),

  def_tier_core = list(en = "core", fr = "de base"),
  def_tier_advanced = list(en = "advanced", fr = "avancé"),

  # =====================================================================
  # AUTO-FILLED PARAMETERS NOTICE
  # =====================================================================

  imputed_load_data_first = list(en = "Load data first.", fr = "Chargez d'abord les données."),
  imputed_card_body_single = list(
    en = "%d parameter not supplied in your upload: auto-filled from IPCC defaults so the simulation could run. Override these values in the template if you have country-specific data.",
    fr = "%d paramètre non fourni dans votre téléversement : rempli automatiquement à partir des valeurs IPCC par défaut afin que la simulation puisse s'exécuter. Remplacez ces valeurs dans le modèle si vous disposez de données nationales."
  ),
  imputed_card_body_plural = list(
    en = "%d parameters not supplied in your upload: auto-filled from IPCC defaults so the simulation could run. Override these values in the template if you have country-specific data.",
    fr = "%d paramètres non fournis dans votre téléversement : remplis automatiquement à partir des valeurs IPCC par défaut afin que la simulation puisse s'exécuter. Remplacez ces valeurs dans le modèle si vous disposez de données nationales."
  ),
  imputed_dt_col_param = list(en = "Parameter", fr = "Paramètre"),
  imputed_dt_col_default = list(en = "Default value used", fr = "Valeur par défaut utilisée"),
  imputed_dt_col_unit = list(en = "Unit", fr = "Unité"),
  imputed_dt_col_ref = list(en = "IPCC reference", fr = "Référence IPCC"),
  imputed_dt_col_source = list(en = "Source", fr = "Source"),
  imputed_default_source = list(en = "AUTO-FILLED (IPCC default)",
                                  fr = "REMPLI AUTO (IPCC par défaut)"),
  imputed_notice_title_single = list(en = " %d parameter auto-filled from IPCC defaults",
                                       fr = " %d paramètre rempli automatiquement avec une valeur IPCC par défaut"),
  imputed_notice_title_plural = list(en = " %d parameters auto-filled from IPCC defaults",
                                       fr = " %d paramètres remplis automatiquement avec des valeurs IPCC par défaut"),
  imputed_notice_params_label = list(en = "Parameters:", fr = "Paramètres :"),
  imputed_th_param = list(en = "Parameter", fr = "Paramètre"),
  imputed_th_default = list(en = "IPCC default used", fr = "Valeur IPCC par défaut utilisée"),
  imputed_th_ref = list(en = "IPCC reference", fr = "Référence IPCC"),
  imputed_notice_tail_pre = list(
    en = " These are IPCC defaults: replace with country-specific values in your template where available. Full details and QA flags are on the ",
    fr = " Ce sont des valeurs IPCC par défaut : remplacez par des valeurs nationales dans votre modèle lorsque possible. Tous les détails et les indicateurs QA sont sur l'onglet "
  ),
  imputed_notice_tail_qaqc = list(en = "QA/QC", fr = "QA/QC"),
  imputed_notice_tail_post = list(en = " tab.", fr = "."),

  # =====================================================================
  # QA/QC table: status icons, summary badges, check labels
  # =====================================================================

  qa_icon_pass = list(en = "pass", fr = "OK"),
  qa_icon_info = list(en = "info", fr = "info"),
  qa_icon_warn = list(en = "warn", fr = "attention"),
  qa_icon_fail = list(en = "fail", fr = "échec"),
  qa_icon_missing = list(en = "missing", fr = "manquant"),
  qa_badge_autofilled = list(en = "auto-filled", fr = "remplis auto"),
  qa_badge_pass = list(en = "pass", fr = "OK"),
  qa_badge_info = list(en = "info", fr = "info"),
  qa_badge_warn = list(en = "warn", fr = "attention"),
  qa_badge_fail = list(en = "fail", fr = "échec"),
  qa_col_group = list(en = "Group", fr = "Groupe"),
  qa_col_parameter = list(en = "Parameter", fr = "Paramètre"),
  qa_col_check = list(en = "Check", fr = "Vérification"),
  qa_col_status = list(en = "Status", fr = "Statut"),
  qa_col_message = list(en = "Message", fr = "Message"),
  qa_no_data = list(en = "No data loaded.", fr = "Aucune donnée chargée."),

  # QA verdict messages: sprintf templates keyed by check id + verdict.
  # Use `qa_msg(key, ...)` (see helper below) to fetch the right language.
  qa_msg_bounds_order_fail_lo = list(
    en = "Lower (%.4g) > mean (%.4g). Bounds must bracket the mean.",
    fr = "Borne inférieure (%.4g) > moyenne (%.4g). Les bornes doivent encadrer la moyenne."
  ),
  qa_msg_bounds_order_fail_hi = list(
    en = "Mean (%.4g) > upper (%.4g). Bounds must bracket the mean.",
    fr = "Moyenne (%.4g) > borne supérieure (%.4g). Les bornes doivent encadrer la moyenne."
  ),
  qa_msg_bounds_order_pass = list(en = "Lower <= mean <= upper",
                                    fr = "Inférieure ≤ moyenne ≤ supérieure"),
  qa_msg_bounds_order_zero = list(en = "Zero-mean parameter (degenerate constant)",
                                    fr = "Paramètre à moyenne nulle (constante dégénérée)"),
  qa_msg_nonneg_warn = list(
    en = "Lower bound (%.4g) is negative. All IPCC livestock parameters should be >= 0.",
    fr = "Borne inférieure (%.4g) négative. Tous les paramètres d'élevage IPCC doivent être ≥ 0."
  ),
  qa_msg_nonneg_pass = list(en = "Lower bound >= 0",
                              fr = "Borne inférieure ≥ 0"),
  qa_msg_zero_spread_info = list(
    en = "lower = upper = mean: no uncertainty, %s is sampled as a constant.",
    fr = "inférieure = supérieure = moyenne : aucune incertitude, %s est tiré comme une constante."
  ),
  qa_msg_unc_missing_warn = list(
    en = "No lower/upper bounds and no uncertainty_pct: %s is sampled as a constant (%.4g). Give a range, or set the distribution to constant.",
    fr = "Aucune borne inférieure/supérieure ni uncertainty_pct : %s est tiré comme une constante (%.4g). Donnez une plage, ou mettez la distribution à constant."
  ),
  qa_msg_unit_fraction_fail = list(
    en = "%s = %.4g. The template expects a percentage (%s); this looks like a fraction. If it is one, enter %.4g.",
    fr = "%s = %.4g. Le modèle attend un pourcentage (%s) ; ceci ressemble à une fraction. Si c'en est une, saisissez %.4g."
  ),
  qa_msg_unit_percent_fail = list(
    en = "%s = %.4g. The template expects a fraction between 0 and 1 (%s); this looks like a percentage. If it is one, enter %.4g.",
    fr = "%s = %.4g. Le modèle attend une fraction entre 0 et 1 (%s) ; ceci ressemble à un pourcentage. Si c'en est un, saisissez %.4g."
  ),
  qa_msg_range_de_fail = list(en = "DE = %.1f%%. Must be above 0 and at most 100.",
                                fr = "DE = %.1f %%. Doit être supérieur à 0 et au plus 100."),
  qa_msg_range_de_pass = list(en = "DE = %.1f%% (0 to 100)",
                                fr = "DE = %.1f %% (0 à 100)"),
  qa_msg_range_pct_fail = list(en = "%s = %.4g%%. A percentage must be between 0 and 100.",
                                 fr = "%s = %.4g %%. Un pourcentage doit être entre 0 et 100."),
  qa_msg_range_pct_pass = list(en = "%s = %.4g%% (0 to 100)",
                                 fr = "%s = %.4g %% (0 à 100)"),
  qa_msg_frac_fail = list(en = "%s = %.4g. Must be a fraction in [0, 1].",
                            fr = "%s = %.4g. Doit être une fraction dans [0, 1]."),
  qa_msg_frac_pass = list(en = "%s = %.4g (valid fraction in [0, 1])",
                            fr = "%s = %.4g (fraction valide dans [0, 1])"),
  qa_msg_plaus_warn = list(
    en = "%s = %.4g %s is outside the usual range %.4g to %.4g (%s). Check the value and its unit.",
    fr = "%s = %.4g %s est hors de la plage usuelle %.4g à %.4g (%s). Vérifiez la valeur et son unité."
  ),
  qa_msg_plaus_zero_pass = list(en = "%s = 0: not used for this group",
                                  fr = "%s = 0 : non utilisé pour ce groupe"),
  qa_msg_plaus_pass = list(en = "%s = %.4g %s (usual range %.4g to %.4g)",
                             fr = "%s = %.4g %s (plage usuelle %.4g à %.4g)"),
  qa_msg_beta_fail = list(
    en = "Beta is drawn between lower and upper around the mean, so the bounds must enclose the mean strictly. Got lower %.4g, mean %.4g, upper %.4g.",
    fr = "La loi beta est tirée entre les bornes autour de la moyenne ; les bornes doivent donc encadrer strictement la moyenne. Reçu inférieure %.4g, moyenne %.4g, supérieure %.4g."
  ),
  qa_msg_beta_pass = list(en = "Beta between %.4g and %.4g, mean inside",
                            fr = "Beta entre %.4g et %.4g, moyenne à l'intérieur"),
  qa_msg_lognorm_fail = list(
    en = "Log-normal needs a positive mean and a positive lower bound (the spread is read on the log scale). Got mean %.4g, lower %.4g; with a lower bound at or below 0 every draw equals the mean.",
    fr = "La loi log-normale requiert une moyenne et une borne inférieure positives (la dispersion est lue en échelle log). Reçu moyenne %.4g, inférieure %.4g ; avec une borne inférieure nulle ou négative, chaque tirage vaut la moyenne."
  ),
  qa_msg_lognorm_pass = list(en = "Log-normal: mean and bounds > 0",
                               fr = "Log-normale : moyenne et bornes > 0"),
  qa_msg_tnorm_warn = list(
    en = "tnorm_0_1 clips to [0,1]; bounds [%.4g, %.4g] extend beyond this.",
    fr = "tnorm_0_1 tronque à [0,1] ; les bornes [%.4g, %.4g] dépassent cette plage."
  ),
  qa_msg_tnorm_pass = list(en = "tnorm_0_1: bounds within [0,1]",
                             fr = "tnorm_0_1 : bornes dans [0,1]"),
  qa_msg_bench_fail = list(
    en = "Mean (%.4g) deviates %.0f%% from %s default (%.4g). Verify the value or document the country-specific source.",
    fr = "La moyenne (%.4g) s'écarte de %.0f %% par rapport à la valeur par défaut %s (%.4g). Vérifiez la valeur ou documentez la source nationale."
  ),
  qa_msg_bench_warn = list(
    en = "Mean (%.4g) deviates %.0f%% from %s default (%.4g). Large deviation: please document the source.",
    fr = "La moyenne (%.4g) s'écarte de %.0f %% par rapport à la valeur par défaut %s (%.4g). Écart important : veuillez documenter la source."
  ),
  qa_msg_bench_pass = list(
    en = "Mean (%.4g) within 50%% of %s default (%.4g)",
    fr = "La moyenne (%.4g) est à moins de 50 %% de la valeur par défaut %s (%.4g)"
  ),
  qa_msg_paramtype_fail = list(
    en = "param_type = '%s' is not recognised. Use 'activity_data' or 'coefficient'.",
    fr = "param_type = '%s' non reconnu. Utilisez « activity_data » ou « coefficient »."
  ),
  qa_msg_missing = list(
    en = "%s not supplied in upload - auto-filled with IPCC default %.4g %s (%s). Override in template if local data is available.",
    fr = "%s non fourni dans le téléversement : rempli automatiquement avec la valeur IPCC par défaut %.4g %s (%s). Remplacez dans le modèle si des données locales sont disponibles."
  ),
  qa_msg_frac_dist_warn = list(
    en = "%s uses '%s' with bounds %.4g to %.4g: about %.1f%% of the draws would fall outside [0, 1]. Use a bounded distribution (beta, pert, triangular, tnorm_0_1) or narrow the range.",
    fr = "%s utilise « %s » avec les bornes %.4g à %.4g : environ %.1f %% des tirages sortiraient de [0, 1]. Utilisez une distribution bornée (beta, pert, triangular, tnorm_0_1) ou resserrez la plage."
  ),
  qa_msg_frac_dist_pass = list(en = "%s: '%s' keeps the draws within [0, 1]",
                                  fr = "%s : « %s » garde les tirages dans [0, 1]"),
  qa_msg_asym_info = list(
    en = "%s: bounds nearly symmetric around the mean (upper span / lower span = %.1f). IPCC gives a right-skewed range, %.4g to %.4g around %.4g (%s). Keep yours if it is a national estimate; otherwise use the IPCC range from the blank template.",
    fr = "%s : bornes presque symétriques autour de la moyenne (étendue sup. / étendue inf. = %.1f). L'IPCC donne une plage asymétrique à droite, %.4g à %.4g autour de %.4g (%s). Gardez les vôtres s'il s'agit d'une estimation nationale ; sinon utilisez la plage IPCC du modèle vierge."
  ),
  qa_msg_asym_pass = list(
    en = "%s: asymmetric bounds applied (upper/lower span ratio = %.1f)",
    fr = "%s : bornes asymétriques appliquées (ratio étendue sup./inf. = %.1f)"
  ),
  qa_msg_no_mms = list(
    en = "No Manure_Management sheet present: manure CH4 and N2O fall back to default 70%% pasture / 30%% solid_storage allocation. Add a Manure_Management sheet to use per-MMS values.",
    fr = "Pas de feuille Manure_Management : CH4 et N2O du fumier reviennent à l'allocation par défaut 70 %% pâturage / 30 %% solid_storage. Ajoutez une feuille Manure_Management pour utiliser des valeurs par-MMS."
  ),
  qa_msg_sub_no_match = list(
    en = "Parameters sub_category '%s' has no matching Manure_Management rows (no rows for cattle_type='%s', aggregation_level='%s'). Falls back to default 70%% pasture / 30%% solid_storage allocation, which under-counts MM N2O. Either add MM rows for this group or remove it from Parameters.",
    fr = "La sous-catégorie « %s » des Parameters n'a pas de lignes Manure_Management correspondantes (aucune pour cattle_type='%s', aggregation_level='%s'). Repli sur l'allocation 70 %% pâturage / 30 %% solid_storage, qui sous-estime le N2O de MM. Ajoutez des lignes MM pour ce groupe ou retirez-le des Parameters."
  ),
  qa_msg_sub_auto_match = list(
    en = "Parameters sub_category '%s' was auto-matched to Manure_Management sub_category '%s' (same cattle_type + aggregation_level, edit distance %d). Verify this is the same animal sub-category. Fix the spelling in either sheet to silence this warning.",
    fr = "La sous-catégorie Parameters « %s » a été auto-appariée à la sous-catégorie Manure_Management « %s » (mêmes cattle_type + aggregation_level, distance d'édition %d). Vérifiez qu'il s'agit de la même sous-catégorie animale. Corrigez l'orthographe dans l'une ou l'autre feuille pour faire taire cet avertissement."
  ),
  qa_msg_sub_ambiguous = list(
    en = "Parameters sub_category '%s' is ambiguously close to multiple Manure_Management sub-categories: %s. Cannot auto-match. Fix the spelling in either sheet so exactly one MM sub-category matches.",
    fr = "La sous-catégorie Parameters « %s » est ambiguë vis-à-vis de plusieurs sous-catégories Manure_Management : %s. Auto-appariement impossible. Corrigez l'orthographe dans une feuille pour qu'une seule sous-catégorie MM corresponde."
  ),
  qa_msg_sub_no_match_listed = list(
    en = "Parameters sub_category '%s' has no matching Manure_Management row in cattle_type='%s' / aggregation_level='%s'. MM sub-categories available in this group: %s. Falls back to default 70%% pasture / 30%% solid_storage allocation.",
    fr = "La sous-catégorie Parameters « %s » n'a pas de ligne Manure_Management correspondante pour cattle_type='%s' / aggregation_level='%s'. Sous-catégories MM disponibles dans ce groupe : %s. Repli sur l'allocation 70 %% pâturage / 30 %% solid_storage."
  ),

  # =====================================================================
  # CORRELATIONS TAB: radio options + TS status + Compare toggle
  # =====================================================================

  corr_mode_none = list(en = "No correlations (default)",
                          fr = "Pas de corrélations (par défaut)"),
  corr_mode_preset = list(en = "Structural defaults (literature-based)",
                            fr = "Valeurs structurelles par défaut (fondées sur la littérature)"),
  corr_mode_ts = list(en = "From template (auto, time-series)",
                       fr = "Depuis le modèle (auto, séries temporelles)"),
  corr_mode_manual = list(en = "Advanced: manual matrix entry",
                            fr = "Avancé : saisie manuelle de la matrice"),
  corr_mode_unavailable_ts = list(
    en = ": needs a non-empty Parameter_TimeSeries sheet",
    fr = " : nécessite une feuille Parameter_TimeSeries non vide"
  ),
  corr_mode_unavailable_manual = list(
    en = ": needs an uploaded matrix",
    fr = " : nécessite une matrice téléversée"
  ),


  corr_ts_status_ok = list(
    en = "Time-series sheet loaded: correlations computed from your data.",
    fr = "Feuille de séries temporelles chargée : corrélations calculées à partir de vos données."
  ),
  corr_ts_status_missing = list(
    en = "No Parameter_TimeSeries sheet found in your upload. Upload a template with this sheet, or pick another correlation mode.",
    fr = "Aucune feuille Parameter_TimeSeries trouvée dans votre téléversement. Téléversez un modèle contenant cette feuille ou choisissez un autre mode de corrélation."
  ),
  corr_ts_status_empty = list(
    en = "Parameter_TimeSeries sheet found but is empty. Fill it with multi-year activity data or pick another correlation mode.",
    fr = "Feuille Parameter_TimeSeries trouvée mais vide. Remplissez-la avec des données pluriannuelles ou choisissez un autre mode de corrélation."
  ),


  cmp_run_label = list(en = "Compare with/without correlations",
                         fr = "Comparer avec/sans corrélations"),
  cmp_run_tooltip = list(
    en = "When ticked, the simulation runs twice: once with the correlations you picked, once with all correlations off, and the Results tab shows both side-by-side so you can see the impact.",
    fr = "Quand coché, la simulation s'exécute deux fois : une avec les corrélations choisies, une avec les corrélations désactivées, et l'onglet Résultats les affiche côte à côte pour voir l'effet."
  ),
  cmp_disabled_note = list(
    en = "No correlations selected on the Correlations tab: comparison would be identical, so this toggle is disabled.",
    fr = "Aucune corrélation sélectionnée sur l'onglet Corrélations : la comparaison serait identique, ce bouton est donc désactivé."
  ),

  # Correlations tab: radio mode label + tooltip + per-mode help text
  corr_mode_label = list(en = "Mode", fr = "Mode"),
  tip_corr_mode = list(
    en = "How should the tool decide which input parameters move together? Modes whose prerequisites are missing (no time-series, no manual matrix uploaded) are greyed out below.",
    fr = "Comment l'outil doit-il décider quels paramètres bougent ensemble ? Les modes dont les prérequis manquent (pas de séries temporelles, pas de matrice manuelle téléversée) sont grisés ci-dessous."
  ),
  corr_disabled_prefix = list(en = "Disabled: ", fr = "Désactivé, "),
  corr_help_none = list(
    en = "Pick this if you have no information about how your parameters move together. Matches the standard IPCC Approach 2 starting point.",
    fr = "Choisissez ceci si vous n'avez aucune information sur la manière dont vos paramètres bougent ensemble. Correspond au point de départ standard IPCC Approche 2."
  ),
  corr_help_ts_pre = list(en = "Pick this when your upload contains a ",
                            fr = "Choisissez ceci lorsque votre téléversement contient une feuille "),
  corr_help_ts_post = list(en = " sheet with ≥5 years of data. ",
                             fr = " avec ≥ 5 années de données. "),
  corr_help_ts_em = list(en = "Recommended whenever you have the data.",
                           fr = "Recommandé dès que vous avez les données."),
  corr_help_ts_disabled_pre = list(en = "your ",
                                      fr = "votre feuille "),
  corr_help_ts_disabled_post = list(
    en = " sheet is empty or missing. Upload a template with a populated TS sheet (≥5 years, ≥2 numeric columns) to enable.",
    fr = " est vide ou absente. Téléversez un modèle avec une feuille TS remplie (≥ 5 années, ≥ 2 colonnes numériques) pour l'activer."
  ),
  corr_help_preset = list(
    en = "Known biological linkages (BW↔MW, DE↔Ym, Milk↔BW, Milk↔DE, etc.) applied automatically. ",
    fr = "Liens biologiques connus (BW↔MW, DE↔Ym, Milk↔BW, Milk↔DE, etc.) appliqués automatiquement. "
  ),
  corr_help_preset_em = list(en = "Recommended for single-year inventories.",
                                fr = "Recommandé pour les inventaires d'une seule année."),
  corr_help_preset_disabled = list(
    en = "no parameter data loaded yet. Load Country X / Country Y or upload your own template to enable.",
    fr = "aucune donnée de paramètres chargée. Chargez Pays X / Pays Y ou téléversez votre propre modèle pour l'activer."
  ),
  corr_help_manual_loaded = list(
    en = "A manual CSV matrix is loaded: using it for the run. Re-upload below to replace.",
    fr = "Une matrice CSV manuelle est chargée : utilisée pour l'exécution. Téléversez à nouveau ci-dessous pour remplacer."
  ),
  corr_help_manual_pick = list(
    en = "Pick this to use a CSV correlation matrix. Two starting templates appear below: a blank matrix with all parameter names pre-labelled, and an example pre-filled with the structural-defaults pairs. Edit cells and re-upload.",
    fr = "Choisissez ceci pour utiliser une matrice de corrélation CSV. Deux modèles de départ apparaissent ci-dessous : une matrice vierge avec tous les noms de paramètres pré-étiquetés, et un exemple pré-rempli avec les paires des valeurs structurelles par défaut. Modifiez les cellules et téléversez à nouveau."
  ),
  corr_mode_advanced_manual_short = list(en = "Advanced: manual entry",
                                            fr = "Avancé : saisie manuelle"),

  # Correlations TS status messages (server-rendered)
  corr_ts_no_data = list(
    en = " No time-series data in the loaded inventory. To enable auto-correlation, upload a template with a populated ",
    fr = " Aucune donnée de séries temporelles dans l'inventaire chargé. Pour activer l'auto-corrélation, téléversez un modèle avec une feuille "
  ),
  corr_ts_param_ts = list(en = "Parameter_TimeSeries", fr = "Parameter_TimeSeries"),
  corr_ts_no_data_tail = list(
    en = " sheet, or load Country X / Country Y from the dropdown (both ship with example time-series).",
    fr = " remplie, ou chargez Pays X / Pays Y depuis le menu déroulant (les deux incluent des séries temporelles d'exemple)."
  ),
  corr_ts_loaded = list(en = " Correlation matrix loaded: %d parameters (%s).",
                          fr = " Matrice de corrélation chargée : %d paramètres (%s)."),

  # Compare-with-without-correlations
  cmp_disabled_long = list(
    en = " No correlations selected on Tab 3: comparison would be identical to the main run, so this option is disabled. Enable a correlation mode to activate it.",
    fr = " Aucune corrélation sélectionnée sur l'onglet 3 : la comparaison serait identique à l'exécution principale, cette option est donc désactivée. Activez un mode de corrélation pour l'activer."
  ),

  # Correlation heatmap labels
  corr_heatmap_no_matrix = list(en = "No correlation matrix loaded",
                                  fr = "Aucune matrice de corrélation chargée"),
  corr_heatmap_title_ad = list(en = "Activity Data Correlation Matrix",
                                  fr = "Matrice de corrélation des données d'activité"),

  # =====================================================================
  # RESULTS VIEW (Simulate tab: post-run)
  # =====================================================================

  res_back_to_settings = list(en = "Back to settings (run another simulation)",
                              fr = "Retour aux paramètres (lancer une autre simulation)"),
  res_headline_h = list(en = "Headline results", fr = "Résultats principaux"),
  res_summary_intro = list(
    en = "Mean and 95% confidence interval for each emission source, with the margin of error as a percentage.",
    fr = "Moyenne et intervalle de confiance à 95 % pour chaque source d'émission, avec la marge d'erreur en pourcentage."
  ),

  res_vb_enteric_label = list(en = "Enteric fermentation CH₄",
                                 fr = "Fermentation entérique CH₄"),
  res_vb_manure_ch4_label = list(en = "Manure management CH₄",
                                    fr = "Gestion du fumier CH₄"),
  res_vb_manure_n2o_label = list(en = "Manure management N₂O",
                                    fr = "Gestion du fumier N₂O"),
  res_vb_pasture_n2o_label = list(en = "Pasture deposition N₂O",
                                     fr = "Dépôts au pâturage N₂O"),
  res_vb_moe_label = list(en = "Total CO₂eq: 95% MoE",
                            fr = "CO₂éq total : MoE 95 %"),
  res_vb_mean_label = list(en = "mean", fr = "moyenne"),
  res_vb_ci_label = list(en = "95% CI", fr = "IC 95 %"),
  res_vb_moe_pct_label = list(en = "± of mean", fr = "± de la moyenne"),

  res_histogram_title = list(en = "Total CO₂eq distribution",
                                fr = "Distribution du CO₂éq total"),
  res_histogram_subtitle = list(
    en = "Monte Carlo iterations across the whole inventory. Vertical lines mark the 2.5%/50%/97.5% quantiles.",
    fr = "Itérations Monte Carlo sur l'inventaire complet. Les lignes verticales marquent les quantiles 2,5 % / 50 % / 97,5 %."
  ),

  res_decomp_h = list(en = "Uncertainty decomposition", fr = "Décomposition de l'incertitude"),
  res_decomp_intro = list(
    en = "How much of the 95% margin of error comes from activity-data (population) uncertainty vs. coefficient (per-head EF) uncertainty.",
    fr = "Quelle part de la marge d'erreur 95 % provient de l'incertitude des données d'activité (population) vs des coefficients (FE par tête)."
  ),
  res_decomp_ad_label = list(en = "Activity data", fr = "Données d'activité"),
  res_decomp_ef_label = list(en = "Coefficients (EF)", fr = "Coefficients (FE)"),
  res_decomp_combined_label = list(en = "Combined", fr = "Combinée"),

  res_by_system_h = list(en = "Results by sub-category",
                            fr = "Résultats par sous-catégorie"),
  res_by_system_intro = list(
    en = "Per-sub-category mean and 95% CI for each emission source.",
    fr = "Moyenne et IC 95 % par sous-catégorie pour chaque source d'émission."
  ),

  res_by_category_h = list(en = "Results by cattle type",
                              fr = "Résultats par type de bétail"),
  res_by_category_intro = list(
    en = "Aggregated by cattle type (dairy, non-dairy, buffalo).",
    fr = "Agrégés par type de bétail (laitier, non laitier, buffle)."
  ),

  res_comparison_h = list(en = "With vs without correlations",
                             fr = "Avec vs sans corrélations"),
  res_comparison_intro = list(
    en = "Side-by-side comparison of the same Monte Carlo run with the correlations you picked vs. with all correlations turned off. The difference shows how much the correlation structure widens or narrows the uncertainty range.",
    fr = "Comparaison côte à côte de la même simulation Monte Carlo avec les corrélations choisies vs. toutes corrélations désactivées. La différence montre comment la structure des corrélations élargit ou réduit la plage d'incertitude."
  ),
  res_comparison_with_label = list(en = "With correlations", fr = "Avec corrélations"),
  res_comparison_without_label = list(en = "Without correlations", fr = "Sans corrélations"),
  res_comparison_delta_label = list(en = "Δ (% points)", fr = "Δ (points de %)"),

  # Trend Results value boxes
  res_vb_trend_latest = list(en = "Latest year: Total CO₂eq",
                                fr = "Année la plus récente : CO₂éq total"),
  res_vb_trend_delta = list(en = "Change since base year",
                              fr = "Variation depuis l'année de base"),
  res_vb_trend_slope = list(en = "Trend slope (per year)",
                              fr = "Pente de tendance (par an)"),
  res_vb_trend_yoy = list(en = "Year-over-year change (latest)",
                            fr = "Variation interannuelle (dernière)"),

  # Simulation status messages
  sim_status_running = list(en = "Running simulation…", fr = "Simulation en cours…"),
  sim_status_done = list(en = "Simulation complete.", fr = "Simulation terminée."),
  sim_status_done_with_decomp = list(
    en = "Simulation complete. Decomposition computed.",
    fr = "Simulation terminée. Décomposition calculée."
  ),
  sim_status_idle = list(en = "Idle. Click Run to start a simulation.",
                           fr = "En attente. Cliquez sur Lancer pour démarrer une simulation."),
  sim_status_failed = list(en = "Simulation failed:", fr = "Échec de la simulation :"),
  trend_status_running = list(en = "Running trend analysis…",
                                fr = "Analyse de tendance en cours…"),
  trend_status_done = list(en = "Trend analysis complete.",
                             fr = "Analyse de tendance terminée."),
  trend_status_failed = list(en = "Trend analysis failed:",
                               fr = "Échec de l'analyse de tendance :"),

  # Results: DT column headers + chart titles
  res_col_cattle_type    = list(en = "Cattle type", fr = "Type de bétail"),
  res_col_group          = list(en = "Group", fr = "Groupe"),
  res_col_source         = list(en = "Source", fr = "Source"),
  res_col_enteric_ch4_t  = list(en = "Enteric CH₄ (t)", fr = "CH₄ entérique (t)"),
  res_col_manure_ch4_t   = list(en = "Manure CH₄ (t)", fr = "CH₄ du fumier (t)"),
  res_col_manure_n2o_t   = list(en = "Manure N₂O (t)", fr = "N₂O du fumier (t)"),
  res_col_pasture_n2o_t  = list(en = "Pasture N₂O (t)", fr = "N₂O au pâturage (t)"),
  res_col_total_co2e_t   = list(en = "Total CO₂eq (t)", fr = "CO₂éq total (t)"),
  res_col_mean_ch4_t     = list(en = "Mean CH₄ (t)", fr = "Moy. CH₄ (t)"),
  res_col_mean_n2o_t     = list(en = "Mean N₂O (t)", fr = "Moy. N₂O (t)"),
  res_col_mean_co2e_t    = list(en = "Mean CO₂eq (t)", fr = "Moy. CO₂éq (t)"),
  res_col_mean_t_ch4     = list(en = "Mean (t CH₄)", fr = "Moy. (t CH₄)"),
  res_col_mean_t_n2o     = list(en = "Mean (t N₂O)", fr = "Moy. (t N₂O)"),
  res_col_mean_t_co2e    = list(en = "Mean (t CO₂eq)", fr = "Moy. (t CO₂éq)"),
  res_col_moe_pct        = list(en = "MoE 95% (%)", fr = "MoE 95 % (%)"),
  res_col_ci_lower_t     = list(en = "CI lower (t CO₂eq)", fr = "Borne inf. IC (t CO₂éq)"),
  res_col_ci_upper_t     = list(en = "CI upper (t CO₂eq)", fr = "Borne sup. IC (t CO₂éq)"),

  # 2026-10-28 (review): figure numbers, captions, units, tornado legend,
  # Definitions search.
  fig_word = list(en = "Figure", fr = "Figure"),
  fig_conv_title = list(en = "Convergence of the simulation", fr = "Convergence de la simulation"),
  fig_tornado_year_title = list(en = "Top 10 drivers of the latest year", fr = "Les 10 principaux facteurs de la dernière année"),
  fig_tornado_delta_title = list(en = "Top 10 drivers of the change between the first and the last year", fr = "Les 10 principaux facteurs de la variation entre la première et la dernière année"),
  fig_cap_corr = list(
    en = "Correlation used in the run between each pair of activity-data inputs, from -1 to +1. Green cells move together, red cells move in opposite directions, white cells are independent.",
    fr = "Corrélation utilisée dans l'exécution entre chaque paire de données d'activité, de -1 à +1. Les cellules vertes varient ensemble, les rouges en sens opposé, les blanches sont indépendantes."),
  fig_cap_conv = list(
    en = "Running mean of total CO2eq (solid line) and running 2.5th and 97.5th percentiles (dashed lines) as iterations are added. Lines that are flat at the right edge show that the simulation ran long enough.",
    fr = "Moyenne cumulée du CO₂éq total (trait plein) et 2,5e et 97,5e percentiles cumulés (tirets) au fil des itérations. Des courbes plates à droite indiquent que la simulation a été assez longue."),
  fig_cap_hist = list(
    en = "Each bar counts the iterations whose total CO2eq fell in that range. The dashed lines are the 2.5th and 97.5th percentiles, the bounds of the 95% confidence interval.",
    fr = "Chaque barre compte les itérations dont le CO₂éq total tombe dans cet intervalle. Les tirets sont les 2,5e et 97,5e percentiles, bornes de l'intervalle de confiance à 95 %."),
  fig_cap_decomp = list(
    en = "Margin of error (MoE: half the width of the 95% confidence interval, as a percentage of the mean) of total CO2eq when only the activity data vary, when only the coefficients vary, and when both vary. The combined bar is the reported uncertainty.",
    fr = "Marge d'erreur (MoE : demi-largeur de l'intervalle de confiance à 95 %, en pourcentage de la moyenne) du CO₂éq total lorsque seules les données d'activité varient, lorsque seuls les coefficients varient, et lorsque les deux varient. La barre combinée est l'incertitude rapportée."),
  fig_cap_trend = list(
    en = "Mean total CO2eq for each year (line) with its 95% confidence interval (shaded band).",
    fr = "CO₂éq total moyen pour chaque année (courbe) avec son intervalle de confiance à 95 % (bande)."),
  fig_cap_yoy = list(
    en = "Change in mean total CO2eq from one year to the next, in percent. Bars above zero are increases.",
    fr = "Variation du CO₂éq total moyen d'une année à l'autre, en pourcentage. Les barres au-dessus de zéro sont des hausses."),
  fig_cap_delta = list(
    en = "Distribution, across iterations, of the difference between the last and the first year. The dashed lines bound the 95% confidence interval; when it does not include zero, the trend is distinguishable from no change.",
    fr = "Distribution, sur les itérations, de la différence entre la dernière et la première année. Les tirets bornent l'intervalle de confiance à 95 % ; s'il n'inclut pas zéro, la tendance se distingue d'une absence de changement."),
  fig_cap_tornado = list(
    en = "The ten inputs with the largest influence on the selected output. Bar length is the sensitivity coefficient (SRC); bars to the right raise the output, bars to the left lower it. Green: inputs you can improve with better national data. Blue: IPCC coefficients.",
    fr = "Les dix entrées qui influencent le plus la sortie choisie. La longueur de la barre est le coefficient de sensibilité (SRC) ; les barres à droite augmentent la sortie, celles à gauche la diminuent. Vert : entrées améliorables par de meilleures données nationales. Bleu : coefficients IPCC."),
  fig_cap_tornado_year = list(
    en = "The ten inputs with the largest influence on total CO2eq in the latest year. Green: inputs you can improve with better national data. Blue: IPCC coefficients.",
    fr = "Les dix entrées qui influencent le plus le CO₂éq total de la dernière année. Vert : entrées améliorables par de meilleures données nationales. Bleu : coefficients IPCC."),
  fig_cap_tornado_delta = list(
    en = "The ten inputs with the largest influence on the change between the first and the last year. Green: inputs you can improve with better national data. Blue: IPCC coefficients.",
    fr = "Les dix entrées qui influencent le plus la variation entre la première et la dernière année. Vert : entrées améliorables par de meilleures données nationales. Bleu : coefficients IPCC."),
  fig_cap_src_hist = list(
    en = "Simulated distribution of the emissions of each source, one panel per source.",
    fr = "Distribution simulée des émissions de chaque source, un panneau par source."),
  fig_cap_report_tornado = list(
    en = "The ten inputs with the largest influence on total CO2eq. Green: inputs you can improve with better national data. Blue: IPCC coefficients.",
    fr = "Les dix entrées qui influencent le plus le CO₂éq total. Vert : entrées améliorables par de meilleures données nationales. Bleu : coefficients IPCC."),
  fig_cap_input_dens = list(
    en = "Distribution of up to twelve inputs of the first production system, as drawn in the simulation. Use it to check that each input has the shape and range you intended.",
    fr = "Distribution d'au plus douze entrées du premier système de production, telles que tirées dans la simulation. Vérifiez que chaque entrée a la forme et la plage voulues."),
  sens_leg_reducible = list(en = "Input you can improve with national data", fr = "Entrée améliorable par des données nationales"),
  sens_leg_ipcc = list(en = "IPCC coefficient", fr = "Coefficient IPCC"),
  sens_tornado_title = list(en = "Top 10 drivers", fr = "Les 10 principaux facteurs"),
  sens_view_without_suffix = list(en = ", without correlations", fr = ", sans corrélations"),
  res_units_label = list(en = "Show results in", fr = "Afficher les résultats en"),
  res_units_gg = list(en = "Gigagrams (Gg)", fr = "Gigagrammes (Gg)"),
  res_units_t = list(en = "Tonnes (t)", fr = "Tonnes (t)"),
  res_units_both = list(en = "Both", fr = "Les deux"),
  def_search_placeholder = list(en = "Search the definitions (e.g. Ym, margin of error)", fr = "Rechercher dans les définitions (ex. Ym, marge d'erreur)"),
  def_jump_params = list(en = "Parameter definitions", fr = "Définitions des paramètres"),
  def_jump_stats = list(en = "Statistical terms", fr = "Termes statistiques"),
  def_more_hint = list(en = "Click a row to see its IPCC basis, distribution, level, framing and reference.", fr = "Cliquez sur une ligne pour voir sa base IPCC, sa distribution, son niveau, son cadrage et sa référence."),

  res_hist_chart_title = list(en = "Distribution of Total CO2eq Emissions",
                                fr = "Distribution des émissions totales CO₂éq"),
  res_hist_xaxis = list(en = "Total CO2eq (tonnes)", fr = "CO₂éq total (tonnes)"),
  res_hist_yaxis = list(en = "Frequency", fr = "Fréquence"),
  res_hist_outlier_note = list(
    en = "%d of %d iterations beyond chart range",
    fr = "%d itérations sur %d au-delà de la plage du graphique"),
  res_decomp_chart_title = list(
    en = "Uncertainty decomposition (MoE, total CO2eq)",
    fr = "Décomposition de l'incertitude (MoE, CO₂éq total)"
  ),
  res_decomp_yaxis = list(en = "MoE (%)", fr = "MoE (%)"),

  res_cmp_total_co2e = list(en = "Total CO2eq", fr = "CO₂éq total"),
  res_cmp_total_ch4  = list(en = "Total CH4", fr = "CH₄ total"),
  res_cmp_total_n2o  = list(en = "Total N2O", fr = "N₂O total"),
  res_cmp_chart_title = list(
    en = "95% MoE comparison: with vs. without correlations",
    fr = "Comparaison MoE 95 % : avec vs sans corrélations"
  ),

  sens_view_label = list(en = "View:", fr = "Vue :"),

  res_sim_results_h = list(en = "Simulation results", fr = "Résultats de la simulation"),
  res_vb_enteric_ch4_t = list(en = "Enteric CH₄ (t)", fr = "CH₄ entérique (t)"),
  res_vb_manure_ch4_t  = list(en = "Manure CH₄ (t)", fr = "CH₄ du fumier (t)"),
  res_vb_manure_n2o_t  = list(en = "Manure N₂O (t)", fr = "N₂O du fumier (t)"),
  res_vb_pasture_n2o_t = list(en = "Pasture N₂O (t)", fr = "N₂O au pâturage (t)"),
  res_vb_total_moe_pct = list(en = "Total 95% MoE (%)", fr = "MoE 95 % total (%)"),
  res_vb_total_moe_sub = list(
    en = "± half-width of 95% CI / mean: IPCC convention",
    fr = "± demi-largeur IC 95 % / moyenne : convention IPCC"
  ),
  res_vb_direct_indirect = list(en = "Direct + indirect", fr = "Direct + indirect"),

  res_inline_total_co2e = list(en = "Total CO₂eq:", fr = "CO₂éq total :"),
  res_inline_moe = list(en = "95% MoE:", fr = "MoE 95 % :"),
  res_inline_total_ch4 = list(en = "Total CH₄:", fr = "CH₄ total :"),
  res_inline_total_n2o = list(en = "Total N₂O:", fr = "N₂O total :"),

  res_headline_by_cattle_h = list(
    en = "Headline by cattle type (dairy / other)",
    fr = "Synthèse par type de bétail (laitier / autre)"
  ),
  res_headline_by_cattle_note = list(
    en = "One row per cattle_type from the Parameters sheet. Per-source means are inventory-summed across iterations; ± is the 95 % margin of error (MoE).",
    fr = "Une ligne par cattle_type de la feuille Parameters. Les moyennes par source sont sommées sur les itérations ; ± est la marge d'erreur 95 % (MoE)."
  ),
  res_emission_dist_h = list(en = "Emission Distribution (Total CO₂eq)",
                                fr = "Distribution des émissions (CO₂éq total)"),

  res_agg_level_label = list(en = "Aggregation level:", fr = "Niveau d'agrégation :"),
  res_agg_cattle_type = list(en = "Cattle type (dairy / other)",
                                fr = "Type de bétail (laitier / autre)"),
  res_agg_production_system = list(en = "Production system",
                                      fr = "Système de production"),
  res_agg_sub_category = list(en = "Sub-category", fr = "Sous-catégorie"),
  res_agg_level_note = list(en = "Tables below aggregate per-iteration results at this level.",
                              fr = "Les tableaux ci-dessous agrègent les résultats par itération à ce niveau."),

  res_by_system_h = list(en = "By-System Breakdown",
                            fr = "Détail par système"),
  res_by_category_h = list(en = "By Reporting Category (IPCC Table 3.3 layout)",
                              fr = "Par catégorie de rapport (mise en page IPCC Tableau 3.3)"),
  res_by_category_note = list(
    en = "Each row is one IPCC inventory reporting line (group × source). Rows match the granularity used in IPCC Volume 1 Chapter 3 uncertainty reporting.",
    fr = "Chaque ligne est une ligne de rapport d'inventaire IPCC (groupe × source). La granularité correspond à celle des rapports d'incertitude IPCC Volume 1 Chapitre 3."
  ),

  res_vb_trend_slope_short = list(en = "Average change per year", fr = "Variation moyenne par an"),
  res_vb_trend_latest_short = list(en = "Latest year total", fr = "Total de la dernière année"),
  res_vb_trend_yoy_largest = list(en = "Largest one-year change",
                                     fr = "Plus grande variation sur un an"),

  res_trend_yoy_h = list(en = "Year-over-year % change",
                           fr = "Variation interannuelle (%)"),
  res_trend_delta_hist_h = list(
    en = "How certain is the change between the first and last year?",
    fr = "Quelle certitude sur la variation entre la première et la dernière année ?"
  ),
  res_trend_delta_hist_note = list(
    en = "Each bar counts simulation runs by the size of the change in total CO₂eq between the first and last year. The dashed red lines mark the 95% range; the dotted line marks zero. If zero lies inside the range, the inventory cannot tell an increase from a decrease at 95%.",
    fr = "Chaque barre compte les tirages de simulation selon l'ampleur de la variation du CO₂éq total entre la première et la dernière année. Les lignes rouges en tirets marquent la plage à 95 % ; la ligne pointillée marque zéro. Si zéro est dans la plage, l'inventaire ne permet pas de distinguer une hausse d'une baisse à 95 %."
  ),
  res_trend_footer_note = list(
    en = "What drives the uncertainty (latest year, and the change between the first and last year) is on the Sensitivity tab. Word, Excel and CSV reports are on the IPCC Report tab.",
    fr = "Ce qui pilote l'incertitude (dernière année, et variation entre la première et la dernière année) se trouve dans l'onglet Sensibilité. Les rapports Word, Excel et CSV sont dans l'onglet Rapport GIEC."
  ),
  res_trend_plot_title = list(en = "Trend in total CO₂eq emissions (95% CI)",
                                fr = "Tendance des émissions CO₂éq totales (IC 95 %)"),
  res_trend_xaxis_year = list(en = "Inventory year", fr = "Année d'inventaire")
)

# =============================================================================
# QA verdict helper: fetches a translated sprintf template by key
# =============================================================================
# Usage: qa_msg("bounds_order_fail_lo", lo, mu) returns the formatted string
# in the current language. Falls back to English if the key or language
# isn't in .STRINGS. Saves wrapping every QA `add()` call in a manual
# t() + sprintf() pair.
qa_msg <- function(key, ...) {
  tmpl <- t(paste0("qa_msg_", key))
  if (grepl("^\\[\\?", tmpl)) return(tmpl)  # missing key: propagate
  sprintf(tmpl, ...)
}

# =============================================================================
# Parameter definitions (Definitions tab): French translations
# =============================================================================
# Keyed by canonical parameter name. The English versions live in
# PARAM_CATALOGUE$definition (R/utils_template.R) and stay authoritative;
# we only override the displayed `definition` column when .LANG_CURRENT == "fr".
# IPCC codes (BW, MW, Ym, Bo, EF3_PRP, etc.) and table/equation references
# (IPCC Vol.4 Ch.10 Eq 10.X, Table 10.Y, 2019R, …) are kept verbatim: they
# are international identifiers, not translatable text.
.PARAM_DEFINITIONS_FR <- c(
  N            = "Nombre d'animaux dans cette sous-catégorie",
  BW           = "Poids vif moyen des animaux",
  MW           = "Poids vif adulte (mature) des animaux",
  WG           = "Gain de poids quotidien moyen: fixer 0 pour les animaux adultes (non en croissance)",
  Milk         = "Rendement laitier quotidien par vache en lactation (pas la moyenne de la sous-catégorie : l'outil multiplie par pct_pregnant en interne). Fixer 0 pour les sous-catégories qui ne lactent pas.",
  Fat          = "Teneur en matière grasse du lait (% en poids)",
  pct_pregnant = "Fraction des femelles de cette sous-catégorie gestantes pendant l'année, entre 0 et 1, y compris les génisses gestantes n'ayant pas encore vêlé. Pondère Cpregnancy dans l'Éq IPCC 10.13 (NEp) et le terme de rétention de N du lait dans l'Éq 10.33. Ne pondère PAS la lactation : l'Éq 10.8 ne comporte aucun facteur de ce type et la production laitière fournie est déjà une moyenne annuelle par tête. Saisir la fraction gestante, et non la fraction en lactation.",
  DE           = "Énergie digestible en pourcentage de l'énergie brute : plage typique 45-75 %",
  Cfi          = "Coefficient d'énergie d'entretien : dépend du sexe et de l'état de lactation (IPCC Tableau 10.4)",
  Ca           = "Coefficient d'activité pour l'énergie de locomotion : dépend de la situation alimentaire (IPCC Tableau 10.5)",
  C            = "Coefficient de croissance pour l'équation NEg : dépend du sexe et de l'état physiologique (IPCC Éq 10.6)",
  Cp           = "Coefficient de gestation: 0,10 pour les animaux gestants (IPCC Tableau 10.7)",
  hours        = "Heures de travail quotidiennes (Éq. 10.11) : fixer 0 si les animaux ne travaillent pas ; pertinent uniquement lorsque les animaux sont utilisés pour la traction/portage",
  CP           = "Teneur en protéines brutes (CP %) de la ration : utilisée pour estimer l'excrétion d'azote",
  Ym           = "Facteur de conversion en méthane : % de l'énergie brute convertie en méthane (IPCC Tableau 10.12)",
  Bo           = "Capacité maximale de production de CH₄ du fumier (IPCC Tableau 10.16)",
  ASH          = "Teneur en cendres du fumier : valeur IPCC par défaut 0,08 (note de bas de page Éq 10.24)",
  UE           = "Énergie urinaire en fraction de l'énergie brute : valeur IPCC par défaut 0,04 (note de bas de page Éq 10.24)",
  EF3_PRP      = "Facteur d'émission N₂O pour les excréments/urine au pâturage (IPCC Vol.4 Ch.11 Tableau 11.1). Valeur utilisée par l'outil : 0,006 (2019R EF3_PRP,CPP bovins/volailles/porcs, climat humide). Autres options : agrégé 0,004 ; climat sec 0,002 ; 2006 = 0,02.",
  EF4          = "FE N₂O pour le dépôt atmosphérique d'azote (IPCC Vol.4 Ch.11 Tableau 11.3). Valeur utilisée par l'outil : 0,014 (2019R, climat humide, plage 0,011-0,017). Autres options : agrégé 0,010 ; climat sec 0,005 ; 2006 = 0,010.",
  EF5          = "FE N₂O pour le lessivage/ruissellement d'azote (IPCC Vol.4 Ch.11 Tableau 11.3). 2019R EF5 = 0,011 (plage 0,000-0,020), sans désagrégation climatique. 2006 = 0,0075.",
  Frac_GASM_PRP = "Fraction d'azote volatilisée à partir des excréments/urine au pâturage (IPCC Vol.4 Ch.11 Tableau 11.3, FracGASM). 2019R = 0,21 (plage 0,00-0,31) ; 2006 = 0,20.",
  Frac_LEACH_PRP = "Fraction d'azote lessivée à partir du dépôt au pâturage (IPCC Vol.4 Ch.11 Tableau 11.3, FracLEACH-(H)). Valeur utilisée par l'outil : 0,24 (2019R, climat humide, plage 0,01-0,73). Autres options : climat sec = 0 ; 2006 = 0,30.",
  MilkPR       = "Teneur en protéines du lait : alimente le terme N du lait dans l'Éq IPCC Vol.4 Ch.10 10.33 (rétention d'azote pour les bovins, où la conversion 6,38 protéine-laitière-vers-N est définie)",
  Tw           = "Température moyenne quotidienne en hiver (°C) : ajustement Cfi climat froid selon IPCC Vol.4 Ch.10 Éq 10.2 (modifie Cfi de l'Éq 10.3). Laisser vide ou fixer 20 pour désactiver l'ajustement"
)

# Unit strings (French). Most physical units stay identical; only words like
# "head", "fraction", "dimensionless" change.
.PARAM_UNITS_FR <- c(
  N            = "têtes",
  BW           = "kg",
  MW           = "kg",
  WG           = "kg/jour",
  Milk         = "kg/tête/jour",
  Fat          = "%",
  pct_pregnant = "fraction (0-1)",
  DE           = "%",
  Cfi          = "MJ/jour/kg^0,75",
  Ca           = "sans dimension",
  C            = "sans dimension",
  Cp           = "sans dimension",
  hours        = "heures/jour",
  CP           = "%",
  Ym           = "%",
  Bo           = "m3 CH₄/kg VS",
  ASH          = "fraction",
  UE           = "fraction",
  EF3_PRP      = "kg N2O-N/kg N",
  EF4          = "kg N2O-N/kg N",
  EF5          = "kg N2O-N/kg N",
  Frac_GASM_PRP = "fraction",
  Frac_LEACH_PRP = "fraction",
  MilkPR       = "%",
  Tw           = "°C"
)
