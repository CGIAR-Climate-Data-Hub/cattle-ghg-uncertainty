# Verify Country X with the new manure data: full app-style pipeline,
# checking that per-pathway EF uncertainties now DIFFER across N2O rows.

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

specs <- fill_bounds(generate_country_x_example())
comp <- ensure_completeness(specs, region = NULL)
if (isTRUE(comp$valid)) specs <- comp$param_specs
manure <- generate_country_x_manure()

group_key <- paste(specs$cattle_type, specs$aggregation_level,
                   specs$sub_category, sep = "||")
sys_groups <- unique(group_key)

# Build systems_data the way the app does it (with per-MMS samples)
n_iter <- 5000L
systems_data <- list()
for (sg in sys_groups) {
  sys_specs <- specs[group_key == sg, ]
  manure_key <- paste(manure$cattle_type, manure$aggregation_level,
                       manure$sub_category, sep = "||")
  mms_rows <- manure[manure_key == sg, ]

  fp  <- as.numeric(mms_rows$fraction_pct) / 100
  mcf <- as.numeric(mms_rows$MCF_pct) / 100
  ef3 <- as.numeric(mms_rows$EF3)
  mms_fracs <- setNames(fp,  mms_rows$mms_type)
  mcf_vals  <- setNames(mcf, mms_rows$mms_type)
  ef3_vals  <- setNames(ef3, mms_rows$mms_type)

  frac_gas_vals   <- setNames(as.numeric(mms_rows$Frac_GasMS_pct)/100,
                               mms_rows$mms_type)
  frac_leach_vals <- setNames(as.numeric(mms_rows$Frac_LeachMS_pct)/100,
                               mms_rows$mms_type)

  # per-MMS samples (uncertainty bounds present)
  mr_mcf <- mms_rows
  for (col in c("MCF_pct","lower_mcf","upper_mcf"))
    if (col %in% names(mr_mcf)) mr_mcf[[col]] <- as.numeric(mr_mcf[[col]])/100
  mcf_samples <- sample_per_mms_param(mr_mcf, "MCF_pct", "lower_mcf",
                                       "upper_mcf", "distribution_mcf",
                                       n_iter, default_dist = "pert")
  ef3_samples <- sample_per_mms_param(mms_rows, "EF3", "lower_ef3",
                                       "upper_ef3", "distribution_ef3",
                                       n_iter, default_dist = "pert")
  # fraction samples + simplex renormalisation
  fraction_samples <- sample_per_mms_param(mms_rows, "fraction_pct",
                                            "lower_fraction", "upper_fraction",
                                            "distribution_fraction",
                                            n_iter, default_dist = "pert")
  fraction_samples[fraction_samples < 0] <- 0
  fraction_samples <- fraction_samples / 100
  rs <- rowSums(fraction_samples); rs[rs <= 0] <- 1
  fraction_samples <- fraction_samples / rs

  ord <- names(mms_fracs)
  mcf_samples      <- mcf_samples[, ord, drop = FALSE]
  ef3_samples      <- ef3_samples[, ord, drop = FALSE]
  fraction_samples <- fraction_samples[, ord, drop = FALSE]

  systems_data[[sg]] <- list(
    param_specs = sys_specs, corr_matrix = NULL, ef_corr_matrix = NULL,
    unified_corr_matrix = NULL,
    mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
    frac_gas_values = frac_gas_vals, frac_leach_values = frac_leach_vals,
    mcf_samples = mcf_samples, ef3_samples = ef3_samples,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = fraction_samples
  )
}

# Combined run
sim <- run_inventory_simulation(systems_data, n_iter = n_iter, gwp = "AR5",
                                 seed = 42L, pct_pregnant = 1,
                                 sampler = "iman_conover")
unc <- calc_all_uncertainty(sim$inventory)

# AD-only and EF-only runs (mirrors app fix_params)
fix_params <- function(sd, fix_type) {
  ps <- sd$param_specs
  ps$param_type[is.na(ps$param_type)] <- "coefficient"
  rows <- ps$param_type == fix_type
  ps$distribution[rows] <- "constant"
  ps$lower[rows] <- ps$mean[rows]; ps$upper[rows] <- ps$mean[rows]
  sd$param_specs <- ps
  if (fix_type == "coefficient") {
    sd$ef_corr_matrix <- NULL
    sd$mcf_samples <- sd$ef3_samples <- sd$frac_gas_samples <-
      sd$frac_leach_samples <- sd$mms_fraction_samples <- NULL
  }
  if (fix_type == "activity_data") {
    sd$corr_matrix <- NULL; sd$unified_corr_matrix <- NULL
  }
  sd
}
ad_sim <- run_inventory_simulation(
  lapply(systems_data, fix_params, "coefficient"),
  n_iter = n_iter, gwp = "AR5", seed = 42L, pct_pregnant = 1)
ef_sim <- run_inventory_simulation(
  lapply(systems_data, fix_params, "activity_data"),
  n_iter = n_iter, gwp = "AR5", seed = 42L, pct_pregnant = 1)
ad_unc <- calc_all_uncertainty(ad_sim$inventory)
ef_unc <- calc_all_uncertainty(ef_sim$inventory)

# Compare per-pathway MoE
cat("\n=== Country X (with new manure data, 4 MMS) ===\n")
cat(sprintf("%-30s %10s %10s %10s\n",
            "pathway", "AD MoE%", "EF MoE%", "Combined MoE%"))
rows <- c("total_enteric_ch4", "total_manure_ch4",
          "total_direct_n2o_mm", "total_indirect_n2o_mm",
          "total_direct_n2o_prp", "total_indirect_n2o_prp")
for (r in rows) {
  ad_moe <- unc$moe_pct[unc$variable == r]
  # AD-only and EF-only MoEs
  ad_only_moe <- ad_unc$moe_pct[ad_unc$variable == r]
  ef_only_moe <- ef_unc$moe_pct[ef_unc$variable == r]
  combined <- unc$moe_pct[unc$variable == r]
  cat(sprintf("%-30s %10.2f %10.2f %10.2f\n",
              r, ad_only_moe, ef_only_moe, combined))
}
