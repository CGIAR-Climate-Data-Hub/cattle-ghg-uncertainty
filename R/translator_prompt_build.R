# =============================================================================
# AI translator prompt: the GENERATED sections, built from the live R objects
# =============================================================================
#
# 2026-09-17. Until now the three generated knowledge files the model reads
# (param_catalogue.md, template_schema.md, worked_example.md) were written to
# disk by scripts/build_translator_kit.R and read back at runtime. That made
# the model's knowledge of the defaults as fresh as the last time somebody
# remembered to run the script: the September IPCC audit moved 92 values, and
# had the rebuild been skipped the translator would have kept filling Milk 3.5
# and pct_pregnant 0.60 while the app's own gap-fill used 1.2 and 0.52.
#
# The generators now live here as functions of the R objects, and
# assemble_translator_system_prompt() calls them at runtime (memoised per
# process). The build script calls the SAME functions to write the .md files
# for the DIY kit and for review diffs, and writes a manifest of hashes that
# audit check F46 compares against the master. Nothing about the defaults
# reaches the model through a file that can go stale.
#
# Byte-stability matters: Anthropic caches the system prompt by content, so
# the output must not carry dates, locale-dependent number formatting or
# unordered iteration. fmt_num() below pins the formatting.
#
# Load-order note: this file is sourced alphabetically before utils_*.R, so
# it must not evaluate anything at source time. Everything is a function.
# =============================================================================

.TP_PARTIALS_DIR <- "translator_prompts/partials"

# ---- helpers ----------------------------------------------------------------

.tp_fmt_num <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("")
  if (x == 0) return("0")
  # format() with fixed digits and no scientific notation is locale-free for
  # the decimal mark only when OutDec is "."; pin it so a French session
  # cannot emit "0,386" into the prompt.
  old <- options(OutDec = "."); on.exit(options(old), add = TRUE)
  format(x, scientific = FALSE, drop0trailing = TRUE, digits = 12)
}

# Strip HTML comments as BLOCKS (a per-line filter kept the middle lines of a
# multi-line comment and shipped them into the kit; do not simplify).
.tp_strip_html_comments <- function(txt) {
  keep <- rep(TRUE, length(txt)); inside <- FALSE
  for (i in seq_along(txt)) {
    opens  <- grepl("<!--", txt[i], fixed = TRUE)
    closes <- grepl("-->",  txt[i], fixed = TRUE)
    if (inside) {
      keep[i] <- FALSE
      if (closes) inside <- FALSE
    } else if (opens) {
      keep[i] <- FALSE
      if (!closes) inside <- TRUE
    }
  }
  if (inside) stop("unterminated HTML comment in a prompt partial", call. = FALSE)
  txt[keep]
}

# Hand-maintained prose lives in translator_prompts/partials/. A missing
# partial is a hard error, so a deleted file fails loudly instead of silently
# shrinking the prompt the model receives.
.tp_partial <- function(name, dir = .TP_PARTIALS_DIR) {
  f <- file.path(dir, paste0(name, ".md"))
  if (!file.exists(f)) stop("missing prompt partial: ", f, call. = FALSE)
  txt <- .tp_strip_html_comments(readLines(f, warn = FALSE, encoding = "UTF-8"))
  trimws(paste(txt, collapse = "\n"))
}

.tp_read_keyed <- function(fname, required = TRUE, dir = .TP_PARTIALS_DIR) {
  f <- file.path(dir, fname)
  if (!file.exists(f)) {
    if (required) stop("missing prompt partial: ", f, call. = FALSE) else return(list())
  }
  ln <- .tp_strip_html_comments(readLines(f, warn = FALSE, encoding = "UTF-8"))
  # Paragraphs joined with a single space: every consumer renders a keyed
  # partial into ONE markdown table cell, where a newline would break it.
  idx <- grep("^## ", ln); out <- list()
  for (k in seq_along(idx)) {
    key <- sub("^## ", "", ln[idx[k]])
    to  <- if (k < length(idx)) idx[k + 1] - 1 else length(ln)
    out[[key]] <- trimws(paste(ln[(idx[k] + 1):to], collapse = " "))
  }
  out
}

.tp_esc <- function(x) gsub("|", "\\|", x, fixed = TRUE)

# ---- 1. param_catalogue.md --------------------------------------------------

