# Same as _repro_app_path.R but for Country Y. Confirms the full simulation
# observer path (fill_bounds + ensure_completeness + resolve_sub_category_matches
# + run_inventory_simulation + calc_all_uncertainty + AD/EF decomposition +
# aggregate_sensitivity + format_ipcc_table + Word build) all succeed.

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

# Stage 1 — load Country Y exactly like .load_example("country_y") does
specs <- fill_bounds(generate_country_y_example())
cat("After fill_bounds: ", nrow(specs), " rows\n", sep = "")

# Stage 2 — auto-fill missing core params
comp <- ensure_completeness(specs, region = NULL)
cat("ensure_completeness valid = ", comp$valid,
    "; auto_filled = ", length(comp$auto_filled), " rows\n", sep = "")
if (isTRUE(comp$valid) && length(comp$auto_filled) > 0) {
  specs <- comp$param_specs
}
cat("After completeness: ", nrow(specs), " rows\n", sep = "")
cat("Parameters: ", paste(specs$parameter, collapse = ", "), "\n", sep = "")

# Stage 3 — manure_data = NULL for examples
manure <- NULL

# Stage 4 — sys_groups + resolve_sub_category_matches
group_key <- paste(specs$cattle_type, specs$aggregation_level,
                   specs$sub_category, sep = "||")
sys_groups <- unique(group_key)
cat("sys_groups: ", paste(sys_groups, collapse = " | "), "\n", sep = "")
sg_resolve <- resolve_sub_category_matches(specs, manure)
cat("resolve issues: ", nrow(sg_resolve$issues), " row(s)\n", sep = "")

# Stage 5 — systems_data with default 70/30 routing (no upload, no MMS sheet)
systems_data <- list()
for (sg in sys_groups) {
  systems_data[[sg]] <- list(
    param_specs = specs[group_key == sg, ],
    corr_matrix = NULL, ef_corr_matrix = NULL, unified_corr_matrix = NULL,
    mms_fractions = c(pasture = 0.70, solid_storage = 0.30),
    mcf_values    = c(pasture = 0.015, solid_storage = 0.050),
    ef3_values    = c(pasture = 0.020, solid_storage = 0.005),
    frac_gas_values = NULL, frac_leach_values = NULL,
    mcf_samples = NULL, ef3_samples = NULL,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = NULL
  )
}

# Stage 6 — simulation (mirrors app observer)
cat("\n--- Simulation ---\n")
sim <- tryCatch(
  run_inventory_simulation(systems_data, n_iter = 500L, gwp = "AR5",
                            seed = 42L, pct_pregnant = 1,
                            sampler = "iman_conover"),
  error = function(e) { cat("SIM ERR: ", e$message, "\n"); NULL })

if (is.null(sim)) stop("Simulation failed for Country Y")
cat("OK. total_co2e mean = ", round(mean(sim$inventory$total_co2e)), "\n")

# Stage 7 — calc_all_uncertainty
cat("\n--- calc_all_uncertainty ---\n")
unc <- tryCatch(calc_all_uncertainty(sim$inventory),
                 error = function(e) { cat("UNC ERR: ", e$message, "\n"); NULL })
cat(if (is.null(unc)) "FAIL" else paste0("OK (", nrow(unc), " rows)"), "\n")

# Stage 8 — AD-only / EF-only decomposition (the if(NA) candidate)
cat("\n--- AD-only / EF-only decomposition ---\n")
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
systems_ad <- lapply(systems_data, fix_params, fix_type = "coefficient")
ad <- tryCatch(
  run_inventory_simulation(systems_ad, n_iter = 500L, gwp = "AR5",
                            seed = 42L, pct_pregnant = 1),
  error = function(e) { cat("AD ERR: ", e$message, "\n"); NULL })
systems_ef <- lapply(systems_data, fix_params, fix_type = "activity_data")
ef <- tryCatch(
  run_inventory_simulation(systems_ef, n_iter = 500L, gwp = "AR5",
                            seed = 42L, pct_pregnant = 1),
  error = function(e) { cat("EF ERR: ", e$message, "\n"); NULL })
cat("AD-only: ", if (is.null(ad)) "FAIL" else "OK", "; ",
    "EF-only: ", if (is.null(ef)) "FAIL" else "OK", "\n", sep = "")

# Stage 9 — aggregate_sensitivity (exactly what the live app calls)
cat("\n--- aggregate_sensitivity ---\n")
sens <- tryCatch(
  aggregate_sensitivity(sim$by_system, sim$inventory$total_co2e),
  error = function(e) { cat("SENS ERR: ", e$message, "\n"); NULL })
cat("SRC rows: ", if (is.null(sens$src)) "NULL" else nrow(sens$src),
    " | PRCC rows: ", if (is.null(sens$prcc)) "NULL" else nrow(sens$prcc),
    "\n", sep = "")

# Stage 10 — format_ipcc_table
cat("\n--- format_ipcc_table ---\n")
ipcc <- tryCatch(
  format_ipcc_table(list(combined = unc,
                          ad_only  = calc_all_uncertainty(ad$inventory),
                          ef_only  = calc_all_uncertainty(ef$inventory))),
  error = function(e) { cat("IPCC ERR: ", e$message, "\n"); NULL })
cat(if (is.null(ipcc)) "FAIL" else "OK", "\n")

# Stage 11 — Word run-summary build
cat("\n--- Word build ---\n")
ok_word <- tryCatch({
  tmp <- tempfile(fileext = ".docx")
  build_run_summary_docx(
    path = tmp,
    settings = list(n_iter = 500L, gwp_version = "AR5",
                     corr_mode = "none", ef_corr_mode = "none",
                     analysis_mode = "single",
                     emission_sources = character(0)),
    param_specs = sim$by_system[[1]]$samples,
    mc_results = sim, uncertainty = unc,
    sensitivity = NULL, ipcc_table = ipcc)
  file.info(tmp)$size > 50000
}, error = function(e) { cat("WORD ERR: ", e$message, "\n"); FALSE })
cat(if (ok_word) "OK" else "FAIL", "\n")

cat("\n=========\nALL STAGES COMPLETED for Country Y\n=========\n")
