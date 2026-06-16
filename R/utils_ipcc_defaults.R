# IPCC Default Values for Africa/Developing Countries
# Sources: IPCC 2006 Guidelines Vol 4 Ch 10, 2019 Refinement

IPCC_DEFAULTS <- list(
  Cfi = list(cows_lactating = 0.386, cows_dry = 0.322, heifers = 0.322,
             bulls = 0.370, oxen = 0.322, growing_males = 0.370,
             calves_male = 0.370, calves_female = 0.322),
  Ca = list(stall = 0.00, pasture = 0.17, hilly = 0.36),
  LW = list(cows = 275, heifers = 200, adult_males = 300, growing_males = 200, calves = 60),
  WG = list(cows = 0.0, heifers = 0.25, adult_males = 0.0, growing_males = 0.20, calves = 0.30),
  MW = list(cows = 300, heifers = 300, adult_males = 350, growing_males = 350, calves = 300),
  C_growth = list(female = 0.8, castrate = 1.0, bull = 1.2),
  pct_pregnant = 0.60, pct_pregnant_cows = 0.60, pct_pregnant_heifers = 0.20,
  milk_yield = 4.0, milk_fat = 4.0, Ym = 6.5, DE = 55.0,
  # IPCC alignment audit (2026-05): Bo updated 0.10 -> 0.13.
  # 2019R Vol.4 Ch.10 Table 10.16(a) (Updated) gives Bo by region/productivity:
  #   Dairy cattle:    0.24 (NA/W.Europe) / 0.24 (E.Europe) / 0.13 (Oceania,
  #                    Other-regions low productivity)
  #   Non-dairy cattle:0.19 / 0.18 / 0.17 / 0.17 / 0.18 / 0.13
  # Africa maps to "Other regions, low productivity" -> 0.13.
  # 2006 Africa cattle default was 0.10; we now follow 2019R.
  Bo = 0.13, ASH = 0.08, UE = 0.04, CP = 10.0,
  # ----- IPCC alignment audit (2026-05) -----
  # Disambiguation: managed-storage (MS) vs pasture (PRP) N pathways are
  # different equations and pull from different IPCC tables.
  #   Managed storage (Vol.4 Ch.10):
  #     Frac_GASMS    — Eq. 10.26 (volatilisation N losses, MS)
  #     EF4 (MS path) — Eq. 10.27 (indirect N2O via volatilisation)
  #                      Default from Vol.4 Ch.11 Table 11.3
  #     Frac_LEACH_H  — Eq. 10.28 (leaching N losses, MS).
  #                      Canonical alias exposed in docs: Frac_LeachMS.
  #     EF5 (MS path) — Eq. 10.29 (indirect N2O via leaching)
  #                      Default from Vol.4 Ch.11 Table 11.3
  #   Pasture / range / paddock (Vol.4 Ch.11):
  #     EF3_PRP       — Eq. 11.1 (direct PRP N2O, default Table 11.1)
  #     Frac_GASM_PRP — Eq. 11.9 (volatilisation, PRP)
  #     Frac_LEACH_PRP — Eq. 11.10 (leaching, PRP)
  # 2006 vs 2019 Refinement values (verified against Vol.4 Ch.11 Tables 11.1
  # and 11.3, May 2026):
  #   EF4 (kg N2O-N / (kg NH3-N + NOx-N volatilised)):
  #     2006   = 0.010 (Table 11.3; range 0.002-0.05)
  #     2019R  = 0.010 aggregated (range 0.002-0.018)
  #              0.014 wet climate (range 0.011-0.017)
  #              0.005 dry climate (range 0.000-0.011)
  #     The unconditional default below is the AGGREGATED value (0.010),
  #     which happens to coincide with the 2006 single-value default.
  #     Inventories that explicitly classify their climate should use 0.014
  #     (wet) or 0.005 (dry).
  #   EF5 (kg N2O-N / kg N leached/runoff):
  #     2006   = 0.0075 (range 0.0005-0.025)
  #     2019R  = 0.011  (range 0.000-0.020) — no climate disaggregation
  #   EF3_PRP, CPP (cattle, poultry, pigs):
  #     2006   = 0.02 (single value)
  #     2019R  = 0.004 aggregated (range 0.000-0.014)
  #              0.006 wet climate (range 0.000-0.027)
  #              0.002 dry climate (range 0.000-0.007)
  #     The unconditional default below is the AGGREGATED 2019R value (0.004).
  #   FracGASM (volatilisation, organic N + grazing dung/urine):
  #     2006   = 0.20 (range 0.05-0.5)
  #     2019R  = 0.21 (range 0.00-0.31)
  #   FracLEACH-(H) (leaching/runoff in wet climates):
  #     2006   = 0.30 (range 0.1-0.8) — applies only where precipitation
  #              exceeds soil water holding capacity
  #     2019R  = 0.24 (range 0.01-0.73) — wet climate only; 0 in dry
  EF3_PRP = 0.004,    # 2019R aggregated EF3_PRP,CPP (Vol.4 Ch.11 Table 11.1)
  Frac_GASMS = 0.21,  # 2019R aggregated FracGASM (Vol.4 Ch.11 Table 11.3); 2006 = 0.20
  EF4 = 0.010,        # 2019R aggregated (Vol.4 Ch.11 Table 11.3); 2006 = 0.010 (identical)
  EF5 = 0.011,        # 2019R (Vol.4 Ch.11 Table 11.3); 2006 = 0.0075
  Frac_LEACH_H = 0.02,            # MS-side leaching from Vol.4 Ch.10 Table 10.23
  Frac_GASM_PRP = 0.21,           # 2019R FracGASM (Vol.4 Ch.11 Table 11.3); same parameter as Frac_GASMS
  Frac_LEACH_PRP = 0.24           # 2019R FracLEACH-(H) wet climate (Vol.4 Ch.11 Table 11.3); 2006 = 0.30; dry = 0
)

