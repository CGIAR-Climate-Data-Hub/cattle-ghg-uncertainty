# Monte Carlo Simulation Runner

# Run MC simulation for one system-subsystem combination
run_mc_simulation <- function(param_specs, corr_matrix = NULL, n_iter = 10000,
                               mms_fractions = NULL, mcf_values = NULL, ef3_values = NULL,
                               gwp = "AR5", seed = NULL, ef_corr_matrix = NULL,
                               # E1, E3: optional IPCC software inputs
                               Tw = 20, pct_pregnant = 1,
                               # Round 7 R1.13: per-MMS Frac_GasMS / Frac_LeachMS
                               # named vectors. NULL = fall back to IPCC 2019
                               # defaults inside calc_indirect_n2o_mm.
                               frac_gas_values = NULL, frac_leach_values = NULL,
                               # Round 7 T4.3: unified correlation across AD + coefficients
                               unified_corr_matrix = NULL,
                               # Round 7 R1.14: pre-sampled coefficient block (trend mode)
                               pre_sampled_coefficients = NULL,
                               # Andreas 2026-05 follow-up (C4 / C6): per-MMS
                               # uncertainty matrices n_iter × n_MMS. NULL =
                               # treat the corresponding MMS values as
                               # deterministic constants (pre-fix behaviour).
                               mcf_samples = NULL, ef3_samples = NULL,
                               frac_gas_samples = NULL, frac_leach_samples = NULL,
                               # Andreas 28/5/26 #4: per-iteration MMS allocation
                               # matrix (n_iter × n_MMS, rows already renormalised
                               # to sum to 1). NULL = treat mms_fractions as a
                               # deterministic vector.
                               mms_fraction_samples = NULL,
                               # Correlated sampling uses the rank-correlation-
                               # preserving restricted-pairing procedure per IPCC
                               # Vol.1 Ch.3 §3.2.3.2. The argument is retained as a
                               # single-value match for back-compat with any caller
                               # that still passes it explicitly.
                               sampler = "iman_conover") {
  sampler <- match.arg(sampler, choices = "iman_conover")
  # Andreas 2026-05 follow-up: the Dirichlet `mms_fractions_matrix` argument
  # was removed because the Dirichlet MMS-allocation sampling it enabled is
  # not cited in IPCC 2006 / 2019 guidance. MMS% is now deterministic.
  samples <- generate_mc_samples(param_specs, corr_matrix, n_iter, seed, ef_corr_matrix,
                                  unified_corr_matrix = unified_corr_matrix,
                                  pre_sampled_coefficients = pre_sampled_coefficients,
                                  sampler = sampler)

  # Andreas 2026-05 follow-up (C4 / C6): expose per-MMS sampled values to the
  # sensitivity analysis by appending them to `samples` as e.g.
  # MCF_solid_storage, EF3_lagoon, Frac_GasMS_dry_lot, ... Each contributing
  # parameter becomes its own tornado bar instead of being invisible.
  .bind_mms_to_samples <- function(samples, mat, prefix) {
    if (is.null(mat) || ncol(mat) == 0) return(samples)
    extra <- as.data.frame(mat)
    names(extra) <- paste0(prefix, "_", colnames(mat))
    cbind(samples, extra)
  }
  samples <- .bind_mms_to_samples(samples, mcf_samples, "MCF")
  samples <- .bind_mms_to_samples(samples, ef3_samples, "EF3")
  samples <- .bind_mms_to_samples(samples, frac_gas_samples,   "Frac_GasMS")
  samples <- .bind_mms_to_samples(samples, frac_leach_samples, "Frac_LeachMS")
  samples <- .bind_mms_to_samples(samples, mms_fraction_samples, "fraction")

  get_param <- function(name, default = 0) {
    if (name %in% names(samples)) samples[[name]] else rep(default, n_iter)
  }

  if (is.null(mms_fractions)) mms_fractions <- c(pasture = 1.0)
  if (is.null(mcf_values)) mcf_values <- c(pasture = 0.015)
  if (is.null(ef3_values)) ef3_values <- c(pasture = 0.02)

  # C1: parameter names IPCC-aligned (DE, CP, Ym, ASH, Frac_GASMS, Frac_LEACH_H).
  # get_param() falls back to legacy names so old templates still work.
  get_param_alt <- function(new_name, old_name, default = 0) {
    if (new_name %in% names(samples)) samples[[new_name]]
    else if (old_name %in% names(samples)) samples[[old_name]]
    else rep(default, n_iter)
  }

  # R1.6: full IPCC variable rename — look up new IPCC names first, fall back to legacy
  results <- ghg_emissions_vec(
    cattle_pop    = get_param_alt("N",       "cattle_pop",    0),
    live_weight   = get_param_alt("BW",      "live_weight",   275),
    weight_gain   = get_param_alt("WG",      "weight_gain",   0),
    mature_weight = get_param_alt("MW",      "mature_weight", 300),
    milk_yield    = get_param_alt("Milk",    "milk_yield",    0),
    milk_fat      = get_param_alt("Fat",     "milk_fat",      4),
    hours         = get_param("hours", 0),
    DE            = get_param_alt("DE",      "DE_pct",        55),
    Cfi           = get_param("Cfi", 0.322),
    Ca            = get_param("Ca", 0.17),
    C_growth      = get_param_alt("C",       "C_growth",      0.8),
    Cp            = get_param("Cp", 0.10),
    Ym            = get_param_alt("Ym",      "Ym_pct",        6.5),
    Bo            = get_param("Bo", 0.10),
    ASH           = get_param_alt("ASH",     "ash",           0.08),
    UE            = get_param("UE", 0.04),
    CP            = get_param_alt("CP",      "CP_pct",        10),
    mms_fractions = mms_fractions,
    mcf_values    = mcf_values,
    ef3_values    = ef3_values,
    # IPCC alignment audit (2026-05): defaults updated to the 2019 Refinement
    # aggregated values from Vol.4 Ch.11 Tables 11.1 and 11.3:
    #   EF3_PRP,CPP   = 0.004 (aggregated; wet = 0.006, dry = 0.002)
    #   FracGASM      = 0.21  (2019R; 2006 = 0.20)
    #   EF4           = 0.010 (aggregated; wet = 0.014, dry = 0.005;
    #                          coincides with the 2006 single value)
    #   EF5           = 0.011 (2019R; 2006 = 0.0075)
    #   FracLEACH-(H) = 0.02  on the MS side (Vol.4 Ch.10 Table 10.23)
    # 2006 values (0.02 / 0.20 / 0.010 / 0.0075) remain valid for inventories
    # that explicitly target the 2006 Guidelines — supply them via the
    # template instead of relying on these fallbacks.
    EF3_PRP       = get_param("EF3_PRP", 0.004),
    Frac_GASMS    = get_param_alt("Frac_GASMS",   "Frac_GASM",  0.21),
    EF4           = get_param("EF4", 0.010),
    EF5           = get_param("EF5", 0.011),
    Frac_LEACH_H  = get_param_alt("Frac_LEACH_H", "Frac_LEACH", 0.02),
    # Andreas 2026-05 #10: PRP-side fractions, distinct from MM (Table 11.3).
    # Falls back to IPCC 2019 Table 11.3 defaults when the template does not
    # provide them (most existing templates won't yet).
    Frac_GASM_PRP  = get_param("Frac_GASM_PRP",  0.21),
    # IPCC 2019R Vol.4 Ch.11 Table 11.3: Frac_LEACH-(H) = 0.24 (wet climate);
    # dry-climate default is 0. 2006 default was 0.30. Aligned with the
    # function default in calc_indirect_n2o_prp and the IPCC_DEFAULTS comment
    # in utils_ipcc_defaults.R; runs targeting 2006 must supply the value
    # via the Parameters template.
    Frac_LEACH_PRP = get_param("Frac_LEACH_PRP", 0.24),
    # Andreas 2026-05 follow-up: MilkPR (milk protein %) is now passed through
    # from samples instead of being hardcoded in calc_n_excretion. Catalogue
    # default is 3.3 (IPCC 2006 Table 10.11 African-dairy mid-point).
    MilkPR         = get_param_alt("MilkPR", "protein_milk", 3.3),
    gwp = gwp,
    # Andreas 2026-05 follow-up: Tw (mean winter temperature for the IPCC
    # Vol.4 Ch.10 Eq 10.2 cold-climate Cfi adjustment, which modifies the
    # Cfi from Eq 10.3) is now sourced exclusively from
    # the Parameters template via the sampled values. Default 20°C makes
    # the adjustment inert (matches the IPCC formula's neutral baseline).
    # The old global Tw argument was retained as a fallback only.
    Tw          = get_param("Tw", 20),
    pct_pregnant = get_param("pct_pregnant", pct_pregnant),
    frac_gas_values   = frac_gas_values,
    frac_leach_values = frac_leach_values,
    # Andreas 2026-05 follow-up (C4 / C6): per-iteration per-MMS matrices
    # from the manure-sheet uncertainty columns. NULL = use the named scalar
    # mms-keyed vectors above (pre-fix deterministic behaviour).
    mcf_samples        = mcf_samples,
    ef3_samples        = ef3_samples,
    frac_gas_samples   = frac_gas_samples,
    frac_leach_samples = frac_leach_samples,
    # Andreas 28/5/26 #4: per-iteration MMS allocation matrix.
    mms_fraction_samples = mms_fraction_samples
  )

  list(samples = samples, results = results)
}

