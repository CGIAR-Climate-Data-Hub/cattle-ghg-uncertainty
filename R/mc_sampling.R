# Monte Carlo Sampling Engine
# Correlated sampling uses the rank-correlation-preserving restricted-pairing
# procedure per IPCC Vol.1 Ch.3 §3.2.3.2 — independent draws from each
# parameter's marginal distribution, then column reordering so the resulting
# Spearman rank correlation matches the target matrix. Distribution-free, so
# the marginal shapes (PERT / lognormal / beta / normal / uniform) are
# preserved exactly.

# Build an n x n uniform correlation matrix (all off-diagonal entries = rho).
# Andreas 2026-05 audit follow-up: warn when nearPD has to make a large
# adjustment to the user-supplied correlation matrix, instead of silently
# changing the correlations to enforce positive-definiteness.
# 2026-05 follow-up #2: tol lowered from 0.05 to 0.01 so users are told about
# shifts that matter (a 0.05 shift to a correlation of 0.30 is a 17% relative
# change — large enough to affect MC results).
.repair_corr <- function(m, label = "correlation matrix", tol = 0.01) {
  fixed <- as.matrix(Matrix::nearPD(m, corr = TRUE)$mat)
  if (is.matrix(m) && all(dim(m) == dim(fixed))) {
    delta <- max(abs(fixed - m), na.rm = TRUE)
    if (is.finite(delta) && delta > tol) {
      warning(sprintf(
        "Supplied %s was not positive-definite; nearPD adjusted correlations by up to %.3f (tol=%.2f).",
        label, delta, tol), call. = FALSE)
    }
  }
  fixed
}

# Used for the legacy "uniform EF correlation" option where a single rho
# represents shared systematic bias across all emission factors. Retained for
# back-compat; the default UI control switched to make_block_corr() in the
# 2026-05 audit follow-up because a single rho across 13 heterogeneous
# coefficients (energy, manure-CH4, manure-N) is statistically extreme.
make_uniform_corr <- function(n, rho) {
  if (n <= 1) return(diag(max(n, 1L)))
  m <- matrix(rho, n, n)
  diag(m) <- 1.0
  .repair_corr(m, "uniform-rho correlation matrix")
}

# 2026-05 audit follow-up: block-structured EF correlation.
# Groups the IPCC coefficients into three blocks that share a measurement /
# methodological provenance, and lets each block carry its own within-block
# correlation. Cross-block entries are zero (the three literatures —
# energy-equation rumen studies, BMP / lagoon studies, NH3/N2O volatilisation
# studies — are independent).
.EF_BLOCKS <- list(
  # Energy-equation coefficients (IPCC Eq 10.3 / 10.4 / 10.16 / 10.21 family)
  energy   = c("Cfi", "Ca", "C", "C_growth", "Cp", "Ym", "Ym_pct"),
  # Manure-CH4 coefficients (BMP / lagoon literature)
  manureCH = c("Bo", "MCF", "ASH", "ash"),
  # Manure-N coefficients (NH3 / N2O volatilisation literature).
  # Andreas 2026-05-27: EF3_S / Frac_GASMS / Frac_LEACH_H dropped from the
  # Parameters sheet (now per-MMS in Manure_Management); legacy aliases
  # ("EF3", "Frac_GASM", "Frac_LEACH") retained so old uploads still map.
  manureN  = c("EF3_PRP", "EF3",
               "Frac_GASM_PRP", "Frac_GASM",
               "EF4", "EF5",
               "Frac_LEACH_PRP", "Frac_LEACH",
               "UE")
)

# Build an n x n block-diagonal correlation matrix. `param_names` are the
# column ordering you want in the output (typically ef_params$parameter);
# `rho_by_block` is a named list like list(energy = 0.3, manureCH = 0.2, manureN = 0).
# Blocks with rho == 0 (or absent) contribute identity rows/cols; blocks with
# only one matching parameter in `param_names` likewise contribute identity.
make_block_corr <- function(param_names, rho_by_block) {
  n <- length(param_names)
  if (n == 0) return(matrix(0, 0, 0))
  m <- diag(n)
  rownames(m) <- colnames(m) <- param_names
  for (blk in names(.EF_BLOCKS)) {
    rho <- rho_by_block[[blk]]
    if (is.null(rho) || !is.finite(rho) || rho == 0) next
    idx <- which(param_names %in% .EF_BLOCKS[[blk]])
    if (length(idx) >= 2) {
      sub <- matrix(rho, length(idx), length(idx))
      diag(sub) <- 1
      m[idx, idx] <- sub
    }
  }
  .repair_corr(m, "block-structured EF correlation matrix")
}

