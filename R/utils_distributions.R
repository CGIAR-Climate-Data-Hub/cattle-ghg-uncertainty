# Distribution Sampling Utilities
# Supports: normal, lognormal, beta, triangular, PERT, uniform, constant
#
# NOTE on lognormal interpretation (verified empirically 2026-05-18):
#   For lognormal, `mean_val` is treated as the MEDIAN of the distribution
#   (mu_log = log(mean_val)), not the arithmetic mean. This matches IPCC
#   GPG 2000 Annex 1 / Penman et al. 2000 / Monni et al. 2007 convention
#   for skewed emission factor parameters, where the "central value" is
#   the geometric mean / median rather than the arithmetic mean.
#   Consequence: the realised arithmetic mean of the MC samples will be
#   `mean_val × exp(sd_log² / 2)`, which is above mean_val by ≈10-25%
#   for the IPCC asymmetric defaults (EF3_PRP, EF4, EF5, Frac_LEACH_H).
#   Users who want mean_val to be the arithmetic mean should pick a
#   different distribution (normal, beta, or pert) instead of lognormal.

sample_distribution <- function(n, type, mean_val, lower, upper) {
  type <- tolower(type)

  # Constant distribution short-circuit: only `mean_val` matters, lower/upper
  # are irrelevant. Without this special case, the NA-bounds guard below
  # would poison every biological-zero row (Milk=0 for males, hours=0 for
  # non-oxen, N placeholders) with NA samples — these typically have NA
  # bounds because there's no uncertainty to express. The downstream
  # emission calc would then propagate NaN into total_co2e and crash the
  # quantile() convergence check at the end of the simulation.
  if (type %in% c("constant", "const")) {
    if (is.na(mean_val)) return(rep(NA_real_, n))
    return(rep(mean_val, n))
  }

  # Andreas 2026-05-26 follow-up: short-circuit when any of mean/lower/upper
  # is NA — this happens when a user uploads a template with a blank yellow
  # cell. Passing NA to mc2d::rpert / mc2d::rtriang / rnorm trips
  # "missing value where TRUE/FALSE needed" deep inside an `if (any(check))`
  # in mc2d that doesn't understand NA inputs. Returning NA samples here
  # lets the simulation finish and propagates the NA into the per-iteration
  # results so the user sees missing values in the QA/QC tab rather than a
  # cryptic crash. The pre-run NA-mean check in the simulation observer
  # (R/app_server.R) is the canonical block; this is defence-in-depth.
  if (is.na(mean_val) || is.na(lower) || is.na(upper)) {
    return(rep(NA_real_, n))
  }

  switch(type,
    "normal" = , "posnorm" = {
      sd_est <- (upper - lower) / (2 * 1.96)
      samples <- rnorm(n, mean = mean_val, sd = sd_est)
      if (type == "posnorm") samples <- pmax(samples, 0)
      samples
    },
    "lognormal" = {
      mu_log <- log(mean_val)
      sd_log <- (log(upper) - log(lower)) / (2 * 1.96)
      rlnorm(n, meanlog = mu_log, sdlog = sd_log)
    },
    "beta" = {
      mu <- (mean_val - lower) / (upper - lower)
      var_est <- ((upper - lower) / (2 * 1.96 * (upper - lower)))^2
      var_est <- min(var_est, mu * (1 - mu) * 0.99)
      alpha <- max(mu * (mu * (1 - mu) / var_est - 1), 0.1)
      beta_param <- max((1 - mu) * (mu * (1 - mu) / var_est - 1), 0.1)
      lower + (upper - lower) * rbeta(n, alpha, beta_param)
    },
    "triangular" = {
      mc2d::rtriang(n, min = lower, mode = mean_val, max = upper)
    },
    "pert" = {
      mc2d::rpert(n, min = lower, mode = mean_val, max = upper, shape = 4)
    },
    "uniform" = {
      runif(n, min = lower, max = upper)
    },
    "constant" = , "const" = {
      rep(mean_val, n)
    },
    "tnorm_0_1" = {
      sd_est <- (upper - lower) / (2 * 1.96)
      samples <- rnorm(n, mean = mean_val, sd = sd_est)
      pmin(pmax(samples, 0), 1)
    },
    stop(paste("Unknown distribution type:", type))
  )
}

# Compute lower/upper from mean and uncertainty percentage
calc_bounds <- function(mean_val, uncertainty_pct) {
  half_range <- mean_val * (uncertainty_pct / 100)
  list(lower = mean_val - half_range, upper = mean_val + half_range)
}
