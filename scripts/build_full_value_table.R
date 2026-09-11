# =============================================================================
# build_full_value_table.R -- every shipped value: July, now, source, reach
# =============================================================================
#
# reference/VALUE_CHANGES_FOR_REVIEW.md lists what CHANGED. This lists
# EVERYTHING, changed or not, because "we checked it and it did not move" is
# also a result a reviewer needs, and because a value that was never examined
# should be visible as such rather than absent.
#
# Four things per value, none of them typed by hand:
#
#   July        reference/baseline_defaults.csv, extracted from commit
#               fbfa1bc (2026-07-10) by scripts/extract_baseline_defaults.R.
#   Now         reference/defaults_master.csv, the single authority.
#   Source      the ipcc_verdict and ipcc_source columns of the master:
#               the exact table, page and row the value was read from, or
#               an explicit statement that IPCC publishes nothing.
#   Reach       DEFAULTS_MATRIX.csv: which of the 15 surfaces carry this
#               value and whether they agree. This is the propagation
#               evidence. "master only" is not a failure; most values are
#               carried by only a few surfaces.
#
# Usage (from project root, after verify_defaults.R has run):
#   Rscript scripts/build_full_value_table.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")
suppressMessages({
  for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))
    if (!grepl("^_", basename(f))) source(f)
})

rd <- function(p) utils::read.csv(p, stringsAsFactors = FALSE,
                                  na.strings = "<NA>", colClasses = "character")
need <- c("reference/baseline_defaults.csv", "reference/defaults_master.csv",
          "DEFAULTS_MATRIX.csv")
for (f in need) if (!file.exists(f))
  stop("missing ", f, ". Run extract_baseline_defaults.R and verify_defaults.R first.",
       call. = FALSE)

B <- rd(need[1]); M <- rd(need[2]); X <- rd(need[3])
k3 <- function(d) paste(d$object, d$key, d$field, sep = "\r")
B$k <- k3(B); M$k <- k3(M); X$k <- k3(X)

num <- function(v) suppressWarnings(as.numeric(v))
fmt <- function(v) {
  n <- num(v)
  ifelse(is.na(n), ifelse(is.na(v), "", v),
         format(n, scientific = FALSE, trim = TRUE, drop0trailing = TRUE))
}
esc <- function(x) gsub("\\|", "\\\\|", ifelse(is.na(x), "", x))

# --- propagation, straight from the matrix ---------------------------------
SURF <- setdiff(names(X), c("object", "key", "field", "reference_n",
                            "ipcc_verdict", "rv_round", "rv_authority", "k"))
reach <- function(key) {
  i <- match(key, X$k)
  if (is.na(i)) return("not in the matrix")
  v <- unlist(X[i, SURF])
  m <- sum(v == "MATCH"); d <- sum(v == "DIFFERS"); a <- sum(v == "absent")
  if (d > 0) return(sprintf("**%d DIFFER**, %d agree", d, m))
  if (a > 0) return(sprintf("%d agree, %d absent", m, a))
  if (m == 0) return("master only")
  sprintf("%d surfaces, all agree", m)
}

# Only the values, not the descriptive fields.
keep <- !is.na(num(M$value)) & M$ipcc_verdict != "META"
R <- M[keep, ]
i <- match(R$k, B$k)
R$july  <- fmt(B$value[i])
R$now   <- fmt(R$value)
R$moved <- is.na(i) | !mapply(function(a, b) {
  na <- num(a); nb <- num(b)
  if (!is.na(na) && !is.na(nb)) abs(na - nb) < 1e-12 else identical(a, b)
}, B$value[i], R$value)
R$reach <- vapply(R$k, reach, character(1))
# A row absent from July is new structure, not a changed value.
R$july[is.na(i)] <- "(new)"

GLOSS <- c(
  CONFIRMED = "read at the cited IPCC table",
  INTERPRETED = "a reading of an IPCC category label, not a quotation",
  DEVIATION_DOCUMENTED = "differs from IPCC deliberately, reason on record",
  DEVIATION_OPEN = "differs from IPCC, no recorded reason",
  NOT_IPCC = "not an IPCC value",
  NO_IPCC_DEFAULT = "IPCC publishes no default for this")

