# IPCC Tier 2 Energy Requirement Calculations
# Source: IPCC 2006 Guidelines, Volume 4, Chapter 10

# Net Energy for Maintenance (Eq 10.3) - MJ/head/day
# E1: Tw cold-climate adjustment is IPCC Vol.4 Ch.10 Eq 10.2 (2006 and 2019R),
# which adjusts the Cfi from Eq 10.3 for open-lot cattle in colder climates:
#   Cfi(in_cold) = Cfi + 0.0048 * (20 - Tw)   when Tw < 20°C
# The same formula is implemented in the IPCC Inventory Software v2.95.
# Andreas 2026-05 audit follow-up: warn on extreme Tw values which would
# inflate Cfi by >50%. The linear adjustment is validated for roughly
# -50°C ≤ Tw < 20°C; outside that range it isn't validated.
calc_nem <- function(live_weight, Cfi, Tw = 20) {
  if (!is.na(Tw) && Tw < -50)
    warning("Tw = ", Tw, "°C is extremely cold; cold-climate Cfi adjustment ",
            "(IPCC Vol.4 Ch.10 Eq 10.2) is only validated for Tw >= -50°C.")
  Cfi_adj <- if (!is.na(Tw) && Tw < 20) Cfi + 0.0048 * (20 - Tw) else Cfi
  Cfi_adj * (live_weight ^ 0.75)
}

# Net Energy for Activity (Eq 10.4) - MJ/head/day
calc_nea <- function(nem, Ca) {
  Ca * nem
}

# Net Energy for Growth (Eq 10.6) - MJ/head/day
calc_neg <- function(live_weight, weight_gain, C, mature_weight) {
  # Andreas 2026-05-26 follow-up: `isTRUE(x <= 0)` instead of bare `x <= 0`
  # so NAs in weight_gain or mature_weight (e.g. a blank yellow cell) don't
  # trip `if(NA)` with "missing value where TRUE/FALSE needed". When either
  # is NA we fall through to the equation, which will produce NA: that NA
  # propagates downstream and the pre-run NA-mean check in the simulation
  # observer is what blocks the run with a helpful message.
  if (isTRUE(weight_gain <= 0) || isTRUE(mature_weight <= 0)) return(0)
  22.02 * ((live_weight / (C * mature_weight)) ^ 0.75) * (weight_gain ^ 1.097)
}

# Net Energy for Lactation (Eq 10.8) - MJ/head/day
#
# NO pct_pregnant factor, and the argument is REMOVED rather than ignored so
# that a caller still passing it fails loudly.
#
# Equation 10.8 is NE_l = Milk x (1.47 + 0.40 x Fat), with nothing else in
# it, and IPCC defines the Milk input as "total annual production divided by
# 365" (Vol.4 Ch.10, Average daily milk production). That figure is ALREADY
# averaged over the whole year including the dry period, so weighting it
# again by the fraction of females calving discounted it twice: at
# pct_pregnant 0.52 the tool produced 1.99 MJ/day where Eq 10.8 gives 3.83.
#
# The weighting IS correct for pregnancy, and calc_nep() keeps it: Table
# 10.7 says "the NEp estimate must be weighted by the portion of the mature
# females that actually go through gestation in a year". It was never
# sanctioned for lactation.
#
# Review round 5 item 9 asked whether merging pct_lactating into
# pct_pregnant was "both IPCC-compliant and simpler". The 28 May rename
# settled simpler. This settles compliant: one parameter can serve both
# roles only if it is applied where IPCC applies it, which is NE_p alone.
calc_nel <- function(milk_yield, milk_fat) {
  milk_yield * (1.47 + 0.40 * milk_fat)
}

# Net Energy for Work (Eq 10.11) - MJ/head/day
calc_new <- function(nem, hours) {
  0.10 * nem * hours
}

# Net Energy for Pregnancy (Eq 10.13) - MJ/head/day
# E3: pct_pregnant pro-rates Cp for cattle that don't all calve in the same year.
# Default 1.0 = no pro-rating (all females pregnant); IPCC software allows 0-1.
calc_nep <- function(nem, Cp, pct_pregnant = 1) {
  Cp * pct_pregnant * nem
}

