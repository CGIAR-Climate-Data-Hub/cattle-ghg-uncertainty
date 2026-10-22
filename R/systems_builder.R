# Systems builder: one place that turns a parameter sheet plus a manure sheet
# into the per-group list run_inventory_simulation() consumes.
#
# 2026-10-16. This code was the body of the Run Simulation observer in
# app_server.R. It was lifted out so that trend mode runs each year through
# exactly the same build as single-year mode. Until then trend mode passed the
# whole parameter sheet as ONE system, and run_mc_simulation() read one row per
# parameter name, so a 32-group inventory came out as one group: on the Zambia
# file 196,566 t against 9,240,534 t from the single-year path. See
# knowledge/22-trend-capacity.md.
#
# Nothing here reads Shiny state. Every former `input$` or `rv$` reference is an
# argument, and what the observer used to assign to rv$shared_summary is
# returned instead.

# Group key: cattle_type || aggregation_level || sub_category. Falls back to a
# system/subsystem pair, then to a single group, so one-group files and the
# audit's fixtures keep working.
make_group_key <- function(df) {
  if (all(c("cattle_type", "aggregation_level") %in% names(df))) {
    sub <- if ("sub_category" %in% names(df)) df$sub_category else rep("", nrow(df))
    paste(df$cattle_type, df$aggregation_level, sub, sep = "||")
  } else if (all(c("system", "subsystem") %in% names(df))) {
    paste(df$system, df$subsystem, sep = "||")
  } else {
    rep("group1", nrow(df))
  }
}

