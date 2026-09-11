# Input Validation Functions

validate_param_specs <- function(param_specs) {
  errors <- character()
  warnings <- character()

  required_cols <- c("parameter", "mean", "lower", "upper", "distribution", "param_type")
  missing <- setdiff(required_cols, names(param_specs))
  if (length(missing) > 0) {
    errors <- c(errors, paste("Missing columns:", paste(missing, collapse = ", ")))
    return(list(valid = FALSE, errors = errors, warnings = warnings))
  }

  # R1.6: accept both legacy "cattle_pop" and new IPCC name "N"
  pop_rows <- param_specs$parameter %in% c("N", "cattle_pop")
  if (any(param_specs$mean[pop_rows] < 0, na.rm = TRUE))
    errors <- c(errors, "Cattle population (N) cannot be negative")

  de_rows <- param_specs$parameter == "DE_pct"
  if (any(param_specs$mean[de_rows] > 100 | param_specs$mean[de_rows] < 0, na.rm = TRUE))
    errors <- c(errors, "Digestible energy must be between 0 and 100%")

  # Hours bug fix: allow lower == upper when the parameter is effectively zero
  # (e.g. hours = 0 when animals do no work; weight_gain = 0 for adult non-growing;
  # Cp = 0 for non-pregnant; C_growth = 0 for some sex codes). These are degenerate
  # constants that the sampler handles without issue. Only flag a strict inversion.
  is_constant_dist <- param_specs$distribution %in% c("constant", "const")
  is_zero_mean    <- !is.na(param_specs$mean) & param_specs$mean == 0 &
                     !is.na(param_specs$lower) & param_specs$lower == 0 &
                     !is.na(param_specs$upper) & param_specs$upper == 0
  bad_bounds <- param_specs$lower > param_specs$upper &
    !is_constant_dist & !is_zero_mean
  if (any(bad_bounds, na.rm = TRUE))
    errors <- c(errors, paste("Lower > upper for:",
                               paste(param_specs$parameter[which(bad_bounds)], collapse = ", ")))

  valid_dists <- c("normal", "posnorm", "lognormal", "beta", "triangular", "pert",
                   "uniform", "constant", "const", "tnorm_0_1")
  invalid <- !tolower(param_specs$distribution) %in% valid_dists
  if (any(invalid))
    errors <- c(errors, paste("Invalid distribution:",
                               paste(param_specs$parameter[invalid], collapse = ", ")))

  # -------------------------------------------------------------------------
  # Controlled vocabulary checks (warnings only, backwards compatible)
  # -------------------------------------------------------------------------
  if ("param_type" %in% names(param_specs) && exists("PARAM_TYPES")) {
    bad_pt <- !(tolower(param_specs$param_type) %in% PARAM_TYPES) &
              !is.na(param_specs$param_type) & nzchar(param_specs$param_type)
    if (any(bad_pt))
      errors <- c(errors, paste("Invalid param_type value(s):",
                                 paste(unique(param_specs$param_type[bad_pt]), collapse = ", "),
                                 "- must be 'activity_data' or 'coefficient' (legacy: 'emission_factor')"))
  }

  list(valid = length(errors) == 0, errors = errors, warnings = warnings)
}

# Validate the Inventory_Metadata sheet against controlled vocabularies
validate_inventory_metadata <- function(meta) {
  errors <- character()
  warnings <- character()
  if (is.null(meta) || nrow(meta) == 0) {
    warnings <- c(warnings, "No Inventory_Metadata provided - using defaults.")
    return(list(valid = TRUE, errors = errors, warnings = warnings))
  }
  m <- meta[1, , drop = FALSE]

  if (!is.null(m$species) && nzchar(m$species) && exists("SPECIES_OPTIONS")) {
    if (!(m$species %in% SPECIES_OPTIONS))
      warnings <- c(warnings, paste("species '", m$species,
                                     "' not in controlled list:",
                                     paste(SPECIES_OPTIONS, collapse = ", "), sep = ""))
  }
  if (!is.null(m$ipcc_version) && nzchar(m$ipcc_version) && exists("IPCC_VERSIONS")) {
    if (!(m$ipcc_version %in% IPCC_VERSIONS))
      warnings <- c(warnings, paste("ipcc_version should be one of:",
                                     paste(IPCC_VERSIONS, collapse = ", ")))
  }
  list(valid = length(errors) == 0, errors = errors, warnings = warnings)
}