out <- c(
"# Every shipped value: July, now, source and reach",
"",
sprintf("Generated %s by `scripts/build_full_value_table.R`. Do not edit by hand.", Sys.Date()),
"",
sprintf("All %d numeric values the tool ships. Unlike `VALUE_CHANGES_FOR_REVIEW.md`, which lists only what changed, this lists everything, because \"we checked it and it did not move\" is also a result.", nrow(R)),
"",
"| column | what it is |",
"|---|---|",
"| **July** | the value at commit `fbfa1bc`, 2026-07-10, the last change before September and the last recorded deployment. Extracted from git by script, never retyped. `(new)` means the row did not exist then. |",
"| **Now** | the value in `reference/defaults_master.csv`, the single authority every other surface is built from. |",
"| **Source** | the exact IPCC table, page and row the value was read from, or an explicit statement that IPCC publishes nothing for it. |",
"| **Reach** | how many of the 15 checked surfaces carry this value and whether they agree. `master only` is normal: most values appear on only a few surfaces. |",
"",
sprintf("- %d values moved since July, %d did not", sum(R$moved), sum(!R$moved)),
sprintf("- verdicts: %s",
        paste(sprintf("%d %s", table(R$ipcc_verdict), names(table(R$ipcc_verdict))),
              collapse = ", ")),
sprintf("- propagation: %d values disagree across surfaces",
        sum(grepl("DIFFER", R$reach))),
"")

ORDER <- c("PARAM_CATALOGUE", "CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT",
           "YM_BY_SUBCAT", "LW_BY_SUBCAT", "MW_BY_SUBCAT", "WG_BY_SUBCAT",
           "DE_BY_SUBCAT", "CP_BY_SUBCAT", "PCT_PREGNANT_BY_SUBCAT",
           "FEEDING_SITUATION_CA", "MMS_DEFAULTS", "MMS_FRAC_DEFAULTS_2019",
           "IPCC_DEFAULTS_BY_REGION", "GWP_VALUES")
TITLE <- c(
  PARAM_CATALOGUE = "The 25 parameters",
  CFI_BY_SUBCAT = "Cfi by sub-category", C_GROWTH_BY_SUBCAT = "C by sub-category",
  YM_BY_SUBCAT = "Ym by sub-category and edition",
  LW_BY_SUBCAT = "Body weight by sub-category",
  MW_BY_SUBCAT = "Mature weight by sub-category",
  WG_BY_SUBCAT = "Weight gain by sub-category",
  DE_BY_SUBCAT = "Digestibility by sub-category",
  CP_BY_SUBCAT = "Crude protein by sub-category",
  PCT_PREGNANT_BY_SUBCAT = "Pregnancy fraction by sub-category",
  FEEDING_SITUATION_CA = "Activity coefficient by feeding situation",
  MMS_DEFAULTS = "Manure systems: methane conversion and direct N2O",
  MMS_FRAC_DEFAULTS_2019 = "Manure systems: nitrogen loss fractions",
  IPCC_DEFAULTS_BY_REGION = "Regional body-weight benchmark (QA only)",
  GWP_VALUES = "Global warming potentials")

for (o in ORDER) {
  d <- R[R$object == o, ]
  if (!nrow(d)) next
  d <- d[order(num(d$row_order), d$field), ]
  out <- c(out, sprintf("## %s", TITLE[[o]]), "",
    sprintf("`%s`, %d values, %d moved since July.", o, nrow(d), sum(d$moved)), "",
    "| key | field | July | Now | | verdict | source | reach |",
    "|---|---|---|---|---|---|---|---|")
  for (j in seq_len(nrow(d))) {
    arrow <- if (d$moved[j]) "**->**" else ""
    out <- c(out, sprintf("| %s | %s | %s | %s | %s | `%s` | %s | %s |",
      esc(d$key[j]), esc(d$field[j]), d$july[j], d$now[j], arrow,
      d$ipcc_verdict[j], esc(d$ipcc_source[j]), d$reach[j]))
  }
  out <- c(out, "")
}

out <- c(out, "## Verdict glossary", "", "| verdict | meaning |", "|---|---|",
  vapply(names(GLOSS), function(k) sprintf("| `%s` | %s |", k, GLOSS[[k]]),
         character(1)), "",
  "## How the reach column is produced", "",
  "`scripts/verify_defaults.R` extracts every default from 15 surfaces and compares each against the master: the Excel Parameters, Vocab, _Lists and Manure_Management sheets, the six AI-translator prompt files, both published guides in source and built form, the QA auto-fill hints, the audit's own literals, and the two built-in example inventories. A value shown as agreeing has been read back out of each of those surfaces and matched. The run is gated in CI, so a surface that drifts fails the build.",
  "",
  "Two limits worth stating. The matrix proves the surfaces agree with the R constants; audit check F39 separately proves the R constants are built from the master, by perturbing it and requiring every object to move. And a value carried by no surface is not unchecked: it is verified against IPCC in the source column, it simply is not repeated anywhere else in the app.",
  "")

writeLines(out, "reference/ALL_VALUES.md", useBytes = TRUE)
utils::write.csv(
  R[, c("object", "key", "field", "july", "now", "moved", "ipcc_verdict",
        "ipcc_source", "reach", "review_round")],
  "reference/ALL_VALUES.csv", row.names = FALSE)
cat(sprintf("wrote reference/ALL_VALUES.md: %d values, %d moved, %d surface disagreements\n",
            nrow(R), sum(R$moved), sum(grepl("DIFFER", R$reach))))