# Correlated sampling for one block of parameters.
# Procedure per IPCC Vol.1 Ch.3 §3.2.3.2: draw each column independently from
# its own marginal, then reorder columns so the resulting Spearman rank
# correlation matches the target matrix. Distribution-free, so the marginal
# shapes (PERT / lognormal / beta / normal / uniform) are preserved exactly.
.iman_conover_sample <- function(n_iter, params, target_rank_corr) {
  target_rank_corr <- .repair_corr(target_rank_corr,
                                   "target rank correlation matrix")
  X <- .indep_sample(n_iter, params)
  # mc2d::cornode reorders the columns of X so that the rank correlation
  # matches `target` while preserving each column's marginal distribution.
  out <- mc2d::cornode(X, target = target_rank_corr, outrank = FALSE,
                        result = FALSE)
  colnames(out) <- params$parameter
  out
}

# Independent sampling for one block (no correlation structure imposed)
.indep_sample <- function(n_iter, params) {
  samp <- matrix(NA, nrow = n_iter, ncol = nrow(params))
  for (j in seq_len(nrow(params))) {
    samp[, j] <- sample_distribution(
      n_iter, params$distribution[j],
      params$mean[j], params$lower[j], params$upper[j]
    )
  }
  colnames(samp) <- params$parameter
  samp
}

# Physically/empirically valid domains for sampled parameters whose governing
# IPCC equations break down outside a documented range. Draws are clamped to
# these bounds AFTER sampling, so the per-iteration calc never evaluates an
# equation outside the domain it was fitted on.
#
# DE (feed digestibility, %): the net-energy-ratio equations REM/REG (2019
# Refinement Vol.4 Ch.10, Eq 10.14/10.15) are empirical fits to ruminant data
# with DE in 45-85% (Ch.10 p.20: 45-55% crop by-products / rangelands; 55-80%
# managed pasture; 72-85% grain-fed feedlot). REG crosses zero near DE = 37.6%,
# so an untruncated normal draw in the low tail (e.g. DE = 38%) sends gross
# energy GE = [.../REM + NEg/REG] / (DE/100) toward +/-infinity and produces
# impossible — even negative — emissions, which stretch the output histogram
# and pull the mean above the 97.5th percentile. Clamping DE to the documented
# range keeps every iteration inside the equations' valid domain. Both the IPCC
# ("DE") and legacy ("DE_pct") column spellings are covered.
.PHYSICAL_BOUNDS <- list(
  DE     = c(45, 85),
  DE_pct = c(45, 85)
)

# Clamp any sampled column that has a registered physical domain into that
# domain. A no-op for columns not in .PHYSICAL_BOUNDS, so it is safe to call on
# every sample frame regardless of which parameters are present. Non-finite
# entries are left untouched (the final scrub in sample_distribution() handles
# those). Returns the same data frame with the offending columns clamped.
.clamp_physical_bounds <- function(df) {
  for (nm in intersect(names(df), names(.PHYSICAL_BOUNDS))) {
    b  <- .PHYSICAL_BOUNDS[[nm]]
    v  <- df[[nm]]
    ok <- is.finite(v)
    v[ok] <- pmin(pmax(v[ok], b[1L]), b[2L])
    df[[nm]] <- v
  }
  df
}

