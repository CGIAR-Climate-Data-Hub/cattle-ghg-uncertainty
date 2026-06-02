# ============================================================================
# End-to-end reproduction of Andreas's 28/5/26 test-run with his actual file.
# Goal: confirm the post-fix tool produces direct/indirect MM N2O headlines
# close to his @Risk reference (~39.9 t direct / ~19.6 t indirect MM N2O).
#
# Run from repo root with:
#   Rscript _zim_verify.R
# ============================================================================

options(warn = 1)
suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})

template_path <- "uncertainty_template_ipcc2019_ZIM_v2.xlsx"
if (!file.exists(template_path))
  stop("Cannot find template at ", template_path)

cat("=== Parsing template ===\n")
parsed <- parse_uploaded_template(template_path)
specs  <- parsed$param_specs
manure <- parsed$manure
cat("  Parameters rows:", nrow(specs), "\n")
cat("  Manure_Management rows:", nrow(manure), "\n")
cat("  Parsing warnings:", length(parsed$warnings), "\n")
for (w in parsed$warnings) cat("    -", w, "\n")

# Andreas's settings (from the 28/5/26 doc § A.1):
#   IPCC 2019, single year, no correlations, 10,000 iterations, seed = 42,
#   AR5 GWP, all sources, AD/EF decomposition.
n_iter_val   <- 10000L
seed_val     <- 42L
gwp_version  <- "AR5"

# Group keys ---------------------------------------------------------------
make_group_key <- function(df) {
  if (all(c("cattle_type", "aggregation_level") %in% names(df))) {
    sub <- if ("sub_category" %in% names(df)) df$sub_category else
                                              rep("", nrow(df))
    paste(df$cattle_type, df$aggregation_level, sub, sep = "||")
  } else if (all(c("system", "subsystem") %in% names(df))) {
    paste(df$system, df$subsystem, sep = "||")
  } else rep("group1", nrow(df))
}

group_key  <- make_group_key(specs)
sys_groups <- unique(group_key)
cat("\n=== Parameters sys_groups (", length(sys_groups), ") ===\n", sep = "")
for (g in sys_groups) cat("  -", g, "\n")

# Auto-match (post-28/5/26 fix) -------------------------------------------
sg_resolve <- resolve_sub_category_matches(specs, manure)
sg_to_mm   <- sg_resolve$matched
sg_issues  <- sg_resolve$issues

cat("\n=== resolve_sub_category_matches issues ===\n")
if (nrow(sg_issues) == 0) {
  cat("  (none — every Parameters key has an exact MM match)\n")
} else {
  for (i in seq_len(nrow(sg_issues))) {
    cat(sprintf("  [%s] %s — %s\n",
                sg_issues$status[i], sg_issues$check[i],
                sg_issues$message[i]))
  }
}

# Stop if any ambiguity (matches the observer's behaviour)
ambig <- sg_issues[sg_issues$status == "fail" &
                     sg_issues$check == "sub_category_ambiguous", ,
                   drop = FALSE]
if (nrow(ambig) > 0) stop("Ambiguous sub-category keys — would block the run.")

# Build systems_data (mirrors app_server.R lines 1086-1247) ---------------
systems_data <- list()
default_mms_fracs <- c(pasture = 0.70, solid_storage = 0.30)
default_mcf_vals  <- c(pasture = 0.015, solid_storage = 0.050)
default_ef3_vals  <- c(pasture = 0.020, solid_storage = 0.005)

