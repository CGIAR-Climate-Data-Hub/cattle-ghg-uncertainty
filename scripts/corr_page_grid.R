# The single-year 3 x 3 grid for section 6 of the correlations help page:
# activity correlations (none, structural, from template) x animal numbers
# between groups (separate, partly, one count), the test inventory template of
# 1 November 17:13, inventory year 2024, 4,000 draws, seed 42.
suppressMessages({for (f in list.files("R", "\\.R$", full.names = TRUE)) try(source(f), silent = TRUE)})
Sys.setenv(APP_RUNTIME_DIR = "C:/tmp/rt")
N_ITER <- 4000L; SEED <- 42L; GWP <- "AR5"
parsed <- parse_uploaded_template("test_data/inv_a/inv_a_1713.xlsx")
specs <- parsed$param_specs; manure <- parsed$manure
comp <- ensure_completeness(specs, region = parsed$metadata$region)
if (isTRUE(comp$valid)) specs <- comp$param_specs
sgm <- resolve_sub_category_matches(specs, manure)$matched
r <- tryCatch(refine_preset_from_timeseries(parsed$population, specs$parameter), error = function(e) NULL)
corr_for <- function(mode) switch(mode, none = NULL,
  preset = expand_corr_matrix(build_ipcc_preset_corr(specs$parameter), specs$parameter),
  timeseries = if (!is.null(r) && !is.null(r$matrix)) expand_corr_matrix(r$matrix, specs$parameter) else NULL)
moe <- function(x) { q <- quantile(x, c(0.025, 0.975), names = FALSE); (q[2] - q[1]) / (2 * mean(x)) * 100 }
cat(sprintf("%-12s %-10s %-10s %-10s\n", "", "separate", "partly", "one count"))
for (m in c("none", "preset", "timeseries")) {
  row <- c()
  for (rho in c(0, 0.5, 1)) {
    built <- build_systems_data(specs, manure = manure, n_iter = N_ITER, seed = SEED, crossgroup = "shared",
                                corr_matrix = corr_for(m), sg_to_mm = sgm, n_group_rho = rho)
    sim <- run_inventory_simulation(built$systems, n_iter = N_ITER, gwp = GWP, seed = SEED, pct_pregnant = 1, keep_sample_rows = 10L)
    row <- c(row, moe(sim$inventory$total_co2e)); rm(built, sim); gc(FALSE)
  }
  cat(sprintf("%-12s %9.1f%% %9.1f%% %9.1f%%\n", m, row[1], row[2], row[3]))
}
cat("done\n")