# REM - Ratio of NE for maintenance to DE consumed (Eq 10.14)
calc_rem <- function(DE) {
  if (any(DE <= 0, na.rm = TRUE))
    stop("calc_rem: DE must be > 0 (got ", DE, "). Check DE_pct in the Parameters sheet.")
  1.123 - (4.092e-3 * DE) + (1.126e-5 * DE^2) - (25.4 / DE)
}

# REG - Ratio of NE for growth to DE consumed (Eq 10.15)
calc_reg <- function(DE) {
  if (any(DE <= 0, na.rm = TRUE))
    stop("calc_reg: DE must be > 0 (got ", DE, "). Check DE_pct in the Parameters sheet.")
  1.164 - (5.160e-3 * DE) + (1.308e-5 * DE^2) - (37.4 / DE)
}

# Gross Energy intake (Eq 10.16) - MJ/head/day
calc_ge <- function(nem, nea, nel, nep, new_energy, neg, rem, reg, DE) {
  GE_num <- (nem + nea + nel + new_energy + nep) / rem + neg / reg
  GE_num / (DE / 100)
}

# IPCC dietary energy density, MJ per kg of feed dry matter. IPCC treats this
# as near-constant across forage and grain diets and hard-codes it inside
# Eq 10.24 (volatile solids) and Eq 10.32 (N intake), which is why those two
# equations keep using it even when a user supplies a measured intake whose
# own implied density differs. See the "measured intake" section of the
# methodology: that residual is the IPCC method, not a defect here.
GE_MJ_PER_KG_DM <- 18.45

# Measured-intake override (2026-09).
#
# The Tier 2 chain above infers gross energy from what the animal DOES:
# maintenance, activity, growth, lactation, work and pregnancy. Datasets that
# measured feed intake instead already know GE, or know dry-matter intake and
# can convert. They typically have no milk yield or weight gain at all,
# because they never needed to infer anything.
#
# Semantics, applied ELEMENT BY ELEMENT so one inventory can mix measured and
# modelled sub-categories:
#   supplied GE  -> use it
#   else supplied DMI -> DMI * 18.45
#   else         -> the value the energy chain just computed
# A value that is NA, non-finite or <= 0 counts as "not supplied". Zero is
# treated as absent deliberately: a zero intake is never a real measurement,
# and reading it as one would silently zero every emission for that group.
#
# GE beats DMI because a supplied GE carries the dataset's own measured feed
# energy density, whereas converting DMI imposes the IPCC 18.45.
#
# Both arguments NULL is the universal case for existing inventories, and it
# returns `ge_chain` itself, untouched, with no arithmetic performed. That is
# what makes the no-override path bit-for-bit identical rather than merely
# numerically close. Audit F50 asserts it with identical().
resolve_ge <- function(ge_chain, GE_measured = NULL, DMI_measured = NULL) {
  if (is.null(GE_measured) && is.null(DMI_measured)) return(ge_chain)

  usable <- function(x) !is.na(x) & is.finite(x) & x > 0
  n <- max(length(ge_chain),
           if (is.null(GE_measured)) 0L else length(GE_measured),
           if (is.null(DMI_measured)) 0L else length(DMI_measured))

  override <- rep(NA_real_, n)
  if (!is.null(DMI_measured)) {
    d <- rep_len(as.numeric(DMI_measured), n)
    ok <- usable(d)
    override[ok] <- d[ok] * GE_MJ_PER_KG_DM
  }
  if (!is.null(GE_measured)) {
    g <- rep_len(as.numeric(GE_measured), n)
    ok <- usable(g)
    override[ok] <- g[ok]          # applied second, so GE wins over DMI
  }

  # rep_len + logical index rather than ifelse(): ifelse is length-fragile
  # when one side is scalar and the other length n, and it drops attributes.
  out <- rep_len(ge_chain, n)
  hit <- !is.na(override)
  out[hit] <- override[hit]
  out
}