build_param_catalogue_md <- function(partials_dir = .TP_PARTIALS_DIR) {
  pc <- PARAM_CATALOGUE
  NPAR <- nrow(pc)
  alias_to <- function(canonical) {
    hits <- names(PARAM_ALIASES)[PARAM_ALIASES == canonical]
    if (length(hits) == 0) "(none)" else paste(hits, collapse = ", ")
  }
  .defs <- .tp_read_keyed("definition_overrides.md", dir = partials_dir)
  bad <- setdiff(names(.defs), pc$parameter)
  if (length(bad)) stop("definition_overrides.md names unknown parameters: ",
                        paste(bad, collapse = ", "), call. = FALSE)
  def_for <- function(prm) if (!is.null(.defs[[prm]])) .defs[[prm]] else
    pc$definition[pc$parameter == prm]

  # The declared basis goes at the TOP: the model fills gaps with these
  # defaults, so it has to know what they assume.
  basis_lines <- c(
    "## What these defaults assume",
    "",
    "Every default in the table below is one cell of a much larger IPCC table. Reaching it means choosing a region, a productivity class, a climate and, for manure, a specific system variant. When the user's data shows that one of these choices does not describe their herd, say so in section D and use their value instead of the default.",
    "",
    "| choice | this tool uses | IPCC also publishes | affects | why, and what to do otherwise |",
    "|---|---|---|---|---|")
  B_TW <- basis_tool_wide()
  for (i in seq_len(nrow(B_TW))) {
    lb <- DEFAULT_BASIS_LABELS[[B_TW$dimension[i]]]
    basis_lines <- c(basis_lines, sprintf("| **%s** | %s | %s | `%s` | %s |",
      if (is.null(lb)) B_TW$dimension[i] else lb,
      .tp_esc(B_TW$chosen[i]), .tp_esc(B_TW$alternatives[i]),
      gsub(" ", "`, `", B_TW$governs[i], fixed = TRUE),
      .tp_esc(B_TW$why[i])))
  }
  basis_lines <- c(basis_lines, "",
    "### Which IPCC variant each manure system models",
    "",
    "Every coefficient on a manure row (MCF, EF3, and the volatilisation and leaching fractions) comes from the single variant named here, so the row describes one real system rather than a blend. If the user's file describes a different variant, flag it.",
    "",
    "| mms_type | IPCC variant modelled |", "|---|---|")
  for (i in seq_len(nrow(MMS_DEFAULTS)))
    basis_lines <- c(basis_lines, sprintf("| `%s` | %s |",
      MMS_DEFAULTS$id[i], MMS_DEFAULTS$ipcc_variant[i]))
  basis_lines <- c(basis_lines, "")

  lines <- c(
    "# Parameter catalogue",
    "",
    basis_lines,
    sprintf("Single source of truth for the %d IPCC-aligned parameters the cattle uncertainty app expects.", NPAR),
    "When you (Claude) translate a user's raw column to a template field, use this table.",
    "All parameter codes are case-sensitive.",
    "",
    "| code | tier | type | unit | IPCC default | suggested ±% | distribution | IPCC ref | aliases accepted | definition |",
    "|------|------|------|------|--------------|--------------|--------------|----------|------------------|------------|"
  )
  for (i in seq_len(nrow(pc))) {
    lines <- c(lines, sprintf(
      "| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
      pc$parameter[i], pc$param_tier[i], pc$param_type[i], pc$unit[i],
      .tp_fmt_num(pc$ipcc_default[i]),
      if (is.na(pc$suggested_uncertainty_pct[i])) "(asymmetric — use bounds)"
        else paste0(pc$suggested_uncertainty_pct[i], "%"),
      pc$suggested_distribution[i],
      if (nzchar(pc$ipcc_ref[i])) pc$ipcc_ref[i] else "—",
      alias_to(pc$parameter[i]),
      .tp_esc(def_for(pc$parameter[i]))))
  }

  asym <- pc[!is.na(pc$suggested_lower_bound) | !is.na(pc$suggested_upper_bound), ]
  if (nrow(asym) > 0) {
    lines <- c(lines, "",
      "## Asymmetric (non-symmetric) bounds", "",
      .tp_partial("asymmetric_bounds_note", partials_dir), "",
      "| code | lower | central | upper |",
      "|------|-------|---------|-------|")
    for (i in seq_len(nrow(asym))) {
      lines <- c(lines, sprintf("| `%s` | %s | %s | %s |",
        asym$parameter[i], .tp_fmt_num(asym$suggested_lower_bound[i]),
        .tp_fmt_num(asym$ipcc_default[i]), .tp_fmt_num(asym$suggested_upper_bound[i])))
    }
  }

  # Sex- and physiology-specific overrides: the TABLE is generated from the
  # resolver's own inputs, so it cannot drift from what the app derives. This
  # section is named by system_instructions.md self-check #9.
  .rownotes <- .tp_read_keyed("subcat_overrides_rownotes.md", required = FALSE, dir = partials_dir)
  lines <- c(lines, "",
    "## Sex- and physiology-specific coefficient overrides", "",
    .tp_partial("subcat_overrides_intro", partials_dir), "",
    "| sub-category | Cfi (Table 10.4) | C (Eq 10.6) | Ym 2019R (Table 10.12) | Ym 2006 | BW | MW | WG | DE | CP | notes |",
    "|---|---|---|---|---|---|---|---|---|---|---|")
  dash <- function(x) if (is.null(x)) "—" else .tp_fmt_num(x)
  for (sc in ANIMAL_SUBCATEGORIES) {
    lines <- c(lines, sprintf("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", sc,
      dash(CFI_BY_SUBCAT[[sc]]), dash(C_GROWTH_BY_SUBCAT[[sc]]),
      dash(ym_for_subcat(sc, "2019_refinement")), dash(ym_for_subcat(sc, "2006")),
      dash(LW_BY_SUBCAT[[sc]]), dash(MW_BY_SUBCAT[[sc]]), dash(WG_BY_SUBCAT[[sc]]),
      dash(DE_BY_SUBCAT[[sc]]), dash(CP_BY_SUBCAT[[sc]]),
      if (!is.null(.rownotes[[sc]])) .tp_esc(.rownotes[[sc]]) else ""))
  }
  lines <- c(lines, "",
    "`Ca` is not per-sub-category: it depends on the feeding situation (IPCC Table 10.5).", "",
    paste0("Values: ", paste(sprintf("%s = %s", names(FEEDING_SITUATION_CA),
           vapply(unlist(FEEDING_SITUATION_CA), .tp_fmt_num, character(1))), collapse = "; "), "."),
    "",
    .tp_partial("subcat_overrides_outro", partials_dir))

  lines <- c(lines, "",
    "## Tier meaning", "",
    "- **core** = user must provide a value (or accept the IPCC default). These are the activity-data parameters and a handful of high-impact coefficients (DE, CP, MilkPR).",
    "- **advanced** = IPCC equation coefficient. Pre-filled with the IPCC default from the column above; only override if the user has a country-specific measurement.",
    "",
    "## param_type", "",
    "- **activity_data** = `N` only (animal population). This is the one true activity-data variable.",
    "- **coefficient** = everything else (production parameters, energy/methane/N₂O coefficients).",
    "",
    "## Distribution codes accepted", "",
    paste("`", paste(DISTRIBUTION_TYPES, collapse = "`, `"), "`", sep = ""),
    "",
    "Use `pert` or `triangular` when only a mode + bounds are known; `normal` for symmetric ±% around a measured mean; `beta` or `tnorm_0_1` for fractions that must stay in [0, 1]; `lognormal` for strictly-positive values with right skew (typical for emission factors).")
  lines
}

