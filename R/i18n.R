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
  ),

  # =====================================================================
  # HOME TAB — full content
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

  # "How to use this tool — step by step" card
  workflow_title = list(en = "How to use this tool -- Step by step",
                          fr = "Comment utiliser cet outil — étape par étape"),
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
                              fr = "Examiner les vérifications de qualité automatiques — corriger les échecs et documenter les écarts importants par rapport aux valeurs par défaut IPCC"),
  workflow_row3_tab  = list(en = "Uncertainty", fr = "Incertitude"),
  workflow_row3_what = list(en = "Review and adjust probability distributions and uncertainty ranges for each parameter",
                              fr = "Examiner et ajuster les distributions de probabilité et les plages d'incertitude de chaque paramètre"),
  workflow_row4_tab  = list(en = "Correlations", fr = "Corrélations"),
  workflow_row4_what = list(en = "(Optional) Upload population time series or manually define correlations between activity data",
                              fr = "(Facultatif) Téléverser des séries temporelles de populations ou définir manuellement les corrélations entre données d'activité"),
  workflow_row5_tab  = list(en = "Simulate", fr = "Simulation"),
  workflow_row5_what = list(en = "Choose number of iterations, GWP version, and click Run — results (emission distributions, 95% CI, decomposition) appear in the same tab",
                              fr = "Choisir le nombre d'itérations, la version de GWP, puis cliquer sur Lancer — les résultats (distributions d'émissions, IC à 95 %, décomposition) apparaissent dans le même onglet"),
  workflow_row6_tab  = list(en = "Sensitivity", fr = "Sensibilité"),
  workflow_row6_what = list(en = "Identify which parameters contribute most to uncertainty (tornado chart)",
                              fr = "Identifier les paramètres qui contribuent le plus à l'incertitude (graphique tornade)"),
  workflow_row7_tab  = list(en = "IPCC Report", fr = "Rapport IPCC"),
  workflow_row7_what = list(en = "Download results formatted as IPCC Table 3.3 for your inventory submission",
                              fr = "Télécharger les résultats au format IPCC Tableau 3.3 pour votre soumission d'inventaire"),

  # Quick-start info panel (HTML with embedded <strong> for tab references)
  quick_start_html = list(
    en = "<strong>Quick start: </strong>To try the tool immediately, go to <strong>1. Data Input</strong>, select 'Country X (hypothetical dairy)', then go to <strong>5. Simulate</strong> and click 'Run Monte Carlo Simulation'.",
    fr = "<strong>Démarrage rapide : </strong>Pour essayer l'outil immédiatement, allez dans <strong>1. Données</strong>, sélectionnez « Pays X (laitier hypothétique) », puis allez dans <strong>5. Simulation</strong> et cliquez sur « Lancer la simulation Monte Carlo »."
  ),

  btn_goto_resources = list(en = "Methodology, user guide & downloads →",
                              fr = "Méthodologie, guide utilisateur & téléchargements →"),

  # "Before you start" card
  before_you_will_need = list(en = "You will need:",
                                fr = "Ce dont vous aurez besoin :"),
  before_li1 = list(
    en = "A Tier 2 input dataset for the inventory year(s) you wish to assess: animal sub-categories with population, body weights, feed quality, and manure-management shares.",
    fr = "Un jeu de données d'entrée Niveau 2 pour l'année (ou les années) d'inventaire à évaluer : sous-catégories animales avec population, poids vifs, qualité de l'alimentation et répartition de la gestion du fumier."
  ),
  before_li2_html = list(
    en = "A defensible estimate of the uncertainty in each input (typically ±% half-width of the 95 % CI, or lower / upper bounds for asymmetric parameters). The tool <strong>does not</strong> estimate input uncertainties for you.",
    fr = "Une estimation défendable de l'incertitude de chaque entrée (généralement la demi-largeur ±% de l'IC à 95 %, ou les bornes inférieure/supérieure pour les paramètres asymétriques). L'outil <strong>n'estime pas</strong> les incertitudes d'entrée à votre place."
  ),
  before_li3 = list(
    en = "Optional but recommended: multi-year time series of activity data, used to compute correlations automatically.",
    fr = "Facultatif mais recommandé : séries temporelles pluriannuelles de données d'activité, utilisées pour calculer automatiquement les corrélations."
  ),
  before_not_do_label = list(en = "What this tool does NOT do:",
                                fr = "Ce que cet outil NE fait PAS :"),
  not_do_li1 = list(
    en = "It does not collect data or estimate input uncertainties — those must be supplied by the user.",
    fr = "Il ne collecte pas les données et n'estime pas les incertitudes d'entrée — celles-ci doivent être fournies par l'utilisateur."
  ),
  not_do_li2 = list(
    en = "It does not produce Tier 1 estimates and is not designed for uncertainty analysis of country-specific Tier 2 methods — the IPCC Tier 2 equation chain is required.",
    fr = "Il ne produit pas d'estimations Niveau 1 et n'est pas conçu pour l'analyse d'incertitude des méthodes Niveau 2 spécifiques à un pays — l'enchaînement d'équations IPCC Niveau 2 est requis."
  ),
  not_do_li3 = list(
    en = "It does not validate your country's IPCC categorisation choices — sub-category structure is the user's responsibility.",
    fr = "Il ne valide pas les choix de catégorisation IPCC de votre pays — la structure des sous-catégories relève de l'utilisateur."
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
    en = "Monte Carlo: Approach 2 from IPCC 2006 Vol 1 Ch 3. Correlations are sampled via the rank-correlation-preserving restricted-pairing procedure per IPCC Vol 1 Ch 3 §3.2.3.2 — the same method is used for every correlated path (time-series, preset, manual, structural defaults).",
    fr = "Monte Carlo : Approche 2 de l'IPCC 2006 Vol 1 Ch 3. Les corrélations sont échantillonnées via la procédure de pairage restreint préservant les corrélations de rang (IPCC Vol 1 Ch 3 §3.2.3.2) — la même méthode est utilisée pour chaque voie corrélée (séries temporelles, préréglée, manuelle, valeurs par défaut structurelles)."
  ),
  resources_sensitivity = list(
    en = "Sensitivity: Standardised regression coefficients (SRC) and partial rank correlation (PRCC) on the sampled inputs vs each output.",
    fr = "Sensibilité : coefficients de régression standardisés (SRC) et corrélation partielle des rangs (PRCC) sur les entrées échantillonnées par rapport à chaque sortie."
  ),
  btn_open_methodology = list(en = "Open full methodology (PDF)",
                                fr = "Ouvrir la méthodologie complète (PDF)"),
  btn_open_userguide = list(en = "Open user guide (PDF)",
                              fr = "Ouvrir le guide utilisateur (PDF)"),

  card_useful_resources = list(en = "Useful resources",
                                 fr = "Ressources utiles"),
  resources_method_foundations = list(en = "Methodological foundations",
                                        fr = "Fondements méthodologiques"),
  resources_method_intro = list(
    en = "The six IPCC chapters that underpin the calculations and uncertainty methodology of this tool. Links open the official PDFs on the IPCC-NGGIP site.",
    fr = "Les six chapitres IPCC qui sous-tendent les calculs et la méthodologie d'incertitude de cet outil. Les liens ouvrent les PDF officiels sur le site IPCC-NGGIP."
  ),
  resources_vol4_livestock_label = list(en = "Vol. 4 (AFOLU) — Livestock & Manure Management:",
                                          fr = "Vol. 4 (AFOLU) — Élevage & gestion du fumier :"),
  resources_vol4_livestock_2006 = list(
    en = "IPCC 2006 Guidelines — Vol. 4, Chapter 10 (Emissions from Livestock and Manure Management)",
    fr = "Lignes directrices IPCC 2006 — Vol. 4, Chapitre 10 (Émissions de l'élevage et de la gestion du fumier)"
  ),
  resources_vol4_livestock_2019 = list(
    en = "2019 Refinement — Vol. 4, Chapter 10 (Updated livestock equations, MMS table 10.17, Bo table 10.16a, Ym table 10.12)",
    fr = "Raffinement 2019 — Vol. 4, Chapitre 10 (équations mises à jour, tableau MMS 10.17, Bo tableau 10.16a, Ym tableau 10.12)"
  ),
  resources_vol4_soils_label = list(en = "Vol. 4 (AFOLU) — Managed Soils (N₂O from soils, including PRP):",
                                       fr = "Vol. 4 (AFOLU) — Sols gérés (N₂O des sols, y compris PRP) :"),
  resources_vol4_soils_2006 = list(
    en = "IPCC 2006 Guidelines — Vol. 4, Chapter 11 (N₂O Emissions from Managed Soils, CO₂ from Lime/Urea)",
    fr = "Lignes directrices IPCC 2006 — Vol. 4, Chapitre 11 (Émissions de N₂O des sols gérés, CO₂ chaux/urée)"
  ),
  resources_vol4_soils_2019 = list(
    en = "2019 Refinement — Vol. 4, Chapter 11 (Updated EF3_PRP table 11.1, EF4/EF5/FracGASM/FracLEACH-(H) table 11.3)",
    fr = "Raffinement 2019 — Vol. 4, Chapitre 11 (EF3_PRP mis à jour tableau 11.1, EF4/EF5/FracGASM/FracLEACH-(H) tableau 11.3)"
  ),
  resources_vol1_uncert_label = list(en = "Vol. 1 — Uncertainty methodology (Approach 1 vs Approach 2):",
                                       fr = "Vol. 1 — Méthodologie d'incertitude (Approche 1 vs Approche 2) :"),
  resources_vol1_uncert_2006 = list(
    en = "IPCC 2006 Guidelines — Vol. 1, Chapter 3 (Uncertainties)",
    fr = "Lignes directrices IPCC 2006 — Vol. 1, Chapitre 3 (Incertitudes)"
  ),
  resources_vol1_uncert_2019 = list(
    en = "2019 Refinement — Vol. 1, Chapter 3 (Uncertainties; including §3.2.2.4 on temporal correlation of EFs)",
    fr = "Raffinement 2019 — Vol. 1, Chapitre 3 (Incertitudes ; y compris §3.2.2.4 sur la corrélation temporelle des FE)"
  ),
  resources_ad_guidance = list(en = "Activity data guidance",
                                 fr = "Guides sur les données d'activité"),
  resources_fao_ladg = list(en = "FAO Livestock Activity Data Guidance (L-ADG)",
                              fr = "Guide FAO sur les données d'activité d'élevage (L-ADG)"),
  resources_penman = list(
    en = "Penman et al. (2000) — Good Practice Guidance and Uncertainty Management in National Greenhouse Gas Inventories",
    fr = "Penman et al. (2000) — Guide des bonnes pratiques et gestion de l'incertitude dans les inventaires nationaux de gaz à effet de serre"
  ),
  resources_dist_mc_title = list(en = "Distributions and Monte Carlo references",
                                   fr = "Distributions et références Monte Carlo"),
  resources_frey_rhodes = list(
    en = "Frey & Rhodes (1998) — Characterizing, simulating, and analyzing variability and uncertainty",
    fr = "Frey & Rhodes (1998) — Caractérisation, simulation et analyse de la variabilité et de l'incertitude"
  ),
  resources_gpg_2000 = list(
    en = "IPCC GPG 2000 §6 — Quantifying uncertainties in practice (Approach 1 vs Approach 2)",
    fr = "IPCC GPG 2000 §6 — Quantifier les incertitudes en pratique (Approche 1 vs Approche 2)"
  ),
  resources_learning_title = list(en = "Learning resources",
                                    fr = "Ressources de formation"),
  resources_fao_elearn_uncert = list(en = "FAO e-learning — Assessing uncertainty in the land sector",
                                       fr = "Cours en ligne FAO — Évaluer l'incertitude dans le secteur des terres"),
  resources_fao_elearn_tier2 = list(en = "FAO e-learning — Tier 2 inventory for livestock",
                                      fr = "Cours en ligne FAO — Inventaire Niveau 2 pour l'élevage"),
  resources_unfccc_webinar = list(en = "UNFCCC webinar notes — Uncertainty analysis for GHG inventories",
                                    fr = "Notes des webinaires CCNUCC — Analyse d'incertitude pour les inventaires GES"),
  resources_case_studies = list(en = "Case studies",
                                  fr = "Études de cas"),
  resources_monni = list(
    en = "Monni et al. (2007) — Uncertainty in agricultural CH₄ and N₂O emissions from Finland",
    fr = "Monni et al. (2007) — Incertitude des émissions agricoles de CH₄ et N₂O en Finlande"
  ),
  resources_karimi = list(
    en = "Karimi-Zindashty et al. (2012) — Sources of uncertainty in livestock emission inventories: Canadian case study",
    fr = "Karimi-Zindashty et al. (2012) — Sources d'incertitude dans les inventaires d'émissions d'élevage : étude de cas canadienne"
  ),
  resources_milne = list(
    en = "Milne et al. (2014) — Estimating uncertainty in pasture-based dairy CH₄ emissions",
    fr = "Milne et al. (2014) — Estimation de l'incertitude des émissions de CH₄ laitières au pâturage"
  ),
  resources_more_to_come = list(en = "Additional national-inventory examples to be added.",
                                  fr = "D'autres exemples d'inventaires nationaux seront ajoutés."),

  # =====================================================================
  # AI TRANSLATOR CARD (wrapper UI only — chat content stays English)
  # =====================================================================

  ai_card_title = list(
    en = "AI Translator — turn your raw cattle data into the tool's template",
    fr = "Traducteur IA — convertir vos données brutes en modèle de l'outil"
  ),
  ai_intro_part1 = list(en = "Drop in your raw cattle data file (.xlsx or .csv). The AI works in three short steps:",
                          fr = "Déposez votre fichier de données brutes (.xlsx ou .csv). L'IA travaille en trois étapes courtes :"),
  ai_step1_label = list(en = "(1) Explore", fr = "(1) Explorer"),
  ai_step1_body  = list(en = "— it reads every sheet and reports back what it found (which parameters live where, units, ambiguities).",
                          fr = "— elle lit chaque feuille et rapporte ce qu'elle a trouvé (quels paramètres sont où, unités, ambiguïtés)."),
  ai_step2_label = list(en = "(2) Clarify", fr = "(2) Clarifier"),
  ai_step2_body  = list(en = "— you answer its questions in plain English.",
                          fr = "— vous répondez à ses questions en anglais simple."),
  ai_step3_label = list(en = "(3) Emit", fr = "(3) Générer"),
  ai_step3_body  = list(en = "— click Produce template now and download the .xlsx in the exact format the Data Input tab expects.",
                          fr = "— cliquez sur « Générer le modèle » et téléchargez le .xlsx au format attendu par l'onglet Données."),
  ai_intro_signin_note = list(en = "No setup — sign in once with your email and you're ready.",
                                fr = "Aucune configuration — connectez-vous une fois avec votre e-mail, c'est prêt."),
  ai_find_out_more = list(en = "Find out more", fr = "En savoir plus"),
  ai_fr_chat_note = list(
    en = "",
    fr = "Note : l'IA répond en anglais et utilise les codes IPCC standards. Vous pouvez lui écrire en français — elle comprend, mais répond en anglais."
  ),

  ai_signed_in = list(en = "Signed in:", fr = "Connecté :"),
  ai_upload_label = list(en = "1.  Upload your raw cattle data",
                           fr = "1.  Téléverser vos données brutes"),
  ai_upload_hint = list(
    en = " (.xlsx or .csv) — the AI reads it and starts the conversation.",
    fr = " (.xlsx ou .csv) — l'IA le lit et entame la conversation."
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
    en = "Stop the AI generation and reload the page? Your conversation is saved — you will not lose it.",
    fr = "Arrêter la génération et recharger la page ? Votre conversation est sauvegardée — vous ne la perdrez pas."
  ),
  tip_ai_stop = list(
    en = "Use this if the AI is generating a template and the page is unresponsive. Reloads the page; the OpenAI call is abandoned. Your conversation history is preserved.",
    fr = "Utilisez cela si l'IA génère un modèle et que la page ne répond plus. Recharge la page ; l'appel OpenAI est abandonné. Votre historique est préservé."
  ),
  btn_ai_download = list(en = "Download template (.xlsx)",
                           fr = "Télécharger le modèle (.xlsx)"),
  ai_spinner_default = list(
    en = "Translator is working — calling the AI, waiting for the first reply…",
    fr = "Le traducteur travaille — appel de l'IA, attente de la première réponse…"
  ),
  ai_empty_messages = list(en = "No messages yet. Upload a file or send a message to begin.",
                             fr = "Aucun message pour le moment. Téléversez un fichier ou envoyez un message pour commencer."),

  # Magic-link sign-in (Resources tab — AI translator)
  auth_signin_title = list(en = "Sign in to the AI translator",
                            fr = "Se connecter au traducteur IA"),
  auth_signin_body = list(
    en = "Enter your email address. We will send you a one-time sign-in link. No password required. CGIAR email addresses are approved automatically; other addresses are reviewed manually by the administrator.",
    fr = "Entrez votre adresse e-mail. Nous vous enverrons un lien de connexion à usage unique. Pas de mot de passe. Les adresses CGIAR sont approuvées automatiquement ; les autres sont examinées par l'administrateur."
  ),
  btn_auth_send_link = list(en = "Send sign-in link",
                              fr = "Envoyer le lien de connexion"),

  # =====================================================================
  # DATA INPUT TAB
  # =====================================================================

  card_analysis_mode = list(en = "Choose your analysis mode",
                              fr = "Choisir votre mode d'analyse"),
  analysis_mode_single = list(
    en = "Single year — quantify uncertainty in one inventory year",
    fr = "Année unique — quantifier l'incertitude d'une année d'inventaire"
  ),
  tip_analysis_mode_single = list(
    en = "Use this mode to estimate the uncertainty for one specific inventory year. All parameters are sampled independently for each iteration. This is the most common mode and is sufficient for IPCC Table 3.3 reporting. Choose Trend if you also want to assess whether emission changes over time are statistically significant.",
    fr = "Mode pour estimer l'incertitude d'une année d'inventaire spécifique. Tous les paramètres sont échantillonnés indépendamment à chaque itération. C'est le mode le plus courant et suffisant pour le rapport IPCC Tableau 3.3. Choisissez Tendance si vous voulez aussi évaluer si les variations d'émissions dans le temps sont statistiquement significatives."
  ),
  analysis_mode_trend = list(
    en = "Trend — compare uncertainty across multiple years",
    fr = "Tendance — comparer l'incertitude entre plusieurs années"
  ),
  tip_analysis_mode_trend = list(
    en = "Use this mode when you have activity data for several inventory years and want to assess whether the trend (change over time) is statistically distinguishable from zero. IPCC Vol 1 Ch 3 §3.7 recommends reporting trend uncertainty for inventory series. Requires a Parameter_TimeSeries sheet in your upload template, or use one of the built-in example datasets.",
    fr = "Mode quand vous disposez de données d'activité pour plusieurs années et voulez évaluer si la tendance est statistiquement distinguable de zéro. IPCC Vol 1 Ch 3 §3.7 recommande de rapporter l'incertitude de tendance pour les séries d'inventaire. Nécessite une feuille Parameter_TimeSeries dans votre modèle, ou utilisez un jeu d'exemple intégré."
  ),
  analysis_mode_warning = list(
    en = "Selection required: pick Single year or Trend before moving on. The Run button on Tab 5 will block until a mode is chosen.",
    fr = "Sélection requise : choisissez Année unique ou Tendance avant de continuer. Le bouton Lancer de l'onglet 5 sera bloqué tant qu'un mode n'est pas choisi."
  ),
  trend_explanation = list(
    en = "What 'Trend' does in this tool: a full Monte Carlo uncertainty run is performed independently for every year present in your time-series upload, and the uncertainty on the trend itself is taken as the distribution of (Year_N − Year_1) — the absolute change in CO₂eq between the last and first year.",
    fr = "Ce que fait « Tendance » dans cet outil : un calcul Monte Carlo complet est exécuté indépendamment pour chaque année présente dans votre téléversement de séries temporelles, et l'incertitude sur la tendance elle-même est prise comme la distribution de (Année_N − Année_1) — le changement absolu en CO₂éq entre la dernière et la première année."
  ),
  trend_ipcc_alignment = list(
    en = "IPCC alignment: IPCC 2006 Vol.1 Ch.3 §3.7 (“Uncertainty in trends”) defines the trend as the change between a",
    fr = "Alignement IPCC : IPCC 2006 Vol.1 Ch.3 §3.7 (« Incertitude des tendances ») définit la tendance comme le changement entre une"
  ),
  trend_base_year = list(en = "base year", fr = "année de base"),
  trend_current_year = list(en = "current year", fr = "année courante"),
  trend_explanation_2 = list(
    en = ". The first / last years of the time series you upload are used as those base and current years respectively. §3.7 covers both Approach 1 (error-propagation, Eq. 3.1–3.2) and Approach 2 (Monte Carlo) for the trend; this tool implements the Approach 2 version. Use 'Trend' if you have multi-year data; use 'Single year' for a one-off uncertainty estimate.",
    fr = ". La première / dernière année de la série temporelle que vous téléversez sont utilisées comme année de base et courante respectivement. §3.7 couvre à la fois l'Approche 1 (propagation d'erreur, Éq. 3.1–3.2) et l'Approche 2 (Monte Carlo) pour la tendance ; cet outil implémente la version Approche 2. Choisissez « Tendance » si vous avez des données pluriannuelles ; « Année unique » pour une estimation ponctuelle."
  ),

  info_data_input = list(
    en = "Select an example country dataset from the dropdown, or upload your own data using the Excel template. The parameter table on the right shows the loaded data — you can click on any cell to edit values directly. Check the validation panel at the bottom left to ensure your data is complete and valid before proceeding to the next tab.",
    fr = "Sélectionnez un jeu de données d'exemple dans le menu déroulant, ou téléversez vos propres données avec le modèle Excel. La table des paramètres à droite montre les données chargées — vous pouvez cliquer sur n'importe quelle cellule pour modifier directement. Vérifiez le panneau de validation en bas à gauche pour vous assurer que vos données sont complètes et valides avant de passer à l'onglet suivant."
  ),
  what_to_do_label = list(en = "What to do:", fr = "Marche à suivre :"),

  data_source_h = list(en = "Data Source", fr = "Source des données"),
  country_label = list(en = "Country / Example Data", fr = "Pays / données d'exemple"),
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
    en = " Pick an IPCC version above first — then these buttons unlock.",
    fr = " Choisissez d'abord une version IPCC ci-dessus — les boutons se débloqueront."
  ),
  ai_inline_promo_title = list(en = " Don't have the template filled yet?",
                                  fr = " Vous n'avez pas encore rempli le modèle ?"),
  ai_inline_promo_body_pre = list(en = "Use the AI Translator on the ",
                                    fr = "Utilisez le traducteur IA sur la "),
  ai_inline_promo_body_link = list(en = "AI Translator card on the Resources tab",
                                     fr = "carte Traducteur IA de l'onglet Ressources"),
  ai_inline_promo_body_post = list(en = " — upload your raw data file and the AI produces a ready-to-upload .xlsx.",
                                     fr = " — téléversez votre fichier brut et l'IA produit un .xlsx prêt à l'emploi."),
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
    en = "After loading data, review these automated quality checks. Each row flags a specific check for one parameter.",
    fr = "Après le chargement des données, examinez ces vérifications de qualité automatiques. Chaque ligne signale une vérification pour un paramètre."
  ),
  qa_status_missing = list(en = "Missing", fr = "Manquant"),
  qa_status_fail = list(en = "Fail", fr = "Échec"),
  qa_status_warn = list(en = "Warn", fr = "Attention"),
  qa_status_info = list(en = "Info", fr = "Info"),
  qa_status_pass = list(en = "Pass", fr = "OK"),
  qa_missing_desc = list(en = " — the parameter was not in your upload and was auto-filled from the IPCC default. Verify or replace with country-specific data.",
                            fr = " — le paramètre n'était pas dans votre téléversement et a été rempli automatiquement avec la valeur IPCC par défaut. Vérifiez ou remplacez par des données nationales."),
  qa_fail_desc = list(en = " — the value or bounds will likely cause an error in the simulation.",
                        fr = " — la valeur ou les bornes provoqueront probablement une erreur dans la simulation."),
  qa_warn_desc = list(en = " — the value is unusual compared with IPCC defaults or Penman/Monni uncertainty references. Investigate and document.",
                        fr = " — la valeur est inhabituelle par rapport aux valeurs IPCC par défaut ou aux références d'incertitude Penman/Monni. À investiguer et documenter."),
  qa_info_desc = list(en = " — informational only. Typically for emission factor parameters (EF3, EF4, EF5, Frac_*) where country-specific overrides are expected and the IPCC benchmark is a Monni-2007 / Penman-2000 mid-point, not a fixed table value. No action required unless the deviation is very large.",
                        fr = " — informatif seulement. Typiquement pour les facteurs d'émission (EF3, EF4, EF5, Frac_*) où des valeurs nationales spécifiques sont attendues et la référence IPCC est un point moyen Monni-2007 / Penman-2000, pas une valeur de tableau fixe. Aucune action requise sauf écart très important."),
  qa_pass_desc = list(en = " — check satisfied.", fr = " — vérification satisfaite."),
  qa_fix_fails = list(en = "Fix any ", fr = "Corrigez tous les "),
  qa_before_sim = list(en = " before running the simulation. ",
                         fr = " avant de lancer la simulation. "),
  qa_warnings_advisory = list(en = " are advisory — document your justification for large deviations from IPCC defaults.",
                                fr = " sont indicatifs — documentez votre justification pour les écarts importants par rapport aux valeurs IPCC par défaut."),
  qa_autofilled_label = list(en = "Auto-filled parameters:",
                                fr = "Paramètres remplis automatiquement :"),
  qa_autofilled_intro = list(en = "If any parameters were absent from your upload, an ",
                                fr = "Si des paramètres étaient absents de votre téléversement, un panneau "),
  qa_autofilled_panel_label = list(en = "Auto-filled parameters",
                                      fr = "Paramètres remplis automatiquement"),
  qa_autofilled_outro = list(en = " panel appears above the results table showing which values were substituted from IPCC defaults. Review these and replace with country-specific data in your template where possible.",
                                fr = " apparaît au-dessus de la table de résultats indiquant quelles valeurs ont été substituées par les valeurs IPCC par défaut. Examinez-les et remplacez-les par des données nationales lorsque possible."),
  qa_summary_h = list(en = "Summary", fr = "Résumé"),
  qa_checks_run = list(
    en = "Checks run: bounds order, non-negative bounds, valid ranges (DE_pct, Ym_pct, fractions), distribution suitability (beta/lognormal/tnorm_0_1), benchmark deviation vs. IPCC defaults (>50% = warn, >200% = fail), and asymmetric-distribution warning for EF3/EF4/EF5/Frac_LEACH.",
    fr = "Vérifications : ordre des bornes, bornes non négatives, plages valides (DE_pct, Ym_pct, fractions), adéquation des distributions (beta/lognormal/tnorm_0_1), écart par rapport aux valeurs IPCC par défaut (>50 % = avertissement, >200 % = échec), et avertissement de distribution asymétrique pour EF3/EF4/EF5/Frac_LEACH."
  ),
  qa_results_h = list(en = "QA/QC Results", fr = "Résultats QA/QC"),

  # =====================================================================
  # UNCERTAINTY TAB
  # =====================================================================

  info_unc_what = list(
    en = "Review and adjust each parameter's probability distribution and uncertainty range. Click any cell in the table below to edit the distribution type (normal, lognormal, beta, triangular, pert, uniform, constant), the uncertainty percentage, or the lower/upper bounds.",
    fr = "Examinez et ajustez la distribution de probabilité et la plage d'incertitude de chaque paramètre. Cliquez sur n'importe quelle cellule du tableau ci-dessous pour modifier le type de distribution (normal, lognormal, beta, triangulaire, pert, uniforme, constant), le pourcentage d'incertitude ou les bornes inférieure/supérieure."
  ),
  info_unc_triangular_label = list(en = "Note on triangular distributions:",
                                      fr = "Note sur les distributions triangulaires :"),
  info_unc_triangular_body = list(
    en = "triangular is most often used when only the minimum, most-likely (mode), and maximum are known. The tool treats lower/upper as absolute min/max, not 95% CI bounds — for triangular, those are usually the same. If you have a 95% CI but want a triangular shape, use PERT instead (PERT uses the 95% bounds and a most-likely value).",
    fr = "La distribution triangulaire est utilisée lorsque seuls le minimum, le mode et le maximum sont connus. L'outil traite lower/upper comme min/max absolus, pas comme bornes IC 95 % — pour la triangulaire, ces valeurs sont en général identiques. Si vous avez un IC 95 % mais voulez une forme triangulaire, utilisez plutôt PERT (PERT utilise les bornes 95 % et un mode)."
  ),
  info_unc_quickset_label = list(en = "Quick-set buttons", fr = "Boutons d'application rapide"),
  info_unc_quickset_body = list(
    en = " at the bottom of the table apply common settings to all parameters of one type (e.g. 'Set all activity data to Normal ±15%').",
    fr = " en bas du tableau appliquent des réglages communs à tous les paramètres d'un même type (par exemple « Mettre toutes les données d'activité en Normal ±15 % »)."
  ),
  unc_table_h = list(en = "Distribution & Uncertainty Specification",
                       fr = "Spécification de distribution et d'incertitude"),
  quickset_undo_note = list(
    en = "Click a preset to apply; click the same button again to undo and restore your previous values.",
    fr = "Cliquez sur un préréglage pour l'appliquer ; cliquez à nouveau sur le même bouton pour annuler et restaurer vos valeurs précédentes."
  ),

  # =====================================================================
  # CORRELATIONS TAB
  # =====================================================================

  info_corr_about_label = list(en = "What is this page about?", fr = "De quoi parle cette page ?"),
  info_corr_about_body = list(
    en = "Real-world uncertainties don't usually live in separate boxes. If your body-weight estimate is off because the census missed some animals, your population estimate is probably off too. Telling the tool which parameters move together — when you have evidence — gives a more honest uncertainty range. If you don't have evidence, leave everything on \"No correlations\": that gives a conservative, defensible answer.",
    fr = "Les incertitudes du monde réel ne vivent pas dans des compartiments séparés. Si votre estimation de poids vif est biaisée parce que le recensement a manqué des animaux, votre estimation de population l'est probablement aussi. Indiquer à l'outil quels paramètres bougent ensemble — lorsque vous avez des preuves — donne une plage d'incertitude plus honnête. Sans preuves, laissez tout sur « Pas de corrélations » : cela donne une réponse prudente et défendable."
  ),
  info_corr_quickguide = list(en = "Quick guide — which option do I pick?",
                                fr = "Guide rapide — quelle option choisir ?"),
  info_corr_q1 = list(en = "Do you have ≥5 years of national time-series data in your upload? → ",
                        fr = "Avez-vous ≥5 années de séries temporelles nationales dans votre téléversement ? → "),
  info_corr_q1_ans = list(en = "From template (auto, time-series)",
                            fr = "Depuis le modèle (auto, séries temporelles)"),
  info_corr_q2 = list(
    en = "No time series, but you want to capture well-known biological linkages (BW ↔ MW, Milk ↔ Fat, DE ↔ Ym, …)? → ",
    fr = "Pas de séries temporelles, mais vous voulez capturer des liens biologiques bien connus (BW ↔ MW, Milk ↔ Fat, DE ↔ Ym, …) ? → "
  ),
  info_corr_q2_ans = list(en = "Structural defaults (expert-elicited)",
                            fr = "Valeurs structurelles par défaut (jugement d'expert)"),
  info_corr_q3 = list(en = "You have your own correlation matrix from a study or expert elicitation? → ",
                        fr = "Vous avez votre propre matrice de corrélation à partir d'une étude ou d'un jugement d'expert ? → "),
  info_corr_q3_ans = list(en = "Advanced — manual entry",
                            fr = "Avancé — saisie manuelle"),
  info_corr_q4 = list(en = "None of the above? → leave ",
                        fr = "Aucune des options ci-dessus ? → laissez "),
  info_corr_no = list(en = "No correlations",
                        fr = "Pas de corrélations"),
  info_corr_q4_post = list(en = " (the default; conservative and defensible).",
                              fr = " (par défaut ; prudent et défendable)."),

  card_ad_corr_h = list(en = "Activity Data Correlations",
                          fr = "Corrélations des données d'activité"),
  ai_find_out_more_long = list(en = "Find out more", fr = "En savoir plus"),
  info_ad_corr = list(
    en = "Activity-data correlations describe how your input parameters move together. If you have a multi-year ",
    fr = "Les corrélations des données d'activité décrivent comment vos paramètres d'entrée bougent ensemble. Si vous disposez d'une feuille pluriannuelle "
  ),
  info_ad_corr_post = list(
    en = " sheet in your upload, the tool can learn the relationships from your own data. If not, pick a preset or skip.",
    fr = " dans votre téléversement, l'outil peut apprendre les relations à partir de vos propres données. Sinon, choisissez un préréglage ou ignorez."
  ),
  info_struct_defaults_label = list(en = "Structural defaults (expert-elicited):",
                                       fr = "Valeurs structurelles par défaut (jugement d'expert) :"),
  info_struct_defaults_body = list(
    en = "applies a sparse correlation matrix with seven well-documented structural pairs (BW ↔ MW, BW ↔ WG, Milk ↔ Fat, Milk ↔ BW, Milk ↔ DE, DE ↔ CP, DE ↔ Ym).",
    fr = "applique une matrice de corrélation creuse avec sept paires structurelles bien documentées (BW ↔ MW, BW ↔ WG, Milk ↔ Fat, Milk ↔ BW, Milk ↔ DE, DE ↔ CP, DE ↔ Ym)."
  ),
  info_struct_defaults_note = list(
    en = "Note: these values reflect documented biological/statistical relationships from the IPCC equations and the livestock literature — they are not IPCC-published correlation coefficients.",
    fr = "Note : ces valeurs reflètent des relations biologiques/statistiques documentées issues des équations IPCC et de la littérature sur l'élevage — ce ne sont pas des coefficients de corrélation publiés par l'IPCC."
  ),
  info_struct_defaults_tail = list(
    en = " All other pairs are zero. Hover any non-zero cell in the heatmap for the per-pair source citation; full provenance and revision history are in the Methodology document.",
    fr = " Toutes les autres paires sont à zéro. Survolez une cellule non nulle de la carte de chaleur pour voir la citation par paire ; la provenance complète et l'historique de révision sont dans le document de méthodologie."
  ),
  info_manual_label = list(en = "Advanced — manual matrix entry.",
                              fr = "Avancé — saisie manuelle de la matrice."),
  info_manual_body = list(
    en = "Upload a CSV with parameter names as both column headers and the first column. Values must be in [-1, 1] with the diagonal = 1. Don't write the matrix from scratch — download one of the templates below, edit cells in Excel, save as CSV, and re-upload.",
    fr = "Téléversez un CSV avec les noms de paramètres comme en-têtes de colonnes et première colonne. Les valeurs doivent être dans [-1, 1] avec la diagonale = 1. N'écrivez pas la matrice à partir de zéro — téléchargez l'un des modèles ci-dessous, modifiez les cellules dans Excel, enregistrez en CSV et téléversez à nouveau."
  ),
  info_manual_zero_label = list(en = "Missing parameters are assumed to have zero correlation:",
                                   fr = "Les paramètres manquants sont supposés avoir une corrélation nulle :"),
  info_manual_zero_body = list(
    en = "any parameter whose row/column is absent from the uploaded matrix (or whose name doesn't match the canonical list) is treated as independent of every other parameter — the simulation runs but no correlation is applied for that parameter.",
    fr = "tout paramètre dont la ligne/colonne est absente de la matrice téléversée (ou dont le nom ne correspond pas à la liste canonique) est traité comme indépendant — la simulation tourne mais aucune corrélation n'est appliquée à ce paramètre."
  ),
  card_ef_corr_h = list(en = "Coefficient Correlations (per-head EF inputs)",
                          fr = "Corrélations des coefficients (entrées du FE par tête)"),
  info_ef_corr = list(
    en = "Emission factors can share systematic bias if they come from the same measurement literature. The IPCC default is to treat them as independent. Pick block-structured if you suspect one literature is biased — for example, all your energy-equation coefficients come from the same regional database.",
    fr = "Les facteurs d'émission peuvent partager un biais systématique s'ils proviennent de la même littérature de mesure. La valeur IPCC par défaut les traite comme indépendants. Choisissez « par blocs » si vous suspectez qu'une littérature est biaisée — par exemple, si tous vos coefficients d'équation énergétique viennent de la même base régionale."
  ),

  # =====================================================================
  # SIMULATE TAB
  # =====================================================================

  info_simulate = list(
    en = "Configure simulation settings on the left, then click 'Run Monte Carlo Simulation' at the bottom of the left-hand panel. The tool will sample all parameters from their distributions and run the IPCC equation chain thousands of times. 10,000+ iterations recommended; check convergence by re-running with a different seed (1,000 is fine for quick testing).",
    fr = "Configurez les paramètres de simulation à gauche, puis cliquez sur « Lancer la simulation Monte Carlo » en bas du panneau de gauche. L'outil échantillonnera tous les paramètres selon leurs distributions et exécutera la chaîne d'équations IPCC des milliers de fois. 10 000+ itérations recommandées ; vérifiez la convergence en relançant avec une autre graine (1 000 suffit pour un test rapide)."
  ),
  info_simulate_results_switch = list(
    en = "Once the simulation completes, this tab switches to the results view automatically.",
    fr = "Une fois la simulation terminée, cet onglet bascule automatiquement vers la vue des résultats."
  ),
  info_simulate_back = list(en = "Back to settings", fr = "Retour aux paramètres"),
  info_simulate_back_body = list(
    en = " button at the top of the results to change inputs and re-run — the next run will switch back to results when it finishes. Tab 7 (Sensitivity) and Tab 8 (IPCC Report) provide deeper drill-downs.",
    fr = " en haut des résultats pour modifier les entrées et relancer — la prochaine exécution rebasculera vers les résultats à la fin. L'onglet 7 (Sensibilité) et l'onglet 8 (Rapport IPCC) offrent des analyses plus approfondies."
  ),
  info_simulate_n_label = list(en = "How many iterations to use:",
                                  fr = "Combien d'itérations utiliser :"),
  info_simulate_n_body = list(
    en = "Use 1,000 only for a quick test run to check that the model runs. Use a minimum of 10,000 iterations for any result you intend to use — convergence is not guaranteed below 10,000. Higher is always better: 25,000–30,000 is recommended for final reporting, especially when correlations are enabled or you have many sub-categories. To verify convergence, re-run with a different random seed: if the 95% MoE changes by more than ~2 percentage points, increase the number of iterations.",
    fr = "Utilisez 1 000 uniquement pour un test rapide vérifiant que le modèle tourne. Utilisez au minimum 10 000 itérations pour tout résultat que vous comptez utiliser — la convergence n'est pas garantie en dessous de 10 000. Plus c'est haut, mieux c'est : 25 000–30 000 sont recommandées pour le rapport final, surtout avec corrélations activées ou de nombreuses sous-catégories. Pour vérifier la convergence, relancez avec une autre graine aléatoire : si la marge d'erreur 95 % change de plus de ~2 points, augmentez le nombre d'itérations."
  ),
  card_sim_settings = list(en = "Simulation Settings", fr = "Paramètres de simulation"),
  sim_n_iter_label = list(en = "Number of Iterations", fr = "Nombre d'itérations"),
  sim_seed_label = list(en = "Random Seed (for reproducibility)",
                          fr = "Graine aléatoire (pour la reproductibilité)"),
  tip_sim_seed = list(
    en = "Fixing the seed makes results exactly reproducible — anyone using the same data, settings, and seed will get the same numbers. To check convergence, re-run with a different seed (e.g. 123 or 456): if the 95% MoE changes by more than ~2 percentage points, increase the number of iterations.",
    fr = "Fixer la graine rend les résultats exactement reproductibles — toute personne utilisant les mêmes données, paramètres et graine obtiendra les mêmes chiffres. Pour vérifier la convergence, relancez avec une autre graine (par exemple 123 ou 456) : si la marge d'erreur 95 % change de plus de ~2 points, augmentez le nombre d'itérations."
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
    en = " — the simulation cannot run without an explicit selection. (Most users tick all 6 for a full inventory.)",
    fr = " — la simulation ne peut pas démarrer sans une sélection explicite. (La plupart des utilisateurs cochent les 6 pour un inventaire complet.)"
  ),
  sim_run_decomp = list(en = "Run uncertainty decomposition (AD/EF/Combined)",
                          fr = "Lancer la décomposition d'incertitude (AD/EF/Combinée)"),
  sim_run_decomp_hint = list(
    en = "Runs two extra full simulations (~3× the run time on a large inventory). Untick for a faster run if you only need the headline result and sensitivity.",
    fr = "Lance deux simulations complètes supplémentaires (~3× le temps de calcul sur un grand inventaire). Décochez pour un calcul plus rapide si vous n'avez besoin que du résultat principal et de la sensibilité."),
  btn_run_sim = list(en = "Run Monte Carlo Simulation",
                       fr = "Lancer la simulation Monte Carlo"),
  btn_run_trend = list(en = "Run Trend Analysis",
                         fr = "Lancer l'analyse de tendance"),

  # =====================================================================
  # DEFINITIONS TAB
  # =====================================================================

  info_definitions_label = list(en = "Parameter glossary.",
                                  fr = "Glossaire des paramètres."),
  info_definitions_body = list(
    en = "All parameters used in the IPCC Tier 2 calculations, with their plain-language definition, unit, IPCC default value, suggested distribution, level (core / advanced), IPCC framing (activity data vs coefficient), and IPCC reference table or equation. Variable names are aligned with the ",
    fr = "Tous les paramètres utilisés dans les calculs IPCC Niveau 2, avec leur définition en langage clair, unité, valeur IPCC par défaut, distribution suggérée, niveau (de base / avancé), cadrage IPCC (donnée d'activité vs coefficient), et tableau ou équation IPCC de référence. Les noms de variables sont alignés sur le "
  ),
  info_definitions_software = list(en = "IPCC Inventory Software",
                                      fr = "logiciel d'inventaire IPCC"),
  info_definitions_tail = list(
    en = " (v2.95) and the symbols used in the IPCC 2006 Vol.4 Ch.10 / Ch.11 equations.",
    fr = " (v2.95) et les symboles utilisés dans les équations IPCC 2006 Vol.4 Ch.10 / Ch.11."
  ),
  card_param_definitions = list(en = "Parameter definitions",
                                  fr = "Définitions des paramètres"),

  # =====================================================================
  # SENSITIVITY TAB
  # =====================================================================

  info_sens_what = list(
    en = "This page shows which input parameters contribute most to the overall emission uncertainty. The tornado chart on the left ranks parameters by their influence -- longer bars mean more influential parameters. Green bars indicate a positive relationship (higher value = higher emissions) and red bars indicate a negative relationship. Use the dropdown on the right to switch between SRC (linear influence) and PRCC (rank-based, more robust).",
    fr = "Cette page montre quels paramètres d'entrée contribuent le plus à l'incertitude globale des émissions. Le graphique tornade à gauche classe les paramètres par leur influence — des barres plus longues indiquent des paramètres plus influents. Les barres vertes indiquent une relation positive (valeur plus élevée = émissions plus élevées) et les barres rouges une relation négative. Utilisez le menu à droite pour basculer entre SRC (influence linéaire) et PRCC (rang, plus robuste)."
  ),
  info_sens_note_label = list(en = "Note:", fr = "Note :"),
  info_sens_note_body = list(en = "These rankings show which parameters drive the ",
                                fr = "Ces classements montrent quels paramètres pilotent l'"),
  info_sens_note_uncertainty = list(en = "uncertainty", fr = "incertitude"),
  info_sens_note_tail = list(en = " of total emissions, not the absolute emission level.",
                                fr = " des émissions totales, pas le niveau d'émission absolu."),
  info_sens_action_label = list(en = "Action item:", fr = "À faire :"),
  info_sens_action_body = list(
    en = "Focus your data improvement efforts on the top 3-5 parameters to get the biggest reduction in overall inventory uncertainty.",
    fr = "Concentrez vos efforts d'amélioration des données sur les 3 à 5 premiers paramètres pour obtenir la plus grande réduction de l'incertitude globale de l'inventaire."
  ),
  info_sens_methods_label = list(en = "Sensitivity methods explained:",
                                    fr = "Méthodes de sensibilité expliquées :"),
  info_sens_src_label = list(en = "SRC (Standardized Regression Coefficients)",
                                fr = "SRC (coefficients de régression standardisés)"),
  info_sens_src_body = list(
    en = " — fits a linear model between each input parameter and the output; fast and easy to interpret. A positive SRC means higher values of that input produce higher emissions.",
    fr = " — ajuste un modèle linéaire entre chaque paramètre d'entrée et la sortie ; rapide et facile à interpréter. Un SRC positif signifie que des valeurs plus élevées de cette entrée produisent des émissions plus élevées."
  ),
  info_sens_prcc_label = list(en = "PRCC (Partial Rank Correlation Coefficients)",
                                 fr = "PRCC (corrélation partielle des rangs)"),
  info_sens_prcc_body = list(
    en = " — rank-based method, more robust when the input-output relationship is non-linear or when the output distribution is skewed. For most livestock inventories both methods give similar rankings. Use PRCC as a cross-check when SRC rankings seem counterintuitive or when distributions are highly asymmetric.",
    fr = " — méthode basée sur les rangs, plus robuste lorsque la relation entrée-sortie est non linéaire ou que la distribution de sortie est asymétrique. Pour la plupart des inventaires d'élevage, les deux méthodes donnent des classements similaires. Utilisez PRCC en validation croisée lorsque les classements SRC semblent contre-intuitifs ou lorsque les distributions sont fortement asymétriques."
  ),
  sens_output_var = list(en = "Output variable", fr = "Variable de sortie"),
  sens_total_co2e = list(en = "Total CO₂eq (all sources)",
                           fr = "CO₂éq total (toutes sources)"),
  sens_method = list(en = "Method", fr = "Méthode"),
  sens_method_src = list(en = "Standardized Regression (SRC)",
                            fr = "Régression standardisée (SRC)"),
  sens_method_prcc = list(en = "Partial Rank Correlation (PRCC)",
                             fr = "Corrélation partielle des rangs (PRCC)"),
  card_tornado_h = list(en = "Tornado Chart - Top Parameters",
                          fr = "Graphique tornade — paramètres principaux"),
  card_sens_rankings = list(en = "Sensitivity Rankings",
                              fr = "Classements de sensibilité"),
  info_trend_sens_what = list(
    en = "Trend sensitivity has two complementary views. ",
    fr = "La sensibilité de tendance comporte deux vues complémentaires. "
  ),
  info_trend_sens_per_year_label = list(en = "Per-year (latest)",
                                           fr = "Par année (la plus récente)"),
  info_trend_sens_per_year_body = list(
    en = " — which parameters dominate the uncertainty in the most recent year. ",
    fr = " — quels paramètres dominent l'incertitude dans l'année la plus récente. "
  ),
  info_trend_sens_delta_label = list(en = "Trend driver (Δ Y_N − Y_1)",
                                        fr = "Pilote de tendance (Δ Y_N − Y_1)"),
  info_trend_sens_delta_body = list(
    en = " — which parameters drive the change between the first and last year (per IPCC Vol 1 Ch 3 §3.7). Bars are coloured by ",
    fr = " — quels paramètres pilotent le changement entre la première et la dernière année (selon IPCC Vol 1 Ch 3 §3.7). Les barres sont colorées par "
  ),
  info_trend_sens_user_red = list(en = "user-reducibility",
                                     fr = "réductibilité par l'utilisateur"),
  info_trend_sens_legend = list(
    en = " (same scheme as the single-year tornado): ",
    fr = " (même schéma que le tornado annuel) : "
  ),
  info_trend_sens_green_note = list(
    en = " = the user can improve uncertainty on this parameter with better local data; ",
    fr = " = l'utilisateur peut améliorer l'incertitude de ce paramètre avec de meilleures données locales ; "
  ),
  info_trend_sens_grey_note = list(
    en = " = IPCC coefficient (requires dedicated measurement research to improve). ",
    fr = " = coefficient IPCC (nécessite de la recherche de mesure dédiée pour s'améliorer). "
  ),
  info_trend_sens_action = list(
    en = "Focus your data improvement efforts on green-coloured parameters in the top 5 — those give you the biggest uncertainty reduction with locally-collectible data.",
    fr = "Concentrez vos efforts d'amélioration des données sur les paramètres verts du top 5 — ils donnent la plus grande réduction d'incertitude avec des données collectables localement."
  ),
  trend_sens_per_year_h = list(en = "Per-year drivers (latest year)",
                                  fr = "Pilotes par année (année la plus récente)"),
  trend_sens_delta_h = list(en = "Trend driver (Δ Y_N − Y_1)",
                              fr = "Pilote de tendance (Δ Y_N − Y_1)"),
  tornado_top10 = list(en = "Tornado — top 10", fr = "Tornado — top 10"),
  trend_rankings_top15 = list(en = "Rankings — top 15 (SRC + PRCC)",
                                fr = "Classements — top 15 (SRC + PRCC)"),
  trend_combined_note = list(
    en = "Combined Y_1 + Y_N inputs are sensitivity-tested against the per-iteration ΔCO₂eq. Suffixes _y1 / _yN distinguish the same parameter at different years.",
    fr = "Les entrées combinées Y_1 + Y_N sont testées en sensibilité contre le ΔCO₂éq par itération. Les suffixes _y1 / _yN distinguent le même paramètre à différentes années."
  ),

  # =====================================================================
  # IPCC REPORT TAB
  # =====================================================================

  info_ipcc_report_intro = list(
    en = "This page shows your uncertainty results formatted as IPCC Table 3.3, ready for your national inventory submission.",
    fr = "Cette page montre vos résultats d'incertitude au format IPCC Tableau 3.3, prêts pour la soumission de votre inventaire national."
  ),
  info_ipcc_three_cols = list(en = "The table has three uncertainty columns — ",
                                 fr = "Le tableau comporte trois colonnes d'incertitude — "),
  col_ad_uncert = list(en = "AD uncertainty (%)", fr = "Incertitude AD (%)"),
  col_ef_uncert = list(en = "EF uncertainty (%)", fr = "Incertitude FE (%)"),
  col_combined_uncert = list(en = "Combined uncertainty (%)",
                                fr = "Incertitude combinée (%)"),
  info_ipcc_pct_label = list(en = "% uncertainty",
                                fr = "% d'incertitude"),
  info_ipcc_pct_body = list(
    en = " (half-width of the 95% CI ÷ mean × 100), following IPCC 2006 Vol. 1 Ch. 3 Table 3.3 conventions. AD = population/activity-data uncertainty only; EF = per-head emission factor uncertainty driven by the 23 IPCC coefficients; Combined = both sources together.",
    fr = " (demi-largeur de l'IC 95 % ÷ moyenne × 100), suivant les conventions IPCC 2006 Vol. 1 Ch. 3 Tableau 3.3. AD = incertitude population/données d'activité uniquement ; FE = incertitude du facteur d'émission par tête, pilotée par les 23 coefficients IPCC ; Combinée = les deux sources ensemble."
  ),
  info_ipcc_xlsx_label = list(en = "'Download Excel Report'",
                                  fr = "« Télécharger le rapport Excel »"),
  info_ipcc_csv_label = list(en = "'Download CSV'",
                                fr = "« Télécharger en CSV »"),
  info_ipcc_xlsx_body = list(
    en = " to get a complete workbook with all results, sensitivity rankings, run settings, and metadata. Click ",
    fr = " pour obtenir un classeur complet avec tous les résultats, classements de sensibilité, paramètres d'exécution et métadonnées. Cliquez sur "
  ),
  info_ipcc_csv_body = list(en = " for a simpler file with uncertainty metrics only.",
                              fr = " pour un fichier plus simple avec uniquement les métriques d'incertitude."),
  info_ipcc_click_label = list(en = "Click ", fr = "Cliquez sur "),
  ad_ef_convention_label = list(en = "AD vs EF column convention:",
                                  fr = "Convention des colonnes AD vs FE :"),
  ad_ef_convention_body = list(
    en = "in this version, AD = population uncertainty only (N), and EF = the per-head emission factor uncertainty driven by the IPCC coefficients (live weight, feed quality, Ym, Bo, EF3_PRP, etc.). This matches IPCC Volume 1 Chapter 3 reporting conventions.",
    fr = "dans cette version, AD = incertitude de population uniquement (N), et FE = incertitude du facteur d'émission par tête, pilotée par les coefficients IPCC (poids vif, qualité de l'alimentation, Ym, Bo, EF3_PRP, etc.). Cela correspond aux conventions de rapport IPCC Volume 1 Chapitre 3."
  ),
  card_ipcc_table_h = list(en = "IPCC Table 3.3 - Uncertainty Report",
                              fr = "Tableau IPCC 3.3 — Rapport d'incertitude"),
  card_downloads_h = list(en = "Download reports", fr = "Télécharger les rapports"),
  downloads_intro = list(
    en = "Export the run results — Excel for the full workbook with sensitivity / settings / metadata sheets, CSV for the bare uncertainty table, Word for the IPCC-style narrative summary.",
    fr = "Exportez les résultats — Excel pour le classeur complet avec les feuilles sensibilité / paramètres / métadonnées, CSV pour le tableau d'incertitude brut, Word pour le résumé narratif au style IPCC."
  ),
  card_dist_per_source = list(en = "Uncertainty distributions per emission source",
                                fr = "Distributions d'incertitude par source d'émission"),
  body_dist_per_source = list(
    en = "Histograms of the Monte Carlo output for each emission source. Useful for third-party QA review of which sources contribute the most variance. When you hover over a bar, the tooltip shows two numbers: the ",
    fr = "Histogrammes de la sortie Monte Carlo pour chaque source d'émission. Utile pour la revue QA tierce des sources qui contribuent le plus à la variance. Quand vous survolez une barre, l'info-bulle affiche deux chiffres : la "
  ),
  xrange_label = list(en = "x-range", fr = "plage x"),
  body_dist_per_source_mid = list(
    en = " (e.g. '37k–38k') is the emission value interval for that bin in tonnes — the width of this interval reflects the spread of the distribution for that source; the ",
    fr = " (par ex. « 37k–38k ») est l'intervalle de valeurs d'émission pour ce bac en tonnes — la largeur de cet intervalle reflète l'étendue de la distribution pour cette source ; le "
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
    en = "Density plots of each input parameter's fitted distribution — confirms each parameter was sampled with the marginal distribution specified in the input table.",
    fr = "Graphiques de densité de la distribution ajustée de chaque paramètre d'entrée — confirme que chaque paramètre a été échantillonné avec la distribution marginale spécifiée dans la table d'entrée."
  ),
  card_inputs_doc = list(en = "Input parameters used in this run",
                           fr = "Paramètres d'entrée utilisés dans cette exécution"),
  body_inputs_doc = list(
    en = "Full record of every parameter value, distribution, and bounds used in the simulation — included for inventory documentation and third-party QA review.",
    fr = "Enregistrement complet de chaque valeur de paramètre, distribution et bornes utilisées dans la simulation — inclus pour la documentation d'inventaire et la revue QA tierce."
  ),
  btn_download_xlsx = list(en = "Download Excel Report",
                              fr = "Télécharger le rapport Excel"),
  btn_download_csv = list(en = "Download CSV", fr = "Télécharger en CSV"),
  btn_download_docx = list(en = "Download Word summary",
                              fr = "Télécharger le résumé Word"),
  info_trend_report_what = list(
    en = "This page presents the trend results — year-by-year totals, the trend slope and Δ across years with their own 95% CIs, and the sensitivity drivers per IPCC Vol 1 Ch 3 §3.7. Use the downloads below to export the trend report as Excel (multi-sheet workbook), CSV (table only), or Word (full IPCC-style narrative report including the executive summary and methodological notes on the year-correlation mode you chose).",
    fr = "Cette page présente les résultats de tendance — totaux annuels, pente de tendance et Δ entre les années avec leurs propres IC à 95 %, et les pilotes de sensibilité selon IPCC Vol 1 Ch 3 §3.7. Utilisez les téléchargements ci-dessous pour exporter le rapport de tendance en Excel (classeur multi-feuilles), CSV (table uniquement), ou Word (rapport narratif complet au style IPCC incluant le résumé exécutif et les notes méthodologiques sur le mode de corrélation inter-années choisi)."
  ),
  card_trend_downloads = list(en = "Trend report — downloads",
                                fr = "Rapport de tendance — téléchargements"),
  trend_downloads_note = list(
    en = "Available after a successful trend run on the Simulate tab. Filename includes the year-correlation mode you picked.",
    fr = "Disponible après une exécution de tendance réussie sur l'onglet Simulation. Le nom de fichier inclut le mode de corrélation inter-années choisi."
  ),
  card_trend_chart_h = list(en = "Trend chart — Total CO₂eq with 95% CI band",
                              fr = "Graphique de tendance — CO₂éq total avec bande IC 95 %"),
  card_trend_table_h = list(en = "Trend table", fr = "Tableau de tendance"),
  trend_table_note = list(
    en = "Year-by-year mean, 95% CI bounds, CV%, MoE%, Δ vs. base year, and year-over-year change.",
    fr = "Moyenne annuelle, bornes IC 95 %, CV%, MoE%, Δ vs année de base et variation interannuelle."
  ),
  card_trend_sens_h = list(en = "Sensitivity drivers (per-year + trend)",
                              fr = "Pilotes de sensibilité (par année + tendance)"),
  trend_sens_note = list(
    en = "Per-year tornado shows drivers of the latest year; Δ Y_N − Y_1 tornado shows what drives the change between the first and last year (per IPCC Vol 1 Ch 3 §3.7).",
    fr = "Le tornado par année montre les pilotes de l'année la plus récente ; le tornado Δ Y_N − Y_1 montre ce qui pilote le changement entre la première et la dernière année (selon IPCC Vol 1 Ch 3 §3.7)."
  ),

  # =====================================================================
  # CONTACT TAB
  # =====================================================================

  contact_intro_label = list(
    en = "We welcome feedback, bug reports, feature suggestions, and methodology questions.",
    fr = "Nous accueillons vos retours, signalements de bugs, suggestions de fonctionnalités et questions sur la méthodologie."
  ),
  contact_intro_body = list(
    en = "Submissions are sent to the development team. We aim to reply within a few working days.",
    fr = "Les soumissions sont envoyées à l'équipe de développement. Nous visons à répondre dans quelques jours ouvrables."
  ),
  card_contact_send = list(en = "Send us a message", fr = "Envoyez-nous un message"),
  card_contact_helps = list(en = "What kind of feedback helps most",
                              fr = "Quel type de retour est le plus utile"),
  contact_bug_label = list(en = "Bug reports", fr = "Signalements de bugs"),
  contact_bug_body = list(en = " — with steps to reproduce, the example dataset or your upload, and the error message.",
                            fr = " — avec les étapes pour reproduire, le jeu de données d'exemple ou votre téléversement, et le message d'erreur."),
  contact_method_label = list(en = "Methodology questions",
                                fr = "Questions méthodologiques"),
  contact_method_body = list(
    en = " — e.g. how a particular IPCC equation is implemented, or whether your country's data fits the assumptions.",
    fr = " — par exemple comment une équation IPCC est implémentée, ou si les données de votre pays correspondent aux hypothèses."
  ),
  contact_feat_label = list(en = "Feature requests", fr = "Demandes de fonctionnalités"),
  contact_feat_body = list(
    en = " — missing parameters, additional emission sources, integration with national inventory tools.",
    fr = " — paramètres manquants, sources d'émission supplémentaires, intégration avec les outils d'inventaire nationaux."
  ),
  contact_doc_label = list(en = "Documentation gaps", fr = "Lacunes documentaires"),
  contact_doc_body = list(en = " — if a tab or label was confusing, tell us where you got stuck.",
                            fr = " — si un onglet ou une étiquette était confus, dites-nous où vous avez été bloqué."),
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
    en = "Tell us what you would like to share — a bug, a feature idea, a methodology question, anything.",
    fr = "Dites-nous ce que vous voulez partager — un bug, une idée de fonctionnalité, une question méthodologique, n'importe quoi."
  ),
  btn_cf_send = list(en = "Send message", fr = "Envoyer le message"),
  cf_status_init = list(
    en = "Submissions go directly to the development team. We aim to reply within a few working days.",
    fr = "Les soumissions vont directement à l'équipe de développement. Nous visons à répondre dans quelques jours ouvrables."
  ),
  cf_sending_btn = list(en = "Sending…", fr = "Envoi…"),
  cf_sending_msg = list(en = "Sending your message…", fr = "Envoi de votre message…"),
  cf_sent_text = list(en = "Message sent — thank you!",
                        fr = "Message envoyé — merci !"),
  cf_sent_sub = list(en = "We aim to reply within a few working days.",
                       fr = "Nous visons à répondre dans quelques jours ouvrables."),
  cf_send_failed = list(en = "Send failed:", fr = "Échec de l'envoi :"),
  cf_unknown_error = list(en = "unknown error", fr = "erreur inconnue"),
  cf_try_again = list(en = "Please try again in a moment.",
                        fr = "Veuillez réessayer dans un instant."),
  cf_network_error = list(en = "Network error. Please try again.",
                            fr = "Erreur réseau. Veuillez réessayer."),

  # =====================================================================
  # DEFINITIONS TABLE — column headers + categorical values
  # =====================================================================

  def_col_variable = list(en = "Variable name", fr = "Nom de variable"),
  def_col_definition = list(en = "Definition", fr = "Définition"),
  def_col_unit = list(en = "Unit", fr = "Unité"),
  def_col_ipcc_default = list(en = "IPCC default", fr = "Valeur IPCC par défaut"),
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
    en = "%d parameter not supplied in your upload — auto-filled from IPCC defaults so the simulation could run. Override these values in the template if you have country-specific data.",
    fr = "%d paramètre non fourni dans votre téléversement — rempli automatiquement à partir des valeurs IPCC par défaut afin que la simulation puisse s'exécuter. Remplacez ces valeurs dans le modèle si vous disposez de données nationales."
  ),
  imputed_card_body_plural = list(
    en = "%d parameters not supplied in your upload — auto-filled from IPCC defaults so the simulation could run. Override these values in the template if you have country-specific data.",
    fr = "%d paramètres non fournis dans votre téléversement — remplis automatiquement à partir des valeurs IPCC par défaut afin que la simulation puisse s'exécuter. Remplacez ces valeurs dans le modèle si vous disposez de données nationales."
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
    en = " These are IPCC defaults — replace with country-specific values in your template where available. Full details and QA flags are on the ",
    fr = " Ce sont des valeurs IPCC par défaut — remplacez par des valeurs nationales dans votre modèle lorsque possible. Tous les détails et les indicateurs QA sont sur l'onglet "
  ),
  imputed_notice_tail_qaqc = list(en = "QA/QC", fr = "QA/QC"),
  imputed_notice_tail_post = list(en = " tab.", fr = "."),

  # =====================================================================
  # QA/QC table — status icons, summary badges, check labels
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

  # QA verdict messages — sprintf templates keyed by check id + verdict.
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
  qa_msg_range_de_fail = list(en = "DE_pct = %.1f%%. Must be in [1, 100].",
                                fr = "DE_pct = %.1f %%. Doit être dans [1, 100]."),
  qa_msg_range_de_pass = list(en = "DE_pct = %.1f%% (valid range 1-100%%)",
                                fr = "DE_pct = %.1f %% (plage valide 1-100 %%)"),
  qa_msg_range_ym_warn = list(
    en = "Ym_pct = %.1f%%. Typical IPCC range is 3-12%%; values outside 1-15%% are unusual.",
    fr = "Ym_pct = %.1f %%. La plage typique IPCC est 3-12 %% ; les valeurs hors 1-15 %% sont inhabituelles."
  ),
  qa_msg_range_ym_pass = list(en = "Ym_pct = %.1f%% (within typical IPCC range)",
                                fr = "Ym_pct = %.1f %% (dans la plage IPCC typique)"),
  qa_msg_frac_fail = list(en = "%s = %.4g. Must be a fraction in [0, 1].",
                            fr = "%s = %.4g. Doit être une fraction dans [0, 1]."),
  qa_msg_frac_pass = list(en = "%s = %.4g (valid fraction in [0, 1])",
                            fr = "%s = %.4g (fraction valide dans [0, 1])"),
  qa_msg_beta_mean_fail = list(
    en = "Beta distribution requires mean in (0,1). Got %.4g.",
    fr = "La distribution beta requiert une moyenne dans (0,1). Reçu %.4g."
  ),
  qa_msg_beta_bounds_fail = list(
    en = "Beta distribution requires bounds in [0,1]. Got [%.4g, %.4g].",
    fr = "La distribution beta requiert des bornes dans [0,1]. Reçu [%.4g, %.4g]."
  ),
  qa_msg_beta_pass = list(en = "Beta: mean in (0,1) and bounds in [0,1]",
                            fr = "Beta : moyenne dans (0,1) et bornes dans [0,1]"),
  qa_msg_lognorm_fail = list(
    en = "Log-normal requires a strictly positive mean. Got %.4g.",
    fr = "La loi log-normale requiert une moyenne strictement positive. Reçu %.4g."
  ),
  qa_msg_lognorm_pass = list(en = "Log-normal: mean > 0",
                               fr = "Log-normale : moyenne > 0"),
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
    en = "Mean (%.4g) deviates %.0f%% from %s default (%.4g). Large deviation — please document the source.",
    fr = "La moyenne (%.4g) s'écarte de %.0f %% par rapport à la valeur par défaut %s (%.4g). Écart important — veuillez documenter la source."
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
    fr = "%s non fourni dans le téléversement — rempli automatiquement avec la valeur IPCC par défaut %.4g %s (%s). Remplacez dans le modèle si des données locales sont disponibles."
  ),
  qa_msg_frac_dist_warn = list(
    en = "%s must lie in [0,1] but uses '%s' which can produce out-of-range samples. Use 'tnorm_0_1' or 'beta' instead.",
    fr = "%s doit être dans [0,1] mais utilise « %s » qui peut produire des échantillons hors plage. Utilisez plutôt « tnorm_0_1 » ou « beta »."
  ),
  qa_msg_frac_dist_pass = list(en = "%s: bounded distribution '%s' used",
                                  fr = "%s : distribution bornée « %s » utilisée"),
  qa_msg_asym_warn = list(
    en = "%s has right-skewed uncertainty (IPCC 2006/2019 guideline tables). Detected near-symmetric bounds (upper span / lower span = %.1f). Consider using the IPCC-recommended asymmetric bounds from the blank template.",
    fr = "%s a une incertitude asymétrique à droite (tableaux IPCC 2006/2019). Bornes quasi symétriques détectées (étendue sup. / étendue inf. = %.1f). Envisagez les bornes asymétriques recommandées par l'IPCC depuis le modèle vierge."
  ),
  qa_msg_asym_pass = list(
    en = "%s: asymmetric bounds applied (upper/lower span ratio = %.1f)",
    fr = "%s : bornes asymétriques appliquées (ratio étendue sup./inf. = %.1f)"
  ),
  qa_msg_no_mms = list(
    en = "No Manure_Management sheet present — manure CH4 and N2O fall back to default 70%% pasture / 30%% solid_storage allocation. Add a Manure_Management sheet to use per-MMS values.",
    fr = "Pas de feuille Manure_Management — CH4 et N2O du fumier reviennent à l'allocation par défaut 70 %% pâturage / 30 %% solid_storage. Ajoutez une feuille Manure_Management pour utiliser des valeurs par-MMS."
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
  # CORRELATIONS TAB — radio options + TS status + Compare toggle
  # =====================================================================

  corr_mode_none = list(en = "No correlations (default)",
                          fr = "Pas de corrélations (par défaut)"),
  corr_mode_preset = list(en = "Structural defaults (expert-elicited)",
                            fr = "Valeurs structurelles par défaut (jugement d'expert)"),
  corr_mode_ts = list(en = "From template (auto, time-series)",
                       fr = "Depuis le modèle (auto, séries temporelles)"),
  corr_mode_manual = list(en = "Advanced — manual matrix entry",
                            fr = "Avancé — saisie manuelle de la matrice"),
  corr_mode_unavailable_ts = list(
    en = " — needs a non-empty Parameter_TimeSeries sheet",
    fr = " — nécessite une feuille Parameter_TimeSeries non vide"
  ),
  corr_mode_unavailable_manual = list(
    en = " — needs an uploaded matrix",
    fr = " — nécessite une matrice téléversée"
  ),

  corr_ef_mode_none = list(en = "No EF correlations (default)",
                             fr = "Pas de corrélations FE (par défaut)"),
  corr_ef_mode_block = list(en = "Block-structured EF correlation",
                              fr = "Corrélation FE structurée par blocs"),

  corr_ts_status_ok = list(
    en = "Time-series sheet loaded — correlations computed from your data.",
    fr = "Feuille de séries temporelles chargée — corrélations calculées à partir de vos données."
  ),
  corr_ts_status_missing = list(
    en = "No Parameter_TimeSeries sheet found in your upload. Upload a template with this sheet, or pick another correlation mode.",
    fr = "Aucune feuille Parameter_TimeSeries trouvée dans votre téléversement. Téléversez un modèle contenant cette feuille ou choisissez un autre mode de corrélation."
  ),
  corr_ts_status_empty = list(
    en = "Parameter_TimeSeries sheet found but is empty. Fill it with multi-year activity data or pick another correlation mode.",
    fr = "Feuille Parameter_TimeSeries trouvée mais vide. Remplissez-la avec des données pluriannuelles ou choisissez un autre mode de corrélation."
  ),

  corr_ef_zero_warning = list(
    en = "All three within-block ρ sliders are at 0 — block-structured EF correlation has no effect. Move at least one slider above 0 to add a correlation.",
    fr = "Les trois curseurs ρ inter-blocs sont à 0 — la corrélation FE structurée par blocs n'a aucun effet. Déplacez au moins un curseur au-dessus de 0 pour ajouter une corrélation."
  ),

  cmp_run_label = list(en = "Compare with/without correlations",
                         fr = "Comparer avec/sans corrélations"),
  cmp_run_tooltip = list(
    en = "When ticked, the simulation runs twice — once with the correlations you picked, once with all correlations off — and the Results tab shows both side-by-side so you can see the impact.",
    fr = "Quand coché, la simulation s'exécute deux fois — une avec les corrélations choisies, une avec les corrélations désactivées — et l'onglet Résultats les affiche côte à côte pour voir l'effet."
  ),
  cmp_disabled_note = list(
    en = "No correlations selected on the Correlations tab — comparison would be identical, so this toggle is disabled.",
    fr = "Aucune corrélation sélectionnée sur l'onglet Corrélations — la comparaison serait identique, ce bouton est donc désactivé."
  ),

  # Correlations tab — radio mode label + tooltip + per-mode help text
  corr_mode_label = list(en = "Mode", fr = "Mode"),
  tip_corr_mode = list(
    en = "How should the tool decide which input parameters move together? Modes whose prerequisites are missing (no time-series, no manual matrix uploaded) are greyed out below.",
    fr = "Comment l'outil doit-il décider quels paramètres bougent ensemble ? Les modes dont les prérequis manquent (pas de séries temporelles, pas de matrice manuelle téléversée) sont grisés ci-dessous."
  ),
  corr_disabled_prefix = list(en = "Disabled — ", fr = "Désactivé — "),
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
    en = "A manual CSV matrix is loaded — using it for the run. Re-upload below to replace.",
    fr = "Une matrice CSV manuelle est chargée — utilisée pour l'exécution. Téléversez à nouveau ci-dessous pour remplacer."
  ),
  corr_help_manual_pick = list(
    en = "Pick this to use a CSV correlation matrix. Two starting templates appear below — a blank matrix with all parameter names pre-labelled, and an example pre-filled with the structural-defaults pairs. Edit cells and re-upload.",
    fr = "Choisissez ceci pour utiliser une matrice de corrélation CSV. Deux modèles de départ apparaissent ci-dessous — une matrice vierge avec tous les noms de paramètres pré-étiquetés, et un exemple pré-rempli avec les paires des valeurs structurelles par défaut. Modifiez les cellules et téléversez à nouveau."
  ),
  corr_mode_advanced_manual_short = list(en = "Advanced — manual entry",
                                            fr = "Avancé — saisie manuelle"),

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
    en = " No correlations selected on Tab 4 — comparison would be identical to the main run, so this option is disabled. Enable a correlation mode to activate it.",
    fr = " Aucune corrélation sélectionnée sur l'onglet 4 — la comparaison serait identique à l'exécution principale, cette option est donc désactivée. Activez un mode de corrélation pour l'activer."
  ),

  # Correlation heatmap labels
  corr_heatmap_no_matrix = list(en = "No correlation matrix loaded",
                                  fr = "Aucune matrice de corrélation chargée"),
  corr_heatmap_title_ad = list(en = "Activity Data Correlation Matrix",
                                  fr = "Matrice de corrélation des données d'activité"),
  corr_heatmap_title_ef = list(en = "EF Correlation Matrix",
                                  fr = "Matrice de corrélation des FE"),
  corr_ef_no_corr = list(en = "No EF correlations applied (IPCC default)",
                          fr = "Aucune corrélation FE appliquée (IPCC par défaut)"),
  tip_ef_corr_mode = list(
    en = "Should emission factors share systematic bias? The IPCC default is independence. Pick block-structured if you suspect one literature is biased (e.g. all your Ym-equation coefficients come from the same regional database).",
    fr = "Les facteurs d'émission partagent-ils un biais systématique ? La valeur IPCC par défaut est l'indépendance. Choisissez « par blocs » si vous suspectez qu'une littérature est biaisée (par ex. tous vos coefficients d'équation Ym proviennent de la même base régionale)."
  ),

  # =====================================================================
  # RESULTS VIEW (Simulate tab — post-run)
  # =====================================================================

  res_back_to_settings = list(en = "Back to settings", fr = "Retour aux paramètres"),
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
  res_vb_moe_label = list(en = "Total CO₂eq — 95% MoE",
                            fr = "CO₂éq total — MoE 95 %"),
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
  res_vb_trend_latest = list(en = "Latest year — Total CO₂eq",
                                fr = "Année la plus récente — CO₂éq total"),
  res_vb_trend_delta = list(en = "Δ vs base year",
                              fr = "Δ vs année de base"),
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

  # Results — DT column headers + chart titles
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

  res_hist_chart_title = list(en = "Distribution of Total CO2eq Emissions",
                                fr = "Distribution des émissions totales CO₂éq"),
  res_hist_xaxis = list(en = "Total CO2eq (tonnes)", fr = "CO₂éq total (tonnes)"),
  res_hist_yaxis = list(en = "Frequency", fr = "Fréquence"),
  res_hist_outlier_note = list(
    en = "%d of %d iterations beyond chart range",
    fr = "%d itérations sur %d au-delà de la plage du graphique"),
  res_decomp_chart_title = list(
    en = "Uncertainty Decomposition (95% MoE, total CO2eq)",
    fr = "Décomposition de l'incertitude (MoE 95 %, CO₂éq total)"
  ),
  res_decomp_yaxis = list(en = "95% MoE (%)", fr = "MoE 95 % (%)"),

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
    en = "± half-width of 95% CI / mean — IPCC convention",
    fr = "± demi-largeur IC 95 % / moyenne — convention IPCC"
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

  res_vb_trend_slope_short = list(en = "Trend slope", fr = "Pente de tendance"),
  res_vb_trend_latest_short = list(en = "Latest year", fr = "Année la plus récente"),
  res_vb_trend_yoy_largest = list(en = "Largest YoY change",
                                     fr = "Plus grande variation interannuelle"),

  res_trend_yoy_h = list(en = "Year-over-year % change",
                           fr = "Variation interannuelle (%)"),
  res_trend_delta_hist_h = list(
    en = "Distribution of Δ Y_N − Y_1 — uncertainty on the trend itself",
    fr = "Distribution de Δ Y_N − Y_1 — incertitude sur la tendance elle-même"
  ),
  res_trend_delta_hist_note = list(
    en = "This histogram shows the Monte Carlo distribution of the absolute change in CO₂eq between the first and last year. The dashed red lines mark the 95% CI; the dotted line marks zero. If zero falls inside the CI, the trend is not statistically distinguishable from no change at this confidence level.",
    fr = "Cet histogramme montre la distribution Monte Carlo de la variation absolue de CO₂éq entre la première et la dernière année. Les lignes rouges pointillées marquent l'IC 95 % ; la ligne en pointillés marque zéro. Si zéro tombe dans l'IC, la tendance n'est pas statistiquement distinguable d'aucun changement à ce niveau de confiance."
  ),
  res_trend_footer_note = list(
    en = "Sensitivity drivers (per-year + Δ Y_N − Y_1) are on Tab 6 (Sensitivity). Word / Excel / CSV trend reports are on Tab 7 (IPCC Report).",
    fr = "Les pilotes de sensibilité (par année + Δ Y_N − Y_1) sont sur l'onglet 6 (Sensibilité). Les rapports de tendance Word / Excel / CSV sont sur l'onglet 7 (Rapport IPCC)."
  ),
  res_trend_plot_title = list(en = "Trend in total CO₂eq emissions (95% CI)",
                                fr = "Tendance des émissions CO₂éq totales (IC 95 %)"),
  res_trend_xaxis_year = list(en = "Inventory year", fr = "Année d'inventaire")
)

