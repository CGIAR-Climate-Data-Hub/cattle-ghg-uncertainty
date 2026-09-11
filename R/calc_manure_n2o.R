# IPCC Tier 2 Manure Management N2O Emissions
# Source: IPCC 2006 Guidelines, Volume 4, Chapter 10 (Eq 10.25-10.34) & Chapter 11

# Nitrogen excretion rate - kg N/head/year (simplified from Eq 10.31-10.34).
# C1: DE (was DE_pct), CP (was CP_pct) — IPCC software-aligned names.
# Andreas 2026-05 follow-up: `MilkPR` (milk protein %) is now a function
# argument instead of a hardcoded 3.3 constant. Users can override it
# per sub-category via the Parameters template (catalogue default 3.3
# is the IPCC 2006 Table 10.11 mid-point for African dairy).
# Weight-gain N retention uses the simplified coefficient 0.032 (Monni
# 2007 / IPCC software approximation of the weight-gain term in Eq 10.33;
# the full IPCC Eq 10.33 requires protein-content data not in the
# standard input set).
calc_n_excretion <- function(ge, CP, milk_yield = 0, pct_pregnant = 0,
                              weight_gain = 0, MilkPR = 3.3) {
  # IPCC 2006 / 2019 Refinement Vol.4 Ch.10 Eq 10.32 (N intake rates for cattle):
  #   N_intake = (GE / 18.45) * (CP% / 100) / 6.25
  # i.e. dry-matter feed mass (GE / 18.45) * protein fraction (CP% / 100) /
  # protein-to-N ratio (6.25). NO `DE` factor — that belongs in the volatile-
  # solids equation (Eq 10.24), where we want the UN-digested fraction.
  # Earlier code wrote N_intake = (GE * DE / 100) / 18.45 * ... which mixed
  # the DE factor in here and under-estimated N intake by ~25-30%, causing
  # downstream Nex / direct N2O MM / indirect N2O MM to be similarly low
  # (Andreas's A1/A2 finding, 2026-05-15 review). The `DE` argument was
  # removed from the signature after the fix; callers should pass only ge.
  # Defensive bounds check on MilkPR (IPCC Table 10.11 range 2.8-3.8%).
  if (!is.na(MilkPR) && (MilkPR < 0 || MilkPR > 10))
    warning("MilkPR = ", MilkPR, " is outside the IPCC Table 10.11 typical ",
            "range (2.8-3.8%). Verify the value.")
  DMI <- ge / 18.45
  N_intake <- DMI * (CP / 100) / 6.25

  N_retained <- 0
  # Andreas 2026-05-26 follow-up: `isTRUE(x > 0)` instead of bare `x > 0` so
  # an NA in milk_yield / pct_pregnant / weight_gain (e.g. a yellow-required
  # cell the user left blank in the template) collapses to FALSE here instead
  # of tripping `if(NA)` with "missing value where TRUE/FALSE needed". The
  # NA itself still propagates through the subtraction below so the user
  # sees an NA in the per-iteration result rather than a silent zero; the
  # pre-run NA-mean check in the simulation observer is the canonical
  # safeguard.
  if (isTRUE(milk_yield > 0) && isTRUE(pct_pregnant > 0)) {
    # IPCC Vol.4 Ch.10 Eq 10.33 (N retention rates for cattle, milk-N term):
    # milk_yield is daily kg per lactating animal; pct_pregnant averages across
    # the sub-category. MilkPR is in % (e.g. 3.3); /6.38 is the milk-protein
    # to milk-N conversion (Jones casein factor) defined inside Eq 10.33.
    N_retained <- milk_yield * pct_pregnant * MilkPR / 100 / 6.38
  }
  if (isTRUE(weight_gain > 0)) {
    N_retained <- N_retained + weight_gain * 0.032
  }

  max(0, (N_intake - N_retained) * 365)
}

# Direct N2O from manure management (Eq 10.25) - kg N2O/head/year
# Excludes pasture (handled separately as PRP)
calc_direct_n2o_mm <- function(Nex, mms_fractions, ef3_values) {
  total <- 0
  for (mms in names(mms_fractions)) {
    if (mms == "pasture") next
    frac <- mms_fractions[mms]
    ef3 <- ef3_values[mms]
    total <- total + Nex * frac * ef3 * (44 / 28)
  }
  total
}