## TT.3 / G1: MMS list expanded to cover IPCC 2006 (8 systems) and 2019 Refinement
## (adds anaerobic_digester, aerobic_treatment, burned_for_fuel, solid_storage_covered).
## `versions` lists which IPCC editions recognise each system.
## `get_mms_for_version(version)` filters MMS_DEFAULTS$id by version (used for
## conditional dropdowns once the user selects an IPCC guidelines version in metadata).
MMS_DEFAULTS <- data.frame(
  id = c("pasture", "daily_spread", "solid_storage", "solid_storage_covered",
         "dry_lot", "deep_bedding", "liquid_slurry", "composting", "lagoon",
         "anaerobic_digester", "aerobic_treatment", "burned_for_fuel"),
  label = c("Pasture/Paddock/Range", "Daily Spread", "Solid Storage",
            "Solid Storage – Covered/Compacted (2019)",
            "Dry Lot", "Deep Bedding (>1 month)", "Liquid/Slurry",
            "Composting", "Anaerobic Lagoon",
            "Anaerobic Digester / Biogas (2019)",
            "Aerobic Treatment (2019)",
            "Burned for Fuel (2019)"),
  versions = c("2006,2019", "2006,2019", "2006,2019", "2019",
               "2006,2019", "2006,2019", "2006,2019", "2006,2019", "2006,2019",
               "2019", "2019", "2019"),
  # MCF retained on the 2006-convention climate-zone values (a coherent set).
  # Deliberately NOT switched to the 2019R Table 10.17 values: the 2019R
  # Pasture/Range/Paddock MCF (0.47%) must, per Table 10.17 footnote 2, be paired
  # with Bo = 0.19 m3/kg VS, and the engine uses a single per-animal Bo — so
  # adopting 2019R MCF correctly would require a per-MMS Bo (deferred engine
  # change). Verified line-by-line vs Table 10.17 on 2026-06-16.
  mcf_tropical     = c(1.5, 1.0, 5.0, 4.0, 5.0, 30.0, 80.0, 1.5, 80.0,  3.5, 0.0,  10.0),
  mcf_tropical_dry = c(1.5, 1.0, 5.0, 4.0, 5.0, 30.0, 80.0, 1.5, 80.0,  3.5, 0.0,  10.0),
  mcf_temperate    = c(1.0, 0.5, 4.0, 2.0, 1.5, 17.0, 35.0, 1.0, 66.0,  1.0, 0.0,  10.0),
  mcf_boreal       = c(1.0, 0.1, 3.0, 1.0, 1.0,  3.0, 10.0, 0.5, 66.0,  1.0, 0.0,  10.0),
  # EF3 = direct N2O EF by managed system, IPCC 2019R Table 10.21 (verified
  # 2026-06-16): solid_storage + solid_storage_covered corrected 0.005 -> 0.010.
  # pasture 0.02 is the PRP/Ch.11 pathway value (not a Table 10.21 MS), left as-is.
  ef3 = c(0.02, 0.0, 0.010, 0.010, 0.02, 0.01, 0.005, 0.006, 0.0, 0.0006, 0.005, 0.0),
  stringsAsFactors = FALSE
)

## Regional benchmark table for the QA/QC plausibility check.
##
## Andreas 28/5/26 #3 follow-up: scope reduced to BW only. The previous
## Milk / DE / Ym / Bo rows were heuristic mid-points derived from the
## Annex 10A illustrative tables, not direct continental IPCC defaults —
## Andreas's reviewer finding was that the QA tab claimed "IPCC default"
## values he could not locate in the guidelines. They have been removed.
##
## BW is the only parameter we currently key off a defensible continental
## IPCC table lookup:
##   - dairy cows : Vol.4 Ch.10 Annex Table 10A.1
##   - non-dairy  : Vol.4 Ch.10 Annex Table 10A.2
##   - buffalo    : Vol.4 Ch.10 Annex Table 10A.3
## (the continental values below are illustrative midpoints across those
## tables — country-specific BW is always expected to override).
##
## Reinstating Milk / DE / Ym / Bo / MW benchmarks properly would require a
## multi-dimensional table (parameter × continent × IPCC version × production
## system × animal sub-category). 2019R further splits each region into low-
## and high-productivity systems. That is a much larger data-entry job
## (deferred — see plan).
IPCC_DEFAULTS_BY_REGION <- data.frame(
  parameter   = rep("BW", 6),
  region      = c("africa","asia","europe","americas","oceania","global"),
  default_val = c(
    # BW (kg) — IPCC Vol.4 Ch.10 Annex Tables 10A.1 / 10A.2 / 10A.3
    # illustrative regional midpoints across sub-categories.
    275, 350, 600, 500, 500, 400),
  stringsAsFactors = FALSE
)

