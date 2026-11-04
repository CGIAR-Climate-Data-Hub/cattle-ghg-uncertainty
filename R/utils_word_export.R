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
  # Alternating row backgrounds (skip if fewer than 2 body rows: seq() would
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

# Headings: use officer's default 'heading N' styles (which Word renders with
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
# PNG's true aspect ratio (so none is stretched: the climate-action wordmark is
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
  if (is.null(x) || length(x) == 0 || is.na(x)) return("n/a")
  formatC(x, digits = digits, format = "f", big.mark = ",")
}

.fmt_signed <- function(x, digits = 1) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("n/a")
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
  # own row in the Word Section 4 table: including pasture direct and
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
# SINGLE-YEAR REPORT: build_run_summary_docx() (redesigned)
# ============================================================================

# 2026-11-02 (Lolita): every figure of the Word reports has a number and a
# title above it and a caption below it; the chart's own title is dropped
# so it is not said twice. One adder per report keeps its own count.
.make_fig_adder <- function() {
  k <- 0L
  function(doc, gg, title, caption, width = 5.5, height = 3.2) {
    if (is.null(gg)) return(doc)
    k <<- k + 1L
    doc <- officer::body_add_fpar(doc, officer::fpar(
      officer::ftext(sprintf("Figure %d. %s", k, title), prop = officer::fp_text(
        bold = TRUE, font.size = 10, color = .GREEN_DARK, font.family = "Calibri")),
      fp_p = officer::fp_par(padding.top = 8, padding.bottom = 2, keep_with_next = TRUE)))
    # 2026-11-02: 150 dpi (officer's default is 300). At 5.5 inches that is
    # 825 pixels, sharp on screen and in print, and it roughly quarters the
    # memory of each chart while the report is built (a test-inventory trend report
    # peaked at 884 MB locally at 300 dpi; the server has 1 GB).
    doc <- officer::body_add_gg(doc, value = gg + ggplot2::labs(title = NULL), width = width, height = height,
                                res = 150)
    invisible(gc(FALSE))
    officer::body_add_fpar(doc, officer::fpar(
      officer::ftext(caption, prop = officer::fp_text(
        italic = TRUE, font.size = 9, color = "#4B5563", font.family = "Calibri")),
      fp_p = officer::fp_par(padding.bottom = 10)))
  }
}