# ---- 2. template_schema.md --------------------------------------------------

# Per-column notes. Keyed by header so a renamed or added column shows up in
# the prompt with a blank note rather than not at all.
.TP_P_COL_NOTES <- c(
  cattle_type       = "yes | e.g. `dairy`, `non_dairy`",
  aggregation_level = "yes | free text label for the inventory grouping (production system, region, AEZ)",
  sub_category      = "yes | one of the ANIMAL_SUBCATEGORIES below (or free-text if the inventory uses custom groups)",
  parameter         = "yes | the parameter code from param_catalogue.md",
  definition        = "no | optional human label (mirrors param_catalogue)",
  unit              = "no | optional unit (mirrors param_catalogue)",
  value             = "yes | the central value — **the number the user is providing**",
  uncertainty_pct   = "one of (uncertainty_pct) or (lower/upper) | symmetric ±% half-width of 95% CI",
  lower_bound       = "no | catalogue reference bound, display only; the model writes bounds to `lower` / `upper`",
  upper_bound       = "no | catalogue reference bound, display only",
  distribution      = "yes | one of the distribution codes in param_catalogue.md",
  lower             = "one of (uncertainty_pct) or (lower/upper) | explicit lower bound; this is the cell the simulator reads",
  upper             = "one of (uncertainty_pct) or (lower/upper) | explicit upper bound; this is the cell the simulator reads",
  param_type        = "yes | `activity_data` (only for `N`) or `coefficient`",
  ipcc_ref          = "no | citation, e.g. `Table 10.4`",
  data_source       = "yes | one of: `user_file`, `user_chat`, `ipcc_default`, `biological_zero`, `placeholder`")

