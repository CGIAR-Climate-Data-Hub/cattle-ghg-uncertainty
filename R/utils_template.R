# =============================================================================
# Excel Input Template — openxlsx version with dropdown menus
# =============================================================================
# Sheets produced:
#   _Lists            (hidden)  — raw lists that power dropdown validation
#   README                      — colour legend + quick-start
#   Inventory_Metadata          — dropdowns for species/climate/GWP/version
#   Parameters                  — pre-populated 22-row block per sub-category,
#                                  dropdowns, auto-fill formulas for lower/upper
#   Manure_Management           — dropdown for mms_type
#   Parameter_TimeSeries        — year-by-parameter grid for correlation estimation
#   Vocab                       — parameter catalogue + all controlled terms
# =============================================================================

# Safe-default operator (used in parse_uploaded_template)
`%||%` <- function(a, b)
  if (is.null(a) || length(a) == 0 || is.na(a[1]) || !nzchar(as.character(a[1]))) b else a

# R2.2: compute a correlation matrix (with nearest-PD projection) from a
# Parameter_TimeSeries-style data frame. Used both by parse_uploaded_template()
# (real upload path) and by .load_example() in app_server.R so that the built-in
# Country X / Country Y examples can populate Tab 4's "From template (auto)"
# correlation mode without requiring a separate upload.
#
# 2026-05 audit follow-up:
#   - Switched from Pearson to Spearman rank correlation (matches the rank
#     correlation the sampler reproduces, per IPCC Vol.1 Ch.3 §3.2.3.2).
#   - Added optional detrending. Default is first differences, which strips the
#     shared long-run growth common to most national livestock series. Linear
#     detrend and "none" (raw, legacy behaviour) are also available.
#   - When `detrend = "first_diff"` and only N=5 years are available, only N-1=4
#     paired observations remain, so the minimum-rows guard is relaxed accordingly.
compute_corr_from_population <- function(population,
                                          detrend = c("first_diff","linear","none")) {
  detrend <- match.arg(detrend)
  if (is.null(population) || ncol(population) < 2) return(NULL)
  if (exists("PARAM_ALIASES")) {
    hits <- names(population) %in% names(PARAM_ALIASES)
    if (any(hits))
      names(population)[hits] <- PARAM_ALIASES[names(population)[hits]]
  }
  num_check  <- suppressWarnings(as.numeric(population[[1]]))
  first_data <- which(!is.na(num_check))[1]
  if (!is.na(first_data) && first_data > 1)
    population <- population[first_data:nrow(population), , drop = FALSE]
  population[] <- lapply(population, function(x) suppressWarnings(as.numeric(x)))
  numeric_cols <- vapply(population, function(x) sum(!is.na(x)) >= 5, logical(1))
  pop_numeric  <- population[, numeric_cols, drop = FALSE]
  if ("year" %in% names(pop_numeric)) pop_numeric$year <- NULL
  if (ncol(pop_numeric) < 2 || nrow(pop_numeric) < 5) return(NULL)
  series <- switch(detrend,
    none       = pop_numeric,
    first_diff = as.data.frame(lapply(pop_numeric, function(y) c(NA_real_, diff(y)))),
    linear     = as.data.frame(lapply(pop_numeric, function(y) {
                   if (sum(!is.na(y)) < 3) return(as.numeric(y))
                   fit <- tryCatch(
                     stats::lm(y ~ seq_along(y), na.action = stats::na.exclude),
                     error = function(e) NULL)
                   if (is.null(fit)) as.numeric(y) else as.numeric(stats::residuals(fit))
                 })))
  # Drop constant (zero-variance) columns: cor() returns NaN for them and warns
  # "the standard deviation is zero". This commonly happens with user templates
  # where one parameter has the same value every year (e.g. hours = 100).
  has_variance <- vapply(series, function(y) {
    y <- y[is.finite(y)]
    length(y) >= 2 && stats::sd(y) > 0
  }, logical(1))
  series <- series[, has_variance, drop = FALSE]
  if (ncol(series) < 2) return(NULL)
  tryCatch({
    cm <- cor(series, use = "complete.obs", method = "spearman")
    as.matrix(Matrix::nearPD(cm, corr = TRUE)$mat)
  }, error = function(e) NULL)
}

# Andreas 28/5/26 follow-up: country-name → continental region lookup.
# Used by normalise_metadata_region() to rescue legacy uploads that only
# have a free-text "Country / region" cell (without the new Continental
# region dropdown). The list is illustrative — it covers the cases
# inventory teams in our partner network are likely to type. Country
# names are matched case-insensitively after stripping whitespace.
# Anything not in this list falls through to "global", which preserves
# the prior behaviour (no false BW benchmark warning).
COUNTRY_TO_REGION <- c(
  # Africa
  "zimbabwe" = "africa", "kenya" = "africa", "uganda" = "africa",
  "tanzania" = "africa", "ethiopia" = "africa", "south africa" = "africa",
  "rwanda" = "africa", "burundi" = "africa", "madagascar" = "africa",
  "ghana" = "africa", "nigeria" = "africa", "senegal" = "africa",
  "mali" = "africa", "burkina faso" = "africa", "niger" = "africa",
  "mozambique" = "africa", "zambia" = "africa", "malawi" = "africa",
  "botswana" = "africa", "namibia" = "africa", "egypt" = "africa",
  "morocco" = "africa", "tunisia" = "africa", "algeria" = "africa",
  "cote d'ivoire" = "africa", "ivory coast" = "africa", "cameroon" = "africa",
  # Asia
  "india" = "asia", "china" = "asia", "pakistan" = "asia",
  "bangladesh" = "asia", "vietnam" = "asia", "thailand" = "asia",
  "indonesia" = "asia", "philippines" = "asia", "myanmar" = "asia",
  "nepal" = "asia", "sri lanka" = "asia", "cambodia" = "asia",
  "laos" = "asia", "mongolia" = "asia", "kazakhstan" = "asia",
  "japan" = "asia", "south korea" = "asia", "korea" = "asia",
  "iran" = "asia", "iraq" = "asia", "turkey" = "asia",
  # Europe
  "united kingdom" = "europe", "uk" = "europe", "ireland" = "europe",
  "france" = "europe", "germany" = "europe", "italy" = "europe",
  "spain" = "europe", "portugal" = "europe", "netherlands" = "europe",
  "belgium" = "europe", "denmark" = "europe", "sweden" = "europe",
  "norway" = "europe", "finland" = "europe", "poland" = "europe",
  "czech republic" = "europe", "switzerland" = "europe", "austria" = "europe",
  "greece" = "europe", "romania" = "europe", "ukraine" = "europe",
  # Americas
  "united states" = "americas", "usa" = "americas", "us" = "americas",
  "canada" = "americas", "mexico" = "americas", "brazil" = "americas",
  "argentina" = "americas", "colombia" = "americas", "peru" = "americas",
  "chile" = "americas", "uruguay" = "americas", "paraguay" = "americas",
  "bolivia" = "americas", "ecuador" = "americas", "venezuela" = "americas",
  "costa rica" = "americas", "guatemala" = "americas", "honduras" = "americas",
  "nicaragua" = "americas", "panama" = "americas",
  # Oceania
  "australia" = "oceania", "new zealand" = "oceania",
  "fiji" = "oceania", "papua new guinea" = "oceania"
)

# Resolve the metadata `region` field from either:
#   (a) the new "Continental region" cell (case-insensitive match to
#       africa / asia / europe / americas / oceania / global), OR
#   (b) the legacy single "Country / region" cell — by looking up the
#       country in COUNTRY_TO_REGION.
# Anything unresolved falls through to "global" (the existing default).
normalise_metadata_region <- function(metadata) {
  if (is.null(metadata) || !is.data.frame(metadata)) return(metadata)

  # The transposed-layout parser turns label -> column-name by stripping
  # everything after a slash and converting spaces to underscores. So a
  # template cell labelled "Continental region" lands in
  # `metadata$continental_region`; "Region" lands in `metadata$region`.
  # Look for either, plus the legacy combined "Country / region" cell
  # (which the parser stripped down to just `country`). First match wins.
  pull <- function(key) {
    if (!key %in% names(metadata)) return(NA_character_)
    v <- as.character(metadata[[key]][1])
    if (is.na(v)) NA_character_ else tolower(trimws(v))
  }
  region_raw <- pull("region")
  if (is.na(region_raw) || !nzchar(region_raw))
    region_raw <- pull("continental_region")
  country_raw <- pull("country")
  # Belt-and-braces fallback for any parser-key quirk (e.g. trailing-underscore
  # legacy variants like `country_` that older slash-strip code produced).
  if (is.na(country_raw) || !nzchar(country_raw))
    country_raw <- pull("country_")

  valid <- c("africa","asia","europe","americas","oceania","global")
  resolved <- if (!is.na(region_raw) && nzchar(region_raw) &&
                  region_raw %in% valid) {
    region_raw                                          # (a) explicit
  } else if (!is.na(country_raw) && nzchar(country_raw) &&
             country_raw %in% names(COUNTRY_TO_REGION)) {
    COUNTRY_TO_REGION[[country_raw]]                    # (b) country fallback
  } else "global"
  metadata$region <- resolved
  metadata
}

# C1: parameter renaming map (legacy → IPCC-aligned).
# parse_uploaded_template applies these so existing user templates keep working.
# New canonical names match the IPCC Inventory Software v2.95 symbols.
PARAM_ALIASES <- c(
  # Phase 2 — first batch
  "ash"          = "ASH",
  "DE_pct"       = "DE",
  "CP_pct"       = "CP",
  "Ym_pct"       = "Ym",
  "Frac_GASM"    = "Frac_GASMS",
  "Frac_LEACH"   = "Frac_LEACH_H",
  # IPCC alignment audit (2026-05): the managed-storage (MS) and pasture (PRP)
  # leaching/volatilisation fractions are conceptually distinct (Vol.4 Ch.10
  # Eq. 10.26/10.28 for MS vs Vol.4 Ch.11 Eq. 11.9/11.10 for PRP). The legacy
  # names "Frac_GASMS" and "Frac_LEACH_H" are the MS-side parameters;
  # "Frac_GASM_PRP" / "Frac_LEACH_PRP" are the PRP-side parameters. The new
  # canonical names exposed in the methodology and user guide are
  # "Frac_LeachMS" / "Frac_GasMS" / "Frac_LeachPRP" / "Frac_GasPRP" — accept
  # them as aliases here so docs and templates stay in sync.
  "Frac_LeachMS"  = "Frac_LEACH_H",
  "Frac_GasMS"    = "Frac_GASMS",
  "Frac_LeachPRP" = "Frac_LEACH_PRP",
  "Frac_GasPRP"   = "Frac_GASM_PRP",
  # R1.6 — full IPCC alignment per IPCC Inventory Software v2.95
  "cattle_pop"   = "N",
  "mature_weight"= "MW",
  "weight_gain"  = "WG",
  "milk_yield"   = "Milk",
  "milk_fat"     = "Fat",
  "protein_milk" = "MilkPR",
  "C_growth"     = "C",
  # Andreas 2026-05 #6 (final rename 2026-05-19): canonical name is now
  # "BW" (matches IPCC Eq 10.6 / 10.17 / 10.18 — see Vol 4 Ch 10 p.17).
  # Legacy "W" and "live_weight" still accepted on upload.
  "W"            = "BW",
  "live_weight"  = "BW",
  # Andreas 28/5/26 #2: canonical name is now `pct_pregnant` (was
  # `pct_calving`). This aligns with IPCC wording in Vol.4 Ch.10 Eq 10.13
  # (Cpregnancy is weighted by proportion of females pregnant) and extends
  # the parameter to pregnant heifers that have not yet calved. Legacy
  # `pct_calving` and `pct_lactating` are accepted on upload and renamed to
  # the canonical here. For sub-categories where lactation and pregnancy
  # populations differ, users should enter pct_pregnant (the tool also uses
  # it as the lactation-weight in Eq 10.8 NEl by convention).
  "pct_lactating" = "pct_pregnant",
  "pct_calving"   = "pct_pregnant"
)