# Generate MC samples.
#   corr_matrix    – optional correlation matrix for activity data (n_AD x n_AD)
#   ef_corr_matrix – optional correlation matrix for emission factors (n_EF x n_EF).
#                    Pass make_uniform_corr(n_ef, rho) for a uniform assumption.
generate_mc_samples <- function(param_specs, corr_matrix = NULL, n_iter = 10000,
                                 seed = NULL, ef_corr_matrix = NULL,
                                 # Round 7 T4.3: unified correlation across AD +
                                 # coefficients so cross-block correlations
                                 # (e.g. BW <-> Cfi) are honoured. When supplied,
                                 # this is a square named matrix covering the
                                 # union of AD and coefficient parameter names.
                                 # Falls back to the two-pass behaviour when NULL.
                                 unified_corr_matrix = NULL,
                                 # Round 7 R1.14: pre-sampled coefficient block
                                 # matrix (n_iter x n_coef) used by the trend tab
                                 # to share the same coefficient draws across
                                 # years. Overrides the coefficient-block sampler
                                 # when supplied.
                                 pre_sampled_coefficients = NULL,
                                 # All correlated paths use the rank-correlation
                                 # preserving procedure per IPCC Vol.1 Ch.3
                                 # §3.2.3.2. Kept as an argument for back-compat;
                                 # the only accepted value is "iman_conover".
                                 sampler = "iman_conover") {
  sampler <- match.arg(sampler, choices = "iman_conover")
  if (!is.null(seed)) set.seed(seed)

  ad_params <- param_specs[param_specs$param_type == "activity_data", ]
  ef_params <- param_specs[param_specs$param_type == "coefficient", ]
  n_ad <- nrow(ad_params)
  n_ef <- nrow(ef_params)

  # Round 7 T4.3: single-pass unified-correlation path
  if (!is.null(unified_corr_matrix) && (n_ad + n_ef) > 0) {
    all_params <- rbind(ad_params, ef_params)
    nm <- all_params$parameter
    M  <- diag(length(nm))
    rownames(M) <- colnames(M) <- nm
    common <- intersect(rownames(unified_corr_matrix), nm)
    if (length(common) >= 2) {
      M[common, common] <- unified_corr_matrix[common, common]
      M <- .repair_corr(M, "unified AD+coefficient correlation matrix")
      rownames(M) <- colnames(M) <- nm
      samp <- .iman_conover_sample(n_iter, all_params, M)
      out  <- as.data.frame(samp)
      # If the trend tab supplied pre-sampled coefficients, override that block
      if (!is.null(pre_sampled_coefficients) && n_ef > 0) {
        for (cn in intersect(colnames(pre_sampled_coefficients), names(out))) {
          out[[cn]] <- pre_sampled_coefficients[, cn]
        }
      }
      return(.clamp_physical_bounds(out))
    }
    # If unified matrix has < 2 overlapping params, fall through to two-pass
  }

  # Activity data: correlated or independent
  if (n_ad > 0) {
    use_ad_corr <- !is.null(corr_matrix) &&
                   nrow(corr_matrix) == n_ad && ncol(corr_matrix) == n_ad
    ad_samples <- if (use_ad_corr) {
      .iman_conover_sample(n_iter, ad_params, corr_matrix)
    } else {
      .indep_sample(n_iter, ad_params)
    }
  } else {
    ad_samples <- matrix(nrow = n_iter, ncol = 0)
  }

  # Emission factors: correlated, independent, or pre-sampled (R1.14 trend mode).
  # Same rank-correlation-preserving procedure as the AD block — the EF block no
  # longer has a special-case sampler.
  if (n_ef > 0) {
    if (!is.null(pre_sampled_coefficients) &&
        nrow(pre_sampled_coefficients) == n_iter &&
        all(ef_params$parameter %in% colnames(pre_sampled_coefficients))) {
      ef_samples <- pre_sampled_coefficients[, ef_params$parameter, drop = FALSE]
    } else {
      use_ef_corr <- !is.null(ef_corr_matrix) &&
                     nrow(ef_corr_matrix) == n_ef && ncol(ef_corr_matrix) == n_ef
      ef_samples <- if (use_ef_corr) {
        .iman_conover_sample(n_iter, ef_params, ef_corr_matrix)
      } else {
        .indep_sample(n_iter, ef_params)
      }
    }
  } else {
    ef_samples <- matrix(nrow = n_iter, ncol = 0)
  }

  .clamp_physical_bounds(as.data.frame(cbind(ad_samples, ef_samples)))
}

