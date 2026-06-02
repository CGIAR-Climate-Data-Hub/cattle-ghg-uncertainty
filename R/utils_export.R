# Export Functions - IPCC Table 3.3 and Excel Reports

format_ipcc_table <- function(uncertainty_decomposition, country = "", year = "") {
  combined <- uncertainty_decomposition$combined
  ad_only <- uncertainty_decomposition$ad_only
  ef_only <- uncertainty_decomposition$ef_only

  # IPCC 2006 Vol 1 Ch 3 Table 3.3 defines "% uncertainty" as the half-width of
  # the 95% confidence interval divided by the mean — i.e. moe_pct, not cv_pct.
  #
  # Andreas 2026-05-21 follow-up: the variable names produced by
  # calc_all_uncertainty() reflect the column names of the input frame, and
  # there are TWO conventions in use:
  #   - per-system results (s$results): `enteric_ch4_total`, `manure_ch4_total`,
  #     `direct_n2o_mm_total`, ... (the suffix convention)
  #   - aggregated inventory (run_inventory_simulation()$inventory):
  #     `total_enteric_ch4`, `total_manure_ch4`, `total_direct_n2o_mm`, ...
  #     (the prefix convention)
  # The legacy decompose_uncertainty() path (mc_uncertainty.R) fed the per-system
  # frame, so historical IPCC tables matched the suffix convention. The current
  # app_server.R Stage-4 path (R/app_server.R L1336-1337) feeds the aggregated
  # inventory frame instead, which uses the prefix convention. Without this
  # lookup helper, six of the nine IPCC rows silently come back NA because the
  # variable names don't match. The pair below maps both conventions to a
  # single canonical (suffix) lookup so the table populates regardless of which
  # caller built the uncertainty frame.
  alt_name <- function(var) {
    # Map the suffix-style canonical name to its prefix-style sibling:
    #   "enteric_ch4_total"   <-> "total_enteric_ch4"
    #   "direct_n2o_mm_total" <-> "total_direct_n2o_mm"
    # "total_ch4" / "total_n2o" / "total_co2e" are the same in both
    # conventions and are returned unchanged.
    if (!endsWith(var, "_total")) return(var)
    paste0("total_", sub("_total$", "", var))
  }
  get_moe <- function(df, var) {
    row <- df[df$variable == var, , drop = FALSE]
    if (nrow(row) == 0L) row <- df[df$variable == alt_name(var), , drop = FALSE]
    if (nrow(row) == 0L) return(NA_real_)
    round(row$moe_pct, 1)
  }
  # Andreas 2026-06-02 review: also expose the asymmetric half-widths so users
  # can read +upper% / -lower% for the combined run alongside the symmetric MoE.
  get_asym <- function(df, var, side) {
    row <- df[df$variable == var, , drop = FALSE]
    if (nrow(row) == 0L) row <- df[df$variable == alt_name(var), , drop = FALSE]
    if (nrow(row) == 0L) return(NA_real_)
    col <- if (side == "upper") "upper_pct" else "lower_pct"
    if (!col %in% names(row)) return(NA_real_)
    round(row[[col]], 1)
  }

  # Andreas 2026-05 #36, C10: pasture direct + indirect must appear as
  # separate IPCC reporting lines, not collapsed into "total N2O".
  vars <- c("enteric_ch4_total", "manure_ch4_total",
            "direct_n2o_mm_total", "indirect_n2o_mm_total",
            "direct_n2o_prp_total", "indirect_n2o_prp_total",
            "total_ch4", "total_n2o", "total_co2e")

  data.frame(
    `Emission category` = c(
      "3.A.1 Enteric Fermentation — Cattle",
      "3.A.2 Manure Management — Cattle (CH₄)",
      "3.A.2 Manure Management — Cattle (N₂O direct)",
      "3.A.2 Manure Management — Cattle (N₂O indirect)",
      "3.C.4 Direct N₂O — Pasture/Range/Paddock",
      "3.C.5 Indirect N₂O — Pasture/Range/Paddock",
      "Total CH₄", "Total N₂O", "Total CO₂eq"
    ),
    Gas = c("CH₄", "CH₄", "N₂O", "N₂O", "N₂O", "N₂O", "CH₄", "N₂O", "CO₂eq"),
    # Andreas 28/5/26 #6: column labels now explicitly state "95% MoE %" so
    # users do not mistake them for CV. Per IPCC Vol.1 Ch.3 Table 3.3, "%
    # uncertainty" IS the 95% MoE (half-width of the 95% CI / mean).
    `AD uncertainty (95% MoE %)`       = sapply(vars, function(v) get_moe(ad_only, v)),
    `EF uncertainty (95% MoE %)`       = sapply(vars, function(v) get_moe(ef_only, v)),
    `Combined uncertainty (95% MoE %)` = sapply(vars, function(v) get_moe(combined, v)),
    # Asymmetric breakdown on the combined run — for skewed pathways the
    # +upper% and -lower% differ, which IPCC Vol.1 Ch.3 §3.7 explicitly
    # endorses reporting alongside the symmetric MoE.
    `Combined +upper (%)`              = sapply(vars, function(v) get_asym(combined, v, "upper")),
    `Combined -lower (%)`              = sapply(vars, function(v) get_asym(combined, v, "lower")),
    check.names = FALSE,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

export_results_xlsx <- function(results, uncertainty, sensitivity, ipcc_table, filepath,
                                settings = NULL) {
  # Andreas 2026-05 #38: previously crashed when ipcc_table was NULL (which
  # happens whenever AD/EF decomposition didn't run, e.g. for custom uploads
  # — see app_server.R line 982). Replace NULL/empty inputs with placeholder
  # data frames so the writer always succeeds.
  placeholder <- function(msg)
    data.frame(Note = msg, stringsAsFactors = FALSE)

  summary_df <- if (is.null(ipcc_table) || !is.data.frame(ipcc_table) || nrow(ipcc_table) == 0)
    placeholder("IPCC summary unavailable. Enable 'Run uncertainty decomposition (AD/EF/Combined)' on Tab 5 and re-run to populate this sheet.")
  else ipcc_table

  # 2026-06: drop the cv_pct column from the Uncertainty_Metrics sheet so the
  # Excel export aligns with every other user-facing surface (in-app tables,
  # Word report, IPCC Annex 7), which all report 95% MoE as the single
  # uncertainty metric. moe_pct stays; raw mean / sd / quantiles stay so
  # advanced users can still re-derive CV manually if needed.
  uncertainty_df <- if (is.null(uncertainty) || !is.data.frame(uncertainty) || nrow(uncertainty) == 0) {
    placeholder("No uncertainty metrics available. Run a Monte Carlo simulation on Tab 5 first.")
  } else {
    uncertainty[, setdiff(names(uncertainty), "cv_pct"), drop = FALSE]
  }

  src_df <- if (!is.null(sensitivity) && is.data.frame(sensitivity$src) && nrow(sensitivity$src) > 0)
    sensitivity$src
  else placeholder(if (!is.null(attr(sensitivity, "message"))) attr(sensitivity, "message")
                    else "Sensitivity (SRC) unavailable for this run.")

  prcc_df <- if (!is.null(sensitivity) && is.data.frame(sensitivity$prcc) && nrow(sensitivity$prcc) > 0)
    sensitivity$prcc
  else placeholder(if (!is.null(attr(sensitivity, "message"))) attr(sensitivity, "message")
                    else "Sensitivity (PRCC) unavailable for this run.")

  n_iter <- if (is.data.frame(results)) nrow(results) else NA_integer_

  run_settings_df <- if (!is.null(settings)) {
    data.frame(
      Setting = c("Iterations", "AD correlations", "EF correlations",
                  "Comparison run (no corr.)", "GWP basis", "Seed",
                  "Analysis mode", "Emission sources"),
      Value   = c(
        as.character(settings$n_iter %||% NA),
        as.character(settings$corr_mode %||% "none"),
        as.character(settings$ef_corr_mode %||% "none"),
        if (isTRUE(settings$run_comparison)) "yes" else "no",
        as.character(settings$gwp_version %||% NA),
        as.character(settings$seed %||% NA),
        as.character(settings$analysis_mode %||% NA),
        paste(settings$emission_sources %||% character(0), collapse = ", ")
      ),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(Note = "Settings not recorded (re-download after running a simulation).",
               stringsAsFactors = FALSE)
  }

  sheets <- list(
    Run_Settings        = run_settings_df,
    Summary             = summary_df,
    Uncertainty_Metrics = uncertainty_df,
    Sensitivity_SRC     = src_df,
    Sensitivity_PRCC    = prcc_df,
    Metadata = data.frame(
      Field = c("Generated", "Tool", "Iterations"),
      Value = c(as.character(Sys.time()),
                "IPCC Tier 2 Uncertainty Calculator v1.1",
                as.character(n_iter)),
      stringsAsFactors = FALSE
    )
  )
  writexl::write_xlsx(sheets, path = filepath)
}

# Round 8: trend export — multi-sheet Excel for the Trend tab.
# Sheets: Trend_summary (year x metrics), Slope_and_delta (per-iter MC summary),
# Sensitivity_per_year_*, Sensitivity_delta_*, Methodology.
export_trend_xlsx <- function(results_table, slope, delta_total,
                               sensitivity_per_year, sensitivity_delta,
                               year_corr, n_iter, filepath) {
  slope_delta_summary <- data.frame(
    Metric = c("Trend slope (t CO2eq / yr)",
               "Trend slope 95% CI lower",
               "Trend slope 95% CI upper",
               "Delta total (Y_N - Y_1, t CO2eq)",
               "Delta total 95% CI lower",
               "Delta total 95% CI upper",
               "Delta percent (vs Y_1)",
               "Delta percent 95% CI lower",
               "Delta percent 95% CI upper"),
    Value  = c(slope$mean, slope$ci[1], slope$ci[2],
               delta_total$mean, delta_total$ci[1], delta_total$ci[2],
               delta_total$pct_mean, delta_total$pct_ci[1], delta_total$pct_ci[2]),
    stringsAsFactors = FALSE
  )
  methodology <- data.frame(
    Field = c("Generated", "Tool", "Iterations per year",
              "Year-to-year correlation mode",
              "IPCC reference"),
    Value = c(as.character(Sys.time()),
              "IPCC Tier 2 Uncertainty Calculator — Trend",
              n_iter, year_corr,
              "IPCC 2019 Refinement Vol 1 Ch 3 §3.2.2.4 (year correlation) + §3.7 (trend reporting)"),
    stringsAsFactors = FALSE
  )

  pull_df <- function(sens, key) {
    if (is.null(sens) || is.null(sens[[key]])) return(data.frame())
    sens[[key]]
  }

  sheets <- list(
    Trend_summary    = results_table,
    Slope_and_delta  = slope_delta_summary,
    Sensitivity_per_year_SRC  = pull_df(sensitivity_per_year, "src"),
    Sensitivity_per_year_PRCC = pull_df(sensitivity_per_year, "prcc"),
    Sensitivity_delta_SRC     = pull_df(sensitivity_delta, "src"),
    Sensitivity_delta_PRCC    = pull_df(sensitivity_delta, "prcc"),
    Methodology      = methodology
  )
  writexl::write_xlsx(sheets, path = filepath)
}
