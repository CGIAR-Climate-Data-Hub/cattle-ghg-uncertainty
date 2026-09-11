# Trend Tab — multi-year inventory uncertainty (F / T4.22 / TT.6)
#
# Reads a long-format CSV (year, parameter, mean, uncertainty_pct), runs a
# separate Monte Carlo simulation per year using the year-specific values, and
# returns a data.frame summarising the per-year mean / 95% CI / margin of error
# and a percent-change column relative to the earliest year.

# Build a parsable param_specs from a single year's slice of the long CSV.
.trend_year_specs <- function(year_df, base_specs, catalogue = PARAM_CATALOGUE) {
  # Start from the user's current param_specs (preserves grouping / param_type)
  ps <- base_specs
  # Apply year-specific mean and uncertainty_pct where the long CSV provides them
  for (i in seq_len(nrow(year_df))) {
    p   <- year_df$parameter[i]
    new_mean <- suppressWarnings(as.numeric(year_df$mean[i]))
    new_pct  <- suppressWarnings(as.numeric(year_df$uncertainty_pct[i]))
    sel <- which(ps$parameter == p)
    if (length(sel) == 0) next
    if (!is.na(new_mean)) ps$mean[sel] <- new_mean
    if (!is.na(new_pct))  ps$uncertainty_pct[sel] <- new_pct
    # Recompute bounds from the new mean and pct
    if (!is.na(new_mean) && !is.na(new_pct)) {
      ps$lower[sel] <- new_mean * (1 - new_pct / 100)
      ps$upper[sel] <- new_mean * (1 + new_pct / 100)
    }
  }
  ps
}

