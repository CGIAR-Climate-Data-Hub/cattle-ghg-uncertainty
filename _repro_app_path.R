# Reproduce the LIVE app's Country X simulation path more faithfully than
# _example_verify.R does. Includes:
#   - fill_bounds()
#   - ensure_completeness() with auto-fill of missing core params
#   - resolve_sub_category_matches() with manure_data = NULL
#   - the full systems_data structure (mcf_samples, ef3_samples, ... = NULL)
#   - the same input$* shape the simulation observer passes through
#
# Goal: trigger the "missing value where TRUE/FALSE needed" error so we can
# find the offending if(NA).

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

# Stage 1 — load example exactly like .load_example() does
specs <- fill_bounds(generate_country_x_example())
cat("After fill_bounds:", nrow(specs), "rows\n")

# Stage 2 — apply completeness (auto-fill missing core params)
comp <- ensure_completeness(specs, region = NULL)
cat("ensure_completeness valid =", comp$valid, "\n")
cat("auto_filled =", length(comp$auto_filled), "rows\n")
if (isTRUE(comp$valid) && length(comp$auto_filled) > 0) {
  specs <- comp$param_specs
}
cat("After completeness:", nrow(specs), "rows\n")
cat("Parameters present:\n")
print(specs[, c("parameter", "mean", "uncertainty_pct", "distribution",
                "lower", "upper", "param_type")])

# Stage 3 — set the manure data to NULL (no upload), like the example path
manure <- NULL

# Stage 4 — simulation observer logic
make_group_key <- function(df) {
  if (all(c("cattle_type", "aggregation_level") %in% names(df))) {
    sub <- if ("sub_category" %in% names(df)) df$sub_category else rep("", nrow(df))
    paste(df$cattle_type, df$aggregation_level, sub, sep = "||")
  } else rep("group1", nrow(df))
}
group_key  <- make_group_key(specs)
sys_groups <- unique(group_key)
cat("\nsys_groups:\n"); print(sys_groups)

sg_resolve <- resolve_sub_category_matches(specs, manure)
cat("\nresolve_sub_category_matches issues:\n")
print(sg_resolve$issues)

# Stage 5 — build systems_data exactly like app_server.R
default_mms_fracs <- c(pasture = 0.70, solid_storage = 0.30)
default_mcf_vals  <- c(pasture = 0.015, solid_storage = 0.050)
default_ef3_vals  <- c(pasture = 0.020, solid_storage = 0.005)

systems_data <- list()
for (sg in sys_groups) {
  sys_specs <- specs[group_key == sg, ]
  systems_data[[sg]] <- list(
    param_specs = sys_specs,
    corr_matrix = NULL, ef_corr_matrix = NULL, unified_corr_matrix = NULL,
    mms_fractions = default_mms_fracs,
    mcf_values    = default_mcf_vals,
    ef3_values    = default_ef3_vals,
    frac_gas_values = NULL, frac_leach_values = NULL,
    mcf_samples = NULL, ef3_samples = NULL,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = NULL
  )
}

# Stage 6 — run the simulation
cat("\nRunning simulation...\n")
sim <- tryCatch(
  run_inventory_simulation(systems_data, n_iter = 100L, gwp = "AR5",
                            seed = 42L, pct_pregnant = 1,
                            sampler = "iman_conover"),
  error = function(e) {
    cat("\n*** ERROR ***\n", conditionMessage(e), "\n")
    cat("\nTraceback:\n")
    print(sys.calls())
    NULL
  })