# =============================================================================
# QA verdict helper — fetches a translated sprintf template by key
# =============================================================================
# Usage: qa_msg("bounds_order_fail_lo", lo, mu) returns the formatted string
# in the current language. Falls back to English if the key or language
# isn't in .STRINGS. Saves wrapping every QA `add()` call in a manual
# t() + sprintf() pair.
qa_msg <- function(key, ...) {
  tmpl <- t(paste0("qa_msg_", key))
  if (grepl("^\\[\\?", tmpl)) return(tmpl)  # missing key — propagate
  sprintf(tmpl, ...)
}

# =============================================================================
# Parameter definitions (Definitions tab) — French translations
# =============================================================================
# Keyed by canonical parameter name. The English versions live in
# PARAM_CATALOGUE$definition (R/utils_template.R) and stay authoritative;
# we only override the displayed `definition` column when .LANG_CURRENT == "fr".
# IPCC codes (BW, MW, Ym, Bo, EF3_PRP, etc.) and table/equation references
# (IPCC Vol.4 Ch.10 Eq 10.X, Table 10.Y, 2019R, …) are kept verbatim — they
# are international identifiers, not translatable text.
.PARAM_DEFINITIONS_FR <- c(
  N            = "Nombre d'animaux dans cette sous-catégorie",
  BW           = "Poids vif moyen des animaux",
  MW           = "Poids vif adulte (mature) des animaux",
  WG           = "Gain de poids quotidien moyen — fixer 0 pour les animaux adultes (non en croissance)",
  Milk         = "Rendement laitier quotidien par vache en lactation (pas la moyenne de la sous-catégorie — l'outil multiplie par pct_pregnant en interne). Fixer 0 pour les sous-catégories qui ne lactent pas.",
  Fat          = "Teneur en matière grasse du lait (% en poids)",
  pct_pregnant = "Fraction des femelles de cette sous-catégorie gestantes pendant l'année, entre 0 et 1 — inclut les génisses gestantes n'ayant pas encore vêlé. Pondère Cpregnancy dans l'Éq IPCC 10.13 (NEp) et le terme de rétention de N du lait dans l'Éq 10.33 ; l'outil l'applique aussi comme poids de lactation dans l'Éq 10.8 (NEl). Pour les sous-catégories où les populations en lactation et en gestation diffèrent, entrer la fraction gestante.",
  DE           = "Énergie digestible en pourcentage de l'énergie brute — plage typique 45-75 %",
  Cfi          = "Coefficient d'énergie d'entretien — dépend du sexe et de l'état de lactation (IPCC Tableau 10.4)",
  Ca           = "Coefficient d'activité pour l'énergie de locomotion — dépend de la situation alimentaire (IPCC Tableau 10.5)",
  C            = "Coefficient de croissance pour l'équation NEg — dépend du sexe et de l'état physiologique (IPCC Éq 10.6)",
  Cp           = "Coefficient de gestation — 0,10 pour les animaux gestants (IPCC Tableau 10.7)",
  hours        = "Heures de travail quotidiennes (Éq. 10.11) — fixer 0 si les animaux ne travaillent pas ; pertinent uniquement lorsque les animaux sont utilisés pour la traction/portage",
  CP           = "Teneur en protéines brutes (CP %) de la ration — utilisée pour estimer l'excrétion d'azote",
  Ym           = "Facteur de conversion en méthane : % de l'énergie brute convertie en méthane (IPCC Tableau 10.12)",
  Bo           = "Capacité maximale de production de CH₄ du fumier (IPCC Tableau 10.16)",
  ASH          = "Teneur en cendres du fumier — valeur IPCC par défaut 0,08 (note de bas de page Éq 10.24)",
  UE           = "Énergie urinaire en fraction de l'énergie brute — valeur IPCC par défaut 0,04 (note de bas de page Éq 10.24)",
  EF3_PRP      = "Facteur d'émission N₂O pour les excréments/urine au pâturage (IPCC Vol.4 Ch.11 Tableau 11.1). 2019R EF3_PRP,CPP pour bovins/volailles/porcs : agrégé 0,004 ; climat humide 0,006 ; climat sec 0,002. 2006 = 0,02.",
  EF4          = "FE N₂O pour le dépôt atmosphérique d'azote (IPCC Vol.4 Ch.11 Tableau 11.3). 2019R agrégé EF4 = 0,010 (plage 0,002-0,018) ; climat humide 0,014 ; climat sec 0,005. 2006 = 0,010.",
  EF5          = "FE N₂O pour le lessivage/ruissellement d'azote (IPCC Vol.4 Ch.11 Tableau 11.3). 2019R EF5 = 0,011 (plage 0,000-0,020), sans désagrégation climatique. 2006 = 0,0075.",
  Frac_GASM_PRP = "Fraction d'azote volatilisée à partir des excréments/urine au pâturage (IPCC Vol.4 Ch.11 Tableau 11.3, FracGASM). 2019R = 0,21 (plage 0,00-0,31) ; 2006 = 0,20.",
  Frac_LEACH_PRP = "Fraction d'azote lessivée à partir du dépôt au pâturage (IPCC Vol.4 Ch.11 Tableau 11.3, FracLEACH-(H), climats humides uniquement). 2019R = 0,24 (plage 0,01-0,73) ; 2006 = 0,30 ; en climats secs = 0.",
  MilkPR       = "Teneur en protéines du lait — alimente le terme N du lait dans l'Éq IPCC Vol.4 Ch.10 10.33 (rétention d'azote pour les bovins, où la conversion 6,38 protéine-laitière-vers-N est définie)",
  Tw           = "Température moyenne quotidienne en hiver (°C) — ajustement Cfi climat froid selon IPCC Vol.4 Ch.10 Éq 10.2 (modifie Cfi de l'Éq 10.3). Laisser vide ou fixer 20 pour désactiver l'ajustement"
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