.TP_MM_COL_NOTES <- c(
  cattle_type       = "yes | matches Parameters sheet",
  aggregation_level = "yes | matches Parameters sheet",
  sub_category      = "yes | matches Parameters sheet (auto-matched on upload if a near-spelling exists in Parameters, e.g. `DINT_heif` ↔ `DINT_heifer`)",
  mms_type          = "yes | controlled vocabulary (below)",
  fraction_pct      = "yes | % of manure to this MMS; rows per group must sum to 100",
  lower_fraction    = "no | min % for fraction_pct uncertainty (optional, enables per-MMS allocation sampling)",
  upper_fraction    = "no | max % for fraction_pct uncertainty",
  distribution_fraction = "no | distribution code for fraction_pct (default `pert`). Rows are renormalised per iteration so the simplex (sum = 100) is preserved.",
  MCF_pct           = "yes | methane conversion factor in PERCENT (e.g. 5 for 5 %) — see climate-zone table",
  lower_mcf         = "no | for asymmetric ranges, percent",
  upper_mcf         = "no | for asymmetric ranges, percent",
  distribution_mcf  = "no | distribution code for MCF",
  EF3               = "yes | direct N₂O EF (kg N₂O-N/kg N) for this MMS, a FRACTION (e.g. 0.01)",
  lower_ef3         = "no | ",
  upper_ef3         = "no | ",
  distribution_ef3  = "no | ",
  Frac_GasMS_pct    = "yes | per-MMS volatilisation fraction in PERCENT (e.g. 45) — defaults from IPCC 2019 Table 10.22",
  lower_frac_gas    = "no | percent",
  upper_frac_gas    = "no | percent",
  distribution_frac_gas = "no | ",
  Frac_LeachMS_pct  = "yes | per-MMS leaching fraction in PERCENT (e.g. 2) — defaults from IPCC 2019 Table 10.22",
  lower_frac_leach  = "no | percent",
  upper_frac_leach  = "no | percent",
  distribution_frac_leach = "no | ")

.tp_col_table <- function(cols, notes) {
  out <- c("| col | header | required? | notes |", "|-----|--------|-----------|-------|")
  for (i in seq_along(cols)) {
    n <- notes[cols[i]]
    if (is.na(n)) n <- "no | "
    parts <- strsplit(n, " | ", fixed = TRUE)[[1]]
    out <- c(out, sprintf("| %s | %s | %s | %s |", .tp_col_letter(i), cols[i],
                          parts[1], if (length(parts) > 1) parts[2] else ""))
  }
  out
}
.tp_col_letter <- function(i) {
  # 1 -> A, 26 -> Z, 27 -> AA
  s <- ""
  while (i > 0) { r <- (i - 1) %% 26; s <- paste0(LETTERS[r + 1], s); i <- (i - 1) %/% 26 }
  s
}