# Build the per-group systems list.
#
#   specs              parameter sheet, every group, QA repairs already applied
#   manure             Manure_Management sheet or NULL
#   n_iter             iterations; also the row count of any sampled matrix
#   seed               seed for the shared coefficient draws
#   crossgroup         "shared" draws a coefficient once for every group that
#                      carries the same estimate; "independent" lets each group
#                      draw its own (the pre-2026-09 behaviour)
#   corr_matrix        the ACTIVE activity-data correlation matrix, already
#                      resolved by the caller, or NULL for none
#   sg_to_mm           group key -> manure group key, from
#                      resolve_sub_category_matches(); empty list = literal match
#   pre_sampled_blocks optional named list, group key -> n_iter x k coefficient
#                      matrix, which REPLACES the shared draws built here. Trend
#                      mode passes the same blocks every year so coefficients
#                      are drawn once per run, which is the IPCC year
#                      correlation. When NULL, shared draws are built here.
#
# Returns list(systems, shared, group_key, sys_groups).
build_systems_data <- function(specs, manure = NULL, n_iter, seed = NULL,
                               crossgroup = c("shared", "independent"),
                               corr_matrix = NULL, sg_to_mm = list(),
                               pre_sampled_blocks = NULL) {
  crossgroup <- match.arg(crossgroup)
  n_iter <- as.integer(n_iter)
  group_key  <- make_group_key(specs)
  sys_groups <- unique(group_key)
  systems_data <- list()

  # Used when a group has no usable Manure_Management row. Shared with
  # trend_tab.R, scripts/audit.R and scripts/example_verify.R, which
  # all used to keep their own retyped copy of these numbers.
  .mms_fb <- default_mms_fallback()
  default_mms_fracs <- .mms_fb$fractions
  default_mcf_vals  <- .mms_fb$mcf
  default_ef3_vals  <- .mms_fb$ef3

  # Cross-group coefficient sharing (2026-09). Drawn ONCE, before the
  # group loop, so that groups holding the same estimate for a
  # coefficient move together instead of averaging each other out.
  # Without this the reported MoE falls as 1/sqrt(number of groups),
  # i.e. the headline figure depends on how finely the inventory was
  # disaggregated rather than on the data. See the block comment above
  # build_shared_coefficient_draws() in R/mc_sampling.R.
  #
  # The per-system seed set inside run_inventory_simulation() is
  # unaffected: it governs only the columns each system still draws for
  # itself.
  shared_draws <- if (!is.null(pre_sampled_blocks)) {
    list(blocks = pre_sampled_blocks, summary = NULL)
  } else if (identical(crossgroup, "shared")) {
    build_shared_coefficient_draws(specs, n_iter, seed = seed, group_keys = group_key)
  } else list(blocks = list(), summary = NULL)

  for (sg in sys_groups) {
    sys_specs <- specs[group_key == sg, ]

    # Round 7 R1.13: also extract per-MMS Frac_GasMS / Frac_LeachMS
    # from the manure sheet if the columns are present. NA -> fall back
    # to mms_frac_defaults_2019() inside calc_indirect_n2o_mm().
    frac_gas_vals   <- NULL
    frac_leach_vals <- NULL
    # Andreas 2026-05 follow-up (C4 / C6): per-MMS uncertainty matrices
    # populated below if the manure sheet has lower/upper/dist cols.
    # Andreas 28/5/26 #4: fraction_samples is the new per-MMS sampled
    # allocation matrix (n_iter x n_mms, rows renormalised to sum to 1).
    mcf_samples <- ef3_samples <- fg_samples <- fl_samples <-
      fraction_samples <- NULL

    if (!is.null(manure) && nrow(manure) > 0 &&
        all(c("mms_type", "fraction_pct", "MCF_pct", "EF3") %in% names(manure))) {
      manure_key <- make_group_key(manure)
      # Use the auto-matched MM key from resolve_sub_category_matches
      # (falls through to the literal sg when no remap was needed).
      sg_lookup  <- if (sg %in% names(sg_to_mm)) sg_to_mm[[sg]] else sg
      mms_rows   <- manure[manure_key == sg_lookup, ]
      if (nrow(mms_rows) > 0) {
        # Defensive coercion in case Excel stored these as text
        fp_num   <- suppressWarnings(as.numeric(mms_rows$fraction_pct))
        mcf_num  <- suppressWarnings(as.numeric(mms_rows$MCF_pct))
        ef3_num  <- suppressWarnings(as.numeric(mms_rows$EF3))
        mms_fracs <- setNames(fp_num / 100,  mms_rows$mms_type)
        mcf_vals  <- setNames(mcf_num / 100, mms_rows$mms_type)
        ef3_vals  <- setNames(ef3_num,       mms_rows$mms_type)
        # Drop any rows that didn't coerce (NA fraction -> useless)
        mms_fracs <- mms_fracs[!is.na(mms_fracs)]
        mcf_vals  <- mcf_vals[names(mms_fracs)]
        ef3_vals  <- ef3_vals[names(mms_fracs)]
        # Replace any leftover NAs in MCF/EF3 with THAT SYSTEM's own
        # default rather than crashing. This used to substitute 0.015
        # and 0.005 for every system alike, which are pasture's
        # temperate MCF and the superseded solid-storage EF3: a blank
        # MCF on an uncovered lagoon became 1.5% where Table 10.17
        # gives 77%.
        mcf_vals <- fill_mms_blanks(mcf_vals, "mcf")
        ef3_vals <- fill_mms_blanks(ef3_vals, "ef3")

        # Round 7 R1.13: per-MMS Frac_GasMS / Frac_LeachMS columns.
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

        # Andreas 2026-05 follow-up (C4 / C6): sample per-MMS MCF /
        # EF3 / Frac_GasMS / Frac_LeachMS uncertainty from the
        # lower / upper / distribution columns on the manure sheet.
        # Was previously dropped: only central values were used as
        # deterministic per-iteration constants, so MCF never showed
        # up in the MM-CH4 tornado despite huge bounds in real data.
        # Pre-scale percentage cols to fractions so the sampler works
        # in the same units the downstream calc expects.
        mr_mcf_scaled <- mms_rows
        for (col in c("MCF_pct", "lower_mcf", "upper_mcf")) {
          if (col %in% names(mr_mcf_scaled))
            mr_mcf_scaled[[col]] <- suppressWarnings(
              as.numeric(mr_mcf_scaled[[col]])) / 100
        }
        mr_fg_scaled <- mms_rows
        for (col in c("Frac_GasMS_pct", "lower_frac_gas", "upper_frac_gas")) {
          if (col %in% names(mr_fg_scaled))
            mr_fg_scaled[[col]] <- suppressWarnings(
              as.numeric(mr_fg_scaled[[col]])) / 100
        }
        mr_fl_scaled <- mms_rows
        for (col in c("Frac_LeachMS_pct", "lower_frac_leach", "upper_frac_leach")) {
          if (col %in% names(mr_fl_scaled))
            mr_fl_scaled[[col]] <- suppressWarnings(
              as.numeric(mr_fl_scaled[[col]])) / 100
        }
        mcf_samples <- sample_per_mms_param(
          mr_mcf_scaled, "MCF_pct", "lower_mcf", "upper_mcf",
          "distribution_mcf", n_iter, default_dist = "pert")
        ef3_samples <- sample_per_mms_param(
          mms_rows, "EF3", "lower_ef3", "upper_ef3",
          "distribution_ef3", n_iter, default_dist = "pert")
        fg_samples <- sample_per_mms_param(
          mr_fg_scaled, "Frac_GasMS_pct", "lower_frac_gas",
          "upper_frac_gas", "distribution_frac_gas",
          n_iter, default_dist = "pert")
        fl_samples <- sample_per_mms_param(
          mr_fl_scaled, "Frac_LeachMS_pct", "lower_frac_leach",
          "upper_frac_leach", "distribution_frac_leach",
          n_iter, default_dist = "pert")

        # Andreas 28/5/26 #4: sample fraction_pct per-MMS so MMS
        # allocation can show up in the tornado / rank-correlation.
        # If lower_fraction / upper_fraction are absent or equal to
        # the central value, the sampler degenerates to a constant
        # row (matching the prior deterministic behaviour). Each
        # iteration row is then divided by 100 and renormalised so
        # it sums to 1: keeps the values on the simplex (Option A
        # from the design Q: independent sample + renormalise).
        if (any(c("lower_fraction", "upper_fraction",
                   "distribution_fraction") %in% names(mms_rows))) {
          fraction_samples <- sample_per_mms_param(
            mms_rows, "fraction_pct", "lower_fraction",
            "upper_fraction", "distribution_fraction",
            n_iter, default_dist = "pert")
          if (!is.null(fraction_samples)) {
            # `pmax(0, x)` strips the matrix dim attribute; clamp
            # in place to keep `fraction_samples` a matrix.
            fraction_samples[fraction_samples < 0] <- 0
            fraction_samples <- fraction_samples / 100
            rs <- rowSums(fraction_samples)
            rs[rs <= 0] <- 1  # safeguard against degenerate rows
            fraction_samples <- fraction_samples / rs
          }
        }

        # Reorder columns to match mms_fracs ordering.
        ord_names <- names(mms_fracs)
        if (!is.null(mcf_samples)) mcf_samples <- mcf_samples[, ord_names, drop = FALSE]
        if (!is.null(ef3_samples)) ef3_samples <- ef3_samples[, ord_names, drop = FALSE]
        if (!is.null(fg_samples))  fg_samples  <- fg_samples[, ord_names, drop = FALSE]
        if (!is.null(fl_samples))  fl_samples  <- fl_samples[, ord_names, drop = FALSE]
        if (!is.null(fraction_samples))
          fraction_samples <- fraction_samples[, ord_names, drop = FALSE]
        # Final guard: if all MMS rows were unparsable, use defaults
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

    # R1.1 / Round 7 T4.3: build a UNIFIED correlation matrix over both
    # AD and coefficient parameters. The preset matrix and the time-series
    # matrix can both span both blocks (post-Round-7), so we expand the
    # user's matrix to the full (AD + coefficient) parameter list. This
    # supersedes the prior two-pass `corr_matrix` / `ef_corr_matrix` split,
    # though both inputs are still passed downstream for back-compat.
    ad_names   <- sys_specs$parameter[sys_specs$param_type == "activity_data"]
    coef_names <- sys_specs$parameter[sys_specs$param_type == "coefficient"]
    all_names  <- c(ad_names, coef_names)

    unified_corr <- if (!is.null(corr_matrix)) {
      expand_corr_matrix(corr_matrix, all_names)
    } else NULL

    ts_coef_corr <- if (!is.null(corr_matrix)) {
      expand_corr_matrix(corr_matrix, coef_names)
    } else NULL

    # AD block has only cattle_pop: within-block correlation is meaningless.
    corr <- NULL

    # The activity-data correlation modes are the only remaining
    # source of a coefficient-block matrix; block-structured EF
    # correlation was removed on 2026-10-15.
    ef_corr <- ts_coef_corr

    # Andreas 2026-05 follow-up: Dirichlet MMS-allocation sampling
    # removed (not in IPCC guidance; MMS% is now deterministic).
    # Per-MMS uncertainty matrices (C4 / C6 fix) attached below.
    systems_data[[sg]] <- list(
      param_specs = sys_specs, corr_matrix = corr, ef_corr_matrix = ef_corr,
      unified_corr_matrix = unified_corr,
      mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
      frac_gas_values = frac_gas_vals, frac_leach_values = frac_leach_vals,
      mcf_samples = mcf_samples, ef3_samples = ef3_samples,
      frac_gas_samples = fg_samples, frac_leach_samples = fl_samples,
      # Andreas 28/5/26 #4: per-iteration MMS allocation samples
      mms_fraction_samples = fraction_samples,
      # Shared coefficient draws for this group (NULL when the group
      # shares nothing, or when the user chose independent groups).
      pre_sampled_coefficients = shared_draws$blocks[[sg]]
    )
  }

  list(systems = systems_data, shared = shared_draws,
       group_key = group_key, sys_groups = sys_groups)
}

# Every coefficient of every group drawn once, as per-group blocks.
#
# Used by trend mode for year_corr = "full": the same blocks are handed to
# build_systems_data() for every year, so a coefficient's error is identical
# in 2010 and 2022 and cancels in the difference, which is the IPCC default
# (Vol. 1 Ch. 3 §3.2.2.4). Coefficients that several groups hold as the same
# estimate share one draw across those groups when crossgroup = "shared",
# exactly as build_shared_coefficient_draws() does within a year; the rest
# are drawn independently per group. Activity data is never pre-sampled.
#
# Memory is one n_iter vector per distinct draw. Groups whose coefficient
# rows all resolve to the same draws share one matrix object.
build_full_coefficient_blocks <- function(specs, n_iter, seed = NULL,
                                          crossgroup = c("shared", "independent")) {
  crossgroup <- match.arg(crossgroup)
  n_iter <- as.integer(n_iter)
  group_key <- make_group_key(specs)
  pt <- if ("param_type" %in% names(specs)) specs$param_type else NA
  pt[is.na(pt)] <- "coefficient"
  is_coef <- pt == "coefficient"
  if (!any(is_coef)) return(list())

  shared <- if (identical(crossgroup, "shared"))
    detect_shared_parameters(specs, group_key) else list()

  # Draw id per coefficient row: the partition id if the row is shared,
  # otherwise its own (group, parameter).
  draw_id <- rep(NA_character_, nrow(specs))
  for (i in which(is_coef)) {
    p <- specs$parameter[i]; g <- group_key[i]
    id <- NULL
    if (!is.null(shared[[p]])) {
      for (pi in seq_along(shared[[p]])) {
        if (g %in% shared[[p]][[pi]]) { id <- paste0(p, "#", pi); break }
      }
    }
    if (is.null(id)) id <- paste0(p, "@", g)
    draw_id[i] <- id
  }

  if (!is.null(seed)) set.seed(seed)
  draws <- list()
  # Deterministic order: first appearance in the sheet.
  for (i in which(is_coef)) {
    id <- draw_id[i]
    if (!is.null(draws[[id]])) next
    draws[[id]] <- sample_distribution(n_iter, specs$distribution[i],
                                       specs$mean[i], specs$lower[i], specs$upper[i])
  }

  per_group <- split(seq_len(nrow(specs))[is_coef], group_key[is_coef])
  per_group <- lapply(per_group, function(rows) {
    ids <- draw_id[rows]; ps <- specs$parameter[rows]
    # one column per parameter; a repeated row keeps its last occurrence,
    # matching how the per-group sampler treats a repeated row
    keep <- !duplicated(ps, fromLast = TRUE)
    list(ids = ids[keep], params = ps[keep])
  })
  sig  <- vapply(per_group, function(x) paste(x$ids, collapse = "\r"), character(1))
  mats <- list()
  for (i in which(!duplicated(sig))) {
    x <- per_group[[i]]
    m <- do.call(cbind, draws[x$ids])
    colnames(m) <- x$params
    mats[[sig[i]]] <- m
  }
  blocks <- unname(lapply(sig, function(s) mats[[s]]))
  names(blocks) <- names(per_group)
  blocks
}

# Year-to-year correlated coefficient blocks for year_corr = "partial".
#
# Returns a closure; each call yields the per-group blocks for the next year.
# The year-to-year link is a Gaussian AR(1) on a latent z per draw, with the
# marginal imposed by rank: z_t = rho z_{t-1} + sqrt(1 - rho^2) e_t, and the
# year's marginal draw is reordered by rank(z_t). Lag-k Spearman is then
# (6/pi) asin(rho^k / 2), about 0.68 at lag 1 for rho = 0.7.
#
# 2026-10-16: this replaces the earlier .ar1_samples_one_coef(), which
# reordered all years jointly with mc2d::cornode and therefore had to hold
# n_iter x n_years per coefficient ROW. On 32 groups and 35 years that is
# over 2 GB. The sequential form keeps one n_iter vector of state per
# distinct draw, whichever the number of years.
make_partial_block_generator <- function(specs, n_iter, seed = NULL, rho = 0.7,
                                         crossgroup = c("shared", "independent")) {
  crossgroup <- match.arg(crossgroup)
  n_iter <- as.integer(n_iter)
  group_key <- make_group_key(specs)
  pt <- if ("param_type" %in% names(specs)) specs$param_type else NA
  pt[is.na(pt)] <- "coefficient"
  is_coef <- pt == "coefficient"
  shared <- if (identical(crossgroup, "shared"))
    detect_shared_parameters(specs, group_key) else list()

  draw_id <- rep(NA_character_, nrow(specs))
  for (i in which(is_coef)) {
    p <- specs$parameter[i]; g <- group_key[i]; id <- NULL
    if (!is.null(shared[[p]])) {
      for (pi in seq_along(shared[[p]])) {
        if (g %in% shared[[p]][[pi]]) { id <- paste0(p, "#", pi); break }
      }
    }
    if (is.null(id)) id <- paste0(p, "@", g)
    draw_id[i] <- id
  }
  ids   <- unique(draw_id[is_coef])
  spec_row <- vapply(ids, function(id) which(draw_id == id)[1], integer(1))
  per_group <- split(seq_len(nrow(specs))[is_coef], group_key[is_coef])
  per_group <- lapply(per_group, function(rows) {
    pids <- draw_id[rows]; ps <- specs$parameter[rows]
    keep <- !duplicated(ps, fromLast = TRUE)
    list(ids = pids[keep], params = ps[keep])
  })

  st <- new.env(parent = emptyenv())
  st$z <- NULL
  st$year <- 0L
  st$rng <- seed

  function() {
    st$year <- st$year + 1L
    if (!is.null(st$rng)) set.seed(st$rng + st$year)
    z_new <- matrix(stats::rnorm(n_iter * length(ids)), nrow = n_iter)
    st$z <- if (is.null(st$z)) z_new else rho * st$z + sqrt(1 - rho^2) * z_new
    draws <- list()
    for (k in seq_along(ids)) {
      i <- spec_row[k]
      m <- sort(sample_distribution(n_iter, specs$distribution[i],
                                    specs$mean[i], specs$lower[i], specs$upper[i]))
      draws[[ids[k]]] <- m[rank(st$z[, k], ties.method = "first")]
    }
    sig  <- vapply(per_group, function(x) paste(x$ids, collapse = "\r"), character(1))
    mats <- list()
    for (i in which(!duplicated(sig))) {
      x <- per_group[[i]]
      mm <- do.call(cbind, draws[x$ids]); colnames(mm) <- x$params
      mats[[sig[i]]] <- mm
    }
    blocks <- unname(lapply(sig, function(s) mats[[s]]))
    names(blocks) <- names(per_group)
    blocks
  }
}

# ---------------------------------------------------------------------------
# AD/EF split (IPCC Table 3.3 columns E and F). Lifted verbatim from the
# run_sim observer on 2026-10-22 so trend_decompose_year() runs the same
# two fixed-parameter simulations as single-year. fix_type = "coefficient"
# holds every coefficient at its mean (the AD-only run); "activity_data"
# holds the activity data at its mean (the EF-only run).
fix_params_for_decomposition <- function(sd, fix_type) {
  ps <- sd$param_specs
  ps$param_type[is.na(ps$param_type)] <- "coefficient"
  rows <- ps$param_type == fix_type
  ps$distribution[rows] <- "constant"
  ps$lower[rows] <- ps$mean[rows]
  ps$upper[rows] <- ps$mean[rows]
  sd$param_specs <- ps
  if (fix_type == "coefficient") {
    sd$ef_corr_matrix <- NULL
    # Andreas 28/5/26 #9: per-MMS sample matrices (mcf_samples,
    # ef3_samples, frac_gas_samples, frac_leach_samples) and the
    # MMS-allocation sample matrix (mms_fraction_samples) all
    # carry coefficient-side variance: they were leaking
    # iteration-to-iteration MCF / EF3 / Frac variation into the
    # AD-only run, so AD-only CV differed across emission sources
    # even though N was the only AD parameter. Null them here so
    # the AD-only run sees deterministic per-MMS values
    # (mcf_values / ef3_values / frac_gas_values / frac_leach_values
    # / mms_fractions are still respected: they are the central
    # values used when the matrices are NULL).
    sd$mcf_samples           <- NULL
    sd$ef3_samples           <- NULL
    sd$frac_gas_samples      <- NULL
    sd$frac_leach_samples    <- NULL
    sd$mms_fraction_samples  <- NULL
    # Cross-group shared coefficient draws are pure coefficient
    # variance, exactly like the per-MMS matrices above. Leaving
    # them in the AD-only run would leak that variance into the
    # activity-data column of IPCC Table 3.3, the same class of
    # bug as the 2026-05 per-MMS leak.
    sd$pre_sampled_coefficients <- NULL
  }
  if (fix_type == "activity_data") {
    sd$corr_matrix         <- NULL
    sd$unified_corr_matrix <- NULL
    # Per-MMS sample matrices STAY active in the EF-only run -
    # they are coefficient-side variance and are exactly what
    # the EF-only run is meant to expose.
  }
  sd
}