for (sg in sys_groups) {
  sys_specs <- specs[group_key == sg, ]

  frac_gas_vals   <- NULL
  frac_leach_vals <- NULL
  mcf_samples <- ef3_samples <- fg_samples <- fl_samples <-
    fraction_samples <- NULL

  if (!is.null(manure) && nrow(manure) > 0 &&
      all(c("mms_type", "fraction_pct", "MCF_pct", "EF3") %in% names(manure))) {
    manure_key <- make_group_key(manure)
    sg_lookup  <- if (sg %in% names(sg_to_mm)) sg_to_mm[[sg]] else sg
    mms_rows   <- manure[manure_key == sg_lookup, ]
    if (nrow(mms_rows) > 0) {
      fp_num  <- suppressWarnings(as.numeric(mms_rows$fraction_pct))
      mcf_num <- suppressWarnings(as.numeric(mms_rows$MCF_pct))
      ef3_num <- suppressWarnings(as.numeric(mms_rows$EF3))
      mms_fracs <- setNames(fp_num / 100,  mms_rows$mms_type)
      mcf_vals  <- setNames(mcf_num / 100, mms_rows$mms_type)
      ef3_vals  <- setNames(ef3_num,       mms_rows$mms_type)
      mms_fracs <- mms_fracs[!is.na(mms_fracs)]
      mcf_vals  <- mcf_vals[names(mms_fracs)]
      ef3_vals  <- ef3_vals[names(mms_fracs)]
      mcf_vals[is.na(mcf_vals)] <- 0.015
      ef3_vals[is.na(ef3_vals)] <- 0.005

      if ("Frac_GasMS_pct" %in% names(mms_rows)) {
        fg_num <- suppressWarnings(as.numeric(mms_rows$Frac_GasMS_pct)) / 100
        frac_gas_vals <- setNames(fg_num, mms_rows$mms_type)
        frac_gas_vals <- frac_gas_vals[names(mms_fracs)]
      }
      if ("Frac_LeachMS_pct" %in% names(mms_rows)) {
        fl_num <- suppressWarnings(as.numeric(mms_rows$Frac_LeachMS_pct)) / 100
        frac_leach_vals <- setNames(fl_num, mms_rows$mms_type)
        frac_leach_vals <- frac_leach_vals[names(mms_fracs)]
      }

      mr_mcf_scaled <- mms_rows
      for (col in c("MCF_pct", "lower_mcf", "upper_mcf"))
        if (col %in% names(mr_mcf_scaled))
          mr_mcf_scaled[[col]] <- suppressWarnings(
            as.numeric(mr_mcf_scaled[[col]])) / 100
      mr_fg_scaled <- mms_rows
      for (col in c("Frac_GasMS_pct", "lower_frac_gas", "upper_frac_gas"))
        if (col %in% names(mr_fg_scaled))
          mr_fg_scaled[[col]] <- suppressWarnings(
            as.numeric(mr_fg_scaled[[col]])) / 100
      mr_fl_scaled <- mms_rows
      for (col in c("Frac_LeachMS_pct", "lower_frac_leach", "upper_frac_leach"))
        if (col %in% names(mr_fl_scaled))
          mr_fl_scaled[[col]] <- suppressWarnings(
            as.numeric(mr_fl_scaled[[col]])) / 100

      mcf_samples <- sample_per_mms_param(
        mr_mcf_scaled, "MCF_pct", "lower_mcf", "upper_mcf",
        "distribution_mcf", n_iter_val, default_dist = "pert")
      ef3_samples <- sample_per_mms_param(
        mms_rows, "EF3", "lower_ef3", "upper_ef3",
        "distribution_ef3", n_iter_val, default_dist = "pert")
      fg_samples <- sample_per_mms_param(
        mr_fg_scaled, "Frac_GasMS_pct", "lower_frac_gas",
        "upper_frac_gas", "distribution_frac_gas",
        n_iter_val, default_dist = "pert")
      fl_samples <- sample_per_mms_param(
        mr_fl_scaled, "Frac_LeachMS_pct", "lower_frac_leach",
        "upper_frac_leach", "distribution_frac_leach",
        n_iter_val, default_dist = "pert")
      # Andreas 28/5/26 #4: sample fraction_pct per-MMS so MMS allocation
      # shows up in the tornado / rank-correlation. Mirrors app_server.R.
      if (any(c("lower_fraction", "upper_fraction", "distribution_fraction")
              %in% names(mms_rows))) {
        fraction_samples <- sample_per_mms_param(
          mms_rows, "fraction_pct", "lower_fraction",
          "upper_fraction", "distribution_fraction",
          n_iter_val, default_dist = "pert")
        if (!is.null(fraction_samples)) {
          fraction_samples[fraction_samples < 0] <- 0
          fraction_samples <- fraction_samples / 100
          rs <- rowSums(fraction_samples)
          rs[rs <= 0] <- 1
          fraction_samples <- fraction_samples / rs
        }
      }

      ord_names <- names(mms_fracs)
      if (!is.null(mcf_samples)) mcf_samples <- mcf_samples[, ord_names, drop = FALSE]
      if (!is.null(ef3_samples)) ef3_samples <- ef3_samples[, ord_names, drop = FALSE]
      if (!is.null(fg_samples))  fg_samples  <- fg_samples[, ord_names, drop = FALSE]
      if (!is.null(fl_samples))  fl_samples  <- fl_samples[, ord_names, drop = FALSE]
      if (!is.null(fraction_samples))
        fraction_samples <- fraction_samples[, ord_names, drop = FALSE]

      if (length(mms_fracs) == 0) {
        mms_fracs <- default_mms_fracs
        mcf_vals  <- default_mcf_vals
        ef3_vals  <- default_ef3_vals
      }
    } else {
      mms_fracs <- default_mms_fracs
      mcf_vals  <- default_mcf_vals
      ef3_vals  <- default_ef3_vals
    }
  } else {
    mms_fracs <- default_mms_fracs
    mcf_vals  <- default_mcf_vals
    ef3_vals  <- default_ef3_vals
  }

  systems_data[[sg]] <- list(
    param_specs = sys_specs, corr_matrix = NULL, ef_corr_matrix = NULL,
    unified_corr_matrix = NULL,
    mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
    frac_gas_values = frac_gas_vals, frac_leach_values = frac_leach_vals,
    mcf_samples = mcf_samples, ef3_samples = ef3_samples,
    frac_gas_samples = fg_samples, frac_leach_samples = fl_samples,
    mms_fraction_samples = fraction_samples)
}

