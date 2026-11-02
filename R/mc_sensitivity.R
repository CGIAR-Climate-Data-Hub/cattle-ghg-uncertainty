# Sensitivity Analysis
# Standardised regression coefficients (SRC).
#
# 2026-10-29: the partial rank correlation (PRCC) was removed. It needed one
# regression per parameter, so it was skipped above 40 columns, which on any
# multi-group inventory meant every tornado carried a note saying so; the two
# methods agreed on the top drivers wherever both ran. SRC is the one method.

# 2026-10-29: SRC is fitted directly on a numeric matrix. It used scale() on
# the data frame and lm() on a formula, which between them held about six
# copies of the design matrix: on Zambia (4,000 rows x 1,250 columns, 38 MB)
# that added about 300 MB at the memory peak of a run, and with the
# no-correlation comparison the session was dropped. The arithmetic is the
# same as before, step for step, and the result is identical to the bit
# (checked on every emission source of the Zambia run, with and without
# correlations, and on the audit's examples):
#   - each column is standardised as scale() does it: colMeans(), then the
#     root mean square of the centred column with n - 1, then centred / that;
#   - the fit is the QR decomposition lm() calls (.lm.fit, tolerance 1e-7)
#     on the same matrix with the intercept column first;
#   - standard errors and p-values follow summary.lm(): pivoted columns, the
#     inverse of R from chol2inv(), residual variance on n - rank degrees of
#     freedom, two-sided t; aliased columns are left out as summary.lm() does.
.std_cols <- function(inputs, intercept = TRUE) {
  k <- as.integer(intercept)
  x <- matrix(1, nrow(inputs), length(inputs) + k)
  for (j in seq_along(inputs)) {
    v <- as.double(inputs[[j]])
    v <- v - colMeans(matrix(v, ncol = 1L), na.rm = TRUE)
    s <- sqrt(sum(v^2, na.rm = TRUE) / max(1, sum(!is.na(v)) - 1L))
    x[, j + k] <- v / s
  }
  x
}