build_template_schema_md <- function(partials_dir = .TP_PARTIALS_DIR) {
  lines <- c(
    "# Template schema", "",
    "The app expects an `.xlsx` workbook with the sheets and columns below.",
    "Sheet names and column headers are **case-sensitive and must match exactly**.",
    "",
    "## Workbook overview", "",
    "| sheet | required? | purpose |",
    "|-------|-----------|---------|",
    "| `_Lists` | optional (hidden) | dropdown vocabularies — created automatically when the user downloads the blank template; safe to omit when you (Claude) build a workbook from scratch |",
    "| `README` | optional | human-readable quick-start — safe to omit |",
    "| `Inventory_Metadata` | **required** | country, region, year, IPCC version, species |",
    sprintf("| `Parameters` | **required** | the %d parameters per cattle sub-category |", nrow(PARAM_CATALOGUE)),
    "| `Manure_Management` | **required** | per-MMS allocation; per-group fractions must sum to 100% |",
    "| `Parameter_TimeSeries` | optional | 5+ years of annual values for auto-correlation |",
    "| `Vocab` | optional | reference catalogue — safe to omit |",
    "",
    "## Sheet: `Inventory_Metadata`", "",
    "Transposed (label/value) layout, one field per row starting at row 2. Column B is the label, column C is the value, column D a hint. The parser locates the value column by its header `Value`, so a workbook built from scratch may also use label in A and value in B.",
    "",
    "| label (column B) | field | value | notes |",
    "|-------|-------|-------|-------|")
  meta_notes <- c(
    country = "(free text) | e.g. `Zimbabwe`. Used in the report header.",
    region  = paste0("one of: ", paste(c("africa","asia","europe","americas","oceania","global"), collapse = " / "),
                     " | Continental region — drives the BW plausibility benchmark (IPCC Vol.4 Ch.10 Annex 10A.1/10A.2). Always set it from the country; never leave it to default."),
    inventory_year = "(integer) | e.g. `2022`",
    species = paste0("one of: ", paste(SPECIES_OPTIONS, collapse = " / "), " | controlled vocabulary"),
    ipcc_version = paste0("one of: ", paste(IPCC_VERSIONS, collapse = " / "), " | drives MMS list filtering and the edition-specific Ym"),
    prepared_by = "(free text) | name / institution",
    notes = "(free text) | optional; the translator appends its provenance stamp here")
  for (i in seq_len(nrow(TEMPLATE_META_FIELDS))) {
    f <- TEMPLATE_META_FIELDS$col[i]
    parts <- strsplit(meta_notes[[f]], " | ", fixed = TRUE)[[1]]
    lines <- c(lines, sprintf("| %s | `%s` | %s | %s |", TEMPLATE_META_FIELDS$label[i], f,
                              parts[1], if (length(parts) > 1) parts[2] else ""))
  }

  lines <- c(lines, "",
    "## Sheet: `Parameters`", "",
    "Banner in row 1, legend in row 2, header row in row 3. Data starts at row 4. One row per (cattle_type × aggregation_level × sub_category × parameter).",
    "",
    .tp_col_table(TEMPLATE_P_COLS, .TP_P_COL_NOTES),
    "",
    "### Sub-category codes (ANIMAL_SUBCATEGORIES)", "")
  for (k in seq_along(ANIMAL_SUBCATEGORIES))
    lines <- c(lines, sprintf("- `%s` — %s", ANIMAL_SUBCATEGORIES[k],
                              ANIMAL_SUBCATEGORY_LABELS[ANIMAL_SUBCATEGORIES[k]]))

  lines <- c(lines, "",
    "## Sheet: `Manure_Management`", "",
    "Banner in row 1, header row in row 2, hints in row 3. Data starts at row 4. One row per (cattle_type × aggregation_level × sub_category × mms_type). Per-group rows must sum to fraction_pct = 100.",
    "",
    "Units on this sheet: `fraction_pct`, `MCF_pct`, `Frac_GasMS_pct` and `Frac_LeachMS_pct` are PERCENTAGES (5 means 5 %). `EF3` is a FRACTION (0.01). Never write an MCF as 0.05 to mean 5 %.",
    "",
    .tp_col_table(TEMPLATE_MM_COLS, .TP_MM_COL_NOTES),
    "",
    "### MMS types — by IPCC version", "",
    "| id | label | 2006? | 2019R? | MCF trop.moist | MCF trop.dry | MCF temperate | MCF boreal | EF3 |",
    "|----|-------|-------|--------|----------------|--------------|---------------|------------|-----|")
  mms <- MMS_DEFAULTS
  for (i in seq_len(nrow(mms))) {
    vs <- strsplit(mms$versions[i], ",")[[1]]
    lines <- c(lines, sprintf("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |",
      mms$id[i], mms$label[i],
      if ("2006" %in% vs) "✓" else "", if ("2019" %in% vs) "✓" else "",
      .tp_fmt_num(mms$mcf_tropical[i]), .tp_fmt_num(mms$mcf_tropical_dry[i]),
      .tp_fmt_num(mms$mcf_temperate[i]), .tp_fmt_num(mms$mcf_boreal[i]),
      .tp_fmt_num(mms$ef3[i])))
  }
  mfd <- MMS_FRAC_DEFAULTS_2019
  lines <- c(lines, "",
    "### Per-MMS volatilisation & leaching defaults (IPCC 2019 Refinement)", "",
    "Use these when filling Frac_GasMS_pct and Frac_LeachMS_pct. The table gives FRACTIONS; multiply by 100 for the sheet.",
    "",
    "| mms_type | Frac_Gas (mean / low / high) | Frac_Leach (mean / low / high) |",
    "|----------|------------------------------|--------------------------------|")
  for (i in seq_len(nrow(mfd))) {
    lines <- c(lines, sprintf("| `%s` | %s / %s / %s | %s / %s / %s |",
      mfd$mms_type[i],
      .tp_fmt_num(mfd$frac_gas[i]),   .tp_fmt_num(mfd$frac_gas_low[i]),   .tp_fmt_num(mfd$frac_gas_high[i]),
      .tp_fmt_num(mfd$frac_leach[i]), .tp_fmt_num(mfd$frac_leach_low[i]), .tp_fmt_num(mfd$frac_leach_high[i])))
  }

  ts_params <- setdiff(TEMPLATE_TS_COLS, c("cattle_type","aggregation_level","sub_category","year"))
  lines <- c(lines, "",
    "## Sheet: `Parameter_TimeSeries` (optional)", "",
    "Banner in row 1, header row in row 2, description in row 3, units in row 4. Data starts at row 5. Annual values, used to compute Spearman-rank correlations between activity-data parameters. Minimum 5 years (or 4 if first-difference detrending is used).",
    "",
    "| col | header | notes |",
    "|-----|--------|-------|",
    "| A | cattle_type | optional — blank = applies to all groups |",
    "| B | aggregation_level | optional |",
    "| C | sub_category | optional |",
    "| D | year | required (integer) |",
    sprintf("| %s–%s | %s | the %d parameters the app correlates; leave columns blank for parameters not measured |",
            .tp_col_letter(5), .tp_col_letter(length(TEMPLATE_TS_COLS)),
            paste(ts_params, collapse = ", "), length(ts_params)),
    "",
    "## Validation rules the app applies", "",
    "These are the checks Claude should run before declaring the workbook ready:", "",
    "- **bounds**: `lower ≤ value ≤ upper` for every Parameters row (exception: when `distribution = constant` and all three = 0, e.g. WG for adults, hours for non-working cattle)",
    "- **N ≥ 0** (cattle population can't be negative)",
    "- **DE ∈ [0, 100]**, **Ym > 0**, Parameters-sheet fractions (`pct_pregnant`, `ASH`, `UE`, `Frac_GASM_PRP`, `Frac_LEACH_PRP`) ∈ [0, 1]; Manure_Management percentages ∈ [0, 100]",
    "- **distribution** ∈ DISTRIBUTION_TYPES",
    "- **param_type** ∈ {`activity_data`, `coefficient`}",
    "- **Manure_Management**: per (cattle_type, aggregation_level, sub_category), `fraction_pct` central values sum to 100 ± 1 (bounds may widen; the app renormalises each Monte Carlo iteration to preserve the simplex when `lower_fraction` / `upper_fraction` are supplied)",
    "- **Manure_Management**: `lower_fraction ≤ fraction_pct ≤ upper_fraction` for every row that supplies the uncertainty columns; blank = deterministic",
    "- **Manure_Management**: `sub_category` should match the Parameters sheet exactly. Near-spellings (e.g. `DINT_heif` vs `DINT_heifer`) are auto-matched on upload and shown as a `warn` row in the QAQC tab; multi-candidate ambiguity blocks the run",
    "- **Manure_Management**: mms_type must be a valid id for the selected IPCC version",
    "- **Inventory_Metadata.species** ∈ SPECIES_OPTIONS; **ipcc_version** ∈ IPCC_VERSIONS",
    "",
    "## Distribution choice guide", "",
    "When the user gives you a value but no distribution, pick from this priority list:", "",
    sprintf("1. If the parameter has an asymmetric IPCC range (%s) → use **`lognormal`** or **`pert`** with the absolute bounds from the asymmetric table in param_catalogue.md.",
            paste0("`", paste(PARAM_CATALOGUE$parameter[!is.na(PARAM_CATALOGUE$suggested_lower_bound) | !is.na(PARAM_CATALOGUE$suggested_upper_bound)], collapse = "`, `"), "`")),
    "2. If the parameter is a fraction bounded in [0, 1] (pct_pregnant, ASH, UE, manure fractions) → **`beta`** or **`tnorm_0_1`**.",
    "3. If the central value comes from a measured mean ± SD or ±CV → **`normal`**.",
    "4. If only min / mode / max are known (expert judgement) → **`pert`** (preferred) or **`triangular`**.",
    "5. If the parameter is structurally constant (WG = 0 for adults, hours = 0 for non-working cattle) → **`constant`**, lower = value = upper.",
    "")
  lines
}