# Validate Manure_Management rows (fractions sum to 100, controlled MMS types).
# R1.10: when `meta` is supplied, MMS list is filtered to the selected IPCC version.
validate_manure_sheet <- function(manure_df, meta = NULL) {
  errors <- character()
  warnings <- character()
  if (is.null(manure_df) || nrow(manure_df) == 0)
    return(list(valid = TRUE, errors = errors, warnings = warnings))

  # TT.3 + R1.10: MMS list filtered by IPCC version when version is provided.
  # The MMS_DEFAULTS data.frame has a `versions` column listing which IPCC editions
  # recognise each system; `get_mms_for_version()` filters accordingly.
  ipcc_v <- if (!is.null(meta) && "ipcc_version" %in% names(meta))
    meta$ipcc_version else "2006"
  valid_mms <- if (exists("get_mms_for_version")) {
    get_mms_for_version(ipcc_v)$id
  } else if (exists("MMS_DEFAULTS")) {
    MMS_DEFAULTS$id
  } else {
    c("pasture", "daily_spread", "solid_storage", "solid_storage_covered",
      "dry_lot", "deep_bedding", "liquid_slurry", "composting", "lagoon",
      "anaerobic_digester", "aerobic_treatment", "burned_for_fuel")
  }
  if ("mms_type" %in% names(manure_df)) {
    bad <- !(manure_df$mms_type %in% valid_mms)
    if (any(bad))
      errors <- c(errors, paste("Invalid mms_type(s):",
                                 paste(unique(manure_df$mms_type[bad]), collapse = ", ")))
  }

  # Support both old column names (backwards compat) and new 3-level naming
  has_new_cols <- all(c("cattle_type", "aggregation_level", "fraction_pct") %in% names(manure_df))
  has_old_cols <- all(c("system", "subsystem", "fraction_pct") %in% names(manure_df))
  if (has_new_cols) {
    sub_col <- if ("sub_category" %in% names(manure_df)) manure_df$sub_category else ""
    key <- paste(manure_df$cattle_type, manure_df$aggregation_level, sub_col, sep = "||")
    sums <- tapply(manure_df$fraction_pct, key, sum, na.rm = TRUE)
    off <- sums[abs(sums - 100) > 1]
    if (length(off) > 0) {
      errors <- c(errors, paste("Manure fractions do not sum to 100% for:",
                                 paste(names(off), collapse = "; "),
                                 "(got", paste(round(off, 1), collapse = ", "), ")"))
    }
  } else if (has_old_cols) {
    key <- paste(manure_df$system, manure_df$subsystem, sep = "||")
    sums <- tapply(manure_df$fraction_pct, key, sum, na.rm = TRUE)
    off <- sums[abs(sums - 100) > 1]
    if (length(off) > 0) {
      errors <- c(errors, paste("Manure fractions do not sum to 100% for:",
                                 paste(names(off), collapse = "; "),
                                 "(got", paste(round(off, 1), collapse = ", "), ")"))
    }
  }

  # Round 7 R1.12: per-MMS Frac_GasMS / Frac_LeachMS range checks
  for (col in c("Frac_GasMS_pct", "Frac_LeachMS_pct")) {
    if (col %in% names(manure_df)) {
      v <- suppressWarnings(as.numeric(manure_df[[col]]))
      bad <- which(!is.na(v) & (v < 0 | v > 100))
      if (length(bad) > 0) {
        errors <- c(errors, sprintf("%s out of range [0,100] in row(s): %s",
                                    col, paste(bad, collapse = ", ")))
      }
    }
  }

  list(valid = length(errors) == 0, errors = errors, warnings = warnings)
}