calc_src <- function(inputs, output) {
  # Andreas 28/5/26 #10: the parameter names are kept exactly as given
  # ("Ym (DINT_cow)"); no formula is built, so nothing is backticked.
  orig_names <- colnames(inputs)
  n <- nrow(inputs)
  x <- .std_cols(inputs, intercept = TRUE)
  y <- as.vector(scale(output))
  z <- .lm.fit(x, y, tol = 1e-07)
  rm(x)
  p <- z$rank; p1 <- seq_len(p); p_all <- length(orig_names) + 1L
  coef <- z$coefficients
  if (p < p_all) coef[(p + 1L):p_all] <- NA
  coef[z$pivot] <- coef
  rdf    <- n - p
  resvar <- sum(z$residuals^2) / rdf
  se     <- sqrt(diag(chol2inv(z$qr[p1, p1, drop = FALSE])) * resvar)
  piv    <- z$pivot[p1]
  est    <- coef[piv]
  pval   <- 2 * pt(abs(est / se), rdf, lower.tail = FALSE)
  nm     <- c("(Intercept)", orig_names)[piv]
  keep   <- nm != "(Intercept)"

  result <- data.frame(
    parameter = nm[keep],
    src = unname(est[keep]),
    abs_src = unname(abs(est[keep])),
    p_value = unname(pval[keep]),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  result <- result[order(-result$abs_src), ]
  result$rank <- seq_len(nrow(result))
  rownames(result) <- NULL
  result
}

# `method` is accepted for the callers that still pass it and ignored: SRC
# is the one method (see the note at the top of this file).
sensitivity_analysis <- function(inputs, output, method = "src") {

  # Output-variance guard: SRC on a constant (or near-constant) output
  # returns spurious ranks. This happens when the selected output column is
  # structurally zero: e.g. PRP direct N2O for an intensive-dairy run where
  # pct_pasture = 0 across all iterations. Return an empty list with a
  # `message` attribute so renderers can surface why the chart is empty.
  out_sd <- stats::sd(output, na.rm = TRUE)
  if (length(output) == 0 || !is.finite(out_sd) || out_sd < 1e-9) {
    out <- list()
    attr(out, "message") <- paste0(
      "This output is constant across all Monte Carlo iterations, so ",
      "sensitivity is not defined. Common cause: the selected emission ",
      "pathway is zero for this dataset (e.g. pasture-deposition emissions ",
      "when no animals are on pasture)."
    )
    return(out)
  }

  # Keep only columns with a finite, positive standard deviation. `na.rm` +
  # `is.finite` is essential: a column carrying NaN/NA (e.g. a per-MMS sample
  # from a degenerate PERT parameterisation) makes sd() return NA, and a
  # logical index containing NA crashes `inputs[, var_cols]` with
  # "undefined columns selected" (the Zambia/Andy run). vapply guarantees a
  # clean logical vector with no NA entries.
  var_cols <- vapply(inputs, function(x) {
    s <- stats::sd(x, na.rm = TRUE)
    isTRUE(is.finite(s) && s > 0)
  }, logical(1))
  inputs_var <- inputs[, var_cols, drop = FALSE]
  if (ncol(inputs_var) == 0) return(list())

  list(src = calc_src(inputs_var, output))
}

# Aggregate sensitivity across a multi-system inventory. Each system's
# `samples` data frame is column-relabelled with the sub-category in
# parentheses (e.g. "Ym" -> "Ym (DINT_cow)") so the tornado chart and rank-
# correlation table identify which animal sub-category each influential
# parameter belongs to (Andreas 28/5/26 #8). The labelled frames are
# column-bound and regressed against the supplied `output` vector: which
# should be the per-iteration sum of the chosen metric across systems
# (typically `inventory$total_co2e` or `rowSums(by_system[[*]]$results[[src]])`
# for a per-source view).
#
# `output` must have length = n_iter (the row count of each system's samples
# frame).
aggregate_sensitivity <- function(by_system, output, method = "both",
                                  max_rows = 4000L) {
  if (is.null(by_system) || length(by_system) == 0) return(NULL)
  if (is.null(output) || length(output) == 0) return(NULL)

  # Extract sub_category from sys_name. sys_names are
  # "cattle_type||aggregation_level||sub_category"; fall back to the full
  # name when the structure is non-standard.
  sub_category_of <- function(sn) {
    parts <- strsplit(sn, "||", fixed = TRUE)[[1]]
    if (length(parts) >= 3 && nzchar(trimws(parts[3L])))
      trimws(parts[3L]) else sn
  }

  # 2026-09-21: with several production systems the same sub-category
  # recurs (other_cows in five beef systems on Zambia), cbind() then
  # de-duplicated the columns to "DE (other_cows).2" and the report named a
  # driver nobody could locate. When more than one aggregation level is
  # present the label carries it: "DE (other_cows, emergent_beef)".
  level_of <- function(sn) {
    parts <- strsplit(sn, "||", fixed = TRUE)[[1]]
    if (length(parts) >= 2 && nzchar(trimws(parts[2L]))) trimws(parts[2L]) else ""
  }
  levels_present <- unique(vapply(names(by_system), level_of, character(1)))
  multi_level <- length(setdiff(levels_present, "")) > 1L

  # 2026-10-28: rows are cut to the regression size BEFORE the groups are
  # joined. The join used to build the full n_iter x (all groups' columns)
  # matrix first and subsample it only at the end; on Zambia (32 groups,
  # 10,000 draws) that and the duplicate test below peaked at 1.4 GB per call,
  # twice per run with the no-correlation comparison, and the server dropped
  # the session. Every Monte Carlo row is an independent draw, so the first
  # rows are the same subsample the end of this function took before.
  n_keep <- length(output)
  if (is.finite(max_rows)) n_keep <- min(n_keep, max_rows)
  full_rows <- list(); full_means <- list()
  label_samples <- function(sn) {
    samp <- by_system[[sn]]$samples
    if (is.null(samp) || ncol(samp) == 0) return(NULL)
    # The full-length row count and column means are kept for the
    # subsample note and the "= value (shared by N groups)" labels, so both
    # read exactly as they did when the whole matrix was joined.
    full_rows[[sn]] <<- nrow(samp)
    full_means[[sn]] <<- colMeans(samp)
    if (nrow(samp) > n_keep) samp <- samp[seq_len(n_keep), , drop = FALSE]
    sc <- sub_category_of(sn)
    lv <- level_of(sn)
    tag <- if (multi_level && nzchar(lv)) paste0(sc, ", ", lv) else sc
    colnames(samp) <- paste0(colnames(samp), " (", tag, ")")
    samp
  }

  blocks <- Filter(Negate(is.null), lapply(names(by_system), label_samples))
  if (length(blocks) == 0) return(NULL)
  combined <- if (length(blocks) == 1) blocks[[1]] else do.call(cbind, blocks)
  full_means <- unname(unlist(full_means[names(full_rows)]))
  n_full     <- max(unlist(full_rows))
  # The group tag of every column ("cows" or "cows, extensive beef"), kept
  # so that each row of the result can say which groups it covers.
  col_tags  <- sub("^.*\\(([^()]*)\\)\\s*$", "\\1", colnames(combined))
  groups_of <- stats::setNames(col_tags, colnames(combined))

  # Cross-group sharing (2026-09) makes the per-group columns of a shared
  # coefficient NUMERICALLY IDENTICAL. Left alone that is a silent failure,
  # not a loud one: lm() aliases the duplicate columns so calc_src() quietly
  # returns fewer rows than it was given, and a rank-based residual
  # regression gets ~zero residuals and returns NaN. The existing zero-variance
  # guard does not catch it, because it tests the OUTPUT.
  #
  # Collapse duplicates to one column and name it for the parameter rather
  # than for any single group. That is also the more honest answer: a
  # coefficient shared by 251 groups is one driver of the uncertainty, and
  # belongs in the tornado once, not 251 times.
  if (ncol(combined) > 1L) {
    # Identical columns are found from a numeric fingerprint (sum, sum of
    # squares, first and last value), and every candidate pair is confirmed
    # with identical(). The previous test pasted every column into one long
    # string, which held a text copy of the whole matrix in memory.
    cs  <- colSums(combined); cs2 <- colSums(combined * combined)
    fp  <- paste(cs, cs2, unlist(combined[1L, ]), unlist(combined[nrow(combined), ]), sep = "|")
    grp <- match(fp, fp)
    for (j in which(grp != seq_along(grp))) {
      if (!identical(unname(combined[, j]), unname(combined[, grp[j]]))) grp[j] <- j
    }
    dups <- duplicated(grp)
    if (any(dups)) {
      keep_i <- which(!dups)
      n_share <- vapply(grp[keep_i], function(g) sum(grp == g), integer(1))
      nm <- colnames(combined)[keep_i]
      base <- sub("\\s*\\(.*\\)$", "", nm)
      # "DE (cows)" shared by several groups becomes
      # "DE = 65.4 (shared by 251 groups)".
      #
      # The value is part of the label, not decoration. An inventory can hold
      # several regional estimates of the same coefficient, each shared by its
      # own set of groups. Naming them all "GE (shared by 112 groups)" produced
      # colliding rows that data.frame() then silently made unique as
      # "GE (shared by 112 groups).3", which tells the reader nothing. Each
      # partition is defined by a distinct value, so the value distinguishes
      # them and says which estimate the row is about.
      # Formatted one value at a time. format() on a vector picks a single
      # layout for all of it, so a column of body weights next to a column of
      # Ym values would render both in scientific notation ("6.31e+00").
      val <- vapply(full_means[keep_i],
                    function(v) format(signif(v, 3L), trim = TRUE,
                                       scientific = FALSE, drop0trailing = TRUE),
                    character(1))
      # 2026-10-30 (Lolita): the groups behind each shared estimate are kept
      # (the `groups` column of the result), and when they all sit in one
      # production system the label names it: "DE = 52.8 (extensive beef,
      # 6 groups)" instead of "DE = 52.8 (shared by 6 groups)".
      members <- lapply(grp[keep_i], function(g) col_tags[grp == g])
      level_of_tag <- function(tg) if (grepl(", ", tg, fixed = TRUE)) sub("^.*, ", "", tg) else NA_character_
      one_level <- vapply(members, function(m) {
        lv <- unique(vapply(m, level_of_tag, character(1)))
        if (length(lv) == 1L && !is.na(lv)) lv else NA_character_
      }, character(1))
      nm <- ifelse(n_share > 1L,
                   ifelse(!is.na(one_level),
                          paste0(base, " = ", val, " (", one_level, ", ", n_share, " groups)"),
                          paste0(base, " = ", val, " (shared by ", n_share, " groups)")),
                   nm)
      combined <- combined[, keep_i, drop = FALSE]
      # Safety net: never leave uniquification to data.frame(), which would
      # append a bare index and hide a collision instead of reporting one.
      colnames(combined) <- make.unique(nm, sep = " #")
      groups_of <- stats::setNames(vapply(members, paste, character(1), collapse = "; "),
                                   colnames(combined))
    }
  }

  # 2026-10-30 (Lolita): animal numbers drawn as one count split into
  # groups have identical ranks in every group (different scales), which a
  # regression cannot separate. Columns of N with the same ranks become one
  # column, their sum, shown as one bar: "N (one count, 32 groups)".
  n_cols <- colnames(combined)[sub("\\s*\\(.*\\)$", "", colnames(combined)) == "N"]
  if (length(n_cols) > 1L) {
    # 2026-11-02: columns are merged on a rank correlation above 0.999, not
    # on identical ranks. Counts rounded to whole animals tie in some groups
    # and not in others, so identical ranks failed for 8 of the 27 Zambia
    # groups at 10,000 rows and the regression got eight collinear columns.
    rk  <- lapply(n_cols, function(cn) rank(combined[, cn], ties.method = "average"))
    left <- seq_along(n_cols)
    while (length(left) > 1L) {
      ref <- rk[[left[1]]]
      rho <- vapply(left, function(i) suppressWarnings(stats::cor(rk[[i]], ref)), numeric(1))
      pick <- left[is.finite(rho) & rho > 0.999]
      left <- setdiff(left, if (length(pick)) pick else left[1])
      members <- n_cols[pick]
      if (length(members) < 2L) next
      tot <- rowSums(combined[, members, drop = FALSE])
      lab <- sprintf("N (one count, %d groups)", length(members))
      tags_m <- sub("^.*\\(([^()]*)\\)\\s*$", "\\1", members)
      combined <- combined[, setdiff(colnames(combined), members), drop = FALSE]
      combined <- cbind(combined, tot)
      colnames(combined)[ncol(combined)] <- lab
      groups_of[[lab]] <- paste(tags_m, collapse = "; ")
    }
  }

  # Row subsample for the sensitivity regression ONLY. On a large multi-system
  # inventory the combined design matrix is ~n_iter x (15 x n_systems) columns;
  # the SRC lm() on a full 10,000-row x ~685-column matrix peaks several hundred
  # MB and runs twice (main + no-correlation comparison) on top of the 3x
  # decomposition: enough to exhaust a small instance and force a reload during
  # the sensitivity step (the "server needed to reload" failure on the heaviest
  # all-sources + correlations + decomposition run). SRC *rankings* are
  # stable far below the iteration count the headline percentiles need, so we
  # rank on a capped subsample. Each Monte Carlo row is an independent draw, so
  # the first `max_rows` rows are a valid random subsample. The headline 95% MoE
  # is unaffected: it is computed elsewhere from the full iteration set.
  # Reconcile the design matrix and the output vector to a common row count
  # before regressing. Two reasons:
  #   1. the subsample cap (rankings are stable far below the iteration count
  #      the headline percentiles need: see the note above), and
  #   2. `combined` may now be SHORTER than `output`: the Shiny app thins the
  #      retained per-system `samples` to ~4000 rows for memory, while the
  #      per-source `output` (e.g. rowSums of the full-n_iter `results`) is
  #      still full length. Aligning to the minimum keeps lm() inputs matched
  #      and avoids a "differing number of rows" error. The first k MC rows
  #      are an i.i.d. subsample, so rows line up across both.
  m <- min(n_full, length(output))
  if (is.finite(max_rows)) m <- min(m, max_rows)
  if (m < n_full || m < length(output)) {
    idx      <- seq_len(m)
    combined <- combined[idx, , drop = FALSE]
    output   <- output[idx]
  }
  res <- sensitivity_analysis(combined, output, method = method)
  # Which groups each row covers: one group, or the list behind a shared
  # estimate. Read by the group filter on Tab 5 and shown in the table.
  if (is.list(res) && is.data.frame(res$src) && nrow(res$src) > 0) {
    g <- unname(groups_of[res$src$parameter])
    res$src$groups <- ifelse(is.na(g), "", g)
  }
  if (m < n_full && is.list(res)) {
    attr(res, "subsampled_note") <- sprintf(
      paste0("Sensitivity ranking computed on the first %s of %s iterations ",
             "(the ranking is stable; the headline uncertainty uses all ",
             "iterations)."),
      format(m, big.mark = ","), format(n_full, big.mark = ","))
  }
  res
}

# Parse a sensitivity parameter name produced by aggregate_sensitivity() and
# return its sub_category (the contents of the trailing parentheses): or
# "(ungrouped)" when the column name was emitted without a parenthesised
# suffix (single-system inputs to sensitivity_analysis directly).
sens_group_of <- function(var_name) {
  m <- regmatches(var_name,
                   regexec("\\(([^()]+)\\)\\s*$", var_name))[[1]]
  if (length(m) >= 2 && nzchar(m[2])) m[2] else "(ungrouped)"
}

# The groups a sensitivity row covers, from its `groups` column when the
# frame has one (a shared estimate lists several, "; "-separated), else
# from the label.
sens_groups_of_row <- function(df) {
  if (!is.null(df$groups)) {
    out <- strsplit(as.character(df$groups), "; ", fixed = TRUE)
    lapply(seq_along(out), function(i)
      if (length(out[[i]]) && any(nzchar(out[[i]]))) out[[i]] else sens_group_of(df$parameter[i]))
  } else lapply(df$parameter, sens_group_of)
}


# 2026-11-02: which inputs a compiler can improve with national data (green
# in the tornado) and which are IPCC coefficients (blue). Labels arrive as
# "DE (heifers, emergent_beef)", "Ym = 5.24 (shared by 5 groups)",
# "N (one count, 27 groups)", "MCF_liquid_slurry (...)" or "BW_y1"; the
# bracket, the " = value" and the year suffix are removed before the
# catalogue lookup. The manure system coefficients (MCF, EF3, Frac_GasMS,
# Frac_LeachMS) are IPCC coefficients; the manure shares (fraction_...)
# and anything not in the catalogue count as national data.
param_reducible <- function(params) {
  # the trend's change ranking names an input per year: "N (cows) 2022"
  bare <- sub("[[:space:]]+[0-9]{4}$", "", as.character(params))
  bare <- sub("[[:space:]]*[(][^()]*[)][[:space:]]*$", "", bare)
  bare <- sub("[[:space:]]*=.*$", "", bare)
  bare <- sub("_(y1|yN)$", "", bare)
  lut <- stats::setNames(PARAM_CATALOGUE$user_reducible, PARAM_CATALOGUE$parameter)
  r <- as.logical(lut[bare])
  coef <- grepl("^(MCF|EF3|Frac_GasMS|Frac_LeachMS|Frac_GASM|Frac_LEACH|EF4|EF5|B0|Bo)(_|$)", bare)
  r[is.na(r) & coef] <- FALSE
  r[is.na(r)] <- TRUE
  r
}