# Lookup: returns region-specific default or NA
get_regional_default <- function(parameter, region = "global") {
  if (is.null(region) || is.na(region)) region <- "global"
  region <- tolower(trimws(region))
  if (!region %in% IPCC_DEFAULTS_BY_REGION$region) region <- "global"
  hit <- IPCC_DEFAULTS_BY_REGION[
    IPCC_DEFAULTS_BY_REGION$parameter == parameter &
    IPCC_DEFAULTS_BY_REGION$region == region, , drop = FALSE]
  if (nrow(hit) == 0) return(NA_real_)
  hit$default_val[1]
}

## G1: helper to filter MMS_DEFAULTS by IPCC version string ("2006" or "2019_refinement")
get_mms_for_version <- function(version = "2006") {
  v_key <- if (grepl("2019", version)) "2019" else "2006"
  has_version <- vapply(strsplit(MMS_DEFAULTS$versions, ","),
                        function(v) v_key %in% v, logical(1))
  MMS_DEFAULTS[has_version, , drop = FALSE]
}

## Round 7 R1.12 / R1.13: per-MMS Frac_GasMS and Frac_LeachMS defaults from
## IPCC 2019 Refinement Vol.4 Ch.10 Table 10.22 — BOTH volatilisation (Frac_GasMS)
## and leaching (Frac_LeachMS). (Corrected citation: leaching is Table 10.22, not
## 10.23; Table 10.23 is the N2:N2O loss ratio.) Values are the "Other Cattle"
## column of Table 10.22; bounds use the IPCC ranges where the table gives them,
## else +-50% (Penman 2000 / Monni 2007).
## Verified + corrected line-by-line on 2026-06-16 against Table 10.22:
##   solid_storage_covered gas 0.10->0.22, leach 0.02->0.00
##   dry_lot      leach 0.00->0.035 (rainfall-dependent, range 0-0.07)
##   deep_bedding gas 0.30->0.25, leach 0.02->0.035
##   composting   leach 0.02->0.06 (static-pile/windrow row, matches gas 0.65)
##   aerobic_treatment gas 0.40->0.85 (forced-aeration Other Cattle)
##   lagoon       gas 0.78->0.35 (0.78 matched no cattle column — clear error)
## (pasture stays 0/0: PRP volatilisation/leaching is the Frac_*_PRP catalogue
##  pathway, not a managed-storage fraction.)
MMS_FRAC_DEFAULTS_2019 <- data.frame(
  mms_type = c("pasture", "daily_spread", "solid_storage",
               "solid_storage_covered", "dry_lot", "deep_bedding",
               "liquid_slurry", "anaerobic_digester", "composting",
               "aerobic_treatment", "lagoon", "burned_for_fuel"),
  frac_gas       = c(0.00, 0.07, 0.45, 0.22, 0.30, 0.25,
                     0.48, 0.05, 0.65, 0.85, 0.35, 0.00),
  frac_gas_low   = c(0.00, 0.04, 0.23, 0.03, 0.15, 0.10,
                     0.24, 0.02, 0.33, 0.27, 0.20, 0.00),
  frac_gas_high  = c(0.00, 0.10, 0.68, 0.26, 0.45, 0.30,
                     0.72, 0.08, 0.98, 1.00, 0.80, 0.00),
  frac_leach     = c(0.00, 0.00, 0.02, 0.00, 0.035, 0.035,
                     0.00, 0.00, 0.06, 0.00, 0.00, 0.00),
  frac_leach_low = c(0.00, 0.00, 0.01, 0.00, 0.00, 0.00,
                     0.00, 0.00, 0.03, 0.00, 0.00, 0.00),
  frac_leach_high = c(0.00, 0.00, 0.03, 0.00, 0.07, 0.07,
                      0.00, 0.00, 0.09, 0.00, 0.00, 0.00),
  stringsAsFactors = FALSE
)

mms_frac_defaults_2019 <- function(mms_type) {
  if (length(mms_type) == 1L) {
    hit <- MMS_FRAC_DEFAULTS_2019[MMS_FRAC_DEFAULTS_2019$mms_type == mms_type, , drop = FALSE]
    if (nrow(hit) == 0L) {
      return(list(frac_gas = 0.20, frac_gas_low = 0.10, frac_gas_high = 0.30,
                  frac_leach = 0.02, frac_leach_low = 0.01, frac_leach_high = 0.03))
    }
    return(as.list(hit[1, -1, drop = FALSE]))
  }
  # vectorised
  hit <- MMS_FRAC_DEFAULTS_2019[match(mms_type, MMS_FRAC_DEFAULTS_2019$mms_type), , drop = FALSE]
  hit$mms_type <- mms_type
  hit
}

