# Trend reporting (2026-10-22): what a compiler reports from a multi-year
# run, in the shape of IPCC 2006 Vol. 1 Ch. 3 Table 3.3, the general
# reporting table for uncertainty. Everything here is computed from the
# per-year, per-iteration totals that run_trend_analysis() retains in
# res$inventory_by_year, so no simulation is re-run except for the optional
# AD/EF split (trend_decompose_year), which the single-year path also does
# as two extra runs.
#
# Table 3.3 columns and where each comes from:
#   C  base year emissions          mean of the base year's draws
#   D  year t emissions             mean of year t's draws
#   E  activity data uncertainty    AD-only run for year t (optional)
#   F  emission factor uncertainty  EF-only run for year t (optional)
#   G  combined uncertainty         2.5 / 97.5 percentiles of year t, as
#                                   (-) and (+) % of the mean
#   H  contribution to variance     cov(row, total) / var(total) in year t;
#      in year t                    sums to 1 over the six sources, which is
#                                   what the foot of the table requires when
#                                   sources are correlated (Approach 2)
#   I  trend                        (mean_t - mean_base) / mean_base * 100
#   J  uncertainty in the trend     2.5 / 97.5 percentiles of the per-
#                                   iteration trend, as percentage points
#                                   from column I (the IPCC convention: a
#                                   trend of -5% with a range of -8% to -3%
#                                   is reported as -3 to +2)
#   K  approach and comments        Approach 2 (Monte Carlo) and the
#                                   year-to-year correlation setting
# The table is in t CO2eq, the unit used everywhere else in the tool; IPCC
# prints Gg CO2eq. Divide by 1,000 to convert.

