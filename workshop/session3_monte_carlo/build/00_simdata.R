# 00_simdata.R -- produce the real numbers the Session 3 deck is built on.
#
# Every figure in the deck must come from an actual run of the app's own
# sampler and equation chain, not from invented data. A training deck that
# quotes fabricated numbers is worse than no deck: the consultants will run
# the same example on Day 2 and see different figures.
#
# Writes workshop/session3_monte_carlo/assets/simdata.rds, which 01_figures.R
# reads. Run from the project root:
#   Rscript workshop/session3_monte_carlo/build/00_simdata.R

if (basename(getwd()) == "build") setwd("../../..")
options(warn = 1)

suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

OUT_DIR <- "workshop/session3_monte_carlo/assets"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

N_ITER <- 10000L
SEED   <- 42L

cat("Building Country X systems_data ...\n")
specs <- fill_bounds(generate_country_x_example())

group_key <- paste(specs$cattle_type, specs$aggregation_level,
                   specs$sub_category, sep = "||")
sg <- unique(group_key)
stopifnot(length(sg) == 1L)

fb <- default_mms_fallback()
systems_data <- list()
systems_data[[sg]] <- list(
  param_specs   = specs,
  corr_matrix   = NULL,
  ef_corr_matrix = NULL,
  unified_corr_matrix = NULL,
  mms_fractions = fb$fractions,
  mcf_values    = fb$mcf,
  ef3_values    = fb$ef3)

# ---------------------------------------------------------------- uncorrelated
cat("Running ", N_ITER, " iterations, no correlations ...\n", sep = "")
sim <- run_inventory_simulation(
  systems_data, n_iter = N_ITER, gwp = "AR5", seed = SEED,
  pct_pregnant = 1, sampler = "iman_conover")

total <- sim$inventory$total_co2e
met   <- calc_uncertainty_metrics(total)

cat(sprintf("  mean = %.0f t CO2e   CI [%.0f, %.0f]   MoE = %.1f%%\n",
            met$mean, met$ci_lower, met$ci_upper, met$moe_pct))

# ------------------------------------------------------------------ correlated
# The structural-defaults preset, so slide 25 can quote the real widening
# rather than the generic "3 to 10%" from the knowledge notes.
cat("Running ", N_ITER, " iterations with the structural-defaults preset ...\n",
    sep = "")
corr_ok <- TRUE
sim_corr <- tryCatch({
  pnames <- specs$parameter
  ucm <- build_ipcc_preset_corr(pnames)
  sd2 <- systems_data
  sd2[[sg]]$unified_corr_matrix <- ucm
  run_inventory_simulation(sd2, n_iter = N_ITER, gwp = "AR5", seed = SEED,
                           pct_pregnant = 1, sampler = "iman_conover")
}, error = function(e) { corr_ok <<- FALSE
  message("  preset run failed: ", conditionMessage(e)); NULL })

met_corr <- if (!is.null(sim_corr)) {
  calc_uncertainty_metrics(sim_corr$inventory$total_co2e)
} else NULL
if (!is.null(met_corr)) {
  cat(sprintf("  correlated MoE = %.1f%%  (widening %+.1f%%)\n",
              met_corr$moe_pct,
              (met_corr$moe_pct / met$moe_pct - 1) * 100))
}

# ----------------------------------------------------------------- sensitivity
cat("Sensitivity ...\n")
sens <- tryCatch({
  s <- sim$by_system[[sg]]
  sensitivity_analysis(s$samples, s$results$total_co2e)
}, error = function(e) { message("  sensitivity failed: ",
                                 conditionMessage(e)); NULL })

# ------------------------------------------------- per-source decomposition
sources <- c(total_enteric_ch4 = "Enteric CH4",
             total_manure_ch4  = "Manure CH4",
             total_direct_n2o_mm = "Direct N2O, manure",
             total_indirect_n2o_mm = "Indirect N2O, manure",
             total_direct_n2o_prp = "Direct N2O, pasture",
             total_indirect_n2o_prp = "Indirect N2O, pasture")
by_source <- do.call(rbind, lapply(names(sources), function(cl) {
  if (!cl %in% names(sim$inventory)) return(NULL)
  m <- calc_uncertainty_metrics(sim$inventory[[cl]])
  data.frame(col = cl, label = sources[[cl]], mean = m$mean,
             moe_pct = m$moe_pct, stringsAsFactors = FALSE)
}))

# ------------------------------------------------------- per-parameter samples
# Kept for the propagation and correlation figures: these are the actual
# draws the sampler made, so the shapes on the slides are the shapes the
# tool produces.
sysres <- sim$by_system[[sg]]
keep_params <- intersect(c("N", "BW", "DE", "Ym", "Milk", "WG", "Bo", "Cfi"),
                         colnames(sysres$samples))
param_samples <- as.data.frame(sysres$samples[, keep_params, drop = FALSE])

out <- list(
  n_iter        = N_ITER,
  seed          = SEED,
  total         = total,
  metrics       = met,
  metrics_corr  = met_corr,
  by_source     = by_source,
  sensitivity   = sens,
  param_samples = param_samples,
  param_specs   = specs[, c("parameter", "mean", "lower", "upper",
                            "uncertainty_pct", "distribution", "param_type")],
  system_total  = sysres$results$total_co2e,
  built         = as.character(Sys.Date())
)

saveRDS(out, file.path(OUT_DIR, "simdata.rds"))
cat("\nWrote ", file.path(OUT_DIR, "simdata.rds"), "\n", sep = "")

cat("\n--- headline numbers for the deck ---\n")
cat(sprintf("n_iter        : %s\n", format(N_ITER, big.mark = ",")))
cat(sprintf("mean total    : %s t CO2e\n", format(round(met$mean), big.mark = ",")))
cat(sprintf("95%% CI        : %s to %s t CO2e\n",
            format(round(met$ci_lower), big.mark = ","),
            format(round(met$ci_upper), big.mark = ",")))
cat(sprintf("MoE           : %.1f%%\n", met$moe_pct))
if (!is.null(met_corr)) cat(sprintf("MoE, preset   : %.1f%%\n", met_corr$moe_pct))
if (!is.null(sens)) { cat("top drivers   :\n"); print(utils::head(sens, 8)) }
cat("by source     :\n"); print(by_source)
