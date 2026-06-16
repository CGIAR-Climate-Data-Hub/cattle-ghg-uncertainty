# Word run-summary exports.
#
# Two public entry points:
#   build_run_summary_docx()    - single-year MC run (Round 6b, redesigned R8)
#   build_trend_summary_docx()  - multi-year trend run (Round 8)
#
# Both share a design vocabulary mirroring the AW response document:
#   H1 / H2 dark green (#1B4332), H3 mid green (#2D6A4F), tables with green
#   header + alternating rows + width-constrained layout. Wide tables are
#   wrapped in landscape sections so they don't overflow the page.
#
# Plotly renderers in the live app are untouched; ggplot2 versions of every
# chart are rebuilt here so the doc renders deterministically on shinyapps.io
# without a Chromium binary (which webshot2 would require).

# ============================================================================
# DESIGN VOCABULARY (shared)
# ============================================================================

.GREEN_DARK <- "#1B4332"
.GREEN_MID  <- "#2D6A4F"
.GREEN_BG   <- "#D8F3DC"
.ROW_ALT    <- "#F2F2F2"
.BORDER     <- "#B0B0B0"

# Apply the AW-doc visual style to a flextable: green header + alternating
# rows + 0.5pt grey borders + width=1 (fill 100% of available text width so
# the table never overflows the page).
.styled_flextable <- function(ft) {
  if (is.null(ft)) return(NULL)
  ncols <- length(ft$col_keys)
  ft <- flextable::theme_box(ft)
  ft <- flextable::bg(ft, bg = .GREEN_MID, part = "header")
  ft <- flextable::color(ft, color = "white", part = "header")
  ft <- flextable::bold(ft, bold = TRUE, part = "header")
  ft <- flextable::fontsize(ft, size = 9, part = "header")
  ft <- flextable::fontsize(ft, size = 8, part = "body")
  ft <- flextable::padding(ft, padding = 3, part = "all")
  ft <- flextable::border_inner(ft, officer::fp_border(color = .BORDER, width = 0.5))
  ft <- flextable::border_outer(ft, officer::fp_border(color = .BORDER, width = 0.5))
  # Alternating row backgrounds (skip if fewer than 2 body rows — seq() would
  # error with `wrong sign in 'by' argument` for a 1-row table).
  body_rows <- nrow(ft$body$dataset)
  if (body_rows >= 2L) {
    even_rows <- seq(2, body_rows, by = 2)
    if (length(even_rows) > 0L)
      ft <- flextable::bg(ft, i = even_rows, bg = .ROW_ALT, part = "body")
  }
  # Constrain width to page width so columns shrink to fit instead of overflow
  ft <- flextable::set_table_properties(ft, layout = "autofit", width = 1)
  ft
}

# Headings — use officer's default 'heading N' styles (which Word renders with
# the document's heading style) but coerced to our green colour via fp_par.
.add_h1 <- function(doc, text) {
  officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(text, prop = officer::fp_text(
      bold = TRUE, font.size = 18, color = .GREEN_DARK,
      font.family = "Calibri")),
    fp_p = officer::fp_par(padding.top = 12, padding.bottom = 4)
  ))
}

.add_h2 <- function(doc, text) {
  officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(text, prop = officer::fp_text(
      bold = TRUE, font.size = 13, color = .GREEN_DARK,
      font.family = "Calibri")),
    fp_p = officer::fp_par(padding.top = 10, padding.bottom = 4)
  ))
}

.add_h3 <- function(doc, text) {
  officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(text, prop = officer::fp_text(
      bold = TRUE, font.size = 11, color = .GREEN_MID,
      font.family = "Calibri")),
    fp_p = officer::fp_par(padding.top = 8, padding.bottom = 2)
  ))
}

.add_p <- function(doc, text) {
  officer::body_add_par(doc, text, style = "Normal")
}

# Wrap the *preceding* content in a landscape section. Officer applies the
# section break AFTER the block_section call, so call this immediately after
# the wide table you want in landscape.
.add_landscape_break <- function(doc) {
  ps <- officer::prop_section(
    page_size = officer::page_size(orient = "landscape", width = 11.69, height = 8.27),
    page_margins = officer::page_mar(top = 0.6, bottom = 0.6, left = 0.7, right = 0.7,
                                       header = 0.3, footer = 0.3, gutter = 0)
  )
  officer::body_end_block_section(doc,
    value = officer::block_section(property = ps))
}

.add_portrait_break <- function(doc) {
  ps <- officer::prop_section(
    page_size = officer::page_size(orient = "portrait", width = 8.27, height = 11.69),
    page_margins = officer::page_mar(top = 0.8, bottom = 0.8, left = 0.9, right = 0.9,
                                       header = 0.3, footer = 0.3, gutter = 0)
  )
  officer::body_end_block_section(doc,
    value = officer::block_section(property = ps))
}

.add_flextable_safe <- function(doc, ft) {
  if (is.null(ft)) return(doc)
  flextable::body_add_flextable(doc, ft, align = "left")
}

# Append a centred logo row matching the app's home-page logo bar:
# Alliance of Bioversity & CIAT, CGIAR Climate Action Programme, and the Global
# Methane Hub. Each logo is shown at a common height with its width set from the
# PNG's true aspect ratio (so none is stretched — the climate-action wordmark is
# ~3.8:1, much wider than the others). Missing PNGs are skipped silently so the
# Word build never errors when a logo hasn't been staged in www/.
.add_logo_footer <- function(doc) {
  H <- 0.55  # inches; common logo height, widths derived from each aspect ratio
  logos <- list(
    list(src = "www/alliance_logo.png",       w = 0.76),  # 1549x1126 ~ 1.38:1
    list(src = "www/climate_action_logo.png", w = 2.10),  # 439x115  ~ 3.82:1
    list(src = "www/gmh_logo.png",            w = 1.07)   # 879x452  ~ 1.94:1
  )
  logos <- Filter(function(L) file.exists(L$src), logos)
  if (length(logos) == 0) return(doc)
  parts <- list()
  for (i in seq_along(logos)) {
    if (i > 1) parts <- c(parts, list(officer::ftext("     ")))
    parts <- c(parts, list(officer::external_img(
      src = logos[[i]]$src, width = logos[[i]]$w, height = H)))
  }
  doc <- officer::body_add_fpar(doc,
    do.call(officer::fpar, c(parts, list(
      fp_p = officer::fp_par(text.align = "center", padding.top = 8)))))
  doc
}

.fmt_int <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("(unset)")
  format(as.integer(x), big.mark = ",")
}

.fmt_num <- function(x, digits = 1) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("—")
  formatC(x, digits = digits, format = "f", big.mark = ",")
}

.fmt_signed <- function(x, digits = 1) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("—")
  s <- formatC(x, digits = digits, format = "f")
  if (x > 0) paste0("+", s) else s
}

.as_str <- function(x, default = "") {
  if (is.null(x) || length(x) == 0) return(default)
  if (is.na(x))                      return(default)
  if (!nzchar(as.character(x)))      return(default)
  as.character(x)
}

.pretty_var <- function(v) {
  # Andreas 2026-05 #37, #39: every IPCC emission source must appear as its
  # own row in the Word Section 4 table — including pasture direct and
  # indirect, which were missing.
  map <- c(
    total_co2e             = "Total CO2eq",
    total_ch4              = "Total CH4",
    total_n2o              = "Total N2O",
    enteric_ch4_total      = "Enteric fermentation CH4",
    manure_ch4_total       = "Manure management CH4",
    direct_n2o_mm_total    = "Manure management N2O direct",
    indirect_n2o_mm_total  = "Manure management N2O indirect",
    direct_n2o_prp_total   = "Pasture deposition N2O direct",
    indirect_n2o_prp_total = "Pasture deposition N2O indirect",
    total_enteric_ch4      = "Enteric fermentation CH4 (inventory)",
    total_manure_ch4       = "Manure management CH4 (inventory)",
    total_direct_n2o_mm    = "Manure management N2O direct (inventory)",
    total_indirect_n2o_mm  = "Manure management N2O indirect (inventory)",
    total_direct_n2o_prp   = "Pasture deposition N2O direct (inventory)",
    total_indirect_n2o_prp = "Pasture deposition N2O indirect (inventory)"
  )
  out <- map[v]
  out[is.na(out)] <- v[is.na(out)]
  unname(out)
}

# Andreas 2026-05 #37, #39, C11: unit lookup for the Word Section 4 table
# (and reusable elsewhere).
.unit_for_var <- function(v) {
  ch4_vars <- c("total_ch4","enteric_ch4_total","manure_ch4_total",
                "total_enteric_ch4","total_manure_ch4")
  n2o_vars <- c("total_n2o","direct_n2o_mm_total","indirect_n2o_mm_total",
                "direct_n2o_prp_total","indirect_n2o_prp_total",
                "total_direct_n2o_mm","total_indirect_n2o_mm",
                "total_direct_n2o_prp","total_indirect_n2o_prp",
                "total_direct_n2o","total_indirect_n2o")
  ifelse(v %in% ch4_vars, "t CH4",
         ifelse(v %in% n2o_vars, "t N2O",
                ifelse(v == "total_co2e", "t CO2eq", "")))
}

# ============================================================================
# SINGLE-YEAR REPORT — build_run_summary_docx() (redesigned)
# ============================================================================

