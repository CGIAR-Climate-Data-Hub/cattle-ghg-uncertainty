# Uncertainty Metric Calculations

calc_uncertainty_metrics <- function(x) {
  m  <- mean(x)
  q025 <- quantile(x, 0.025, names = FALSE)
  q975 <- quantile(x, 0.975, names = FALSE)
  # Guard: CV and MOE are undefined when the mean is zero (e.g. a source that is
  # structurally zero for this sub-category). Return NA rather than NaN/Inf so
  # downstream formatters can handle it gracefully.
  cv_pct  <- if (isTRUE(m != 0)) sd(x) / m * 100 else NA_real_
  moe_pct <- if (isTRUE(m != 0)) ((q975 - q025) / 2) / m * 100 else NA_real_
  # Andreas 2026-06-02 review: asymmetric half-widths reported alongside the
  # symmetric MoE so users can see the +upper% / -lower% breakdown when the
  # emission distribution is skewed (lognormal EFs, PERT-bounded fractions,
  # manure-N2O sums). For a perfectly symmetric distribution these equal MoE.
  upper_pct <- if (isTRUE(m != 0)) (q975 - m) / m * 100 else NA_real_
  lower_pct <- if (isTRUE(m != 0)) (m - q025) / m * 100 else NA_real_
  data.frame(
    mean = m, median = median(x), sd = sd(x),
    cv_pct  = cv_pct,
    ci_lower = q025,
    ci_upper = q975,
    # T6.1 / T8.1: IPCC 95% margin of error — half-width of the 95% CI as a
    # percent of the mean. Quantile-based so it handles asymmetric distributions.
    # (Previous formula was 1.96*sd/sqrt(n)/mean — that is the standard error
    # of the *estimator*, not the uncertainty of the emission value.)
    moe_pct = moe_pct,
    upper_pct = upper_pct,
    lower_pct = lower_pct,
    iqr = IQR(x), min = min(x), max = max(x)
  )
}

calc_all_uncertainty <- function(results_df) {
  metrics <- lapply(names(results_df), function(col) {
    m <- calc_uncertainty_metrics(results_df[[col]])
    m$variable <- col
    m
  })
  do.call(rbind, metrics)
}

# Uncertainty decomposition: AD-only, EF-only, Combined.
# Andreas 2026-05 #29: defensive coercion of param_type — custom uploads can
# arrive with NA in param_type when the user didn't fill that column. Treat
# missing as "coefficient" (the IPCC convention adopted in this tool — only
# N is activity data). NA in a logical subset triggers "NAs not allowed in
# subscripted assignments", which manifested as the silent decomposition
# failure on custom data Andreas reported.
#
# DEPRECATION NOTE (2026-05-18): The Shiny app no longer calls this function
# for the main decomposition path. Stage 4 of the simulation observer in
# app_server.R uses fix_params() + run_inventory_simulation() directly, which
# (a) supports multi-group inventories and (b) correctly passes per-MMS
# uncertainty matrices (mcf_samples, ef3_samples, frac_gas_samples,
# frac_leach_samples). This function is retained for direct/test use but will
# not reflect per-MMS sampling — call the app_server.R path instead for
# production results.
decompose_uncertainty <- function(param_specs, corr_matrix = NULL, n_iter = 10000,
                                   mms_fractions = NULL, mcf_values = NULL, ef3_values = NULL,
                                   gwp = "AR5", seed = NULL, ef_corr_matrix = NULL) {
  if (is.null(param_specs) || nrow(param_specs) == 0) {
    stop("decompose_uncertainty: param_specs is empty.")
  }
  if (!"param_type" %in% names(param_specs)) {
    param_specs$param_type <- ifelse(
      param_specs$parameter %in% c("N", "cattle_pop"),
      "activity_data", "coefficient")
  }
  param_specs$param_type[is.na(param_specs$param_type)] <- "coefficient"

  # Combined
  combined <- run_mc_simulation(param_specs, corr_matrix, n_iter,
                                 mms_fractions, mcf_values, ef3_values, gwp, seed,
                                 ef_corr_matrix = ef_corr_matrix)

  # AD only: fix emission factors at means
  ad_specs <- param_specs
  ef_rows <- ad_specs$param_type == "coefficient"
  ad_specs$distribution[ef_rows] <- "constant"
  ad_specs$lower[ef_rows] <- ad_specs$mean[ef_rows]
  ad_specs$upper[ef_rows] <- ad_specs$mean[ef_rows]
  ad_only <- run_mc_simulation(ad_specs, corr_matrix, n_iter,
                                mms_fractions, mcf_values, ef3_values, gwp, seed,
                                ef_corr_matrix = NULL)

  # EF only: fix activity data at means
  ef_specs <- param_specs
  ad_rows <- ef_specs$param_type == "activity_data"
  ef_specs$distribution[ad_rows] <- "constant"
  ef_specs$lower[ad_rows] <- ef_specs$mean[ad_rows]
  ef_specs$upper[ad_rows] <- ef_specs$mean[ad_rows]
  ef_only <- run_mc_simulation(ef_specs, NULL, n_iter,
                                mms_fractions, mcf_values, ef3_values, gwp, seed,
                                ef_corr_matrix = ef_corr_matrix)

  list(
    combined = calc_all_uncertainty(combined$results),
    ad_only = calc_all_uncertainty(ad_only$results),
    ef_only = calc_all_uncertainty(ef_only$results),
    combined_raw = combined,
    ad_raw = ad_only,
    ef_raw = ef_only
  )
}