GWP_VALUES <- list(
  AR4 = list(CH4 = 25,   N2O = 298),
  AR5 = list(CH4 = 28,   N2O = 265),
  # Andreas 2026-05 follow-up: AR6 CH4 corrected from 27.9 (not an IPCC value)
  # to 27.0 — IPCC AR6 WG1 Table 7.15 gives CH4-fossil = 29.8 and
  # CH4-non-fossil = 27.0. Cattle CH4 (enteric and manure) is biogenic /
  # non-fossil, so 27.0 is the correct value. N2O = 273 unchanged.
  AR6 = list(CH4 = 27.0, N2O = 273)
)

SUBCATS <- c("cows", "heifers", "adult_males", "growing_males", "calves")
SUBCAT_LABELS <- c(cows = "Dairy Cows", heifers = "Heifers (>1yr)",
                   adult_males = "Adult Males (bulls/oxen)",
                   growing_males = "Growing Males (1-3yr)", calves = "Calves (<1yr)")

# ==========================================================================
# CONTROLLED VOCABULARIES FOR INPUT TEMPLATE
# These are used for dropdowns, validation, and auto-fill of defaults
# ==========================================================================

# Livestock species (IPCC Ch 10 scope). Cattle is the primary focus.
SPECIES_OPTIONS <- c("cattle_dairy", "cattle_non_dairy", "buffalo")
SPECIES_LABELS <- c(
  cattle_dairy = "Cattle - Dairy",
  cattle_non_dairy = "Cattle - Non-Dairy (Beef/Other)",
  buffalo = "Buffalo"
)

# Production systems (informed by hypothetical-country inventories + IPCC Table 10A.1/10A.2)
PRODUCTION_SYSTEMS <- c(
  "pastoral", "agro_pastoral", "semi_intensive_dairy", "intensive_dairy",
  "extensive_ranching", "semi_intensive_beef", "intensive_beef",
  "feedlot", "mixed_crop_livestock", "smallholder_dairy"
)
PRODUCTION_SYSTEM_LABELS <- c(
  pastoral = "Pastoral",
  agro_pastoral = "Agro-Pastoral",
  semi_intensive_dairy = "Semi-Intensive Dairy",
  intensive_dairy = "Intensive Dairy",
  extensive_ranching = "Extensive Ranching / Beef",
  semi_intensive_beef = "Semi-Intensive Beef",
  intensive_beef = "Intensive Beef",
  feedlot = "Feedlot",
  mixed_crop_livestock = "Mixed Crop-Livestock",
  smallholder_dairy = "Smallholder Dairy"
)

# System type classification (for reporting and defaults)
SYSTEM_TYPES <- c("dairy", "beef", "mixed")

# Animal sub-categories (IPCC-aligned, expanded to match real inventories)
ANIMAL_SUBCATEGORIES <- c(
  "dairy_cows", "other_cows", "bulls", "oxen",
  "heifers", "growing_males", "calves_female", "calves_male",
  "feedlot_cattle"
)
ANIMAL_SUBCATEGORY_LABELS <- c(
  dairy_cows = "Dairy Cows (mature lactating females)",
  other_cows = "Other Cows (mature non-dairy females, inc. dry)",
  bulls = "Bulls (mature intact males, breeding)",
  oxen = "Oxen (mature castrated males)",
  heifers = "Heifers (young females 1-3yr, not yet calved)",
  growing_males = "Growing Males (young males 1-3yr, steers/bulls)",
  calves_female = "Calves - Female (<1yr)",
  calves_male = "Calves - Male (<1yr)",
  feedlot_cattle = "Feedlot Cattle (concentrated feeding)"
)

# Sex categories
SEX_OPTIONS <- c("female", "male", "mixed")

# Age class categories (harmonised with hypothetical-country templates)
AGE_CLASSES <- c("adult_>3yr", "young_1-3yr", "calf_<1yr", "mixed")
AGE_CLASS_LABELS <- c(
  "adult_>3yr" = "Adult (>3 years)",
  "young_1-3yr" = "Young (1-3 years)",
  "calf_<1yr" = "Calf (<1 year)",
  "mixed" = "Mixed ages"
)

# Feeding situation (IPCC Table 10.5 -> determines Ca coefficient)
FEEDING_SITUATIONS <- c("stall_fed", "pasture_flat", "pasture_hilly")
FEEDING_SITUATION_LABELS <- c(
  stall_fed = "Stall-fed / confined (Ca = 0.00)",
  pasture_flat = "Pasture - flat terrain (Ca = 0.17)",
  pasture_hilly = "Pasture - hilly terrain (Ca = 0.36)"
)
FEEDING_SITUATION_CA <- list(stall_fed = 0.00, pasture_flat = 0.17, pasture_hilly = 0.36)

# Climate zones (IPCC Table 10.17 -> determines MCF)
CLIMATE_ZONES <- c("tropical_moist", "tropical_dry", "temperate", "boreal")
CLIMATE_ZONE_LABELS <- c(
  tropical_moist = "Tropical - warm, moist / wet",
  tropical_dry = "Tropical - warm, dry",
  temperate = "Temperate",
  boreal = "Boreal / Cold"
)