build_run_summary_docx <- function(path,
                                   settings,
                                   param_specs,
                                   mc_results,
                                   uncertainty,
                                   sensitivity = NULL,
                                   ipcc_table  = NULL,
                                   ipcc_meta   = NULL,
                                   decomposition          = NULL,
                                   comparison_uncertainty = NULL,
                                   diagnostics            = NULL,
                                   samples_for_density    = NULL,
                                   app_version = NULL) {

  doc <- officer::read_docx()

  # ---- Title block --------------------------------------------------------
  doc <- .add_h1(doc, "Cattle GHG Tier 2 Uncertainty — Single-year run")
  meta_line <- paste(
    sprintf("Generated %s.", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$ipcc_version))
      sprintf("IPCC guidelines: %s.", ipcc_meta$ipcc_version) else NULL,
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$region) && nzchar(ipcc_meta$region))
      sprintf("Region: %s.", ipcc_meta$region) else NULL,
    "Approach 2 Monte Carlo simulation per IPCC Vol 1 Ch 3."
  )
  doc <- .add_p(doc, paste(stats::na.omit(meta_line), collapse = " "))

  # ---- Executive summary --------------------------------------------------
  doc <- .add_h2(doc, "Executive summary")
  doc <- .add_p(doc, .build_single_exec_summary(uncertainty, sensitivity, settings))

  # Andreas 2026-05 C11: AD-uncertainty and EF-uncertainty per-source tables
  # follow the exec summary, matching the mock-up. Only render when the
  # decomposition was actually run (ipcc_table is the canonical signal).
  if (!is.null(ipcc_table) && is.data.frame(ipcc_table) && nrow(ipcc_table) > 0) {
    ad_ft <- .ad_ef_flextable(ipcc_table, kind = "AD")
    if (!is.null(ad_ft)) {
      doc <- .add_p(doc, "For IPCC reporting, the key results are:")
      doc <- .add_p(doc, "Activity-data uncertainty:")
      doc <- .add_flextable_safe(doc, .styled_flextable(ad_ft))
    }
    ef_ft <- .ad_ef_flextable(ipcc_table, kind = "EF")
    if (!is.null(ef_ft)) {
      doc <- .add_p(doc, "Emission-factor uncertainty:")
      doc <- .add_flextable_safe(doc, .styled_flextable(ef_ft))
    }
  }

  # ---- Run settings -------------------------------------------------------
  doc <- .add_h2(doc, "1. What was run")
  doc <- .add_flextable_safe(doc, .styled_flextable(.settings_flextable(settings)))

  # ---- Auto-filled parameters --------------------------------------------
  imputed_ft <- .imputed_flextable(param_specs)
  if (!is.null(imputed_ft)) {
    doc <- .add_h2(doc, "2. Auto-filled parameters")
    doc <- .add_p(doc,
      "These parameters were not in the upload and were filled with IPCC defaults so the simulation could run. Override with country-specific data when available.")
    doc <- .add_flextable_safe(doc, .styled_flextable(imputed_ft))
  }

  # ---- IPCC Table 3.3 results (LANDSCAPE) --------------------------------
  if (!is.null(ipcc_table) && is.data.frame(ipcc_table) && nrow(ipcc_table) > 0) {
    doc <- .add_h2(doc, "3. IPCC Table 3.3 — uncertainty decomposition")
    doc <- .add_p(doc,
      "Combined % uncertainty (95% MoE — IPCC Vol.1 Ch.3 Table 3.3 convention) per emission source decomposed into the activity-data and emission-factor contributions, formatted for Annex 7 of a national inventory submission.")
    doc <- .add_flextable_safe(doc, .styled_flextable(.ipcc_flextable(ipcc_table)))
    doc <- .add_landscape_break(doc)
  }

  # ---- Headline by-source results ----------------------------------------
  doc <- .add_h2(doc, "4. Headline results — by source")
  doc <- .add_p(doc,
    "Mean total emissions per source with the 95% confidence interval and 95% margin of error (MoE %, the IPCC Vol.1 Ch.3 Table 3.3 convention) from the Monte Carlo run.")
  doc <- .add_flextable_safe(doc, .styled_flextable(.results_flextable(uncertainty)))
  doc <- .add_portrait_break(doc)

  # ---- Results aggregated by cattle type / production system / sub-category
  # Round 9b §5 / Andreas 2026-05 #39: per-cattle-type aggregation tables.
  agg_fts <- .aggregated_results_flextable(mc_results)
  if (!is.null(agg_fts)) {
    any_rendered <- FALSE
    for (lvl in c("cattle_type", "aggregation_level", "sub_category")) {
      ft <- agg_fts[[lvl]]
      if (is.null(ft)) next
      if (!any_rendered) {
        doc <- .add_h2(doc, "5. Results by cattle type / production system / sub-category")
        doc <- .add_p(doc,
          "Each table aggregates the Monte Carlo results to one row per group at the chosen level. Use these breakdowns to identify which group drives the headline totals in section 4.")
        any_rendered <- TRUE
      }
      level_label <- switch(lvl,
        cattle_type       = "By cattle type",
        aggregation_level = "By production system (aggregation level)",
        sub_category      = "By sub-category")
      doc <- .add_h3(doc, level_label)
      doc <- .add_flextable_safe(doc, .styled_flextable(ft))
    }
    if (any_rendered) doc <- .add_portrait_break(doc)
  }

  # ---- Per-(cattle_type × source) breakdown with raw CH4 / N2O (Andreas 28/5/26 #7.2 + #7.3)
  ps_ft <- .per_source_breakdown_flextable(mc_results, settings$gwp_version)
  if (!is.null(ps_ft)) {
    doc <- .add_h2(doc, "5b. Per-(cattle type × emission source) breakdown")
    doc <- .add_p(doc,
      "One row per cattle_type × IPCC emission source. The 'Mean (t CH4)' and 'Mean (t N2O)' columns give the raw gas-specific quantities inventory teams report; the 'Mean (t CO2eq)' column applies the GWP for cross-source comparison.")
    doc <- .add_flextable_safe(doc, .styled_flextable(ps_ft))
    doc <- .add_portrait_break(doc)
  }

  # ---- AD vs EF vs Combined decomposition chart --------------------------
  # Round 9b §6: visual companion to the IPCC Table 3.3 decomposition above.
  decomp_plot <- .gg_decomposition(decomposition)
  if (!is.null(decomp_plot)) {
    doc <- .add_h2(doc, "6. AD vs EF vs Combined uncertainty")
    doc <- .add_p(doc,
      "95% margin of error (MoE) for total CO2eq, CH4 and N2O under three configurations: AD-only (activity data drives the uncertainty, all coefficients fixed), EF-only (coefficients drive the uncertainty, AD fixed) and Combined (both vary). The Combined value is what is reported in the IPCC Table 3.3 row. MoE is the IPCC reporting convention (Vol.1 Ch.3 Table 3.3); CV is still available in the per-source results table in section 4 for users who want it.")
    doc <- officer::body_add_gg(doc, value = decomp_plot, width = 5.5, height = 3.2)
  }

  # ---- Comparison: with vs without correlations --------------------------
  # Round 9b §7: only rendered when a comparison run was executed.
  comp_plot <- .gg_comparison(uncertainty, comparison_uncertainty)
  if (!is.null(comp_plot)) {
    doc <- .add_h2(doc, "7. Effect of correlations on uncertainty")
    doc <- .add_p(doc,
      "Comparison of the main run (with the parameter correlations set on the Uncertainty tab) against an otherwise-identical run that ignores correlations. A larger 'with-correlations' 95% MoE indicates that the correlation structure compounds parameter uncertainty; similar MoE in both cases indicates the correlations have little effect for this inventory.")
    doc <- officer::body_add_gg(doc, value = comp_plot, width = 5.5, height = 3.0)
  }

  # ---- Sensitivity ranking — top 10 drivers ------------------------------
  sens_ft <- .sensitivity_flextable(sensitivity, top_n = 10L)
  if (!is.null(sens_ft)) {
    doc <- .add_h2(doc, "8. Sensitivity ranking — top 10 drivers")
    doc <- .add_p(doc,
      "Standardised regression coefficient (SRC) and partial rank correlation (PRCC) of each input parameter against total CO2eq. Larger absolute values dominate the output uncertainty. Parameter labels include the cattle-type and sub-category they belong to when the inventory has more than one group.")
    doc <- .add_flextable_safe(doc, .styled_flextable(sens_ft))
  }

  # ---- Full sensitivity rankings -----------------------------------------
  # Round 9b §9: SRC and PRCC side-by-side. Perf (2026-06): capped to the top
  # WORD_SENS_MAX drivers so the Word doc stays small (officer print.rdocx cost
  # scales with table size). The complete ranking for every parameter is in the
  # Sensitivity_SRC / Sensitivity_PRCC sheets of the Excel download.
  n_sens <- if (!is.null(sensitivity$src)) nrow(sensitivity$src)
            else if (!is.null(sensitivity$prcc)) nrow(sensitivity$prcc) else 0L
  full_sens_ft <- .sensitivity_flextable(sensitivity, top_n = WORD_SENS_MAX)
  if (!is.null(full_sens_ft)) {
    if (is.finite(n_sens) && n_sens > WORD_SENS_MAX) {
      doc <- .add_h2(doc, sprintf("9. Sensitivity rankings — top %d drivers", WORD_SENS_MAX))
      doc <- .add_p(doc, sprintf(
        paste0("SRC and PRCC for the %d most influential parameters (of %d), sorted ",
               "by decreasing absolute SRC. The complete ranking for every parameter ",
               "is in the Sensitivity_SRC / Sensitivity_PRCC sheets of the Excel download."),
        WORD_SENS_MAX, n_sens))
    } else {
      doc <- .add_h2(doc, "9. Full sensitivity rankings (all parameters)")
      doc <- .add_p(doc,
        "Complete SRC and PRCC values for every input parameter, sorted by decreasing absolute SRC. Useful for QA and for documenting which parameters were considered in the run.")
    }
    doc <- .add_flextable_safe(doc, .styled_flextable(full_sens_ft))
    doc <- .add_landscape_break(doc)
  }

  # ---- Charts -------------------------------------------------------------
  doc <- .add_h2(doc, "10. Charts")

  hist_plot <- .gg_total_co2e_hist(mc_results)
  if (!is.null(hist_plot)) {
    doc <- .add_h3(doc, "Total CO2eq — Monte Carlo distribution")
    doc <- officer::body_add_gg(doc, value = hist_plot, width = 5.5, height = 3.0)
  }

  tornado_plot <- .gg_tornado(sensitivity)
  if (!is.null(tornado_plot)) {
    doc <- .add_h3(doc, "Sensitivity tornado")
    doc <- officer::body_add_gg(doc, value = tornado_plot, width = 5.5, height = 3.5)
  }

  src_plot <- .gg_source_grid(mc_results)
  if (!is.null(src_plot)) {
    doc <- .add_h3(doc, "Per-source emission distributions")
    doc <- officer::body_add_gg(doc, value = src_plot, width = 5.5, height = 4.0)
  }

  # ---- Per-parameter density plots ---------------------------------------
  # Round 9b §11: mirrors the IPCC Report tab's input-density subplots.
  density_plot <- .gg_input_densities(samples_for_density)
  if (!is.null(density_plot)) {
    doc <- .add_h2(doc, "11. Sampled parameter distributions")
    doc <- .add_p(doc,
      "Histograms of the actual parameter draws used in the Monte Carlo run (up to 12 parameters). Use this to confirm the distributions are shaped as you expected — particularly for any parameter with a non-normal distribution or asymmetric uncertainty bounds.")
    doc <- officer::body_add_gg(doc, value = density_plot, width = 6.5, height = 4.5)
  }

  # ---- MC convergence diagnostics ---------------------------------------
  # Round 9b §12: convergence plot + 4-row diagnostics summary table.
  conv_plot <- .gg_convergence(diagnostics)
  diag_ft   <- .diagnostics_flextable(diagnostics)
  if (!is.null(conv_plot) || !is.null(diag_ft)) {
    doc <- .add_h2(doc, "12. Monte Carlo convergence diagnostics")
    doc <- .add_p(doc,
      "Quality checks confirming the Monte Carlo run is large enough to give a stable headline result. PASS values indicate the reported mean and 95% CI are not sensitive to the random seed; WARN/FAIL means consider re-running with more iterations.")
    if (!is.null(diag_ft)) {
      doc <- .add_flextable_safe(doc, .styled_flextable(diag_ft))
    }
    if (!is.null(conv_plot)) {
      doc <- officer::body_add_gg(doc, value = conv_plot, width = 5.5, height = 3.0)
    }
  }

  # ---- Input parameter documentation -------------------------------------
  # Round 9b §13: full parameter catalogue used in the run.
  inputs_ft <- .inputs_doc_flextable(param_specs)
  if (!is.null(inputs_ft)) {
    doc <- .add_h2(doc, "13. Input parameter documentation")
    total_params <- nrow(param_specs)
    if (is.data.frame(param_specs) && total_params > WORD_INPUTS_MAX) {
      doc <- .add_p(doc, sprintf(
        paste0("Showing the first %d of %s parameter rows (distribution, central ",
               "value, bounds and IPCC reference). The COMPLETE per-parameter ",
               "audit trail for every sub-category is in the 'Input_Parameters' ",
               "sheet of the Excel download — the Word table is capped so the ",
               "report renders quickly."),
        WORD_INPUTS_MAX, format(total_params, big.mark = ",")))
    } else {
      doc <- .add_p(doc,
        "Every parameter used in this run: distribution, central value, bounds and IPCC reference. This table is the input audit trail for the IPCC inventory submission.")
    }
    doc <- .add_flextable_safe(doc, .styled_flextable(inputs_ft))
    doc <- .add_landscape_break(doc)
  }

  # ---- IPCC reporting context --------------------------------------------
  doc <- .add_h2(doc, "14. IPCC reporting context")
  # Andreas 2026-05 C12: previous wording named a specific column ("column J")
  # in the national inventory uncertainty table that we had not verified
  # against the live IPCC 2006 Vol 1 Ch 3 / Annex 7 template. Reworded to
  # describe the metric instead of pinning a column letter.
  doc <- .add_p(doc,
    "This run follows IPCC 2006 Vol 1 Ch 3 Approach 2 (Monte Carlo) for combined uncertainty estimation. The headline 95% MoE values in section 4 are the per-source combined-uncertainty figures used to populate the IPCC Annex 7 / Table 3.3 national inventory uncertainty table (% uncertainty column — the half-width of the 95% confidence interval / mean, per IPCC's own definition). Cross-check the exact column position against your national submission template. The activity-data vs emission-factor split follows the convention adopted in this tool — AD = animal population (N) only; coefficient (EF) = the IPCC equation parameters that combine into the per-head emission factor. See the methodology document (Resources tab) for the full IPCC / UNFCCC reporting-alignment guidance, including the CRT category map and the three-level disaggregation scheme this tool produces.")
  doc <- .add_p(doc,
    "Where parameters were auto-filled (section 2), the IPCC default carries the uncertainty bounds suggested by Penman et al. (2000) and Monni et al. (2007). For parameters with country-specific values, the uncertainty bounds entered on the Uncertainty tab of the app drive the Monte Carlo distribution.")

  # ---- Footer -------------------------------------------------------------
  doc <- .add_p(doc, "")
  doc <- .add_logo_footer(doc)
  footer_bits <- c(
    "Generated by Cattle GHG Uncertainty Calculator",
    if (!is.null(app_version)) sprintf("v%s", app_version) else NULL,
    sprintf("on %s.", format(Sys.Date(), "%Y-%m-%d")),
    "CGIAR Alliance / Bioversity-CIAT — funded by the Global Methane Hub."
  )
  doc <- .add_p(doc, paste(footer_bits, collapse = " "))

  # Release transient chart/flextable objects before officer serialises the
  # document (print.rdocx is the most expensive step and runs alongside the
  # resident simulation data on the ~1 GB worker).
  invisible(gc(FALSE))
  print(doc, target = path)
  invisible(path)
}