# ---- 3. worked_example.md ---------------------------------------------------

.WE_SUBCATS <- c("dairy_cows", "heifers")
.WE_USER <- list(
  dairy_cows = c(N = 12000, BW = 420, MW = 450, Milk = 8.5, Fat = 4.0, DE = 62, CP = 14),
  heifers    = c(N = 3000,  BW = 250, MW = 450, DE = 58, CP = 12))
.WE_MMS <- list(
  dairy_cows = c(pasture = 30, solid_storage = 50, daily_spread = 15, liquid_slurry = 5),
  heifers    = c(pasture = 70, solid_storage = 25, daily_spread = 5))
.WE_IPCC_VERSION <- "2019_refinement"

.we_num <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("null")
  old <- options(OutDec = "."); on.exit(options(old), add = TRUE)
  trimws(format(x, scientific = FALSE, trim = TRUE, drop0trailing = TRUE, digits = 12))
}

build_worked_example_md <- function(partials_dir = .TP_PARTIALS_DIR) {
  pc <- PARAM_CATALOGUE; NPAR <- nrow(pc)
  we <- c("# Worked example -- complete template-ready JSON for a small inventory",
          "", .tp_partial("worked_example_intro", partials_dir), "",
          sprintf("This example has %d sub-categories, so %d x %d = %d parameter rows. An inventory with 8 sub-categories would need 8 x %d = %d.",
                  length(.WE_SUBCATS), length(.WE_SUBCATS), NPAR,
                  length(.WE_SUBCATS) * NPAR, NPAR, 8 * NPAR),
          "", "```template-ready", "{",
          '  "inventory_metadata": {',
          '    "country": "Country Z", "region": "asia", "year": 2023, "species": "cattle_dairy",',
          sprintf('    "ipcc_version": "%s", "prepared_by": "National Inventory Team"', .WE_IPCC_VERSION),
          "  },", '  "parameters": [')
  prow <- character(0)
  for (sc in .WE_SUBCATS) {
    usr <- .WE_USER[[sc]]
    for (prm in pc$parameter) {
      rs <- resolve_subcat_default(sc, prm, .WE_IPCC_VERSION)
      is_user <- prm %in% names(usr)
      val  <- if (is_user) usr[[prm]] else if (!is.null(rs)) rs$value else NA_real_
      dist <- if (!is.null(rs)) rs$distribution else pc$suggested_distribution[pc$parameter == prm]
      lo <- if (!is.null(rs)) rs$lower else pc$suggested_lower_bound[pc$parameter == prm]
      hi <- if (!is.null(rs)) rs$upper else pc$suggested_upper_bound[pc$parameter == prm]
      unc <- if (!is.null(rs)) rs$uncertainty_pct else pc$suggested_uncertainty_pct[pc$parameter == prm]
      asym <- is.na(unc) && !is.na(lo) && !is.na(hi)
      spread <- if (asym) sprintf('"lower": %s, "upper": %s', .we_num(lo), .we_num(hi))
                else sprintf('"uncertainty_pct": %s', .we_num(unc))
      src <- if (is_user) "user_file" else if (!is.null(rs) && identical(rs$data_source, "biological_zero"))
               "biological_zero" else "ipcc_default"
      prow <- c(prow, sprintf(
        '    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "%s", "parameter": "%s", "mean": %s, %s, "distribution": "%s", "param_type": "%s", "data_source": "%s"}',
        sc, prm, .we_num(val), spread, dist, pc$param_type[pc$parameter == prm], src))
    }
  }
  we <- c(we, paste0(prow, c(rep(",", length(prow) - 1), "")), "  ],", '  "manure_management": [')
  mrow <- character(0)
  for (sc in .WE_SUBCATS) {
    alloc <- .WE_MMS[[sc]]
    for (id in names(alloc)) {
      row <- MMS_DEFAULTS[MMS_DEFAULTS$id == id, ]
      fr  <- mms_frac_defaults_2019(id)
      mrow <- c(mrow, sprintf(
        '    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "%s", "mms_type": "%s", "fraction_pct": %s, "MCF_pct": %s, "EF3": %s, "Frac_GasMS_pct": %s, "Frac_LeachMS_pct": %s}',
        sc, id, .we_num(unname(alloc[[id]])), .we_num(row$mcf_tropical),
        .we_num(row$ef3), .we_num(fr$frac_gas * 100), .we_num(fr$frac_leach * 100)))
    }
  }
  we <- c(we, paste0(mrow, c(rep(",", length(mrow) - 1), "")),
          "  ],", '  "parameter_timeseries": []', "}", "```", "",
          .tp_partial("worked_example_outro", partials_dir))
  # The example must parse; a generator bug here would teach the model a
  # broken shape.
  inner <- we[(which(we == "```template-ready") + 1):(which(we == "```")[1] - 1)]
  stopifnot(!is.null(jsonlite::fromJSON(paste(inner, collapse = "\n"))))
  we
}