# Data quality indicators (for documentation)
DATA_QUALITY <- c("measured", "country_specific", "regional_default", "ipcc_default", "expert_judgement")
DATA_QUALITY_LABELS <- c(
  measured = "Measured (local study/survey)",
  country_specific = "Country-specific estimate",
  regional_default = "Regional default (continent/biome)",
  ipcc_default = "IPCC default (Tier 1/2 table)",
  expert_judgement = "Expert judgement"
)

# IPCC Guidelines version
IPCC_VERSIONS <- c("2006", "2019_refinement")

# Distribution types supported (mirrors utils_distributions.R)
DISTRIBUTION_TYPES <- c("normal", "posnorm", "lognormal", "beta", "triangular",
                        "pert", "uniform", "constant", "tnorm_0_1")
DISTRIBUTION_LABELS <- c(
  normal = "Normal (symmetric bell curve)",
  posnorm = "Positive Normal (normal, truncated at 0)",
  lognormal = "Log-normal (strictly positive, right-skewed)",
  beta = "Beta (bounded, flexible shape)",
  triangular = "Triangular (min / mode / max, linear)",
  pert = "PERT (modified Beta, peak at mode)",
  uniform = "Uniform (all values in range equally likely)",
  constant = "Constant (no variation)",
  tnorm_0_1 = "Truncated Normal to [0,1]"
)

PARAM_TYPES <- c("activity_data", "coefficient", "emission_factor")  # emission_factor accepted as legacy alias

# ==========================================================================
# PARAMETER -> EMISSION-SOURCE DEPENDENCY MAP
# Andreas 2026-05-27 feedback: the pre-run "blank value cell" gate must only
# require a parameter to be non-blank if at least one *selected* emission
# source actually consumes it. A CH4-only run should not be blocked by blank
# manure-N2O parameters.
#
# .GE_BLOCK are the parameters that feed Gross Energy (IPCC Eq. 10.16) and
# therefore every downstream source (enteric CH4, manure CH4, all N2O via Nex).
# Tw is deliberately excluded — calc_nem() handles NA Tw gracefully (no
# cold-climate adjustment when Tw is NA), so a blank Tw never breaks a run.
# ==========================================================================
.GE_BLOCK <- c("N", "BW", "MW", "WG", "Milk", "Fat", "pct_pregnant", "DE",
               "Cfi", "Ca", "C", "Cp", "hours")

SOURCE_PARAM_DEPS <- list(
  enteric_ch4          = c(.GE_BLOCK, "Ym"),
  manure_ch4           = c(.GE_BLOCK, "UE", "ASH", "Bo"),
  manure_n2o_direct    = c(.GE_BLOCK, "CP", "MilkPR"),
  manure_n2o_indirect  = c(.GE_BLOCK, "CP", "MilkPR", "EF4", "EF5"),
  pasture_n2o_direct   = c(.GE_BLOCK, "CP", "MilkPR", "EF3_PRP"),
  pasture_n2o_indirect = c(.GE_BLOCK, "CP", "MilkPR", "EF4", "EF5",
                           "Frac_GASM_PRP", "Frac_LEACH_PRP")
)
# Parameters NEVER required by the gate, because their value comes from
# elsewhere or a blank is harmless:
#   - EF3_S, Frac_GASMS, Frac_LEACH_H : specified per-MMS in Manure_Management
#       (or fall back to hardcoded IPCC defaults); the Parameters-tab copies
#       are not consumed by the equation chain.
#   - Tw : NA-safe in calc_nem().

# Union of parameters genuinely required by the selected emission sources.
# Returns character(0) when no sources are selected (the "tick at least one
# source" gate handles that case separately).
params_needed_for_sources <- function(sources) {
  if (is.null(sources) || length(sources) == 0) return(character(0))
  # Legacy single "pasture_n2o" checkbox -> both PRP sources.
  if ("pasture_n2o" %in% sources)
    sources <- unique(c(sources, "pasture_n2o_direct", "pasture_n2o_indirect"))
  hit <- intersect(sources, names(SOURCE_PARAM_DEPS))
  if (length(hit) == 0) return(character(0))
  unique(unlist(SOURCE_PARAM_DEPS[hit], use.names = FALSE))
}

# ==========================================================================
# EXPANDED DEFAULT LOOKUPS BY NEW SUB-CATEGORY
# ==========================================================================

# Cfi by sub-category, IPCC Table 10.4 (verified at source 2026-06-16). Strict
# category reading adopted: 0.370 applies ONLY to mature breeding "bulls"; the
# 0.322 category explicitly covers "all non-lactating cows, steers, heifers AND
# calves" — so young/growing/calf males and feedlot stock take 0.322, not the
# intact-bull uplift. (Resolves a prior R-table-vs-translator-prompt mismatch;
# the prompt already used 0.322 for growing_males.)
CFI_BY_SUBCAT <- list(
  dairy_cows = 0.386,     # lactating dairy cows
  other_cows = 0.322,     # dry/non-dairy cows
  bulls = 0.370,          # mature intact males (only category at 0.370)
  oxen = 0.322,           # castrated males (steers)
  heifers = 0.322,        # young females
  growing_males = 0.322,  # young males — not mature bulls
  calves_female = 0.322,
  calves_male = 0.322,    # calves are explicitly in the 0.322 category
  feedlot_cattle = 0.322  # finishing stock, not breeding bulls
)