.build_single_exec_summary <- function(uncertainty, sensitivity, settings) {
  total_row <- if (!is.null(uncertainty) && "variable" %in% names(uncertainty))
    uncertainty[uncertainty$variable == "total_co2e", , drop = FALSE]
  else NULL
  if (is.null(total_row) || nrow(total_row) == 0) {
    return("Total CO2eq could not be summarised — no result row found.")
  }
  m   <- total_row$mean
  lo  <- total_row$ci_lower
  hi  <- total_row$ci_upper
  moe <- total_row$moe_pct

  # Top driver from sensitivity (SRC if available)
  driver_text <- ""
  base <- if (!is.null(sensitivity$src) && nrow(sensitivity$src) > 0) sensitivity$src
          else if (!is.null(sensitivity$prcc) && nrow(sensitivity$prcc) > 0) sensitivity$prcc
          else NULL
  if (!is.null(base) && nrow(base) > 0) {
    val_col <- if ("src" %in% names(base)) "src" else "prcc"
    top <- base[order(-abs(base[[val_col]])), , drop = FALSE][1, ]
    driver_text <- sprintf(
      " The single dominant uncertainty driver is %s (%s = %s).",
      top$parameter, toupper(val_col),
      formatC(top[[val_col]], digits = 2, format = "f"))
  }

  n_iter_str <- .fmt_int(settings$n_iter)
  # 2026-06: dropped the parallel "Coefficient of variation: …" sentence so the
  # exec summary leads with the single IPCC-aligned metric (95% MoE) used
  # throughout the rest of the report.
  sprintf(
    "Total emissions: %s t CO2eq with a 95%% confidence interval of [%s, %s]. 95%% margin of error: %s%%.%s These figures are based on %s Monte Carlo iterations under the IPCC Approach 2 method.",
    .fmt_num(m, 0), .fmt_num(lo, 0), .fmt_num(hi, 0),
    .fmt_num(moe, 1),
    driver_text, n_iter_str
  )
}

# ============================================================================
# TREND REPORT — build_trend_summary_docx() (new, Round 8)
# ============================================================================