if (!is.null(sim)) {
  cat("\nSimulation OK. total_co2e mean =", mean(sim$inventory$total_co2e), "\n")

  # Stage 7 — full post-simulation pipeline (calc_all_uncertainty, decomposition,
  # sensitivity, format_ipcc_table) to find the if(NA).
  cat("\n--- calc_all_uncertainty ---\n")
  unc <- tryCatch(calc_all_uncertainty(sim$inventory),
                   error = function(e) { cat("ERR:", conditionMessage(e), "\n"); NULL })

  cat("\n--- AD-only decomposition ---\n")
  fix_params <- function(sd, fix_type) {
    ps <- sd$param_specs
    ps$param_type[is.na(ps$param_type)] <- "coefficient"
    rows <- ps$param_type == fix_type
    ps$distribution[rows] <- "constant"
    ps$lower[rows] <- ps$mean[rows]
    ps$upper[rows] <- ps$mean[rows]
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
  ad_result <- tryCatch(
    run_inventory_simulation(systems_ad, n_iter = 100L, gwp = "AR5",
                              seed = 42L, pct_pregnant = 1),
    error = function(e) { cat("AD ERR:", conditionMessage(e), "\n"); NULL })

  cat("\n--- EF-only decomposition ---\n")
  systems_ef <- lapply(systems_data, fix_params, fix_type = "activity_data")
  ef_result <- tryCatch(
    run_inventory_simulation(systems_ef, n_iter = 100L, gwp = "AR5",
                              seed = 42L, pct_pregnant = 1),
    error = function(e) { cat("EF ERR:", conditionMessage(e), "\n"); NULL })

  cat("\n--- format_ipcc_table ---\n")
  ipcc <- tryCatch(
    format_ipcc_table(list(combined = unc,
                            ad_only  = calc_all_uncertainty(ad_result$inventory),
                            ef_only  = calc_all_uncertainty(ef_result$inventory))),
    error = function(e) { cat("IPCC ERR:", conditionMessage(e), "\n"); NULL })

  cat("\n--- sensitivity (aggregate_sensitivity — exactly what live app calls) ---\n")
  sens <- tryCatch(
    aggregate_sensitivity(sim$by_system, sim$inventory$total_co2e),
    error = function(e) { cat("AGG_SENS ERR:", conditionMessage(e), "\n"); NULL })
  cat("agg sensitivity SRC rows:", if (!is.null(sens$src)) nrow(sens$src) else "NULL", "\n")
  cat("agg sensitivity PRCC rows:", if (!is.null(sens$prcc)) nrow(sens$prcc) else "NULL", "\n")

  cat("\n--- Per-source sensitivity (Stage 5b in app) ---\n")
  for (src in c("enteric_ch4", "manure_ch4", "manure_n2o_direct",
                "manure_n2o_indirect", "pasture_n2o_direct",
                "pasture_n2o_indirect")) {
    col_name <- sub("manure_", "", sub("pasture_", "", src))
    suffix_col <- paste0(col_name, "_total")
    per_src_totals <- tryCatch(
      Reduce("+", lapply(sim$by_system, function(bs)
        if (!is.null(bs$results[[suffix_col]])) bs$results[[suffix_col]] else 0)),
      error = function(e) { cat(src, "Reduce ERR:", conditionMessage(e), "\n"); NULL })
    if (is.null(per_src_totals) || length(per_src_totals) == 0) next
    s <- tryCatch(
      aggregate_sensitivity(sim$by_system, per_src_totals),
      error = function(e) { cat(src, "agg ERR:", conditionMessage(e), "\n"); NULL })
    cat(sprintf("  %s: SRC=%s PRCC=%s\n", src,
                if (!is.null(s$src)) nrow(s$src) else "NULL",
                if (!is.null(s$prcc)) nrow(s$prcc) else "NULL"))
  }

  cat("\n--- Word run-summary build ---\n")
  word_ok <- tryCatch({
    tmp <- tempfile(fileext = ".docx")
    build_run_summary_docx(
      path = tmp,
      settings = list(n_iter = 100L, gwp_version = "AR5",
                       corr_mode = "none", ef_corr_mode = "none",
                       analysis_mode = "single",
                       emission_sources = character(0)),
      param_specs = sim$by_system[[1]]$samples,
      mc_results = sim,
      uncertainty = unc,
      sensitivity = NULL,
      ipcc_table = ipcc)
    file.info(tmp)$size > 50000
  }, error = function(e) { cat("WORD ERR:", conditionMessage(e), "\n"); FALSE })
  cat("Word build:", word_ok, "\n")

  cat("\n========= ALL STAGES COMPLETED =========\n")
}