.TREND_IPCC_ROWS <- data.frame(
  var = c("total_enteric_ch4", "total_manure_ch4",
          "total_direct_n2o_mm", "total_indirect_n2o_mm",
          "total_direct_n2o_prp", "total_indirect_n2o_prp",
          "total_ch4", "total_n2o", "total_co2e"),
  category = c(
    "3.A.1 Enteric Fermentation: Cattle",
    "3.B.1 Manure Management: Cattle (CH₄)",
    "3.B.1 Manure Management: Cattle (N₂O direct)",
    "3.B.5 Manure Management: Cattle (N₂O indirect)",
    "3.D.1.c Direct N₂O: Pasture/Range/Paddock",
    "3.D.2 Indirect N₂O: Pasture/Range/Paddock",
    "Total CH₄", "Total N₂O", "Total CO₂eq"),
  gas = c("CH4", "CH4", "N2O", "N2O", "N2O", "N2O", "CH4", "N2O", "CO2eq"),
  is_source = c(rep(TRUE, 6L), FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

.gas_label <- function(gas) {
  c(CH4 = "CH₄", N2O = "N₂O", CO2eq = "CO₂eq")[gas]
}

# One row's per-iteration emissions in t CO2eq for one year.
.trend_row_co2e <- function(inv, var, gas, gwp = "AR5") {
  x <- inv[[var]]
  if (is.null(x)) return(NULL)
  g <- GWP_VALUES[[gwp]]
  switch(gas, CH4 = x * g$CH4, N2O = x * g$N2O, x)
}

.q <- function(x, p) stats::quantile(x, p, names = FALSE, na.rm = TRUE)

# Per-source summary for one year: mean, 95% bounds, and the (-) / (+)
# half-widths as % of the mean. One row per entry of .TREND_IPCC_ROWS.
trend_year_sources <- function(res, year, gwp = "AR5") {
  inv <- res$inventory_by_year[[as.character(year)]]
  if (is.null(inv)) return(NULL)
  rows <- lapply(seq_len(nrow(.TREND_IPCC_ROWS)), function(i) {
    r <- .TREND_IPCC_ROWS[i, ]
    x <- .trend_row_co2e(inv, r$var, r$gas, gwp)
    if (is.null(x)) return(NULL)
    m <- mean(x, na.rm = TRUE); lo <- .q(x, 0.025); hi <- .q(x, 0.975)
    data.frame(var = r$var, category = r$category, gas = .gas_label(r$gas),
               year = as.integer(year), mean_t_co2e = m, lo = lo, hi = hi,
               moe_pct   = if (m > 0) (hi - lo) / 2 / m * 100 else NA_real_,
               lower_pct = if (m > 0) (m - lo) / m * 100 else NA_real_,
               upper_pct = if (m > 0) (hi - m) / m * 100 else NA_real_,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Per-source summary for every retained year, long format (one row per
# source and year). This is the sheet a compiler pastes into a workbook.
trend_sources_long <- function(res, gwp = "AR5") {
  do.call(rbind, lapply(names(res$inventory_by_year), function(y)
    trend_year_sources(res, y, gwp)))
}

# Two years side by side, per source: the numbers behind columns C, D, G,
# H, I and J of Table 3.3, in one frame.
trend_compare_years <- function(res, base_year, year_t, gwp = "AR5") {
  b <- res$inventory_by_year[[as.character(base_year)]]
  t <- res$inventory_by_year[[as.character(year_t)]]
  if (is.null(b) || is.null(t)) return(NULL)
  total_t <- .trend_row_co2e(t, "total_co2e", "CO2eq", gwp)
  var_tot <- stats::var(total_t, na.rm = TRUE)
  rows <- lapply(seq_len(nrow(.TREND_IPCC_ROWS)), function(i) {
    r  <- .TREND_IPCC_ROWS[i, ]
    xb <- .trend_row_co2e(b, r$var, r$gas, gwp)
    xt <- .trend_row_co2e(t, r$var, r$gas, gwp)
    if (is.null(xb) || is.null(xt)) return(NULL)
    mb <- mean(xb, na.rm = TRUE); mt <- mean(xt, na.rm = TRUE)
    lob <- .q(xb, 0.025); hib <- .q(xb, 0.975)
    lot <- .q(xt, 0.025); hit <- .q(xt, 0.975)
    # column I, on the means, as IPCC defines it
    trend <- if (mb > 0) (mt - mb) / mb * 100 else NA_real_
    # column J: the per-iteration trend's 2.5 / 97.5 percentiles, as
    # percentage points from column I. With coefficients fully correlated
    # across years their error cancels here, which is the point of
    # Approach 2 for trends.
    ok <- is.finite(xb) & is.finite(xt) & xb > 0
    tr_i <- if (mb > 0 && sum(ok) > 10) (xt[ok] - xb[ok]) / xb[ok] * 100 else NA_real_
    j_lo <- if (all(is.na(tr_i))) NA_real_ else .q(tr_i, 0.025) - trend
    j_hi <- if (all(is.na(tr_i))) NA_real_ else .q(tr_i, 0.975) - trend
    # column H
    contrib <- if (is.finite(var_tot) && var_tot > 0)
      stats::cov(xt, total_t, use = "complete.obs") / var_tot else NA_real_
    data.frame(
      var = r$var, category = r$category, gas = .gas_label(r$gas),
      is_source = r$is_source,
      base_mean = mb, base_lower_pct = if (mb > 0) (mb - lob) / mb * 100 else NA_real_,
      base_upper_pct = if (mb > 0) (hib - mb) / mb * 100 else NA_real_,
      base_moe_pct = if (mb > 0) (hib - lob) / 2 / mb * 100 else NA_real_,
      t_mean = mt, t_lower_pct = if (mt > 0) (mt - lot) / mt * 100 else NA_real_,
      t_upper_pct = if (mt > 0) (hit - mt) / mt * 100 else NA_real_,
      t_moe_pct = if (mt > 0) (hit - lot) / 2 / mt * 100 else NA_real_,
      contribution = contrib,
      trend_pct = trend, trend_lo_pp = j_lo, trend_hi_pp = j_hi,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  attr(out, "base_year") <- as.integer(base_year)
  attr(out, "year_t")    <- as.integer(year_t)
  out
}

# The headline numbers a compiler has to report, as a list, so the UI and
# the Word report can phrase them in either language.
trend_headline <- function(res, base_year, year_t, gwp = "AR5") {
  cmp <- trend_compare_years(res, base_year, year_t, gwp)
  if (is.null(cmp)) return(NULL)
  tot <- cmp[cmp$var == "total_co2e", ]
  list(
    base_year = as.integer(base_year), year_t = as.integer(year_t),
    base_mean = tot$base_mean, base_moe = tot$base_moe_pct,
    base_lower = tot$base_lower_pct, base_upper = tot$base_upper_pct,
    base_lo = tot$base_mean * (1 - tot$base_lower_pct / 100),
    base_hi = tot$base_mean * (1 + tot$base_upper_pct / 100),
    t_mean = tot$t_mean, t_moe = tot$t_moe_pct,
    t_lower = tot$t_lower_pct, t_upper = tot$t_upper_pct,
    t_lo = tot$t_mean * (1 - tot$t_lower_pct / 100),
    t_hi = tot$t_mean * (1 + tot$t_upper_pct / 100),
    trend_pct = tot$trend_pct,
    trend_lo_pp = tot$trend_lo_pp, trend_hi_pp = tot$trend_hi_pp,
    # the same range as a range of the trend itself
    trend_lo_pct = tot$trend_pct + tot$trend_lo_pp,
    trend_hi_pct = tot$trend_pct + tot$trend_hi_pp,
    # does the 95% range of the change include "no change"?
    zero_inside = isTRUE(tot$trend_pct + tot$trend_lo_pp <= 0 &&
                         tot$trend_pct + tot$trend_hi_pp >= 0),
    n_years = length(res$years),
    year_corr = res$year_corr,
    # draws behind the two years when they come from a reporting pair
    n_iter_pair = attr(res, "n_iter_pair")
  )
}

# Table 3.3 for the two chosen years. decomp is NULL (columns E and F
# blank, which IPCC allows) or the result of trend_decompose_year() for
# year t.
trend_ipcc_table <- function(res, base_year, year_t, gwp = "AR5",
                             decomp = NULL, year_corr = "full") {
  cmp <- trend_compare_years(res, base_year, year_t, gwp)
  if (is.null(cmp)) return(NULL)
  pick <- function(frame, var, col) {
    if (is.null(frame)) return(rep(NA_real_, length(var)))
    vapply(var, function(v) {
      row <- frame[frame$variable == v, , drop = FALSE]
      if (nrow(row) == 0L || !col %in% names(row)) NA_real_ else row[[col]][1]
    }, numeric(1))
  }
  ad <- if (!is.null(decomp)) decomp$ad_only else NULL
  ef <- if (!is.null(decomp)) decomp$ef_only else NULL
  yc <- switch(year_corr %||% "full",
               full    = "coefficients fully correlated between years",
               partial = "coefficients partly correlated between years (factors revised every few years)",
               none    = "coefficients independent between years",
               year_corr)
  n_src <- sum(cmp$is_source)
  out <- data.frame(
    `IPCC category` = cmp$category,
    Gas = cmp$gas,
    `Base year emissions (t CO₂eq)` = round(cmp$base_mean, 1),
    `Year t emissions (t CO₂eq)`    = round(cmp$t_mean, 1),
    `AD uncertainty (-) %` = round(pick(ad, cmp$var, "lower_pct"), 1),
    `AD uncertainty (+) %` = round(pick(ad, cmp$var, "upper_pct"), 1),
    `EF uncertainty (-) %` = round(pick(ef, cmp$var, "lower_pct"), 1),
    `EF uncertainty (+) %` = round(pick(ef, cmp$var, "upper_pct"), 1),
    `Combined uncertainty (-) %` = round(cmp$t_lower_pct, 1),
    `Combined uncertainty (+) %` = round(cmp$t_upper_pct, 1),
    `Contribution to variance in year t` = round(cmp$contribution, 4),
    `Trend (% of base year)` = round(cmp$trend_pct, 1),
    `Trend uncertainty (-) pp` = round(cmp$trend_lo_pp, 1),
    `Trend uncertainty (+) pp` = round(cmp$trend_hi_pp, 1),
    `Approach and comments` = c(rep("Approach 2 (Monte Carlo)", n_src),
                                rep("Approach 2 (Monte Carlo); gas total", 2L),
                                paste0("Approach 2 (Monte Carlo); ", yc)),
    check.names = FALSE, stringsAsFactors = FALSE, row.names = NULL)
  attr(out, "base_year") <- as.integer(base_year)
  attr(out, "year_t")    <- as.integer(year_t)
  attr(out, "has_ad_ef") <- !is.null(decomp)
  attr(out, "n_iter_pair") <- attr(res, "n_iter_pair")
  out
}

# AD/EF split for one year of the trend: the two extra simulations the
# single-year path runs (coefficients held at their means, then activity
# data held at their means), on the year's systems built exactly as the
# trend built them. Returns the two uncertainty frames plus the combined
# one, in the shape format_ipcc_table() and trend_ipcc_table() read.
trend_decompose_year <- function(trend_df, base_specs, year, n_iter = 2000,
                                 gwp = "AR5", seed = 42, manure = NULL,
                                 crossgroup = "shared", corr_matrix = NULL,
                                 sg_to_mm = list(), year_corr = "full",
                                 keep_sample_rows = 4000L, progress_fn = NULL,
                                 n_group_rho = 0, n_year_corr = "none", ar1_rho = 0.7) {
  year <- as.integer(year)
  year_df <- trend_df[trend_df$year == year, , drop = FALSE]
  specs <- .trend_year_specs(year_df, base_specs)
  # 2026-10-30: this year's animal-number draws, chained as the series
  # chains them (the generator is stepped up to this year)
  act_block <- NULL
  if (n_group_rho > 0 || !identical(n_year_corr, "none")) {
    years_all <- sort(unique(as.integer(trend_df$year)))
    act_gen <- make_activity_generator(n_iter, seed = seed, rho_group = n_group_rho,
                                       year_corr = n_year_corr, rho = ar1_rho)
    for (k in seq_len(match(year, years_all)))
      act_block <- act_gen(.trend_year_specs(trend_df[trend_df$year == years_all[k], , drop = FALSE], base_specs))
  }
  # 2026-10-29: the year's own random stream, seeded as run_trend_analysis()
  # seeds it (.trend_year_seed on the year's index), so the AD-only and
  # EF-only runs of a year draw from the same streams as its combined run,
  # which is what the single-year path does with its one seed. Until now
  # they used the run seed itself, so every year's decomposition drew the
  # same numbers and none of them matched the combined run.
  yi <- match(year, sort(unique(as.integer(trend_df$year))))
  year_seed <- .trend_year_seed(seed, yi)
  # the same coefficient draws the trend run used for this year when the
  # blocks are shared across years
  blocks <- if (identical(year_corr, "full"))
    make_year_block_generator(base_specs, n_iter, seed = seed, rho = 1, crossgroup = crossgroup,
                              corr_matrix = corr_matrix)(specs, yi)
  else NULL
  built <- build_systems_data(specs, manure = manure, n_iter = n_iter, seed = year_seed,
                              crossgroup = crossgroup, corr_matrix = corr_matrix,
                              sg_to_mm = sg_to_mm, pre_sampled_blocks = blocks,
                              pre_sampled_activity = act_block)
  run_fixed <- function(fix_type, label) {
    if (is.function(progress_fn)) try(progress_fn(label), silent = TRUE)
    sys <- lapply(built$systems, fix_params_for_decomposition, fix_type = fix_type)
    sim <- run_inventory_simulation(sys, n_iter = n_iter, gwp = gwp, seed = year_seed,
                                    keep_sample_rows = keep_sample_rows)
    u <- calc_all_uncertainty(sim$inventory)
    rm(sys, sim); gc(FALSE)
    u
  }
  ad <- run_fixed("coefficient",   sprintf("AD-only run, year %d", year))
  ef <- run_fixed("activity_data", sprintf("EF-only run, year %d", year))
  rm(built, blocks); gc(FALSE)
  list(year = year, ad_only = ad, ef_only = ef)
}

# ---------------------------------------------------------------------------
# The two reported years at the reporting draw count (2026-10-29).
#
# The series runs every year at the trend count (2,000 by default), which
# is enough for the chart and the slope. The headline figures and IPCC
# Table 3.3 come from the base year and year t only, so those two are run
# again here at the single-year count (10,000 by default), as a PAIR: under
# year_corr = "full" both years take the same coefficient draws, so a
# coefficient's error cancels in the change between them exactly as in
# run_trend_analysis(); under "partial" the AR(1) generator is advanced to
# each year's index, so the two years carry the lag-k link of the series;
# under "none" they are independent. Each year keeps the seed the series
# gives it (.trend_year_seed on its index). The AD-only and EF-only
# simulations for year t (Table 3.3 columns E and F) run on the same
# systems at the same count, as trend_decompose_year() did on its own.
#
# Monte Carlo error at 2,000 draws against 10,000 on the test-inventory total: the
# standard error of the mean 0.30% against 0.13%; the 95% half-width known
# to plus or minus 1.2 points against 0.6 (knowledge/22, section 6).
#
# Returns the per-source totals of the two years (what trend_compare_years()
# reads), the AD/EF split of year t (what trend_ipcc_table() reads) and the
# settings, so the UI can tell whether a stored pair matches the chosen years.
.trend_pair_key <- function(base_year, year_t) paste(base_year, year_t, sep = "_")

trend_reporting_pair <- function(trend_df, base_specs, base_year, year_t,
                                 n_iter = 10000, gwp = "AR5", seed = 42,
                                 year_corr = "full", ar1_rho = 0.7,
                                 manure = NULL, crossgroup = "shared",
                                 corr_matrix = NULL, sg_to_mm = list(),
                                 # nothing reads the pair's input draws (the
                                 # trend tornadoes read the series), so one
                                 # row is kept: about 60 MB less at the peak
                                 # on the test inventory at 10,000
                                 keep_sample_rows = 1L, progress_fn = NULL,
                                 n_group_rho = 0, n_year_corr = "none") {
  n_iter <- as.integer(n_iter)
  trend_df$year <- suppressWarnings(as.integer(trend_df$year))
  years <- sort(unique(trend_df$year[!is.na(trend_df$year)]))
  pair  <- unique(as.integer(c(base_year, year_t)))
  yi    <- match(pair, years)
  # 2026-10-30: the animal-number draws, chained across years as the
  # series chains them, stepped up to the later of the two years
  act_blocks <- list()
  if (n_group_rho > 0 || !identical(n_year_corr, "none")) {
    act_gen <- make_activity_generator(n_iter, seed = seed, rho_group = n_group_rho,
                                       year_corr = n_year_corr, rho = ar1_rho)
    for (k in seq_len(max(yi))) {
      ab <- act_gen(.trend_year_specs(trend_df[trend_df$year == years[k], , drop = FALSE], base_specs))
      if (k %in% yi) act_blocks[[as.character(years[k])]] <- ab
    }
  }
  if (anyNA(yi)) stop("trend_reporting_pair: a chosen year is not in the series.")
  tick <- function(frac, label)
    if (is.function(progress_fn)) try(progress_fn(frac, label), silent = TRUE)

  # coefficient draws between the two years, linked as the series links them
  blocks <- list()
  # 2026-11-04: each year's blocks from that year's own specs (see
  # make_year_block_generator()); "full" asks for the two years directly,
  # "partial" steps through the chain up to the later one.
  yspecs <- function(k) .trend_year_specs(trend_df[trend_df$year == years[k], , drop = FALSE], base_specs)
  if (identical(year_corr, "full")) {
    gen <- make_year_block_generator(base_specs, n_iter, seed = seed, rho = 1,
                                     crossgroup = crossgroup, corr_matrix = corr_matrix)
    for (k in yi) blocks[[as.character(years[k])]] <- gen(yspecs(k), k)
  } else if (identical(year_corr, "partial")) {
    gen <- make_year_block_generator(base_specs, n_iter, seed = seed, rho = ar1_rho,
                                     crossgroup = crossgroup, corr_matrix = corr_matrix)
    for (k in seq_len(max(yi))) {
      bk <- gen(yspecs(k), k)
      if (k %in% yi) blocks[[as.character(years[k])]] <- bk
    }
  }

  inventory_by_year <- list(); decomp <- NULL
  n_steps <- length(pair) + 2L; step <- 0L
  fmt <- function(n) format(n, big.mark = ",")
  for (j in seq_along(pair)) {
    y  <- pair[j]
    ps <- .trend_year_specs(trend_df[trend_df$year == y, , drop = FALSE], base_specs)
    year_seed <- .trend_year_seed(seed, yi[j])
    built <- build_systems_data(ps, manure = manure, n_iter = n_iter, seed = year_seed,
                                crossgroup = crossgroup, corr_matrix = corr_matrix,
                                sg_to_mm = sg_to_mm,
                                pre_sampled_blocks = blocks[[as.character(y)]],
                                pre_sampled_activity = act_blocks[[as.character(y)]])
    run <- function(systems, label) {
      lo <- step / n_steps; hi <- (step + 1L) / n_steps
      tick(lo, label)
      sim <- run_inventory_simulation(
        systems, n_iter = n_iter, gwp = gwp, seed = year_seed,
        keep_sample_rows = keep_sample_rows,
        progress_cb = function(done, total)
          tick(lo + (hi - lo) * done / max(total, 1L), label))
      step <<- step + 1L
      sim
    }
    sim <- run(built$systems, sprintf("Year %d at %s draws", y, fmt(n_iter)))
    inventory_by_year[[as.character(y)]] <- sim$inventory
    rm(sim); gc(FALSE)
    if (y == as.integer(year_t)) {
      ad <- run(lapply(built$systems, fix_params_for_decomposition, fix_type = "coefficient"),
                sprintf("AD-only run, year %d", y))
      u_ad <- calc_all_uncertainty(ad$inventory); rm(ad)
      ef <- run(lapply(built$systems, fix_params_for_decomposition, fix_type = "activity_data"),
                sprintf("EF-only run, year %d", y))
      u_ef <- calc_all_uncertainty(ef$inventory); rm(ef)
      decomp <- list(year = y, ad_only = u_ad, ef_only = u_ef)
    }
    rm(built); gc(FALSE)
  }
  tick(1, "Done")
  list(base_year = as.integer(base_year), year_t = as.integer(year_t),
       n_iter = n_iter, seed = seed, year_corr = year_corr,
       inventory_by_year = inventory_by_year, decomp = decomp)
}

# The series result with the two reported years replaced by the pair's draws,
# for trend_compare_years(), trend_headline() and trend_ipcc_table(). The
# result is returned unchanged when there is no pair or it was run for other
# years, so the table then shows the series' own draws for the two years.
trend_reporting_res <- function(res, pair, base_year, year_t) {
  if (is.null(res) || is.null(pair)) return(res)
  if (!identical(as.integer(pair$base_year), as.integer(base_year)) ||
      !identical(as.integer(pair$year_t), as.integer(year_t))) return(res)
  for (y in names(pair$inventory_by_year))
    res$inventory_by_year[[y]] <- pair$inventory_by_year[[y]]
  attr(res, "n_iter_pair") <- pair$n_iter
  res
}