# Run the simulation -------------------------------------------------------
cat("\n=== Running simulation (n_iter =", n_iter_val, ", seed =",
    seed_val, ", GWP =", gwp_version, ") ===\n")
t0 <- Sys.time()
sim <- run_inventory_simulation(
  systems_data, n_iter = n_iter_val, gwp = gwp_version, seed = seed_val,
  pct_pregnant = 1, sampler = "iman_conover")
cat("  Simulation took", round(as.numeric(difftime(Sys.time(), t0,
                                                    units = "secs")), 1),
    "s\n")

inv <- sim$inventory

# Headline numbers ---------------------------------------------------------
summarise <- function(x) c(mean = mean(x),
                            ci_lo = quantile(x, 0.025, names = FALSE),
                            ci_hi = quantile(x, 0.975, names = FALSE))

cols <- c("total_enteric_ch4", "total_manure_ch4",
          "total_direct_n2o_mm", "total_indirect_n2o_mm",
          "total_direct_n2o_prp", "total_indirect_n2o_prp")

cat("\n=== Headline results vs @Risk reference ===\n")
risk_ref <- list(
  total_enteric_ch4     = 2929,
  total_manure_ch4      = 708.3,
  total_direct_n2o_mm   = 39.9,
  total_indirect_n2o_mm = 19.595,
  total_direct_n2o_prp  = NA_real_,
  total_indirect_n2o_prp= NA_real_)

cat(sprintf("%-26s %10s %10s %10s %10s\n",
            "Source", "tool_mean", "ci_lo", "ci_hi", "@Risk_mean"))
for (col in cols) {
  if (!col %in% names(inv)) next
  s <- summarise(inv[[col]])
  ref <- risk_ref[[col]]
  cat(sprintf("%-26s %10.3f %10.3f %10.3f %10s\n",
              col, s["mean"], s["ci_lo"], s["ci_hi"],
              if (is.na(ref)) "(no ref)" else sprintf("%.3f", ref)))
}

cat("\n=== Per-sub-category MM N2O contribution (direct, indirect) ===\n")
cat(sprintf("%-40s %12s %12s\n", "Sub-category", "direct_mean", "indir_mean"))
for (sg in names(sim$by_system)) {
  bs <- sim$by_system[[sg]]$results
  d <- if ("direct_n2o_mm_total"   %in% names(bs)) mean(bs$direct_n2o_mm_total)   else NA
  i <- if ("indirect_n2o_mm_total" %in% names(bs)) mean(bs$indirect_n2o_mm_total) else NA
  cat(sprintf("%-40s %12.4f %12.4f\n", sg, d, i))
}
