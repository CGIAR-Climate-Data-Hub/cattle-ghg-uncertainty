# Input Validation Functions

# ---------------------------------------------------------------------------
# How many groups this deployment can simulate (2026-10-13)
#
# A group is one (cattle_type, aggregation_level, sub_category) triple, which
# is what the sampler allocates per-iteration matrices for. Peak memory was
# measured on the Colombian fixture at about 1.8 MB per group against a single
# shinyapps.io worker with roughly 1 GB:
#
#   140 groups  420 MB  |  350  787 MB  |  560  1.14 GB  |  812  1.61 GB
#
# 400 is the point past which a run is more likely to die than finish, once
# Shiny's own overhead is allowed for. It is a property of the deployment, not
# of the method: a local R session with more memory has no such limit.
#
# One constant, used by the template upload check below, by the translator
# upload warning in R/chat_ui.R, and quoted to the model in the Runnable-size
# rule of the system prompt. Audit F64 fails if those drift apart.
# ---------------------------------------------------------------------------
.MAX_SIMULATED_GROUPS <- 400L

# Distinct groups described by a Parameters sheet. Used before a run to warn,
# never to block: a user may be running locally, where the limit is their own
# machine.
inventory_group_count <- function(param_specs) {
  if (is.null(param_specs) || !NROW(param_specs)) return(0L)
  key <- paste(param_specs$cattle_type %||% "",
               param_specs$aggregation_level %||% "",
               param_specs$sub_category %||% "",
               sep = "\u001f")
  length(unique(key))
}

# Thousands separator for the current language. French writes 10 089, not
# 10,089, and the group warning is one of the few places the app prints a
# number large enough for it to show.
.fmt_count <- function(n) {
  fr <- identical(get0(".LANG_CURRENT", envir = .GlobalEnv, ifnotfound = "en"), "fr")
  format(n, big.mark = if (fr) " " else ",", trim = TRUE)
}

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

  # 2026-10-28: the upload renames DE_pct to DE before this runs, so the
  # check looked for a name that never occurs. Both spellings now.
  de_rows <- param_specs$parameter %in% c("DE", "DE_pct")
  if (any(param_specs$mean[de_rows] > 100 | param_specs$mean[de_rows] < 0, na.rm = TRUE))
    errors <- c(errors, "Digestible energy (DE) must be between 0 and 100%")

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

