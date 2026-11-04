# Trend Tab: multi-year inventory uncertainty (F / T4.22 / TT.6)
#
# Runs the single-year inventory once per year of the Parameter_TimeSeries
# sheet, through the same per-group build as single-year mode
# (build_systems_data() in R/systems_builder.R), with coefficient draws held
# across years according to year_corr. Returns per-year summaries, the
# per-iteration inventory totals per year, and per-iteration slope and delta.
#
# 2026-10-16 rewrite. Until this date trend mode (a) dropped the group key,
# so the last group's value for a parameter overwrote every group's, and (b)
# passed the whole parameter sheet as one system, so the inventory was
# computed from one group. On the test-inventory file: every group given N = 252,503
# and a total of 196,566 t against 9,240,534 t. It also retained the full
# sample matrix of every year, 2.09 GB over 35 years. See
# knowledge/22-trend-capacity.md.

# Build a parsable param_specs from a single year's slice of the long frame.
# Matches on (group, parameter) when the slice carries a group column, so a
# multi-group series updates each group's own row. Falls back to parameter
# only for one-group inputs with no key, which is what the audit's fixture
# and a hand-made CSV look like.
.trend_year_specs <- function(year_df, base_specs, catalogue = PARAM_CATALOGUE) {
  ps <- base_specs
  # A slice built straight from a keyed sheet carries the key columns rather
  # than a group column: derive it here so every caller, not only
  # run_trend_analysis(), gets per-group matching. Audit D5b caught exactly
  # this: a direct call with a keyed frame collapsed three groups to one.
  if (!"group" %in% names(year_df) &&
      all(c("cattle_type", "aggregation_level") %in% names(year_df)))
    year_df$group <- make_group_key(year_df)
  has_group <- "group" %in% names(year_df) &&
    any(!is.na(year_df$group) & nzchar(year_df$group))
  ps_key <- if (has_group) make_group_key(ps) else NULL
  for (i in seq_len(nrow(year_df))) {
    p   <- year_df$parameter[i]
    new_mean <- suppressWarnings(as.numeric(year_df$mean[i]))
    new_pct  <- suppressWarnings(as.numeric(year_df$uncertainty_pct[i]))
    sel <- if (has_group && !is.na(year_df$group[i]) && nzchar(year_df$group[i]))
      which(ps$parameter == p & ps_key == year_df$group[i])
    else which(ps$parameter == p)
    if (length(sel) == 0) next
    old_mean <- suppressWarnings(as.numeric(ps$mean[sel]))
    if (!is.na(new_mean)) ps$mean[sel] <- new_mean
    if (!is.na(new_pct))  ps$uncertainty_pct[sel] <- new_pct
    # Recompute bounds from the new mean and pct
    if (!is.na(new_mean) && !is.na(new_pct)) {
      ps$lower[sel] <- new_mean * (1 - new_pct / 100)
      ps$upper[sel] <- new_mean * (1 + new_pct / 100)
    } else if (!is.na(new_mean)) {
      # 2026-10-30: no range for this year: each row keeps its own relative
      # range (its own uncertainty_pct, or its bounds scaled with the value).
      # It used to take the first group's pct, or a blanket 15%.
      for (k in seq_along(sel)) {
        r <- sel[k]
        pc <- suppressWarnings(as.numeric(ps$uncertainty_pct[r]))
        lo <- suppressWarnings(as.numeric(ps$lower[r]))
        hi <- suppressWarnings(as.numeric(ps$upper[r]))
        # 2026-11-04: a row whose range is given by bounds may carry a 0 in
        # uncertainty_pct; the bounds win then. Now that every year's draws
        # come from its own specs (make_year_block_generator), taking the 0
        # would have collapsed the range of every later year.
        has_bounds <- !is.na(lo) && !is.na(hi) && hi > lo
        if (!is.na(pc) && (pc > 0 || !has_bounds)) {
          ps$lower[r] <- new_mean * (1 - pc / 100)
          ps$upper[r] <- new_mean * (1 + pc / 100)
        } else if (!is.na(old_mean[k]) && old_mean[k] != 0) {
          ratio <- new_mean / old_mean[k]
          ps$lower[r] <- lo * ratio
          ps$upper[r] <- hi * ratio
        }
      }
    }
  }
  ps
}