build_run_summary_docx <- function(path,
                                   settings,
                                   param_specs,
                                   mc_results,
                                   uncertainty,
                                   sensitivity = NULL,
                                   ipcc_table  = NULL,
                                   ipcc_by_type = NULL,
                                   ipcc_meta   = NULL,
                                   decomposition          = NULL,
                                   comparison_uncertainty = NULL,
                                   comparison_levels      = NULL,
                                   diagnostics            = NULL,
                                   samples_for_density    = NULL,
                                   app_version = NULL,
                                   qa_caveats  = NULL,
                                   manure      = NULL) {

  doc <- officer::read_docx()

  # ---- Title block --------------------------------------------------------
  doc <- .add_h1(doc, "Cattle GHG Tier 2 Uncertainty: single-year run")
  meta_line <- paste(
    sprintf("Generated %s.", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$ipcc_version))
      sprintf("IPCC guidelines: %s.", ipcc_meta$ipcc_version) else NULL,
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$region) && nzchar(ipcc_meta$region))
      sprintf("Region: %s.", ipcc_meta$region) else NULL,
    "Approach 2 Monte Carlo simulation per IPCC Vol 1 Ch 3."
  )
  doc <- .add_p(doc, paste(stats::na.omit(meta_line), collapse = " "))

  # 2026-11-02 (Lolita: "really messy, doesn't make sense why things are in
  # this order"). The report now reads in the order of the work: a short
  # summary; 1. what was run (settings, then whether the run was long
  # enough); 2. the inputs (gaps filled, placeholder ranges, checks waved
  # through, the sampled distributions, the full input table); 3. the
  # results (by source with their charts, IPCC Table 3.3 and its AD / EF
  # split, by group, the effect of correlations); 4. what drives the
  # uncertainty (tornado and ranking). The IPCC reporting notes part was
  # removed on 2026-11-02 (Lolita: "remove ipcc reporting notes").
  # Wide tables sit on landscape pages: a portrait break closes the
  # portrait text before them, a landscape break closes the table.
  num <- local({ part <- 0L; sub <- 0L
    list(part = function(doc, title) { part <<- part + 1L; sub <<- 0L
                                        .add_h2(doc, sprintf("%d. %s", part, title)) },
         sub  = function(doc, title) { sub <<- sub + 1L
                                        .add_h3(doc, sprintf("%d.%d %s", part, sub, title)) })
  })
  fig <- .make_fig_adder()

  # ---- Summary ------------------------------------------------------------
  doc <- .add_h2(doc, "Summary")
  doc <- .add_p(doc, .build_single_exec_summary(uncertainty, sensitivity, settings))
  doc <- .add_p(doc, paste(
    "The report has four parts: the simulation, the inputs, the results",
    "and the sensitivity analysis.", trimws(.sources_sentence(settings$emission_sources))))

  # ---- 1. What was run ----------------------------------------------------
  doc <- num$part(doc, "Simulation")
  doc <- num$sub(doc, "Run settings")
  doc <- .add_flextable_safe(doc, .styled_flextable(.settings_flextable(settings)))

  conv_plot <- .gg_convergence(diagnostics)
  diag_ft   <- .diagnostics_flextable(diagnostics)
  if (!is.null(conv_plot) || !is.null(diag_ft)) {
    doc <- num$sub(doc, "Monte Carlo diagnostics")
    doc <- .add_p(doc,
      "Quality checks on the Monte Carlo run. PASS means the reported mean and 95% confidence interval do not depend on the random seed; WARN or FAIL means the run should be repeated with more iterations.")
    if (!is.null(diag_ft)) doc <- .add_flextable_safe(doc, .styled_flextable(diag_ft))
    doc <- fig(doc, conv_plot, "Convergence of the simulation",
      "Running mean of total CO2eq (solid line) and running 2.5th and 97.5th percentiles (dashed lines) as iterations are added. Lines that are flat at the right edge show that the simulation ran long enough.",
      height = 3.0)
  }

  # ---- 2. Inputs ----------------------------------------------------------
  doc <- num$part(doc, "Inputs")
  imputed_ft <- .imputed_flextable(param_specs)
  if (!is.null(imputed_ft)) {
    doc <- num$sub(doc, "IPCC default parameters")
    doc <- .add_p(doc,
      "These parameters were not in the upload and were filled with IPCC defaults so the simulation could run. Replace them with country-specific data when available.")
    doc <- .add_flextable_safe(doc, .styled_flextable(imputed_ft))
  }

  doc <- .add_placeholder_section(doc, param_specs, manure, "Placeholder uncertainty ranges",
                                  heading_fn = num$sub)

  if (!is.null(qa_caveats) && is.data.frame(qa_caveats) && nrow(qa_caveats) > 0) {
    doc <- num$sub(doc, "QA/QC caveats")
    doc <- .add_p(doc, paste0(
      "The compiler chose to run with ", nrow(qa_caveats),
      " QA/QC failure(s) unresolved. \"ignored\" means the input was used as ",
      "uploaded despite the failed check; \"repaired\" means the tool applied ",
      "the smallest change that lets the sampler run (bounds widened to bracket ",
      "the mean, or an unsuitable distribution replaced by normal). Results that ",
      "depend on these inputs should be treated as provisional."))
    doc <- .add_flextable_safe(doc, .styled_flextable(flextable::flextable(qa_caveats)))
  }

  density_plot <- .gg_input_densities(samples_for_density)
  if (!is.null(density_plot)) {
    doc <- num$sub(doc, "Input distributions")
    doc <- fig(doc, density_plot, "Sampled input distributions",
      "Histograms of the values drawn for up to 12 inputs of the first group. Use them to confirm that the distributions have the expected shape, especially for inputs with a non-normal distribution or asymmetric bounds.",
      width = 6.5, height = 4.5)
  }

  inputs_ft <- .inputs_doc_flextable(param_specs)
  if (!is.null(inputs_ft)) {
    doc <- .add_portrait_break(doc)
    doc <- num$sub(doc, "Input parameters")
    total_params <- nrow(param_specs)
    if (is.data.frame(param_specs) && total_params > WORD_INPUTS_MAX) {
      doc <- .add_p(doc, sprintf(
        paste0("The first %d of %s parameter rows: distribution, mean, bounds and IPCC reference. ",
               "Every row is in the Input_Parameters sheet of the Excel download."),
        WORD_INPUTS_MAX, format(total_params, big.mark = ",")))
    } else {
      doc <- .add_p(doc,
        "Every parameter used in this run: distribution, mean, bounds and IPCC reference.")
    }
    doc <- .add_flextable_safe(doc, .styled_flextable(inputs_ft))
    doc <- .add_landscape_break(doc)
  }

  # ---- 3. Results ---------------------------------------------------------
  doc <- num$part(doc, "Results")
  doc <- num$sub(doc, "Emissions by source")
  doc <- .add_p(doc,
    "Mean emissions of each IPCC reporting line with the 95% confidence interval and the 95% margin of error (MoE, half the width of the interval as a percentage of the mean), and its lower and upper halves.")
  doc <- .add_flextable_safe(doc, .styled_flextable(.results_flextable(uncertainty)))
  hist_plot <- .gg_total_co2e_hist(mc_results)
  doc <- fig(doc, hist_plot, "Emission distribution (total CO2eq)",
    "Each bar counts the iterations whose total CO2eq fell in that range. The dashed red lines are the 2.5th and 97.5th percentiles, the bounds of the 95% confidence interval; the black line is the mean.",
    height = 3.0)
  src_plot <- .gg_source_grid(mc_results)
  doc <- fig(doc, src_plot, "Emission distribution by source",
    "The distribution of each emission source over the iterations, in tonnes of CH4 or N2O.",
    height = 4.0)

  has_ipcc <- !is.null(ipcc_table) && is.data.frame(ipcc_table) && nrow(ipcc_table) > 0
  if (has_ipcc) {
    doc <- .add_portrait_break(doc)
    doc <- num$sub(doc, "IPCC Table 3.3")
    doc <- .add_p(doc,
      "For each reporting line: the uncertainty when only the activity data vary (AD), when only the emission factors and coefficients vary (EF), and when both vary (combined, the figure reported in Table 3.3), as 95% MoE.")
    doc <- .add_flextable_safe(doc, .styled_flextable(.ipcc_flextable(ipcc_table)))
    # 2026-11-04: the same table by cattle type, when the run has both
    if (is.data.frame(ipcc_by_type) && length(unique(ipcc_by_type[["Cattle type"]])) > 1L) {
      doc <- num$sub(doc, "IPCC Table 3.3 by cattle type")
      doc <- .add_p(doc,
        "The same lines for dairy and non-dairy cattle separately, for countries that report the two types apart (reporting codes 3.A.1.a and 3.A.1.b, 3.B.1.a and 3.B.1.b). Each type's uncertainty is computed from the draws of its own groups, summed within the type.")
      doc <- .add_flextable_safe(doc, .styled_flextable(.ipcc_flextable(ipcc_by_type)))
    }
    doc <- .add_landscape_break(doc)
    decomp_plot <- .gg_decomposition(decomposition)
    doc <- fig(doc, decomp_plot, "Uncertainty from activity data and emission factors",
      "Margin of error (MoE: half the width of the 95% confidence interval, as a percentage of the mean) of total CO2eq, CH4 and N2O when only the activity data vary, when only the emission factors and coefficients vary, and when both vary. The combined bar is the reported uncertainty.")
  }

  agg_fts <- .aggregated_results_flextable(mc_results)
  ps_ft   <- .per_source_breakdown_flextable(mc_results, settings$gwp_version)
  if (!is.null(agg_fts) || !is.null(ps_ft)) {
    doc <- num$sub(doc, "Results by group")
    doc <- .add_p(doc,
      "The results aggregated by cattle type, production system and sub-category, to show which groups drive the totals above.")
    if (!is.null(agg_fts)) for (lvl in c("cattle_type", "aggregation_level", "sub_category")) {
      ft <- agg_fts[[lvl]]
      if (is.null(ft)) next
      doc <- .add_p(doc, switch(lvl, cattle_type = "By cattle type:",
                                aggregation_level = "By production system:",
                                sub_category = "By sub-category:"))
      doc <- .add_flextable_safe(doc, .styled_flextable(ft))
    }
    if (!is.null(ps_ft)) {
      doc <- .add_p(doc,
        "By cattle type and emission source, in tonnes of CH4 or N2O and in tonnes CO2eq:")
      doc <- .add_flextable_safe(doc, .styled_flextable(ps_ft))
    }
  }

  comp_plot <- .gg_comparison_levels(comparison_levels)
  if (is.null(comp_plot)) comp_plot <- .gg_comparison(uncertainty, comparison_uncertainty)
  if (!is.null(comp_plot)) {
    doc <- num$sub(doc, "Effect of correlations")
    doc <- fig(doc, comp_plot, "Uncertainty by correlation level",
      "95% margin of error of total CO2eq, CH4 and N2O with no correlations, then with each choice of the Correlations tab added in turn; the last bar is the reported run. The change from the previous level is written on each bar, in percentage points. A rise means the correlations widen the uncertainty, a fall that they narrow it.",
      height = 3.2)
  }

  # ---- 4. What drives the uncertainty --------------------------------------
  tornado_plot <- .gg_tornado(sensitivity)
  n_sens <- if (!is.null(sensitivity$src)) nrow(sensitivity$src) else 0L
  full_sens_ft <- .sensitivity_flextable(sensitivity, top_n = WORD_SENS_MAX)
  if (!is.null(tornado_plot) || !is.null(full_sens_ft)) {
    doc <- num$part(doc, "Sensitivity analysis")
    doc <- .add_p(doc,
      "The standardised regression coefficient (SRC) of each input against total CO2eq, from -1 to +1: the further from zero, the more the input drives the uncertainty. The inputs at the top are where better national data reduce the uncertainty most.")
    if (!is.null(tornado_plot)) {
      doc <- num$sub(doc, "Top 10 drivers")
      doc <- fig(doc, tornado_plot, "Top 10 drivers of the uncertainty of total CO2eq (SRC)",
        "The ten inputs with the largest influence on total CO2eq. Bar length is the sensitivity coefficient (SRC); bars to the right raise the output, bars to the left lower it. Green: inputs you can improve with better national data. Blue: IPCC coefficients.",
        height = 4.0)
    }
    if (!is.null(full_sens_ft)) {
      doc <- num$sub(doc, "SRC ranking")
      doc <- .add_p(doc, if (is.finite(n_sens) && n_sens > WORD_SENS_MAX)
                           sprintf("The %d largest drivers, of %d inputs.", WORD_SENS_MAX, n_sens)
                         else "Every input, by decreasing absolute SRC.")
      if (is.finite(n_sens) && n_sens > WORD_SENS_MAX)
        doc <- .add_p(doc, "The complete ranking is in the Sensitivity_SRC sheet of the Excel download.")
      doc <- .add_flextable_safe(doc, .styled_flextable(full_sens_ft))
    }
  }

  # ---- Footer -------------------------------------------------------------
  doc <- .add_p(doc, "")
  doc <- .add_logo_footer(doc)
  footer_bits <- c(
    "Generated by Cattle GHG Uncertainty Calculator",
    if (!is.null(app_version)) sprintf("v%s", app_version) else NULL,
    sprintf("on %s.", format(Sys.Date(), "%Y-%m-%d")),
    "CGIAR Alliance / Bioversity-CIAT, funded by the Global Methane Hub."
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
    return("Total CO2eq could not be summarised: no result row found.")
  }
  m   <- total_row$mean
  lo  <- total_row$ci_lower
  hi  <- total_row$ci_upper
  moe <- total_row$moe_pct

  # Top driver from sensitivity (SRC if available)
  driver_text <- ""
  base <- if (!is.null(sensitivity$src) && nrow(sensitivity$src) > 0) sensitivity$src
          else NULL
  if (!is.null(base) && nrow(base) > 0) {
    val_col <- "src"
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
# TREND REPORT: build_trend_summary_docx() (new, Round 8)
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
                                      app_version = NULL,
                                      # 2026-10-22: what to report and the
                                      # IPCC reporting table for the chosen
                                      # base year and year t
                                      headline    = NULL,
                                      ipcc_table  = NULL,
                                      compare     = NULL,
                                      manure      = NULL,
                                     corr_settings = NULL,
                                     ipcc_by_type = NULL,
                                     change_draws = NULL,
                                     diagnostics = NULL) {

  doc <- officer::read_docx()
  yrs <- if (!is.null(years)) range(years) else range(trend_results$Year)

  # ---- Title block --------------------------------------------------------
  doc <- .add_h1(doc, sprintf("Cattle GHG Tier 2 Uncertainty: trend %d to %d",
                                yrs[1], yrs[2]))
  meta_line <- paste(
    sprintf("Generated %s.", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$ipcc_version))
      sprintf("IPCC guidelines: %s.", ipcc_meta$ipcc_version) else NULL,
    if (!is.null(ipcc_meta) && !is.null(ipcc_meta$region) && nzchar(ipcc_meta$region))
      sprintf("Region: %s.", ipcc_meta$region) else NULL,
    "Approach 2 Monte Carlo per IPCC Vol 1 Ch 3 §3.2.2.4 + §3.7."
  )
  doc <- .add_p(doc, paste(stats::na.omit(meta_line), collapse = " "))

  # 2026-11-02 (Lolita: "same comment for the word"). The trend report now
  # reads in the order of the single-year report: summary; 1. simulation
  # (settings, Monte Carlo diagnostics); 2. inputs; 3. results (base year
  # and year t with IPCC Table 3.3, every year, the change between the
  # first and last year); 4. sensitivity analysis (notes part removed
  # 2026-11-02).
  num <- local({ part <- 0L; sub <- 0L
    list(part = function(doc, title) { part <<- part + 1L; sub <<- 0L
                                        .add_h2(doc, sprintf("%d. %s", part, title)) },
         sub  = function(doc, title) { sub <<- sub + 1L
                                        .add_h3(doc, sprintf("%d.%d %s", part, sub, title)) })
  })
  fig <- .make_fig_adder()

  # ---- Summary ------------------------------------------------------------
  doc <- .add_h2(doc, "Summary")
  # 2026-11-04 (review of the new version): the figures a country reports
  # first, from the paired run of the two chosen years, the same numbers as
  # the app's headline cards; then the driver and the basis of the run.
  if (!is.null(headline)) for (line in .trend_headline_sentences(headline)) doc <- .add_p(doc, line)
  doc <- .add_p(doc, .build_trend_exec_summary(headline, sensitivity_delta, year_corr, n_iter))
  doc <- .add_p(doc, paste(
    "The report has four parts: the simulation, the inputs, the results",
    "and the sensitivity analysis.", trimws(.sources_sentence(corr_settings$emission_sources))))

  # ---- 1. Simulation --------------------------------------------------------
  doc <- num$part(doc, "Simulation")
  doc <- num$sub(doc, "Run settings")
  doc <- .add_flextable_safe(doc,
    .styled_flextable(.trend_settings_flextable(year_corr, n_iter, yrs, ipcc_meta, headline$n_iter_pair,
                                                 corr_settings = corr_settings)))
  if (!is.null(diagnostics) && !is.null(diagnostics$year_t)) {
    doc <- num$sub(doc, "Monte Carlo diagnostics")
    doc <- .add_p(doc, sprintf(paste(
      "Quality checks on the paired run of the base year and year t (%s draws each). PASS means the reported",
      "figures do not depend on the random seed; WARN or FAIL means the run should be repeated with more draws."),
      .fmt_int(diagnostics$year_t$n)))
    yt <- .diagnostics_flextable(diagnostics$year_t)
    if (!is.null(yt)) {
      doc <- .add_p(doc, sprintf("Year t total (%s):", diagnostics$years[2]))
      doc <- .add_flextable_safe(doc, .styled_flextable(yt))
    }
    ch <- .diagnostics_flextable(diagnostics$delta)
    if (!is.null(ch)) {
      doc <- .add_p(doc, sprintf("Change from %s to %s (percentages relative to the year t total):",
                                 diagnostics$years[1], diagnostics$years[2]))
      doc <- .add_flextable_safe(doc, .styled_flextable(ch))
    }
    doc <- fig(doc, .gg_convergence(diagnostics$year_t), "Convergence of the simulation (year t)",
      "Running mean of the year t total (solid line) and running 2.5th and 97.5th percentiles (dashed lines) as draws are added. Lines that are flat at the right edge show that the run was long enough.",
      height = 3.0)
  }

  # ---- 2. Inputs ------------------------------------------------------------
  doc <- num$part(doc, "Inputs")
  doc <- .add_placeholder_section(doc, param_specs, manure, "Placeholder uncertainty ranges",
                                  heading_fn = num$sub)
  inputs_ft <- .inputs_doc_flextable(param_specs)
  if (!is.null(inputs_ft)) {
    doc <- .add_portrait_break(doc)
    doc <- num$sub(doc, "Input parameters")
    total_params <- if (is.data.frame(param_specs)) nrow(param_specs) else 0L
    doc <- .add_p(doc, paste(
      if (total_params > WORD_INPUTS_MAX)
        sprintf("The first %d of %s parameter rows; every row is in the Input_Parameters sheet of the Excel download.",
                WORD_INPUTS_MAX, format(total_params, big.mark = ","))
      else "Every parameter used in the trend run: distribution, mean, bounds and IPCC reference.",
      "Animal numbers are drawn for each year; the coefficients follow the year-to-year correlation in section 1."))
    doc <- .add_flextable_safe(doc, .styled_flextable(inputs_ft))
    doc <- .add_landscape_break(doc)
  }

  # ---- 3. Results -----------------------------------------------------------
  # 2026-11-04: what a country reports first (the two chosen years, the
  # change and its uncertainty, IPCC Table 3.3, by cattle type), then the
  # whole series.
  doc <- num$part(doc, "Results")
  if (!is.null(headline)) {
    doc <- num$sub(doc, sprintf("Base year %d and year t %d", headline$base_year, headline$year_t))
    if (!is.null(compare)) {
      doc <- .add_p(doc, "The two years side by side, by emission source:")
      doc <- .add_flextable_safe(doc, .styled_flextable(.trend_compare_flextable(compare)))
    }
    if (length(change_draws) > 10) {
      hw <- (headline$trend_hi_pp - headline$trend_lo_pp) / 2
      doc <- fig(doc, .gg_change_hist(change_draws, headline),
        sprintf("How certain is the change from %d to %d?", headline$base_year, headline$year_t),
        sprintf(paste("Change in total emissions between the two years, draw by draw, in percent of the base year. The solid line is the mean change (%s%%),",
                      "the dashed lines the 95%% interval (%s%% to %s%%); half its width, %s percentage points, is the uncertainty of the change reported in IPCC Table 3.3."),
                .fmt_signed(headline$trend_pct, 1), .fmt_signed(headline$trend_lo_pct, 1),
                .fmt_signed(headline$trend_hi_pct, 1), formatC(hw, digits = 1, format = "f")),
        height = 3.0)
    }
    if (!is.null(ipcc_table)) {
      doc <- .add_portrait_break(doc)
      doc <- .add_p(doc, paste(
        "IPCC Table 3.3, the general reporting table for uncertainty. Approach 2 (Monte Carlo); values in t CO2eq, divide by 1,000 for Gg.",
        if (isTRUE(attr(ipcc_table, "has_ad_ef")))
          "The activity data (AD) and emission factor (EF) columns come from extra simulations of both years with the other side held at its mean: the year t columns are the uncertainty of year t emissions, the trend columns the uncertainty the AD and the EF introduce into the trend (95% half-width, percentage points)."
        else "The activity data and emission factor columns were not computed for this report; IPCC allows them to be left blank.",
        "Contribution to variance is each source's covariance with the total divided by the variance of the total; the sources sum to 1.",
        "Trend uncertainty is in percentage points around the trend, the IPCC convention."))
      doc <- .add_flextable_safe(doc, .styled_flextable(.trend_ipcc_flextable(ipcc_table)))
      doc <- .add_landscape_break(doc)
    }
    if (is.data.frame(ipcc_by_type) && length(unique(ipcc_by_type[["Cattle type"]])) > 1L) {
      doc <- .add_portrait_break(doc)
      doc <- num$sub(doc, "By cattle type")
      doc <- .add_p(doc, paste(
        "IPCC Table 3.3 for dairy and non-dairy cattle separately (reporting codes 3.A.1.a and 3.A.1.b, 3.B.1.a and 3.B.1.b).",
        "Year t uncertainties are +/- half-widths of the 95% interval; each type's figures come from the draws of its own groups."))
      ft <- flextable::fontsize(flextable::flextable(ipcc_by_type), size = 6.5, part = "all")
      doc <- .add_flextable_safe(doc, .styled_flextable(flextable::autofit(ft)))
      doc <- .add_landscape_break(doc)
    }
  }

  doc <- num$sub(doc, "The whole series")
  doc <- .add_p(doc, sprintf(paste(
    "Every year of the series at %s draws per year: mean total emissions with the 95%% confidence interval,",
    "the 95%% margin of error, and the change since the base year and from the previous year.",
    "The figures above come from the paired run of the two chosen years."), .fmt_int(n_iter)))
  doc <- .add_flextable_safe(doc, .styled_flextable(.trend_table_flextable(trend_results)))
  doc <- fig(doc, .gg_trend_chart(trend_results), "Trend in total CO2eq emissions",
    "Mean total CO2eq for each year (line) with its 95% confidence interval (shaded band).")
  doc <- fig(doc, .gg_yoy_chart(trend_results), "Year-over-year change",
    "Change in mean total CO2eq from one year to the next, in percent. Bars above zero are increases.",
    height = 2.8)
  if (!is.null(slope) && !is.null(slope$mean))
    doc <- .add_p(doc, sprintf(paste(
      "Average change per year over the series (a straight line fitted to every year, draw by draw): %s t CO2eq per year,",
      "95%% confidence interval %s to %s."),
      .fmt_signed(slope$mean, 0), .fmt_signed(slope$ci[1], 0), .fmt_signed(slope$ci[2], 0)))

  # ---- 4. Sensitivity analysis -----------------------------------------------
  has_py <- !is.null(.sensitivity_flextable(sensitivity_per_year, top_n = 1L))
  has_dl <- !is.null(.sensitivity_flextable(sensitivity_delta, top_n = 1L))
  if (has_py || has_dl) {
    doc <- num$part(doc, "Sensitivity analysis")
    doc <- .add_p(doc,
      "The standardised regression coefficient (SRC) of each input, from -1 to +1: the further from zero, the more the input drives the uncertainty. The latest year shows what makes that year uncertain; the change shows what makes the trend uncertain (IPCC Vol. 1 Ch. 3, section 3.7).")
    add_rank <- function(doc, sens, title_sub, fig_title, fig_cap) {
      doc <- num$sub(doc, title_sub)
      doc <- fig(doc, .gg_tornado(sens), fig_title, fig_cap, height = 4.0)
      n_s <- if (!is.null(sens$src)) nrow(sens$src) else 0L
      doc <- .add_p(doc, if (n_s > WORD_SENS_MAX)
                           sprintf("SRC ranking: the %d largest drivers, of %d inputs. The complete ranking is in the Excel download.", WORD_SENS_MAX, n_s)
                         else "SRC ranking of every input:")
      .add_flextable_safe(doc, .styled_flextable(.sensitivity_flextable(sens, top_n = WORD_SENS_MAX)))
    }
    if (has_py) doc <- add_rank(doc, sensitivity_per_year, "Latest year",
      "Top 10 drivers of the latest year (SRC)",
      "The ten inputs with the largest influence on total CO2eq in the latest year. Green: inputs you can improve with better national data. Blue: IPCC coefficients.")
    if (has_dl) doc <- add_rank(doc, sensitivity_delta, "Change between the first and last year",
      "Top 10 drivers of the change between the first and last year (SRC)",
      "The ten inputs with the largest influence on the change in total CO2eq between the first and the last year; an input drawn in both years appears once per year. Green: inputs you can improve with better national data. Blue: IPCC coefficients.")
  }

  # ---- Footer -------------------------------------------------------------
  doc <- .add_p(doc, "")
  doc <- .add_logo_footer(doc)
  footer_bits <- c(
    "Generated by Cattle GHG Uncertainty Calculator, trend report.",
    if (!is.null(app_version)) sprintf("v%s.", app_version) else NULL,
    sprintf("Built on %s.", format(Sys.Date(), "%Y-%m-%d")),
    "CGIAR Alliance / Bioversity-CIAT, funded by the Global Methane Hub."
  )
  doc <- .add_p(doc, paste(footer_bits, collapse = " "))

  # Release transient chart/flextable objects before officer serialises the
  # document (print.rdocx is the most expensive step and runs alongside the
  # resident simulation data on the ~1 GB worker).
  invisible(gc(FALSE))
  print(doc, target = path)
  invisible(path)
}

