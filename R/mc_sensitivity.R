# Sensitivity Analysis
# Standardized Regression Coefficients (SRC) and Partial Rank Correlation (PRCC)

calc_src <- function(inputs, output) {
  # Andreas 28/5/26 #10: preserve original column names through the lm fit.
  # When input names contain spaces/parentheses (e.g. "Ym (DINT_cow)" produced
  # by aggregate_sensitivity), R's formula machinery wraps them in backticks
  # and the resulting coefficient rownames LITERALLY include the backticks
  # ("`Ym (DINT_cow)`"). Strip them so the SRC output has clean parameter
  # names that match the in-app tornado labels.
  orig_names <- colnames(inputs)
  inputs_std <- as.data.frame(scale(inputs), check.names = FALSE)
  colnames(inputs_std) <- orig_names
  output_std <- scale(output)
  df <- cbind(inputs_std, y = output_std)
  fit <- lm(y ~ ., data = df)
  coefs <- summary(fit)$coefficients
  coefs <- coefs[rownames(coefs) != "(Intercept)", , drop = FALSE]

  param_names <- gsub("^`|`$", "", rownames(coefs))

  result <- data.frame(
    parameter = param_names,
    src = coefs[, "Estimate"],
    abs_src = abs(coefs[, "Estimate"]),
    p_value = coefs[, "Pr(>|t|)"],
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  result <- result[order(-result$abs_src), ]
  result$rank <- seq_len(nrow(result))
  rownames(result) <- NULL
  result
}

calc_prcc <- function(inputs, output) {
  # Andreas 28/5/26 #10: preserve original column names — `as.data.frame()`
  # default `check.names = TRUE` mangles "Ym (DINT_cow)" into "Ym..DINT_cow.".
  orig_names <- colnames(inputs)
  ranked_list <- lapply(inputs, rank)
  inputs_ranked <- as.data.frame(ranked_list, check.names = FALSE)
  colnames(inputs_ranked) <- orig_names
  output_ranked <- rank(output)
  n_params <- ncol(inputs_ranked)
  prcc_values <- numeric(n_params)

  for (j in seq_len(n_params)) {
    other_cols <- setdiff(seq_len(n_params), j)
    resid_j <- residuals(lm(inputs_ranked[[j]] ~ as.matrix(inputs_ranked[, other_cols])))
    resid_y <- residuals(lm(output_ranked ~ as.matrix(inputs_ranked[, other_cols])))
    prcc_values[j] <- cor(resid_j, resid_y)
  }

  result <- data.frame(
    parameter = orig_names,
    prcc = prcc_values,
    abs_prcc = abs(prcc_values),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  result <- result[order(-result$abs_prcc), ]
  result$rank <- seq_len(nrow(result))
  rownames(result) <- NULL
  result
}

sensitivity_analysis <- function(inputs, output, method = c("src", "prcc", "both"),
                                  max_prcc_cols = 40L) {
  method <- match.arg(method)

  # Output-variance guard: SRC/PRCC on a constant (or near-constant) output
  # returns spurious ranks. This happens when the selected output column is
  # structurally zero — e.g. PRP direct N2O for an intensive-dairy run where
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

  # PRCC is O(p) in lm() fits (one per parameter). For multi-group inventories
  # the combined parameter matrix can have 80-150 columns, making PRCC take
  # several minutes. Cap it: if p > max_prcc_cols, compute SRC only and attach
  # a note so the UI can explain the fallback.
  prcc_note <- NULL
  if (method %in% c("prcc", "both") && ncol(inputs_var) > max_prcc_cols) {
    method <- "src"
    prcc_note <- paste0(
      "PRCC was skipped: the combined parameter matrix has ",
      ncol(inputs_var), " columns (limit: ", max_prcc_cols, "). ",
      "SRC is shown instead — it requires only one regression fit regardless ",
      "of the number of parameters. To see PRCC, select a single emission ",
      "source from the 'Output' dropdown above."
    )
  }

  result <- list()
  if (method %in% c("src", "both")) result$src <- calc_src(inputs_var, output)
  if (method %in% c("prcc", "both")) result$prcc <- calc_prcc(inputs_var, output)
  if (!is.null(prcc_note)) attr(result, "prcc_note") <- prcc_note
  result
}

# Aggregate sensitivity across a multi-system inventory. Each system's
# `samples` data frame is column-relabelled with the sub-category in
# parentheses (e.g. "Ym" -> "Ym (DINT_cow)") so the tornado chart and rank-
# correlation table identify which animal sub-category each influential
# parameter belongs to (Andreas 28/5/26 #8). The labelled frames are
# column-bound and regressed against the supplied `output` vector — which
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

  label_samples <- function(sn) {
    samp <- by_system[[sn]]$samples
    if (is.null(samp) || ncol(samp) == 0) return(NULL)
    sc <- sub_category_of(sn)
    colnames(samp) <- paste0(colnames(samp), " (", sc, ")")
    samp
  }

  blocks <- Filter(Negate(is.null), lapply(names(by_system), label_samples))
  if (length(blocks) == 0) return(NULL)
  combined <- if (length(blocks) == 1) blocks[[1]] else do.call(cbind, blocks)

  # Row subsample for the sensitivity regression ONLY. On a large multi-system
  # inventory the combined design matrix is ~n_iter x (15 x n_systems) columns;
  # the SRC lm() on a full 10,000-row x ~685-column matrix peaks several hundred
  # MB and runs twice (main + no-correlation comparison) on top of the 3x
  # decomposition — enough to exhaust a small instance and force a reload during
  # the sensitivity step (the "server needed to reload" failure on the heaviest
  # all-sources + correlations + decomposition run). SRC/PRCC *rankings* are
  # stable far below the iteration count the headline percentiles need, so we
  # rank on a capped subsample. Each Monte Carlo row is an independent draw, so
  # the first `max_rows` rows are a valid random subsample. The headline 95% MoE
  # is unaffected — it is computed elsewhere from the full iteration set.
  n_full <- nrow(combined)
  if (is.finite(max_rows) && n_full > max_rows) {
    idx <- seq_len(max_rows)
    combined <- combined[idx, , drop = FALSE]
    output   <- output[idx]
  }
  res <- sensitivity_analysis(combined, output, method = method)
  if (is.finite(max_rows) && n_full > max_rows && is.list(res)) {
    attr(res, "subsampled_note") <- sprintf(
      paste0("Sensitivity ranking computed on the first %s of %s iterations ",
             "(the ranking is stable; the headline uncertainty uses all ",
             "iterations)."),
      format(max_rows, big.mark = ","), format(n_full, big.mark = ","))
  }
  res
}

# Parse a sensitivity parameter name produced by aggregate_sensitivity() and
# return its sub_category (the contents of the trailing parentheses) — or
# "(ungrouped)" when the column name was emitted without a parenthesised
# suffix (single-system inputs to sensitivity_analysis directly).
sens_group_of <- function(var_name) {
  m <- regmatches(var_name,
                   regexec("\\(([^()]+)\\)\\s*$", var_name))[[1]]
  if (length(m) >= 2 && nzchar(m[2])) m[2] else "(ungrouped)"
}