# Live weight defaults by subcategory (kg, IPCC Africa defaults)
LW_BY_SUBCAT <- list(
  dairy_cows = 275, other_cows = 275, bulls = 350, oxen = 300,
  heifers = 200, growing_males = 200, calves_female = 60, calves_male = 60,
  feedlot_cattle = 250
)

# Mature weight defaults by subcategory (kg)
MW_BY_SUBCAT <- list(
  dairy_cows = 300, other_cows = 300, bulls = 400, oxen = 350,
  heifers = 300, growing_males = 350, calves_female = 300, calves_male = 350,
  feedlot_cattle = 400
)

# Weight gain defaults (kg/day)
WG_BY_SUBCAT <- list(
  dairy_cows = 0.0, other_cows = 0.0, bulls = 0.0, oxen = 0.0,
  heifers = 0.25, growing_males = 0.20, calves_female = 0.30, calves_male = 0.30,
  feedlot_cattle = 1.00
)

# C_growth by subcategory (IPCC Eq 10.6)
C_GROWTH_BY_SUBCAT <- list(
  dairy_cows = 0.8, other_cows = 0.8, bulls = 1.2, oxen = 1.0,
  heifers = 0.8, growing_males = 1.0, calves_female = 0.8, calves_male = 1.0,
  feedlot_cattle = 1.0
)

# Sex inferred from subcategory
SEX_BY_SUBCAT <- list(
  dairy_cows = "female", other_cows = "female", bulls = "male", oxen = "male",
  heifers = "female", growing_males = "male", calves_female = "female",
  calves_male = "male", feedlot_cattle = "mixed"
)

# Age class inferred from subcategory
AGE_BY_SUBCAT <- list(
  dairy_cows = "adult_>3yr", other_cows = "adult_>3yr",
  bulls = "adult_>3yr", oxen = "adult_>3yr",
  heifers = "young_1-3yr", growing_males = "young_1-3yr",
  calves_female = "calf_<1yr", calves_male = "calf_<1yr",
  feedlot_cattle = "young_1-3yr"
)

# Pregnancy fraction defaults by sub-category, matching the translator prompt
# (system_instructions.md Step 5b): breeding females 0.85, replacement heifers
# 0.5. Males and pre-pubertal calves resolve to a biological zero below; any
# other sub-category falls back to the generic PARAM_CATALOGUE default (0.60).
PCT_PREGNANT_BY_SUBCAT <- list(
  dairy_cows = 0.85, other_cows = 0.85, heifers = 0.5
)

# ==========================================================================
# SPARSE-OVERLAY RESOLVER
# ==========================================================================
# resolve_subcat_default() returns the IPCC default for any (sub_category,
# parameter) the AI translator did NOT supply. Under the sparse-overlay design
# the translator emits only user-supplied values; the writer calls this for
# every remaining cell so the produced template is always complete (every
# parameter x sub-category populated, exactly as today).
#
# It is the SINGLE SOURCE OF TRUTH for "what the app derives", assembling only
# objects verified against the IPCC source: the generic PARAM_CATALOGUE row plus
# the per-sub-category overrides above (Cfi/C/BW/MW/WG/pct_pregnant) and the
# biological-zero rules from the translator self-check #9 (Milk/Fat/MilkPR/
# pct_pregnant = 0 for males; pct_pregnant = 0 for pre-pubertal calves; working
# hours = 0 for non-oxen). Returns a list(value, distribution, uncertainty_pct,
# lower, upper, data_source); NULL for an unknown parameter. `N` has no IPCC
# default (value = NA) — it is core activity data the user must always supply.
resolve_subcat_default <- function(sub_category, parameter,
                                   ipcc_version = "2019_refinement") {
  cat <- PARAM_CATALOGUE[PARAM_CATALOGUE$parameter == parameter, , drop = FALSE]
  if (nrow(cat) == 0L) return(NULL)
  sex <- SEX_BY_SUBCAT[[sub_category]]; if (is.null(sex)) sex <- "mixed"
  age <- AGE_BY_SUBCAT[[sub_category]]; if (is.null(age)) age <- "adult_>3yr"
  is_calf <- identical(age, "calf_<1yr")

  bio_zero <- list(value = 0, distribution = "constant",
                   uncertainty_pct = NA_real_, lower = 0, upper = 0,
                   data_source = "biological_zero")

  # Biological zeros (match translator self-check #9 / Step 8 rule 3).
  if (parameter %in% c("Milk", "Fat", "MilkPR") && identical(sex, "male"))
    return(bio_zero)
  if (parameter == "pct_pregnant" && (identical(sex, "male") || is_calf))
    return(bio_zero)
  if (parameter == "hours" && !identical(sub_category, "oxen"))
    return(bio_zero)

  # Generic default from the verified catalogue.
  res <- list(value = cat$ipcc_default[1],
              distribution = cat$suggested_distribution[1],
              uncertainty_pct = cat$suggested_uncertainty_pct[1],
              lower = cat$suggested_lower_bound[1],
              upper = cat$suggested_upper_bound[1],
              data_source = "ipcc_default")

  # Per-sub-category overrides (value only; keep the catalogue distribution and
  # uncertainty, which apply around the sub-category-specific central).
  ov <- switch(parameter,
    Cfi = CFI_BY_SUBCAT[[sub_category]],
    C   = C_GROWTH_BY_SUBCAT[[sub_category]],
    BW  = LW_BY_SUBCAT[[sub_category]],
    MW  = MW_BY_SUBCAT[[sub_category]],
    WG  = WG_BY_SUBCAT[[sub_category]],
    pct_pregnant = PCT_PREGNANT_BY_SUBCAT[[sub_category]],
    NULL)
  if (!is.null(ov)) res$value <- ov

  # A weight gain of exactly 0 (adults) is a no-growth constant, not a spread.
  if (parameter == "WG" && isTRUE(res$value == 0)) {
    res$distribution <- "constant"; res$uncertainty_pct <- NA_real_
    res$lower <- 0; res$upper <- 0
  }
  res
}