# R2.3: convert a wide Parameter_TimeSeries data frame (rows = years,
# columns = parameters) into the long format run_trend_analysis() expects.
# This lets the Trend tab consume the time-series the user already loaded
# via the main template (or via a built-in example) instead of forcing a
# separate CSV upload. Default uncertainty_pct comes from base_specs so
# each year inherits the same per-parameter uncertainty unless overridden.
trend_df_from_population <- function(population, base_specs,
                                      default_uncertainty_pct = 15) {
  if (is.null(population) || ncol(population) < 2)
    stop("No time-series data available — load a template with a Parameter_TimeSeries sheet, or use the CSV upload override below.")
  if (!"year" %in% names(population))
    stop("Time-series must have a 'year' column.")
  param_cols <- setdiff(names(population), "year")
  rows <- list()
  for (p in param_cols) {
    # Map this column's uncertainty_pct from base_specs if present
    pct_default <- default_uncertainty_pct
    if (!is.null(base_specs)) {
      hit <- which(base_specs$parameter == p)
      if (length(hit) > 0 && !is.na(base_specs$uncertainty_pct[hit[1]]))
        pct_default <- base_specs$uncertainty_pct[hit[1]]
    }
    rows[[length(rows) + 1]] <- data.frame(
      year             = population$year,
      parameter        = p,
      mean             = population[[p]],
      uncertainty_pct  = pct_default,
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  out[!is.na(out$mean), , drop = FALSE]
}

# Round 7 R1.14: pre-sample the coefficient block once for the trend run.
# Used by year_corr = "full" mode where the same coefficient draws are reused
# across every year (per IPCC 2019 Refinement Vol 1 Ch 3 §3.2.2.4).
.pre_sample_coefficients <- function(base_specs, n_iter, seed = NULL) {
  coef <- base_specs[base_specs$param_type == "coefficient", , drop = FALSE]
  if (nrow(coef) == 0) return(NULL)
  if (!is.null(seed)) set.seed(seed)
  samp <- matrix(NA_real_, nrow = n_iter, ncol = nrow(coef))
  for (j in seq_len(nrow(coef))) {
    samp[, j] <- sample_distribution(
      n_iter, coef$distribution[j],
      coef$mean[j], coef$lower[j], coef$upper[j]
    )
  }
  colnames(samp) <- coef$parameter
  samp
}

# Build AR(1)-correlated samples of one coefficient across years.
# rho is the year-to-year rank correlation; default 0.7 mirrors a moderate
# "partially correlated" assumption per IPCC Vol.1 Ch.3 §3.2.2.4. Returns an
# n_iter x n_years matrix where each row is one coefficient's annual draw.
#
# Procedure (per IPCC Vol.1 Ch.3 §3.2.3.2): draw n_iter independent samples
# from the coefficient's marginal for each year, then reorder columns so the
# resulting Spearman rank correlation across years matches the AR(1) target
# matrix rho^|i-j|. Distribution-free — the coefficient's PERT/lognormal/beta
# shape is preserved exactly.
.ar1_samples_one_coef <- function(spec, n_iter, n_years, rho = 0.7) {
  # Independent draws per year from the coefficient's marginal
  X <- matrix(NA_real_, nrow = n_iter, ncol = n_years)
  for (k in seq_len(n_years)) {
    X[, k] <- sample_distribution(n_iter, spec$distribution,
                                   spec$mean, spec$lower, spec$upper)
  }
  # AR(1) rank-correlation target across years
  R <- outer(seq_len(n_years), seq_len(n_years), function(i, j) rho ^ abs(i - j))
  # Reorder columns to hit the target rank correlation (preserves marginals)
  mc2d::cornode(X, target = R, outrank = FALSE, result = FALSE)
}

run_trend_analysis <- function(trend_df, base_specs, n_iter = 2000,
                                gwp = "AR5", seed = 42,
                                # Year-to-year correlation mode per IPCC Vol.1
                                # Ch.3 §3.2.2.4.
                                #   "full"    = same coefficient draws every year
                                #               (default). AD redrawn per year.
                                #   "partial" = AR(1) rank-correlation across
                                #               years (rho=0.7) for each
                                #               coefficient, applied via the same
                                #               restricted-pairing procedure as
                                #               the within-year correlations
                                #               (IPCC Vol.1 Ch.3 §3.2.3.2).
                                #   "none"    = independent per year (pre-Round-7
                                #               behaviour).
                                year_corr = c("full", "partial", "none"),
                                ar1_rho   = 0.7,
                                # Round 9: filter the per-year total_co2e by the
                                # selected emission sources (mirrors the single-year
                                # handler at app_server.R ~line 927). NULL (or all
                                # 5 keys) = include every source. Used to align the
                                # trend output with the user's source-checkbox
                                # selection on Tab 5.
                                emission_sources = NULL,
                                # Round 9 follow-up: optional per-year progress
                                # callback so the Shiny observer can advance a
                                # withProgress bar. Called as progress_fn(yi,
                                # n_years, year_label) after each year completes.
                                progress_fn = NULL) {
  year_corr <- match.arg(year_corr)

  # Required columns
  req_cols <- c("year", "parameter", "mean", "uncertainty_pct")
  miss <- setdiff(req_cols, names(trend_df))
  if (length(miss) > 0)
    stop("Trend data is missing column(s): ", paste(miss, collapse = ", "))

  # Apply legacy parameter aliases (so old DE_pct etc. still work)
  if (exists("PARAM_ALIASES")) {
    aliased <- trend_df$parameter %in% names(PARAM_ALIASES)
    if (any(aliased))
      trend_df$parameter[aliased] <- PARAM_ALIASES[trend_df$parameter[aliased]]
  }

  trend_df$year <- suppressWarnings(as.integer(trend_df$year))
  trend_df <- trend_df[!is.na(trend_df$year), , drop = FALSE]
  years <- sort(unique(trend_df$year))
  if (length(years) < 2)
    stop("Trend CSV must contain at least 2 distinct years.")

  # ---- Round 7 R1.14: pre-sample coefficients once for "full" mode ----
  pre_full <- if (year_corr == "full") {
    .pre_sample_coefficients(base_specs, n_iter, seed = seed)
  } else NULL

  # ---- "partial": pre-build AR(1) draws across years for each coefficient ----
  pre_partial <- NULL
  if (year_corr == "partial") {
    coef_specs <- base_specs[base_specs$param_type == "coefficient", , drop = FALSE]
    if (nrow(coef_specs) > 0) {
      if (!is.null(seed)) set.seed(seed)
      pre_partial <- list()
      for (j in seq_len(nrow(coef_specs))) {
        pre_partial[[coef_specs$parameter[j]]] <-
          .ar1_samples_one_coef(coef_specs[j, ], n_iter,
                                n_years = length(years), rho = ar1_rho)
      }
    }
  }

  # Round 8: cache per-year MC samples + co2e vectors so the trend tab can
  # compute sensitivity (per-year + delta-driven) and richer metrics later.
  rows            <- list()
  samples_by_year <- list()
  co2e_by_year    <- list()

  # Round 9: emission-source filter — applied per year to recompute total_co2e
  # from the per-source columns of sim$inventory. Mirrors the single-year
  # post-filter at app_server.R ~line 927. NULL or all 5 keys = include all.
  # Andreas 2026-05 #27: pasture direct & indirect split. Legacy "pasture_n2o"
  # accepted as alias for both.
  all_src_keys <- c("enteric_ch4", "manure_ch4", "manure_n2o_direct",
                     "manure_n2o_indirect",
                     "pasture_n2o_direct", "pasture_n2o_indirect")
  srcs <- if (is.null(emission_sources) || length(emission_sources) == 0L)
            all_src_keys else emission_sources
  apply_source_filter <- length(srcs) > 0L && length(srcs) < length(all_src_keys)
  gwp_vals <- if (!is.null(GWP_VALUES[[gwp]])) GWP_VALUES[[gwp]]
              else GWP_VALUES[["AR5"]]

  filter_co2e <- function(df) {
    if (!apply_source_filter) return(df$total_co2e)
    legacy_pasture <- "pasture_n2o" %in% srcs
    ch4 <- (if ("enteric_ch4" %in% srcs) df$enteric_ch4_total else 0) +
           (if ("manure_ch4"  %in% srcs) df$manure_ch4_total  else 0)
    n2o <- (if ("manure_n2o_direct"   %in% srcs) df$direct_n2o_mm_total   else 0) +
           (if ("manure_n2o_indirect" %in% srcs) df$indirect_n2o_mm_total else 0) +
           (if (legacy_pasture || "pasture_n2o_direct"   %in% srcs) df$direct_n2o_prp_total   else 0) +
           (if (legacy_pasture || "pasture_n2o_indirect" %in% srcs) df$indirect_n2o_prp_total else 0)
    ch4 * gwp_vals$CH4 + n2o * gwp_vals$N2O
  }

  for (yi in seq_along(years)) {
    y <- years[yi]
    year_slice <- trend_df[trend_df$year == y, , drop = FALSE]
    ps <- .trend_year_specs(year_slice, base_specs)

    # Pick which pre-sampled coefficient block to inject for this year
    pre_coef <- if (year_corr == "full") {
      pre_full
    } else if (year_corr == "partial" && !is.null(pre_partial)) {
      do.call(cbind, lapply(names(pre_partial), function(p) {
        v <- pre_partial[[p]][, yi]
        m <- matrix(v, ncol = 1)
        colnames(m) <- p
        m
      }))
    } else NULL

    sys <- list(
      param_specs    = ps,
      corr_matrix    = NULL,
      # The same fallback the app uses, from the one function that defines it.
      mms_fractions  = default_mms_fallback()$fractions,
      mcf_values     = default_mms_fallback()$mcf,
      ef3_values     = default_mms_fallback()$ef3,
      ef_corr_matrix = NULL,
      pre_sampled_coefficients = pre_coef
    )
    sim <- run_inventory_simulation(
      list(year_run = sys), n_iter = n_iter, gwp = gwp,
      # If we already injected coefficient draws, fix the seed so AD draws stay
      # reproducible across re-runs but don't accidentally redraw coefficients.
      seed = if (!is.null(pre_coef)) seed + yi else seed
    )
    # Round 9: apply emission-source filter to total_co2e. The per-source
    # columns (enteric_ch4_total, manure_ch4_total, etc.) live on
    # sim$by_system$year_run$results, not on sim$inventory which only carries
    # the cross-system total_* aggregates. Same gotcha as Round 6a #8.
    per_source_df <- sim$by_system$year_run$results
    co2e <- filter_co2e(per_source_df)
    m    <- mean(co2e)
    s    <- sd(co2e)
    lo   <- quantile(co2e, 0.025, names = FALSE)
    hi   <- quantile(co2e, 0.975, names = FALSE)
    moe  <- if (m > 0) ((hi - lo) / 2) / m * 100 else NA_real_
    cv   <- if (m > 0) s / m * 100 else NA_real_

    samples_by_year[[as.character(y)]] <- sim$by_system$year_run$samples
    if (is.function(progress_fn)) {
      try(progress_fn(yi, length(years), as.character(y)), silent = TRUE)
    }
    co2e_by_year[[as.character(y)]]    <- co2e

    rows[[length(rows) + 1]] <- data.frame(
      Year         = y,
      Mean_t_CO2eq = round(m, 2),
      CI_Lower_t   = round(lo, 2),
      CI_Upper_t   = round(hi, 2),
      CV_pct       = round(cv, 2),
      MoE_95_pct   = round(moe, 1)
    )
  }

  out <- do.call(rbind, rows)
  base_mean <- out$Mean_t_CO2eq[1]
  out$Delta_vs_base_pct <- round((out$Mean_t_CO2eq - base_mean) / base_mean * 100, 1)
  # Round 8: year-over-year % change column for IPCC-style stepwise reporting
  out$YoY_pct <- c(NA_real_, round(diff(out$Mean_t_CO2eq) /
                                    out$Mean_t_CO2eq[-nrow(out)] * 100, 1))
  attr(out, "year_corr") <- year_corr

  # Round 8: per-iteration trend metrics — slope (kt CO2eq/yr) via lm() per
  # iteration, and Delta total (Y_N - Y_1) per iteration. Both are returned
  # with their own MC distribution + 95% CI per IPCC Vol 1 Ch 3 §3.7.
  yr_vec <- as.numeric(years)
  co2e_mat <- do.call(cbind, co2e_by_year)  # n_iter x n_years
  # Slope per iteration via least-squares closed form (faster than lm() per row)
  yr_centered <- yr_vec - mean(yr_vec)
  denom <- sum(yr_centered ^ 2)
  slope_per_iter <- as.numeric(co2e_mat %*% yr_centered) / denom
  delta_per_iter <- co2e_mat[, ncol(co2e_mat)] - co2e_mat[, 1]
  base_co2e_per_iter <- co2e_mat[, 1]
  delta_pct_per_iter <- ifelse(base_co2e_per_iter > 0,
                                delta_per_iter / base_co2e_per_iter * 100,
                                NA_real_)
  q025 <- function(x) stats::quantile(x, 0.025, names = FALSE, na.rm = TRUE)
  q975 <- function(x) stats::quantile(x, 0.975, names = FALSE, na.rm = TRUE)

  list(
    table = out,
    samples_by_year = samples_by_year,
    co2e_by_year    = co2e_by_year,
    slope = list(
      per_iter = slope_per_iter,
      mean     = mean(slope_per_iter, na.rm = TRUE),
      ci       = c(q025(slope_per_iter), q975(slope_per_iter))
    ),
    delta_total = list(
      per_iter   = delta_per_iter,
      mean       = mean(delta_per_iter, na.rm = TRUE),
      ci         = c(q025(delta_per_iter), q975(delta_per_iter)),
      pct_per_iter = delta_pct_per_iter,
      pct_mean   = mean(delta_pct_per_iter, na.rm = TRUE),
      pct_ci     = c(q025(delta_pct_per_iter), q975(delta_pct_per_iter))
    ),
    year_corr = year_corr,
    years     = years
  )
}