# Compute a named correlation matrix from a time series data frame.
# Only numeric columns are used. Returns a named matrix so expand_corr_matrix()
# can later slot it into the full AD parameter space.
#
# 2026-05 audit follow-up: switched from Pearson (default) to Spearman rank
# correlation, and added optional detrending. Spearman is the rank correlation
# the sampler reproduces exactly (per IPCC Vol.1 Ch.3 §3.2.3.2), and detrending
# separates shared long-run growth from year-to-year parameter co-movement
# (IPCC V1 Ch3 p.26 lists "time series techniques can be used to analyse or
# simulate temporal autocorrelation" — implying detrending first).
#
# `detrend` options:
#   "first_diff" (default) — take year-on-year differences before correlation
#   "linear"               — subtract a fitted linear trend
#   "none"                 — raw series (legacy behaviour)
compute_correlation_from_timeseries <- function(pop_data,
                                                 detrend = c("first_diff","linear","none")) {
  detrend <- match.arg(detrend)
  numeric_cols <- sapply(pop_data, is.numeric)
  pop_numeric  <- pop_data[, numeric_cols, drop = FALSE]
  if (ncol(pop_numeric) < 2)
    stop("Time series must contain at least 2 numeric columns.")
  series <- switch(detrend,
    none       = pop_numeric,
    first_diff = as.data.frame(lapply(pop_numeric, function(y) c(NA, diff(y)))),
    linear     = as.data.frame(lapply(pop_numeric, function(y) {
                   if (sum(!is.na(y)) < 3) return(y)
                   fit <- stats::lm(y ~ seq_along(y), na.action = stats::na.exclude)
                   as.numeric(stats::residuals(fit))
                 })))
  # Drop constant columns (sd = 0 → cor() warns and returns NaN).
  has_variance <- vapply(series, function(y) {
    y <- y[is.finite(y)]
    length(y) >= 2 && stats::sd(y) > 0
  }, logical(1))
  series <- series[, has_variance, drop = FALSE]
  if (ncol(series) < 2)
    stop("Time series must contain at least 2 non-constant numeric columns after detrending.")
  cor_matrix <- cor(series, use = "complete.obs", method = "spearman")
  as.matrix(Matrix::nearPD(cor_matrix, corr = TRUE)$mat)
}

# Andreas 2026-05 follow-up (C4 / C6 root cause): per-MMS uncertainty sampler.
# Manure_Management exposes lower_mcf / upper_mcf / distribution_mcf, and the
# same triplet for EF3, Frac_GasMS, Frac_LeachMS. Previously only the central
# values flowed into the calc; the uncertainty triplets were silently dropped.
# This helper builds an n_iter x n_MMS matrix sampled per MMS from its own
# distribution. If any MMS has missing lower/upper/dist for the target column,
# that MMS broadcasts the central value (no MC variability for that one).
sample_per_mms_param <- function(mms_rows, value_col, lower_col, upper_col,
                                  dist_col, n_iter, default_dist = "pert") {
  if (is.null(mms_rows) || nrow(mms_rows) == 0) return(NULL)
  mms_names <- as.character(mms_rows$mms_type)
  out <- matrix(NA_real_, nrow = n_iter, ncol = length(mms_names))
  colnames(out) <- mms_names
  for (j in seq_along(mms_names)) {
    mu <- suppressWarnings(as.numeric(mms_rows[[value_col]][j]))
    lo <- if (lower_col %in% names(mms_rows))
      suppressWarnings(as.numeric(mms_rows[[lower_col]][j])) else NA_real_
    hi <- if (upper_col %in% names(mms_rows))
      suppressWarnings(as.numeric(mms_rows[[upper_col]][j])) else NA_real_
    dist <- if (dist_col %in% names(mms_rows))
      as.character(mms_rows[[dist_col]][j]) else NA_character_
    if (is.na(dist) || !nzchar(dist)) dist <- default_dist
    if (is.na(mu)) {
      out[, j] <- 0  # caller fills with default downstream
      next
    }
    if (is.na(lo) || is.na(hi) || isTRUE(all.equal(lo, hi)) || lo >= hi) {
      out[, j] <- mu                      # no uncertainty → broadcast central value
    } else {
      out[, j] <- sample_distribution(n_iter, dist, mu, lo, hi)
    }
  }
  out
}

# Dirichlet MMS-allocation sampling (introduced in Round 7 T4.21) was removed
# in the Andreas 2026-05 follow-up: it is not explicitly cited in IPCC 2006 /
# 2019 Refinement guidance, and the diagnostic run-through proved it leaves
# the mean of every emission source unchanged (Dirichlet preserves marginal
# means when per-MMS coefficients are constant). MMS% is now deterministic,
# matching the IPCC Inventory Software's behaviour. If the feature ever needs
# to come back, the previous `sample_dirichlet_simplex` implementation lives
# in git history at commit 4191b73.