# ---------------------------------------------------------------------------
# PARAMETER CATALOGUE  (central source of truth for the Vocab sheet and
#                        for pre-populating the Parameters sheet)
# ---------------------------------------------------------------------------
PARAM_CATALOGUE <- data.frame(
  # R1.6: parameter names fully IPCC-aligned (per IPCC Inventory Software v2.95).
  # Older names (cattle_pop, live_weight, DE_pct, etc.) are auto-renamed by
  # parse_uploaded_template via PARAM_ALIASES so legacy templates still work.
  # Andreas 2026-05-27 feedback: EF3_S, Frac_GASMS and Frac_LEACH_H were
  # removed from the Parameters sheet. EF3_S was never consumed by the
  # equation chain (direct MM N2O uses the per-MMS EF3 column from the
  # Manure_Management tab); Frac_GASMS / Frac_LEACH_H are specified per-MMS
  # in Manure_Management (Frac_GasMS_pct / Frac_LeachMS_pct) and only ever
  # served as scalar fallbacks here. The scalar fallbacks in ghg_emissions_vec
  # now resolve to the hardcoded IPCC 2019 defaults (0.21 / 0.02) via
  # get_param_alt(), which is the correct behaviour. The PRP-side fractions
  # (Frac_GASM_PRP / Frac_LEACH_PRP) and the indirect EFs (EF4 / EF5) and the
  # PRP direct EF (EF3_PRP) remain — they have no per-MMS equivalent.
  parameter = c(
    "N","BW","MW","WG",
    "Milk","Fat","pct_pregnant","DE",
    "Cfi","Ca","C","Cp","hours","CP",
    "Ym","Bo","ASH","UE",
    "EF3_PRP","EF4","EF5",
    "Frac_GASM_PRP","Frac_LEACH_PRP",
    "MilkPR","Tw"),
  definition = c(
    "Number of animals in this sub-category",
    "Average live body weight of the animals",
    "Mature (adult) body weight of the animals",
    "Average daily weight gain — set 0 for non-growing (adult) animals",
    "Daily milk yield per lactating cow (not sub-category-average — the tool multiplies by pct_pregnant internally). Set 0 for sub-categories that do not lactate.",
    "Fat content of milk (% by weight)",
    "Fraction of females in this sub-category that are pregnant during the year, between 0 and 1 — includes pregnant heifers that have not yet calved. Weights Cpregnancy in IPCC Eq 10.13 (NEp) and the milk-N retention term in Eq 10.33; the tool also applies it as the lactation-weight in Eq 10.8 (NEl). For sub-categories where lactation and pregnancy populations differ, enter the pregnancy fraction.",
    "Digestible energy as a percentage of gross energy — typical range 45-75%",
    "Maintenance energy coefficient — depends on sex and lactation status (IPCC Table 10.4)",
    "Activity coefficient for locomotion energy — depends on feeding situation (IPCC Table 10.5)",
    "Growth coefficient for the NEg equation — depends on sex and physiological status (IPCC Eq 10.6)",
    "Pregnancy coefficient — 0.10 for pregnant animals (IPCC Table 10.7)",
    "Daily working hours (Eq. 10.11) — set 0 if animals do no work; relevant only where animals are used for traction/load",
    "Crude protein (CP%) content of the diet — used to estimate nitrogen excretion",
    "Methane conversion factor: % of gross energy in feed converted to methane (IPCC Table 10.12)",
    "Maximum CH₄ producing capacity of manure (IPCC Table 10.16)",
    "Ash content of manure — IPCC default 0.08 (Eq 10.24 footnote)",
    "Urinary energy as fraction of gross energy — IPCC default 0.04 (Eq 10.24 footnote)",
    "N₂O emission factor for dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.1). 2019R EF3_PRP,CPP for cattle/poultry/pigs: aggregated 0.004; wet climate 0.006; dry climate 0.002. 2006 = 0.02.",
    "N₂O EF for atmospheric N deposition (IPCC Vol.4 Ch.11 Table 11.3). 2019R aggregated EF4 = 0.010 (range 0.002-0.018); wet climate 0.014; dry climate 0.005. 2006 = 0.010.",
    "N₂O EF for N leaching/runoff (IPCC Vol.4 Ch.11 Table 11.3). 2019R EF5 = 0.011 (range 0.000-0.020), no climate disaggregation. 2006 = 0.0075.",
    "Fraction of N volatilised from dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.3, FracGASM). 2019R = 0.21 (range 0.00-0.31); 2006 = 0.20.",
    "Fraction of N leached from pasture deposition (IPCC Vol.4 Ch.11 Table 11.3, FracLEACH-(H), wet climates only). 2019R = 0.24 (range 0.01-0.73); 2006 = 0.30; in dry climates = 0.",
    "Protein content of milk — feeds the milk-N term in IPCC Vol.4 Ch.10 Eq 10.33 (N retention for cattle, where the 6.38 milk-protein-to-N conversion is defined)",
    "Mean daily temperature in winter (°C) — Cfi cold-climate adjustment per IPCC Vol.4 Ch.10 Eq 10.2 (modifies the Cfi from Eq 10.3). Leave blank or set 20 to disable adjustment"),
  unit = c(
    "head","kg","kg","kg/day","kg/head/day","%","fraction (0-1)","%",
    "MJ/day/kg^0.75","dimensionless","dimensionless","dimensionless",
    "hours/day","%",
    "%","m3 CH₄/kg VS","fraction","fraction",
    "kg N2O-N/kg N","kg N2O-N/kg N","kg N2O-N/kg N",
    "fraction","fraction",
    "%","°C"),
  # IPCC alignment audit (2026-05) — verified against Vol.4 Ch.11 Tables 11.1
  # and 11.3:
  #   EF3_PRP,CPP : 0.004 aggregated 2019R (wet=0.006, dry=0.002); 2006 = 0.02
  #   EF4         : 0.010 aggregated 2019R (wet=0.014, dry=0.005); 2006 = 0.010
  #   EF5         : 0.011 (2019R); 2006 = 0.0075
  #   FracLEACH_PRP: 0.24 (2019R wet); 2006 = 0.30; dry = 0
  # Bo: 0.13 = 2019R Vol.4 Ch.10 Table 10.16(a) "Other regions, low productivity" cattle (2006 Africa = 0.10).
  # Andreas review round 2 (2026-06): Africa dairy Milk and MilkFat defaults
  # corrected to IPCC 2019R Vol.4 Ch.10 Annex Table 10A.1 — Milk 3.5 kg/d
  # (was 4.0), MilkFat 4.3% (was 4.0).
  ipcc_default = c(
    NA, 275, 300, 0.0, 3.5, 4.3, 0.60, 55.0,
    0.386, 0.17, 0.8, 0.10, 0.0, 10.0,
    6.5, 0.13, 0.08, 0.04,
    0.004, 0.010, 0.011,
    0.21, 0.24,
    3.3, 20),
  # Uncertainty % per Penman et al. (2000) / Monni et al. (2007).
  # NA = asymmetric: use suggested_lower_bound / suggested_upper_bound instead.
  suggested_uncertainty_pct = c(
    10, 15, 10, 30, 20, 10, 20, 15,   # N..DE
    30, 30, 30, 10, 20, 15,            # Cfi, Ca, C, Cp, hours, CP
    8, 20, 25, 25,                     # Ym, Bo, ASH, UE
    NA, NA, NA,                        # EF3_PRP, EF4, EF5 (asymmetric — use IPCC bounds)
    NA, NA,                            # Frac_GASM_PRP, Frac_LEACH_PRP (IPCC 2019 Table 11.3 — asymmetric bounds)
    10, 25),                           # MilkPR, Tw
  suggested_distribution = c(
    "normal","normal","normal","pert","normal","normal","beta","normal",
    "pert","triangular","triangular","beta","pert","normal",
    "pert","pert","pert","pert",
    "pert","lognormal","lognormal",
    "pert","pert",
    "normal","normal"),
  # Absolute lower/upper bounds for asymmetric parameters — sourced from IPCC 2006/2019 Refinement.
  # These override the symmetric ±pct formula in the Excel template.
  # IPCC alignment audit (2026-05) — corrected source attribution:
  #   EF3_PRP    → Vol.4 Ch.11 Table 11.1 (PRP direct-N2O EFs)
  #   EF4 / EF5  → Vol.4 Ch.11 Table 11.3 (indirect-N2O EFs; 2019 Refinement
  #                                          values used for the central, with
  #                                          wider Penman/Monni bounds retained)
  #   Frac_GASM_PRP / Frac_LEACH_PRP → Vol.4 Ch.11 Table 11.3 (2019 Refinement)
  suggested_lower_bound = c(
    NA, NA, NA, NA, NA, NA, NA, NA,
    NA, NA, NA, NA, NA, NA,
    NA, NA, NA, NA,
    0.0007, 0.002, 0.0005,  # EF3_PRP (Vol.4 Ch.11 Table 11.1: range [0.0007, 0.060]), EF4, EF5
    0.05, 0.05,            # Frac_GASM_PRP, Frac_LEACH_PRP
    NA, NA),
  suggested_upper_bound = c(
    NA, NA, NA, NA, NA, NA, NA, NA,
    NA, NA, NA, NA, NA, NA,
    NA, NA, NA, NA,
    0.060, 0.020, 0.025,  # EF3_PRP, EF4, EF5
    0.50, 0.80,           # Frac_GASM_PRP, Frac_LEACH_PRP
    NA, NA),
  # D1: IPCC convention adopted — only cattle_pop is true Activity Data;
  # everything else is a "coefficient" (combines into the per-head emission factor)
  param_type = c(
    "activity_data",          # N
    rep("coefficient", 23),   # all other production parameters + IPCC equation params
    "coefficient"),           # Tw
  # Andreas 2026-05 #5: renamed levels to avoid clash with IPCC "Tier" terminology.
  # "core" = must be entered by user; "advanced" = IPCC coefficient, pre-filled with default.
  param_tier = c(
    "core","core","core","core","core","core","core","core",
    "advanced","advanced","advanced","advanced","core","core",
    "advanced","advanced","advanced","advanced",
    "advanced","advanced","advanced",
    "advanced","advanced",
    "core","advanced"),
  # TRUE = user can reduce this uncertainty by improving local data/surveys;
  # FALSE = IPCC coefficient — requires dedicated measurement research to improve
  user_reducible = c(
    TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
    FALSE, FALSE, FALSE, FALSE, TRUE, TRUE,
    FALSE, FALSE, FALSE, FALSE,
    FALSE, FALSE, FALSE,
    FALSE, FALSE,
    TRUE, TRUE),
  # IPCC alignment audit (2026-05): corrected references —
  #   Tw cold-climate adjustment is Vol.4 Ch.10 Eq 10.2 (confirmed in both
  #     2006 and 2019R Vol.4 Ch.10 — it's the formal numbered equation for
  #     Cfi(in_cold) = Cfi + 0.0048 * (20 - Tw); modifies Eq 10.3).
  ipcc_ref = c(
    "","Table 10A.2","Table 10A.2","Table 10A.1","","","","Eq 10.14--16",
    "Table 10.4","Table 10.5","Eq 10.6","Table 10.7","Eq 10.11","Eq 10.32",
    "Table 10.12","Table 10.16","Eq 10.24","Eq 10.24",
    "Ch.11 Table 11.1","Ch.11 Table 11.3","Ch.11 Table 11.3",
    "Ch.11 Table 11.3","Ch.11 Table 11.3",
    "Eq 10.33","Eq 10.2"),
  # T1.3: IPCC Inventory Software variable names (from screenshots provided by Andreas, May 2026).
  # Surfacing these here means inventory teams can match our column to the IPCC
  # software's terminology one-to-one when transposing data between tools.
  # Format: "<symbol> — <full name in IPCC software>"
  ipcc_software_name = c(
    "N(T) — Annual Average Population (head)",
    "BW — Body weight (kg) [also TAM = Typical Animal Mass; IPCC Eq 10.3/10.6/10.17/10.18]",
    "(MW) — Mature body weight, used in NEg equation",
    "WG — Daily weight gain (Average Daily Feed Intake tab)",
    "Milk — Average daily milk production (kg/day)",
    "Fat — Fat content of milk (% by weight)",
    "pct_pregnant — Fraction of females pregnant in a year (Cpregnancy weight in Eq 10.13; includes pregnant heifers)",
    "DE% — Feed digestibility (%)",
    "Cfi — Coefficient for calculating Net Energy for Maintenance",
    "Ca — Activity coefficient",
    "(C) — Growth coefficient (sex-dependent: female 0.8 / castrate 1.0 / bull 1.2)",
    "Cpregnancy — Coefficient for calculating Net Energy for Pregnancy",
    "(hours) — Daily working hours",
    "CP% — Percent crude protein in diet",
    "Ym — Methane conversion factor (% of GE → CH4)",
    "Bo — Maximum methane producing capacity",
    "ASH — Ash content of manure (fraction of dry matter)",
    "UE — Urinary Energy fraction of GE",
    "EF3(PRP) — Direct N₂O EF, manure on pasture/range/paddock",
    "EF4 — N₂O EF for atmospheric N deposition (Vol 4 Ch 11)",
    "EF5 — N₂O EF for N leaching/runoff (Vol 4 Ch 11)",
    "FracGASM — Fraction of N volatilised from pasture deposition (Table 11.3)",
    "Frac_leach-(H) — Fraction of N lost through leaching from pasture deposition (Table 11.3)",
    "Milk PR% — Milk protein content (1.9 + 0.4*Fat)",
    "Tw — Mean winter daily temperature (°C); IPCC software Cfi adjustment input"),
  stringsAsFactors = FALSE
)


# ---------------------------------------------------------------------------
# Correlation matrix template (Lolita 2026-06-02 review).
# Produces a square CSV the user can drop into the "Advanced — manual entry"
# correlation-mode upload. The row and column names are the canonical
# PARAM_CATALOGUE$parameter values so the upload parser + expand_corr_matrix()
# in the simulation observer can pick up every pair correctly. Without this
# template, users hand-writing a matrix risk typos in headers that get
# silently dropped (expand_corr_matrix uses intersect() — names that don't
# match the simulation's parameter list contribute no correlation).
#
# include_example = TRUE pre-fills the seven structural-defaults pairs
# (BW <-> MW, BW <-> WG, Milk <-> Fat, Milk <-> BW, Milk <-> DE, DE <-> CP,
# DE <-> Ym) via build_ipcc_preset_corr() so the example matrix is IDENTICAL
# to what the in-app "Structural defaults" preset applies — single source of
# truth in PRESET_PAIRS (R/mc_sampling.R).
generate_corr_matrix_template <- function(filepath, include_example = FALSE) {
  params <- PARAM_CATALOGUE$parameter
  m <- if (include_example) {
    build_ipcc_preset_corr(params)
  } else {
    out <- diag(length(params))
    rownames(out) <- colnames(out) <- params
    out
  }
  # write.csv with row.names = TRUE so the first column carries the parameter
  # names — exactly the shape read.csv(..., row.names = 1, check.names = FALSE)
  # expects in the upload parser (R/app_server.R observeEvent(corr_matrix_upload)).
  utils::write.csv(m, file = filepath, row.names = TRUE)
  invisible(filepath)
}

# ---------------------------------------------------------------------------
# MAIN ENTRY POINT
# ---------------------------------------------------------------------------
generate_template <- function(filepath, include_example = FALSE,
                                ipcc_version = "2006") {
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    generate_template_openxlsx(filepath, include_example, ipcc_version = ipcc_version)
  } else {
    message("Package 'openxlsx' not found — install it for dropdown menus:\n",
            "  install.packages('openxlsx')\n",
            "Falling back to basic template (no dropdowns).")
    generate_template_basic(filepath, include_example)
  }
  invisible(filepath)
}