# Country X \u2014 hypothetical mid-altitude smallholder dairy system.
# Visibly distinct from Country Y: dairy cattle, milking, higher live weight.
generate_country_x_example <- function() {
  data.frame(
    cattle_type       = rep("dairy", 12),
    aggregation_level = rep("Country X \u2013 smallholder dairy", 12),
    sub_category      = rep("cows", 12),
    parameter = c("N", "BW", "MW", "WG",
                   "Milk", "Fat", "DE", "Cfi", "Ca", "Cp",
                   "Ym", "Bo"),
    mean = c(500000, 275, 300, 0, 4, 4, 55, 0.386, 0.17, 0.10, 6.5, 0.10),
    uncertainty_pct = c(10, 15, 10, 0, 20, 10, 10, 5, 20, 15, 15, 20),
    distribution = c("normal", "normal", "normal", "constant", "normal", "normal",
                      "normal", "pert", "triangular", "beta", "pert", "pert"),
    lower = NA_real_, upper = NA_real_,
    # D1: only cattle_pop is activity_data; everything else is "coefficient"
    param_type = c("activity_data", rep("coefficient", 11)),
    stringsAsFactors = FALSE
  )
}

# R2.2: synthetic 5-year time-series for Country X. Produced so that loading the
# built-in example populates rv$population and rv$corr_matrix the same way an
# Excel upload would, enabling Tab 4's "From template (auto)" mode without a
# separate file. Trends are illustrative (population grows slowly; weight gain
# kicks up with feed quality; Ym drifts down as feed improves).
generate_country_x_timeseries <- function() {
  data.frame(
    year       = 2018:2022,
    N          = c(480000, 488000, 495000, 503000, 510000),
    BW         = c(265, 268, 272, 276, 280),
    MW         = c(295, 297, 300, 302, 305),
    Milk       = c(3.6, 3.8, 4.0, 4.2, 4.4),
    Fat        = c(4.05, 4.0, 4.0, 3.95, 3.95),
    DE         = c(54.0, 54.5, 55.0, 55.5, 56.0),
    Ym         = c(6.8, 6.7, 6.5, 6.4, 6.3),
    stringsAsFactors = FALSE
  )
}

# Country Y \u2014 hypothetical pastoral non-dairy beef system (semi-arid rangeland).
# Visibly different from Country X \u2014 non-dairy, smaller animals, no milk.
generate_country_y_example <- function() {
  data.frame(
    cattle_type       = rep("non_dairy", 11),
    aggregation_level = rep("Country Y \u2013 pastoral rangeland", 11),
    sub_category      = rep("breeding_cows", 11),
    parameter = c("N", "BW", "MW", "WG",
                   "Milk", "DE", "Cfi", "Ca", "Cp",
                   "Ym", "Bo"),
    mean = c(2400000, 230, 260, 0.05, 1.5, 50, 0.322, 0.36, 0.10, 7.0, 0.10),
    uncertainty_pct = c(15, 20, 15, 50, 40, 15, 5, 25, 25, 20, 25),
    distribution = c("normal", "normal", "normal", "pert", "lognormal",
                      "normal", "pert", "triangular", "beta", "pert", "pert"),
    lower = NA_real_, upper = NA_real_,
    # D1: only cattle_pop is activity_data; everything else is "coefficient"
    param_type = c("activity_data", rep("coefficient", 10)),
    stringsAsFactors = FALSE
  )
}