# Structural-defaults preset correlation matrix (expert-elicited, NOT IPCC-published).
# Renamed 2026-05 from "IPCC-guidance preset" after the statistical audit: IPCC V1
# Ch3 / V4 Ch10 publish no numerical correlation values for any livestock parameter.
# These pairs reflect documented biological / statistical relationships from the
# IPCC equations and the published livestock literature.
#
# Convention: the `rho` values below are Spearman rank correlations, the target
# preserved by the sampler in mc_simulation.R per IPCC Vol.1 Ch.3 §3.2.3.2.
#
# Pure function — no rv dependency. Returns a named partial matrix containing
# only the pairs whose endpoints exist in `all_param_names`. Pairs missing from
# the spec are silently dropped.
#
# Each entry carries a `source` field surfaced in the UI tooltip so users can
# trace where the value came from.
#
# Revisions:
#   - 2026-05: dropped the previous N <-> BW = 0.30 pair (N is sampled as a
#     scalar broadcast, so any N-X correlation is inert at MC time).
#   - 2026-06 (Andreas livestock-science review): lowered BW-MW from 0.85 to
#     0.50 (BW is typically a census average while MW is a breed reference
#     constant, so they're not from the same survey); dropped Milk-pct_pregnant
#     (sign is ambiguous: negative per-cow genetic correlation vs positive
#     per-herd management correlation); dropped Cfi-Ca (independent inputs in
#     IPCC Eq 10.3/10.4, not jointly estimated -- continues the May 2026
#     trajectory that already lowered this from 0.60 -> 0.30); added two
#     cross-group biological linkages Andreas flagged as real (Milk-BW and
#     Milk-DE, both +0.30).
PRESET_PAIRS <- list(
  # 2026-06: lowered from 0.85 to 0.50. In practice MW is taken from a breed
  # reference table (essentially constant per breed) while BW comes from the
  # national livestock census (varies with diet/condition). The high 0.85 only
  # holds if both come from the same animal-condition survey. 0.50 covers the
  # typical mixed-source case; users with same-source data can override via
  # the manual matrix mode.
  list(a = "BW",   b = "MW",          rho =  0.50,
       source = "Growth-curve relation (Brody 1945) reused in IPCC Eq 10.3. Set to 0.5 rather than 0.85: 0.85 assumes BW and MW come from the same survey; in practice MW is usually a breed-reference constant while BW is from the national livestock census, so the cross-source correlation is closer to 0.5."),
  # 2026-06: kept at 0.40 but the source comment now flags the sign ambiguity
  # so reviewers don't read it as settled.
  list(a = "BW",   b = "WG",          rho =  0.40,
       source = "IPCC Eq 10.6 (NEg scales with BW^0.75 x WG^1.097); joint regression estimation correlation, NRC 2001. Note the sign is system-dependent: heavy growing animals gain slower (negative), while well-fed adults are both heavier and gain more (positive). +0.40 reflects the well-fed-adult case typical of dairy/beef finishing systems; growing-young-stock systems may warrant a negative override."),
  list(a = "Milk", b = "Fat",         rho = -0.30,
       source = "Milk dilution effect, dairy genetics literature (Wilmink 1987; VandeHaar 1998). Within-herd literature -0.20 to -0.40; 0.30 is the midpoint."),
  # 2026-06 ADDED (Andreas review): Milk-BW. High-producing cows are larger;
  # Holstein vs Jersey illustrate the linkage (~650 kg vs ~450 kg, ~30 vs ~20
  # kg milk/day). This is one of the "real biological linkages cutting across
  # the old population/intake groups" Andreas highlighted.
  list(a = "Milk", b = "BW",          rho =  0.30,
       source = "High-producing dairy breeds are physically larger (Holstein ~650 kg ~30 kg milk/d vs Jersey ~450 kg ~20 kg milk/d). NRC Dairy 2001; Stallings & Knowlton 2013. Included as a real cross-group biological linkage."),
  # 2026-06 ADDED (Andreas review): Milk-DE. Higher feed digestibility lifts
  # nutrient availability and so milk yield, especially in concentrate-fed
  # dairy systems. Andreas' second flagged linkage.
  list(a = "Milk", b = "DE",          rho =  0.30,
       source = "Higher digestibility → more nutrient availability → higher milk yield, especially in concentrate-fed dairy. NRC Dairy 2001 Ch.2. Included as a real cross-group biological linkage."),
  list(a = "DE",   b = "CP",          rho =  0.50,
       source = "Forage-quality co-variation across feed types (NRC 2001; INRA; Feedipedia). High-quality forages have both high DE and high CP; cross-feedstuff correlations 0.4-0.7."),
  # 2026-05 audit re-review: strengthened from -0.40 to -0.50. IPCC 2019
  # Refinement Eq 10.21 makes Ym an explicit decreasing function of DE
  # (with NDF, EE). Observational meta-analyses (Niu et al. 2018 Global
  # Change Biology; Hristov et al. 2013) show a stronger negative cross-
  # diet correlation than -0.40, closer to the equation slope.
  list(a = "DE",   b = "Ym",          rho = -0.50,
       source = "IPCC 2019 Refinement Eq 10.21 (Ym decreases with DE) + meta-analysis (Niu et al. 2018 GCB; Hristov et al. 2013). Set to -0.50 rather than -0.40 to align with the observed cross-diet slope.")
  # 2026-06: Milk-pct_pregnant was dropped. Sign is ambiguous: per-cow genetic
  # studies show high milk yield <-> reduced fertility (negative); per-herd
  # management gives the opposite (positive: well-run dairies have both high
  # milk and high pregnancy rates). Without committing to one frame, the pair
  # added noise rather than signal.
  #
  # 2026-06: Cfi-Ca was dropped. Cfi and Ca are independent inputs in IPCC Eq
  # 10.3 / 10.4 (not jointly estimated), so the "both energy constants"
  # linkage was a soft hand-wave. The May 2026 audit had already lowered this
  # from 0.60 to 0.30 for the same reason; June 2026 continues to 0.
)

