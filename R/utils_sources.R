# Emission-source selection (Tab 4 ticks), applied to every result.
#
# 2026-11-04 (review of the new version: "I selected to run it only for
# enteric fermentation, but in the results tab and IPCC report all the
# emission sources were calculated ... you are not sure if this is only
# enteric fermentation or if it includes all sources"). Until this date the
# ticks only rewrote the totals of the main run; the AD-only, EF-only and
# comparison runs, the per-source cards and tables, IPCC Table 3.3 and the
# trend's paired run ignored them. Decision (Lolita, 4 November): the ticks
# filter everything. Every simulation result goes through
# filter_sim_sources() before any summary is taken, and the displays drop
# the rows of unticked sources.

# One row per source: the Tab 4 key, the per-group column (suffix naming)
# and the inventory column (prefix naming), and the gas.
SOURCE_COLUMNS <- data.frame(
  key    = c("enteric_ch4", "manure_ch4", "manure_n2o_direct",
             "manure_n2o_indirect", "pasture_n2o_direct", "pasture_n2o_indirect"),
  suffix = c("enteric_ch4_total", "manure_ch4_total", "direct_n2o_mm_total",
             "indirect_n2o_mm_total", "direct_n2o_prp_total", "indirect_n2o_prp_total"),
  prefix = c("total_enteric_ch4", "total_manure_ch4", "total_direct_n2o_mm",
             "total_indirect_n2o_mm", "total_direct_n2o_prp", "total_indirect_n2o_prp"),
  gas    = c("CH4", "CH4", "N2O", "N2O", "N2O", "N2O"),
  stringsAsFactors = FALSE
)
ALL_SOURCE_KEYS <- SOURCE_COLUMNS$key

# The ticked keys, with the legacy single "pasture_n2o" box read as both
# pasture sources. NULL or empty means every source (callers that must
# refuse an empty selection check it before).
normalize_sources <- function(sources) {
  s <- as.character(sources %||% character(0))
  if ("pasture_n2o" %in% s) s <- c(s, "pasture_n2o_direct", "pasture_n2o_indirect")
  s <- intersect(ALL_SOURCE_KEYS, s)
  if (length(s) == 0L) ALL_SOURCE_KEYS else s
}
all_sources_selected <- function(sources) setequal(normalize_sources(sources), ALL_SOURCE_KEYS)

# The result-column names (both namings) of the sources NOT ticked.
unselected_source_vars <- function(sources) {
  off <- !SOURCE_COLUMNS$key %in% normalize_sources(sources)
  c(SOURCE_COLUMNS$suffix[off], SOURCE_COLUMNS$prefix[off])
}

# Gases that keep at least one ticked source ("CH4", "N2O").
selected_gases <- function(sources) {
  unique(SOURCE_COLUMNS$gas[SOURCE_COLUMNS$key %in% normalize_sources(sources)])
}

# Zero the unticked per-source columns of one results frame (either naming)
# and recompute every total from what is left. The combined direct and
# indirect N2O totals of the inventory frame are recomputed too.
filter_sources_df <- function(df, sources, gwp = "AR5") {
  if (is.null(df) || all_sources_selected(sources)) return(df)
  keep <- normalize_sources(sources)
  gv <- GWP_VALUES[[gwp]] %||% GWP_VALUES[["AR5"]]
  n <- nrow(df)
  col <- function(i) {
    for (nm in c(SOURCE_COLUMNS$suffix[i], SOURCE_COLUMNS$prefix[i]))
      if (!is.null(df[[nm]])) return(df[[nm]])
    rep(0, n)
  }
  vals <- lapply(seq_len(nrow(SOURCE_COLUMNS)), function(i)
    if (SOURCE_COLUMNS$key[i] %in% keep) col(i) else rep(0, n))
  for (i in seq_len(nrow(SOURCE_COLUMNS))) {
    for (nm in c(SOURCE_COLUMNS$suffix[i], SOURCE_COLUMNS$prefix[i]))
      if (!is.null(df[[nm]])) df[[nm]] <- vals[[i]]
  }
  ch4 <- vals[[1]] + vals[[2]]
  n2o <- vals[[3]] + vals[[4]] + vals[[5]] + vals[[6]]
  if (!is.null(df$total_direct_n2o))   df$total_direct_n2o   <- vals[[3]] + vals[[5]]
  if (!is.null(df$total_indirect_n2o)) df$total_indirect_n2o <- vals[[4]] + vals[[6]]
  df$total_ch4 <- ch4
  df$total_n2o <- n2o
  if (!is.null(df$co2e_ch4)) df$co2e_ch4 <- ch4 * gv$CH4
  if (!is.null(df$co2e_n2o)) df$co2e_n2o <- n2o * gv$N2O
  df$total_co2e <- ch4 * gv$CH4 + n2o * gv$N2O
  df
}