build_trend_summary_docx <- function(path,
                                      trend_results,
                                      slope,
                                      delta_total,
                                      sensitivity_per_year = NULL,
                                      sensitivity_delta    = NULL,
                                      year_corr   = "full",
                                      years       = NULL,
                                      n_iter      = 2000,
                                      ipcc_meta   = NULL,
                                      param_specs = NULL,
                                      app_version = NULL) {

  doc <- officer::read_docx()
  yrs <- if (!is.null(years)) range(years) else range(trend_results$Year)

  # ---- Title block --------------------------------------------------------
  doc <- .add_h1(doc, sprintf("Cattle GHG Tier 2 Uncertainty — Trend %d–%d",
                                yrs[1], yrs[2]))
  meta_line <- paste(
    sprintf("Generated %s.", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    sprintf("Year-to-year correlation mode: %s.", year_corr),
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$ipcc_version))
      sprintf("IPCC guidelines: %s.", ipcc_meta$ipcc_version) else NULL,
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$region) && nzchar(ipcc_meta$region))
      sprintf("Region: %s.", ipcc_meta$region) else NULL,
    "Approach 2 Monte Carlo per IPCC Vol 1 Ch 3 §3.2.2.4 + §3.7."
  )
  doc <- .add_p(doc, paste(stats::na.omit(meta_line), collapse = " "))

  # ---- Executive summary --------------------------------------------------
  doc <- .add_h2(doc, "Executive summary")
  doc <- .add_p(doc, .build_trend_exec_summary(trend_results, slope, delta_total,
                                                 sensitivity_delta, year_corr, n_iter))

  # ---- Run settings -------------------------------------------------------
  doc <- .add_h2(doc, "1. What was run")
  doc <- .add_flextable_safe(doc,
    .styled_flextable(.trend_settings_flextable(year_corr, n_iter, yrs, ipcc_meta)))

  # ---- Trend table (LANDSCAPE) -------------------------------------------
  doc <- .add_h2(doc, "2. Year-by-year trend")
  doc <- .add_p(doc,
    "Per-year mean total emissions, 95% confidence interval, 95% margin of error (the IPCC reporting convention per Vol.1 Ch.3 Table 3.3), and the percent change relative to the base year and to the previous year.")
  doc <- .add_flextable_safe(doc, .styled_flextable(.trend_table_flextable(trend_results)))
  doc <- .add_landscape_break(doc)

  # ---- Trend chart --------------------------------------------------------
  doc <- .add_h2(doc, "3. Trend chart")
  trend_plot <- .gg_trend_chart(trend_results)
  if (!is.null(trend_plot)) {
    doc <- officer::body_add_gg(doc, value = trend_plot, width = 5.5, height = 3.2)
  }

  # Round 9b §3a — Year-over-year % change bar chart.
  yoy_plot <- .gg_yoy_chart(trend_results)
  if (!is.null(yoy_plot)) {
    doc <- .add_h3(doc, "Year-over-year % change")
    doc <- officer::body_add_gg(doc, value = yoy_plot, width = 5.5, height = 2.8)
  }

  # Round 9b §3b — Distribution of ΔY_N − Y_1, the uncertainty on the trend.
  delta_plot <- .gg_delta_distribution(delta_total)
  if (!is.null(delta_plot)) {
    doc <- .add_h3(doc, "Distribution of ΔY_N − Y_1")
    doc <- officer::body_add_gg(doc, value = delta_plot, width = 5.5, height = 3.0)
  }

  # ---- Slope + delta mini-table ------------------------------------------
  doc <- .add_h2(doc, "4. Trend slope and Δ Y_N − Y_1")
  doc <- .add_p(doc,
    "The slope is fitted via least-squares per Monte Carlo iteration; the 95% CI is the [2.5%, 97.5%] of that distribution. ΔY_N−Y_1 is the per-iteration difference between the last and first year, with its own 95% CI and percent of the base year.")
  doc <- .add_flextable_safe(doc,
    .styled_flextable(.slope_delta_flextable(slope, delta_total)))

  # ---- Sensitivity drivers -----------------------------------------------
  doc <- .add_h2(doc, "5. Sensitivity drivers")
  doc <- .add_p(doc,
    "Two views: per-year drivers identify what dominates the uncertainty in the most recent year, while trend drivers (Δ across years) identify what drives the change between Y_1 and Y_N. The latter is the methodologically correct answer to 'what makes the trend uncertain' per IPCC Vol 1 Ch 3 §3.7.")

  py_ft <- .sensitivity_flextable(sensitivity_per_year, top_n = 10L)
  if (!is.null(py_ft)) {
    doc <- .add_h3(doc, "Per-year (latest year) — top 10")
    doc <- .add_flextable_safe(doc, .styled_flextable(py_ft))
    py_plot <- .gg_tornado(sensitivity_per_year)
    if (!is.null(py_plot))
      doc <- officer::body_add_gg(doc, value = py_plot, width = 5.5, height = 3.0)
  }

  dl_ft <- .sensitivity_flextable(sensitivity_delta, top_n = 10L)
  if (!is.null(dl_ft)) {
    doc <- .add_h3(doc, "Trend driver (Δ Y_N − Y_1) — top 10")
    doc <- .add_flextable_safe(doc, .styled_flextable(dl_ft))
    dl_plot <- .gg_tornado(sensitivity_delta)
    if (!is.null(dl_plot))
      doc <- officer::body_add_gg(doc, value = dl_plot, width = 5.5, height = 3.0)
  }

  # Round 9b §5a — Full sensitivity rankings (all parameters).
  full_py <- .sensitivity_flextable(sensitivity_per_year, top_n = Inf)
  full_dl <- .sensitivity_flextable(sensitivity_delta,    top_n = Inf)
  if (!is.null(full_py) || !is.null(full_dl)) {
    doc <- .add_h2(doc, "5a. Full sensitivity rankings (all parameters)")
    doc <- .add_p(doc,
      "Complete SRC and PRCC values for every input parameter. Per-year is the latest-year analysis; trend driver is the Δ Y_N − Y_1 analysis.")
    if (!is.null(full_py)) {
      doc <- .add_h3(doc, "Per-year (latest year) — full ranking")
      doc <- .add_flextable_safe(doc, .styled_flextable(full_py))
    }
    if (!is.null(full_dl)) {
      doc <- .add_h3(doc, "Trend driver (Δ Y_N − Y_1) — full ranking")
      doc <- .add_flextable_safe(doc, .styled_flextable(full_dl))
    }
    doc <- .add_landscape_break(doc)
  }

  # Round 9b §6 — Input parameter documentation.
  inputs_ft <- .inputs_doc_flextable(param_specs)
  if (!is.null(inputs_ft)) {
    doc <- .add_h2(doc, "6. Input parameter documentation")
    doc <- .add_p(doc,
      "Every parameter used in the trend run: distribution, central value, bounds and IPCC reference. AD parameters (animal population) are re-drawn per year; coefficient (EF) parameters are drawn according to the year-correlation mode in section 1.")
    doc <- .add_flextable_safe(doc, .styled_flextable(inputs_ft))
    doc <- .add_landscape_break(doc)
  }

  # ---- Methodological notes ----------------------------------------------
  doc <- .add_h2(doc, "7. Methodological notes")
  yc_text <- switch(
    year_corr,
    full    = "Coefficient draws (the 23 IPCC equation parameters) are sampled once and reused across every year, while activity data (animal population N) is re-drawn fresh for each year. This is the IPCC 2019 Refinement Vol 1 Ch 3 §3.2.2.4 default for emission-factor uncertainty: same EF every year, AD re-estimated annually. The trend uncertainty in this configuration reflects only the AD changes between years.",
    partial = "Coefficient draws are correlated across years with an AR(1) rank-correlation target (ρ = 0.7), reproduced through restricted-pairing reordering per IPCC Vol.1 Ch.3 §3.2.3.2. This represents partial year-to-year correlation per IPCC §3.2.2.4 — a moderate assumption for cases where coefficients drift over time but neighbouring years share most of the same observational basis.",
    none    = "Coefficient draws and activity-data draws are both independent for each year. This is the most conservative assumption and tends to inflate trend uncertainty; per IPCC §3.2.2.4 it is appropriate only when each year's emission factors come from genuinely independent measurement campaigns."
  )
  doc <- .add_p(doc, yc_text)
  doc <- .add_p(doc,
    "All uncertainty quantification follows IPCC 2006 Vol 1 Ch 3 Approach 2 (Monte Carlo). The trend slope is computed via per-iteration least-squares fit; the slope's 95% CI is therefore the empirical 2.5%/97.5% quantiles of the slope distribution, not a parametric CI. ΔY_N−Y_1 reports the difference between the per-iteration totals at the last and first years, preserving the year-to-year correlation structure imposed above.")

  # ---- IPCC reporting context --------------------------------------------
  doc <- .add_h2(doc, "8. IPCC reporting context")
  doc <- .add_p(doc,
    "Per IPCC Vol 1 Ch 3 §3.7, trend uncertainty should be reported alongside the level of emissions in any national inventory submission that covers more than a single year. The Δ vs base year column in section 2 maps to the trend uncertainty cells of the IPCC Table 3.3 trend annex; the slope in section 4 supports the §3.7.2 'trend assessment' text typical of biennial transparency reports under the Paris Agreement Enhanced Transparency Framework. See the methodology document (Resources tab) for the full IPCC / UNFCCC reporting-alignment guidance.")
  doc <- .add_p(doc,
    "If the trend is reported with a year-correlation assumption other than 'fully correlated coefficients', that choice should be documented in the methods section of the national inventory report — the year-correlation setting recorded in section 1 of this document is the one to cite.")

  # ---- Footer -------------------------------------------------------------
  doc <- .add_p(doc, "")
  doc <- .add_logo_footer(doc)
  footer_bits <- c(
    "Generated by Cattle GHG Uncertainty Calculator — Trend report.",
    if (!is.null(app_version)) sprintf("v%s.", app_version) else NULL,
    sprintf("Built on %s.", format(Sys.Date(), "%Y-%m-%d")),
    "CGIAR Alliance / Bioversity-CIAT — funded by the Global Methane Hub."
  )
  doc <- .add_p(doc, paste(footer_bits, collapse = " "))

  # Release transient chart/flextable objects before officer serialises the
  # document (print.rdocx is the most expensive step and runs alongside the
  # resident simulation data on the ~1 GB worker).
  invisible(gc(FALSE))
  print(doc, target = path)
  invisible(path)
}