validate_corr_matrix <- function(corr_matrix, n_params) {
  errors <- character()
  if (!is.matrix(corr_matrix))
    return(list(valid = FALSE, errors = "Correlation matrix must be a matrix"))
  if (nrow(corr_matrix) != n_params || ncol(corr_matrix) != n_params)
    errors <- c(errors, paste("Matrix dimensions don't match parameters:", n_params))
  if (!isSymmetric(corr_matrix, tol = 1e-8))
    errors <- c(errors, "Correlation matrix is not symmetric")
  eigenvalues <- eigen(corr_matrix, only.values = TRUE)$values
  if (any(eigenvalues < -1e-8))
    errors <- c(errors, "Correlation matrix is not positive semi-definite (can be auto-corrected)")
  list(valid = length(errors) == 0, errors = errors)
}

validate_manure_fractions <- function(fractions) {
  total <- sum(fractions)
  if (abs(total - 1.0) > 0.01)
    return(list(valid = FALSE,
                errors = paste("Manure fractions sum to", round(total * 100, 1), "% (must be ~100%)")))
  list(valid = TRUE, errors = character())
}

# C1: also normalise legacy parameter names to the new IPCC-aligned names
# before any completeness check or downstream processing.
normalise_param_names <- function(param_specs) {
  if (!"parameter" %in% names(param_specs) || !exists("PARAM_ALIASES"))
    return(param_specs)
  aliased <- param_specs$parameter %in% names(PARAM_ALIASES)
  if (any(aliased))
    param_specs$parameter[aliased] <- PARAM_ALIASES[param_specs$parameter[aliased]]
  if ("param_type" %in% names(param_specs))
    param_specs$param_type[param_specs$param_type == "emission_factor"] <- "coefficient"
  param_specs
}