# Run simulation across multiple systems/subsystems
run_inventory_simulation <- function(systems_data, n_iter = 10000, gwp = "AR5",
                                      seed = NULL, Tw = 20, pct_pregnant = 1,
                                      # Correlated sampling uses the rank-
                                      # correlation-preserving procedure per IPCC
                                      # Vol.1 Ch.3 §3.2.3.2. Kept as an argument
                                      # for back-compat with callers that still
                                      # pass it; the only accepted value is
                                      # "iman_conover".
                                      sampler = "iman_conover",
                                      # Optional progress callback, invoked once
                                      # per system as progress_cb(done, total).
                                      # Default NULL = no-op (audit / headless
                                      # callers). The Shiny observer wires this
                                      # to incProgress() so the websocket keeps
                                      # receiving traffic during a multi-minute
                                      # run on a large inventory — without it the
                                      # blocking loop goes silent and shinyapps.io
                                      # drops the connection (~180 s idle), which
                                      # is the "timed out after a few minutes"
                                      # failure on the 32-sub-category Zambia run.
                                      progress_cb = NULL) {
  sampler <- match.arg(sampler, choices = "iman_conover")
  by_system <- list()
  n_sys <- length(systems_data)

  for (sys_name in names(systems_data)) {
    sys <- systems_data[[sys_name]]
    sim <- run_mc_simulation(
      param_specs     = sys$param_specs,
      corr_matrix     = sys$corr_matrix,
      n_iter          = n_iter,
      mms_fractions   = sys$mms_fractions,
      mcf_values      = sys$mcf_values,
      ef3_values      = sys$ef3_values,
      gwp             = gwp,
      seed            = if (!is.null(seed)) seed + which(names(systems_data) == sys_name) else NULL,
      ef_corr_matrix  = sys$ef_corr_matrix,
      Tw              = if (!is.null(sys$Tw)) sys$Tw else Tw,
      pct_pregnant     = if (!is.null(sys$pct_pregnant)) sys$pct_pregnant else pct_pregnant,
      frac_gas_values   = sys$frac_gas_values,
      frac_leach_values = sys$frac_leach_values,
      unified_corr_matrix      = sys$unified_corr_matrix,
      pre_sampled_coefficients = sys$pre_sampled_coefficients,
      mcf_samples              = sys$mcf_samples,
      ef3_samples              = sys$ef3_samples,
      frac_gas_samples         = sys$frac_gas_samples,
      frac_leach_samples       = sys$frac_leach_samples,
      mms_fraction_samples     = sys$mms_fraction_samples,
      sampler                  = sampler
    )
    by_system[[sys_name]] <- sim
    # Keep-alive heartbeat (no-op when progress_cb is NULL).
    if (is.function(progress_cb)) {
      tryCatch(progress_cb(length(by_system), n_sys), error = function(e) NULL)
    }
  }

  # Andreas 2026-05 #33: harden against an empty by_system (or one whose
  # per-iteration result frame has zero rows — which produces the cryptic
  # "replacement has 0 rows, data has 5000" error when downstream code
  # assigns to a pre-allocated column). Bail out with a descriptive error
  # before the rowSums(sapply(...)) call instead.
  if (length(by_system) == 0L) {
    stop("run_inventory_simulation: no systems were simulated. Check that ",
         "Parameters has at least one cattle_type+aggregation_level+sub_category ",
         "group with a non-zero population.")
  }
  row_counts <- vapply(by_system, function(s) nrow(s$results), integer(1))
  if (any(row_counts != n_iter)) {
    stop("run_inventory_simulation: at least one system returned ",
         row_counts[row_counts != n_iter][1], " iterations instead of the ",
         "expected ", n_iter, ". This usually means a sampled parameter ",
         "collapsed to length 0 — re-upload the template after checking ",
         "that every Parameters row has a numeric `mean`.")
  }

  # Sum across systems per iteration. Per-source columns kept *separately* for
  # MM and PRP (Andreas 2026-05 #27, C1 value-boxes) — totals retained for
  # back-compat with consumers that still expect total_direct_n2o /
  # total_indirect_n2o.
  inventory_results <- data.frame(
    total_enteric_ch4    = rowSums(sapply(by_system, function(s) s$results$enteric_ch4_total)),
    total_manure_ch4     = rowSums(sapply(by_system, function(s) s$results$manure_ch4_total)),
    total_direct_n2o_mm  = rowSums(sapply(by_system, function(s) s$results$direct_n2o_mm_total)),
    total_indirect_n2o_mm = rowSums(sapply(by_system, function(s) s$results$indirect_n2o_mm_total)),
    total_direct_n2o_prp  = rowSums(sapply(by_system, function(s) s$results$direct_n2o_prp_total)),
    total_indirect_n2o_prp = rowSums(sapply(by_system, function(s) s$results$indirect_n2o_prp_total)),
    total_direct_n2o     = rowSums(sapply(by_system, function(s) s$results$direct_n2o_mm_total + s$results$direct_n2o_prp_total)),
    total_indirect_n2o   = rowSums(sapply(by_system, function(s) s$results$indirect_n2o_mm_total + s$results$indirect_n2o_prp_total)),
    total_ch4  = rowSums(sapply(by_system, function(s) s$results$total_ch4)),
    total_n2o  = rowSums(sapply(by_system, function(s) s$results$total_n2o)),
    total_co2e = rowSums(sapply(by_system, function(s) s$results$total_co2e))
  )

  list(by_system = by_system, inventory = inventory_results)
}
