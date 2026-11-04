# Results by cattle type: IPCC Table 3.3 split between dairy and non-dairy
# cattle (2026-11-04, review of the new version: "once a country moves to
# Tier 2 ... they may want to report the results divided between cattle
# types. Would it be possible to produce a table of results for each
# emission source for each cattle type in addition to the main result?").
#
# Built from the per-draw group results the runs already produce: within a
# run, the groups of one cattle type are summed draw by draw, then the
# 2.5 / 97.5 percentiles are taken. Summing before the quantiles keeps the
# shared and correlated draws between groups. No extra simulation. The
# reporting codes follow the UNFCCC Common Reporting Tables as listed in the
# methodology: 3.A.1.a / 3.A.1.b and 3.B.1.a / 3.B.1.b; the other lines are
# not split by animal type in those tables and carry the cattle type in
# words only.

# "dairy" or "non_dairy" from a group key "cattle_type||level||sub_category".
.cattle_type_of_group <- function(sn) {
  ct <- strsplit(sn, "||", fixed = TRUE)[[1]][1]
  if (.is_dairy_type(ct)) "dairy" else "non_dairy"
}

# Per-draw sums of every result column over the groups of each cattle type:
# a named list (dairy, non_dairy) of data frames, or NULL.
cattle_type_results <- function(sim) {
  bs <- sim$by_system
  if (is.null(bs) || !length(bs)) return(NULL)
  types <- vapply(names(bs), .cattle_type_of_group, character(1))
  out <- list()
  for (ty in intersect(c("dairy", "non_dairy"), unique(types))) {
    acc <- NULL; cols <- NULL
    for (sn in names(bs)[types == ty]) {
      r <- bs[[sn]]$results
      if (is.null(r)) next
      num <- names(r)[vapply(r, is.numeric, logical(1))]
      cols <- if (is.null(cols)) num else intersect(cols, num)
      m <- as.matrix(r[, cols, drop = FALSE])
      acc <- if (is.null(acc)) m else acc[, cols, drop = FALSE] + m
    }
    if (!is.null(acc)) out[[ty]] <- as.data.frame(acc)
  }
  if (length(out)) out else NULL
}

# The uncertainty summary of each cattle type (calc_all_uncertainty), rows of
# unticked sources dropped.
cattle_type_uncertainty <- function(sim, sources = NULL) {
  ct <- cattle_type_results(sim)
  if (is.null(ct)) return(NULL)
  lapply(ct, function(df) drop_unselected_rows(calc_all_uncertainty(df), sources))
}

.CT_LINES <- data.frame(
  var  = c("enteric_ch4_total", "manure_ch4_total", "direct_n2o_mm_total",
           "indirect_n2o_mm_total", "direct_n2o_prp_total", "indirect_n2o_prp_total",
           "total_co2e"),
  code_dairy     = c("3.A.1.a", "3.B.1.a", "3.B.1.a", "3.B.5", "3.D.1.c", "3.D.2", ""),
  code_non_dairy = c("3.A.1.b", "3.B.1.b", "3.B.1.b", "3.B.5", "3.D.1.c", "3.D.2", ""),
  line = c("Enteric fermentation", "Manure management (CH₄)",
           "Manure management (N₂O direct)", "Manure management (N₂O indirect)",
           "Pasture, range and paddock (N₂O direct)",
           "Pasture, range and paddock (N₂O indirect)", "Total"),
  gas = c("CH₄", "CH₄", "N₂O", "N₂O", "N₂O", "N₂O", "CO₂eq"),
  stringsAsFactors = FALSE)
.CT_LABEL <- c(dairy = "Dairy cattle", non_dairy = "Non-dairy cattle")

# IPCC Table 3.3 by cattle type for a single year. by_type is
# list(combined = <per-type uncertainty>, ad_only = ..., ef_only = ...),
# each a named list (dairy, non_dairy) of calc_all_uncertainty frames.
format_ipcc_table_by_type <- function(by_type) {
  comb <- by_type$combined
  if (is.null(comb) || !length(comb)) return(NULL)
  pick <- function(frame, var, col) {
    if (is.null(frame)) return(NA_real_)
    row <- frame[frame$variable == var, , drop = FALSE]
    if (nrow(row) == 0L || !col %in% names(row)) NA_real_ else row[[col]][1]
  }
  rows <- list()
  for (i in seq_len(nrow(.CT_LINES))) {
    l <- .CT_LINES[i, ]
    for (ty in names(comb)) {
      m <- pick(comb[[ty]], l$var, "mean")
      if (is.na(m)) next
      code <- if (ty == "dairy") l$code_dairy else l$code_non_dairy
      rows[[length(rows) + 1L]] <- data.frame(
        `Emission category` = trimws(paste(code, l$line)),
        `Cattle type` = .CT_LABEL[[ty]],
        Gas = l$gas,
        `Mean emissions (t of the gas)` = round(m, 1),
        `AD uncertainty (95% MoE %)` = round(pick(by_type$ad_only[[ty]], l$var, "moe_pct"), 1),
        `EF uncertainty (95% MoE %)` = round(pick(by_type$ef_only[[ty]], l$var, "moe_pct"), 1),
        `Combined uncertainty (95% MoE %)` = round(pick(comb[[ty]], l$var, "moe_pct"), 1),
        `Combined +upper (%)` = round(pick(comb[[ty]], l$var, "upper_pct"), 1),
        `Combined -lower (%)` = round(pick(comb[[ty]], l$var, "lower_pct"), 1),
        check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
