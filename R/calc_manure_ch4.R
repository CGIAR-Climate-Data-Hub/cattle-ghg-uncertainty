# IPCC Tier 2 Manure Management CH4 Emissions
# Source: IPCC 2006 Guidelines, Volume 4, Chapter 10, Eq 10.23-10.24

# Volatile Solids excretion rate (Eq 10.24) - kg DM/head/day
# C1: DE (was DE_pct), ASH (was ash) — IPCC software-aligned names.
# Andreas 2026-05 audit follow-up: bounds checks. ASH and UE are fractions
# in [0, 1]; out-of-range values silently produce wrong VS otherwise.
calc_volatile_solids <- function(ge, DE,
                                 UE  = .cat_default("UE"),
                                 ASH = .cat_default("ASH")) {
  if (!is.na(ASH) && (ASH < 0 || ASH >= 1))
    warning("ASH = ", ASH, " is outside [0, 1). Typical IPCC value is 0.08.")
  if (!is.na(UE)  && (UE  < 0 || UE  >  1))
    warning("UE = ",  UE,  " is outside [0, 1]. Typical IPCC value is 0.04.")
  (ge * (1 - DE / 100) + UE * ge) * ((1 - ASH) / 18.45)
}

# Manure CH4 emission factor per head per year (Eq 10.23) - kg CH4/head/year
# mms_fractions: named numeric vector of MMS fractions (sum to 1)
# mcf_values: named numeric vector of MCF values (as fractions, not %)
# Bo: maximum CH4 producing capacity (m3 CH4/kg VS)
calc_manure_ch4 <- function(VS, Bo, mms_fractions, mcf_values) {
  total <- 0
  for (mms in names(mms_fractions)) {
    frac <- mms_fractions[mms]
    mcf <- mcf_values[mms]
    total <- total + VS * 365 * Bo * 0.67 * mcf * frac
  }
  total
}