# ---- 4. Placeholders in the hand-written prompt files -----------------------
#
# system_instructions.md and mapping_examples.md are prose and must stay
# hand-written, but they used to carry literal defaults (0.52, 0.54, 0.5,
# the Cfi and C self-check values) that went stale. They now carry tokens:
#
#   {{default:PARAM}}          the catalogue default of PARAM
#   {{default:PARAM:SUBCAT}}   the resolver's value for SUBCAT
#   {{unc:PARAM}}              the catalogue suggested uncertainty %
#   {{n_params}}               nrow(PARAM_CATALOGUE)
#   {{params}}                 the comma-separated parameter codes
#   {{subcats}}                the comma-separated sub-category codes
#   {{subcats_non_dairy}}      the same minus dairy_cows
#
# An unknown token is a hard error at assembly time rather than a silent
# literal "{{...}}" in the prompt.
translator_prompt_fill_placeholders <- function(txt) {
  fill_one <- function(tok) {
    parts <- strsplit(tok, ":", fixed = TRUE)[[1]]
    switch(parts[1],
      "n_params" = as.character(nrow(PARAM_CATALOGUE)),
      "params"   = paste(PARAM_CATALOGUE$parameter, collapse = ", "),
      "subcats"  = paste(ANIMAL_SUBCATEGORIES, collapse = ", "),
      "subcats_non_dairy" = paste(setdiff(ANIMAL_SUBCATEGORIES, "dairy_cows"), collapse = ", "),
      "default"  = {
        if (length(parts) == 2) .tp_fmt_num(.cat_default(parts[2]))
        else {
          rs <- resolve_subcat_default(parts[3], parts[2])
          if (is.null(rs)) stop("placeholder {{", tok, "}}: unknown parameter", call. = FALSE)
          .tp_fmt_num(rs$value)
        }
      },
      "unc" = .tp_fmt_num(PARAM_CATALOGUE$suggested_uncertainty_pct[PARAM_CATALOGUE$parameter == parts[2]]),
      stop("unknown prompt placeholder {{", tok, "}}", call. = FALSE))
  }
  m <- gregexpr("\\{\\{[A-Za-z0-9_:]+\\}\\}", txt, perl = TRUE)
  toks <- unique(unlist(regmatches(txt, m)))
  for (t in toks) {
    inner <- sub("^\\{\\{", "", sub("\\}\\}$", "", t))
    txt <- gsub(t, fill_one(inner), txt, fixed = TRUE)
  }
  txt
}

