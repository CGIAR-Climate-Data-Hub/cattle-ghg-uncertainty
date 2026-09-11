# =============================================================================
# Build the knowledge files for the in-app GMH Uncertainty Translator
# =============================================================================
# Reads PARAM_CATALOGUE, PARAM_ALIASES, MMS_DEFAULTS and controlled vocabularies
# from the live R source and emits Markdown knowledge files into
# translator_prompts/. These .md files are concatenated at runtime by
# R/openai_client.R::assemble_translator_system_prompt() into the system
# prompt sent to Anthropic Claude (see R/anthropic_client.R; the "GPT-4.1"
# in older comments here is stale).
#
# Usage (from project root):
#   Rscript scripts/build_translator_kit.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

# --- Regeneration is safe -----------------------------------------------------
#
# This script was frozen between 2026-09-10 and 2026-09-11 because it destroyed
# hand-added prompt content on every run. It no longer does. Every factual table
# in the generated files is now built from the R constants, and the prose that
# used to be hand-edited into the output lives in translator_prompts/partials/
# and is read back in. A missing partial is a hard error rather than a silently
# shorter prompt.
#
# Rule for maintainers: NEVER hand-edit translator_prompts/param_catalogue.md or
# template_schema.md. Change the R constants for numbers, or the partials for
# prose, then re-run this script.
# -----------------------------------------------------------------------------

suppressMessages({
  source("R/utils_template.R", local = FALSE)
  source("R/utils_validation.R", local = FALSE)
  source("R/utils_ipcc_defaults.R", local = FALSE)
})

out_dir <- "translator_prompts"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

stamp <- format(Sys.Date(), "%Y-%m-%d")

# ---------------------------------------------------------------------------
# 1. param_catalogue.md  -- the IPCC-aligned parameters with everything
# Claude needs to map a raw column to a template field.
# ---------------------------------------------------------------------------
fmt_num <- function(x) {
  if (is.na(x)) "" else if (x == 0) "0" else format(x, scientific = FALSE,
                                                      drop0trailing = TRUE)
}

# Build alias index: parameter -> aliases pointing to it
alias_to <- function(canonical) {
  hits <- names(PARAM_ALIASES)[PARAM_ALIASES == canonical]
  if (length(hits) == 0) "(none)" else paste(hits, collapse = ", ")
}

pc <- PARAM_CATALOGUE
NPAR <- nrow(pc)

