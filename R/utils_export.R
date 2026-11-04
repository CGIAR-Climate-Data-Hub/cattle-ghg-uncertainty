# Export Functions - IPCC Table 3.3 and Excel Reports

format_ipcc_table <- function(uncertainty_decomposition, country = "", year = "",
                              sources = NULL) {
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

  out <- data.frame(
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
  # 2026-11-04: only the Tab 4 sources that were ticked, and the gas totals
  # that still have a source (R/utils_sources.R)
  if (!is.null(sources) && !all_sources_selected(sources)) {
    out <- out[!vars %in% unselected_vars(sources), , drop = FALSE]
    rownames(out) <- NULL
  }
  attr(out, "vars") <- if (!is.null(sources)) setdiff(vars, unselected_vars(sources)) else vars
  out
}

export_results_xlsx <- function(results, uncertainty, sensitivity, ipcc_table, filepath,
                                settings = NULL, param_specs = NULL,
                                qa_caveats = NULL, manure = NULL,
                                ipcc_by_type = NULL) {
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
      # 2026-11-02 (Lolita): single-year rows only (no "between years"),
      # the two Tab 3 choices named as on the tab.
      Setting = c("Analysis mode", "Iterations", "Links between inputs (Tab 3)",
                  "Animal numbers (N) between groups (Tab 3)",
                  "Comparison of correlation levels", "GWP basis", "Seed",
                  "Emission sources",
                  # (2026-11-02: the "Intake route" row removed at Lolita's
                  # request; the results table in the app still shows it.)
                  "QA/QC checks ignored or repaired"),
      Value   = c(
        "Single year",
        as.character(settings$n_iter %||% NA),
        .corr_mode_label(settings$corr_mode),
        .n_corr_label(settings$n_group_corr %||% "full", "group"),
        if (isTRUE(settings$run_comparison)) "yes" else "no",
        as.character(settings$gwp_version %||% NA),
        as.character(settings$seed %||% NA),
        .emission_sources_label(settings$emission_sources %||% character(0)),
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
  # 2026-11-04: Table 3.3 by cattle type, when the run has both types
  has_type <- is.data.frame(ipcc_by_type) && length(unique(ipcc_by_type[["Cattle type"]])) > 1L
  readme_df <- data.frame(
    Sheet = c("", "README", "Run_Settings", "QA_Caveats", "Results",
              if (has_type) "Results_by_cattle_type", "Sensitivity_SRC", "Input_Parameters"),
    Contents = c(
      paste0(sprintf("Cattle GHG uncertainty calculator, version %s. Generated %s. Single-year Monte Carlo results, %s iterations.",
                     .app_version(), format(Sys.time(), "%Y-%m-%d %H:%M"), format(n_iter, big.mark = ",")),
             .sources_sentence(settings$emission_sources)),
      "This sheet: what each sheet of the workbook contains.",
      "The settings of the run: iterations, correlation choices (Tab 3), GWP basis, seed, emission sources, and how many QA/QC checks were ignored or repaired.",
      "The QA/QC checks that were ignored or repaired so the run could go ahead. Empty when there were none.",
      paste0("One row per IPCC reporting line (Table 3.3): mean emissions in tonnes of the gas, the 95% confidence interval (CI), ",
             "the 95% margin of error (MoE, half the width of the CI as a percentage of the mean) and its lower and upper halves",
             if (has_decomp) ", then the uncertainty from the activity data (AD) alone and from the emission factors and coefficients (EF) alone."
             else ". The AD and EF split appears when 'Run uncertainty decomposition' is ticked on Tab 4."),
      if (has_type) "The same lines for dairy and non-dairy cattle separately (reporting codes 3.A.1.a and 3.A.1.b, 3.B.1.a and 3.B.1.b): mean emissions in tonnes of the gas, the AD, EF and combined 95% MoE, and the lower and upper halves of the combined interval. Each type's uncertainty is computed from the draws of its own groups, summed within the type.",
      "The sensitivity analysis of total CO2eq: one row per input, its standardised regression coefficient (src, from -1 to +1; the further from zero, the more the input matters), its absolute value, p_value, rank, and the animal groups that use it.",
      "Every input of the run: group, parameter, mean, distribution, bounds, and range_source, which says where each uncertainty range comes from and marks the placeholder ranges (no published source)."),
    stringsAsFactors = FALSE)

  sheets <- list(
    README           = readme_df,
    Run_Settings     = run_settings_df,
    QA_Caveats       = caveats_df,
    Results          = results_df,
    Results_by_cattle_type = if (has_type) ipcc_by_type else NULL,
    Sensitivity_SRC  = src_df,
    Input_Parameters = inputs_df
  )
  writexl::write_xlsx(Filter(Negate(is.null), sheets), path = filepath)
}

# 2026-11-04: " Sources included in every figure: ..." when not every Tab 4
# source was ticked, "" otherwise (README sheets and Word summaries).
.sources_sentence <- function(sources) {
  if (is.null(sources) || all_sources_selected(sources)) return("")
  paste0(" Sources included in every figure: ", sources_label(sources), ".")
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
  # 2026-11-04: a line absent from the uncertainty frame (a source not
  # ticked on Tab 4) is not reported; AD and EF are matched by category
  out <- out[!is.na(out[["Mean emissions (t of the gas)"]]), , drop = FALSE]
  rownames(out) <- NULL
  if (is.data.frame(ipcc_table) && "Emission category" %in% names(ipcc_table) &&
      all(c("AD uncertainty (95% MoE %)", "EF uncertainty (95% MoE %)") %in% names(ipcc_table))) {
    k <- match(out[["Emission category"]], ipcc_table[["Emission category"]])
    out[["AD uncertainty, MoE 95% (%)"]] <- ipcc_table[["AD uncertainty (95% MoE %)"]][k]
    out[["EF uncertainty, MoE 95% (%)"]] <- ipcc_table[["EF uncertainty (95% MoE %)"]][k]
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
                               sources_long = NULL, by_group = NULL,
                               # 2026-11-02: the run settings, the QA/QC
                               # caveats and the inputs, as in the
                               # single-year workbook
                               settings = NULL, qa_caveats = NULL,
                               param_specs = NULL, manure = NULL) {
  # 2026-11-02 (Lolita: "the excel for trend is really messy ... like the
  # single year one"). README first, then the run, the headline figures,
  # IPCC Table 3.3, every year (total, by source, by group), the two
  # sensitivity rankings and the inputs. Dropped as duplicates: the two
  # years by source (in IPCC Table 3.3 and All_years_by_source), the slope
  # and delta sheet (in Headline), the Methodology sheet (in README and
  # Run_Settings).
  placeholder <- function(msg) data.frame(Note = msg, stringsAsFactors = FALSE)
  r1 <- function(x, d = 1) if (is.null(x) || !length(x) || is.na(x[1])) NA_real_ else round(x, d)
  yrs <- if (is.data.frame(results_table) && nrow(results_table)) range(results_table$Year) else c(NA, NA)
  h <- headline
  n_pair <- if (!is.null(h) && !is.null(h$n_iter_pair)) h$n_iter_pair else n_iter

  run_settings_df <- data.frame(
    Setting = c("Analysis mode", "Years", "Draws per year (series)", "Draws for base year and year t (paired run)",
                "Year-to-year correlation of coefficients", "Links between inputs (Tab 3)",
                "Animal numbers (N) between groups (Tab 3)", "Animal numbers (N) between years (Tab 3)",
                "GWP basis", "Seed", "Emission sources", "QA/QC checks ignored or repaired"),
    Value = c("Trend",
              sprintf("%s to %s (%d years)", yrs[1], yrs[2], if (is.data.frame(results_table)) nrow(results_table) else NA_integer_),
              format(n_iter, big.mark = ","), format(n_pair, big.mark = ","),
              .year_corr_label(year_corr),
              .corr_mode_label(settings$corr_mode),
              .n_corr_label(settings$n_group_corr %||% "full", "group"),
              .n_corr_label(settings$n_year_corr %||% "none", "year"),
              as.character(settings$gwp_version %||% NA), as.character(settings$seed %||% NA),
              .emission_sources_label(settings$emission_sources %||% character(0)),
              if (is.null(qa_caveats) || !nrow(qa_caveats)) "none" else paste0(nrow(qa_caveats), " (see sheet QA_Caveats)")),
    stringsAsFactors = FALSE)

  caveats_df <- if (is.data.frame(qa_caveats) && nrow(qa_caveats) > 0) qa_caveats
                else placeholder("No QA/QC checks were ignored or repaired for this run.")

  headline_df <- if (!is.null(h)) data.frame(
    Item = c("Base year", "Base year: mean total emissions (t CO2eq)",
             "Base year: 95% CI lower (t CO2eq)", "Base year: 95% CI upper (t CO2eq)", "Base year: MoE 95% (%)",
             "Year t", "Year t: mean total emissions (t CO2eq)",
             "Year t: 95% CI lower (t CO2eq)", "Year t: 95% CI upper (t CO2eq)", "Year t: MoE 95% (%)",
             "Change in mean emissions, base year to year t (%)",
             "Change: 95% CI lower (%)", "Change: 95% CI upper (%)",
             "Trend uncertainty, lower (percentage points)", "Trend uncertainty, upper (percentage points)",
             "The 95% CI of the change includes zero",
             "Average change per year over all years (t CO2eq per year)",
             "Average change per year: 95% CI lower", "Average change per year: 95% CI upper"),
    Value = c(h$base_year, r1(h$base_mean, 0), r1(h$base_lo, 0), r1(h$base_hi, 0), r1(h$base_moe),
              h$year_t, r1(h$t_mean, 0), r1(h$t_lo, 0), r1(h$t_hi, 0), r1(h$t_moe),
              r1(h$trend_pct), r1(h$trend_lo_pct), r1(h$trend_hi_pct),
              r1(h$trend_lo_pp), r1(h$trend_hi_pp),
              if (isTRUE(h$zero_inside)) "yes" else "no",
              r1(slope$mean, 0), r1(slope$ci[1], 0), r1(slope$ci[2], 0)),
    stringsAsFactors = FALSE) else placeholder("Headline figures unavailable.")

  all_years_df <- if (is.data.frame(results_table) && nrow(results_table)) data.frame(
    Year = results_table$Year,
    `Mean total emissions (t CO2eq)` = round(results_table$Mean_t_CO2eq, 0),
    `95% CI lower (t CO2eq)` = round(results_table$CI_Lower_t, 0),
    `95% CI upper (t CO2eq)` = round(results_table$CI_Upper_t, 0),
    `MoE 95% (%)` = round(results_table$MoE_95_pct, 1),
    `Change in mean since the base year (%)` = round(results_table$Delta_vs_base_pct, 1),
    `Change in mean from the previous year (%)` = round(results_table$YoY_pct, 1),
    check.names = FALSE, stringsAsFactors = FALSE) else placeholder("No trend results.")

  by_source_df <- if (!is.null(sources_long) && nrow(sources_long)) {
    sl <- sources_long
    data.frame(Year = sl$year, `Emission source` = sl$category, Gas = sl$gas,
               `Mean emissions (t CO2eq)` = round(sl$mean_t_co2e, 1),
               `95% CI lower (t CO2eq)` = round(sl$lo, 1), `95% CI upper (t CO2eq)` = round(sl$hi, 1),
               `MoE 95% (%)` = round(sl$moe_pct, 1),
               `Lower half of the CI (-%)` = round(sl$lower_pct, 1), `Upper half of the CI (+%)` = round(sl$upper_pct, 1),
               check.names = FALSE, stringsAsFactors = FALSE)
  } else placeholder("No per-source results.")

  by_group_df <- if (!is.null(by_group) && nrow(by_group)) {
    bg <- by_group
    src_lab <- c(enteric_ch4_total = "Enteric CH4", manure_ch4_total = "Manure CH4",
                 direct_n2o_mm_total = "Manure N2O direct", indirect_n2o_mm_total = "Manure N2O indirect",
                 direct_n2o_prp_total = "Pasture N2O direct", indirect_n2o_prp_total = "Pasture N2O indirect",
                 total_ch4 = "Total CH4", total_n2o = "Total N2O", total_co2e = "Total CO2eq")
    s <- as.character(bg$source); s <- ifelse(s %in% names(src_lab), src_lab[s], s)
    data.frame(Year = bg$year, `Cattle type` = bg$cattle_type,
               `Production system` = bg$aggregation_level, `Sub-category` = bg$sub_category,
               Source = unname(s),
               `Mean (t of the gas; t CO2eq for Total CO2eq)` = round(bg$mean, 2),
               `95% CI lower` = round(bg$lo, 2), `95% CI upper` = round(bg$hi, 2),
               check.names = FALSE, stringsAsFactors = FALSE)
  } else placeholder("No per-group results.")

  pull_sens <- function(sens) {
    if (is.null(sens) || !is.data.frame(sens$src) || !nrow(sens$src)) return(placeholder("Sensitivity unavailable for this run."))
    x <- sens$src
    if ("rank" %in% names(x)) x <- x[order(x$rank), , drop = FALSE]
    num <- vapply(x, is.numeric, logical(1)); x[num] <- lapply(x[num], round, 3)
    x
  }

  inputs_df <- if (is.data.frame(param_specs) && nrow(param_specs)) {
    x <- param_specs
    x$range_source <- tryCatch(range_source_label(param_specs), error = function(e) NA_character_)
    x
  } else placeholder("Input parameters unavailable.")

  readme_df <- data.frame(
    Sheet = c("", "README", "Run_Settings", "QA_Caveats", "Headline", "IPCC_Table_3_3", "All_years",
              "All_years_by_source", "All_years_by_group", "Sensitivity_latest_year", "Sensitivity_change", "Input_Parameters"),
    Contents = c(
      paste0(sprintf("Cattle GHG uncertainty calculator, version %s. Generated %s. Trend %s to %s.",
                     .app_version(), format(Sys.time(), "%Y-%m-%d %H:%M"), yrs[1], yrs[2]),
             .sources_sentence(settings$emission_sources)),
      "This sheet: what each sheet of the workbook contains.",
      "The settings of the run: years, draws, the year-to-year correlation of the coefficients, the correlation choices of Tab 3, GWP basis, seed, emission sources, and how many QA/QC checks were ignored or repaired.",
      "The QA/QC checks that were ignored or repaired so the run could go ahead.",
      "The figures to report: total emissions of the base year and year t with their 95% confidence interval (CI) and 95% margin of error (MoE, half the width of the CI as a percentage of the mean); the change between the two years with its 95% CI and the trend uncertainty in percentage points; the average change per year over all years.",
      "IPCC 2006 Vol. 1 Ch. 3 Table 3.3, the general reporting table for uncertainty, for the base year and year t.",
      "One row per year: mean total emissions, 95% CI, MoE, change since the base year and from the previous year.",
      "One row per year and emission source: mean emissions in t CO2eq, 95% CI, MoE and its lower and upper halves.",
      "One row per year, animal group and emission source: mean and 95% CI.",
      "The sensitivity analysis of total CO2eq in the latest year: one row per input, its standardised regression coefficient (src, from -1 to +1; the further from zero, the more the input matters), its absolute value, p_value and rank.",
      "The same for the change in total CO2eq between the first and the last year; an input drawn in both years appears once per year.",
      "Every input of the run, with range_source, which says where each uncertainty range comes from and marks the placeholder ranges."),
    stringsAsFactors = FALSE)

  sheets <- list(
    README = readme_df, Run_Settings = run_settings_df, QA_Caveats = caveats_df,
    Headline = headline_df,
    IPCC_Table_3_3 = if (is.data.frame(ipcc_table) && nrow(ipcc_table)) ipcc_table else placeholder("IPCC table unavailable."),
    All_years = all_years_df, All_years_by_source = by_source_df, All_years_by_group = by_group_df,
    Sensitivity_latest_year = pull_sens(sensitivity_per_year),
    Sensitivity_change = pull_sens(sensitivity_delta),
    Input_Parameters = inputs_df)
  writexl::write_xlsx(sheets, path = filepath)
}

# 2026-11-02: the year-to-year correlation of the coefficients as the
# reports word it.
.year_corr_label <- function(code) {
  switch(as.character(code %||% "full"),
         full    = "The same factors for every year (fully correlated between years)",
         partial = "Factors revised every few years (partly correlated between years)",
         none    = "Independent (no year-to-year correlation)",
         as.character(code))
}

# 2026-11-02: the Tab 3 "links between inputs" option as the reports word it.
.corr_mode_label <- function(code) {
  switch(as.character(code %||% "none"),
         none = "none", preset = "Structural defaults (literature-based)",
         timeseries = "From template (time series)", manual = "Manual matrix",
         as.character(code))
}
# 2026-11-02: the emission sources with their names, not their codes.
.emission_sources_label <- function(codes) {
  if (!length(codes)) return("(none)")
  lab <- c(enteric_ch4 = "Enteric CH4", manure_ch4 = "Manure CH4",
           manure_n2o_direct = "Manure N2O direct", manure_n2o_indirect = "Manure N2O indirect",
           pasture_n2o_direct = "Pasture N2O direct", pasture_n2o_indirect = "Pasture N2O indirect")
  b <- sub("_total$", "", as.character(codes))
  b <- sub("^direct_n2o_mm$", "manure_n2o_direct", b); b <- sub("^indirect_n2o_mm$", "manure_n2o_indirect", b)
  b <- sub("^direct_n2o_prp$", "pasture_n2o_direct", b); b <- sub("^indirect_n2o_prp$", "pasture_n2o_indirect", b)
  out <- ifelse(b %in% names(lab), lab[b], as.character(codes))
  paste(unname(out), collapse = ", ")
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