# ===========================================================================
# OPENXLSX VERSION — full dropdowns, formulas, colour-coding
# ===========================================================================
generate_template_openxlsx <- function(filepath, include_example,
                                         ipcc_version = "2006") {

  wb <- openxlsx::createWorkbook()
  openxlsx::modifyBaseFont(wb, fontName = "Calibri", fontSize = 10)

  # ── colour palette ─────────────────────────────────────────────────────────
  C_HEADER     <- "#1B4332"   # dark green  — column headers
  C_SECTION    <- "#2D6A4F"   # mid green   — section labels
  C_REQUIRED   <- "#FFF9C4"   # pale yellow — cells user MUST fill (core activity data)
  C_TECHNICAL  <- "#FFF3E0"   # pale orange — IPCC coefficient pre-filled, editable
  C_DROPDOWN   <- "#E8F5E9"   # pale green  — controlled-vocab dropdowns
  C_PREFILL    <- "#E3F2FD"   # pale blue   — pre-filled info (read only)
  C_AUTO       <- "#F5F5F5"   # light grey  — auto-computed formulas
  C_OPTIONAL   <- "#FFFFFF"   # white       — optional free-text
  C_GREY_TXT   <- "#6B6B6B"
  C_RED        <- "#C62828"   # for required labels

  # ── styles ─────────────────────────────────────────────────────────────────
  mk <- openxlsx::createStyle  # shortcut

  s_hdr  <- mk(fontColour="white", fgFill=C_HEADER, fontName="Calibri",
                fontSize=10, textDecoration="bold", halign="center",
                valign="center", wrapText=TRUE,
                border="TopBottomLeftRight", borderColour="#2D6A4F")
  s_req  <- mk(fgFill=C_REQUIRED, fontName="Calibri", fontSize=10,
                border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="left", valign="top")
  s_drop <- mk(fgFill=C_DROPDOWN, fontName="Calibri", fontSize=10,
                border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="left", valign="top")
  s_pre  <- mk(fgFill=C_PREFILL, fontColour="#1565C0", fontName="Calibri",
                fontSize=9, border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="left", valign="top")
  s_auto <- mk(fgFill=C_AUTO, fontColour=C_GREY_TXT, fontName="Calibri",
                fontSize=9, border="TopBottomLeftRight", borderColour="#DDDDDD",
                halign="left", valign="top")
  s_opt  <- mk(fgFill=C_OPTIONAL, fontName="Calibri", fontSize=10,
                border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="left", valign="top")
  s_sec  <- mk(fontColour="white", fgFill=C_SECTION, fontName="Calibri",
                fontSize=10, textDecoration="bold", halign="left", valign="center")
  s_lbl  <- mk(fontName="Calibri", fontSize=9, textDecoration="bold",
                halign="right", valign="center", fontColour=C_GREY_TXT)
  s_note <- mk(fontName="Calibri", fontSize=8, fontColour=C_GREY_TXT,
                textDecoration="italic", halign="left", valign="top",
                wrapText=TRUE)
  s_bold <- mk(fontName="Calibri", fontSize=10, textDecoration="bold",
                halign="left", valign="center")
  s_num  <- mk(fgFill=C_REQUIRED, fontName="Calibri", fontSize=10,
                border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="right", valign="top", numFmt="0.0000")
  s_tech <- mk(fgFill=C_TECHNICAL, fontName="Calibri", fontSize=10,
                border="TopBottomLeftRight", borderColour="#BBBBBB",
                halign="left", valign="top")

  # helper ─────────────────────────────────────────────────────────────────
  add_validation <- function(sheet, col, rows, list_key) {
    # Use cell-range reference — produces standard <dataValidation> with visible arrows
    ref <- list_ref(list_key)
    openxlsx::dataValidation(wb, sheet, col = col, rows = rows,
                             type = "list", operator = "equal", value = ref,
                             showInputMsg = TRUE, showErrorMsg = TRUE)
  }

  apply_style <- function(sheet, style, rows, cols) {
    openxlsx::addStyle(wb, sheet, style = style, rows = rows, cols = cols,
                       gridExpand = TRUE, stack = FALSE)
  }

  # ── vocabulary lists (used by multiple sheets) ────────────────────────────
  V_SPECIES   <- c("cattle_dairy","cattle_non_dairy","buffalo")
  V_IPCCVER   <- c("2006","2019_refinement")
  V_DIST      <- c("normal","posnorm","lognormal","beta",
                   "triangular","pert","uniform","constant","tnorm_0_1")
  V_PTYPE     <- c("activity_data","coefficient")
  V_QUALITY   <- c("measured","country_specific","regional_default",
                   "ipcc_default","expert_judgement")
  # Andreas 28/5/26 follow-up: the QA benchmark deviation check for BW reads
  # the user's continent from `region`. The old single "Country / region"
  # field was free text and got typed as a country name ("Zimbabwe"),
  # which silently fell back to the global default. The new template has a
  # separate dropdown-constrained Continental region cell using these slugs.
  V_REGION    <- c("africa","asia","europe","americas","oceania","global")
  # TT.3: MMS list sourced from MMS_DEFAULTS (covers IPCC 2006 + 2019).
  # Round 7.1 (Andreas Template #3 follow-up): the MMS dropdown now filters to
  # the systems valid for the chosen IPCC version, instead of always showing
  # all 12 entries. Two separate template downloads (2006 / 2019) are exposed
  # on Tab 1; each generates its own filtered dropdown list. The previous
  # behaviour deferred the version mismatch to upload-time validation only —
  # this change matches the dropdown to the user's selected version up-front.
  V_MMS       <- if (exists("get_mms_for_version"))
                   get_mms_for_version(ipcc_version)$id
                 else MMS_DEFAULTS$id

  # Kept for Vocab reference tables (informational, no longer used as dropdowns)
  V_SUBSYS    <- c("dairy_cows","other_cows","bulls","oxen",
                   "heifers","growing_males","calves_female","calves_male",
                   "feedlot_cattle")
  V_FEED      <- c("stall_fed","pasture_flat","pasture_hilly")

  N_DATA_ROWS <- 200   # rows to apply formatting/validation in Parameters

  # ── Named vocabulary lists (order defines column index in _Lists) ──────────
  # Each list becomes one column; add_validation references these ranges.
  V_LISTS <- list(
    ipccver = V_IPCCVER,  # col A
    dist    = V_DIST,     # col B
    ptype   = V_PTYPE,    # col C
    quality = V_QUALITY,  # col D
    mms     = V_MMS,      # col E
    species = V_SPECIES,  # col F
    region  = V_REGION    # col G  (Andreas 28/5/26 follow-up: BW benchmark)
  )

  # Helper: return Excel range string for a named list
  list_ref <- function(key) {
    idx <- which(names(V_LISTS) == key)
    col_letter <- LETTERS[idx]
    n <- length(V_LISTS[[key]])
    sprintf("'_Lists'!$%s$2:$%s$%d", col_letter, col_letter, n + 1)
  }

  # =========================================================================
  # SHEET: _Lists (hidden — vocabulary columns for Excel dropdown validation)
  # =========================================================================
  openxlsx::addWorksheet(wb, "_Lists", visible = FALSE)

  # Write each vocabulary list as a column (row 1 = header, rows 2+ = values)
  for (i in seq_along(V_LISTS)) {
    key <- names(V_LISTS)[i]
    vals <- V_LISTS[[i]]
    openxlsx::writeData(wb, "_Lists",
                        data.frame(x = c(key, vals), stringsAsFactors = FALSE),
                        startRow = 1, startCol = i, colNames = FALSE)
  }

  # Sub-category property lookup (used by Vocab) — placed after vocabulary cols
  lut_start_col <- length(V_LISTS) + 2   # leave a gap
  subcat_lut <- data.frame(
    subsystem  = V_SUBSYS,
    sex        = unlist(SEX_BY_SUBCAT[V_SUBSYS]),
    age_class  = unlist(AGE_BY_SUBCAT[V_SUBSYS]),
    Cfi        = unlist(CFI_BY_SUBCAT[V_SUBSYS]),
    LW_default = unlist(LW_BY_SUBCAT[V_SUBSYS]),
    MW_default = unlist(MW_BY_SUBCAT[V_SUBSYS]),
    WG_default = unlist(WG_BY_SUBCAT[V_SUBSYS]),
    C_growth   = unlist(C_GROWTH_BY_SUBCAT[V_SUBSYS]),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "_Lists", subcat_lut, startRow = 1, startCol = lut_start_col)

  # MCF lookup (used by Vocab)
  openxlsx::writeData(wb, "_Lists", MMS_DEFAULTS,
                      startRow = 1, startCol = lut_start_col + ncol(subcat_lut) + 1)

  # =========================================================================
  # SHEET: README
  # =========================================================================
  openxlsx::addWorksheet(wb, "README", tabColour = "#2D6A4F", gridLines = FALSE)
  openxlsx::setColWidths(wb, "README", cols = 1:3, widths = c(6, 28, 70))

  readme_title <- data.frame(
    x = "Cattle GHG Uncertainty Calculator — Input Template",
    stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "README", readme_title, startRow = 1, startCol = 1,
                      colNames = FALSE)
  apply_style("README", mk(fontColour="white", fgFill=C_HEADER, fontSize=16,
                            textDecoration="bold", halign="left", valign="center"),
              rows=1, cols=1:3)
  openxlsx::mergeCells(wb, "README", cols=1:3, rows=1)
  openxlsx::setRowHeights(wb, "README", rows=1, heights=36)

  legend <- data.frame(
    Colour = c("Pale yellow","Pale green","Pale blue","Light grey","White"),
    Meaning = c(
      "REQUIRED — you must fill this in",
      "CONTROLLED — choose from the dropdown list",
      "PRE-FILLED — read the value, keep or override (emission factors pre-filled with IPCC defaults)",
      "AUTO-COMPUTED — calculated from your inputs, do not edit",
      "OPTIONAL — free text or leave blank (white lower_bound/upper_bound columns override the symmetric auto-computed bounds for asymmetric distributions)"),
    stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "README", legend, startRow = 3, startCol = 1,
                      colNames = TRUE)
  apply_style("README", s_hdr,  rows=3, cols=1:2)
  apply_style("README", s_req,  rows=4, cols=1:2)
  apply_style("README", s_drop, rows=5, cols=1:2)
  apply_style("README", s_pre,  rows=6, cols=1:2)
  apply_style("README", s_auto, rows=7, cols=1:2)
  apply_style("README", s_opt,  rows=8, cols=1:2)

  steps <- data.frame(
    Step = paste0("Step ", 1:7),
    Action = c(
      "Fill in the Inventory_Metadata sheet (country, species, inventory year). Note: MCF values for manure must be entered manually in Manure_Management — see Vocab sheet for IPCC Table 10.17 reference values by climate zone.",
      "In the Parameters sheet, fill in cattle_type (col A: 'dairy' or 'other'), aggregation_level (col B: your region/AEZ/system name), and optionally sub_category (col C: cows/heifers/calves/etc.).",
      "Fill in the VALUE (col G) for each parameter. Emission factor parameters (Cfi, Ym, Bo, etc.) are pre-filled with IPCC defaults — update with your own values if available.",
      "Fill in UNCERTAINTY_PCT (col H) for symmetric distributions — LOWER and UPPER bounds auto-compute. For asymmetric distributions (triangular/PERT): also fill LOWER_BOUND (col I) and UPPER_BOUND (col J) with the min/max values.",
      "To add a second sub-category: copy the parameter rows, paste below, change cattle_type/aggregation_level/sub_category.",
      "Fill in the Manure_Management sheet: one row per MMS type per sub-category. Enter MCF and EF3 values (look up IPCC Table 10.17 and 10.21 in the Vocab sheet). Fractions must sum to 100% per sub-category.",
      "Optionally fill in the Parameter_TimeSeries sheet with historical annual values (one row per year, one column per parameter) to enable automatic activity data correlation analysis."),
    stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "README", steps, startRow = 10, startCol = 1,
                      colNames = TRUE)
  apply_style("README", s_hdr,  rows=10, cols=1:2)
  apply_style("README", s_bold, rows=11:17, cols=1)
  apply_style("README", s_note, rows=11:17, cols=2)
  openxlsx::setColWidths(wb, "README", cols = 1:2, widths = c(10, 90))
  openxlsx::setRowHeights(wb, "README", rows=11:17, heights=30)

  sheets_desc <- data.frame(
    Sheet = c("Inventory_Metadata","Parameters","Manure_Management",
              "Parameter_TimeSeries","Vocab"),
    Description = c(
      "Country, reporting year, species, IPCC guidelines version.",
      "All parameters for each animal sub-category. 3 user-defined naming columns (cattle_type, aggregation_level, sub_category). Emission factors pre-filled with IPCC defaults. Supports symmetric (uncertainty_pct) and asymmetric (lower_bound, upper_bound) distributions.",
      "Manure management system allocation. Enter MCF and EF3 values manually (see Vocab for IPCC reference tables). Fractions must sum to 100 per sub-category. Full distribution support for MCF and EF3.",
      "CORRELATIONS — one row per year, one column per activity data parameter. Fill in historical values; the app computes a Pearson correlation matrix automatically on upload (Tab 4). You only need columns you have data for.",
      "Parameter catalogue + IPCC MCF reference table (Table 10.17) + controlled vocabulary terms and definitions."),
    stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "README", sheets_desc, startRow = 20, startCol = 1,
                      colNames = TRUE)
  apply_style("README", s_hdr,  rows=20, cols=1:2)
  apply_style("README", s_note, rows=21:25, cols=1:2)

  # =========================================================================
  # SHEET: Inventory_Metadata
  # =========================================================================
  openxlsx::addWorksheet(wb, "Inventory_Metadata", tabColour = "#2D6A4F",
                         gridLines = FALSE)
  openxlsx::setColWidths(wb, "Inventory_Metadata",
                         cols = 1:4, widths = c(4, 24, 36, 60))
  openxlsx::setRowHeights(wb, "Inventory_Metadata",
                          rows = 1:8, heights = 24)

  # Write as label-value pairs (transposed layout — more readable)
  meta_fields <- list(
    list(label="Country",                  col="country",       req=TRUE,
         hint="Free text, e.g. Zimbabwe. Used in the report header.",
         dropdown=NULL),
    # Andreas 28/5/26 follow-up: split the old free-text "Country / region"
    # cell into a free-text Country (above) and a dropdown-constrained
    # Continental region (below). The region drives the QA benchmark
    # deviation check for BW (Vol.4 Ch.10 Annex Tables 10A.1 / 10A.2 /
    # 10A.3). Free-text country names like "Zimbabwe" were silently
    # falling back to the global default; the dropdown makes that
    # impossible.
    list(label="Continental region",       col="region",        req=TRUE,
         hint="Select your continent — drives the IPCC continental BW benchmark (Annex 10A.1/10A.2/10A.3).",
         dropdown="region"),
    list(label="Inventory year",           col="inventory_year",req=TRUE,
         hint="Integer year, e.g. 2021",                          dropdown=NULL),
    list(label="Livestock species",        col="species",       req=TRUE,
         hint="Select from dropdown",                             dropdown="species"),
    # Round 7.2: ipcc_version is no longer a dropdown — the user picks the
    # version at download time on Tab 1, and this cell is pre-set to match.
    # Hint reminds them not to change it without downloading the matching
    # template (otherwise the MMS dropdown won't line up).
    list(label="IPCC Guidelines version", col="ipcc_version",  req=FALSE,
         hint="Pre-set from your template download choice. Re-download from Tab 1 if you need to switch IPCC versions (the MMS dropdown is filtered to the version you pick).",
         dropdown=NULL),
    list(label="Prepared by",             col="prepared_by",   req=FALSE,
         hint="Agency / author name",                             dropdown=NULL),
    list(label="Notes",                   col="notes",         req=FALSE,
         hint="Scope, caveats, deviations from standard methodology. Note: MCF values for manure must be entered manually in Manure_Management — see Vocab sheet for IPCC Table 10.17 reference.", dropdown=NULL)
  )

  # Column headers
  openxlsx::writeData(wb, "Inventory_Metadata",
    data.frame(A="", B="Field", C="Value", D="Hint / valid options"),
    startRow=1, startCol=1, colNames=FALSE)
  apply_style("Inventory_Metadata", s_hdr, rows=1, cols=1:4)

  example_vals <- list(
    country="Country X", region="africa",
    inventory_year=2021, species="cattle_non_dairy",
    ipcc_version=ipcc_version,
    prepared_by="National GHG Inventory Team",
    notes="Hypothetical example inventory — replace with your country's data.")

  for (i in seq_along(meta_fields)) {
    f <- meta_fields[[i]]
    row_i <- i + 1
    # Column B: label
    openxlsx::writeData(wb, "Inventory_Metadata",
                        f$label, startRow=row_i, startCol=2, colNames=FALSE)
    apply_style("Inventory_Metadata", s_lbl, rows=row_i, cols=2)

    # Column C: value (required=yellow, optional=white)
    # Round 7.1: even on the blank template, pre-set ipcc_version so the
    # downloaded file's MMS dropdown lines up with the version the user
    # picked at download time.
    val <- if (include_example) {
      example_vals[[f$col]]
    } else if (identical(f$col, "ipcc_version")) {
      ipcc_version
    } else ""
    openxlsx::writeData(wb, "Inventory_Metadata",
                        val, startRow=row_i, startCol=3, colNames=FALSE)
    apply_style("Inventory_Metadata",
                if (f$req) s_req else s_opt, rows=row_i, cols=3)

    # Column D: hint
    openxlsx::writeData(wb, "Inventory_Metadata",
                        f$hint, startRow=row_i, startCol=4, colNames=FALSE)
    apply_style("Inventory_Metadata", s_note, rows=row_i, cols=4)

    # Dropdown validation on column C
    if (!is.null(f$dropdown))
      add_validation("Inventory_Metadata", col=3, rows=row_i, f$dropdown)
  }

  openxlsx::freezePane(wb, "Inventory_Metadata", firstRow=TRUE)


  # =========================================================================
  # SHEET: Parameters
  # =========================================================================
  openxlsx::addWorksheet(wb, "Parameters", tabColour = "#1B4332",
                         gridLines = TRUE)

  # Column layout (17 cols):
  # A  cattle_type      (required, free text: "dairy" / "other")
  # B  aggregation_level (required, free text: region/AEZ/production system)
  # C  sub_category     (optional, free text: cows/heifers/calves)
  # D  parameter        (pre-filled, info)
  # E  definition       (pre-filled, info)
  # F  unit             (pre-filled, info)
  # G  value            *** REQUIRED USER INPUT ***
  # H  uncertainty_pct  (yellow — fill for symmetric distributions)
  # I  lower_bound      (optional override — min value for asymmetric distributions)
  # J  upper_bound      (optional override — max value for asymmetric distributions)
  # K  distribution     (dropdown)
  # L  lower            (auto-formula: uses lower_bound if filled, else value*(1-pct/100))
  # M  upper            (auto-formula: uses upper_bound if filled, else value*(1+pct/100))
  # N  param_type       (pre-filled, info)
  # O  ipcc_ref         (pre-filled, info)
  # P  data_source      (optional, free text)
  # Q  data_quality     (dropdown, optional)

  # TT.2: data_quality column removed in v2.3 (was documentation-only, never used in calculations)
  P_COLS <- c("cattle_type","aggregation_level","sub_category",
              "parameter","definition","unit",
              "value","uncertainty_pct","lower_bound","upper_bound",
              "distribution","lower","upper",
              "param_type","ipcc_ref","data_source")
  P_WIDTHS <- c(14, 20, 16, 15, 46, 16, 10, 14, 12, 12, 12, 10, 10, 14, 12, 22)
  P_COL_IDX <- setNames(seq_along(P_COLS), P_COLS)

  openxlsx::setColWidths(wb, "Parameters", cols = seq_along(P_COLS), widths = P_WIDTHS)

  # Row 1: instruction banner
  openxlsx::writeData(wb, "Parameters",
    "HOW TO USE: YELLOW = core activity data — enter your own values. ORANGE = technical IPCC coefficient — pre-filled with defaults from Penman et al. (2000); uncertainty ranges from Penman (2000) / Monni et al. (2007); edit if you have country-specific values. GREEN = dropdown. BLUE = pre-filled info. GREY = auto-computed. PERCENTAGE FIELDS (DE_pct, milk_fat, CP_pct, Ym_pct, uncertainty_pct, etc.): enter the bare number, e.g. '45' for 45% — do NOT include the '%' symbol. uncertainty_pct is the ±% half-width of the 95% CI. For symmetric distributions: fill value (G) + uncertainty_pct (H). For asymmetric distributions (PERT/lognormal): fill lower_bound (I) and upper_bound (J) instead — these override the pct formula. Copy rows 4 onwards to add more sub-categories.",
    startRow=1, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Parameters", cols=1:16, rows=1)
  apply_style("Parameters",
    mk(fontColour="white", fgFill=C_SECTION, fontSize=9, textDecoration="italic",
       halign="left", valign="center", wrapText=TRUE),
    rows=1, cols=1:16)
  openxlsx::setRowHeights(wb, "Parameters", rows=1, heights=44)

  # Row 2: colour legend (mini legend)
  legend_labels <- c(
    "REQUIRED","REQUIRED","OPTIONAL","INFO","INFO","INFO",
    "REQUIRED","REQUIRED","OPT.OVERRIDE","OPT.OVERRIDE","DROPDOWN","AUTO","AUTO",
    "INFO","INFO","OPTIONAL")
  openxlsx::writeData(wb, "Parameters",
    as.data.frame(t(legend_labels)), startRow=2, startCol=1, colNames=FALSE)
  apply_style("Parameters",
    mk(fontSize=7, textDecoration="italic", halign="center",
       fontColour=C_GREY_TXT, fgFill="#FAFAFA"), rows=2, cols=1:16)
  openxlsx::setRowHeights(wb, "Parameters", rows=2, heights=14)

  # Row 3: column headers
  openxlsx::writeData(wb, "Parameters",
    as.data.frame(t(P_COLS)), startRow=3, startCol=1, colNames=FALSE)
  apply_style("Parameters", s_hdr, rows=3, cols=1:16)
  openxlsx::setRowHeights(wb, "Parameters", rows=3, heights=28)

  # Freeze rows 1-3 and column A
  openxlsx::freezePane(wb, "Parameters", firstActiveRow=4, firstActiveCol=2)

  # ── Build data rows per sub-category block ────────────────────────────────
  n_params <- nrow(PARAM_CATALOGUE)
  DATA_START <- 4   # first data row

  # Example values: hypothetical Country X activity data + IPCC defaults
  # Blank template: activity data blank, EFs pre-filled with IPCC defaults
  # Example values mirror the PARAM_CATALOGUE order; keep lengths == nrow(PARAM_CATALOGUE).
  ex_values <- c(500000, 275, 300, 0.10, 3.5, 4.3, 0.60, 55,
                 0.386, 0.17, 0.8, 0.10, 0, 10,
                 6.5, 0.13, 0.08, 0.04,   # Ym, Bo (2019R "Other regions" cattle), ASH, UE
                 # IPCC alignment audit (2026-05): verified against
                 # Vol.4 Ch.11 Tables 11.1 / 11.3. Andreas 2026-05-27: the
                 # managed-storage (MS) manure-N2O params (EF3_S, Frac_GASMS,
                 # Frac_LEACH_H) moved out of the Parameters sheet — they are
                 # specified per-MMS in the Manure_Management tab.
                 #   EF3_PRP,CPP aggregated 2019R = 0.004 (2006 = 0.02)
                 #   EF4 aggregated 2019R = 0.010 (2006 = 0.010; wet 0.014, dry 0.005)
                 #   EF5         2019R = 0.011 (2006 = 0.0075)
                 #   FracLEACH-(H) PRP-side 2019R wet = 0.24 (2006 = 0.30; dry = 0)
                 0.004, 0.010, 0.011,        # EF3_PRP, EF4, EF5
                 0.21, 0.24,                 # Frac_GASM_PRP, Frac_LEACH_PRP
                 3.3, 20)                    # MilkPR, Tw
  # Example uncertainties — asymmetric parameters use IPCC 2006/2019 bounds (lower/upper pre-filled).
  # NA = asymmetric parameter; lower_bound/upper_bound are pre-filled from catalogue instead.
  ex_unc <- c(10,15,10,30,20,10,20,15, 30,30,30,10,20,15, 8,20,25,25,
              NA,NA,NA,              # EF3_PRP, EF4, EF5 (IPCC bounds)
              NA,NA,                 # Frac_GASM_PRP, Frac_LEACH_PRP (IPCC 2019 Table 11.3 bounds)
              10, 25)                # MilkPR, Tw

  for (i in seq_len(n_params)) {
    r <- DATA_START + i - 1
    # Andreas 2026-05 #5: "technical" renamed to "advanced"; accept both during transition.
    is_tech <- PARAM_CATALOGUE$param_tier[i] %in% c("advanced", "technical")
    is_ef   <- PARAM_CATALOGUE$param_type[i] == "coefficient"

    # value column: technical params get IPCC default; core activity data left blank
    val_cell <- if (include_example) {
      ex_values[i]
    } else if (is_tech) {
      PARAM_CATALOGUE$ipcc_default[i]   # pre-fill all technical params with IPCC default
    } else {
      NA   # core activity data left blank
    }
    unc_cell <- if (include_example) ex_unc[i] else PARAM_CATALOGUE$suggested_uncertainty_pct[i]

    # For asymmetric parameters (unc_cell is NA): pre-fill lower_bound / upper_bound from catalogue
    lb_cell <- if (!is.na(unc_cell)) NA else PARAM_CATALOGUE$suggested_lower_bound[i]
    ub_cell <- if (!is.na(unc_cell)) NA else PARAM_CATALOGUE$suggested_upper_bound[i]

    row_data <- list(
      cattle_type       = if (include_example) "dairy"                      else "dairy",
      aggregation_level = if (include_example) "Country X – smallholder dairy" else "Region_or_system_name",
      sub_category      = if (include_example) "cows"                       else "sub_category_name",
      parameter         = PARAM_CATALOGUE$parameter[i],
      definition        = PARAM_CATALOGUE$definition[i],
      unit              = PARAM_CATALOGUE$unit[i],
      value             = val_cell,
      uncertainty_pct   = unc_cell,
      lower_bound       = lb_cell,
      upper_bound       = ub_cell,
      distribution      = PARAM_CATALOGUE$suggested_distribution[i],
      lower             = NA,  # formula below
      upper             = NA,  # formula below
      param_type        = PARAM_CATALOGUE$param_type[i],
      ipcc_ref          = PARAM_CATALOGUE$ipcc_ref[i],
      data_source       = if (include_example) "IPCC default / hypothetical Country X" else ""
    )

    # Write each column
    for (col_nm in names(row_data)) {
      ci <- P_COL_IDX[col_nm]
      val <- row_data[[col_nm]]
      if (!is.null(val) && !is.na(val))
        openxlsx::writeData(wb, "Parameters", val, startRow=r, startCol=ci,
                            colNames=FALSE)
    }

    # Andreas 2026-05 #22c: for example rows we know the value + uncertainty_pct
    # ahead of time, so pre-compute the lower/upper bounds as numeric cells.
    # This avoids the openxlsx-formula auto-recalc quirk where the lower/upper
    # cells showed blank until the user clicked into them. For blank rows we
    # still need the formula so the bounds populate as soon as the user fills
    # value + uncertainty_pct in Excel.
    g_col <- LETTERS[P_COL_IDX["value"]]           # "G"
    h_col <- LETTERS[P_COL_IDX["uncertainty_pct"]] # "H"
    i_col <- LETTERS[P_COL_IDX["lower_bound"]]     # "I"
    j_col <- LETTERS[P_COL_IDX["upper_bound"]]     # "J"
    val_i <- row_data$value
    unc_i <- row_data$uncertainty_pct
    lb_i  <- row_data$lower_bound
    ub_i  <- row_data$upper_bound
    have_numeric <- is.numeric(val_i) && length(val_i) == 1 && !is.na(val_i) &&
                    is.numeric(unc_i) && length(unc_i) == 1 && !is.na(unc_i)
    if (have_numeric) {
      lower_val <- if (!is.null(lb_i) && !is.na(lb_i) && is.numeric(lb_i)) lb_i
                   else val_i * (1 - unc_i / 100)
      upper_val <- if (!is.null(ub_i) && !is.na(ub_i) && is.numeric(ub_i)) ub_i
                   else val_i * (1 + unc_i / 100)
      openxlsx::writeData(wb, "Parameters", lower_val, startRow = r,
                          startCol = P_COL_IDX["lower"], colNames = FALSE)
      openxlsx::writeData(wb, "Parameters", upper_val, startRow = r,
                          startCol = P_COL_IDX["upper"], colNames = FALSE)
    } else {
      openxlsx::writeFormula(wb, "Parameters",
        x = sprintf('=IF(%s%d<>"",%s%d,IF(AND(%s%d<>"",%s%d<>""),%s%d*(1-%s%d/100),\"\"))',
                    i_col,r, i_col,r, g_col,r, h_col,r, g_col,r, h_col,r),
        startRow=r, startCol=P_COL_IDX["lower"])
      openxlsx::writeFormula(wb, "Parameters",
        x = sprintf('=IF(%s%d<>"",%s%d,IF(AND(%s%d<>"",%s%d<>""),%s%d*(1+%s%d/100),\"\"))',
                    j_col,r, j_col,r, g_col,r, h_col,r, g_col,r, h_col,r),
        startRow=r, startCol=P_COL_IDX["upper"])
    }
  }

  # ── Apply styles to data rows ──────────────────────────────────────────────
  data_rows  <- DATA_START:(DATA_START + n_params - 1)
  # Andreas 2026-05 #5: "technical" renamed to "advanced"; accept both during transition.
  core_rows  <- DATA_START - 1 + which(PARAM_CATALOGUE$param_tier == "core")
  tech_rows  <- DATA_START - 1 + which(PARAM_CATALOGUE$param_tier %in% c("advanced", "technical"))

  apply_style("Parameters", s_req,  rows=data_rows, cols=P_COL_IDX["cattle_type"])
  apply_style("Parameters", s_req,  rows=data_rows, cols=P_COL_IDX["aggregation_level"])
  apply_style("Parameters", s_opt,  rows=data_rows, cols=P_COL_IDX["sub_category"])
  apply_style("Parameters", s_pre,  rows=data_rows, cols=P_COL_IDX["parameter"])
  apply_style("Parameters", s_pre,  rows=data_rows, cols=P_COL_IDX["definition"])
  apply_style("Parameters", s_pre,  rows=data_rows, cols=P_COL_IDX["unit"])
  # value + uncertainty_pct: yellow for core (user enters), orange for technical (IPCC default pre-filled)
  apply_style("Parameters", s_req,  rows=core_rows, cols=P_COL_IDX["value"])
  apply_style("Parameters", s_req,  rows=core_rows, cols=P_COL_IDX["uncertainty_pct"])
  apply_style("Parameters", s_tech, rows=tech_rows, cols=P_COL_IDX["value"])
  apply_style("Parameters", s_tech, rows=tech_rows, cols=P_COL_IDX["uncertainty_pct"])
  apply_style("Parameters", s_opt,  rows=data_rows, cols=P_COL_IDX["lower_bound"])
  apply_style("Parameters", s_opt,  rows=data_rows, cols=P_COL_IDX["upper_bound"])
  apply_style("Parameters", s_drop, rows=data_rows, cols=P_COL_IDX["distribution"])
  apply_style("Parameters", s_auto, rows=data_rows, cols=P_COL_IDX["lower"])
  apply_style("Parameters", s_auto, rows=data_rows, cols=P_COL_IDX["upper"])
  apply_style("Parameters", s_pre,  rows=data_rows, cols=P_COL_IDX["param_type"])
  apply_style("Parameters", s_pre,  rows=data_rows, cols=P_COL_IDX["ipcc_ref"])
  apply_style("Parameters", s_opt,  rows=data_rows, cols=P_COL_IDX["data_source"])
  openxlsx::setRowHeights(wb, "Parameters", rows=data_rows, heights=18)

  # ── Extend styles + dropdowns to extra blank rows (rows after the block) ──
  extra_rows <- (DATA_START + n_params):(DATA_START + N_DATA_ROWS)
  apply_style("Parameters", s_req,  rows=extra_rows, cols=P_COL_IDX["cattle_type"])
  apply_style("Parameters", s_req,  rows=extra_rows, cols=P_COL_IDX["aggregation_level"])
  apply_style("Parameters", s_opt,  rows=extra_rows, cols=P_COL_IDX["sub_category"])
  apply_style("Parameters", s_req,  rows=extra_rows, cols=P_COL_IDX["value"])
  apply_style("Parameters", s_req,  rows=extra_rows, cols=P_COL_IDX["uncertainty_pct"])
  apply_style("Parameters", s_opt,  rows=extra_rows, cols=P_COL_IDX["lower_bound"])
  apply_style("Parameters", s_opt,  rows=extra_rows, cols=P_COL_IDX["upper_bound"])
  apply_style("Parameters", s_drop, rows=extra_rows, cols=P_COL_IDX["distribution"])
  apply_style("Parameters", s_auto, rows=extra_rows, cols=P_COL_IDX["lower"])
  apply_style("Parameters", s_auto, rows=extra_rows, cols=P_COL_IDX["upper"])

  # Formulas for extra rows
  for (r in extra_rows) {
    g_col <- LETTERS[P_COL_IDX["value"]]
    h_col <- LETTERS[P_COL_IDX["uncertainty_pct"]]
    i_col <- LETTERS[P_COL_IDX["lower_bound"]]
    j_col <- LETTERS[P_COL_IDX["upper_bound"]]
    openxlsx::writeFormula(wb, "Parameters",
      x = sprintf('=IF(%s%d<>"",%s%d,IF(AND(%s%d<>"",%s%d<>""),%s%d*(1-%s%d/100),\"\"))',
                  i_col,r, i_col,r, g_col,r, h_col,r, g_col,r, h_col,r),
      startRow=r, startCol=P_COL_IDX["lower"])
    openxlsx::writeFormula(wb, "Parameters",
      x = sprintf('=IF(%s%d<>"",%s%d,IF(AND(%s%d<>"",%s%d<>""),%s%d*(1+%s%d/100),\"\"))',
                  j_col,r, j_col,r, g_col,r, h_col,r, g_col,r, h_col,r),
      startRow=r, startCol=P_COL_IDX["upper"])
  }

  # ── Dropdown validations for Parameters (rows 4 to DATA_START+N_DATA_ROWS) ─
  all_data_rows <- DATA_START:(DATA_START + N_DATA_ROWS)
  add_validation("Parameters", P_COL_IDX["distribution"], all_data_rows, "dist")

  # ── Separator row between the pre-populated block and empty rows ──────────
  sep_row <- DATA_START + n_params
  openxlsx::writeData(wb, "Parameters",
    "--- Add more sub-categories below: copy rows 4 onward, paste here, change cattle_type/aggregation_level/sub_category ---",
    startRow=sep_row, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Parameters", cols=1:16, rows=sep_row)
  apply_style("Parameters",
    mk(fgFill="#E8EAF6", fontColour="#3949AB", fontSize=8,
       textDecoration="italic", halign="center"),
    rows=sep_row, cols=1:16)

  # =========================================================================
  # SHEET: Manure_Management
  # =========================================================================
  openxlsx::addWorksheet(wb, "Manure_Management", tabColour = "#1B4332",
                         gridLines = TRUE)

  # Round 7 R1.12: per-MMS Frac_GasMS / Frac_LeachMS columns.
  # Andreas 2026-05 #22b: Bo removed from Manure_Management — it is animal-
  # sub-category-specific (varies by dairy vs non-dairy, not by MMS) and the
  # app reads it from the Parameters sheet only. The earlier MM column was
  # never consumed and lacked uncertainty inputs (#22d), so it created
  # confusion without affecting calculations.
  # Andreas 28/5/26 #4: per-MMS uncertainty on the fraction_pct allocation.
  # The new columns (lower_fraction / upper_fraction / distribution_fraction)
  # let users specify uncertainty around each MMS share. The sampler then
  # surfaces each sampled column as fraction_<mms> in the sensitivity output
  # so MMS allocation can finally show up as an influential parameter.
  # Per-iteration rows are renormalised so they sum to 1.
  MM_COLS   <- c("cattle_type","aggregation_level","sub_category",
                 "mms_type","fraction_pct",
                 "lower_fraction","upper_fraction","distribution_fraction",
                 "MCF_pct","lower_mcf","upper_mcf","distribution_mcf",
                 "EF3","lower_ef3","upper_ef3","distribution_ef3",
                 "Frac_GasMS_pct","lower_frac_gas","upper_frac_gas","distribution_frac_gas",
                 "Frac_LeachMS_pct","lower_frac_leach","upper_frac_leach","distribution_frac_leach")
  MM_WIDTHS <- c(14, 20, 16, 18, 12, 12, 12, 18,
                 10, 10, 10, 15, 10, 10, 10, 15,
                 14, 12, 12, 18, 14, 12, 12, 18)
  MM_NCOL   <- length(MM_COLS)

  openxlsx::setColWidths(wb, "Manure_Management",
                         cols=seq_along(MM_COLS), widths=MM_WIDTHS)

  # Instruction banner
  openxlsx::writeData(wb, "Manure_Management",
    "Enter one row per manure management system (MMS) per sub-category. fraction_pct values for the same cattle_type+aggregation_level+sub_category MUST sum to 100. SUB-CATEGORY HANDLING: if all sub-categories of the same cattle_type+aggregation_level use the same MMS allocation, you may leave sub_category blank — the values will apply to every sub-category in that group. If sub-categories differ (e.g. cows vs calves), provide a separate set of rows per sub-category. Enter MCF values from IPCC Table 10.17 for your climate zone (see Vocab sheet). EF3 from IPCC Table 10.21. For asymmetric distributions, fill lower_mcf/upper_mcf or lower_ef3/upper_ef3 with min/max values.",
    startRow=1, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Manure_Management", cols=1:MM_NCOL, rows=1)
  apply_style("Manure_Management",
    mk(fontColour="white", fgFill=C_SECTION, fontSize=9, textDecoration="italic",
       halign="left", valign="center", wrapText=TRUE),
    rows=1, cols=1:MM_NCOL)
  openxlsx::setRowHeights(wb, "Manure_Management", rows=1, heights=44)

  openxlsx::writeData(wb, "Manure_Management",
    as.data.frame(t(MM_COLS)), startRow=2, startCol=1, colNames=FALSE)
  apply_style("Manure_Management", s_hdr, rows=2, cols=1:MM_NCOL)

  hints_mm <- data.frame(
    cattle_type="dairy / other (free text)",
    aggregation_level="Region / AEZ / production system (free text)",
    sub_category="Optional: cows / heifers / calves (free text)",
    mms_type="Select from dropdown",
    fraction_pct="% of manure to this MMS (all rows per sub-cat must sum to 100)",
    lower_fraction="Optional: min % for the fraction_pct uncertainty range (leave blank if known exactly)",
    upper_fraction="Optional: max % for the fraction_pct uncertainty range (leave blank if known exactly)",
    distribution_fraction="Distribution for fraction_pct uncertainty — select from dropdown (default pert). Per-iteration rows are renormalised to sum to 100%.",
    MCF_pct="Methane conv. factor % — look up IPCC Table 10.17 in Vocab sheet",
    lower_mcf="Optional: min value for asymmetric MCF distribution",
    upper_mcf="Optional: max value for asymmetric MCF distribution",
    distribution_mcf="Distribution for MCF uncertainty — select from dropdown",
    EF3="Direct N2O EF — look up IPCC Table 10.21 in Vocab sheet",
    lower_ef3="Optional: min value for asymmetric EF3 distribution",
    upper_ef3="Optional: max value for asymmetric EF3 distribution",
    distribution_ef3="Distribution for EF3 uncertainty — select from dropdown",
    Frac_GasMS_pct="Volatilisation fraction % per MMS — IPCC 2019 Table 10.22",
    lower_frac_gas="Optional: min for asymmetric Frac_GasMS distribution",
    upper_frac_gas="Optional: max for asymmetric Frac_GasMS distribution",
    distribution_frac_gas="Distribution for Frac_GasMS — select from dropdown",
    Frac_LeachMS_pct="Leaching fraction % per MMS — IPCC 2019 Table 10.23",
    lower_frac_leach="Optional: min for asymmetric Frac_LeachMS distribution",
    upper_frac_leach="Optional: max for asymmetric Frac_LeachMS distribution",
    distribution_frac_leach="Distribution for Frac_LeachMS — select from dropdown",
    stringsAsFactors=FALSE)
  openxlsx::writeData(wb, "Manure_Management", hints_mm, startRow=3, startCol=1,
                      colNames=FALSE)
  apply_style("Manure_Management", s_note, rows=3, cols=1:MM_NCOL)
  openxlsx::setRowHeights(wb, "Manure_Management", rows=3, heights=36)
  openxlsx::freezePane(wb, "Manure_Management", firstActiveRow=4)

  # Example or blank data
  if (include_example) {
    manure_data <- data.frame(
      cattle_type=c("dairy","dairy"),
      aggregation_level=c("Country X \u2013 smallholder dairy","Country X \u2013 smallholder dairy"),
      sub_category=c("cows","cows"),
      mms_type=c("pasture","solid_storage"),
      fraction_pct=c(70,30),
      # Example asymmetric \u00b110 pp uncertainty around the central allocation.
      # Per-iteration rows are renormalised to sum to 100 so this stays on
      # the simplex.
      lower_fraction=c(60,20),
      upper_fraction=c(80,40),
      distribution_fraction=c("pert","pert"),
      MCF_pct=c(1.5,5.0),
      lower_mcf=c(NA_real_,NA_real_),
      upper_mcf=c(NA_real_,NA_real_),
      distribution_mcf=c("pert","pert"),
      EF3=c(0.02,0.005),
      lower_ef3=c(NA_real_,NA_real_),
      upper_ef3=c(NA_real_,NA_real_),
      distribution_ef3=c("pert","pert"),
      Frac_GasMS_pct=c(mms_frac_defaults_2019("pasture")$frac_gas * 100,
                       mms_frac_defaults_2019("solid_storage")$frac_gas * 100),
      lower_frac_gas=c(mms_frac_defaults_2019("pasture")$frac_gas_low * 100,
                       mms_frac_defaults_2019("solid_storage")$frac_gas_low * 100),
      upper_frac_gas=c(mms_frac_defaults_2019("pasture")$frac_gas_high * 100,
                       mms_frac_defaults_2019("solid_storage")$frac_gas_high * 100),
      distribution_frac_gas=c("pert","pert"),
      Frac_LeachMS_pct=c(mms_frac_defaults_2019("pasture")$frac_leach * 100,
                         mms_frac_defaults_2019("solid_storage")$frac_leach * 100),
      lower_frac_leach=c(mms_frac_defaults_2019("pasture")$frac_leach_low * 100,
                         mms_frac_defaults_2019("solid_storage")$frac_leach_low * 100),
      upper_frac_leach=c(mms_frac_defaults_2019("pasture")$frac_leach_high * 100,
                         mms_frac_defaults_2019("solid_storage")$frac_leach_high * 100),
      distribution_frac_leach=c("pert","pert"),
      stringsAsFactors=FALSE)
    openxlsx::writeData(wb, "Manure_Management", manure_data, startRow=4,
                        startCol=1, colNames=FALSE)
    data_rng <- 4:5
  } else {
    data_rng <- 4:100
  }

  # Andreas 28/5/26 #4: per-MMS fraction uncertainty columns inserted at cols
  # 6-8, every column past fraction_pct shifts down by 3.
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=1)    # cattle_type
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=2)    # aggregation_level
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=3)    # sub_category
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=4)    # mms_type
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=5)    # fraction_pct
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=6:7)  # lower/upper_fraction
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=8)    # distribution_fraction
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=9)    # MCF_pct
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=10:11) # lower/upper_mcf
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=12)   # distribution_mcf
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=13)   # EF3
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=14:15) # lower/upper_ef3
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=16)   # distribution_ef3
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=17)   # Frac_GasMS_pct
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=18:19) # lower/upper frac_gas
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=20)   # distribution_frac_gas
  apply_style("Manure_Management", s_req,  rows=data_rng, cols=21)   # Frac_LeachMS_pct
  apply_style("Manure_Management", s_opt,  rows=data_rng, cols=22:23) # lower/upper frac_leach
  apply_style("Manure_Management", s_drop, rows=data_rng, cols=24)   # distribution_frac_leach

  add_validation("Manure_Management", col=4,  rows=data_rng, "mms")
  add_validation("Manure_Management", col=8,  rows=data_rng, "dist")
  add_validation("Manure_Management", col=12, rows=data_rng, "dist")
  add_validation("Manure_Management", col=16, rows=data_rng, "dist")
  add_validation("Manure_Management", col=20, rows=data_rng, "dist")
  add_validation("Manure_Management", col=24, rows=data_rng, "dist")

  # =========================================================================
  # SHEET: Parameter_TimeSeries  (rows = years, cols = parameters)
  # Parsed by parse_uploaded_template() to auto-compute the AD correlation matrix.
  # =========================================================================
  openxlsx::addWorksheet(wb, "Parameter_TimeSeries", tabColour = "#40916C",
                         gridLines = TRUE)
  # R1.6: time-series uses IPCC names (parser still aliases legacy names on upload).
  # Andreas 2026-05 #22e: added cattle_type / aggregation_level / sub_category
  # so users can supply per-group time series instead of a single inventory-wide
  # series. Leave them blank to apply the row to all groups.
  ts_params <- c("N", "BW", "MW", "WG",
                 "Milk", "Fat", "pct_pregnant", "DE",
                 "CP", "MilkPR")
  ts_units <- c("head", "kg", "kg", "kg/day",
                "kg/head/day", "%", "fraction (0-1)", "%", "%", "%")
  ts_desc  <- c("No. of animals", "Avg. body weight (BW)", "Mature body weight",
                "Daily weight gain", "Daily milk yield per cow", "Milk fat content",
                "Fraction calving (calves/females/year)", "Digestible energy",
                "Crude protein in diet", "Milk protein content")
  ts_all_cols  <- c("cattle_type", "aggregation_level", "sub_category",
                    "year", ts_params)
  ts_all_units <- c("(label)", "(label)", "(label)",
                    "(label only)", ts_units)
  ts_all_desc  <- c("dairy / non_dairy / mixed (free text; blank = applies to all)",
                    "Production system / AEZ (free text; blank = all)",
                    "Sub-category (free text; blank = all)",
                    "Calendar year", ts_desc)
  ts_n_cols    <- length(ts_all_cols)

  s_ts_hdr   <- mk(fontSize=10, fontName="Calibri", textDecoration="bold",
                   fontColour="#FFFFFF", fgFill="#2D6A4F",
                   border="TopBottomLeftRight", borderColour="#1B4332",
                   halign="center", valign="center", wrapText=TRUE)
  s_ts_sub   <- mk(fontSize=9, fontName="Calibri", fontColour="#555555",
                   fgFill="#D8F3DC", border="TopBottomLeftRight",
                   borderColour="#B7DFC0", halign="center", valign="top",
                   wrapText=TRUE, textDecoration="italic")
  s_ts_year  <- mk(fontSize=10, fontName="Calibri", halign="center",
                   fgFill="#F0FDF4", border="TopBottomLeftRight",
                   borderColour="#D1FAE5")
  s_ts_data  <- mk(fontSize=10, fontName="Calibri", halign="right",
                   fgFill="#F0FDF4", border="TopBottomLeftRight",
                   borderColour="#D1FAE5", numFmt="0.000")
  s_ts_int   <- mk(fontSize=10, fontName="Calibri", halign="right",
                   fgFill="#F0FDF4", border="TopBottomLeftRight",
                   borderColour="#D1FAE5", numFmt="#,##0")
  s_ts_empty <- mk(fontSize=10, fontName="Calibri", halign="right",
                   fgFill="#FFFFFF", border="TopBottomLeftRight",
                   borderColour="#E5E7EB")
  s_ts_note  <- mk(fontSize=9, fontName="Calibri", fontColour="#6B7280",
                   textDecoration="italic", wrapText=TRUE)

  ts_banner <- if (include_example) {
    paste("CORRELATIONS: Fill in one row per year for each parameter you have data for.",
          "When you upload this template in Tab 1, the app automatically computes a Pearson",
          "correlation matrix and uses it in Monte Carlo sampling (Tab 4 > Activity Data).",
          "You do NOT need every column - absent parameters are treated as uncorrelated (r=0).",
          "Delete the Country X example rows and replace with your data.",
          "Minimum: 2 numeric columns and 5 rows.")
  } else {
    paste("CORRELATIONS: Fill in one row per year for each parameter you have historical data for.",
          "When you upload this template in Tab 1, the app automatically computes a Pearson",
          "correlation matrix and uses it in Monte Carlo sampling (Tab 4 > Activity Data).",
          "You do NOT need every column - absent parameters are treated as uncorrelated (r=0).",
          "Minimum: 2 numeric columns and 5 rows.")
  }
  openxlsx::writeData(wb, "Parameter_TimeSeries", ts_banner,
    startRow=1, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Parameter_TimeSeries", cols=1:ts_n_cols, rows=1)
  apply_style("Parameter_TimeSeries",
    mk(fontColour="white", fgFill=C_SECTION, fontSize=9, textDecoration="italic",
       halign="left", valign="center", wrapText=TRUE),
    rows=1, cols=1:ts_n_cols)
  openxlsx::setRowHeights(wb, "Parameter_TimeSeries", rows=1, heights=52)

  openxlsx::writeData(wb, "Parameter_TimeSeries",
                      as.data.frame(t(ts_all_cols)), startRow=2, startCol=1,
                      colNames=FALSE)
  apply_style("Parameter_TimeSeries", s_ts_hdr, rows=2, cols=1:ts_n_cols)
  openxlsx::setRowHeights(wb, "Parameter_TimeSeries", rows=2, heights=22)

  openxlsx::writeData(wb, "Parameter_TimeSeries",
                      as.data.frame(t(ts_all_desc)), startRow=3, startCol=1,
                      colNames=FALSE)
  apply_style("Parameter_TimeSeries", s_ts_sub, rows=3, cols=1:ts_n_cols)
  openxlsx::setRowHeights(wb, "Parameter_TimeSeries", rows=3, heights=28)

  openxlsx::writeData(wb, "Parameter_TimeSeries",
                      as.data.frame(t(ts_all_units)), startRow=4, startCol=1,
                      colNames=FALSE)
  apply_style("Parameter_TimeSeries", s_ts_sub, rows=4, cols=1:ts_n_cols)
  openxlsx::setRowHeights(wb, "Parameter_TimeSeries", rows=4, heights=18)

  TS_DATA_START <- 5

  if (include_example) {
    # Andreas #22e: example now includes cattle_type / aggregation_level /
    # sub_category so users see the expected layout.
    ts_ex <- data.frame(
      cattle_type       = rep("dairy", 10),
      aggregation_level = rep("Country X – smallholder dairy", 10),
      sub_category      = rep("", 10),
      year         = 2013:2022,
      N            = c(4320000, 4410000, 4480000, 4530000, 4490000,
                       4560000, 4620000, 4670000, 4720000, 4790000),
      BW           = c(278, 275, 272, 270, 274, 271, 268, 273, 276, 274),
      MW           = c(302, 300, 300, 299, 301, 300, 298, 301, 302, 300),
      WG           = c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
      Milk         = c(3.9, 4.1, 4.0, 3.8, 4.2, 4.0, 3.9, 4.1, 4.0, 4.3),
      Fat          = c(3.9, 4.0, 4.1, 3.9, 4.0, 4.0, 4.1, 4.0, 3.9, 4.1),
      pct_pregnant  = c(0.59, 0.61, 0.60, 0.58, 0.62, 0.60, 0.59, 0.61, 0.60, 0.62),
      DE           = c(54.5, 55.0, 55.5, 54.0, 55.5, 55.0, 54.5, 56.0, 55.0, 55.5),
      CP           = c(9.8, 10.0, 10.2, 9.6, 10.3, 10.0, 9.9, 10.4, 10.1, 10.2),
      MilkPR       = c(3.2, 3.3, 3.3, 3.2, 3.4, 3.3, 3.2, 3.4, 3.3, 3.4),
      stringsAsFactors = FALSE
    )
    ts_n_ex <- nrow(ts_ex)
    openxlsx::writeData(wb, "Parameter_TimeSeries", ts_ex,
                        startRow=TS_DATA_START, startCol=1, colNames=FALSE)
    # Cols 1-3 = labels, col 4 = year, col 5 = N (integer), 6+ = numeric.
    apply_style("Parameter_TimeSeries", s_ts_year,
                rows=TS_DATA_START:(TS_DATA_START + ts_n_ex - 1), cols=1:4)
    apply_style("Parameter_TimeSeries", s_ts_int,
                rows=TS_DATA_START:(TS_DATA_START + ts_n_ex - 1), cols=5)
    apply_style("Parameter_TimeSeries", s_ts_data,
                rows=TS_DATA_START:(TS_DATA_START + ts_n_ex - 1), cols=6:ts_n_cols)
    openxlsx::setRowHeights(wb, "Parameter_TimeSeries",
                            rows=TS_DATA_START:(TS_DATA_START + ts_n_ex - 1), heights=16)
    TS_BLANK_START <- TS_DATA_START + ts_n_ex
  } else {
    ts_n_ex        <- 0L
    TS_BLANK_START <- TS_DATA_START
  }

  TS_BLANK_END <- TS_BLANK_START + 19
  apply_style("Parameter_TimeSeries", s_ts_empty,
              rows=TS_BLANK_START:TS_BLANK_END, cols=1:ts_n_cols)
  openxlsx::setRowHeights(wb, "Parameter_TimeSeries",
                          rows=TS_BLANK_START:TS_BLANK_END, heights=16)

  TS_NOTE_ROW <- TS_BLANK_END + 2
  ts_note <- if (include_example) {
    "Add more rows above if needed. Delete rows 5-14 (Country X example) and replace with your own data."
  } else {
    "Add more rows above if needed. Enter one row per year, starting from row 5."
  }
  openxlsx::writeData(wb, "Parameter_TimeSeries", ts_note,
                      startRow=TS_NOTE_ROW, startCol=1)
  apply_style("Parameter_TimeSeries", s_ts_note, rows=TS_NOTE_ROW, cols=1)
  openxlsx::mergeCells(wb, "Parameter_TimeSeries", cols=1:ts_n_cols, rows=TS_NOTE_ROW)

  # Andreas #22e: column widths now reflect the cattle_type/agg/sub_cat columns
  # before the year column.
  openxlsx::setColWidths(wb, "Parameter_TimeSeries", cols=1, widths=14)  # cattle_type
  openxlsx::setColWidths(wb, "Parameter_TimeSeries", cols=2, widths=22)  # aggregation_level
  openxlsx::setColWidths(wb, "Parameter_TimeSeries", cols=3, widths=16)  # sub_category
  openxlsx::setColWidths(wb, "Parameter_TimeSeries", cols=4, widths=7)   # year
  openxlsx::setColWidths(wb, "Parameter_TimeSeries", cols=5:ts_n_cols, widths=14)
  openxlsx::freezePane(wb, "Parameter_TimeSeries", firstActiveRow=TS_DATA_START)

  if (FALSE) { # dead block — kept only so unicode – below doesn't break parse
    pop_example_dead <- data.frame(
      cattle_type="dairy",
      aggregation_level="Country X \u2013 smallholder dairy",
      sub_category="cows",
      "2018"=450000L,"2019"=460000L,"2020"=470000L,
      "2021"=480000L,"2022"=490000L,"2023"=500000L,
      check.names=FALSE, stringsAsFactors=FALSE)
    openxlsx::writeData(wb, "Population_TimeSeries", pop_example, startRow=3,
                        startCol=1, colNames=FALSE)
  }

  # =========================================================================
  # SHEET: Vocab (combined parameter catalogue + controlled vocabulary)
  # =========================================================================
  openxlsx::addWorksheet(wb, "Vocab", tabColour = "#2D6A4F", gridLines = FALSE)
  openxlsx::setColWidths(wb, "Vocab",
                         cols=1:8, widths=c(18,48,18,12,14,12,16,50))

  # ── Section A: Parameter catalogue ──────────────────────────────────────
  openxlsx::writeData(wb, "Vocab", "SECTION A — Parameter Catalogue",
                      startRow=1, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Vocab", cols=1:8, rows=1)
  apply_style("Vocab",
    mk(fontColour="white", fgFill=C_HEADER, fontSize=13, textDecoration="bold",
       halign="left", valign="center"),
    rows=1, cols=1:8)
  openxlsx::setRowHeights(wb, "Vocab", rows=1, heights=28)

  cat_hdr <- data.frame(
    parameter="parameter", definition="definition", unit="unit",
    ipcc_default="ipcc_default", suggested_uncertainty_pct="suggested_unc_%",
    suggested_distribution="suggested_distribution",
    param_type="param_type", ipcc_ref="ipcc_ref",
    stringsAsFactors=FALSE)
  openxlsx::writeData(wb, "Vocab", cat_hdr, startRow=2, startCol=1,
                      colNames=FALSE)
  apply_style("Vocab", s_hdr, rows=2, cols=1:8)

  openxlsx::writeData(wb, "Vocab", PARAM_CATALOGUE, startRow=3, startCol=1,
                      colNames=FALSE)
  cat_data_rows <- 3:(2+nrow(PARAM_CATALOGUE))

  # Alternating row shading
  for (i in seq_along(cat_data_rows)) {
    r <- cat_data_rows[i]
    bg <- if (i %% 2 == 1) "#FFFFFF" else C_PREFILL
    apply_style("Vocab",
      mk(fgFill=bg, fontName="Calibri", fontSize=9,
         border="Bottom", borderColour="#DDDDDD",
         halign="left", valign="top", wrapText=TRUE),
      rows=r, cols=1:8)
  }
  # Highlight parameter column bold
  apply_style("Vocab",
    mk(fontName="Calibri", fontSize=9, textDecoration="bold",
       fgFill="#FFFFFF", border="Bottom", borderColour="#DDDDDD"),
    rows=cat_data_rows, cols=1)
  openxlsx::setRowHeights(wb, "Vocab", rows=cat_data_rows, heights=22)

  # ── Spacer ────────────────────────────────────────────────────────────────
  spacer_row <- max(cat_data_rows) + 2

  # ── Section B: Controlled vocabulary tables ───────────────────────────────
  openxlsx::writeData(wb, "Vocab", "SECTION B — Controlled Vocabulary",
                      startRow=spacer_row, startCol=1, colNames=FALSE)
  openxlsx::mergeCells(wb, "Vocab", cols=1:8, rows=spacer_row)
  apply_style("Vocab",
    mk(fontColour="white", fgFill=C_HEADER, fontSize=13, textDecoration="bold",
       halign="left", valign="center"),
    rows=spacer_row, cols=1:8)
  openxlsx::setRowHeights(wb, "Vocab", rows=spacer_row, heights=28)

  # Each vocabulary table: term | label/description | used_in | valid_for
  vocab_tables <- list(
    list(title="species (Inventory_Metadata dropdown)",
         cols=c("term","label","used_in"),
         data=data.frame(
           term=V_SPECIES,
           label=c("Cattle — dairy breeds","Cattle — non-dairy / beef / multipurpose","Buffalo"),
           used_in=rep("Inventory_Metadata.species", 3),
           stringsAsFactors=FALSE)),

    list(title="IPCC Table 10.17 — MCF (%) by climate zone  [enter values into Manure_Management sheet]",
         cols=c("mms_type","tropical_moist_%","tropical_dry_%","temperate_%","boreal_%"),
         data=data.frame(
           mms_type=MMS_DEFAULTS$id,
           tropical_moist=MMS_DEFAULTS$mcf_tropical,
           tropical_dry=MMS_DEFAULTS$mcf_tropical_dry,
           temperate=MMS_DEFAULTS$mcf_temperate,
           boreal=MMS_DEFAULTS$mcf_boreal,
           stringsAsFactors=FALSE)),

    list(title="mms_type (manure management system)",
         cols=c("term","label","EF3 (kg N2O-N/kg N)","MCF tropical%","MCF temperate%"),
         data=data.frame(
           term=MMS_DEFAULTS$id,
           label=MMS_DEFAULTS$label,
           ef3=MMS_DEFAULTS$ef3,
           mcf_trop=MMS_DEFAULTS$mcf_tropical,
           mcf_temp=MMS_DEFAULTS$mcf_temperate,
           stringsAsFactors=FALSE)),

    list(title="distribution (Parameters and Manure_Management dropdowns)",
         cols=c("term","shape","when_to_use","bounds_input"),
         data=data.frame(
           term=V_DIST,
           shape=c("Symmetric bell","Symmetric, truncated at 0","Right-skewed, always positive",
                   "Flexible, bounded [lower,upper]","Linear triangle","Smooth peak at mode",
                   "Flat — all values equally likely","No variation","Normal clamped to [0,1]"),
           use=c("Large populations, body weights, symmetric uncertainty",
                 "Non-negative parameters with near-symmetric uncertainty",
                 "Emission factors, ratios — strictly positive, possible right tail",
                 "Fractions 0-1: pct_pregnant, Cp",
                 "Expert-elicited min/mode/max: Ca, C_growth, DE_pct",
                 "IPCC coefficients: Cfi, Ym, Bo, EF3_PRP — recommended for most EFs",
                 "Only bounds known, no preferred value",
                 "Zero uncertainty, e.g. WG=0 for non-growing adults",
                 "Fractions that must stay in [0,1]"),
           bounds=c("uncertainty_pct only","uncertainty_pct only","uncertainty_pct only",
                    "uncertainty_pct only","lower_bound+upper_bound (min/max)",
                    "lower_bound+upper_bound (min/max)",
                    "lower_bound+upper_bound (min/max)","none","uncertainty_pct only"),
           stringsAsFactors=FALSE)),

    # data_quality vocab section removed in v2.3 (TT.2 - column was unused)

    list(title="animal sub-category reference — IPCC defaults (for reference only; sub_category is free text in the template)",
         cols=c("ipcc_term","label","sex","age_class","default_Cfi",
                "default_LW_kg","default_WG_kg_day"),
         data=data.frame(
           term=V_SUBSYS,
           label=unname(ANIMAL_SUBCATEGORY_LABELS),
           sex=unlist(SEX_BY_SUBCAT[V_SUBSYS]),
           age_class=unlist(AGE_BY_SUBCAT[V_SUBSYS]),
           Cfi=unlist(CFI_BY_SUBCAT[V_SUBSYS]),
           LW=unlist(LW_BY_SUBCAT[V_SUBSYS]),
           WG=unlist(WG_BY_SUBCAT[V_SUBSYS]),
           stringsAsFactors=FALSE)),

    list(title="feeding_situation reference — Ca values (for reference only; feeding situation is captured in sub_category free text)",
         cols=c("term","description","Ca value (IPCC Table 10.5)"),
         data=data.frame(
           term=V_FEED,
           description=c("Animal is stall-fed or kept in enclosure",
                         "Animal grazes on flat terrain",
                         "Animal grazes on hilly terrain"),
           Ca=c(0.00, 0.17, 0.36),
           stringsAsFactors=FALSE))
  )

  cur_row <- spacer_row + 1
  for (vt in vocab_tables) {
    # Section title
    openxlsx::writeData(wb, "Vocab", vt$title, startRow=cur_row, startCol=1,
                        colNames=FALSE)
    openxlsx::mergeCells(wb, "Vocab", cols=1:8, rows=cur_row)
    apply_style("Vocab",
      mk(fontColour="white", fgFill=C_SECTION, fontSize=10,
         textDecoration="bold", halign="left", valign="center"),
      rows=cur_row, cols=1:8)
    openxlsx::setRowHeights(wb, "Vocab", rows=cur_row, heights=22)
    cur_row <- cur_row + 1

    # Column headers
    hdr_df <- as.data.frame(t(vt$cols), stringsAsFactors=FALSE)
    openxlsx::writeData(wb, "Vocab", hdr_df, startRow=cur_row, startCol=1,
                        colNames=FALSE)
    apply_style("Vocab", s_hdr, rows=cur_row, cols=seq_along(vt$cols))
    cur_row <- cur_row + 1

    # Data
    nc <- ncol(vt$data)
    openxlsx::writeData(wb, "Vocab", vt$data, startRow=cur_row, startCol=1,
                        colNames=FALSE)
    for (i in seq_len(nrow(vt$data))) {
      bg <- if (i%%2==1) "#FFFFFF" else C_DROPDOWN
      apply_style("Vocab",
        mk(fgFill=bg, fontName="Calibri", fontSize=9,
           border="Bottom", borderColour="#DDDDDD",
           halign="left", valign="top"),
        rows=cur_row+i-1, cols=1:nc)
      # Bold the term column
      apply_style("Vocab",
        mk(fgFill=bg, fontName="Calibri", fontSize=9, textDecoration="bold",
           border="Bottom", borderColour="#DDDDDD"),
        rows=cur_row+i-1, cols=1)
    }
    cur_row <- cur_row + nrow(vt$data) + 1  # +1 blank gap
  }

  # =========================================================================
  # G3 / TT.8: Excel-level conditional formatting QC
  # =========================================================================
  # The Parameters sheet is laid out with banner row 1, legend row 2, headers
  # row 3, and data rows 4..(DATA_START + N_DATA_ROWS). Reference column IDs
  # (P_COL_IDX) are still in scope from the generation pass above.
  qc_data_rows <- 4:(DATA_START + N_DATA_ROWS)
  red_fill    <- openxlsx::createStyle(fgFill = "#FECACA",
                                        fontColour = "#7F1D1D")
  orange_fill <- openxlsx::createStyle(fgFill = "#FED7AA",
                                        fontColour = "#9A3412")

  # Rule 1: required value cell (col G) blank when sub-category in col A is filled
  openxlsx::conditionalFormatting(wb, "Parameters",
    cols = P_COL_IDX["value"], rows = qc_data_rows,
    rule = sprintf('AND(G%1$d="",A%1$d<>"")', qc_data_rows[1]),
    style = red_fill, type = "expression")

  # Rule 2: uncertainty_pct (col H) > 100 — likely entered "45%" instead of 45
  openxlsx::conditionalFormatting(wb, "Parameters",
    cols = P_COL_IDX["uncertainty_pct"], rows = qc_data_rows,
    rule = ">100", style = orange_fill, type = "expression")

  # Rule 3: lower_bound (col I) >= upper_bound (col J)
  openxlsx::conditionalFormatting(wb, "Parameters",
    cols = P_COL_IDX["lower_bound"], rows = qc_data_rows,
    rule = sprintf('AND(I%1$d<>"",J%1$d<>"",I%1$d>=J%1$d)', qc_data_rows[1]),
    style = red_fill, type = "expression")
  openxlsx::conditionalFormatting(wb, "Parameters",
    cols = P_COL_IDX["upper_bound"], rows = qc_data_rows,
    rule = sprintf('AND(I%1$d<>"",J%1$d<>"",I%1$d>=J%1$d)', qc_data_rows[1]),
    style = red_fill, type = "expression")

  # =========================================================================
  # Save workbook
  # =========================================================================
  openxlsx::saveWorkbook(wb, filepath, overwrite = TRUE)
  message("Template saved to: ", filepath)
}


# ===========================================================================
# FALLBACK — basic writexl version (no dropdowns)
# ===========================================================================
generate_template_basic <- function(filepath, include_example) {
  ex_values <- c(500000, 275, 300, 0.10, 3.5, 4.3, 0.60, 55,
                 0.386, 0.17, 0.8, 0.10, 0, 10,
                 6.5, 0.13, 0.08, 0.04,   # Ym, Bo (2019R "Other regions" cattle), ASH, UE
                 0.02, 0.005, 0.20, 0.010, 0.0075, 0.02,
                 0.21, 0.30,
                 3.3, 20)
  params <- if (include_example) {
    data.frame(
      cattle_type="dairy",
      aggregation_level="Country X \u2013 smallholder dairy",
      sub_category="cows",
      parameter=PARAM_CATALOGUE$parameter,
      definition=PARAM_CATALOGUE$definition,
      unit=PARAM_CATALOGUE$unit,
      value=ex_values,
      uncertainty_pct=PARAM_CATALOGUE$suggested_uncertainty_pct,
      lower_bound=NA_real_,
      upper_bound=NA_real_,
      distribution=PARAM_CATALOGUE$suggested_distribution,
      lower=NA_real_, upper=NA_real_,
      param_type=PARAM_CATALOGUE$param_type,
      ipcc_ref=PARAM_CATALOGUE$ipcc_ref,
      data_source="IPCC default / hypothetical Country X",
      stringsAsFactors=FALSE)
  } else {
    is_ef <- PARAM_CATALOGUE$param_type == "coefficient"
    data.frame(
      cattle_type="dairy",
      aggregation_level="",
      sub_category="",
      parameter=PARAM_CATALOGUE$parameter,
      definition=PARAM_CATALOGUE$definition,
      unit=PARAM_CATALOGUE$unit,
      value=ifelse(is_ef, PARAM_CATALOGUE$ipcc_default, NA_real_),
      uncertainty_pct=PARAM_CATALOGUE$suggested_uncertainty_pct,
      lower_bound=NA_real_,
      upper_bound=NA_real_,
      distribution=PARAM_CATALOGUE$suggested_distribution,
      lower=NA_real_, upper=NA_real_,
      param_type=PARAM_CATALOGUE$param_type,
      ipcc_ref=PARAM_CATALOGUE$ipcc_ref,
      data_source="",
      stringsAsFactors=FALSE)
  }
  writexl::write_xlsx(list(Parameters=params, Vocab=PARAM_CATALOGUE),
                      path=filepath)
}


# ===========================================================================
# PARSER — read back an uploaded template (openxlsx or writexl output)
# ===========================================================================
parse_uploaded_template <- function(path) {
  warnings_list <- character()

  sheet_names <- tryCatch(readxl::excel_sheets(path),
                          error = function(e) character())

  # T1.1 (followup): The generated template has multi-row headers — Parameters
  # has banner+legend+header (skip=2), Manure_Management has banner+header
  # (skip=1), Inventory_Metadata starts with headers (skip=0). Try several
  # skip values and pick the one where expected columns appear.
  read_sheet_smart <- function(name, expected_cols, max_skip = 3) {
    if (!(name %in% sheet_names)) return(NULL)
    best <- NULL
    for (sk in 0:max_skip) {
      df <- tryCatch(
        suppressMessages(as.data.frame(
          readxl::read_excel(path, sheet = name, skip = sk,
                             .name_repair = "unique"))),
        error = function(e) NULL)
      if (is.null(df)) next
      hits <- sum(expected_cols %in% names(df))
      if (hits == length(expected_cols)) return(df)            # perfect
      if (hits > 0 && is.null(best)) best <- df                # partial fallback
    }
    # If nothing matched, return the default skip=0 read so callers can produce
    # a meaningful "missing column" error pointing to what was actually found.
    if (!is.null(best)) return(best)
    tryCatch(
      as.data.frame(readxl::read_excel(path, sheet = name,
                                       .name_repair = "unique")),
      error = function(e) {
        warnings_list <<- c(warnings_list,
                            paste("Could not read sheet", name, ":", e$message))
        NULL
      })
  }

  metadata <- read_sheet_smart("Inventory_Metadata",
                               c("Field", "Value"))
  params   <- read_sheet_smart("Parameters",
                               c("parameter", "cattle_type"))
  manure   <- read_sheet_smart("Manure_Management",
                               c("mms_type", "fraction_pct"))

  # Parameter_TimeSeries: the main template has 4 header rows (banner + parameter
  # names + descriptions + units), data starts row 5. The standalone time-series
  # template has 3 header rows. Try both skip values and pick the one that yields
  # parameter-name column headers we recognise.
  # Also accept old "Population_TimeSeries" name for backwards compatibility.
  ts_sheet <- if ("Parameter_TimeSeries" %in% sheet_names) "Parameter_TimeSeries" else
               if ("Population_TimeSeries" %in% sheet_names) "Population_TimeSeries" else NULL
  read_ts_with_skip <- function(skip_n) {
    tryCatch(
      as.data.frame(readxl::read_excel(
        path, sheet = ts_sheet, col_names = TRUE, skip = skip_n,
        .name_repair = "unique")),
      error = function(e) NULL)
  }
  expected_param_names <- c("year",
                            # New IPCC-aligned names
                            "N", "BW", "Milk", "DE", "CP", "MW", "WG", "Fat",
                            # Legacy fallbacks
                            "cattle_pop", "live_weight", "milk_yield",
                            "DE_pct", "CP_pct")
  population <- NULL
  if (!is.null(ts_sheet)) {
    for (sk in 0:3) {
      df <- read_ts_with_skip(sk)
      if (is.null(df)) next
      if (any(expected_param_names %in% names(df))) {
        population <- df
        break
      }
    }
    # Fall back to skip=0 if nothing matched
    if (is.null(population)) population <- read_ts_with_skip(0)
  }

  # R2.2: shared logic moved to compute_corr_from_population() so that the same
  # path produces a correlation matrix whether the user uploaded a real
  # template or loaded a built-in example with a synthetic time-series block.
  corr_matrix_from_ts <- compute_corr_from_population(population)

  # For the transposed Inventory_Metadata layout (Field | Value | Hint)
  if (!is.null(metadata) && ncol(metadata) >= 2) {
    if (all(c("Field","Value") %in% names(metadata)) ||
        (ncol(metadata) >= 2 && names(metadata)[2] %in%
         c("Field","B","country","country / region",
           "Country / region", "Country", "Continental region"))) {
      # Try to detect transposed layout (rows = fields, col 2 = value)
      tryCatch({
        field_col <- grep("field|label", names(metadata), ignore.case=TRUE)[1]
        val_col   <- grep("value|val", names(metadata), ignore.case=TRUE)[1]
        if (!is.na(field_col) && !is.na(val_col)) {
          # Andreas 28/5/26 follow-up: do the slash-strip BEFORE the
          # space→underscore conversion. Previously the slash strip ran on
          # the underscore-converted string, so "Country / region" became
          # "Country_/_region" → "Country_" (with trailing underscore)
          # → broke the country-name lookup in normalise_metadata_region.
          # New order: "Country / region" → strip "/rest" → "Country" →
          # space→underscore → "Country" → tolower → "country".
          m2 <- setNames(as.list(metadata[[val_col]]),
                         tolower(gsub(" ","_",
                           gsub("\\s*/.*","",
                             metadata[[field_col]]))))
          metadata <- as.data.frame(m2, stringsAsFactors=FALSE)
        }
      }, error=function(e) NULL)
    }
  }

  # Andreas 28/5/26 follow-up: legacy templates only have a single "Country
  # / region" cell that's free text. If the new "Continental region" cell
  # is missing or unrecognised, fall back to a country -> continent
  # lookup so the BW benchmark deviation check still picks up the right
  # continental default. Match is case-insensitive on the user's "country"
  # cell; if no country listed (or no match), we leave region as-is and
  # the QA check falls back to "global" (the existing behaviour).
  metadata <- normalise_metadata_region(metadata)

  if (is.null(params) || nrow(params) == 0)
    stop("Parameters sheet is empty or missing. ",
         "Make sure the workbook contains a sheet named 'Parameters' ",
         "with at least one row of data.")

  if (!"parameter" %in% names(params))
    stop("Parameters sheet is missing the required 'parameter' column. ",
         "Found columns: ", paste(names(params), collapse = ", "))

  # Drop blank/instruction rows first (no parameter name).
  raw_n <- nrow(params)
  params <- params[
    !is.na(params$parameter) &
    nzchar(as.character(params$parameter)), ,
    drop = FALSE]

  # Andreas 2026-05 audit follow-up: defensive whitespace + case normalisation
  # on grouping and lookup columns so a stray trailing space ("N " instead of
  # "N") or inconsistent case ("Dairy" vs "dairy") doesn't silently drop rows
  # or split a group across two systems_data entries.
  if ("parameter" %in% names(params))
    params$parameter <- trimws(as.character(params$parameter))
  if ("cattle_type" %in% names(params))
    params$cattle_type <- tolower(trimws(as.character(params$cattle_type)))
  if ("aggregation_level" %in% names(params))
    params$aggregation_level <- trimws(as.character(params$aggregation_level))
  if ("sub_category" %in% names(params))
    params$sub_category <- trimws(as.character(params$sub_category))
  if ("distribution" %in% names(params))
    params$distribution <- tolower(trimws(as.character(params$distribution)))
  if (!is.null(manure)) {
    for (col in c("cattle_type", "aggregation_level", "sub_category", "mms_type")) {
      if (col %in% names(manure))
        manure[[col]] <- trimws(as.character(manure[[col]]))
    }
    if ("cattle_type" %in% names(manure))
      manure$cattle_type <- tolower(manure$cattle_type)
  }

  # C1 / R1.6 hotfix (Round 7.1): apply legacy-name aliases BEFORE the
  # catalogue filter, otherwise rows whose parameter still uses the pre-rename
  # spelling (cattle_pop, live_weight, milk_yield, DE_pct, ...) get dropped
  # silently. Then ensure_completeness() reports the renamed parameter as
  # missing — and N has no IPCC default, so the run fails with a confusing
  # "missing N" error instead of the legacy template just working.
  if ("parameter" %in% names(params) && exists("PARAM_ALIASES")) {
    aliased <- params$parameter %in% names(PARAM_ALIASES)
    if (any(aliased))
      params$parameter[aliased] <- PARAM_ALIASES[params$parameter[aliased]]
  }

  # Now filter to rows whose (translated) parameter name is in the catalogue.
  params <- params[params$parameter %in% PARAM_CATALOGUE$parameter, , drop = FALSE]

  if (nrow(params) == 0) {
    # Surface what we did find so the user can fix names. params still has its
    # original column structure here even though all rows were filtered out.
    found_raw <- unique(stats::na.omit(as.character(params$parameter)))
    stop("No recognised parameters found in the Parameters sheet ",
         "(", raw_n, " rows read, 0 matched the catalogue). ",
         if (length(found_raw))
           paste0("Names found: ", paste(head(found_raw, 10), collapse = ", "),
                  ". ") else "",
         "Expected names: ",
         paste(head(PARAM_CATALOGUE$parameter, 6), collapse = ", "), ", ...")
  }

  # Rename 'value' -> 'mean' for mc_sampling compatibility
  if ("value" %in% names(params) && !"mean" %in% names(params))
    names(params)[names(params) == "value"] <- "mean"

  # D1: backwards-compat alias — coerce legacy "emission_factor" param_type to "coefficient"
  if ("param_type" %in% names(params))
    params$param_type[params$param_type == "emission_factor"] <- "coefficient"

  # Ensure numeric
  for (nm in c("mean","uncertainty_pct","lower","upper","lower_bound","upper_bound")) {
    if (nm %in% names(params))
      params[[nm]] <- suppressWarnings(as.numeric(params[[nm]]))
  }

  # Fill lower/upper from lower_bound/upper_bound overrides or uncertainty_pct
  params <- fill_bounds(params)

  # Ensure Bo default in manure sheet
  if (!is.null(manure) && nrow(manure) > 0) {
    if (!"Bo" %in% names(manure)) manure$Bo <- 0.10
    manure$Bo[is.na(manure$Bo)] <- 0.10
    # Ensure numeric — fraction_pct was missing from this list which caused
    # "non-numeric argument to binary operator" when systems_data tried to do
    # `mms_rows$fraction_pct / 100` after upload.
    for (nm in c("fraction_pct","MCF_pct","EF3","Bo",
                 "lower_mcf","upper_mcf","lower_ef3","upper_ef3",
                 "lower_fraction","upper_fraction",
                 "Frac_GasMS_pct","lower_frac_gas","upper_frac_gas",
                 "Frac_LeachMS_pct","lower_frac_leach","upper_frac_leach",
                 "uncertainty_pct_mcf","uncertainty_pct_ef3")) {
      if (nm %in% names(manure))
        manure[[nm]] <- suppressWarnings(as.numeric(manure[[nm]]))
    }
  }

  list(param_specs=params, metadata=metadata,
       manure=manure, population=population,
       corr_matrix=corr_matrix_from_ts,
       warnings=warnings_list)
}


# ===========================================================================
# IPCC REFERENCE SHEET  (kept for backwards compatibility — used by the
# old writexl path and accessible from build_ipcc_reference_sheet())
# ===========================================================================
build_ipcc_reference_sheet <- function() {
  bind_rows_safe <- function(...) {
    dfs <- list(...)
    do.call(rbind, lapply(dfs, function(d) { rownames(d) <- NULL; d }))
  }
  cfi <- data.frame(category="Cfi", subcategory=names(CFI_BY_SUBCAT),
    default_value=unlist(CFI_BY_SUBCAT), unit="MJ/day/kg^0.75",
    ipcc_ref="Table 10.4", depends_on="Sex, lactation, maturity",
    notes="Africa defaults", stringsAsFactors=FALSE)
  ca  <- data.frame(category="Ca", subcategory=names(FEEDING_SITUATION_CA),
    default_value=unlist(FEEDING_SITUATION_CA), unit="dimensionless",
    ipcc_ref="Table 10.5", depends_on="Feeding situation",
    notes="stall=0, flat=0.17, hilly=0.36", stringsAsFactors=FALSE)
  cg  <- data.frame(category="C_growth",
    subcategory=c("female","castrate","bull"), default_value=c(0.8,1.0,1.2),
    unit="dimensionless", ipcc_ref="Eq 10.6", depends_on="Sex",
    notes="NEg equation", stringsAsFactors=FALSE)
  lw  <- data.frame(category="Live weight", subcategory=names(LW_BY_SUBCAT),
    default_value=unlist(LW_BY_SUBCAT), unit="kg",
    ipcc_ref="Table 10A.1-10A.2", depends_on="Sub-category, region",
    notes="Africa defaults", stringsAsFactors=FALSE)
  ym  <- data.frame(category="Ym",
    subcategory=c("Dairy high-DE","Dairy low-DE","Feedlot","Other low-DE","Other high-DE"),
    default_value=c(6.0,6.5,3.0,6.5,6.5), unit="%",
    ipcc_ref="Table 10.12", depends_on="Feed quality, system",
    notes="GE->CH4 conversion", stringsAsFactors=FALSE)
  mcf_rows <- do.call(rbind, lapply(seq_len(nrow(MMS_DEFAULTS)), function(i) {
    m <- MMS_DEFAULTS[i,]
    data.frame(category="MCF",
      subcategory=paste0(m$label," / ",c("tropical_moist","tropical_dry","temperate","boreal")),
      default_value=c(m$mcf_tropical,m$mcf_tropical_dry,m$mcf_temperate,m$mcf_boreal),
      unit="%", ipcc_ref="Table 10.17", depends_on="MMS, climate",
      notes="", stringsAsFactors=FALSE)
  }))
  ef3 <- data.frame(category="EF3",
    subcategory=paste0(MMS_DEFAULTS$label," (N2O MMS)"),
    default_value=MMS_DEFAULTS$ef3, unit="kg N2O-N/kg N",
    ipcc_ref="Table 10.21", depends_on="MMS type", notes="",
    stringsAsFactors=FALSE)
  gwp <- data.frame(category="GWP",
    subcategory=c("CH4/AR4","N2O/AR4","CH4/AR5","N2O/AR5","CH4/AR6","N2O/AR6"),
    default_value=c(25,298,28,265,27.0,273), unit="kg CO2eq/kg gas",
    ipcc_ref="IPCC AR WG1", depends_on="Assessment report",
    notes="100-yr GWP", stringsAsFactors=FALSE)
  bind_rows_safe(cfi, ca, cg, lw, ym, mcf_rows, ef3, gwp)
}