# The same on a whole simulation result (inventory and every group).
filter_sim_sources <- function(sim, sources, gwp = "AR5") {
  if (is.null(sim) || all_sources_selected(sources)) return(sim)
  if (!is.null(sim$inventory)) sim$inventory <- filter_sources_df(sim$inventory, sources, gwp)
  for (sn in names(sim$by_system))
    if (!is.null(sim$by_system[[sn]]$results))
      sim$by_system[[sn]]$results <- filter_sources_df(sim$by_system[[sn]]$results, sources, gwp)
  sim
}

# Drop the uncertainty rows of unticked sources (calc_all_uncertainty
# output, "variable" column), and the gas totals left without a source.
unselected_vars <- function(sources) {
  if (all_sources_selected(sources)) return(character(0))
  drop <- unselected_source_vars(sources)
  g <- selected_gases(sources)
  if (!"CH4" %in% g) drop <- c(drop, "total_ch4", "co2e_ch4")
  if (!"N2O" %in% g) drop <- c(drop, "total_n2o", "co2e_n2o", "total_direct_n2o", "total_indirect_n2o")
  drop
}
drop_unselected_rows <- function(unc, sources, col = "variable") {
  if (is.null(unc) || !col %in% names(unc) || all_sources_selected(sources)) return(unc)
  unc[!unc[[col]] %in% unselected_vars(sources), , drop = FALSE]
}

# Which input-draw columns feed the ticked sources: the Parameters inputs
# through SOURCE_PARAM_DEPS (R/utils_ipcc_defaults.R), the per-system manure
# draws by their prefix. Inputs feeding only unticked sources are left out
# of the sensitivity regression, where they would show as near-zero bars.
sample_columns_for_sources <- function(cols, sources) {
  if (all_sources_selected(sources)) return(rep(TRUE, length(cols)))
  keep <- normalize_sources(sources)
  base <- sub(" .*$", "", cols)
  needed <- unique(c(params_needed_for_sources(keep), "GE", "DMI", "Tw"))
  manure_any <- any(keep %in% c("manure_ch4", "manure_n2o_direct", "manure_n2o_indirect",
                                "pasture_n2o_direct", "pasture_n2o_indirect"))
  out <- base %in% needed
  out[grepl("^MCF_", base)]          <- "manure_ch4" %in% keep
  out[grepl("^EF3_", base) & base != "EF3_PRP"] <- "manure_n2o_direct" %in% keep
  out[grepl("^Frac_(GasMS|LeachMS)_", base)]    <- "manure_n2o_indirect" %in% keep
  out[grepl("^fraction_", base)]     <- manure_any
  out
}

# "Enteric fermentation CH4, Manure management CH4", for the line shown
# above the results when not every source is ticked.
SOURCE_LABELS <- list(
  en = c(enteric_ch4 = "Enteric fermentation CH4", manure_ch4 = "Manure management CH4",
         manure_n2o_direct = "Manure management N2O (direct)",
         manure_n2o_indirect = "Manure management N2O (indirect)",
         pasture_n2o_direct = "Pasture, range and paddock N2O (direct)",
         pasture_n2o_indirect = "Pasture, range and paddock N2O (indirect)"),
  fr = c(enteric_ch4 = "Fermentation entérique CH4", manure_ch4 = "Gestion des effluents CH4",
         manure_n2o_direct = "Gestion des effluents N2O (direct)",
         manure_n2o_indirect = "Gestion des effluents N2O (indirect)",
         pasture_n2o_direct = "Pâturages N2O (direct)",
         pasture_n2o_indirect = "Pâturages N2O (indirect)")
)
sources_label <- function(sources, lang = "en") {
  lab <- SOURCE_LABELS[[lang]] %||% SOURCE_LABELS$en
  paste(unname(lab[normalize_sources(sources)]), collapse = ", ")
}
