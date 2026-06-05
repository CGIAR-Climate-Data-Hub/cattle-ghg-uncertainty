# Verify the built-in examples (Country X dairy + Country Y pastoral) produce
# sensible end-to-end results.
#
# Andreas in the 2 Jun meeting said the examples worked; Lolita's worry is the
# opposite — examples might be silently producing wrong numbers (factor-of-10
# style). This script runs both through the same simulation pipeline as the
# live app and prints hand-comparable per-head and total emission numbers.

# Run from project root: Rscript scripts/example_verify.R
if (basename(getwd()) == "scripts") setwd("..")

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

run_example <- function(spec_fn, label) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("EXAMPLE:", label, "\n")
  cat(strrep("=", 70), "\n", sep = "")
  specs <- fill_bounds(spec_fn())
  cat("Parameters:\n")
  print(specs[, c("parameter", "mean", "uncertainty_pct", "distribution",
                  "param_type")])

  group_key <- paste(specs$cattle_type, specs$aggregation_level,
                     specs$sub_category, sep = "||")
  sg <- unique(group_key)
  if (length(sg) != 1L) stop("Expected single group for example")

  # No manure data on the examples — falls back to default MMS (70/30
  # pasture/solid_storage). Mirrors app_server.R's fall-through branch.
  systems_data <- list()
  systems_data[[sg]] <- list(
    param_specs = specs, corr_matrix = NULL, ef_corr_matrix = NULL,
    unified_corr_matrix = NULL,
    mms_fractions = c(pasture = 0.70, solid_storage = 0.30),
    mcf_values    = c(pasture = 0.015, solid_storage = 0.050),
    ef3_values    = c(pasture = 0.020, solid_storage = 0.005))

  sim <- run_inventory_simulation(
    systems_data, n_iter = 5000L, gwp = "AR5", seed = 42L,
    pct_pregnant = 1, sampler = "iman_conover")

  inv <- sim$inventory
  cat("\nHeadline totals (mean across ", nrow(inv), " iterations):\n", sep = "")
  summarise <- function(x) c(mean = mean(x),
                              p2.5 = quantile(x, 0.025, names = FALSE),
                              p97.5 = quantile(x, 0.975, names = FALSE),
                              moe_pct = (quantile(x, 0.975, names = FALSE) -
                                          quantile(x, 0.025, names = FALSE)) /
                                          (2 * mean(x)) * 100)
  N <- specs$mean[specs$parameter == "N"]
  cat(sprintf("  Population N: %s head\n", format(N, big.mark = ",")))
  for (col in c("total_enteric_ch4", "total_manure_ch4",
                "total_direct_n2o_mm", "total_indirect_n2o_mm",
                "total_direct_n2o_prp", "total_indirect_n2o_prp",
                "total_co2e")) {
    if (!col %in% names(inv)) next
    s <- summarise(inv[[col]])
    per_head <- if (col == "total_co2e") s["mean"] * 1e3 / N
                else s["mean"] * 1e3 / N
    unit <- if (col == "total_co2e") "kg CO2eq/head/yr" else "kg gas/head/yr"
    cat(sprintf("  %-25s mean = %10.2f  CI [%10.2f, %10.2f]  MoE±%5.1f%%  per-head = %8.2f %s\n",
                col, s["mean"], s["p2.5"], s["p97.5"], s["moe_pct"],
                per_head, unit))
  }

  # Per-head sanity checks against IPCC Tier 2 typical ranges.
  ent <- mean(inv$total_enteric_ch4) * 1e3 / N
  mm_ch4 <- mean(inv$total_manure_ch4) * 1e3 / N
  mm_n2o_d <- mean(inv$total_direct_n2o_mm) * 1e3 / N
  cat("\nSanity check vs typical Tier-2 per-head ranges:\n")
  cat(sprintf("  Enteric CH4/head/yr: %.1f kg (typical dairy 60-130, beef 40-90)\n", ent))
  cat(sprintf("  Manure CH4/head/yr:  %.2f kg (typical 1-30 depending on MMS)\n", mm_ch4))
  cat(sprintf("  Direct N2O-mm/head/yr: %.4f kg (typical 0.01-0.3)\n", mm_n2o_d))

  invisible(sim)
}

sim_x <- run_example(generate_country_x_example,
                      "Country X — dairy smallholder (12 params, dairy/cows)")
sim_y <- run_example(generate_country_y_example,
                      "Country Y — pastoral non-dairy (11 params, non_dairy/breeding_cows)")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DONE\n")