# R2.3: convert the Parameter_TimeSeries sheet (one row per group per year,
# parameters as columns) into the long format run_trend_analysis() expects:
# (group, year, parameter, mean, uncertainty_pct). The group key is carried
# so the per-year specs update the right row. Blank cells are dropped: the
# translator leaves a column blank where a value does not change across
# years, and that blank means "keep the template value".
trend_df_from_population <- function(population, base_specs,
                                      default_uncertainty_pct = NA_real_) {
  if (is.null(population) || ncol(population) < 2)
    stop("No time-series data available: load a template with a Parameter_TimeSeries sheet, or use the CSV upload override below.")
  if (!"year" %in% names(population))
    stop("Time-series must have a 'year' column.")
  key_cols <- intersect(c("cattle_type", "aggregation_level", "sub_category",
                          "system", "subsystem"), names(population))
  # 2026-10-30: the sheet says "blank = applies to all" for cattle_type. A
  # blank one takes the cattle_type of the Parameters group with the same
  # aggregation_level and sub_category (or the only one of that system);
  # the key used to read "NA||...", matched nothing, and the trend kept the
  # inventory-year values for the whole group without saying so (the test inventory
  # 2024 translation: all of commercial dairy).
  if (all(c("cattle_type", "aggregation_level") %in% names(population)) &&
      !is.null(base_specs) &&
      all(c("cattle_type", "aggregation_level") %in% names(base_specs))) {
    ct <- as.character(population$cattle_type)
    blank <- is.na(ct) | !nzchar(trimws(ct))
    sub_p <- if ("sub_category" %in% names(population)) as.character(population$sub_category) else rep(NA, nrow(population))
    sub_b <- if ("sub_category" %in% names(base_specs)) as.character(base_specs$sub_category) else rep(NA, nrow(base_specs))
    for (i in which(blank)) {
      in_sys <- base_specs$aggregation_level %in% population$aggregation_level[i]
      hit <- unique(base_specs$cattle_type[in_sys & sub_b %in% sub_p[i]])
      if (length(hit) != 1L) hit <- unique(base_specs$cattle_type[in_sys])
      if (length(hit) == 1L) ct[i] <- hit
    }
    population$cattle_type <- ct
  }
  group <- if (length(key_cols)) make_group_key(population) else rep("", nrow(population))
  param_cols <- setdiff(names(population), c("year", key_cols))
  rows <- list()
  for (p in param_cols) {
    vals <- suppressWarnings(as.numeric(population[[p]]))
    if (all(is.na(vals))) next          # a label column, or a blank one
    # 2026-10-30: blank unless the caller sets one. A year without its own
    # range keeps each group's range from the Parameters sheet (see
    # .trend_year_specs); taking the first group's, or 15%, was wrong for
    # every other group and invented a range where the country gave none.
    pct_default <- default_uncertainty_pct
    rows[[length(rows) + 1]] <- data.frame(
      group            = group,
      year             = population$year,
      parameter        = p,
      mean             = vals,
      uncertainty_pct  = pct_default,
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  # The sheet's own annotation rows ("(label only)", "Calendar year") make
  # the year column character; coerce here so every caller gets integers
  # and those rows are gone.
  out$year <- suppressWarnings(as.integer(out$year))
  out[!is.na(out$mean) & !is.na(out$year), , drop = FALSE]
}

# Kept for callers that still use it. Trend mode itself now uses
# build_full_coefficient_blocks() in R/systems_builder.R, which is per group
# and shares draws across groups.
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

# Kept for reference. Trend mode now uses make_partial_block_generator(),
# which is sequential and does not hold n_iter x n_years per coefficient.
.ar1_samples_one_coef <- function(spec, n_iter, n_years, rho = 0.7) {
  X <- matrix(NA_real_, nrow = n_iter, ncol = n_years)
  for (k in seq_len(n_years)) {
    X[, k] <- sample_distribution(n_iter, spec$distribution,
                                   spec$mean, spec$lower, spec$upper)
  }
  R <- outer(seq_len(n_years), seq_len(n_years), function(i, j) rho ^ abs(i - j))
  mc2d::cornode(X, target = R, outrank = FALSE, result = FALSE)
}

# Per-year, per-system summary kept instead of the per-system results
# frames: mean and 95% bounds for every source, per system. A few kilobytes
# a year, and enough for a by-cattle-type or by-level table for any year.
.trend_system_summary <- function(by_system, year) {
  srcs <- c("enteric_ch4_total", "manure_ch4_total", "direct_n2o_mm_total",
            "indirect_n2o_mm_total", "direct_n2o_prp_total",
            "indirect_n2o_prp_total", "total_co2e")
  rows <- lapply(names(by_system), function(sn) {
    r <- by_system[[sn]]$results
    parts <- strsplit(sn, "||", fixed = TRUE)[[1]]
    do.call(rbind, lapply(srcs, function(s) {
      x <- r[[s]]
      if (is.null(x)) return(NULL)
      data.frame(year = year, system = sn,
                 cattle_type = if (length(parts) >= 1) parts[1] else "",
                 aggregation_level = if (length(parts) >= 2) parts[2] else "",
                 sub_category = if (length(parts) >= 3) parts[3] else "",
                 source = s, mean = mean(x, na.rm = TRUE),
                 lo = stats::quantile(x, 0.025, names = FALSE, na.rm = TRUE),
                 hi = stats::quantile(x, 0.975, names = FALSE, na.rm = TRUE),
                 stringsAsFactors = FALSE)
    }))
  })
  do.call(rbind, rows)
}

# What is kept of a year's sample matrices: per system, the thinned draws
# only. That is what aggregate_sensitivity() reads.
.trend_keep_samples <- function(by_system) {
  lapply(by_system, function(s) list(samples = s$samples))
}

# Seed of year `yi` in a trend run. Within one year, run_inventory_simulation()
# seeds group i with year_seed + i, the shared coefficient draws use
# year_seed, and the per-MMS draws use year_seed + 1000003. Until 2026-10-28
# the year seed was seed + yi, so year y group g + 1 and year y + 1 group g
# both drew from seed + y + g + 1: their animal numbers had a rank
# correlation of 1.000 (31 of 32 groups on the test inventory, every pair of
# consecutive years), a year-to-year correlation nobody chose. A stride of
# 10007 per year keeps every stream of every year apart for up to 9,300
# groups; the partial-correlation generator (seed + 1 .. seed + n_years) and
# the full coefficient blocks (seed) stay below the first year's streams.
.trend_year_seed <- function(seed, yi) {
  if (is.null(seed)) return(NULL)
  as.integer(seed) + 10007L * as.integer(yi)
}

run_trend_analysis <- function(trend_df, base_specs, n_iter = 2000,
                                gwp = "AR5", seed = 42,
                                # Year-to-year correlation mode per IPCC Vol.1
                                # Ch.3 §3.2.2.4.
                                #   "full"    = same coefficient draws every year
                                #               (default). AD redrawn per year.
                                #   "partial" = AR(1) across years (rho) for
                                #               each coefficient draw.
                                #   "none"    = independent per year.
                                year_corr = c("full", "partial", "none"),
                                ar1_rho   = 0.7,
                                # Round 9: filter the per-year total_co2e by the
                                # selected emission sources. NULL (or all keys)
                                # = include every source.
                                emission_sources = NULL,
                                # Optional per-year progress callback, called
                                # as progress_fn(yi, n_years, year_label).
                                progress_fn = NULL,
                                # 2026-10-16: the same inputs single-year mode
                                # gives build_systems_data(). manure = NULL
                                # falls back to the 70/30 default split.
                                manure = NULL,
                                crossgroup = c("shared", "independent"),
                                corr_matrix = NULL,
                                sg_to_mm = list(),
                                # Which years' sample matrices to keep:
                                # "ends" = first and last (what the trend
                                # sensitivity views read), "none", or "all".
                                keep_samples = c("ends", "none", "all"),
                                # Rows kept per retained sample matrix. The
                                # Shiny app passes 4000, as single-year does.
                                keep_sample_rows = NULL,
                                # 2026-10-30: animal numbers, between groups
                                # (0..1) and between years ("none" = annual
                                # survey, "full" = one census interpolated,
                                # "partial" = AR(1))
                                n_group_rho = 0,
                                n_year_corr = c("none", "full", "partial")) {
  year_corr  <- match.arg(year_corr)
  crossgroup <- match.arg(crossgroup)
  n_year_corr <- match.arg(n_year_corr)
  act_gen <- if (n_group_rho > 0 || n_year_corr != "none")
    make_activity_generator(n_iter, seed = seed, rho_group = n_group_rho,
                            year_corr = n_year_corr, rho = ar1_rho) else NULL
  keep_samples <- match.arg(keep_samples)
  n_iter <- as.integer(n_iter)

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
  # A long frame built straight from a parameter sheet carries the key
  # columns rather than a group column; derive it so both shapes work.
  if (!"group" %in% names(trend_df) &&
      all(c("cattle_type", "aggregation_level") %in% names(trend_df)))
    trend_df$group <- make_group_key(trend_df)

  trend_df$year <- suppressWarnings(as.integer(trend_df$year))
  trend_df <- trend_df[!is.na(trend_df$year), , drop = FALSE]
  years <- sort(unique(trend_df$year))
  if (length(years) < 2)
    stop("Trend CSV must contain at least 2 distinct years.")
  n_years <- length(years)

  # ---- coefficient draws across years -----------------------------------
  # "full": one set of per-group blocks, reused every year.
  # "partial": a generator yielding the next year's blocks, AR(1)-linked.
  # "none": no blocks; each year builds its own shared draws with its own seed.
  # 2026-11-04: one generator for both links, fed each year's own specs, so
  # a coefficient's time series reaches the draws (see
  # make_year_block_generator() in R/systems_builder.R).
  year_blocks <- if (year_corr %in% c("full", "partial"))
    make_year_block_generator(base_specs, n_iter, seed = seed,
                              rho = if (year_corr == "full") 1 else ar1_rho,
                              crossgroup = crossgroup, corr_matrix = corr_matrix) else NULL

  rows            <- list()
  co2e_by_year    <- list()
  inventory_by_year <- list()
  system_summary  <- list()
  samples_by_year <- list()
  n_nonfinite     <- list()
  shared_summary  <- NULL

  # 2026-11-04: the Tab 4 source ticks filter each year's whole result
  # (inventory and groups) through filter_sim_sources() (R/utils_sources.R),
  # so the per-source frames, the group summaries and the totals agree. The
  # old filter rewrote the yearly total only.
  srcs <- normalize_sources(emission_sources)

  for (yi in seq_along(years)) {
    y <- years[yi]
    year_slice <- trend_df[trend_df$year == y, , drop = FALSE]
    ps <- .trend_year_specs(year_slice, base_specs)

    blocks <- if (!is.null(year_blocks)) year_blocks(ps, yi) else NULL

    year_seed <- .trend_year_seed(seed, yi)
    built <- build_systems_data(ps, manure = manure, n_iter = n_iter,
                                seed = year_seed, crossgroup = crossgroup,
                                corr_matrix = corr_matrix, sg_to_mm = sg_to_mm,
                                pre_sampled_blocks = blocks,
                                pre_sampled_activity = if (!is.null(act_gen)) act_gen(ps) else NULL)
    if (is.null(shared_summary) && !is.null(built$shared$summary))
      shared_summary <- built$shared$summary

    sim <- run_inventory_simulation(
      built$systems, n_iter = n_iter, gwp = gwp,
      seed = year_seed,
      keep_sample_rows = keep_sample_rows
    )
    sim <- filter_sim_sources(sim, srcs, gwp)

    inv  <- sim$inventory
    co2e <- inv$total_co2e
    # The sampler's physical floors (mc_sampling.R) keep the energy chain
    # finite; this is the second line of defence, and the count is reported
    # rather than hidden.
    n_nonfinite[[as.character(y)]] <- sum(!is.finite(co2e))
    m    <- mean(co2e, na.rm = TRUE)
    s    <- stats::sd(co2e, na.rm = TRUE)
    lo   <- stats::quantile(co2e, 0.025, names = FALSE, na.rm = TRUE)
    hi   <- stats::quantile(co2e, 0.975, names = FALSE, na.rm = TRUE)
    moe  <- if (m > 0) ((hi - lo) / 2) / m * 100 else NA_real_
    cv   <- if (m > 0) s / m * 100 else NA_real_

    yl <- as.character(y)
    co2e_by_year[[yl]]      <- co2e
    inventory_by_year[[yl]] <- inv
    system_summary[[yl]]    <- .trend_system_summary(sim$by_system, y)
    if (keep_samples == "all" ||
        (keep_samples == "ends" && (yi == 1L || yi == n_years)))
      samples_by_year[[yl]] <- .trend_keep_samples(sim$by_system)

    rows[[length(rows) + 1]] <- data.frame(
      Year         = y,
      Mean_t_CO2eq = round(m, 2),
      CI_Lower_t   = round(lo, 2),
      CI_Upper_t   = round(hi, 2),
      CV_pct       = round(cv, 2),
      MoE_95_pct   = round(moe, 1)
    )

    # The per-system results frames are the memory that used to accumulate:
    # drop them before the next year is built.
    rm(sim, built, inv)
    gc(FALSE)

    if (is.function(progress_fn))
      try(progress_fn(yi, n_years, yl), silent = TRUE)
  }

  out <- do.call(rbind, rows)
  base_mean <- out$Mean_t_CO2eq[1]
  out$Delta_vs_base_pct <- round((out$Mean_t_CO2eq - base_mean) / base_mean * 100, 1)
  # Round 8: year-over-year % change column for IPCC-style stepwise reporting
  out$YoY_pct <- c(NA_real_, round(diff(out$Mean_t_CO2eq) /
                                    out$Mean_t_CO2eq[-nrow(out)] * 100, 1))
  attr(out, "year_corr") <- year_corr

  # Round 8: per-iteration trend metrics, slope (t CO2eq/yr) via closed-form
  # least squares per iteration, and Delta total (Y_N - Y_1) per iteration.
  # Both reported as mean + empirical 2.5/97.5 % CI per IPCC Vol 1 Ch 3 §3.7.
  yr_vec <- as.numeric(years)
  co2e_mat <- do.call(cbind, co2e_by_year)  # n_iter x n_years
  colnames(co2e_mat) <- as.character(years)
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
    # per-system thinned draws for the years in keep_samples; read by the
    # trend sensitivity views through aggregate_sensitivity()
    samples_by_year = samples_by_year,
    co2e_by_year    = co2e_by_year,
    co2e_matrix     = co2e_mat,
    # per-iteration per-source inventory totals for every year: what a
    # two-year comparison and the IPCC trend columns are computed from
    inventory_by_year = inventory_by_year,
    # per-system, per-source mean and 95% bounds for every year
    system_summary  = do.call(rbind, system_summary),
    shared_summary  = shared_summary,
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
    emission_sources = srcs,
    n_group_rho = n_group_rho,
    n_year_corr = n_year_corr,
    years     = years,
    # iterations per year whose total was not finite and were left out of
    # the summaries above (0 everywhere on a healthy run)
    n_nonfinite_by_year = unlist(n_nonfinite)
  )
}

# Sensitivity of a single year's total to its inputs, from the retained
# per-system draws. Wraps aggregate_sensitivity() so the caller does not
# need to know the retained shape.
trend_sensitivity_year <- function(res, year = NULL, method = "both") {
  if (is.null(res$samples_by_year) || !length(res$samples_by_year)) return(NULL)
  yl <- if (is.null(year)) names(res$samples_by_year)[length(res$samples_by_year)]
        else as.character(year)
  bs <- res$samples_by_year[[yl]]
  out <- res$co2e_by_year[[yl]]
  if (is.null(bs) || is.null(out)) return(NULL)
  aggregate_sensitivity(bs, out, method = method, sources = res$emission_sources)
}

# Sensitivity of the first-to-last change to the inputs of both years. The
# two years' draws are placed side by side, labelled by group and year, and
# regressed on the per-iteration delta.
# 2026-11-04: columns that cannot move a group's emissions are left out of
# the trend-change regression: the draws of a manure system the group does
# not use (its allocation fraction is 0 in every draw: MCF, EF3, Frac_GasMS,
# Frac_LeachMS and the fraction itself) and any constant column. Each group
# carries six manure systems; over two years and 27 groups the regression
# had more inputs (over 3,000) than draws (2,000), and its coefficients ran
# into the thousands.
.drop_inert_columns <- function(samp) {
  cn <- colnames(samp)
  fr <- grep("^fraction_", cn, value = TRUE)
  unused <- sub("^fraction_", "", fr[vapply(fr, function(f) all(samp[, f] == 0, na.rm = TRUE), logical(1))])
  drop <- cn %in% as.vector(outer(c("MCF_", "EF3_", "Frac_GasMS_", "Frac_LeachMS_", "fraction_"), unused, paste0))
  rng <- apply(samp, 2, function(v) diff(range(v, na.rm = TRUE)))
  drop <- drop | !is.finite(rng) | rng == 0
  samp[, !drop, drop = FALSE]
}

trend_sensitivity_delta <- function(res, method = "both", max_rows = 4000L) {
  sb <- res$samples_by_year
  if (is.null(sb) || length(sb) < 2) return(NULL)
  y1 <- names(sb)[1]; yN <- names(sb)[length(sb)]
  # 2026-11-04: the production system joins the sub-category in the label
  # when the inventory has several ("N (dairy_cows, commercial) 1990"); the
  # sub-category alone gave repeated names that data.frame() numbered
  # ("N (dairy_cows) 1990.1").
  lv_all <- unique(unlist(lapply(sb, function(bs) vapply(names(bs), function(sn) {
    parts <- strsplit(sn, "||", fixed = TRUE)[[1]]; if (length(parts) >= 2) parts[2] else "" }, character(1)))))
  multi_level <- length(setdiff(lv_all, "")) > 1L
  label <- function(bs, tag) {
    blocks <- lapply(names(bs), function(sn) {
      samp <- bs[[sn]]$samples
      if (is.null(samp) || ncol(samp) == 0) return(NULL)
      if (!is.null(res$emission_sources) && !all_sources_selected(res$emission_sources)) {
        samp <- samp[, sample_columns_for_sources(colnames(samp), res$emission_sources), drop = FALSE]
        if (ncol(samp) == 0) return(NULL)
      }
      samp <- .drop_inert_columns(samp)
      if (ncol(samp) == 0) return(NULL)
      parts <- strsplit(sn, "||", fixed = TRUE)[[1]]
      sc <- if (length(parts) >= 3 && nzchar(parts[3])) parts[3] else sn
      if (multi_level && length(parts) >= 2 && nzchar(parts[2])) sc <- paste0(sc, ", ", parts[2])
      colnames(samp) <- paste0(colnames(samp), " (", sc, ") ", tag)
      samp
    })
    blocks <- Filter(Negate(is.null), blocks)
    if (!length(blocks)) return(NULL)
    if (length(blocks) == 1) blocks[[1]] else do.call(cbind, blocks)
  }
  a <- label(sb[[y1]], y1); b <- label(sb[[yN]], yN)
  if (is.null(a) || is.null(b)) return(NULL)
  m <- min(nrow(a), nrow(b), length(res$delta_total$per_iter), max_rows)
  cm <- as.matrix(cbind(a[seq_len(m), , drop = FALSE], b[seq_len(m), , drop = FALSE]))
  rm(a, b)
  # 2026-11-04: inputs that move together are one input for the regression.
  # Animal numbers drawn as one count split into groups, and a count or a
  # coefficient linked between the two years, have (almost) the same ranks
  # in every column; regressed side by side they are collinear, and the
  # standardised coefficients ran to +/-30 (an SRC lies between -1 and +1).
  # Columns of one parameter whose rank correlation is above 0.999 are
  # merged, as aggregate_sensitivity() does for the single-year run: the
  # animal numbers into their sum, any other input into its first column,
  # labelled with the groups and the years it covers.
  base_of <- sub(" \\(.*$", "", colnames(cm))
  year_of <- sub("^.* ", "", colnames(cm))
  tag_of  <- sub("^.*\\((.*)\\) [^ ]+$", "\\1", colnames(cm))
  cols <- list(); nms <- character(0)
  for (bp in unique(base_of)) {
    idx <- which(base_of == bp)
    if (length(idx) == 1L) { cols[[length(cols) + 1L]] <- cm[, idx]; nms <- c(nms, colnames(cm)[idx]); next }
    R <- apply(cm[, idx, drop = FALSE], 2, rank, ties.method = "average")
    C <- suppressWarnings(stats::cor(R)); C[!is.finite(C)] <- 0
    left <- seq_along(idx)
    while (length(left)) {
      ref <- left[1]
      pick <- unique(c(ref, left[C[left, ref] > 0.999]))
      left <- setdiff(left, pick)
      mem <- idx[pick]
      if (length(mem) == 1L) { cols[[length(cols) + 1L]] <- cm[, mem]; nms <- c(nms, colnames(cm)[mem]); next }
      yrs <- unique(year_of[mem]); tg <- unique(tag_of[mem])
      grp_txt <- if (length(tg) > 1L) sprintf("%s%d groups", if (bp == "N") "one count, " else "", length(tg)) else tg
      cols[[length(cols) + 1L]] <- if (bp == "N") rowSums(cm[, mem, drop = FALSE]) else cm[, mem[1]]
      nms <- c(nms, sprintf("%s (%s) %s", bp, grp_txt, paste(yrs, collapse = " and ")))
    }
  }
  combined <- do.call(cbind, cols); colnames(combined) <- make.unique(nms, sep = " #")
  rm(cm, cols); gc(FALSE)
  y <- res$delta_total$per_iter[seq_len(m)]
  # 2026-11-04: screening before the regression. With two years of inputs
  # the regression can still hold several hundred columns for 2,000 draws,
  # and minor inputs then take large coefficients by chance. The inputs are
  # ranked by their rank correlation with the change and at most one per ten
  # draws (and at least 50) enter the regression, the usual screening step
  # of a Monte Carlo sensitivity analysis. The ones left out have the
  # weakest correlation with the change.
  k_max <- max(50L, floor(m / 10))
  n_in <- ncol(combined)
  if (n_in > k_max) {
    rc <- suppressWarnings(abs(stats::cor(combined, y, method = "spearman")))[, 1]
    rc[!is.finite(rc)] <- 0
    keep <- order(-rc)[seq_len(k_max)]
    combined <- combined[, sort(keep), drop = FALSE]
  }
  out <- sensitivity_analysis(as.data.frame(combined), y, method = method)
  if (!is.null(out)) attr(out, "screened") <- c(inputs = n_in, regressed = ncol(combined))
  out
}
