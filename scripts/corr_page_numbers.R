# Numbers for section 6 of the correlations help page, from the test-inventory
# template of 1 November 17:13 (every series, range and coefficient equal
# to the file). Single year 2024 at 4,000 draws; trend 1990 to 2024 at
# 2,000 draws per year plus a 4,000-draw pair for the two reported years.
suppressMessages({for (f in list.files("R", "\\.R$", full.names = TRUE)) try(source(f), silent = TRUE)})
Sys.setenv(APP_RUNTIME_DIR = "C:/tmp/rt")
N_ITER <- 4000L; SEED <- 42L; GWP <- "AR5"
parsed <- parse_uploaded_template("test_data/inv_a/inv_a_1713.xlsx")
specs <- parsed$param_specs; manure <- parsed$manure
comp <- ensure_completeness(specs, region = parsed$metadata$region)
if (isTRUE(comp$valid)) specs <- comp$param_specs
sgm <- resolve_sub_category_matches(specs, manure)$matched
cat("the test inventory 2024: rows", nrow(specs), " groups", length(unique(make_group_key(specs))), " year", parsed$metadata$inventory_year %||% parsed$metadata$year, "\n")
summ <- function(x) { m <- mean(x); q <- quantile(x, c(0.025, 0.975), names = FALSE)
  c(mean_Mt = m / 1e6, lo_Mt = q[1] / 1e6, hi_Mt = q[2] / 1e6, moe_pct = (q[2] - q[1]) / (2 * m) * 100) }

cat("\n== From template: the check on the series (refine_preset_from_timeseries) ==\n")
r <- tryCatch(refine_preset_from_timeseries(parsed$population, specs$parameter), error = function(e) { cat("refine failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(r)) { cat("components:", paste(names(r), collapse = ", "), "\n"); for (nm in setdiff(names(r), "matrix")) { cat("--", nm, "\n"); print(r[[nm]]) } }

corr_for <- function(mode) switch(mode, none = NULL,
  preset = expand_corr_matrix(build_ipcc_preset_corr(specs$parameter), specs$parameter),
  timeseries = if (!is.null(r) && !is.null(r$matrix)) expand_corr_matrix(r$matrix, specs$parameter) else NULL)

run1 <- function(corr_mode, rho) {
  built <- build_systems_data(specs, manure = manure, n_iter = N_ITER, seed = SEED, crossgroup = "shared",
                              corr_matrix = corr_for(corr_mode), sg_to_mm = sgm, n_group_rho = rho)
  sim <- run_inventory_simulation(built$systems, n_iter = N_ITER, gwp = GWP, seed = SEED, pct_pregnant = 1, keep_sample_rows = 10L)
  out <- summ(sim$inventory$total_co2e); rm(built, sim); gc(FALSE); out
}
cat("\n== 6.1 ONE YEAR (2024): activity correlations (N between groups = one count split, rho 1) ==\n")
for (m in c("none", "preset", "timeseries")) { s <- run1(m, 1); cat(sprintf("%-12s mean %.2f Mt  95%% %.2f to %.2f  MoE %.1f%%\n", m, s[1], s[2], s[3], s[4])) }
cat("\n== 6.1 ONE YEAR (2024): N between groups (activity correlations none) ==\n")
for (rho in c(0, 0.5, 1)) { s <- run1("none", rho); cat(sprintf("rho %-4s mean %.2f Mt  95%% %.2f to %.2f  MoE %.1f%%\n", rho, s[1], s[2], s[3], s[4])) }

cat("\n== 6.2 TREND 1990 to 2024: factors between years x N between years (rho 1, correlations none) ==\n")
df <- trend_df_from_population(parsed$population, specs)
years <- sort(unique(as.integer(df$year))); y1 <- years[1]; yN <- years[length(years)]
cat("years:", y1, "to", yN, "; groups in the series:", length(unique(df$group_key %||% df$sub_category)), "\n")
for (yc in c("full", "partial", "none")) for (nyc in c("none", "partial", "full")) {
  t0 <- Sys.time()
  res <- run_trend_analysis(df, base_specs = specs, n_iter = 2000L, gwp = GWP, seed = SEED, year_corr = yc,
                            manure = manure, crossgroup = "shared", corr_matrix = NULL, sg_to_mm = sgm,
                            keep_samples = "none", n_group_rho = 1, n_year_corr = nyc)
  pair <- trend_reporting_pair(df, specs, y1, yN, n_iter = 4000L, gwp = GWP, seed = SEED, year_corr = yc,
                               manure = manure, crossgroup = "shared", corr_matrix = NULL, sg_to_mm = sgm,
                               n_group_rho = 1, n_year_corr = nyc)
  h <- trend_headline(trend_reporting_res(res, pair, y1, yN), y1, yN, GWP)
  cat(sprintf("factors %-8s N %-8s base MoE %5.1f%%  yT MoE %5.1f%%  rise %+.0f%%  range %+.0f%% to %+.0f%%   [%.0f s]\n",
              yc, nyc, h$base_moe, h$t_moe, h$trend_pct, h$trend_lo_pp, h$trend_hi_pp, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  rm(res, pair); gc(FALSE)
}
cat("done\n")
