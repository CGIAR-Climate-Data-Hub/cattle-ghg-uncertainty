# =============================================================================
# export_defaults_master.R -- one-time export of the R constants to the master
# =============================================================================
#
# Run ONCE to seed reference/defaults_master.csv from the constants as they
# stand today. After that the CSV is the authority and R/load_defaults.R reads
# it; this script exists so the transition is provably lossless rather than
# retyped, and so it can be re-run to regenerate the seed if the migration is
# ever redone from scratch.
#
# Usage (from project root):
#   Rscript scripts/export_defaults_master.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

suppressMessages({
  for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))
    if (!grepl("^_", basename(f))) source(f)
})

RP <- "knowledge/review_provenance_index.csv"
REV <- if (file.exists(RP)) read.csv(RP, stringsAsFactors = FALSE) else
  data.frame(object = character(), key = character(), field = character(),
             round = character(), authority = character(),
             stringsAsFactors = FALSE)
prov <- function(obj, key, fld) {
  h <- REV[REV$object == obj &
           (REV$key == key | REV$key == "ALL") &
           (REV$field == fld | REV$field == "ALL"), ]
  if (nrow(h) == 0) c("", "") else c(h$round[1], h$authority[1])
}

rows <- list()
add <- function(object, key, field, value, order = NA_integer_) {
  p <- prov(object, key, field)
  rows[[length(rows) + 1L]] <<- data.frame(
    object = object, key = key, field = field,
    value = if (is.na(value)) NA_character_ else as.character(value),
    row_order = order,
    review_round = p[1], review_authority = p[2],
    stringsAsFactors = FALSE)
}

# --- PARAM_CATALOGUE. row_order is LOAD-BEARING: the translator writer emits
# one block of rows per sub-category in exactly this order. -----------------
pc <- PARAM_CATALOGUE
for (i in seq_len(nrow(pc))) for (f in names(pc))
  if (f != "parameter") add("PARAM_CATALOGUE", pc$parameter[i], f, pc[[f]][i], i)

md <- MMS_DEFAULTS
for (i in seq_len(nrow(md))) for (f in names(md))
  if (f != "id") add("MMS_DEFAULTS", md$id[i], f, md[[f]][i], i)

mf <- MMS_FRAC_DEFAULTS_2019
for (i in seq_len(nrow(mf))) for (f in names(mf))
  if (f != "mms_type") add("MMS_FRAC_DEFAULTS_2019", mf$mms_type[i], f,
                           mf[[f]][i], i)

for (nm in c("CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT", "LW_BY_SUBCAT",
             "MW_BY_SUBCAT", "WG_BY_SUBCAT", "PCT_PREGNANT_BY_SUBCAT",
             "DE_BY_SUBCAT", "CP_BY_SUBCAT", "FEEDING_SITUATION_CA")) {
  o <- get(nm); k <- names(o)
  for (i in seq_along(k)) add(nm, k[i], "value", o[[k[i]]], i)
}

# Ym is the one default that differs between guideline editions, so it is a
# wide table (one column per edition) rather than a single "value" column.
for (i in seq_len(nrow(YM_BY_SUBCAT))) for (f in names(YM_BY_SUBCAT))
  if (f != "sub_category")
    add("YM_BY_SUBCAT", YM_BY_SUBCAT$sub_category[i], f, YM_BY_SUBCAT[[f]][i], i)

for (i in seq_len(nrow(IPCC_DEFAULTS_BY_REGION))) {
  r <- IPCC_DEFAULTS_BY_REGION[i, ]
  add("IPCC_DEFAULTS_BY_REGION", r$region, "parameter", r$parameter, i)
  add("IPCC_DEFAULTS_BY_REGION", r$region, "default_val", r$default_val, i)
}

ord <- 0L
for (ar in names(GWP_VALUES)) for (g in names(GWP_VALUES[[ar]])) {
  ord <- ord + 1L
  add("GWP_VALUES", paste0(ar, ".", g), "value", GWP_VALUES[[ar]][[g]], ord)
}

M <- do.call(rbind, rows)
dir.create("reference", showWarnings = FALSE)

# Carry forward the IPCC verification verdicts if the master already has them.
# They are research results that cannot be regenerated from the constants, so
# a re-seed must not silently discard them. scripts/annotate_ipcc_verdicts.R
# rewrites them from its own table; this only stops a re-seed being lossy.
if (file.exists("reference/defaults_master.csv")) {
  old <- utils::read.csv("reference/defaults_master.csv", stringsAsFactors = FALSE,
                         na.strings = "<NA>", colClasses = "character")
  if (all(c("ipcc_verdict", "ipcc_source") %in% names(old))) {
    k <- function(d) paste(d$object, d$key, d$field, sep = "\r")
    i <- match(k(M), k(old))
    M$ipcc_verdict <- old$ipcc_verdict[i]
    M$ipcc_source  <- old$ipcc_source[i]
    cat(sprintf("  carried forward %d verdicts (%d rows had none)\n",
                sum(!is.na(M$ipcc_verdict)), sum(is.na(M$ipcc_verdict))))
  }
}
# NA and "" are different things here: PARAM_CATALOGUE$ipcc_ref is an empty
# STRING for the four parameters with no IPCC reference, while ipcc_default is
# a true NA for N. Writing both as "" would collapse them and the round trip
# would silently retype four cells.
write.csv(M, "reference/defaults_master.csv", row.names = FALSE, na = "<NA>")
cat(sprintf("wrote reference/defaults_master.csv: %d rows, %d objects\n",
            nrow(M), length(unique(M$object))))
cat(sprintf("  with review provenance: %d\n", sum(nzchar(M$review_round))))