# T1.2 / T2.2 + A1: completeness check, instead of blocking the Run button when
# core parameters are missing, auto-fill them from PARAM_CATALOGUE$ipcc_default.
# Returns a list with $param_specs (possibly augmented), $auto_filled (data frame
# of what was added), $message, and $valid (only FALSE if a core param has no
# default available: genuine error).
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

  # THE REGIONAL TABLE NO LONGER FILLS VALUES. Decided 2026-09-11.
  #
  # Round 7 T2.1 wired IPCC_DEFAULTS_BY_REGION into this function so a missing
  # BW took a continental figure instead of the catalogue default. The
  # reviewer's round 7 item 3 objection was that the tool cited IPCC defaults
  # he could not find in the guidelines; the response narrowed the benchmark
  # to BW only and never re-checked BW's own regional numbers. Read against
  # Table 10A.2 in September 2026, five of the six non-dairy values come from
  # the wrong table or from no table at all: asia 350, oceania 500 and
  # americas 500 match no 10A.2 row, europe 600 and americas 500 were read off
  # the DAIRY table, and no annex table has a global row. Only africa 275 is a
  # genuine 10A.2 figure.
  #
  # An unfindable number reaching a result is worse than a coarse one raising
  # a warning, and BW drives the entire energy chain through BW^0.75. So a
  # missing value now takes the catalogue default, which is verified to a
  # cited table and row. The regional table survives for the QA/QC
  # plausibility warning only, where an indicative continental yardstick is an
  # honest thing to compare against.

  group_cols <- intersect(c("cattle_type", "aggregation_level", "sub_category"),
                          names(param_specs))
  if (length(group_cols) == 0) {
    ps1 <- apply_default_ranges(param_specs, catalogue)
    return(list(valid = TRUE, param_specs = ps1, auto_filled = NULL,
                ranges_filled = sum(ps1$range_default %in% TRUE),
                message = "Single-group input: no per-group completeness check."))
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

    # The sub-category is known here, so use it. This loop used to fill every
    # group from the CATALOGUE alone, and the catalogue is the dairy-cow row:
    # a calves group with a blank BW was auto-filled at 270 kg against a calf
    # default of 60, and a bulls group at 270 against 350. BW enters the
    # energy chain as BW^0.75, so a calf filled at 4.5x its weight carries
    # roughly 3.4x the enteric emissions. resolve_subcat_default() has held
    # the right answer since June; the translator and the QA tab both call it,
    # and this path, the one that runs on every upload, did not.
    #
    # It also returns biological zeros, so a bulls group no longer gets a
    # milk yield.
    sub_cat <- if ("sub_category" %in% names(g)) as.character(g[["sub_category"]]) else NA
    subcat_default <- function(p) {
      if (is.na(sub_cat) || !nzchar(sub_cat)) return(NULL)
      r <- tryCatch(resolve_subcat_default(sub_cat, p), error = function(e) NULL)
      if (is.null(r) || is.null(r$value) || is.na(r$value)) return(NULL)
      r
    }

    for (p in miss) {
      rs  <- subcat_default(p)
      def <- if (!is.null(rs)) rs$value else defaults_lut[[p]]
      if (is.null(def) || is.na(def)) {
        # No default: record as unfillable
        unfillable[[length(unfillable) + 1]] <- list(
          group = paste(unlist(g), collapse = " / "),
          parameter = p
        )
        # Skip; row is left missing, downstream will warn but not crash
        next
      }
      pct <- if (!is.null(rs) && !is.null(rs$uncertainty_pct) &&
                 !is.na(rs$uncertainty_pct)) rs$uncertainty_pct else unc_lut[[p]]
      # No fallback range any more (2026-10-30): an input without a default
      # range keeps a blank one, which the QA/QC reports as Missing.
      if (is.null(pct)) pct <- NA_real_
      lower <- if (!is.null(rs) && !is.null(rs$lower) && !is.na(rs$lower))
                 rs$lower else if (is.na(pct)) NA_real_ else def * (1 - pct / 100)
      upper <- if (!is.null(rs) && !is.null(rs$upper) && !is.na(rs$upper))
                 rs$upper else if (is.na(pct)) NA_real_ else def * (1 + pct / 100)
      new_row <- as.data.frame(
        c(as.list(g),
          list(parameter = p,
               mean = def,
               uncertainty_pct = pct,
               lower = lower,
               upper = upper,
               distribution = if (!is.null(rs) && !is.null(rs$distribution) &&
                                  !is.na(rs$distribution))
                                rs$distribution else dist_lut[[p]],
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
    # The "Region 'X' applied for: ..." clause used to appear here. It is gone
    # with the regional override itself: the auto-fill no longer varies by
    # region, so saying that it did would be false. `region` is still accepted
    # as an argument because callers pass it and the QA tab still uses it.
    msg_parts <- c(msg_parts, base_msg)
  }
  if (length(unfillable) > 0) {
    uf <- vapply(unfillable, function(x) sprintf("%s: %s", x$group, x$parameter),
                 character(1))
    msg_parts <- c(msg_parts,
      sprintf("Cannot run: %d core parameter(s) have no IPCC default and are missing: %s.",
              length(unfillable), paste(head(uf, 3), collapse = "; ")))
  }
  # 2026-10-30: blank ranges take a default only where one is defensible
  # (see apply_default_ranges). Everything else stays blank for the QA/QC.
  n_before <- if ("range_default" %in% names(param_specs)) sum(param_specs$range_default %in% TRUE) else 0L
  param_specs <- apply_default_ranges(param_specs, catalogue)
  ranges_filled <- sum(param_specs$range_default %in% TRUE) - n_before

  if (length(msg_parts) == 0) msg_parts <- "All sub-categories complete."

  list(
    valid = length(unfillable) == 0,
    param_specs = param_specs,
    auto_filled = added_rows,
    ranges_filled = ranges_filled,
    message = paste(msg_parts, collapse = " ")
  )
}

# Backwards-compat shim: old callers may still use validate_completeness()
validate_completeness <- function(param_specs, catalogue = PARAM_CATALOGUE) {
  res <- ensure_completeness(param_specs, catalogue)
  list(valid = res$valid, missing = NULL, message = res$message)
}

# ===========================================================================
# DEFAULT UNCERTAINTY RANGES (decision 2026-10-30)
#
# A default range is applied ONLY where the literature gives one that can be
# defended for another country's data:
#   - IPCC publishes the range together with the default value (Ym, Bo, the
#     Chapter 11 pasture factors and fractions; per manure system, EF3 and
#     the Table 10.22 volatilisation and leaching fractions);
#   - Cfi, Ca, C and Cp: IPCC equation coefficients that no country can
#     measure, with the expert-judgement ranges of Monni et al. (2007) that
#     the Finnish and UK inventories use.
# Every other input (animal numbers, weights, milk, fat, pregnancy, diet,
# MCF ...) describes the country's own data, so its range must come from the
# country. A blank range there is reported as Missing by the QA/QC and blocks
# the run until the compiler enters one (or sets the distribution to
# constant, which says the value is known exactly).
#
# The bounds-type defaults (asymmetric IPCC ranges) belong to the IPCC
# default value: they are applied only when the row carries that value. A
# percentage default is applied around whatever value the row carries, and
# the QA/QC info row asks for an own range when the value is the country's.
# ===========================================================================
DEFAULT_RANGE_SOURCE <- c(
  Ym             = "IPCC 2019, Vol. 4, Table 10.12",
  Bo             = "IPCC 2019, Vol. 4, Table 10.16A",
  Cfi            = "Monni et al. (2007), Table I",
  Ca             = "Monni et al. (2007), Table I",
  C              = "Monni et al. (2007), Table I",
  Cp             = "Monni et al. (2007), Table I",
  EF3_PRP        = "IPCC 2019, Vol. 4, Table 11.1",
  EF4            = "IPCC 2019, Vol. 4, Table 11.3",
  EF5            = "IPCC 2019, Vol. 4, Table 11.3",
  Frac_GASM_PRP  = "IPCC 2019, Vol. 4, Table 11.3",
  Frac_LEACH_PRP = "IPCC 2019, Vol. 4, Table 11.3"
)

.same_value <- function(a, b) {
  length(a) == 1L && length(b) == 1L && !is.na(a) && !is.na(b) &&
    abs(a - b) <= 1e-9 * max(1, abs(b))
}

# The default range for one parameter around one value, or NULL.
default_range_for <- function(parameter, mean, catalogue = PARAM_CATALOGUE) {
  if (is.null(parameter) || is.na(parameter) || is.na(mean)) return(NULL)
  if (!parameter %in% names(DEFAULT_RANGE_SOURCE)) return(NULL)
  i <- match(parameter, catalogue$parameter)
  if (is.na(i)) return(NULL)
  src <- unname(DEFAULT_RANGE_SOURCE[[parameter]])
  pct <- suppressWarnings(as.numeric(catalogue$suggested_uncertainty_pct[i]))
  if (!is.na(pct)) {
    b <- calc_bounds(mean, pct)
    return(list(pct = pct, lower = b$lower, upper = b$upper, source = src))
  }
  lo  <- suppressWarnings(as.numeric(catalogue$suggested_lower_bound[i]))
  hi  <- suppressWarnings(as.numeric(catalogue$suggested_upper_bound[i]))
  def <- suppressWarnings(as.numeric(catalogue$ipcc_default[i]))
  if (!is.na(lo) && !is.na(hi) && .same_value(mean, def))
    return(list(pct = NA_real_, lower = lo, upper = hi, source = src))
  NULL
}

# TRUE when a row needs a range and has none: not a constant, a non-zero
# value, and no lower or no upper bound.
range_is_blank <- function(mean, lower, upper, distribution) {
  is_const <- !is.na(distribution) & tolower(distribution) %in% c("constant", "const")
  !is_const & !is.na(mean) & mean != 0 & (is.na(lower) | is.na(upper))
}

# PLACEHOLDER RANGES (decision 2026-10-30, later the same day). A blank
# range on an input with no defensible default no longer stops the run: it
# takes a placeholder, the value the catalogue carried before the decision
# (EXAMPLE_ILLUSTRATION_UNC_PCT). A placeholder has no published source. It is
# flagged (range_placeholder), shown as a Warn on the QA/QC tab, listed in the
# Word report, marked in the Excel and IPCC-table exports, and tagged in the
# translated template ("placeholder range" in data_source), so it is never
# mistaken for a default or for the country's own range.
# Written out, not taken from EXAMPLE_ILLUSTRATION_UNC_PCT, because some
# scripts source the R files in another order; audit F65 checks the two
# agree.
PLACEHOLDER_UNC_PCT <- c(
  N = 10, BW = 15, MW = 10, WG = 30, Milk = 20, Fat = 10, pct_pregnant = 20,
  DE = 15, hours = 20, CP = 15, ASH = 25, UE = 25, MilkPR = 10, Tw = 25,
  GE = 15, DMI = 15)
.PLACEHOLDER_TAG <- "placeholder range"

# The placeholder range for one parameter around one value, or NULL.
# Percentage parameters take PLACEHOLDER_UNC_PCT; a bounds-type IPCC input
# with the country's own value keeps the IPCC range's shape scaled to it.
placeholder_range_for <- function(parameter, mean, catalogue = PARAM_CATALOGUE) {
  if (is.null(parameter) || is.na(parameter) || is.na(mean) || mean == 0) return(NULL)
  # Tw at 20 C or above has no effect (the cold adjustment applies below
  # 20 C only); a range around it would push half the draws below 20 and
  # raise Cfi in warm climates. It is treated as a fixed value instead.
  if (identical(parameter, "Tw") && mean >= 20) return(NULL)
  pct <- if (parameter %in% names(PLACEHOLDER_UNC_PCT)) unname(PLACEHOLDER_UNC_PCT[[parameter]]) else NA_real_
  if (!is.na(pct)) {
    b <- calc_bounds(mean, pct)
    return(list(pct = pct, lower = b$lower, upper = b$upper,
                label = sprintf("+/-%s%%", format(pct))))
  }
  i <- match(parameter, catalogue$parameter)
  if (is.na(i)) return(NULL)
  lo  <- suppressWarnings(as.numeric(catalogue$suggested_lower_bound[i]))
  hi  <- suppressWarnings(as.numeric(catalogue$suggested_upper_bound[i]))
  def <- suppressWarnings(as.numeric(catalogue$ipcc_default[i]))
  if (is.na(lo) || is.na(hi) || is.na(def) || def == 0) return(NULL)
  list(pct = NA_real_, lower = mean * lo / def, upper = mean * hi / def,
       label = "the IPCC range scaled to your value")
}

# Fill blank ranges: a defensible default where one exists (range_default),
# else a placeholder (range_placeholder). A row the translator tagged
# "placeholder range" in data_source keeps its range and is flagged too.
apply_default_ranges <- function(param_specs, catalogue = PARAM_CATALOGUE) {
  ps <- param_specs
  if (is.null(ps) || !nrow(ps) || !all(c("parameter", "mean") %in% names(ps)))
    return(ps)
  for (cl in c("lower", "upper", "uncertainty_pct"))
    if (!cl %in% names(ps)) ps[[cl]] <- NA_real_
  if (!"distribution" %in% names(ps)) ps$distribution <- NA_character_
  for (fl in c("range_default", "range_placeholder")) {
    if (!fl %in% names(ps)) ps[[fl]] <- FALSE
    ps[[fl]][is.na(ps[[fl]])] <- FALSE
  }
  if ("data_source" %in% names(ps))
    ps$range_placeholder[grepl(.PLACEHOLDER_TAG, as.character(ps$data_source), fixed = TRUE)] <- TRUE
  mu <- suppressWarnings(as.numeric(ps$mean))
  blank <- range_is_blank(mu, suppressWarnings(as.numeric(ps$lower)),
                          suppressWarnings(as.numeric(ps$upper)),
                          as.character(ps$distribution))
  for (i in which(blank)) {
    if (identical(as.character(ps$parameter[i]), "Tw") && mu[i] >= 20) {
      ps$distribution[i] <- "constant"; ps$lower[i] <- mu[i]; ps$upper[i] <- mu[i]
      next
    }
    r <- default_range_for(ps$parameter[i], mu[i], catalogue)
    is_def <- !is.null(r)
    if (!is_def) r <- placeholder_range_for(ps$parameter[i], mu[i], catalogue)
    if (is.null(r)) next
    if (!is.na(r$pct)) ps$uncertainty_pct[i] <- r$pct
    ps$lower[i] <- r$lower
    ps$upper[i] <- r$upper
    if (is.na(ps$distribution[i]) || !nzchar(ps$distribution[i])) {
      j <- match(ps$parameter[i], catalogue$parameter)
      ps$distribution[i] <- catalogue$suggested_distribution[j]
    }
    if (is_def) ps$range_default[i] <- TRUE else ps$range_placeholder[i] <- TRUE
  }
  ps
}

# Manure sheet: the IPCC range of a per-system value, or NULL. EF3 varies by
# a factor of 2 (IPCC 2019 Vol. 4 Table 10.21 footnote 24); the volatilisation
# and leaching fractions take the Table 10.22 range where IPCC publishes one.
# MCF has no published range, so it has none here. Each range belongs to the
# IPCC default value of that system and is used only when the row carries it.
# `value` is in the sheet's unit (EF3 a fraction, the fractions in percent).
MANURE_RANGE_FIELDS <- list(
  MCF_pct          = c(lower = "lower_mcf",        upper = "upper_mcf"),
  EF3              = c(lower = "lower_ef3",        upper = "upper_ef3"),
  Frac_GasMS_pct   = c(lower = "lower_frac_gas",   upper = "upper_frac_gas"),
  Frac_LeachMS_pct = c(lower = "lower_frac_leach", upper = "upper_frac_leach")
)

.mms_bound_is_ipcc <- function(mms_type, field) {
  if (!exists(".defaults_master")) return(FALSE)
  m <- .defaults_master
  v <- m$ipcc_verdict[m$object == "MMS_FRAC_DEFAULTS_2019" & m$key == mms_type &
                      m$field %in% paste0(field, c("_low", "_high"))]
  length(v) == 2L && all(v %in% c("CONFIRMED", "INTERPRETED"))
}

manure_default_range <- function(mms_type, column, value) {
  if (is.na(value) || is.na(mms_type)) return(NULL)
  if (column == "EF3") {
    d <- tryCatch(mms_default(mms_type, "ef3"), error = function(e) NA_real_)
    if (!.same_value(value, d) || d <= 0) return(NULL)
    return(list(lower = d / 2, upper = d * 2,
                source = "IPCC 2019, Vol. 4, Table 10.21 (factor of 2)"))
  }
  fld <- switch(column, Frac_GasMS_pct = "frac_gas", Frac_LeachMS_pct = "frac_leach", NULL)
  if (is.null(fld)) return(NULL)
  if (!mms_type %in% MMS_FRAC_DEFAULTS_2019$mms_type) return(NULL)
  if (!.mms_bound_is_ipcc(mms_type, fld)) return(NULL)
  d <- mms_frac_defaults_2019(mms_type)
  if (!.same_value(value, d[[fld]] * 100)) return(NULL)
  list(lower = d[[paste0(fld, "_low")]] * 100, upper = d[[paste0(fld, "_high")]] * 100,
       source = "IPCC 2019, Vol. 4, Table 10.22")
}

# Manure placeholders (2026-10-30): MCF +/-25 %, EF3 a factor of two either
# way, the volatilisation and leaching fractions +/-50 %: the ranges the
# translator and the project rule used before the decision. Percent columns
# are capped at 100.
MANURE_PLACEHOLDER <- list(
  MCF_pct          = list(lo = 0.75, hi = 1.25, label = "+/-25%"),
  EF3              = list(lo = 0.5,  hi = 2,    label = "a factor of 2"),
  Frac_GasMS_pct   = list(lo = 0.5,  hi = 1.5,  label = "+/-50%"),
  Frac_LeachMS_pct = list(lo = 0.5,  hi = 1.5,  label = "+/-50%"))

# Fill blank manure ranges: the IPCC range where one exists for the IPCC
# default value, else the placeholder. Placeholder columns are listed per row
# in range_placeholder_cols (comma-separated); a translated template carries
# them in its data_source column ("placeholder range: MCF_pct, EF3").
# Rows whose value cell is blank are left alone here: the sampler fills the
# value from the system's IPCC default and its IPCC range.
apply_default_ranges_manure <- function(manure) {
  if (is.null(manure) || !nrow(manure) || !"mms_type" %in% names(manure)) return(manure)
  if (!"range_placeholder_cols" %in% names(manure)) manure$range_placeholder_cols <- NA_character_
  if ("data_source" %in% names(manure)) {
    # the tag the translator writes starts the cell ("placeholder range:
    # MCF_pct, EF3"); the template's hint row only mentions it
    tagged <- grepl(paste0("^[[:space:]]*", .PLACEHOLDER_TAG), as.character(manure$data_source))
    manure$range_placeholder_cols[tagged & is.na(manure$range_placeholder_cols)] <-
      trimws(sub(paste0("^.*", .PLACEHOLDER_TAG, "[: ]*"), "", as.character(manure$data_source[tagged & is.na(manure$range_placeholder_cols)])))
  }
  add_flag <- function(i, col) {
    cur <- manure$range_placeholder_cols[i]
    manure$range_placeholder_cols[i] <<- if (is.na(cur) || !nzchar(cur)) col else paste(unique(c(strsplit(cur, ", *")[[1]], col)), collapse = ", ")
  }
  for (col in names(MANURE_RANGE_FIELDS)) {
    if (!col %in% names(manure)) next
    f <- MANURE_RANGE_FIELDS[[col]]
    for (cl in f) if (!cl %in% names(manure)) manure[[cl]] <- NA_real_
    val <- suppressWarnings(as.numeric(manure[[col]]))
    lo  <- suppressWarnings(as.numeric(manure[[f[["lower"]]]]))
    hi  <- suppressWarnings(as.numeric(manure[[f[["upper"]]]]))
    share <- if ("fraction_pct" %in% names(manure)) suppressWarnings(as.numeric(manure$fraction_pct)) else rep(1, nrow(manure))
    for (i in which(!is.na(val) & val != 0 & (is.na(lo) | is.na(hi)))) {
      id <- as.character(manure$mms_type[i])
      r <- manure_default_range(id, col, val[i])
      if (!is.null(r)) {
        manure[[f[["lower"]]]][i] <- r$lower; manure[[f[["upper"]]]][i] <- r$upper
        next
      }
      # pasture's EF3 and fractions are not used; systems with no share
      # and placeholder rows of the template need no range
      if (identical(id, "pasture") && col != "MCF_pct") next
      if (is.na(share[i]) || share[i] <= 0) next
      if (is.na(id) || !nzchar(trimws(id)) || grepl("^select", id, ignore.case = TRUE)) next
      ph <- MANURE_PLACEHOLDER[[col]]
      cap <- if (col == "EF3") Inf else 100
      manure[[f[["lower"]]]][i] <- val[i] * ph$lo
      manure[[f[["upper"]]]][i] <- min(cap, val[i] * ph$hi)
      add_flag(i, col)
    }
  }
  manure
}

# The IPCC default of a manure column for one system, in the sheet's unit.
.manure_column_default <- function(id, column, climate = "tropical") {
  tryCatch(switch(column,
    MCF_pct          = mms_mcf_fraction(id, climate) * 100,
    EF3              = mms_default(id, "ef3"),
    Frac_GasMS_pct   = mms_frac_defaults_2019(id)$frac_gas * 100,
    Frac_LeachMS_pct = mms_frac_defaults_2019(id)$frac_leach * 100,
    NA_real_), error = function(e) NA_real_)
}

# Manure rows still without a range: one row per (sheet row, column), for the
# QA/QC. A blank value cell is read as that system's IPCC default, since that
# is what the sampler uses, and takes the IPCC range where one exists.
# Systems with a zero share, and zero values, need no range.
manure_missing_ranges <- function(manure, climate = "tropical") {
  if (is.null(manure) || !nrow(manure) || !"mms_type" %in% names(manure)) return(NULL)
  frac <- if ("fraction_pct" %in% names(manure))
    suppressWarnings(as.numeric(manure$fraction_pct)) else rep(1, nrow(manure))
  col_or_na <- function(nm) if (nm %in% names(manure))
    suppressWarnings(as.numeric(manure[[nm]])) else rep(NA_real_, nrow(manure))
  out <- list()
  for (col in names(MANURE_RANGE_FIELDS)) {
    f <- MANURE_RANGE_FIELDS[[col]]
    val <- col_or_na(col); lo <- col_or_na(f[["lower"]]); hi <- col_or_na(f[["upper"]])
    for (i in seq_len(nrow(manure))) {
      # A row with no share, or no system (the template's "Select from
      # dropdown" placeholder), is not a manure system.
      if (is.na(frac[i]) || frac[i] <= 0) next
      if (!is.na(lo[i]) && !is.na(hi[i])) next
      id <- as.character(manure$mms_type[i])
      if (is.na(id) || !nzchar(trimws(id)) || grepl("^select", id, ignore.case = TRUE)) next
      # A blank value cell is filled by the sampler with the system's IPCC
      # default and its IPCC range or a placeholder: nothing is missing.
      if (is.na(val[i])) next
      # Pasture N goes through the Chapter 11 pathway (EF3_PRP, Frac_GASM_PRP,
      # Frac_LEACH_PRP on the Parameters sheet); the row's EF3 and fractions
      # are not used, so they need no range. Its MCF is used.
      if (identical(id, "pasture") && col != "MCF_pct") next
      v <- val[i]
      if (is.na(v)) v <- .manure_column_default(id, col, climate)
      if (is.na(v) || v == 0) next
      if (!is.null(manure_default_range(id, col, v))) next
      grp <- paste(c(if ("cattle_type" %in% names(manure)) manure$cattle_type[i],
                     if ("sub_category" %in% names(manure) && !is.na(manure$sub_category[i]) &&
                         nzchar(manure$sub_category[i])) manure$sub_category[i]),
                   collapse = " / ")
      lvl <- if ("aggregation_level" %in% names(manure)) as.character(manure$aggregation_level[i]) else NA_character_
      out[[length(out) + 1L]] <- data.frame(row = i, group = grp, level = lvl,
                                            mms_type = id, column = col, value = v,
                                            stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

# Labels of the inputs that still have no range, limited to what the selected
# emission sources use. Empty when the run may go ahead.
run_range_gate <- function(param_specs, manure, needed_params, sources) {
  out <- character()
  ps <- param_specs
  if (!is.null(ps) && nrow(ps) > 0 && all(c("parameter", "mean") %in% names(ps))) {
    lo <- if ("lower" %in% names(ps)) suppressWarnings(as.numeric(ps$lower)) else rep(NA_real_, nrow(ps))
    hi <- if ("upper" %in% names(ps)) suppressWarnings(as.numeric(ps$upper)) else rep(NA_real_, nrow(ps))
    d  <- if ("distribution" %in% names(ps)) as.character(ps$distribution) else rep(NA_character_, nrow(ps))
    bl <- range_is_blank(suppressWarnings(as.numeric(ps$mean)), lo, hi, d) &
          ps$parameter %in% needed_params
    if (any(bl)) {
      key_cols <- intersect(c("cattle_type", "sub_category"), names(ps))
      grp <- if (length(key_cols)) do.call(paste, c(lapply(key_cols, function(k) ps[[k]][bl]), sep = " / ")) else ""
      out <- c(out, paste0(grp, ": ", ps$parameter[bl]))
    }
  }
  mm <- manure_missing_ranges(manure)
  if (!is.null(mm) && nrow(mm) > 0) {
    if ("pasture_n2o" %in% sources) sources <- c(sources, "pasture_n2o_direct", "pasture_n2o_indirect")
    need_col <- c(MCF_pct = "manure_ch4" %in% sources,
                  EF3 = "manure_n2o_direct" %in% sources,
                  Frac_GasMS_pct = "manure_n2o_indirect" %in% sources,
                  Frac_LeachMS_pct = "manure_n2o_indirect" %in% sources)
    mm <- mm[need_col[mm$column] %in% TRUE, , drop = FALSE]
    if (nrow(mm) > 0)
      out <- c(out, paste0(ifelse(nzchar(mm$group), paste0(mm$group, ": "), ""),
                           mm$column, " (", mm$mms_type, ")"))
  }
  unique(out)
}

# Where each range came from, for the Excel export (one label per row).
range_source_label <- function(param_specs) {
  ps <- param_specs
  if (is.null(ps) || !nrow(ps)) return(character(0))
  d  <- if ("distribution" %in% names(ps)) tolower(as.character(ps$distribution)) else rep("", nrow(ps))
  mu <- suppressWarnings(as.numeric(ps$mean))
  out <- rep("your file", nrow(ps))
  out[d %in% c("constant", "const") | (!is.na(mu) & mu == 0)] <- "no range (fixed value)"
  if ("range_default" %in% names(ps)) {
    k <- which(ps$range_default %in% TRUE)
    out[k] <- paste0("default range: ", ifelse(ps$parameter[k] %in% names(DEFAULT_RANGE_SOURCE),
                                               unname(DEFAULT_RANGE_SOURCE[as.character(ps$parameter[k])]), ""))
  }
  if ("range_placeholder" %in% names(ps))
    out[ps$range_placeholder %in% TRUE] <- "PLACEHOLDER: no published source, replace with your own"
  out
}

# Every placeholder, one row per (group, input), for the Word report.
placeholder_table <- function(param_specs, manure = NULL) {
  rows <- list()
  ps <- param_specs
  if (!is.null(ps) && nrow(ps) && "range_placeholder" %in% names(ps)) {
    k <- which(ps$range_placeholder %in% TRUE)
    for (i in k) {
      pct <- suppressWarnings(as.numeric(ps$uncertainty_pct[i]))
      rng <- if (!is.na(pct)) sprintf("+/-%s%%", format(pct))
             else sprintf("%s to %s", format(signif(as.numeric(ps$lower[i]), 4)), format(signif(as.numeric(ps$upper[i]), 4)))
      rows[[length(rows) + 1L]] <- data.frame(
        Group = paste(c(if ("aggregation_level" %in% names(ps)) ps$aggregation_level[i], ps$sub_category[i]), collapse = " / "),
        Input = as.character(ps$parameter[i]), Value = format(signif(as.numeric(ps$mean[i]), 5)),
        `Placeholder range` = rng, check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  if (!is.null(manure) && is.data.frame(manure) && nrow(manure) && "range_placeholder_cols" %in% names(manure)) {
    for (i in which(!is.na(manure$range_placeholder_cols) & nzchar(manure$range_placeholder_cols))) {
      for (col in strsplit(manure$range_placeholder_cols[i], ", *")[[1]]) {
        f <- MANURE_RANGE_FIELDS[[col]]; if (is.null(f)) next
        rows[[length(rows) + 1L]] <- data.frame(
          Group = paste(c(if ("aggregation_level" %in% names(manure)) manure$aggregation_level[i], manure$sub_category[i]), collapse = " / "),
          Input = sprintf("%s (%s)", col, manure$mms_type[i]),
          Value = format(signif(suppressWarnings(as.numeric(manure[[col]][i])), 5)),
          `Placeholder range` = sprintf("%s to %s (%s)", format(signif(as.numeric(manure[[f[["lower"]]]][i]), 4)),
                                        format(signif(as.numeric(manure[[f[["upper"]]]][i]), 4)), MANURE_PLACEHOLDER[[col]]$label),
          check.names = FALSE, stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

# For each IPCC reporting line, the inputs that carry a placeholder range
# (the parameters the source uses, plus the manure columns it reads).
.IPCC_LINE_SOURCES <- list(
  enteric_ch4_total      = list(src = "enteric_ch4",          mm = character(0)),
  manure_ch4_total       = list(src = "manure_ch4",           mm = "MCF_pct"),
  direct_n2o_mm_total    = list(src = "manure_n2o_direct",    mm = "EF3"),
  indirect_n2o_mm_total  = list(src = "manure_n2o_indirect",  mm = c("Frac_GasMS_pct", "Frac_LeachMS_pct")),
  direct_n2o_prp_total   = list(src = "pasture_n2o_direct",   mm = character(0)),
  indirect_n2o_prp_total = list(src = "pasture_n2o_indirect", mm = character(0)))
.IPCC_LINE_TOTALS <- list(
  total_ch4  = c("enteric_ch4_total", "manure_ch4_total"),
  total_n2o  = c("direct_n2o_mm_total", "indirect_n2o_mm_total", "direct_n2o_prp_total", "indirect_n2o_prp_total"),
  total_co2e = names(.IPCC_LINE_SOURCES))

placeholder_inputs_by_line <- function(param_specs, manure = NULL) {
  ps <- param_specs
  pp <- if (!is.null(ps) && nrow(ps) && "range_placeholder" %in% names(ps))
    unique(as.character(ps$parameter[ps$range_placeholder %in% TRUE])) else character(0)
  mc <- if (!is.null(manure) && is.data.frame(manure) && "range_placeholder_cols" %in% names(manure))
    unique(unlist(strsplit(stats::na.omit(manure$range_placeholder_cols), ", *"))) else character(0)
  one <- function(k) {
    sp <- .IPCC_LINE_SOURCES[[k]]
    c(intersect(pp, SOURCE_PARAM_DEPS[[sp$src]]), intersect(mc, sp$mm))
  }
  out <- lapply(names(.IPCC_LINE_SOURCES), one); names(out) <- names(.IPCC_LINE_SOURCES)
  for (k in names(.IPCC_LINE_TOTALS)) out[[k]] <- unique(unlist(out[.IPCC_LINE_TOTALS[[k]]]))
  vapply(out, function(v) if (length(v)) paste(sort(v), collapse = ", ") else "none", character(1))
}