.build_trend_exec_summary <- function(headline, sensitivity_delta, year_corr, n_iter) {
  driver_text <- ""
  base <- if (!is.null(sensitivity_delta$src) && nrow(sensitivity_delta$src) > 0) sensitivity_delta$src else NULL
  if (!is.null(base)) {
    top <- base[order(-abs(base$src)), , drop = FALSE][1, ]
    driver_text <- sprintf("The input that drives the uncertainty of the change most is %s (SRC %s). ",
                           top$parameter, formatC(top$src, digits = 2, format = "f"))
  }
  yc_short <- switch(year_corr %||% "full",
    full    = "the same factors for every year (coefficients fully correlated between years)",
    partial = "factors revised every few years (coefficients partly correlated between years)",
    none    = "independent years")
  pair_txt <- if (!is.null(headline$n_iter_pair))
    sprintf("The two years come from a paired run of %s draws each; the series from %s draws per year.",
            .fmt_int(headline$n_iter_pair), .fmt_int(n_iter))
  else sprintf("The two years come from the series at %s draws per year.", .fmt_int(n_iter))
  paste0(driver_text, pair_txt, " Year-to-year setting: ", yc_short, ".")
}

# ============================================================================
# Flextable builders
# ============================================================================

# Assumptions table for section 2c. The IPCC source column is dropped in
# Word (it is in the Excel sheet) so the table fits a portrait page.
.basis_flextable <- function(tbl) {
  keep <- setdiff(names(tbl), "IPCC source")
  ft <- flextable::flextable(tbl[, keep, drop = FALSE])
  ft <- flextable::width(ft, j = 1, width = 1.0)
  ft <- flextable::width(ft, j = 2, width = 1.1)
  ft <- flextable::width(ft, j = 3, width = 0.8)
  ft <- flextable::width(ft, j = 4, width = 1.2)
  ft <- flextable::width(ft, j = 5, width = 2.2)
  ft
}

