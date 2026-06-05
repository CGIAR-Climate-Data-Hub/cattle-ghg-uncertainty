# Build the in-app "Find out more" help pages.
#
# Pre-computes the worked-example simulations Country X + Country Y across all
# four correlation modes (none / preset / time-series / manual), saves the
# resulting headline summaries to www/docs/_cache/*.rds, then renders each
# docs/<topic>.Rmd to www/docs/<topic>.html using those cached results.
#
# Run from repo root with:
#   Rscript scripts/build_help_docs.R
#
# Re-run whenever the simulation pipeline, example data, or topic Rmds change.

if (basename(getwd()) == "scripts") setwd("..")

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

cache_dir <- "www/docs/_cache"
if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
out_dir   <- "www/docs"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
# Copy the shared CSS so it's served alongside the HTML
file.copy("docs/_shared.css", file.path(out_dir, "_shared.css"), overwrite = TRUE)

# -----------------------------------------------------------------------------
# Build a systems_data list mirroring what app_server.R's simulation observer
# builds for the example loads (with manure_data attached so the multi-MMS
# code path fires).
# -----------------------------------------------------------------------------
.build_systems_data <- function(specs, manure, n_iter, unified_corr = NULL) {
  group_key <- paste(specs$cattle_type, specs$aggregation_level,
                     specs$sub_category, sep = "||")
  sg <- unique(group_key)
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
  fg_vals   <- setNames(as.numeric(mms_rows$Frac_GasMS_pct)/100,
                          mms_rows$mms_type)
  fl_vals   <- setNames(as.numeric(mms_rows$Frac_LeachMS_pct)/100,
                          mms_rows$mms_type)

  # Per-MMS samples
  mr_mcf <- mms_rows
  for (col in c("MCF_pct","lower_mcf","upper_mcf"))
    if (col %in% names(mr_mcf)) mr_mcf[[col]] <- as.numeric(mr_mcf[[col]])/100
  mcf_samples <- sample_per_mms_param(mr_mcf, "MCF_pct", "lower_mcf",
                                       "upper_mcf", "distribution_mcf",
                                       n_iter, default_dist = "pert")
  ef3_samples <- sample_per_mms_param(mms_rows, "EF3", "lower_ef3",
                                       "upper_ef3", "distribution_ef3",
                                       n_iter, default_dist = "pert")
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

  list(`X` = list(
    param_specs = sys_specs, corr_matrix = NULL, ef_corr_matrix = NULL,
    unified_corr_matrix = unified_corr,
    mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
    frac_gas_values = fg_vals, frac_leach_values = fl_vals,
    mcf_samples = mcf_samples, ef3_samples = ef3_samples,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = fraction_samples
  ))
}

# -----------------------------------------------------------------------------
# Run one (country, corr_mode) combination, return a compact summary frame.
# -----------------------------------------------------------------------------
.run_one <- function(country, corr_mode, n_iter = 3000L) {
  if (country == "country_x") {
    specs  <- fill_bounds(generate_country_x_example())
    manure <- generate_country_x_manure()
    pop    <- generate_country_x_timeseries()
  } else {
    specs  <- fill_bounds(generate_country_y_example())
    manure <- generate_country_y_manure()
    pop    <- generate_country_y_timeseries()
  }
  comp <- ensure_completeness(specs, region = NULL)
  if (isTRUE(comp$valid)) specs <- comp$param_specs

  # Build the correlation matrix for this mode (NULL for "none")
  all_names <- specs$parameter
  corr_mtx <- switch(corr_mode,
    none       = NULL,
    preset     = build_ipcc_preset_corr(all_names),
    timeseries = compute_corr_from_population(pop, detrend = "first_diff"),
    manual     = build_ipcc_preset_corr(all_names)  # treat manual = preset CSV
  )
  unified <- if (!is.null(corr_mtx)) expand_corr_matrix(corr_mtx, all_names) else NULL

  systems_data <- .build_systems_data(specs, manure, n_iter, unified_corr = unified)
  sim <- run_inventory_simulation(systems_data, n_iter = n_iter,
                                   gwp = "AR5", seed = 42L, pct_pregnant = 1,
                                   sampler = "iman_conover")
  inv <- sim$inventory

  summarise <- function(x) {
    m  <- mean(x)
    q  <- quantile(x, c(0.025, 0.975), names = FALSE)
    c(mean = m, lo = q[1], hi = q[2],
      moe_pct = (q[2] - q[1]) / (2 * m) * 100)
  }
  out <- data.frame(
    variable = c("total_enteric_ch4", "total_manure_ch4",
                 "total_direct_n2o_mm", "total_indirect_n2o_mm",
                 "total_direct_n2o_prp", "total_indirect_n2o_prp",
                 "total_co2e"),
    stringsAsFactors = FALSE
  )
  smat <- t(sapply(out$variable, function(v) summarise(inv[[v]])))
  out  <- cbind(out, as.data.frame(smat))
  list(summary = out, corr_matrix = corr_mtx, sub_category_names = all_names)
}

# -----------------------------------------------------------------------------
# Pre-compute all 8 cells (2 countries × 4 modes) and cache.
# -----------------------------------------------------------------------------
modes <- c("none", "preset", "timeseries", "manual")
countries <- c("country_x", "country_y")
results <- list()
for (cn in countries) {
  for (md in modes) {
    cat(sprintf("  running %s / %s ...\n", cn, md))
    key <- paste(cn, md, sep = "_")
    results[[key]] <- .run_one(cn, md)
  }
}
saveRDS(results, file.path(cache_dir, "correlations_runs.rds"))
cat("Cached", length(results), "simulation summaries to",
    file.path(cache_dir, "correlations_runs.rds"), "\n")

# -----------------------------------------------------------------------------
# Render the topic Rmds. Each renders to www/docs/<name>.html and reads its
# cached results via the params: argument in its YAML.
# -----------------------------------------------------------------------------
topics <- c("correlations")
# rmarkdown resolves output_file relative to the Rmd's directory unless it's
# an absolute path. Build absolute paths from the current working dir so the
# output lands in www/docs/ regardless of where the .Rmd lives.
abs_out_dir <- normalizePath(out_dir, mustWork = TRUE)
abs_cache   <- normalizePath(cache_dir, mustWork = TRUE)
for (topic in topics) {
  src <- file.path("docs", paste0(topic, ".Rmd"))
  if (!file.exists(src)) {
    cat("  SKIP", topic, "- source Rmd missing\n")
    next
  }
  cat("  rendering", topic, "...\n")
  rmarkdown::render(src, output_format = "html_document",
                     output_file = paste0(topic, ".html"),
                     output_dir  = abs_out_dir,
                     params = list(cache_dir = abs_cache),
                     quiet = TRUE, envir = new.env())
  dst <- file.path(out_dir, paste0(topic, ".html"))
  sz <- file.info(dst)$size
  cat(sprintf("  -> %s (%d bytes)\n", dst, sz))
}
cat("Done.\n")