# T1.2 / T2.2 + A1: completeness check — instead of blocking the Run button when
# core parameters are missing, auto-fill them from PARAM_CATALOGUE$ipcc_default.
# Returns a list with $param_specs (possibly augmented), $auto_filled (data frame
# of what was added), $message, and $valid (only FALSE if a core param has no
# default available — genuine error).
ensure_completeness <- function(param_specs, catalogue = PARAM_CATALOGUE,
                                 region = NULL) {
  if (is.null(param_specs) || nrow(param_specs) == 0)
    return(list(valid = FALSE, param_specs = param_specs,
                auto_filled = NULL, message = "No parameters loaded."))

  # C1: normalise any legacy parameter names first
  param_specs <- normalise_param_names(param_specs)

  required <- catalogue$parameter[catalogue$param_tier == "core"]
  defaults_lut <- setNames(catalogue$ipcc_default, catalogue$parameter)
  unc_lut      <- setNames(catalogue$suggested_uncertainty_pct, catalogue$parameter)
  dist_lut     <- setNames(catalogue$suggested_distribution, catalogue$parameter)
  type_lut     <- setNames(catalogue$param_type, catalogue$parameter)
  ref_lut      <- setNames(catalogue$ipcc_ref, catalogue$parameter)

  # Round 7 T2.1: when a region is supplied, prefer the regional default for
  # the 5 parameters covered by IPCC_DEFAULTS_BY_REGION (W, Milk, DE, Ym, Bo)
  # before falling back to the global PARAM_CATALOGUE default. Helper exists
  # since Round 3 G2 but was never wired to ensure_completeness().
  #
  # The regional value is NOT applied here. It was, and that made it blind to
  # cattle type: the table gained a dairy column in September 2026 so that a
  # dairy herd is compared against Annex 10A.1 rather than the non-dairy
  # 10A.2, and this loop kept handing every group the non-dairy figure. The
  # lookup now happens per group, below, where cattle_type is known. This
  # block only records WHICH parameters the region covers, for the message.
  use_region <- !is.null(region) && !is.na(region) && nzchar(region) &&
                exists("get_regional_default")
  region_used <- character()
  if (use_region)
    for (p in names(defaults_lut))
      if (!is.na(get_regional_default(p, region)))
        region_used <- c(region_used, p)

  group_cols <- intersect(c("cattle_type", "aggregation_level", "sub_category"),
                          names(param_specs))
  if (length(group_cols) == 0) {
    return(list(valid = TRUE, param_specs = param_specs, auto_filled = NULL,
                message = "Single-group input — no per-group completeness check."))
  }

  groups <- unique(param_specs[, group_cols, drop = FALSE])
  added_rows <- list()
  unfillable <- list()

  for (i in seq_len(nrow(groups))) {
    g <- groups[i, , drop = FALSE]
    sel <- Reduce(`&`, lapply(group_cols, function(c) param_specs[[c]] == g[[c]]))
    found <- unique(param_specs$parameter[sel])
    miss  <- setdiff(required, found)
    if (length(miss) == 0) next

    for (p in miss) {
      def <- defaults_lut[[p]]
      # Regional override, resolved with this group's cattle type so a dairy
      # herd gets the Table 10A.1 column and a non-dairy herd 10A.2.
      if (use_region) {
        reg_val <- get_regional_default(
          p, region,
          cattle_type = if ("cattle_type" %in% names(g)) g[["cattle_type"]] else NULL)
        if (!is.na(reg_val)) def <- reg_val
      }
      if (is.null(def) || is.na(def)) {
        # No default — record as unfillable
        unfillable[[length(unfillable) + 1]] <- list(
          group = paste(unlist(g), collapse = " / "),
          parameter = p
        )
        # Skip; row is left missing, downstream will warn but not crash
        next
      }
      pct <- unc_lut[[p]]
      if (is.na(pct)) pct <- 20  # safe fallback
      lower <- def * (1 - pct / 100)
      upper <- def * (1 + pct / 100)
      new_row <- as.data.frame(
        c(as.list(g),
          list(parameter = p,
               mean = def,
               uncertainty_pct = pct,
               lower = lower,
               upper = upper,
               distribution = dist_lut[[p]],
               param_type = type_lut[[p]],
               ipcc_ref = ref_lut[[p]],
               data_source = "AUTO-FILLED (IPCC default)",
               imputed = TRUE)),  # R1.3: flag for visibility downstream
        stringsAsFactors = FALSE)
      added_rows[[length(added_rows) + 1]] <- new_row
    }
  }

  # R1.3: ensure 'imputed' column exists across all rows
  if (!"imputed" %in% names(param_specs))
    param_specs$imputed <- FALSE

  if (length(added_rows) > 0) {
    target_cols <- names(param_specs)
    fill_df <- do.call(rbind, lapply(added_rows, function(r) {
      missing_cols <- setdiff(target_cols, names(r))
      for (mc in missing_cols) r[[mc]] <- NA
      r[, target_cols, drop = FALSE]
    }))
    param_specs <- rbind(param_specs, fill_df)
  }

  msg_parts <- character()
  if (length(added_rows) > 0) {
    base_msg <- sprintf("Auto-filled %d core parameter(s) from IPCC defaults.",
                         length(added_rows))
    if (length(region_used) > 0)
      base_msg <- paste0(base_msg,
        sprintf(" Region '%s' applied for: %s.",
                region, paste(region_used, collapse = ", ")))
    msg_parts <- c(msg_parts, base_msg)
  }
  if (length(unfillable) > 0) {
    uf <- vapply(unfillable, function(x) sprintf("%s — %s", x$group, x$parameter),
                 character(1))
    msg_parts <- c(msg_parts,
      sprintf("Cannot run: %d core parameter(s) have no IPCC default and are missing: %s.",
              length(unfillable), paste(head(uf, 3), collapse = "; ")))
  }
  if (length(msg_parts) == 0) msg_parts <- "All sub-categories complete."

  list(
    valid = length(unfillable) == 0,
    param_specs = param_specs,
    auto_filled = added_rows,
    message = paste(msg_parts, collapse = " ")
  )
}

# Backwards-compat shim — old callers may still use validate_completeness()
validate_completeness <- function(param_specs, catalogue = PARAM_CATALOGUE) {
  res <- ensure_completeness(param_specs, catalogue)
  list(valid = res$valid, missing = NULL, message = res$message)
}