.settings_flextable <- function(s) {
  # 2026-11-02 (Lolita): the single-year report shows single-year rows only,
  # and the two Tab 3 choices by name.
  rows <- list(
    c("Analysis mode",         "Single year"),
    c("Iterations",            .fmt_int(s$n_iter)),
    c("Links between inputs (Tab 3)", .corr_mode_label(s$corr_mode)),
    c("Animal numbers (N) between groups (Tab 3)", .n_corr_label(s$n_group_corr %||% "full", "group")),
    c("Comparison of correlation levels", if (isTRUE(s$run_comparison)) "yes" else "no"),
    c("GWP basis",             .as_str(s$gwp_version,  "AR5")),
    c("Seed",                  .as_str(s$seed,         "(random)")),
    c("Emission sources",      .emission_sources_label(s$emission_sources))
  )
  df <- do.call(rbind.data.frame, c(rows, list(stringsAsFactors = FALSE)))
  names(df) <- c("Setting", "Value")
  flextable::flextable(df)
}

.trend_settings_flextable <- function(year_corr, n_iter, yrs, ipcc_meta, n_iter_pair = NULL,
                                      corr_settings = NULL) {
  yc_label <- .year_corr_label(year_corr)
  rows <- list(
    c("Analysis mode",           "Trend"),
    c("Year range",              sprintf("%d – %d", yrs[1], yrs[2])),
    c("Iterations per year",     .fmt_int(n_iter)),
    c("Draws for base year and year t",
      if (is.null(n_iter_pair)) "same as the series" else paste(.fmt_int(n_iter_pair), "(paired run)")),
    c("Year-to-year correlation", yc_label),
    # 2026-11-02: the Tab 3 choices, as in the single-year report, plus the
    # animal numbers between years, which only a trend uses
    c("Links between inputs (Tab 3)", .corr_mode_label(corr_settings$corr_mode %||% "none")),
    c("Animal numbers (N) between groups (Tab 3)", .n_corr_label(corr_settings$n_group_corr %||% "full", "group")),
    c("Animal numbers (N) between years (Tab 3)", .n_corr_label(corr_settings$n_year_corr %||% "none", "year")),
    c("GWP basis", .as_str(corr_settings$gwp_version, "AR5")),
    c("Seed", .as_str(corr_settings$seed, "(random)")),
    c("Emission sources", .emission_sources_label(corr_settings$emission_sources)),
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

# 2026-10-30: the placeholder ranges (see PLACEHOLDER_UNC_PCT in
# R/utils_validation.R), summarised by input since 2026-11-02.
.add_placeholder_section <- function(doc, param_specs, manure, heading, heading_fn = .add_h2) {
  tb <- tryCatch(placeholder_table(param_specs, manure), error = function(e) NULL)
  if (is.null(tb) || !nrow(tb)) return(doc)
  doc <- heading_fn(doc, heading)
  doc <- .add_p(doc, "Your file gave no uncertainty range for the inputs below, and no published default exists for them. So that the run could go ahead, the tool used placeholder ranges. They are not IPCC defaults. The results that depend on them are indicative only. Replace each one with a range from your own data and run again.")
  # 2026-11-02 (Lolita): one row per input instead of one per group and
  # input (59 rows on the test inventory for three inputs). The group-by-group list is
  # in the range_source column of the Excel Input_Parameters sheet.
  sm <- .placeholder_summary(tb)
  doc <- .add_p(doc, sprintf(
    "%d placeholder range(s) were used, on %d input(s). One row per input; the group-by-group list is in the range_source column of the Input_Parameters sheet of the Excel download.",
    nrow(tb), nrow(sm)))
  .add_flextable_safe(doc, .styled_flextable(flextable::flextable(sm)))
}

# The placeholder table summarised by input: the value or values used, the
# placeholder range (the rule's name when it gives different bounds per
# group, as for the manure factors) and the number of groups.
.placeholder_summary <- function(tb) {
  ins <- unique(tb$Input)
  rows <- lapply(ins, function(inp) {
    d <- tb[tb$Input == inp, , drop = FALSE]
    v <- unique(trimws(d$Value))
    num <- suppressWarnings(as.numeric(v))
    val <- if (length(v) == 1L) v
           else if (length(v) <= 3L) paste(v, collapse = ", ")
           else if (all(is.finite(num))) sprintf("%s to %s", format(signif(min(num), 4)), format(signif(max(num), 4)))
           else paste(head(v, 3), collapse = ", ")
    r <- unique(d[["Placeholder range"]])
    rng <- if (length(r) == 1L) r else {
      lab <- unique(sub("^.*[(]([^()]*)[)][[:space:]]*$", "\\1", r[grepl("[)][[:space:]]*$", r)]))
      if (length(lab) == 1L) lab else "varies by group"
    }
    data.frame(Input = inp, `Value(s) in the file` = val, `Placeholder range` = rng,
               Groups = nrow(d), check.names = FALSE, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out[order(-out$Groups, out$Input), , drop = FALSE]
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
  # table so the Word report leads with 95% MoE: the IPCC Vol.1 Ch.3 Table
  # 3.3 convention. `cv_pct` is still in the underlying uncertainty frame for
  # any downstream consumer that wants it.
  # Andreas 2026-06-02 review: include the asymmetric half-widths
  # (+upper% / -lower%) alongside the symmetric MoE: many emission
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
# uncertainty table for the Word exec summary. `kind` is "AD" or "EF" -
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
              CI_Lower_t   = "95% range lower",
              CI_Upper_t   = "95% range upper",
              MoE_95_pct   = "+/- % of mean (95%)",
              Delta_vs_base_pct = "Change since base year (%)",
              YoY_pct      = "Change from previous year (%)")
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
  if (is.null(src) || nrow(src) == 0) return(NULL)

  base <- src
  val_col <- if ("src" %in% names(base)) "src" else names(base)[2]
  base <- base[order(-abs(base[[val_col]])), , drop = FALSE]
  if (is.finite(top_n)) base <- utils::head(base, as.integer(top_n))

  src_disp  <- if ("src" %in% names(base))
                 formatC(base$src,  digits = 3, format = "f") else NULL

  df <- data.frame(Parameter = base$parameter, stringsAsFactors = FALSE)
  if (!is.null(src_disp))  df$SRC  <- src_disp
  flextable::flextable(df)
}

# Round 9b §5: Per-cattle-type / aggregation-level / sub-category breakdown.
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

# Andreas 28/5/26 #7.2 + #7.3: per-(cattle_type × emission source) breakdown
# with raw t CH4 / t N2O and t CO2eq side-by-side. Mirrors the in-app
# results_by_category table when the aggregation level is cattle_type.
.per_source_breakdown_flextable <- function(mc_results, gwp_version = "AR5") {
  if (is.null(mc_results) || is.null(mc_results$by_system) ||
      length(mc_results$by_system) == 0) return(NULL)
  by_sys <- mc_results$by_system
  sys_names <- names(by_sys)
  if (length(sys_names) == 0) return(NULL)

  parts <- strsplit(sys_names, "\\|\\|", fixed = FALSE)
  ct_keys <- sapply(parts, function(p) if (length(p) >= 1 && nzchar(p[1])) p[1] else "n/a")

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

# Round 9b §13: Input parameter documentation. Mirrors inputs_doc_table.
# Perf (2026-06): the input-documentation table is the single biggest driver of
# Word build time on large inventories: for the 32-sub-category test-inventory run it is
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

# Round 9b §12: MC diagnostics summary (badges as a table).
.diagnostics_flextable <- function(diagnostics) {
  if (is.null(diagnostics)) return(NULL)
  d <- diagnostics
  status_str <- function(val, warn, fail) {
    if (is.null(val) || is.na(val)) return("n/a")
    if (val < warn) "PASS" else if (val < fail) "WARN" else "FAIL"
  }
  skew_label <- if (is.null(d$skew_val) || is.na(d$skew_val)) "n/a"
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
  # 2026-11-02: green for inputs a compiler can improve, blue for IPCC
  # coefficients, as in the app; long labels break before their bracket.
  top$kind <- factor(ifelse(param_reducible(as.character(top$parameter)),
                            "Input you can improve with national data", "IPCC coefficient"),
                     levels = c("Input you can improve with national data", "IPCC coefficient"))
  lab <- as.character(top$parameter)
  long <- nchar(lab) > 22 & grepl(" (", lab, fixed = TRUE)
  lab[long] <- sub(" (", "\n(", lab[long], fixed = TRUE)
  top$parameter <- factor(lab, levels = lab)
  top$lbl <- sprintf("%+.2f", top[[val_col]])
  top$lbl_hjust <- ifelse(top[[val_col]] >= 0, -0.15, 1.15)
  x_range <- range(top[[val_col]], na.rm = TRUE)
  x_pad   <- 0.18 * diff(x_range)

  ggplot2::ggplot(top, ggplot2::aes(x = .data[[val_col]], y = parameter, fill = kind)) +
    ggplot2::geom_col() +
    ggplot2::geom_text(ggplot2::aes(label = lbl, hjust = lbl_hjust),
                        size = 3.0, colour = "#1B4332") +
    ggplot2::scale_fill_manual(values = c("Input you can improve with national data" = .GREEN_MID,
                                          "IPCC coefficient" = "#1565C0"),
                               name = NULL, drop = FALSE) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(add = c(x_pad, x_pad))) +
    ggplot2::labs(x = toupper(val_col), y = NULL, subtitle = subtitle) +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")
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
    "Pasture N2O (indirect)"= "indirect_n2o_prp_total"
  )
  # 2026-11-02: the inventory names its columns total_enteric_ch4 and so
  # on; only "total_co2e" matched before, so the grid showed one panel.
  # The total has its own figure, so it is not repeated here.
  parts <- list()
  for (lab in names(picks)) {
    col <- picks[[lab]]
    if (!col %in% names(inv)) col <- paste0("total_", sub("_total$", "", col))
    if (col %in% names(inv)) {
      v <- inv[[col]]
      if (length(v) > 0 && stats::sd(v, na.rm = TRUE) > 0) {
        # Subsample for the histogram (shape is stable; keeps the combined
        # long data frame small: up to 7 sources x n_iter otherwise).
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

# Round 8: trend chart for the trend Word doc, line + 95% CI ribbon
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

# Round 9b §6: AD / EF / Combined 95 % MoE for total CO2eq, total CH4,
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

# Round 9b §7: Effect of correlations on 95 % MoE (with vs without).
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

# 2026-11-02: the correlation levels as in the app: one bar per level
# (no correlations, + the links, + the N correlation), the change from
# the previous level written on each bar.
.gg_comparison_levels <- function(levels) {
  if (is.null(levels) || length(levels) < 2L) return(NULL)
  vars   <- c("total_co2e", "total_ch4", "total_n2o")
  labels <- c("Total CO2eq", "Total CH4", "Total N2O")
  pull <- function(df, v) { r <- df[df$variable == v, , drop = FALSE]; if (nrow(r)) r$moe_pct[1] else NA_real_ }
  rows <- list(); prev <- NULL
  for (k in seq_along(levels)) {
    moe <- vapply(vars, pull, numeric(1), df = levels[[k]])
    lbl <- if (is.null(prev)) sprintf("%.1f%%", moe) else sprintf("%.1f%%\n(%+.1f pts)", moe, moe - prev)
    rows[[k]] <- data.frame(variable = labels, level = names(levels)[k], moe_pct = moe, lbl = lbl,
                            stringsAsFactors = FALSE)
    prev <- moe
  }
  df <- do.call(rbind, rows)
  df <- df[!is.na(df$moe_pct), , drop = FALSE]
  if (!nrow(df)) return(NULL)
  df$variable <- factor(df$variable, levels = labels)
  df$level <- factor(df$level, levels = names(levels))
  cols <- c("#90A4AE", .GREEN_MID, "#1D4ED8")[seq_along(levels)]
  if (length(levels) == 2L) cols <- c("#90A4AE", "#1D4ED8")
  ggplot2::ggplot(df, ggplot2::aes(x = variable, y = moe_pct, fill = level)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.75) +
    ggplot2::geom_text(ggplot2::aes(label = lbl), position = ggplot2::position_dodge(width = 0.8),
                       vjust = -0.3, size = 2.6, colour = "#1B4332", lineheight = 0.9) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.22))) +
    ggplot2::scale_fill_manual(values = stats::setNames(cols, names(levels)), name = NULL) +
    ggplot2::labs(x = NULL, y = "95% MoE (%)") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")
}

# Round 9b §11: Per-parameter density plots (up to 12). Mirrors the live
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

# Round 9b §12: MC convergence: running mean + 2.5/97.5% bands across
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

# Round 9b §3a: Year-over-year % change bar chart for the trend report.
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

# Round 9b §3b: Distribution of Δ Y_N − Y_1 from the per-iteration delta
# samples. Mirrors output$trend_delta_histogram.
# 2026-11-04: the change between the two chosen years, draw by draw, in
# percent of the base year, with the mean, the 95% interval and its
# half-width written on the chart.
.gg_change_hist <- function(d, h) {
  d <- d[is.finite(d)]
  if (length(d) < 10) return(NULL)
  hw <- (h$trend_hi_pp - h$trend_lo_pp) / 2
  lab <- sprintf("Change %s%%\n95%% interval %s%% to %s%%\nHalf-width %s percentage points",
                 .fmt_signed(h$trend_pct, 1), .fmt_signed(h$trend_lo_pct, 1),
                 .fmt_signed(h$trend_hi_pct, 1), formatC(hw, digits = 1, format = "f"))
  ggplot2::ggplot(data.frame(d = d), ggplot2::aes(x = d)) +
    ggplot2::geom_histogram(bins = 40, fill = "#52B788", colour = "#1B4332", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = h$trend_pct, colour = "#1B4332", linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = c(h$trend_lo_pct, h$trend_hi_pct), colour = "#C1121F",
                        linetype = "dashed", linewidth = 0.6) +
    ggplot2::annotate("label", x = -Inf, y = Inf, hjust = -0.05, vjust = 1.1, label = lab,
                      size = 3, colour = "#1B4332", fill = "white", label.size = 0) +
    ggplot2::labs(x = "Change in total emissions (% of the base year)", y = "Draws") +
    ggplot2::theme_minimal(base_size = 10)
}

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
                   title = "Distribution of ΔY_N − Y_1: uncertainty on the trend itself") +
    ggplot2::theme_minimal(base_size = 10)
}

# ---- 2026-10-22: what to report, for the Word trend report ----------------
# English sentences from trend_headline(); the app phrases the same numbers
# through i18n.
.trend_headline_sentences <- function(h) {
  if (is.null(h)) return(character(0))
  f0 <- function(x) format(round(x, 0), big.mark = ",")
  f1 <- function(x) formatC(x, digits = 1, format = "f")
  fs <- function(x) { v <- formatC(x, digits = 1, format = "f"); if (x > 0) paste0("+", v) else v }
  hw <- (h$trend_hi_pp - h$trend_lo_pp) / 2
  # 2026-11-04: in the order of the app's headline cards
  c(sprintf("Emissions in %d (year t): %s t CO2eq, plus or minus %s%% (95%% range %s to %s t).",
            h$year_t, f0(h$t_mean), f1(h$t_moe), f0(h$t_lo), f0(h$t_hi)),
    sprintf("Change from %d to %d: %s%%. With 95%% confidence the change lies between %s%% and %s%%, plus or minus %s percentage points; %s",
            h$base_year, h$year_t, fs(h$trend_pct), fs(h$trend_lo_pct), fs(h$trend_hi_pct), f1(hw),
            if (isTRUE(h$zero_inside)) "this range includes zero, so this analysis cannot say whether emissions fell or rose."
            else "this range does not include zero, so the direction of the change is clear."),
    sprintf("Emissions in %d (base year): %s t CO2eq, plus or minus %s%% (95%% range %s to %s t).",
            h$base_year, f0(h$base_mean), f1(h$base_moe), f0(h$base_lo), f0(h$base_hi)))
}

.trend_compare_flextable <- function(cmp) {
  fs <- function(x) ifelse(is.na(x), "", ifelse(x > 0, paste0("+", formatC(x, digits = 1, format = "f")),
                                                formatC(x, digits = 1, format = "f")))
  df <- data.frame(
    `Emission source` = cmp$category,
    `Base year (t CO2eq)` = format(round(cmp$base_mean, 0), big.mark = ","),
    `Base year +/- %` = formatC(cmp$base_moe_pct, digits = 1, format = "f"),
    `Year t (t CO2eq)` = format(round(cmp$t_mean, 0), big.mark = ","),
    `Year t +/- %` = formatC(cmp$t_moe_pct, digits = 1, format = "f"),
    `Change (%)` = fs(cmp$trend_pct),
    `Change, 95% range (%)` = ifelse(is.na(cmp$trend_lo_pp), "",
                                     paste0(fs(cmp$trend_pct + cmp$trend_lo_pp), " to ",
                                            fs(cmp$trend_pct + cmp$trend_hi_pp))),
    `Share of year t variance` = ifelse(cmp$is_source | cmp$var == "total_co2e",
                                        formatC(cmp$contribution, digits = 3, format = "f"), ""),
    check.names = FALSE, stringsAsFactors = FALSE)
  ft <- flextable::flextable(df)
  ft <- flextable::fontsize(ft, size = 8, part = "all")
  flextable::autofit(ft)
}

.trend_ipcc_flextable <- function(tab) {
  df <- tab
  for (j in 3:4) df[[j]] <- format(round(df[[j]], 0), big.mark = ",")
  for (j in 5:10) df[[j]] <- ifelse(is.na(df[[j]]), "", formatC(df[[j]], digits = 1, format = "f"))
  df[[11]] <- ifelse(is.na(df[[11]]), "", formatC(df[[11]], digits = 3, format = "f"))
  for (j in 12:16) df[[j]] <- ifelse(is.na(df[[j]]), "", formatC(df[[j]], digits = 1, format = "f"))
  # 2026-11-04: the trend's AD and EF columns, and headers that say which
  # figures are the year t level and which the trend
  names(df) <- c("IPCC category", "Gas", "Base year (t CO2eq)", "Year t (t CO2eq)",
                 "Year t AD (-) %", "Year t AD (+) %", "Year t EF (-) %", "Year t EF (+) %",
                 "Year t combined (-) %", "Year t combined (+) %", "Share of variance, year t",
                 "Trend (% of base)", "Trend unc. from AD (+/- pp)", "Trend unc. from EF (+/- pp)",
                 "Trend unc. combined (-) pp", "Trend unc. combined (+) pp",
                 "Approach and comments")
  ft <- flextable::flextable(df)
  ft <- flextable::fontsize(ft, size = 6.5, part = "all")
  flextable::autofit(ft)
}