.build_trend_exec_summary <- function(trend_results, slope, delta_total,
                                        sensitivity_delta, year_corr, n_iter) {
  yrs <- range(trend_results$Year)
  delta_pct_str <- sprintf("%s%% (95%% CI %s%%, %s%%)",
                            .fmt_signed(delta_total$pct_mean, 1),
                            .fmt_signed(delta_total$pct_ci[1], 1),
                            .fmt_signed(delta_total$pct_ci[2], 1))
  slope_str <- sprintf("%s t CO2eq/yr (95%% CI %s, %s)",
                        .fmt_signed(slope$mean, 0),
                        .fmt_signed(slope$ci[1], 0),
                        .fmt_signed(slope$ci[2], 0))

  driver_text <- ""
  base <- if (!is.null(sensitivity_delta$src) && nrow(sensitivity_delta$src) > 0)
    sensitivity_delta$src
  else if (!is.null(sensitivity_delta$prcc) && nrow(sensitivity_delta$prcc) > 0)
    sensitivity_delta$prcc
  else NULL
  if (!is.null(base) && nrow(base) > 0) {
    val_col <- if ("src" %in% names(base)) "src" else "prcc"
    top <- base[order(-abs(base[[val_col]])), , drop = FALSE][1, ]
    driver_text <- sprintf(
      " The dominant trend driver is %s (%s = %s).",
      top$parameter, toupper(val_col),
      formatC(top[[val_col]], digits = 2, format = "f"))
  }

  yc_short <- switch(
    year_corr,
    full    = "fully correlated coefficients across years (IPCC 2019 default)",
    partial = "partial year-to-year correlation (AR(1), ρ = 0.7)",
    none    = "independent years"
  )

  sprintf(
    "Between %d and %d, total cattle emissions changed by %s. The annualised trend slope is %s.%s These figures are based on %s Monte Carlo iterations per year, with %s.",
    yrs[1], yrs[2], delta_pct_str, slope_str, driver_text,
    .fmt_int(n_iter), yc_short
  )
}

# ============================================================================
# Flextable builders
# ============================================================================

.settings_flextable <- function(s) {
  rows <- list(
    c("Iterations",            .fmt_int(s$n_iter)),
    c("AD correlations",       .as_str(s$corr_mode,    "none")),
    c("EF correlations",       .as_str(s$ef_corr_mode, "none")),
    c("Comparison run (no corr.)", if (isTRUE(s$run_comparison)) "yes" else "no"),
    c("GWP basis",             .as_str(s$gwp_version,  "AR5")),
    c("Seed",                  .as_str(s$seed,         "(random)")),
    c("Analysis mode",         .as_str(s$analysis_mode, "single-year")),
    c("Emission sources",
      if (length(s$emission_sources)) paste(s$emission_sources, collapse = ", ") else "(none)")
  )
  df <- do.call(rbind.data.frame, c(rows, list(stringsAsFactors = FALSE)))
  names(df) <- c("Setting", "Value")
  flextable::flextable(df)
}

.trend_settings_flextable <- function(year_corr, n_iter, yrs, ipcc_meta) {
  yc_label <- switch(
    year_corr,
    full    = "Full (coefficients reused across years; AD redrawn) — IPCC 2019 default",
    partial = "Partial (AR(1), ρ = 0.7)",
    none    = "Independent (no year-to-year correlation)"
  )
  rows <- list(
    c("Year range",              sprintf("%d – %d", yrs[1], yrs[2])),
    c("Iterations per year",     .fmt_int(n_iter)),
    c("Year-to-year correlation", yc_label),
    c("IPCC guidelines version",
      if (!is.null(ipcc_meta) && !is.null(ipcc_meta$ipcc_version))
        ipcc_meta$ipcc_version else "(not set)"),
    c("Region",
      if (!is.null(ipcc_meta) && !is.null(ipcc_meta$region) &&
          nzchar(ipcc_meta$region)) ipcc_meta$region else "(not set)")
  )
  df <- do.call(rbind.data.frame, c(rows, list(stringsAsFactors = FALSE)))
  names(df) <- c("Setting", "Value")
  flextable::flextable(df)
}