# Legacy alias table — accept Round-3 names so the helper finds pairs even if
# the user uploaded a pre-rename template.
.PRESET_ALIASES <- list(
  DE_pct = "DE", Ym_pct = "Ym", CP_pct = "CP",
  cattle_pop = "N", live_weight = "BW", mature_weight = "MW",
  weight_gain = "WG", milk_yield = "Milk", milk_fat = "Fat"
)

build_ipcc_preset_corr <- function(all_param_names) {
  if (length(all_param_names) < 2) return(NULL)
  # 2026-06: deduplicate input names first. Multi-sub-category uploads (e.g.
  # ZIM with 5 sub-categories x 22 params = 110 rows) used to produce a
  # 110 x 110 matrix where only the first sub-category had its 7 pairs
  # populated. The downstream per-system slicing in expand_corr_matrix()
  # worked correctly because intersect() deduplicates, but the heatmap (which
  # rendered the raw matrix) appeared almost entirely empty -- 7 coloured
  # cells lost among 12 100. Building on unique names produces a tight 22 x 22
  # matrix with all 7 pairs visible and lifts cleanly to any sub-category.
  unique_names <- unique(all_param_names)
  if (length(unique_names) < 2) return(NULL)

  # Map any legacy aliases to the canonical IPCC name for matching
  resolve <- function(nm) {
    a <- .PRESET_ALIASES[[nm]]
    if (!is.null(a)) a else nm
  }
  canonical <- vapply(unique_names, resolve, character(1))

  m <- diag(length(unique_names))
  rownames(m) <- colnames(m) <- unique_names

  applied <- 0L
  for (p in PRESET_PAIRS) {
    i <- which(canonical == p$a)
    j <- which(canonical == p$b)
    if (length(i) >= 1 && length(j) >= 1) {
      m[i[1], j[1]] <- p$rho
      m[j[1], i[1]] <- p$rho
      applied <- applied + 1L
    }
  }
  if (applied == 0L) return(NULL)
  .repair_corr(m, "structural-defaults preset correlation matrix")
}

# Expand a partial (named) correlation matrix to the full set of AD parameters.
# Parameters present in partial_corr get their pairwise correlations copied in;
# parameters absent are treated as uncorrelated with everything else (identity rows/cols).
# Returns NULL if fewer than 2 parameters overlap (correlation would be meaningless).
expand_corr_matrix <- function(partial_corr, all_param_names) {
  n      <- length(all_param_names)
  full   <- diag(n)
  rownames(full) <- colnames(full) <- all_param_names

  common <- intersect(rownames(partial_corr), all_param_names)
  if (length(common) < 2) return(NULL)

  full[common, common] <- partial_corr[common, common]
  .repair_corr(full, "expanded partial correlation matrix")
}
