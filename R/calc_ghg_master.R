# Master GHG Emissions Calculation
# Combines enteric fermentation, manure CH4, and manure N2O pathways
# C1: variable names IPCC-aligned (DE, CP, Ym, ASH, Frac_GASMS, Frac_LEACH_H)

# Master function for a single animal sub-category - returns named list
ghg_emissions <- function(
  cattle_pop, live_weight, weight_gain, mature_weight,
  milk_yield, milk_fat, pct_pregnant,
  hours, DE, Cfi, Ca, C_growth, Cp,
  Ym, Bo, ASH, UE, CP,
  mms_fractions, mcf_values, ef3_values,
  EF3_PRP, Frac_GASMS, EF4, EF5, Frac_LEACH_H,
  gwp = "AR5",
  # E1: cold-climate Cfi adjustment; E3: pct_pregnant weights NEL, NEp, and N excretion
  Tw = 20,
  # Round 7 R1.13: per-MMS Frac_GasMS / Frac_LeachMS named vectors. NULL =
  # use IPCC 2019 defaults from mms_frac_defaults_2019(). For back-compat with
  # callers that haven't been updated, the legacy broadcast Frac_GASMS scalar
  # above is still applied to the manure-management indirect path as a fallback.
  frac_gas_values   = NULL,
  frac_leach_values = NULL,
  # Andreas 2026-05 comment #10: PRP volatilization/leaching fractions are
  # distinct from MM (IPCC 2019 Table 11.3 vs Table 10.22). NULL = fall back
  # to Table 11.3 defaults for back-compat with callers that don't yet pass
  # PRP-specific values.
  Frac_GASM_PRP  = NULL,
  Frac_LEACH_PRP = NULL,
  # Andreas 2026-05 follow-up: MilkPR (milk protein %) is now threaded
  # through here from the sampled parameters instead of being hardcoded
  # in calc_n_excretion. Default 3.3 matches IPCC 2006 Table 10.11.
  MilkPR = 3.3
) {
  # E1: cold-climate Cfi adjustment via Tw
  nem <- calc_nem(live_weight, Cfi, Tw = Tw)
  nea <- calc_nea(nem, Ca)
  neg <- calc_neg(live_weight, weight_gain, C_growth, mature_weight)
  nel <- calc_nel(milk_yield, milk_fat, pct_pregnant)
  new_energy <- calc_new(nem, hours)
  # E3: Cp pro-rated by pct_pregnant (% of females that give birth in a year)
  nep <- calc_nep(nem, Cp, pct_pregnant = pct_pregnant)
  rem <- calc_rem(DE)
  reg <- calc_reg(DE)
  ge <- calc_ge(nem, nea, nel, nep, new_energy, neg, rem, reg, DE)

  # Enteric CH4
  enteric_ch4_head <- calc_enteric_ch4(ge, Ym)
  enteric_ch4_total <- (enteric_ch4_head * cattle_pop) / 1000

  # Manure CH4
  VS <- calc_volatile_solids(ge, DE, UE, ASH)
  manure_ch4_head <- calc_manure_ch4(VS, Bo, mms_fractions, mcf_values)
  manure_ch4_total <- (manure_ch4_head * cattle_pop) / 1000

  # N excretion and N2O. DE no longer passed — see calc_n_excretion comments.
  Nex <- calc_n_excretion(ge, CP, milk_yield, pct_pregnant, weight_gain,
                           MilkPR = MilkPR)
  pct_pasture <- ifelse("pasture" %in% names(mms_fractions),
                        mms_fractions["pasture"], 0)

  direct_n2o_mm_head <- calc_direct_n2o_mm(Nex, mms_fractions, ef3_values)
  indirect_n2o_mm_head <- calc_indirect_n2o_mm(
    Nex, mms_fractions,
    frac_gas_values  = frac_gas_values,
    frac_leach_values = frac_leach_values,
    EF4 = EF4, EF5 = EF5,
    frac_gas = Frac_GASMS, frac_leach = Frac_LEACH_H
  )
  direct_n2o_prp_head <- calc_direct_n2o_prp(Nex, pct_pasture, EF3_PRP)
  # Andreas 2026-05 #10: prefer PRP-specific Frac defaults (Table 11.3) when
  # supplied; fall back to the function defaults (0.21 / 0.30) if the caller
  # passed NULL.
  prp_fg <- if (!is.null(Frac_GASM_PRP))  Frac_GASM_PRP  else 0.21
  # IPCC 2019R Vol.4 Ch.11 Table 11.3: Frac_LEACH-(H) = 0.24 (wet climate);
  # dry-climate default is 0. 2006 default was 0.30. Align all three default
  # sites in the codebase on 0.24 — runs targeting 2006 must supply the
  # value via the Parameters template explicitly.
  prp_fl <- if (!is.null(Frac_LEACH_PRP)) Frac_LEACH_PRP else 0.24
  indirect_n2o_prp_head <- calc_indirect_n2o_prp(
    Nex, pct_pasture,
    Frac_GASM_PRP  = prp_fg, EF4 = EF4,
    Frac_LEACH_PRP = prp_fl, EF5 = EF5)

  direct_n2o_mm_total <- (direct_n2o_mm_head * cattle_pop) / 1000
  indirect_n2o_mm_total <- (indirect_n2o_mm_head * cattle_pop) / 1000
  direct_n2o_prp_total <- (direct_n2o_prp_head * cattle_pop) / 1000
  indirect_n2o_prp_total <- (indirect_n2o_prp_head * cattle_pop) / 1000

  total_ch4 <- enteric_ch4_total + manure_ch4_total
  total_n2o <- direct_n2o_mm_total + indirect_n2o_mm_total +
               direct_n2o_prp_total + indirect_n2o_prp_total

  gwp_vals <- GWP_VALUES[[gwp]]
  co2e_ch4 <- total_ch4 * gwp_vals$CH4
  co2e_n2o <- total_n2o * gwp_vals$N2O
  total_co2e <- co2e_ch4 + co2e_n2o

  list(
    ge = ge, enteric_ch4_head = enteric_ch4_head,
    enteric_ch4_total = enteric_ch4_total,
    VS = VS, manure_ch4_head = manure_ch4_head,
    manure_ch4_total = manure_ch4_total,
    Nex = Nex,
    direct_n2o_mm_total = direct_n2o_mm_total,
    indirect_n2o_mm_total = indirect_n2o_mm_total,
    direct_n2o_prp_total = direct_n2o_prp_total,
    indirect_n2o_prp_total = indirect_n2o_prp_total,
    total_ch4 = total_ch4, total_n2o = total_n2o,
    co2e_ch4 = co2e_ch4, co2e_n2o = co2e_n2o,
    total_co2e = total_co2e
  )
}

