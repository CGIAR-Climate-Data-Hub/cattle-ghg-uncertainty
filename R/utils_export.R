# Export Functions - IPCC Table 3.3 and Excel Reports

format_ipcc_table <- function(uncertainty_decomposition, country = "", year = "") {
  combined <- uncertainty_decomposition$combined
  ad_only <- uncertainty_decomposition$ad_only
  ef_only <- uncertainty_decomposition$ef_only

  # IPCC 2006 Vol 1 Ch 3 Table 3.3 defines "% uncertainty" as the half-width of
  # the 95% confidence interval divided by the mean: i.e. moe_pct, not cv_pct.
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
      "3.A.1 Enteric Fermentation: Cattle",
      "3.B.1 Manure Management: Cattle (CH₄)",
      "3.B.1 Manure Management: Cattle (N₂O direct)",
      "3.B.5 Manure Management: Cattle (N₂O indirect)",
      "3.D.1.c Direct N₂O: Pasture/Range/Paddock",
      "3.D.2 Indirect N₂O: Pasture/Range/Paddock",
      "Total CH₄", "Total N₂O", "Total CO₂eq"
    ),
    Gas = c("CH₄", "CH₄", "N₂O", "N₂O", "N₂O", "N₂O", "CH₄", "N₂O", "CO₂eq"),
    # Andreas 28/5/26 #6: column labels now explicitly state "95% MoE %" so
    # users do not mistake them for CV. Per IPCC Vol.1 Ch.3 Table 3.3, "%
    # uncertainty" IS the 95% MoE (half-width of the 95% CI / mean).
    `AD uncertainty (95% MoE %)`       = sapply(vars, function(v) get_moe(ad_only, v)),
    `EF uncertainty (95% MoE %)`       = sapply(vars, function(v) get_moe(ef_only, v)),
    `Combined uncertainty (95% MoE %)` = sapply(vars, function(v) get_moe(combined, v)),
    # Asymmetric breakdown on the combined run: for skewed pathways the
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
                                settings = NULL, param_specs = NULL,
                                qa_caveats = NULL, manure = NULL) {
  # Andreas 2026-05 #38: previously crashed when ipcc_table was NULL (which
  # happens whenever AD/EF decomposition didn't run, e.g. for custom uploads
  #: see app_server.R line 982). Replace NULL/empty inputs with placeholder
  # data frames so the writer always succeeds.
  placeholder <- function(msg)
    data.frame(Note = msg, stringsAsFactors = FALSE)

  # 2026-11-02 (Lolita): one Results sheet in place of Summary (the IPCC
  # table) and Uncertainty_Metrics, which carried the same numbers (the
  # IPCC table's "Combined" column is the main run's uncertainty). One row
  # per IPCC reporting line: mean, 95% CI, MoE and its asymmetric halves,
  # then the AD and EF split when the decomposition ran. The placeholder
  # column is gone: Input_Parameters marks each placeholder range.
  results_df <- .results_sheet(uncertainty, ipcc_table)

  src_df <- if (!is.null(sensitivity) && is.data.frame(sensitivity$src) && nrow(sensitivity$src) > 0)
    sensitivity$src
  else placeholder(if (!is.null(attr(sensitivity, "message"))) attr(sensitivity, "message")
                    else "Sensitivity (SRC) unavailable for this run.")

  n_iter <- if (is.data.frame(results)) nrow(results) else NA_integer_

  run_settings_df <- if (!is.null(settings)) {
    data.frame(
      Setting = c("Iterations", "AD correlations",
                  "Animal numbers between groups", "Animal numbers between years (trend)",
                  "Comparison run (no corr.)", "GWP basis", "Seed",
                  "Analysis mode", "Emission sources",
                  # (2026-11-02: the "Intake route" row removed at Lolita's
                  # request; the results table in the app still shows it.)
                  "QA/QC checks ignored or repaired"),
      Value   = c(
        as.character(settings$n_iter %||% NA),
        as.character(settings$corr_mode %||% "none"),
        .n_corr_label(settings$n_group_corr %||% "full", "group"),
        .n_corr_label(settings$n_year_corr %||% "none", "year"),
        if (isTRUE(settings$run_comparison)) "yes" else "no",
        as.character(settings$gwp_version %||% NA),
        as.character(settings$seed %||% NA),
        as.character(settings$analysis_mode %||% NA),
        paste(settings$emission_sources %||% character(0), collapse = ", "),
        if (is.null(qa_caveats) || nrow(qa_caveats) == 0) "none"
        else paste0(nrow(qa_caveats), " (see sheet QA_Caveats)")
      ),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(Note = "Settings not recorded (re-download after running a simulation).",
               stringsAsFactors = FALSE)
  }

  # Full per-parameter input audit trail. This is the complete listing that the
  # Word report's section 13 table is capped against (officer print.rdocx is too
  # slow on the full 500+ row table for a large inventory): Excel handles it
  # instantly, so the exhaustive audit lives here.
  inputs_df <- if (!is.null(param_specs) && is.data.frame(param_specs) && nrow(param_specs) > 0) {
    x <- param_specs
    # 2026-10-30: where each range came from; placeholders are marked
    x$range_source <- tryCatch(range_source_label(param_specs), error = function(e) NA_character_)
    x
  } else placeholder("Input parameters unavailable. Run a Monte Carlo simulation on Tab 5 first.")

  # 2026-09-18: QA/QC failures the user ignored, and repairs applied so the
  # run could proceed. Reviewers must see these next to the numbers.
  caveats_df <- if (!is.null(qa_caveats) && is.data.frame(qa_caveats) && nrow(qa_caveats) > 0)
    qa_caveats
  else placeholder("No QA/QC checks were ignored or repaired for this run.")

  # 2026-10-15: the declared-basis table is withheld from the app and
  # its outputs for now, on request. Nothing that builds it was removed:
  # basis_tool_wide(), basis_dimension_label() and basis_plain_table()
  # are intact, the translator prompt still carries the table, and the
  # full record stays in defaults/DEFAULTS_MASTER.md. Restoring the
  # display means putting these call sites back.

  # 2026-11-02 (Lolita): the Metadata sheet is gone (the iterations are in
  # Run_Settings); a README sheet first says what every sheet holds.
  has_decomp <- "AD uncertainty, MoE 95% (%)" %in% names(results_df)
  readme_df <- data.frame(
    Sheet = c("", "README", "Run_Settings", "QA_Caveats", "Results", "Sensitivity_SRC", "Input_Parameters"),
    Contents = c(
      sprintf("Cattle GHG uncertainty calculator, version %s. Generated %s. Single-year Monte Carlo results, %s iterations.",
              .app_version(), format(Sys.time(), "%Y-%m-%d %H:%M"), format(n_iter, big.mark = ",")),
      "This sheet: what each sheet of the workbook contains.",
      "The settings of the run: iterations, correlation choices (Tab 3), GWP basis, seed, emission sources, and how many QA/QC checks were ignored or repaired.",
      "The QA/QC checks that were ignored or repaired so the run could go ahead. Empty when there were none.",
      paste0("One row per IPCC reporting line (Table 3.3): mean emissions in tonnes of the gas, the 95% confidence interval (CI), ",
             "the 95% margin of error (MoE, half the width of the CI as a percentage of the mean) and its lower and upper halves",
             if (has_decomp) ", then the uncertainty from the activity data (AD) alone and from the emission factors and coefficients (EF) alone."
             else ". The AD and EF split appears when 'Run uncertainty decomposition' is ticked on Tab 4."),
      "The sensitivity analysis of total CO2eq: one row per input, its standardised regression coefficient (src, from -1 to +1; the further from zero, the more the input matters), its absolute value, p_value, rank, and the animal groups that use it.",
      "Every input of the run: group, parameter, mean, distribution, bounds, and range_source, which says where each uncertainty range comes from and marks the placeholder ranges (no published source)."),
    stringsAsFactors = FALSE)

  sheets <- list(
    README           = readme_df,
    Run_Settings     = run_settings_df,
    QA_Caveats       = caveats_df,
    Results          = results_df,
    Sensitivity_SRC  = src_df,
    Input_Parameters = inputs_df
  )
  writexl::write_xlsx(sheets, path = filepath)
}

# 2026-11-02: the app version for the README sheet (VERSION file at the app root).
.app_version <- function() {
  v <- tryCatch(trimws(readLines("VERSION", n = 1L, warn = FALSE)), error = function(e) "")
  if (length(v) == 1L && nzchar(v)) v else "unknown"
}

# 2026-11-02: the Results sheet: one row per IPCC reporting line from the
# main run's uncertainty (mean, CI, MoE, halves), and the AD / EF columns
# of the IPCC table when the decomposition ran.
.results_sheet <- function(uncertainty, ipcc_table = NULL) {
  if (is.null(uncertainty) || !is.data.frame(uncertainty) || nrow(uncertainty) == 0)
    return(data.frame(Note = "No results available. Run a Monte Carlo simulation on Tab 4 first.",
                      stringsAsFactors = FALSE))
  lines <- data.frame(
    var = c("total_enteric_ch4", "total_manure_ch4", "total_direct_n2o_mm", "total_indirect_n2o_mm",
            "total_direct_n2o_prp", "total_indirect_n2o_prp", "total_ch4", "total_n2o", "total_co2e"),
    alt = c("enteric_ch4_total", "manure_ch4_total", "direct_n2o_mm_total", "indirect_n2o_mm_total",
            "direct_n2o_prp_total", "indirect_n2o_prp_total", "total_ch4", "total_n2o", "total_co2e"),
    category = c("3.A.1 Enteric Fermentation: Cattle",
                 "3.B.1 Manure Management: Cattle (CH\u2084)",
                 "3.B.1 Manure Management: Cattle (N\u2082O direct)",
                 "3.B.5 Manure Management: Cattle (N\u2082O indirect)",
                 "3.D.1.c Direct N\u2082O: Pasture/Range/Paddock",
                 "3.D.2 Indirect N\u2082O: Pasture/Range/Paddock",
                 "Total CH\u2084", "Total N\u2082O", "Total CO\u2082eq"),
    gas = c("CH\u2084", "CH\u2084", "N\u2082O", "N\u2082O", "N\u2082O", "N\u2082O", "CH\u2084", "N\u2082O", "CO\u2082eq"),
    stringsAsFactors = FALSE)
  pick <- function(v, a, col) {
    row <- uncertainty[uncertainty$variable %in% c(v, a), , drop = FALSE]
    if (nrow(row) == 0L || !col %in% names(row)) NA_real_ else row[[col]][1]
  }
  get <- function(col, digits) vapply(seq_len(nrow(lines)), function(i)
    round(pick(lines$var[i], lines$alt[i], col), digits), numeric(1))
  out <- data.frame(
    `Emission category` = lines$category,
    Gas = lines$gas,
    `Mean emissions (t of the gas)` = get("mean", 2),
    `95% CI lower (t)` = get("ci_lower", 2),
    `95% CI upper (t)` = get("ci_upper", 2),
    `MoE 95% (%)` = get("moe_pct", 1),
    `Lower half of the CI (-%)` = get("lower_pct", 1),
    `Upper half of the CI (+%)` = get("upper_pct", 1),
    check.names = FALSE, stringsAsFactors = FALSE)
  if (is.data.frame(ipcc_table) && nrow(ipcc_table) == nrow(out) &&
      all(c("AD uncertainty (95% MoE %)", "EF uncertainty (95% MoE %)") %in% names(ipcc_table))) {
    out[["AD uncertainty, MoE 95% (%)"]] <- ipcc_table[["AD uncertainty (95% MoE %)"]]
    out[["EF uncertainty, MoE 95% (%)"]] <- ipcc_table[["EF uncertainty (95% MoE %)"]]
  }
  out
}

# Round 8: trend export, multi-sheet Excel for the Trend tab.
# Sheets: Trend_summary (year x metrics), Slope_and_delta (per-iter MC summary),
# Sensitivity_per_year_*, Sensitivity_delta_*, Methodology.
export_trend_xlsx <- function(results_table, slope, delta_total,
                               sensitivity_per_year, sensitivity_delta,
                               year_corr, n_iter, filepath,
                               # 2026-10-22: what to report (base year and
                               # year t), IPCC Table 3.3, the two years by
                               # source, every year by source and by group
                               headline = NULL, ipcc_table = NULL, compare = NULL,
                               sources_long = NULL, by_group = NULL) {
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
              "IPCC Tier 2 Uncertainty Calculator: Trend",
              n_iter, year_corr,
              "IPCC 2019 Refinement Vol 1 Ch 3 §3.2.2.4 (year correlation) + §3.7 (trend reporting)"),
    stringsAsFactors = FALSE
  )

  pull_df <- function(sens, key) {
    if (is.null(sens) || is.null(sens[[key]])) return(data.frame())
    sens[[key]]
  }

  report_sheets <- list()
  if (!is.null(headline)) {
    h <- headline
    report_sheets$What_to_report <- data.frame(
      Item = c("Base year", "Base year total (t CO2eq)", "Base year uncertainty (+/- % of mean)",
               "Base year 95% range lower (t)", "Base year 95% range upper (t)",
               "Year t", "Year t total (t CO2eq)", "Year t uncertainty (+/- % of mean)",
               "Year t 95% range lower (t)", "Year t 95% range upper (t)",
               "Change from base year to year t (%)",
               "Change, 95% range lower (%)", "Change, 95% range upper (%)",
               "Uncertainty in the trend (-) percentage points",
               "Uncertainty in the trend (+) percentage points",
               "95% range of the change includes zero",
               "Year-to-year correlation of coefficients",
               "Draws for base year and year t", "Draws per year in the series"),
      Value = c(h$base_year, round(h$base_mean, 1), round(h$base_moe, 1),
                round(h$base_lo, 1), round(h$base_hi, 1),
                h$year_t, round(h$t_mean, 1), round(h$t_moe, 1),
                round(h$t_lo, 1), round(h$t_hi, 1),
                round(h$trend_pct, 1), round(h$trend_lo_pct, 1), round(h$trend_hi_pct, 1),
                round(h$trend_lo_pp, 1), round(h$trend_hi_pp, 1),
                if (isTRUE(h$zero_inside)) "yes" else "no", h$year_corr,
                if (is.null(h$n_iter_pair)) n_iter else h$n_iter_pair, n_iter),
      stringsAsFactors = FALSE)
  }
  if (!is.null(ipcc_table)) report_sheets$IPCC_Table_3_3 <- ipcc_table
  if (!is.null(compare)) {
    cmp <- compare
    report_sheets$Two_years_by_source <- data.frame(
      `Emission source` = cmp$category, Gas = cmp$gas,
      `Base year mean (t CO2eq)` = round(cmp$base_mean, 1),
      `Base year +/- %` = round(cmp$base_moe_pct, 1),
      `Base year (-) %` = round(cmp$base_lower_pct, 1),
      `Base year (+) %` = round(cmp$base_upper_pct, 1),
      `Year t mean (t CO2eq)` = round(cmp$t_mean, 1),
      `Year t +/- %` = round(cmp$t_moe_pct, 1),
      `Year t (-) %` = round(cmp$t_lower_pct, 1),
      `Year t (+) %` = round(cmp$t_upper_pct, 1),
      `Change (%)` = round(cmp$trend_pct, 1),
      `Change 95% lower (%)` = round(cmp$trend_pct + cmp$trend_lo_pp, 1),
      `Change 95% upper (%)` = round(cmp$trend_pct + cmp$trend_hi_pp, 1),
      `Share of year t variance` = round(cmp$contribution, 4),
      check.names = FALSE, stringsAsFactors = FALSE)
  }
  if (!is.null(sources_long)) {
    sl <- sources_long
    report_sheets$All_years_by_source <- data.frame(
      Year = sl$year, `Emission source` = sl$category, Gas = sl$gas,
      `Mean (t CO2eq)` = round(sl$mean_t_co2e, 1),
      `95% lower (t)` = round(sl$lo, 1), `95% upper (t)` = round(sl$hi, 1),
      `+/- %` = round(sl$moe_pct, 1), `(-) %` = round(sl$lower_pct, 1),
      `(+) %` = round(sl$upper_pct, 1),
      check.names = FALSE, stringsAsFactors = FALSE)
  }
  if (!is.null(by_group)) {
    bg <- by_group
    report_sheets$All_years_by_group <- data.frame(
      Year = bg$year, `Cattle type` = bg$cattle_type,
      `Production system` = bg$aggregation_level, `Sub-category` = bg$sub_category,
      Source = bg$source, Mean = round(bg$mean, 2),
      `95% lower` = round(bg$lo, 2), `95% upper` = round(bg$hi, 2),
      check.names = FALSE, stringsAsFactors = FALSE)
  }

  sheets <- c(report_sheets, list(
    Trend_summary    = results_table,
    Slope_and_delta  = slope_delta_summary,
    Sensitivity_per_year_SRC  = pull_df(sensitivity_per_year, "src"),
    Sensitivity_delta_SRC     = pull_df(sensitivity_delta, "src"),
    Methodology      = methodology
  ))
  writexl::write_xlsx(sheets, path = filepath)
}

# 2026-10-30: the animal-number choices as the report words them.
.n_corr_label <- function(code, kind = c("group", "year")) {
  kind <- match.arg(kind)
  if (kind == "group")
    switch(as.character(code), full = "one count split into groups (fully correlated)",
           partial = "partly (0.5)", none = "separate counts per group (independent)", as.character(code))
  else
    switch(as.character(code), full = "one census, interpolated (fully correlated)",
           partial = "census every few years (partly correlated)", none = "annual survey (independent)",
           as.character(code))
}