.imputed_flextable <- function(param_specs) {
  if (is.null(param_specs) || !"imputed" %in% names(param_specs)) return(NULL)
  flag <- param_specs$imputed
  flag[is.na(flag)] <- FALSE
  rows <- param_specs[as.logical(flag), , drop = FALSE]
  if (nrow(rows) == 0) return(NULL)

  cat_lookup <- PARAM_CATALOGUE[, c("parameter", "unit", "ipcc_ref")]
  names(cat_lookup)[2:3] <- c("unit_cat", "ipcc_ref_cat")
  rows <- merge(rows, cat_lookup, by = "parameter", all.x = TRUE, sort = FALSE)
  unit_user <- if ("unit" %in% names(rows)) rows$unit else rep(NA_character_, nrow(rows))
  ref_user  <- if ("ipcc_ref" %in% names(rows)) rows$ipcc_ref else rep(NA_character_, nrow(rows))

  pick <- function(primary, fallback) {
    out <- as.character(primary)
    miss <- is.na(out) | !nzchar(out)
    out[miss] <- as.character(fallback)[miss]
    out
  }

  df <- data.frame(
    Parameter        = rows$parameter,
    Value            = formatC(rows$mean, digits = 4, format = "g"),
    Unit             = pick(unit_user, rows$unit_cat),
    `IPCC ref`       = pick(ref_user,  rows$ipcc_ref_cat),
    Source           = if ("data_source" %in% names(rows)) rows$data_source
                       else rep("AUTO-FILLED (IPCC default)", nrow(rows)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  flextable::flextable(df)
}

.results_flextable <- function(uncertainty) {
  # Andreas 2026-05 #37, #39, C11: Section 4 must report every IPCC emission
  # source as its own row (was previously gas-only) and every numeric column
  # must carry its unit. Order matches IPCC Table 3.3 reporting flow.
  if (is.null(uncertainty) || !is.data.frame(uncertainty) || nrow(uncertainty) == 0) {
    return(flextable::flextable(data.frame(Note = "No uncertainty results available.")))
  }
  # Prefer per-system (singular) columns when present (rv$mc_results$by_system),
  # otherwise fall back to inventory totals (run_inventory_simulation output).
  primary_vars <- c("enteric_ch4_total", "manure_ch4_total",
                    "direct_n2o_mm_total", "indirect_n2o_mm_total",
                    "direct_n2o_prp_total", "indirect_n2o_prp_total",
                    "total_ch4", "total_n2o", "total_co2e")
  fallback_vars <- c("total_enteric_ch4", "total_manure_ch4",
                     "total_direct_n2o_mm", "total_indirect_n2o_mm",
                     "total_direct_n2o_prp", "total_indirect_n2o_prp",
                     "total_ch4", "total_n2o", "total_co2e")
  display_vars <- if (any(primary_vars %in% uncertainty$variable))
    primary_vars else fallback_vars
  keep <- uncertainty[match(display_vars, uncertainty$variable), , drop = FALSE]
  keep <- keep[!is.na(keep$variable), , drop = FALSE]
  if (nrow(keep) == 0) keep <- uncertainty

  # Andreas 28/5/26 #6: drop the CV column from the user-facing per-source
  # table so the Word report leads with 95% MoE — the IPCC Vol.1 Ch.3 Table
  # 3.3 convention. `cv_pct` is still in the underlying uncertainty frame for
  # any downstream consumer that wants it.
  # Andreas 2026-06-02 review: include the asymmetric half-widths
  # (+upper% / -lower%) alongside the symmetric MoE — many emission
  # distributions are skewed (lognormal EFs, PERT-bounded fractions,
  # manure-N2O sums) and reporting the two sides separately is what users
  # may need to populate the asymmetric-bounds version of IPCC Table 3.3.
  has_asym <- all(c("upper_pct", "lower_pct") %in% names(keep))
  df <- data.frame(
    `Emission category` = .pretty_var(keep$variable),
    Unit                = .unit_for_var(keep$variable),
    Mean                = formatC(keep$mean,     digits = 4, format = "g"),
    `CI lower`          = formatC(keep$ci_lower, digits = 4, format = "g"),
    `CI upper`          = formatC(keep$ci_upper, digits = 4, format = "g"),
    `MoE 95% (%)`       = formatC(keep$moe_pct,  digits = 3, format = "g"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (has_asym) {
    df[["+ upper (%)"]] <- formatC(keep$upper_pct, digits = 3, format = "g")
    df[["- lower (%)"]] <- formatC(keep$lower_pct, digits = 3, format = "g")
  }
  flextable::flextable(df)
}

.ipcc_flextable <- function(ipcc_table) {
  flextable::flextable(ipcc_table)
}

# Andreas 2026-05 C11 / 28/5/26 #6: per-reporting-category AD or EF
# uncertainty table for the Word exec summary. `kind` is "AD" or "EF" —
# picks the matching column from the IPCC summary table and trims to the
# per-source rows. The IPCC table columns were renamed to
# "AD uncertainty (95% MoE %)" / "EF uncertainty (95% MoE %)" so this
# helper matches them by suffix.
.ad_ef_flextable <- function(ipcc_table, kind = c("AD", "EF")) {
  kind <- match.arg(kind)
  if (is.null(ipcc_table) || !is.data.frame(ipcc_table) || nrow(ipcc_table) == 0)
    return(NULL)
  prefix <- if (kind == "AD") "AD uncertainty" else "EF uncertainty"
  cat_col <- "Emission category"
  col_idx <- which(startsWith(names(ipcc_table), prefix))
  if (length(col_idx) == 0 || !(cat_col %in% names(ipcc_table)))
    return(NULL)
  src_col <- names(ipcc_table)[col_idx[1]]
  source_rows <- !grepl("^Total ", ipcc_table[[cat_col]])
  df <- ipcc_table[source_rows, c(cat_col, "Gas", src_col), drop = FALSE]
  names(df)[3] <- if (kind == "AD") "AD uncertainty (95% MoE %)" else
                                    "EF uncertainty (95% MoE %)"
  if (nrow(df) == 0) return(NULL)
  flextable::flextable(df)
}

.trend_table_flextable <- function(trend_results) {
  # Andreas 28/5/26 #6: drop the CV column from the user-facing trend table
  # so MoE (the IPCC convention) is the only uncertainty metric shown. CV_pct
  # is still in `trend_results` for any consumer that wants it.
  cols <- intersect(
    c("Year", "Mean_t_CO2eq", "CI_Lower_t", "CI_Upper_t",
      "MoE_95_pct", "Delta_vs_base_pct", "YoY_pct"),
    names(trend_results)
  )
  df <- trend_results[, cols, drop = FALSE]
  pretty <- c(Year = "Year",
              Mean_t_CO2eq = "Mean (t CO2eq)",
              CI_Lower_t   = "CI lower",
              CI_Upper_t   = "CI upper",
              MoE_95_pct   = "95% MoE (%)",
              Delta_vs_base_pct = "Δ vs base (%)",
              YoY_pct      = "YoY (%)")
  names(df) <- pretty[names(df)]
  flextable::flextable(df)
}

.slope_delta_flextable <- function(slope, delta_total) {
  df <- data.frame(
    Metric = c("Trend slope (t CO2eq / yr)",
               "Δ total Y_N − Y_1 (t CO2eq)",
               "Δ percent (vs Y_1)"),
    Mean   = c(.fmt_signed(slope$mean, 0),
               .fmt_signed(delta_total$mean, 0),
               paste0(.fmt_signed(delta_total$pct_mean, 1), "%")),
    `95% CI lower` = c(.fmt_signed(slope$ci[1], 0),
                       .fmt_signed(delta_total$ci[1], 0),
                       paste0(.fmt_signed(delta_total$pct_ci[1], 1), "%")),
    `95% CI upper` = c(.fmt_signed(slope$ci[2], 0),
                       .fmt_signed(delta_total$ci[2], 0),
                       paste0(.fmt_signed(delta_total$pct_ci[2], 1), "%")),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  flextable::flextable(df)
}

.sensitivity_flextable <- function(sens, top_n = 10L) {
  if (is.null(sens) || length(sens) == 0) return(NULL)
  src  <- sens$src
  prcc <- sens$prcc
  if ((is.null(src)  || nrow(src) == 0) &&
      (is.null(prcc) || nrow(prcc) == 0)) return(NULL)

  base <- if (!is.null(src) && nrow(src) > 0) src else prcc
  val_col <- if ("src" %in% names(base)) "src"
             else if ("prcc" %in% names(base)) "prcc"
             else names(base)[2]
  base <- base[order(-abs(base[[val_col]])), , drop = FALSE]
  if (is.finite(top_n)) base <- utils::head(base, as.integer(top_n))

  src_disp  <- if ("src" %in% names(base))
                 formatC(base$src,  digits = 3, format = "f") else NULL
  prcc_disp <- if (!is.null(prcc) && "prcc" %in% names(prcc))
                 formatC(prcc$prcc[match(base$parameter, prcc$parameter)],
                         digits = 3, format = "f") else NULL

  df <- data.frame(Parameter = base$parameter, stringsAsFactors = FALSE)
  if (!is.null(src_disp))  df$SRC  <- src_disp
  if (!is.null(prcc_disp)) df$PRCC <- prcc_disp
  flextable::flextable(df)
}

# Round 9b §5 — Per-cattle-type / aggregation-level / sub-category breakdown.
# Mirrors the live results_by_system table at each aggregation level. Returns
# NULL if mc_results$by_system is missing; otherwise a named list of
# flextables keyed by the aggregation level.
.aggregated_results_flextable <- function(mc_results) {
  if (is.null(mc_results) || is.null(mc_results$by_system) ||
      length(mc_results$by_system) == 0) return(NULL)

  by_sys <- mc_results$by_system
  sys_names <- names(by_sys)
  if (length(sys_names) == 0) return(NULL)

  build_one <- function(level) {
    parts <- strsplit(sys_names, "\\|\\|", fixed = FALSE)
    idx <- switch(level, "cattle_type" = 1, "aggregation_level" = 2, "sub_category" = 3, 1)
    group_keys <- sapply(parts, function(p) {
      if (length(p) >= idx && nzchar(p[idx])) p[idx] else paste(p, collapse = " / ")
    })
    rows <- list()
    for (g in unique(group_keys)) {
      members <- sys_names[group_keys == g]
      frames <- lapply(members, function(sn) by_sys[[sn]]$results)
      combined <- frames[[1]]
      if (length(frames) > 1) {
        for (k in 2:length(frames)) {
          for (col in names(combined)) {
            combined[[col]] <- combined[[col]] + frames[[k]][[col]]
          }
        }
      }
      co2e <- combined$total_co2e
      if (is.null(co2e) || length(co2e) == 0) next
      m  <- mean(co2e)
      lo <- stats::quantile(co2e, 0.025, names = FALSE)
      hi <- stats::quantile(co2e, 0.975, names = FALSE)
      moe <- if (m > 0) ((hi - lo) / 2) / m * 100 else NA_real_
      # Andreas 28/5/26 #6: drop the CV column from this flextable so the
      # Word per-cattle-type / per-aggregation-level / per-sub-category
      # tables consistently lead with 95% MoE (IPCC convention).
      rows[[length(rows) + 1L]] <- data.frame(
        Group              = g,
        `Mean CH4 (t)`     = formatC(mean(combined$total_ch4), digits = 2, format = "f"),
        `Mean N2O (t)`     = formatC(mean(combined$total_n2o), digits = 4, format = "f"),
        `Mean CO2eq (t)`   = formatC(m, digits = 2, format = "f"),
        `CI lower (t CO2eq)` = formatC(lo, digits = 2, format = "f"),
        `CI upper (t CO2eq)` = formatC(hi, digits = 2, format = "f"),
        `MoE 95% (%)`      = formatC(moe, digits = 1, format = "f"),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
    if (length(rows) == 0) return(NULL)
    flextable::flextable(do.call(rbind, rows))
  }

  list(
    cattle_type       = build_one("cattle_type"),
    aggregation_level = build_one("aggregation_level"),
    sub_category      = build_one("sub_category")
  )
}

# Andreas 28/5/26 #7.2 + #7.3 — per-(cattle_type × emission source) breakdown
# with raw t CH4 / t N2O and t CO2eq side-by-side. Mirrors the in-app
# results_by_category table when the aggregation level is cattle_type.
.per_source_breakdown_flextable <- function(mc_results, gwp_version = "AR5") {
  if (is.null(mc_results) || is.null(mc_results$by_system) ||
      length(mc_results$by_system) == 0) return(NULL)
  by_sys <- mc_results$by_system
  sys_names <- names(by_sys)
  if (length(sys_names) == 0) return(NULL)

  parts <- strsplit(sys_names, "\\|\\|", fixed = FALSE)
  ct_keys <- sapply(parts, function(p) if (length(p) >= 1 && nzchar(p[1])) p[1] else "—")

  # Combine per-iteration frames within each cattle_type.
  cattle_types <- unique(ct_keys)
  agg <- list()
  for (ct in cattle_types) {
    members <- sys_names[ct_keys == ct]
    frames <- lapply(members, function(sn) by_sys[[sn]]$results)
    combined <- frames[[1]]
    if (length(frames) > 1) {
      for (k in 2:length(frames)) {
        for (col in names(combined)) {
          combined[[col]] <- combined[[col]] + frames[[k]][[col]]
        }
      }
    }
    agg[[ct]] <- combined
  }

  gwp_vals <- if (!is.null(GWP_VALUES[[gwp_version]])) GWP_VALUES[[gwp_version]] else GWP_VALUES[["AR5"]]
  g_ch4 <- gwp_vals$CH4
  g_n2o <- gwp_vals$N2O

  sources <- list(
    list(label = "Enteric fermentation CH4",        gas = "CH4", col = "enteric_ch4_total"),
    list(label = "Manure management CH4",           gas = "CH4", col = "manure_ch4_total"),
    list(label = "Manure management N2O direct",    gas = "N2O", col = "direct_n2o_mm_total"),
    list(label = "Manure management N2O indirect",  gas = "N2O", col = "indirect_n2o_mm_total"),
    list(label = "Pasture deposition N2O direct",   gas = "N2O", col = "direct_n2o_prp_total"),
    list(label = "Pasture deposition N2O indirect", gas = "N2O", col = "indirect_n2o_prp_total")
  )

  rows <- list()
  for (ct in names(agg)) {
    res <- agg[[ct]]
    for (s in sources) {
      raw <- res[[s$col]]
      if (is.null(raw) || all(raw == 0)) next
      co2e <- raw * (if (s$gas == "CH4") g_ch4 else g_n2o)
      m_raw  <- mean(raw)
      m_co2e <- mean(co2e)
      lo <- stats::quantile(co2e, 0.025, names = FALSE)
      hi <- stats::quantile(co2e, 0.975, names = FALSE)
      moe <- if (m_co2e > 0) ((hi - lo) / 2) / m_co2e * 100 else NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        `Cattle type`     = ct,
        Source            = s$label,
        `Mean (t CH4)`    = if (s$gas == "CH4") formatC(m_raw, digits = 3, format = "f") else "",
        `Mean (t N2O)`    = if (s$gas == "N2O") formatC(m_raw, digits = 4, format = "f") else "",
        `Mean (t CO2eq)`  = formatC(m_co2e, digits = 2, format = "f"),
        `MoE 95% (%)`     = formatC(moe, digits = 1, format = "f"),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) return(NULL)
  flextable::flextable(do.call(rbind, rows))
}

# Round 9b §13 — Input parameter documentation. Mirrors inputs_doc_table.
# Perf (2026-06): the input-documentation table is the single biggest driver of
# Word build time on large inventories — for the 32-sub-category Zambia run it is
# 576 rows, and officer's print.rdocx runs several whole-document regex passes
# whose cost scales with the table's WML size (~25 s of the ~33 s build). Cap the
# rows shown in the Word doc; the COMPLETE per-parameter listing ships in the
# "Input_Parameters" sheet of the Excel download (export_results_xlsx), which
# handles hundreds of rows instantly. WORD_INPUTS_MAX is shared with the
# truncation note in build_run_summary_docx().
WORD_INPUTS_MAX <- 80L
# Same idea for the section-9 sensitivity ranking (complete SRC/PRCC are in the
# Excel download's Sensitivity_SRC / Sensitivity_PRCC sheets).
WORD_SENS_MAX <- 50L

.inputs_doc_flextable <- function(param_specs, max_rows = WORD_INPUTS_MAX) {
  if (is.null(param_specs) || !is.data.frame(param_specs) || nrow(param_specs) == 0)
    return(NULL)
  keep <- intersect(c("cattle_type", "aggregation_level", "sub_category",
                      "parameter", "param_type", "mean", "uncertainty_pct",
                      "lower", "upper", "distribution", "data_source",
                      "ipcc_ref"),
                    names(param_specs))
  if (length(keep) == 0) return(NULL)
  df <- param_specs[, keep, drop = FALSE]
  if (is.finite(max_rows) && nrow(df) > max_rows)
    df <- utils::head(df, max_rows)
  # Round numeric columns for readability
  for (col in c("mean", "uncertainty_pct", "lower", "upper")) {
    if (col %in% names(df)) df[[col]] <- formatC(df[[col]], digits = 4, format = "g")
  }
  flextable::flextable(df)
}

# Round 9b §12 — MC diagnostics summary (badges as a table).
.diagnostics_flextable <- function(diagnostics) {
  if (is.null(diagnostics)) return(NULL)
  d <- diagnostics
  status_str <- function(val, warn, fail) {
    if (is.null(val) || is.na(val)) return("—")
    if (val < warn) "PASS" else if (val < fail) "WARN" else "FAIL"
  }
  skew_label <- if (is.null(d$skew_val) || is.na(d$skew_val)) "—"
                else if (abs(d$skew_val) < 0.5) "symmetric"
                else if (d$skew_val > 0)         "right-skewed (expected)"
                else                              "left-skewed"

  df <- data.frame(
    Check  = c("Iterations",
               "Precision (MCSE)",
               "Mean stability (1st vs 2nd half drift)",
               "95% CI stability (1st vs 2nd half drift)",
               "Distribution skew"),
    Value  = c(.fmt_int(d$n),
               sprintf("%.2f%% of mean", d$mcse_pct),
               sprintf("%.1f%%", d$drift_pct),
               sprintf("%.1f%%", d$ci_drift_pct),
               sprintf("%.2f (%s)", if (is.null(d$skew_val)) NA_real_ else d$skew_val, skew_label)),
    Status = c(if (!is.null(d$n) && d$n >= 10000) "PASS" else "WARN",
               status_str(d$mcse_pct,     0.5, 1),
               status_str(d$drift_pct,    2.0, 5),
               status_str(d$ci_drift_pct, 5.0, 10),
               "INFO"),
    stringsAsFactors = FALSE
  )
  flextable::flextable(df)
}

# ============================================================================
# ggplot helpers
# ============================================================================

.gg_total_co2e_hist <- function(mc_results) {
  if (is.null(mc_results) || is.null(mc_results$inventory)) return(NULL)
  inv <- mc_results$inventory
  if (!"total_co2e" %in% names(inv)) return(NULL)
  x <- inv$total_co2e
  if (length(x) == 0 || all(is.na(x))) return(NULL)
  # Stats from ALL iterations; histogram shape from a subsample (each MC draw is
  # i.i.d., so the first N rows are a valid subsample). Keeps the ggplot data
  # frame small so the Word render stays fast and light.
  q025 <- stats::quantile(x, 0.025, names = FALSE)
  q975 <- stats::quantile(x, 0.975, names = FALSE)
  mu   <- mean(x)
  xs   <- if (length(x) > 4000L) x[seq_len(4000L)] else x

  ggplot2::ggplot(data.frame(value = xs), ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(bins = 40, fill = .GREEN_MID, colour = "white") +
    ggplot2::geom_vline(xintercept = c(q025, q975),
                        linetype = "dashed", colour = "#C1121F") +
    ggplot2::geom_vline(xintercept = mu, colour = "black") +
    ggplot2::labs(x = "Total CO2eq (t CO2eq)", y = "Frequency") +
    ggplot2::theme_minimal(base_size = 10)
}

.gg_tornado <- function(sens) {
  if (is.null(sens) || length(sens) == 0) return(NULL)
  base <- if (!is.null(sens$src) && is.data.frame(sens$src) && nrow(sens$src) > 0) {
    sens$src
  } else if (!is.null(sens$prcc) && is.data.frame(sens$prcc) && nrow(sens$prcc) > 0) {
    sens$prcc
  } else NULL
  if (is.null(base)) return(NULL)
  val_col <- if ("src" %in% names(base)) "src" else "prcc"
  if (!val_col %in% names(base) || !"parameter" %in% names(base)) return(NULL)

  top <- utils::head(base[order(-abs(base[[val_col]])), , drop = FALSE], 10)
  top <- top[order(top[[val_col]]), , drop = FALSE]
  top$parameter <- factor(top$parameter, levels = top$parameter)

  # #35: when parameter names carry a "cattle_type | sub_category – param"
  # prefix (added by .aggregate_sensitivity), surface that in the subtitle.
  has_groups <- any(grepl(" \\| .+ \\u2013 | \\| .+ - | \\| .+ – ", as.character(top$parameter))) ||
                any(grepl(" \\| ", as.character(top$parameter), fixed = FALSE))
  subtitle <- if (has_groups) "Top 10 drivers across all cattle groups" else NULL

  # Bar-end value label: number formatted to 2 dp, placed just outside the
  # bar tip (hjust depends on sign so labels always sit on the bar's outer
  # edge, never overlap the axis line).
  top$lbl <- sprintf("%+.2f", top[[val_col]])
  top$lbl_hjust <- ifelse(top[[val_col]] >= 0, -0.15, 1.15)
  x_range <- range(top[[val_col]], na.rm = TRUE)
  x_pad   <- 0.18 * diff(x_range)

  ggplot2::ggplot(top, ggplot2::aes(x = .data[[val_col]], y = parameter,
                                     fill = .data[[val_col]] > 0)) +
    ggplot2::geom_col() +
    ggplot2::geom_text(ggplot2::aes(label = lbl, hjust = lbl_hjust),
                        size = 3.0, colour = "#1B4332") +
    ggplot2::scale_fill_manual(values = c(`TRUE` = .GREEN_MID, `FALSE` = "#C1121F"),
                                guide = "none") +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(add = c(x_pad, x_pad))) +
    ggplot2::labs(x = toupper(val_col), y = NULL, subtitle = subtitle) +
    ggplot2::theme_minimal(base_size = 10)
}

.gg_source_grid <- function(mc_results) {
  if (is.null(mc_results) || is.null(mc_results$inventory)) return(NULL)
  inv <- mc_results$inventory
  picks <- c(
    "Enteric CH4"           = "enteric_ch4_total",
    "Manure CH4"            = "manure_ch4_total",
    "Manure N2O (direct)"   = "direct_n2o_mm_total",
    "Manure N2O (indirect)" = "indirect_n2o_mm_total",
    "Pasture N2O (direct)"  = "direct_n2o_prp_total",
    "Pasture N2O (indirect)"= "indirect_n2o_prp_total",
    "Total CO2eq"           = "total_co2e"
  )
  parts <- list()
  for (lab in names(picks)) {
    col <- picks[[lab]]
    if (col %in% names(inv)) {
      v <- inv[[col]]
      if (length(v) > 0 && stats::sd(v, na.rm = TRUE) > 0) {
        # Subsample for the histogram (shape is stable; keeps the combined
        # long data frame small — up to 7 sources x n_iter otherwise).
        vs <- if (length(v) > 4000L) v[seq_len(4000L)] else v
        parts[[length(parts) + 1L]] <- data.frame(value = vs, source = lab)
      }
    }
  }
  if (length(parts) == 0) return(NULL)
  df <- do.call(rbind, parts)
  df$source <- factor(df$source, levels = unique(df$source))

  ggplot2::ggplot(df, ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(bins = 30, fill = .GREEN_MID, colour = "white") +
    ggplot2::facet_wrap(~ source, scales = "free", ncol = 3) +
    ggplot2::labs(x = NULL, y = "Frequency") +
    ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(strip.text = ggplot2::element_text(face = "bold"))
}

# Round 8: trend chart for the trend Word doc — line + 95% CI ribbon
.gg_trend_chart <- function(trend_results) {
  if (is.null(trend_results) || nrow(trend_results) == 0) return(NULL)
  ggplot2::ggplot(trend_results,
                   ggplot2::aes(x = Year, y = Mean_t_CO2eq)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = CI_Lower_t, ymax = CI_Upper_t),
                          fill = .GREEN_MID, alpha = 0.25) +
    ggplot2::geom_line(colour = .GREEN_DARK, linewidth = 1) +
    ggplot2::geom_point(colour = .GREEN_DARK, size = 2.5) +
    ggplot2::labs(x = "Inventory year", y = "Total CO2eq (t)",
                   title = "Trend in total CO2eq emissions (95% CI)") +
    ggplot2::theme_minimal(base_size = 10)
}

# Round 9b §6 — AD / EF / Combined 95 % MoE for total CO2eq, total CH4,
# total N2O. Mirrors output$decomposition_plot in app_server.R.
# Andreas 28/5/26 #6: switched from cv_pct to moe_pct so the Word report
# tracks the IPCC reporting convention (Vol.1 Ch.3 Table 3.3).
.gg_decomposition <- function(decomp) {
  if (is.null(decomp)) return(NULL)
  need <- c("ad_only", "ef_only", "combined")
  if (!all(need %in% names(decomp))) return(NULL)
  vars   <- c("total_co2e", "total_ch4", "total_n2o")
  labels <- c("Total CO2eq", "Total CH4", "Total N2O")
  rows <- list()
  for (cat in c("AD only", "EF only", "Combined")) {
    df <- switch(cat,
      "AD only"  = decomp$ad_only,
      "EF only"  = decomp$ef_only,
      "Combined" = decomp$combined)
    if (is.null(df) || !is.data.frame(df) || !"variable" %in% names(df)) next
    for (i in seq_along(vars)) {
      r <- df[df$variable == vars[i], , drop = FALSE]
      if (nrow(r) > 0 && !is.na(r$moe_pct[1])) {
        rows[[length(rows) + 1L]] <- data.frame(
          category = cat, variable = labels[i], moe_pct = r$moe_pct[1],
          stringsAsFactors = FALSE)
      }
    }
  }
  if (length(rows) == 0) return(NULL)
  df <- do.call(rbind, rows)
  df$category <- factor(df$category, levels = c("AD only", "EF only", "Combined"))
  df$variable <- factor(df$variable, levels = labels)

  df$lbl <- sprintf("%.1f%%", df$moe_pct)
  ggplot2::ggplot(df, ggplot2::aes(x = variable, y = moe_pct, fill = category)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = lbl),
                        position = ggplot2::position_dodge(width = 0.75),
                        vjust = -0.4, size = 3.0, colour = "#1B4332") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::scale_fill_manual(values = c("AD only"  = "#40916C",
                                            "EF only"  = "#4361EE",
                                            "Combined" = .GREEN_DARK),
                                 name = NULL) +
    ggplot2::labs(x = NULL, y = "95% MoE (%)",
                   title = "Uncertainty decomposition: AD vs EF vs Combined") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")
}

# Round 9b §7 — Effect of correlations on 95 % MoE (with vs without).
# Mirrors output$comparison_plot. Reads the live uncertainty frame and the
# comparison-run uncertainty frame. Andreas 28/5/26 #6: cv_pct → moe_pct.
.gg_comparison <- function(uncertainty_with, uncertainty_without) {
  if (is.null(uncertainty_with)  || !is.data.frame(uncertainty_with)  || nrow(uncertainty_with)  == 0)
    return(NULL)
  if (is.null(uncertainty_without)|| !is.data.frame(uncertainty_without)|| nrow(uncertainty_without) == 0)
    return(NULL)
  vars   <- c("total_co2e", "total_ch4", "total_n2o")
  labels <- c("Total CO2eq", "Total CH4", "Total N2O")
  pull <- function(df, v) {
    r <- df[df$variable == v, , drop = FALSE]
    if (nrow(r) > 0) r$moe_pct[1] else NA_real_
  }
  with_moe    <- vapply(vars, pull, numeric(1), df = uncertainty_with)
  without_moe <- vapply(vars, pull, numeric(1), df = uncertainty_without)
  df <- data.frame(
    variable = factor(rep(labels, 2), levels = labels),
    scenario = factor(rep(c("With correlations", "Without correlations"), each = length(vars)),
                       levels = c("With correlations", "Without correlations")),
    moe_pct  = c(with_moe, without_moe),
    stringsAsFactors = FALSE
  )
  df <- df[!is.na(df$moe_pct), , drop = FALSE]
  if (nrow(df) == 0) return(NULL)

  df$lbl <- sprintf("%.1f%%", df$moe_pct)
  ggplot2::ggplot(df, ggplot2::aes(x = variable, y = moe_pct, fill = scenario)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = lbl),
                        position = ggplot2::position_dodge(width = 0.75),
                        vjust = -0.4, size = 3.0, colour = "#1B4332") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::scale_fill_manual(values = c("With correlations"    = .GREEN_DARK,
                                            "Without correlations" = "#9CA3AF"),
                                 name = NULL) +
    ggplot2::labs(x = NULL, y = "95% MoE (%)",
                   title = "Effect of correlations on uncertainty (95% MoE)") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")
}

# Round 9b §11 — Per-parameter density plots (up to 12). Mirrors the live
# output$report_input_densities. Takes the first by_system block's `samples`
# data frame (parameter columns, n_iter rows).
.gg_input_densities <- function(samples_df, n_max = 12) {
  if (is.null(samples_df) || !is.data.frame(samples_df) || ncol(samples_df) == 0)
    return(NULL)
  keep <- utils::head(colnames(samples_df), n_max)
  long <- do.call(rbind, lapply(keep, function(p) {
    x <- samples_df[[p]]
    if (length(x) == 0 || all(is.na(x))) return(NULL)
    if (stats::sd(x, na.rm = TRUE) == 0) return(NULL)
    data.frame(parameter = p, value = x, stringsAsFactors = FALSE)
  }))
  if (is.null(long) || nrow(long) == 0) return(NULL)
  long$parameter <- factor(long$parameter, levels = keep[keep %in% unique(long$parameter)])

  ncol_panels <- if (length(unique(long$parameter)) <= 6) 3 else 4
  ggplot2::ggplot(long, ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(ggplot2::aes(y = ggplot2::after_stat(density)),
                              bins = 25, fill = .GREEN_MID, colour = "white") +
    ggplot2::facet_wrap(~ parameter, scales = "free", ncol = ncol_panels) +
    ggplot2::labs(x = NULL, y = "Density",
                   title = "Sampled parameter distributions (QA check)") +
    ggplot2::theme_minimal(base_size = 8) +
    ggplot2::theme(strip.text = ggplot2::element_text(face = "bold"))
}

# Round 9b §12 — MC convergence: running mean + 2.5/97.5% bands across
# iterations. Mirrors output$convergence_plot. Reads rv$diagnostics$trace.
.gg_convergence <- function(diagnostics) {
  if (is.null(diagnostics) || is.null(diagnostics$trace)) return(NULL)
  tr <- diagnostics$trace
  if (length(tr$iter) == 0) return(NULL)
  df <- data.frame(
    iter         = tr$iter,
    running_mean = tr$running_mean,
    running_lo   = tr$running_lo,
    running_hi   = tr$running_hi,
    stringsAsFactors = FALSE
  )

  ggplot2::ggplot(df, ggplot2::aes(x = iter)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = running_lo, ymax = running_hi),
                          fill = "#3B82F6", alpha = 0.12) +
    ggplot2::geom_line(ggplot2::aes(y = running_lo),
                        colour = "#3B82F6", linetype = "dashed", linewidth = 0.5) +
    ggplot2::geom_line(ggplot2::aes(y = running_hi),
                        colour = "#3B82F6", linetype = "dashed", linewidth = 0.5) +
    ggplot2::geom_line(ggplot2::aes(y = running_mean),
                        colour = .GREEN_DARK, linewidth = 1) +
    ggplot2::geom_hline(yintercept = tr$final_mean,
                         colour = .GREEN_DARK, linetype = "dashed", linewidth = 0.5) +
    ggplot2::labs(x = "Iteration number", y = "Total CO2eq (t)",
                   title = "Monte Carlo convergence (running mean and 95% CI)") +
    ggplot2::theme_minimal(base_size = 10)
}

# Round 9b §3a — Year-over-year % change bar chart for the trend report.
# Mirrors output$trend_yoy_chart.
.gg_yoy_chart <- function(trend_results) {
  if (is.null(trend_results) || !"YoY_pct" %in% names(trend_results)) return(NULL)
  df <- trend_results[!is.na(trend_results$YoY_pct), , drop = FALSE]
  if (nrow(df) == 0) return(NULL)
  df$sign <- df$YoY_pct >= 0
  df$lbl  <- sprintf("%+.1f%%", df$YoY_pct)
  ggplot2::ggplot(df, ggplot2::aes(x = factor(Year), y = YoY_pct, fill = sign)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = lbl,
                                      vjust = ifelse(YoY_pct >= 0, -0.4, 1.3)),
                        size = 3.0, colour = "#1B4332") +
    ggplot2::geom_hline(yintercept = 0, colour = "#555", linewidth = 0.5) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.12, 0.12))) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = .GREEN_MID, `FALSE` = "#C1121F"),
                                guide = "none") +
    ggplot2::labs(x = "Year", y = "Δ vs prior year (%)",
                   title = "Year-over-year % change") +
    ggplot2::theme_minimal(base_size = 10)
}

# Round 9b §3b — Distribution of Δ Y_N − Y_1 from the per-iteration delta
# samples. Mirrors output$trend_delta_histogram.
.gg_delta_distribution <- function(delta_total) {
  if (is.null(delta_total) || is.null(delta_total$per_iter)) return(NULL)
  x <- delta_total$per_iter
  if (length(x) == 0 || all(is.na(x))) return(NULL)
  ci  <- stats::quantile(x, c(0.025, 0.975), names = FALSE, na.rm = TRUE)
  fill_col <- if (mean(x, na.rm = TRUE) >= 0) .GREEN_MID else "#C1121F"

  ggplot2::ggplot(data.frame(value = x), ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(bins = 40, fill = fill_col, colour = "white") +
    ggplot2::geom_vline(xintercept = ci, linetype = "dashed", colour = "#C1121F") +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted", colour = "#555") +
    ggplot2::geom_vline(xintercept = mean(x, na.rm = TRUE), colour = "black") +
    ggplot2::labs(x = "ΔCO2eq (t) between Y_N and Y_1", y = "Frequency",
                   title = "Distribution of ΔY_N − Y_1 — uncertainty on the trend itself") +
    ggplot2::theme_minimal(base_size = 10)
}