# Vectorized version for Monte Carlo - returns data.frame
ghg_emissions_vec <- function(
  cattle_pop, live_weight, weight_gain, mature_weight,
  milk_yield, milk_fat, pct_pregnant,
  hours, DE, Cfi, Ca, C_growth, Cp,
  Ym, Bo, ASH, UE, CP,
  mms_fractions, mcf_values, ef3_values,
  EF3_PRP, Frac_GASMS, EF4, EF5, Frac_LEACH_H,
  gwp = "AR5",
  Tw = 20,
  frac_gas_values   = NULL,
  frac_leach_values = NULL,
  # Andreas 2026-05 #10: PRP-specific volatilization/leaching fractions
  # (IPCC 2019 Table 11.3). NULL = broadcast a constant from IPCC defaults.
  Frac_GASM_PRP  = NULL,
  Frac_LEACH_PRP = NULL,
  # Andreas 2026-05 follow-up: MilkPR (milk protein %, IPCC 2006 Table 10.11)
  # threaded through to calc_n_excretion. NULL/scalar/vector all supported.
  MilkPR = NULL,
  # Andreas 2026-05 follow-up (C4 / C6): per-iteration per-MMS uncertainty
  # matrices (n_iter × n_MMS). When supplied, the named per-MMS vector for
  # iteration i is row mat[i, ], used in place of the scalar mcf_values /
  # ef3_values / frac_gas_values / frac_leach_values for that iteration.
  mcf_samples        = NULL,
  ef3_samples        = NULL,
  frac_gas_samples   = NULL,
  frac_leach_samples = NULL,
  # Andreas 28/5/26 #4: per-iteration MMS allocation matrix (n_iter × n_MMS,
  # rows pre-renormalised to sum to 1). NULL = treat mms_fractions as a
  # deterministic vector across iterations (pre-fix behaviour).
  mms_fraction_samples = NULL
) {
  # Round 11 (2026-06): fully vectorised over all n iterations. Previously this
  # looped i = 1..n calling the scalar ghg_emissions() once per iteration, which
  # dominated runtime on large inventories (the 32-sub-category Zambia run at
  # 30k iterations × 4 simulations took minutes). Every IPCC equation here is
  # element-wise, so the loop is replaced by whole-vector arithmetic; the only
  # remaining loop is over the handful of MMS *types* (not iterations).
  #
  # The scalar ghg_emissions() and all calc_*() helpers are intentionally left
  # untouched — they remain the reference the audit (deterministic golden case)
  # and the equivalence test check against. This function reproduces their
  # output bit-for-bit, including operation order and the historical broadcast
  # defaults (e.g. Frac_LEACH_PRP -> 0.30 when the caller passes NULL; the app
  # always supplies it via get_param() so that path is never hit in practice).
  n <- length(cattle_pop)

  # Broadcast scalar / NULL arguments to length n (behaviour preserved exactly).
  .bcast <- function(x, default) {
    if (is.null(x)) rep(default, n)
    else if (length(x) == 1L) rep(x, n)
    else x
  }
  prp_fg_vec <- .bcast(Frac_GASM_PRP,  0.21)
  prp_fl_vec <- .bcast(Frac_LEACH_PRP, 0.30)
  milkpr_vec <- .bcast(MilkPR, 3.3)
  tw_vec     <- .bcast(Tw, 20)

  # Per-MMS lookup -> length-n vector for MMS `key`, matching the scalar engine's
  # .row_or_scalar(mat, scalar_vec, i)[key] semantics exactly: sample column when
  # present (NA entries fall back to the named scalar), the named scalar when no
  # matrix is supplied, and NA when the key is absent from the matrix columns.
  .mms_vec <- function(mat, scalar_vec, key) {
    if (is.null(mat)) {
      v <- if (!is.null(scalar_vec) && key %in% names(scalar_vec))
             as.numeric(scalar_vec[[key]]) else NA_real_
      return(rep(v, n))
    }
    if (!(key %in% colnames(mat))) return(rep(NA_real_, n))
    col <- as.numeric(mat[, key])
    bad <- is.na(col)
    if (any(bad)) {
      fb <- if (!is.null(scalar_vec) && key %in% names(scalar_vec))
              as.numeric(scalar_vec[[key]]) else NA_real_
      col[bad] <- fb
    }
    col
  }

  # Indirect-MM Frac_GasMS / Frac_LeachMS with the scalar engine's 3-level
  # fallback (calc_indirect_n2o_mm): per-iteration sample (NA -> named scalar)
  # -> IPCC 2019 per-MMS default -> broadcast scalar. `field` is the
  # mms_frac_defaults_2019() list element ("frac_gas" or "frac_leach").
  .frac_gl_vec <- function(samp_mat, named_vec, key, field, broadcast_vec) {
    if (is.null(samp_mat)) {
      cand <- if (is.null(named_vec) || !(key %in% names(named_vec)))
                rep(NA_real_, n) else rep(as.numeric(named_vec[[key]]), n)
    } else if (!(key %in% colnames(samp_mat))) {
      cand <- rep(NA_real_, n)
    } else {
      cand <- as.numeric(samp_mat[, key])
      bad <- is.na(cand)
      if (any(bad)) {
        fb <- if (!is.null(named_vec) && key %in% names(named_vec))
                as.numeric(named_vec[[key]]) else NA_real_
        cand[bad] <- fb
      }
    }
    avail    <- !is.na(cand)
    def      <- mms_frac_defaults_2019(key)[[field]]
    fallback <- if (!is.na(def)) rep(def, n) else broadcast_vec
    ifelse(avail, cand, fallback)
  }

  # ---- Energy requirements (IPCC Vol.4 Ch.10) ----
  # nem (Eq 10.3) with vectorised cold-climate Cfi adjustment (Eq 10.2):
  Cfi_adj <- ifelse(!is.na(tw_vec) & tw_vec < 20, Cfi + 0.0048 * (20 - tw_vec), Cfi)
  nem <- Cfi_adj * (live_weight ^ 0.75)
  nea <- calc_nea(nem, Ca)
  # neg (Eq 10.6): 0 when weight_gain<=0 or mature_weight<=0 (matches the scalar
  # isTRUE() guards, including NA fall-through). An NA power base for non-positive
  # weight_gain keeps the discarded ifelse branch from raising a NaN warning.
  neg_zero <- (!is.na(weight_gain) & weight_gain <= 0) |
              (!is.na(mature_weight) & mature_weight <= 0)
  wg_pos   <- ifelse(!is.na(weight_gain) & weight_gain > 0, weight_gain, NA_real_)
  neg_full <- 22.02 * ((live_weight / (C_growth * mature_weight)) ^ 0.75) *
              (wg_pos ^ 1.097)
  neg <- ifelse(neg_zero, 0, neg_full)
  nel <- calc_nel(milk_yield, milk_fat, pct_pregnant)
  new_energy <- calc_new(nem, hours)
  nep <- calc_nep(nem, Cp, pct_pregnant = pct_pregnant)
  rem <- calc_rem(DE)
  reg <- calc_reg(DE)
  ge  <- calc_ge(nem, nea, nel, nep, new_energy, neg, rem, reg, DE)

  # ---- Enteric CH4 (Eq 10.21) ----
  enteric_ch4_head  <- calc_enteric_ch4(ge, Ym)
  enteric_ch4_total <- enteric_ch4_head * cattle_pop / 1000

  # ---- Volatile solids (Eq 10.24), inlined (scalar per-element QA warnings
  #      in calc_volatile_solids() are intentionally not raised in the MC path) ----
  VS <- (ge * (1 - DE / 100) + UE * ge) * ((1 - ASH) / 18.45)

  # ---- N excretion (Eq 10.32-10.34), inlined & vectorised ----
  DMI      <- ge / 18.45
  N_intake <- DMI * (CP / 100) / 6.25
  N_ret_milk <- ifelse(!is.na(milk_yield) & !is.na(pct_pregnant) &
                         milk_yield > 0 & pct_pregnant > 0,
                       milk_yield * pct_pregnant * milkpr_vec / 100 / 6.38, 0)
  N_ret_wg   <- ifelse(!is.na(weight_gain) & weight_gain > 0,
                       weight_gain * 0.032, 0)
  Nex <- pmax(0, (N_intake - (N_ret_milk + N_ret_wg)) * 365)

  # ---- Manure CH4 + manure-management N2O: sum over MMS TYPES ----
  # The iterated MMS set mirrors the scalar engine, which loops names(mms_i):
  # the allocation's names when there is no per-iteration allocation matrix,
  # else that matrix's columns.
  mms_keys <- if (is.null(mms_fraction_samples)) names(mms_fractions)
              else colnames(mms_fraction_samples)
  manure_ch4_head      <- numeric(n)
  direct_n2o_mm_head   <- numeric(n)
  indirect_n2o_mm_head <- numeric(n)
  for (key in mms_keys) {
    frac_k <- .mms_vec(mms_fraction_samples, mms_fractions, key)
    mcf_k  <- .mms_vec(mcf_samples,          mcf_values,    key)
    manure_ch4_head <- manure_ch4_head + VS * 365 * Bo * 0.67 * mcf_k * frac_k
    if (identical(as.character(key), "pasture")) next  # PRP handled separately
    ef3_k <- .mms_vec(ef3_samples, ef3_values, key)
    fg_k  <- .frac_gl_vec(frac_gas_samples,   frac_gas_values,   key, "frac_gas",   Frac_GASMS)
    fl_k  <- .frac_gl_vec(frac_leach_samples, frac_leach_values, key, "frac_leach", Frac_LEACH_H)
    direct_n2o_mm_head   <- direct_n2o_mm_head + Nex * frac_k * ef3_k * (44 / 28)
    indirect_n2o_mm_head <- indirect_n2o_mm_head +
      Nex * frac_k * fg_k * EF4 * (44 / 28) +
      Nex * frac_k * fl_k * EF5 * (44 / 28)
  }

  # ---- Pasture / range / paddock (PRP) N2O (Vol.4 Ch.11) ----
  # pct_pasture = per-iteration "pasture" allocation fraction (0 when absent),
  # matching the scalar ifelse("pasture" %in% names(mms_i), mms_i["pasture"], 0).
  pct_pasture_vec <- if ("pasture" %in% mms_keys)
    .mms_vec(mms_fraction_samples, mms_fractions, "pasture") else numeric(n)
  direct_n2o_prp_head   <- calc_direct_n2o_prp(Nex, pct_pasture_vec, EF3_PRP)
  indirect_n2o_prp_head <- calc_indirect_n2o_prp(
    Nex, pct_pasture_vec,
    Frac_GASM_PRP  = prp_fg_vec, EF4 = EF4,
    Frac_LEACH_PRP = prp_fl_vec, EF5 = EF5)

  # ---- Totals (t/yr) and CO2e ----
  manure_ch4_total       <- manure_ch4_head * cattle_pop / 1000
  direct_n2o_mm_total    <- direct_n2o_mm_head * cattle_pop / 1000
  indirect_n2o_mm_total  <- indirect_n2o_mm_head * cattle_pop / 1000
  direct_n2o_prp_total   <- direct_n2o_prp_head * cattle_pop / 1000
  indirect_n2o_prp_total <- indirect_n2o_prp_head * cattle_pop / 1000

  total_ch4 <- enteric_ch4_total + manure_ch4_total
  total_n2o <- direct_n2o_mm_total + indirect_n2o_mm_total +
               direct_n2o_prp_total + indirect_n2o_prp_total

  gwp_vals   <- GWP_VALUES[[gwp]]
  total_co2e <- total_ch4 * gwp_vals$CH4 + total_n2o * gwp_vals$N2O

  data.frame(
    enteric_ch4_total      = enteric_ch4_total,
    manure_ch4_total       = manure_ch4_total,
    direct_n2o_mm_total    = direct_n2o_mm_total,
    indirect_n2o_mm_total  = indirect_n2o_mm_total,
    direct_n2o_prp_total   = direct_n2o_prp_total,
    indirect_n2o_prp_total = indirect_n2o_prp_total,
    total_ch4              = total_ch4,
    total_n2o              = total_n2o,
    total_co2e             = total_co2e
  )
}