# Hand-maintained prose lives in translator_prompts/partials/. Numbers never do:
# every table in the generated files is built from the R constants above, so a
# regeneration cannot reintroduce a stale value. A missing partial is a hard
# error, so a deleted file fails the build instead of silently shrinking the
# prompt the model receives.
# Strip HTML comments as BLOCKS. The first version of this filtered per line
# ("starts with <!--" OR "ends with -->"), which kept every MIDDLE line of a
# multi-line comment. Two such lines were emitted into param_catalogue.md as
# the lead line of a section and shipped in translator_kit.zip. A 4-line
# comment would have leaked 2. Do not simplify this back to a line filter.
.strip_html_comments <- function(txt) {
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

partial <- function(name) {
  f <- file.path(out_dir, "partials", paste0(name, ".md"))
  if (!file.exists(f)) stop("missing prompt partial: ", f, call. = FALSE)
  txt <- .strip_html_comments(readLines(f, warn = FALSE, encoding = "UTF-8"))
  trimws(paste(txt, collapse = "
"))
}

.read_keyed <- function(fname, required = TRUE) {
  f <- file.path(out_dir, "partials", fname)
  if (!file.exists(f)) {
    if (required) stop("missing prompt partial: ", f, call. = FALSE) else return(list())
  }
  # Comment-strip here too: a <!-- --> inside a keyed section would otherwise
  # be emitted verbatim into a markdown table cell.
  ln <- .strip_html_comments(readLines(f, warn = FALSE, encoding = "UTF-8"))
  # Paragraphs are joined with a single space deliberately: every consumer of
  # a keyed partial renders it into ONE markdown table cell, where a newline
  # would break the table.
  idx <- grep("^## ", ln); out <- list()
  for (k in seq_along(idx)) {
    key <- sub("^## ", "", ln[idx[k]])
    to  <- if (k < length(idx)) idx[k + 1] - 1 else length(ln)
    out[[key]] <- trimws(paste(ln[(idx[k] + 1):to], collapse = " "))
  }
  out
}

# Translator-facing definition overrides, deliberately richer than the app's.
.defs <- .read_keyed("definition_overrides.md")
local({
  bad <- setdiff(names(.defs), pc$parameter)
  if (length(bad)) stop("definition_overrides.md names unknown parameters: ",
                        paste(bad, collapse = ", "), call. = FALSE)
})
def_for <- function(prm) if (!is.null(.defs[[prm]])) .defs[[prm]] else
  pc$definition[pc$parameter == prm]

lines <- c(
  "# Parameter catalogue",
  "",
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
    pc$parameter[i],
    pc$param_tier[i],
    pc$param_type[i],
    pc$unit[i],
    fmt_num(pc$ipcc_default[i]),
    if (is.na(pc$suggested_uncertainty_pct[i])) "(asymmetric — use bounds)"
      else paste0(pc$suggested_uncertainty_pct[i], "%"),
    pc$suggested_distribution[i],
    if (nzchar(pc$ipcc_ref[i])) pc$ipcc_ref[i] else "—",
    alias_to(pc$parameter[i]),
    gsub("\\|", "\\\\|", def_for(pc$parameter[i]))
  ))
}

# Asymmetric bounds detail
asym <- pc[!is.na(pc$suggested_lower_bound) | !is.na(pc$suggested_upper_bound), ]
if (nrow(asym) > 0) {
  lines <- c(lines, "",
    "## Asymmetric (non-symmetric) bounds",
    "",
    partial("asymmetric_bounds_note"),
    "",
    "| code | lower | central | upper |",
    "|------|-------|---------|-------|"
  )
  for (i in seq_len(nrow(asym))) {
    lines <- c(lines, sprintf("| `%s` | %s | %s | %s |",
      asym$parameter[i],
      fmt_num(asym$suggested_lower_bound[i]),
      fmt_num(asym$ipcc_default[i]),
      fmt_num(asym$suggested_upper_bound[i])
    ))
  }
}

# Sex- and physiology-specific coefficient overrides. The TABLE is generated
# from CFI_BY_SUBCAT / C_GROWTH_BY_SUBCAT so it cannot drift from what
# resolve_subcat_default() actually returns; only the prose is hand-written.
# This section is named by system_instructions.md self-check #9, so it must not
# disappear from a rebuild -- that was the bug that froze this script.
.rownotes <- .read_keyed("subcat_overrides_rownotes.md", required = FALSE)
lines <- c(lines, "",
  "## Sex- and physiology-specific coefficient overrides",
  "",
  partial("subcat_overrides_intro"),
  "",
  "| sub-category | Cfi (Table 10.4) | C (Eq 10.6) | notes |",
  "|---|---|---|---|")
for (sc in ANIMAL_SUBCATEGORIES) {
  cfi <- CFI_BY_SUBCAT[[sc]]; cg <- C_GROWTH_BY_SUBCAT[[sc]]
  lines <- c(lines, sprintf("| `%s` | %s | %s | %s |", sc,
    if (is.null(cfi)) "—" else fmt_num(cfi),
    if (is.null(cg))  "—" else fmt_num(cg),
    if (!is.null(.rownotes[[sc]])) gsub("\\|", "\\\\|", .rownotes[[sc]]) else ""))
}
lines <- c(lines, "",
  "`Ca` is not per-sub-category: it depends on the feeding situation (IPCC Table 10.5).",
  "",
  paste0("Values: ", paste(sprintf("%s = %s", names(FEEDING_SITUATION_CA),
         vapply(unlist(FEEDING_SITUATION_CA), fmt_num, character(1))), collapse = "; "), "."),
  "",
  partial("subcat_overrides_outro"))

# Tier explanation
lines <- c(lines, "",
  "## Tier meaning",
  "",
  "- **core** = user must provide a value (or accept the IPCC default). These are the activity-data parameters and a handful of high-impact coefficients (DE, CP, MilkPR).",
  "- **advanced** = IPCC equation coefficient. Pre-filled with the IPCC default from the column above; only override if the user has a country-specific measurement.",
  "",
  "## param_type",
  "",
  "- **activity_data** = `N` only (animal population). This is the one true activity-data variable.",
  "- **coefficient** = everything else (production parameters, energy/methane/N₂O coefficients).",
  "",
  "## Distribution codes accepted",
  "",
  paste("`", paste(DISTRIBUTION_TYPES, collapse = "`, `"), "`", sep = ""),
  "",
  "Use `pert` or `triangular` when only a mode + bounds are known; `normal` for symmetric ±% around a measured mean; `beta` or `tnorm_0_1` for fractions that must stay in [0, 1]; `lognormal` for strictly-positive values with right skew (typical for emission factors)."
)

writeLines(lines, file.path(out_dir, "param_catalogue.md"), useBytes = TRUE)
message("✓ wrote param_catalogue.md (", nrow(pc), " parameters)")

# ---------------------------------------------------------------------------
# 2. template_schema.md -- exact sheet/column layout + validation rules
# ---------------------------------------------------------------------------
lines <- c(
  "# Template schema",
  "",
  "The app expects an `.xlsx` workbook with the sheets and columns below.",
  "Sheet names and column headers are **case-sensitive and must match exactly**.",
  "",
  "## Workbook overview",
  "",
  "| sheet | required? | purpose |",
  "|-------|-----------|---------|",
  "| `_Lists` | optional (hidden) | dropdown vocabularies — created automatically when the user downloads the blank template; safe to omit when you (Claude) build a workbook from scratch |",
  "| `README` | optional | human-readable quick-start — safe to omit |",
  "| `Inventory_Metadata` | **required** | country, year, IPCC version, species |",
  sprintf("| `Parameters` | **required** | the %d parameters per cattle sub-category |", nrow(PARAM_CATALOGUE)),
  "| `Manure_Management` | **required** | per-MMS allocation; per-group fractions must sum to 100% |",
  "| `Parameter_TimeSeries` | optional | 5+ years of annual values for auto-correlation |",
  "| `Vocab` | optional | reference catalogue — safe to omit |",
  "",
  "## Sheet: `Inventory_Metadata`",
  "",
  "Transposed (label/value) layout. Column A is the label, column B is the value.",
  "",
  "| label | value | notes |",
  "|-------|-------|-------|",
  "| country | (free text) | e.g. `Zimbabwe`. Used in the report header. |",
  "| region | one of: africa / asia / europe / americas / oceania / global | Continental region — drives the BW deviation benchmark (IPCC Vol.4 Ch.10 Annex 10A.1/10A.2/10A.3). Dropdown-constrained in the latest template. Legacy uploads with only a single free-text country cell are auto-mapped by the parser. |",
  "| inventory_year | (integer) | e.g. `2022` |",
  paste0("| species | one of: ", paste(SPECIES_OPTIONS, collapse = " / "), " | controlled vocabulary |"),
  paste0("| ipcc_version | one of: ", paste(IPCC_VERSIONS, collapse = " / "), " | drives MMS list filtering |"),
  "| prepared_by | (free text) | name / institution |",
  "| notes | (free text) | optional |",
  "",
  "## Sheet: `Parameters`",
  "",
  "Header row in row 3. Data starts at row 4. One row per (cattle_type × aggregation_level × sub_category × parameter).",
  "",
  "| col | header | required? | notes |",
  "|-----|--------|-----------|-------|",
  "| A | cattle_type | yes | e.g. `dairy`, `non_dairy` |",
  "| B | aggregation_level | yes | free text label for the inventory grouping |",
  "| C | sub_category | yes | one of the ANIMAL_SUBCATEGORIES below (or free-text if the inventory uses custom groups) |",
  "| D | parameter | yes | the parameter code from param_catalogue.md |",
  "| E | definition | no | optional human label (mirrors param_catalogue) |",
  "| F | unit | no | optional unit (mirrors param_catalogue) |",
  "| G | value | yes | the central value — **the number the user is providing** |",
  "| H | uncertainty_pct | one of (H) or (I/J) | symmetric ±% half-width of 95% CI |",
  "| I | lower_bound | one of (H) or (I/J) | explicit lower bound (use for asymmetric params) |",
  "| J | upper_bound | one of (H) or (I/J) | explicit upper bound |",
  "| K | distribution | yes | one of the codes above |",
  "| L | lower | no | auto-computed from H or I; safe to leave blank |",
  "| M | upper | no | auto-computed from H or J; safe to leave blank |",
  "| N | param_type | yes | `activity_data` (only for `N`) or `coefficient` |",
  "| O | ipcc_ref | no | citation, e.g. `Table 10.4` |",
  "| P | data_source | no | one of: `user_file`, `user_chat`, `ipcc_default`, `biological_zero` |",
  "",
  "### Sub-category codes (ANIMAL_SUBCATEGORIES)",
  ""
)
for (k in seq_along(ANIMAL_SUBCATEGORIES)) {
  lines <- c(lines, sprintf("- `%s` — %s",
    ANIMAL_SUBCATEGORIES[k], ANIMAL_SUBCATEGORY_LABELS[ANIMAL_SUBCATEGORIES[k]]))
}

lines <- c(lines, "",
  "## Sheet: `Manure_Management`",
  "",
  "One row per (cattle_type × aggregation_level × sub_category × mms_type). Per-group rows must sum to fraction_pct = 100.",
  "",
  "| col | header | required? | notes |",
  "|-----|--------|-----------|-------|",
  "| A | cattle_type | yes | matches Parameters sheet |",
  "| B | aggregation_level | yes | matches Parameters sheet |",
  "| C | sub_category | yes | matches Parameters sheet (auto-matched on upload if a near-spelling exists in Parameters, e.g. `DINT_heif` ↔ `DINT_heifer`) |",
  "| D | mms_type | yes | controlled vocabulary (below) |",
  "| E | fraction_pct | yes | % of manure to this MMS; rows per group must sum to 100 |",
  "| F | lower_fraction | no | min % for fraction_pct uncertainty (optional, enables per-MMS allocation sampling) |",
  "| G | upper_fraction | no | max % for fraction_pct uncertainty (optional, enables per-MMS allocation sampling) |",
  "| H | distribution_fraction | no | distribution code for fraction_pct (default `pert`). Rows are renormalised per iteration so the simplex (sum = 100) is preserved. |",
  "| I | MCF_pct | yes | methane conversion factor (%) — see climate-zone lookup |",
  "| J | lower_mcf | no | for asymmetric ranges |",
  "| K | upper_mcf | no | for asymmetric ranges |",
  "| L | distribution_mcf | no | distribution code for MCF |",
  "| M | EF3 | yes | direct N₂O EF (kg N₂O-N/kg N) for this MMS |",
  "| N | lower_ef3 | no | |",
  "| O | upper_ef3 | no | |",
  "| P | distribution_ef3 | no | |",
  "| Q | Frac_GasMS_pct | no | per-MMS volatilisation fraction (%) — defaults from IPCC 2019 Table 10.22 |",
  "| R | lower_frac_gas | no | |",
  "| S | upper_frac_gas | no | |",
  "| T | distribution_frac_gas | no | |",
  "| U | Frac_LeachMS_pct | no | per-MMS leaching fraction (%) — defaults from IPCC 2019 Table 10.22 |",
  "| V | lower_frac_leach | no | |",
  "| W | upper_frac_leach | no | |",
  "| X | distribution_frac_leach | no | |",
  "",
  "### MMS types — by IPCC version",
  ""
)
mms <- MMS_DEFAULTS
lines <- c(lines, "| id | label | 2006? | 2019R? | MCF trop.moist | MCF trop.dry | MCF temperate | MCF boreal | EF3 |",
  "|----|-------|-------|--------|----------------|--------------|---------------|------------|-----|")
for (i in seq_len(nrow(mms))) {
  vs <- strsplit(mms$versions[i], ",")[[1]]
  lines <- c(lines, sprintf("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |",
    mms$id[i], mms$label[i],
    if ("2006" %in% vs) "✓" else "",
    if ("2019" %in% vs) "✓" else "",
    fmt_num(mms$mcf_tropical[i]),
    fmt_num(mms$mcf_tropical_dry[i]),
    fmt_num(mms$mcf_temperate[i]),
    fmt_num(mms$mcf_boreal[i]),
    fmt_num(mms$ef3[i])
  ))
}

# Per-MMS Frac_Gas / Frac_Leach defaults (2019R)
mfd <- MMS_FRAC_DEFAULTS_2019
lines <- c(lines, "",
  "### Per-MMS volatilisation & leaching defaults (IPCC 2019 Refinement)",
  "",
  "Use these when filling Frac_GasMS_pct and Frac_LeachMS_pct.",
  "",
  "| mms_type | Frac_Gas (mean / low / high) | Frac_Leach (mean / low / high) |",
  "|----------|------------------------------|--------------------------------|"
)
for (i in seq_len(nrow(mfd))) {
  lines <- c(lines, sprintf("| `%s` | %s / %s / %s | %s / %s / %s |",
    mfd$mms_type[i],
    fmt_num(mfd$frac_gas[i]),  fmt_num(mfd$frac_gas_low[i]),  fmt_num(mfd$frac_gas_high[i]),
    fmt_num(mfd$frac_leach[i]),fmt_num(mfd$frac_leach_low[i]),fmt_num(mfd$frac_leach_high[i])
  ))
}

lines <- c(lines, "",
  "## Sheet: `Parameter_TimeSeries` (optional)",
  "",
  "Annual values, used to compute Spearman-rank correlations between activity-data parameters. Minimum 5 years (or 4 if first-difference detrending is used).",
  "",
  "| col | header | notes |",
  "|-----|--------|-------|",
  "| A | cattle_type | optional — blank = applies to all groups |",
  "| B | aggregation_level | optional |",
  "| C | sub_category | optional |",
  "| D | year | required (integer) |",
  "| E–N | N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, CP, MilkPR | the 10 parameters the app correlates; leave columns blank for parameters not measured |",
  "",
  "## Validation rules the app applies",
  "",
  "These are the checks Claude should run before declaring the workbook ready:",
  "",
  "- **bounds**: `lower ≤ value ≤ upper` for every Parameters row (exception: when `distribution = constant` and all three = 0, e.g. WG for adults, hours for non-working cattle)",
  "- **N ≥ 0** (cattle population can't be negative)",
  "- **DE ∈ [0, 100]**, **Ym > 0**, fractions (`Frac_*`, `pct_pregnant`, `ASH`, `UE`) ∈ [0, 1]",
  "- **distribution** ∈ DISTRIBUTION_TYPES",
  "- **param_type** ∈ {`activity_data`, `coefficient`}",
  "- **Manure_Management**: per (cattle_type, aggregation_level, sub_category), `fraction_pct` central values sum to 100 ± 1 (bounds may widen; the app renormalises each Monte Carlo iteration to preserve the simplex when `lower_fraction` / `upper_fraction` are supplied)",
  "- **Manure_Management**: `lower_fraction ≤ fraction_pct ≤ upper_fraction` for every row that supplies the uncertainty columns; blank = deterministic",
  "- **Manure_Management**: `sub_category` should match the Parameters sheet exactly. Near-spellings (e.g. `DINT_heif` vs `DINT_heifer`) are auto-matched on upload and shown as a `warn` row in the QAQC tab; multi-candidate ambiguity blocks the run",
  "- **Manure_Management**: mms_type must be a valid id for the selected IPCC version",
  "- **Inventory_Metadata.species** ∈ SPECIES_OPTIONS; **ipcc_version** ∈ IPCC_VERSIONS",
  "",
  "## Distribution choice guide",
  "",
  "When the user gives you a value but no distribution, pick from this priority list:",
  "",
  sprintf("1. If the parameter has an asymmetric IPCC range (%s) → use **`lognormal`** or **`pert`** with the absolute bounds from the asymmetric table in param_catalogue.md.", paste0("`", paste(PARAM_CATALOGUE$parameter[!is.na(PARAM_CATALOGUE$suggested_lower_bound) | !is.na(PARAM_CATALOGUE$suggested_upper_bound)], collapse = "`, `"), "`")),
  "2. If the parameter is a fraction bounded in [0, 1] (pct_pregnant, ASH, UE, manure fractions) → **`beta`** or **`tnorm_0_1`**.",
  "3. If the central value comes from a measured mean ± SD or ±CV → **`normal`**.",
  "4. If only min / mode / max are known (expert judgement) → **`pert`** (preferred) or **`triangular`**.",
  "5. If the parameter is structurally constant (WG = 0 for adults, hours = 0 for non-working cattle) → **`constant`**, lower = value = upper.",
  ""
)

writeLines(lines, file.path(out_dir, "template_schema.md"), useBytes = TRUE)
message("✓ wrote template_schema.md")

# ---------------------------------------------------------------------------
# 3. Stage user-facing assets into www/ so the Shiny app can serve them.
# Only the files end-users need to download go to www/ — system_instructions.md
# and the README stay in translator_prompts/ for the maintainer.
# ---------------------------------------------------------------------------
www_dir <- "www"
if (!dir.exists(www_dir)) dir.create(www_dir, recursive = TRUE)
# system_instructions.md is staged too — users paste it into the "Instructions"
# field of their own Claude Project (DIY-kit flow). The other four .md files
# are the project knowledge.
# worked_example.md is 5th in the live system prompt (openai_client.R:32-34) but
# was historically absent from both www/ and the kit, so DIY-kit users ran a
# materially different translator from the in-app one. Ship it.
user_facing <- c("system_instructions.md",
                 "questionnaire.md", "getting_started.md",
                 "param_catalogue.md", "template_schema.md",
                 "mapping_examples.md", "worked_example.md")
for (f in user_facing) {
  src <- file.path(out_dir, f)
  dst <- file.path(www_dir, f)
  if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
}
message("✓ staged ", length(user_facing), " files into ", www_dir, "/")

# ---------------------------------------------------------------------------
# 3b. Render the user-facing .Rmd files (getting_started.Rmd, questionnaire.Rmd)
# to PDF + DOCX via rmarkdown::render(). The .Rmd files carry the same polished
# CGIAR-green LaTeX styling as user_guide.Rmd and methodology.Rmd. Outputs are
# staged in translator_prompts/ (canonical) and copied to www/ (served by
# Shiny). Needs: `rmarkdown` package + a LaTeX install (MiKTeX/TinyTeX) for
# pdflatex.
# ---------------------------------------------------------------------------
# Locate a LaTeX engine. R's child-process PATH doesn't always include
# MiKTeX/TinyTeX even when the shell does, so we also check the usual Windows
# install dirs.
find_xelatex <- function() {
  hit <- Sys.which("xelatex")
  if (nzchar(hit) && file.exists(hit)) return(unname(hit))
  candidates <- c(
    file.path(Sys.getenv("LOCALAPPDATA"),
              "Programs/MiKTeX/miktex/bin/x64/xelatex.exe"),
    file.path(Sys.getenv("APPDATA"),
              "TinyTeX/bin/windows/xelatex.exe"),
    "C:/Program Files/MiKTeX/miktex/bin/x64/xelatex.exe",
    "C:/texlive/2024/bin/windows/xelatex.exe",
    "/usr/bin/xelatex", "/usr/local/bin/xelatex"
  )
  for (p in candidates) if (file.exists(p)) return(p)
  ""
}

xelatex_bin <- find_xelatex()
if (nzchar(xelatex_bin)) {
  Sys.setenv(PATH = paste(dirname(xelatex_bin), Sys.getenv("PATH"),
                           sep = .Platform$path.sep))
  message("  (LaTeX engine at ", xelatex_bin, ")")
}

if (requireNamespace("rmarkdown", quietly = TRUE)) {
  to_render <- c("getting_started.Rmd", "questionnaire.Rmd")
  for (rmd in to_render) {
    src <- file.path(out_dir, rmd)
    if (!file.exists(src)) next
    for (fmt in c("pdf_document", "word_document")) {
      out <- tryCatch(
        rmarkdown::render(src, output_format = fmt,
                          quiet = TRUE, envir = new.env()),
        error = function(e) {
          message("✗ ", rmd, " → ", fmt,
                  " failed: ", conditionMessage(e))
          NULL
        })
      if (!is.null(out) && file.exists(out)) {
        file.copy(out, file.path(www_dir, basename(out)), overwrite = TRUE)
        message("✓ ", basename(out), "  (",
                file.info(out)$size, " bytes)")
      }
    }
  }
} else {
  message("(rmarkdown package not installed — ",
          "install.packages('rmarkdown') to enable styled PDF/DOCX.)")
}

# ---------------------------------------------------------------------------
# 3c. Build translator_kit.zip — the bundle users download to set up their
# OWN Claude Project (DIY-kit flow). Public sharing of Claude Projects is
# limited on personal accounts, so instead of pointing users at a shared
# project URL we ship them everything they need to recreate it on their
# own claude.ai account in ~2 minutes.
#
# Zip contents:
#   README.txt              — one-page quick-start (created here, inline)
#   getting_started.pdf     — the polished step-by-step with screenshots
#   system_instructions.md  — paste into the Project's "Instructions" field
#   param_catalogue.md      ┐
#   template_schema.md      │ upload as Project "Files" (knowledge base)
#   mapping_examples.md     │
#   questionnaire.md        ┘
#   questionnaire.docx      — the fillable form the user pastes per chat
# ---------------------------------------------------------------------------
kit_files <- c("system_instructions.md", "param_catalogue.md",
               "template_schema.md", "mapping_examples.md",
               "worked_example.md",
               "questionnaire.md", "questionnaire.docx",
               "getting_started.pdf")
kit_files_present <- kit_files[file.exists(file.path(out_dir, kit_files))]

# Inline README.txt — gives the user the 5-step recipe at a glance.
readme_lines <- c(
  "GMH UNCERTAINTY TRANSLATOR — DIY KIT",
  "=====================================",
  "",
  "WHAT THIS IS",
  "------------",
  "A free AI helper that turns your raw cattle inventory data (Excel/CSV)",
  "into the input template expected by the Cattle Uncertainty App. The",
  "kit lets you set up your OWN Translator on claude.ai in about 2",
  "minutes — no payment, no installation.",
  "",
  "QUICK-START (5 STEPS)",
  "---------------------",
  "1. Sign up for a free account at https://claude.ai (Google / email / Apple).",
  "",
  "2. In the left sidebar, click 'Projects' then 'Create project'.",
  "   Name it 'GMH Uncertainty Translator' (or anything you like).",
  "",
  "3. Open the project and find the 'Instructions' field (top right).",
  "   Open `system_instructions.md` from this kit in any text editor,",
  "   select all, copy, and paste the contents into that field. Save.",
  "",
  "4. Below the Instructions field is a 'Files' panel. Drag-and-drop",
  "   these four files into it:",
  "      - param_catalogue.md",
  "      - template_schema.md",
  "      - mapping_examples.md",
  "      - questionnaire.md",
  "",
  "5. Open `questionnaire.docx`, fill it in (country, year, sub-categories,",
  "   manure systems, etc. — about 2 minutes). Then start a new chat in",
  "   your Project, paste the filled questionnaire as the first message,",
  "   and follow the conversation. Claude will ask you to upload your",
  "   data file(s) next.",
  "",
  "For the full walkthrough with screenshots, open getting_started.pdf",
  "in this kit.",
  "",
  ""
)
writeLines(readme_lines, file.path(out_dir, "README.txt"), useBytes = TRUE)
kit_files_present <- c("README.txt", kit_files_present)

zip_path <- normalizePath(file.path(www_dir, "translator_kit.zip"),
                           winslash = "/", mustWork = FALSE)
if (file.exists(zip_path)) file.remove(zip_path)

# Build the zip with paths flattened (no translator_prompts/ prefix inside
# the archive). Switch into out_dir so the file names in the archive match the
# short names the README references.
old_wd <- getwd()
setwd(out_dir)
zip_ok <- tryCatch({
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(zipfile = zip_path, files = kit_files_present,
             mode = "cherry-pick")
  } else {
    utils::zip(zipfile = zip_path, files = kit_files_present,
               flags = "-q9X")
  }
  TRUE
}, error = function(e) {
  message("  zip build failed: ", conditionMessage(e))
  FALSE
})
setwd(old_wd)
zip_ok <- zip_ok && file.exists(zip_path)

if (zip_ok) {
  message("✓ translator_kit.zip  (",
          file.info(zip_path)$size, " bytes, ",
          length(kit_files_present), " files)")
} else {
  message("✗ translator_kit.zip — neither zip::zip nor utils::zip worked. ",
          "install.packages('zip') and try again.")
}

# ---------------------------------------------------------------------------
# 4. Quick smoke-check
# ---------------------------------------------------------------------------
message("\nFiles in ", out_dir, "/:")
for (f in list.files(out_dir, full.names = TRUE))
  message("  ", basename(f), "  (", file.info(f)$size, " bytes)")

invisible(NULL)