# ---- 5. Memoised access for the runtime prompt ------------------------------

.TP_MEMO <- new.env(parent = emptyenv())

# The generated sections change only when the master or the template layout
# changes, both of which need a process restart to reach the R objects, so a
# per-process memo is exact. `translator_prompt_reset()` clears it for tests.
translator_generated_section <- function(name, partials_dir = .TP_PARTIALS_DIR) {
  key <- paste(name, partials_dir, sep = "|")
  if (!is.null(.TP_MEMO[[key]])) return(.TP_MEMO[[key]])
  out <- switch(name,
    param_catalogue = build_param_catalogue_md(partials_dir),
    template_schema = build_template_schema_md(partials_dir),
    worked_example  = build_worked_example_md(partials_dir),
    stop("no generator for translator prompt section '", name, "'", call. = FALSE))
  .TP_MEMO[[key]] <- paste(out, collapse = "\n")
  .TP_MEMO[[key]]
}
translator_prompt_reset <- function() rm(list = ls(.TP_MEMO), envir = .TP_MEMO)

# ---- 6. Fingerprints ---------------------------------------------------------

.tp_sha256 <- function(x) {
  if (length(x) > 1) x <- paste(x, collapse = "\n")
  paste(as.character(openssl::sha256(charToRaw(enc2utf8(x)))), collapse = "")
}

# What the generated prompt depends on: the master (every default) and the
# workbook layout (every column the model is told about).
translator_prompt_inputs_hash <- function(master_path = "reference/defaults_master.csv") {
  master <- if (file.exists(master_path)) readLines(master_path, warn = FALSE, encoding = "UTF-8") else ""
  list(
    master_sha256 = .tp_sha256(master),
    layout_sha256 = .tp_sha256(c(TEMPLATE_P_COLS, "|", TEMPLATE_MM_COLS, "|", TEMPLATE_TS_COLS, "|",
                                 TEMPLATE_META_FIELDS$col, "|", TEMPLATE_META_FIELDS$label)))
}

# Written by scripts/build_translator_kit.R next to the generated files;
# checked by audit F46 and by scripts/deploy.R.
translator_prompt_manifest <- function(out_dir = "translator_prompts") {
  inp <- translator_prompt_inputs_hash()
  gen <- c("param_catalogue.md", "template_schema.md", "worked_example.md")
  files <- lapply(gen, function(f) {
    p <- file.path(out_dir, f)
    list(file = f, sha256 = if (file.exists(p)) .tp_sha256(readLines(p, warn = FALSE, encoding = "UTF-8")) else NA_character_)
  })
  list(master_sha256 = inp$master_sha256, layout_sha256 = inp$layout_sha256,
       generated = files,
       commit = tryCatch(trimws(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)),
                         error = function(e) NA_character_))
}

# TRUE when the committed generated files match what the live objects would
# produce now. Compares content, not the manifest, so it catches a hand edit
# as well as a forgotten rebuild.
translator_prompt_files_current <- function(out_dir = "translator_prompts") {
  gen <- c(param_catalogue = "param_catalogue.md", template_schema = "template_schema.md",
           worked_example = "worked_example.md")
  stale <- character(0)
  for (nm in names(gen)) {
    p <- file.path(out_dir, gen[[nm]])
    on_disk <- if (file.exists(p)) paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n") else ""
    live <- paste(switch(nm,
      param_catalogue = build_param_catalogue_md(file.path(out_dir, "partials")),
      template_schema = build_template_schema_md(file.path(out_dir, "partials")),
      worked_example  = build_worked_example_md(file.path(out_dir, "partials"))), collapse = "\n")
    if (!identical(enc2utf8(on_disk), enc2utf8(live))) stale <- c(stale, gen[[nm]])
  }
  list(ok = length(stale) == 0L, stale = stale)
}
