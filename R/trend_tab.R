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
# computed from one group. On the Zambia file: every group given N = 252,503
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

# R2.3: convert the Parameter_TimeSeries sheet (one row per group per year,
# parameters as columns) into the long format run_trend_analysis() expects:
# (group, year, parameter, mean, uncertainty_pct). The group key is carried
# so the per-year specs update the right row. Blank cells are dropped: the
# translator leaves a column blank where a value does not change across
# years, and that blank means "keep the template value".
trend_df_from_population <- function(population, base_specs,
                                      default_uncertainty_pct = 15) {
  if (is.null(population) || ncol(population) < 2)
    stop("No time-series data available: load a template with a Parameter_TimeSeries sheet, or use the CSV upload override below.")
  if (!"year" %in% names(population))
    stop("Time-series must have a 'year' column.")
  key_cols <- intersect(c("cattle_type", "aggregation_level", "sub_category",
                          "system", "subsystem"), names(population))
  group <- if (length(key_cols)) make_group_key(population) else rep("", nrow(population))
  param_cols <- setdiff(names(population), c("year", key_cols))
  rows <- list()
  for (p in param_cols) {
    vals <- suppressWarnings(as.numeric(population[[p]]))
    if (all(is.na(vals))) next          # a label column, or a blank one
    pct_default <- default_uncertainty_pct
    if (!is.null(base_specs)) {
      hit <- which(base_specs$parameter == p)
      if (length(hit) > 0 && !is.na(base_specs$uncertainty_pct[hit[1]]))
        pct_default <- base_specs$uncertainty_pct[hit[1]]
    }
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
# correlation of 1.000 (31 of 32 groups on Zambia, every pair of
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
                                keep_sample_rows = NULL) {
  year_corr  <- match.arg(year_corr)
  crossgroup <- match.arg(crossgroup)
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
  full_blocks <- if (year_corr == "full")
    build_full_coefficient_blocks(base_specs, n_iter, seed = seed,
                                  crossgroup = crossgroup) else NULL
  next_partial <- if (year_corr == "partial")
    make_partial_block_generator(base_specs, n_iter, seed = seed,
                                 rho = ar1_rho, crossgroup = crossgroup) else NULL

  rows            <- list()
  co2e_by_year    <- list()
  inventory_by_year <- list()
  system_summary  <- list()
  samples_by_year <- list()
  n_nonfinite     <- list()
  shared_summary  <- NULL

  # Round 9: emission-source filter, applied per year on the inventory
  # frame's per-source totals. NULL or all keys = include all.
  all_src_keys <- c("enteric_ch4", "manure_ch4", "manure_n2o_direct",
                     "manure_n2o_indirect",
                     "pasture_n2o_direct", "pasture_n2o_indirect")
  srcs <- if (is.null(emission_sources) || length(emission_sources) == 0L)
            all_src_keys else emission_sources
  apply_source_filter <- length(srcs) > 0L && length(srcs) < length(all_src_keys)
  gwp_vals <- if (!is.null(GWP_VALUES[[gwp]])) GWP_VALUES[[gwp]]
              else GWP_VALUES[["AR5"]]

  filter_co2e <- function(inv) {
    if (!apply_source_filter) return(inv$total_co2e)
    legacy_pasture <- "pasture_n2o" %in% srcs
    ch4 <- (if ("enteric_ch4" %in% srcs) inv$total_enteric_ch4 else 0) +
           (if ("manure_ch4"  %in% srcs) inv$total_manure_ch4  else 0)
    n2o <- (if ("manure_n2o_direct"   %in% srcs) inv$total_direct_n2o_mm   else 0) +
           (if ("manure_n2o_indirect" %in% srcs) inv$total_indirect_n2o_mm else 0) +
           (if (legacy_pasture || "pasture_n2o_direct"   %in% srcs) inv$total_direct_n2o_prp   else 0) +
           (if (legacy_pasture || "pasture_n2o_indirect" %in% srcs) inv$total_indirect_n2o_prp else 0)
    ch4 * gwp_vals$CH4 + n2o * gwp_vals$N2O
  }

  for (yi in seq_along(years)) {
    y <- years[yi]
    year_slice <- trend_df[trend_df$year == y, , drop = FALSE]
    ps <- .trend_year_specs(year_slice, base_specs)

    blocks <- if (year_corr == "full") full_blocks
              else if (year_corr == "partial") next_partial()
              else NULL

    year_seed <- .trend_year_seed(seed, yi)
    built <- build_systems_data(ps, manure = manure, n_iter = n_iter,
                                seed = year_seed, crossgroup = crossgroup,
                                corr_matrix = corr_matrix, sg_to_mm = sg_to_mm,
                                pre_sampled_blocks = blocks)
    if (is.null(shared_summary) && !is.null(built$shared$summary))
      shared_summary <- built$shared$summary

    sim <- run_inventory_simulation(
      built$systems, n_iter = n_iter, gwp = gwp,
      seed = year_seed,
      keep_sample_rows = keep_sample_rows
    )

    inv  <- sim$inventory
    co2e <- filter_co2e(inv)
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
  aggregate_sensitivity(bs, out, method = method)
}

# Sensitivity of the first-to-last change to the inputs of both years. The
# two years' draws are placed side by side, labelled by group and year, and
# regressed on the per-iteration delta.
trend_sensitivity_delta <- function(res, method = "both", max_rows = 4000L) {
  sb <- res$samples_by_year
  if (is.null(sb) || length(sb) < 2) return(NULL)
  y1 <- names(sb)[1]; yN <- names(sb)[length(sb)]
  label <- function(bs, tag) {
    blocks <- lapply(names(bs), function(sn) {
      samp <- bs[[sn]]$samples
      if (is.null(samp) || ncol(samp) == 0) return(NULL)
      parts <- strsplit(sn, "||", fixed = TRUE)[[1]]
      sc <- if (length(parts) >= 3 && nzchar(parts[3])) parts[3] else sn
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
  combined <- cbind(a[seq_len(m), , drop = FALSE], b[seq_len(m), , drop = FALSE])
  # identical columns (a coefficient shared across groups, or held across
  # both years) are regressed once. 2026-10-29: found from a numeric
  # fingerprint confirmed with identical(), as aggregate_sensitivity() does;
  # pasting every column into a string took 37 s on Zambia (2 x 1,250
  # columns), which was most of the wait before the trend results showed.
  cm <- as.matrix(combined)
  fp <- paste(colSums(cm), colSums(cm * cm), cm[1L, ], cm[nrow(cm), ], sep = "|")
  grp <- match(fp, fp)
  for (j in which(grp != seq_along(grp)))
    if (!identical(unname(cm[, j]), unname(cm[, grp[j]]))) grp[j] <- j
  combined <- combined[, !duplicated(grp), drop = FALSE]
  sensitivity_analysis(combined, res$delta_total$per_iter[seq_len(m)], method = method)
}