# Indirect N2O from manure management - kg N2O/head/year
# Round 7 R1.13: per-MMS Frac_GasMS and Frac_LeachMS per IPCC 2019 Refinement
# Vol 4 Ch 10 Eq 10.26 / 10.28. EF4 and EF5 stay broadcast scalars (per IPCC
# 2019 they are invariant by MMS).
#
# Accepts EITHER:
#   (a) `frac_gas_values` / `frac_leach_values` as named vectors keyed by
#       mms_type (post-Round-7 calling convention), OR
#   (b) `frac_gas` / `frac_leach` as scalars (pre-Round-7 broadcast convention,
#       still accepted for back-compat — the wrapper builds constant vectors).
calc_indirect_n2o_mm <- function(Nex, mms_fractions,
                                  frac_gas_values  = NULL,
                                  frac_leach_values = NULL,
                                  # IPCC 2019 Refinement Vol.4 Ch.11 Table 11.3.
                                  # EF4: aggregated 0.010 (wet 0.014, dry 0.005); 2006 = 0.010.
                                  # EF5: 0.011 in 2019R (no climate disaggregation); 2006 = 0.0075.
                                  # From the master, never a literal: EF4
                                  # sat at the aggregated 0.010 here while
                                  # the catalogue held the wet-climate
                                  # 0.014. Evaluated lazily, so the
                                  # catalogue need not exist at source time.
                                  EF4 = .cat_default("EF4"),
                                  EF5 = .cat_default("EF5"),
                                  frac_gas   = .cat_default("Frac_GASM_PRP"),
                                  frac_leach = 0.02) {
  total <- 0
  for (mms in names(mms_fractions)) {
    if (mms == "pasture") next
    frac <- mms_fractions[mms]
    fg <- if (!is.null(frac_gas_values) && mms %in% names(frac_gas_values)
              && !is.na(frac_gas_values[mms])) {
      frac_gas_values[mms]
    } else {
      # NA fallback to IPCC 2019 default per MMS, then to broadcast scalar
      def <- mms_frac_defaults_2019(mms)
      if (!is.na(def$frac_gas)) def$frac_gas else frac_gas
    }
    fl <- if (!is.null(frac_leach_values) && mms %in% names(frac_leach_values)
              && !is.na(frac_leach_values[mms])) {
      frac_leach_values[mms]
    } else {
      def <- mms_frac_defaults_2019(mms)
      if (!is.na(def$frac_leach)) def$frac_leach else frac_leach
    }
    total <- total + Nex * frac * fg * EF4 * (44 / 28)
    total <- total + Nex * frac * fl * EF5 * (44 / 28)
  }
  total
}

# Direct N2O from pasture/range/paddock (PRP) - kg N2O/head/year
# IPCC Vol.4 Ch.11 Eq. 11.1; EF3_PRP from Table 11.1.
#   2006 default EF3_PRP (cattle/poultry/pigs)        : 0.02 kg N2O-N / kg N
#   2019 Refinement EF3_PRP,CPP aggregated default   : 0.004 (range 0.000-0.014)
#     wet climate                                    : 0.006 (range 0.000-0.027)
#     dry climate                                    : 0.002 (range 0.000-0.007)
# The unconditional default below is the aggregated 2019R value.
calc_direct_n2o_prp <- function(Nex, pct_pasture,
                                # 0.004 was the climate-aggregated value;
                                # the catalogue holds the wet-climate 0.006.
                                EF3_PRP = .cat_default("EF3_PRP")) {
  N_prp <- Nex * pct_pasture
  N_prp * EF3_PRP * (44 / 28)
}

# Indirect N2O from PRP - kg N2O/head/year
# IPCC Vol.4 Ch.11 Eq. 11.9 (volatilisation, uses EF4 and FracGASM) and
# Eq. 11.10 (leaching, uses EF5 and FracLEACH-(H)). Defaults are the 2019
# Refinement Vol.4 Ch.11 Table 11.3 values:
#   FracGASM            : 0.21 (2019R aggregated; 2006 = 0.20)
#   EF4 (aggregated)    : 0.010 (2019R; same as 2006). Wet = 0.014; Dry = 0.005.
#   FracLEACH-(H)       : 0.24 (2019R wet; 2006 = 0.30). In dry climates = 0.
#   EF5                 : 0.011 (2019R; 2006 = 0.0075). Not climate-disaggregated.
# These are the soil-side PRP fractions (Vol.4 Ch.11). They share their
# numerical IPCC source with the managed-soil indirect pathways but are
# logically distinct from the managed-storage fractions in Vol.4 Ch.10
# Tables 10.22 / 10.23; earlier versions of this app reused Frac_GASMS /
# Frac_LEACH_H for both pathways, conflating the two.
calc_indirect_n2o_prp <- function(Nex, pct_pasture,
                                   Frac_GASM_PRP = 0.21, EF4 = 0.010,
                                   Frac_LEACH_PRP = 0.24, EF5 = 0.011) {
  N_prp <- Nex * pct_pasture
  volatilization <- N_prp * Frac_GASM_PRP * EF4 * (44 / 28)
  leaching <- N_prp * Frac_LEACH_PRP * EF5 * (44 / 28)
  volatilization + leaching
}