# R2.2: synthetic 5-year time-series for Country Y. Reflects pastoral
# rangeland dynamics: cyclical herd size driven by drought; weight & DE
# move together with rainfall; Ym slightly anti-correlated with DE.
generate_country_y_timeseries <- function() {
  data.frame(
    year       = 2018:2022,
    N          = c(2200000, 2350000, 2400000, 2300000, 2450000),
    BW         = c(220, 235, 230, 225, 240),
    MW         = c(255, 262, 260, 258, 265),
    WG         = c(0.04, 0.06, 0.05, 0.04, 0.06),
    Milk       = c(1.4, 1.6, 1.5, 1.4, 1.6),
    DE         = c(48, 51, 50, 49, 52),
    Ym         = c(7.2, 6.9, 7.0, 7.1, 6.8),
    stringsAsFactors = FALSE
  )
}

# Country X manure-management allocation (4 MMS types).
# Typical for a smallholder dairy in tropical Africa: half the manure
# deposited on pasture during grazing, the rest split between solid kraal
# storage (most), liquid slurry (washing into pits), and a small share to
# anaerobic-digester biogas (an increasingly common practice). Per-MMS MCF
# / EF3 / Frac_GasMS / Frac_LeachMS follow IPCC 2019 Refinement Vol.4 Ch.10
# Tables 10.17, 10.21, 10.22, 10.23 (warm/tropical climate). Uncertainty
# bounds added on fraction_pct, MCF, and EF3 so the per-MMS sampling code
# path is exercised and MMS allocation surfaces in the sensitivity tornado.
generate_country_x_manure <- function() {
  data.frame(
    cattle_type           = rep("dairy", 4),
    aggregation_level     = rep("Country X – smallholder dairy", 4),
    sub_category          = rep("cows", 4),
    mms_type              = c("pasture", "solid_storage", "liquid_slurry",
                               "anaerobic_digester"),
    fraction_pct          = c(50, 30, 15, 5),
    lower_fraction        = c(40, 25, 10, 2),
    upper_fraction        = c(60, 35, 20, 8),
    distribution_fraction = rep("pert", 4),
    MCF_pct               = c(1.5, 4.0, 71.0, 10.0),
    lower_mcf             = c(1.0, 2.0, 50.0, 5.0),
    upper_mcf             = c(2.0, 8.0, 80.0, 20.0),
    distribution_mcf      = rep("pert", 4),
    EF3                   = c(0.020, 0.005, 0.005, 0.0006),
    lower_ef3             = c(0.007, 0.0025, 0.0025, 0.0003),
    upper_ef3             = c(0.060, 0.0250, 0.0250, 0.0015),
    distribution_ef3      = rep("pert", 4),
    Frac_GasMS_pct        = c(21, 45, 32, 5),
    Frac_LeachMS_pct      = c(30,  2,  0, 0),
    stringsAsFactors      = FALSE
  )
}

# Country Y manure-management allocation (2 MMS types).
# Pastoral non-dairy beef cattle: almost all manure stays on the rangeland
# (pasture), with a small fraction in solid storage during occasional
# overnight confinement in kraals.
generate_country_y_manure <- function() {
  data.frame(
    cattle_type           = rep("non_dairy", 2),
    aggregation_level     = rep("Country Y – pastoral rangeland", 2),
    sub_category          = rep("breeding_cows", 2),
    mms_type              = c("pasture", "solid_storage"),
    fraction_pct          = c(90, 10),
    lower_fraction        = c(80,  5),
    upper_fraction        = c(95, 20),
    distribution_fraction = rep("pert", 2),
    MCF_pct               = c(1.5, 4.0),
    lower_mcf             = c(1.0, 2.0),
    upper_mcf             = c(2.0, 8.0),
    distribution_mcf      = rep("pert", 2),
    EF3                   = c(0.020, 0.005),
    lower_ef3             = c(0.007, 0.0025),
    upper_ef3             = c(0.060, 0.0250),
    distribution_ef3      = rep("pert", 2),
    Frac_GasMS_pct        = c(21, 45),
    Frac_LeachMS_pct      = c(30,  2),
    stringsAsFactors      = FALSE
  )
}

# Fill in lower/upper bounds from explicit overrides or uncertainty_pct
# Priority: lower_bound/upper_bound columns (if present and non-NA) > ±pct formula
fill_bounds <- function(param_specs) {
  has_lb <- "lower_bound" %in% names(param_specs)
  has_ub <- "upper_bound" %in% names(param_specs)
  for (i in seq_len(nrow(param_specs))) {
    # Determine lower
    if (is.na(param_specs$lower[i])) {
      if (has_lb && !is.na(param_specs$lower_bound[i])) {
        param_specs$lower[i] <- param_specs$lower_bound[i]
      } else {
        bounds <- calc_bounds(param_specs$mean[i], param_specs$uncertainty_pct[i])
        param_specs$lower[i] <- bounds$lower
      }
    }
    # Determine upper
    if (is.na(param_specs$upper[i])) {
      if (has_ub && !is.na(param_specs$upper_bound[i])) {
        param_specs$upper[i] <- param_specs$upper_bound[i]
      } else {
        bounds <- calc_bounds(param_specs$mean[i], param_specs$uncertainty_pct[i])
        param_specs$upper[i] <- bounds$upper
      }
    }
  }
  param_specs
}
