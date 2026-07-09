# Build beta_sample_inventory.xlsx — a short, anonymized practice dataset for
# beta testers. Structurally like the ZIM/Zambia files (multiple production
# systems x sub-categories) but tiny, so a reviewer can grasp it in minutes.
#
# It is written through the app's OWN official-template writer
# (.translator_write_official_template -> generate_template_openxlsx), so the
# file is byte-for-byte the schema the Data Input tab expects (styling,
# dropdowns, supporting sheets). We only supply the data overlay.
#
# 4 groups = 2 systems x 2 sub-categories:
#   dairy     / "Commercial dairy" / {cows, heifers}
#   non_dairy / "Extensive beef"   / {cows, oxen}
# Values are round + obviously illustrative; the country is the anonymized
# label "Country" (no invented nation).

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressWarnings(suppressMessages({
  library(shiny); library(openxlsx); library(readxl); library(writexl)
}))
source("R/utils_ipcc_defaults.R")
source("R/utils_template.R")
source("R/chat_ui.R")

# ---- Parameters --------------------------------------------------------------
# Per group: parameter | mean | uncertainty_pct | distribution.
# Biological zeros (WG on adults, Milk/pct_pregnant on non-reproductive groups)
# are entered as constant so they are not auto-filled with a nonzero default.
mk_params <- function(ct, agg, sub, rows) {
  # Provide explicit lower/upper (value ± uncertainty%) so they overwrite the
  # blank template's pre-filled CATALOGUE bounds — otherwise an overridden
  # value (e.g. Bo 0.13->0.24) would keep catalogue bounds that no longer
  # bracket it, and the run-time bounds check would block. u=0 -> lower=upper=mean.
  lower <- rows$m * (1 - rows$u / 100)
  upper <- rows$m * (1 + rows$u / 100)
  data.frame(cattle_type = ct, aggregation_level = agg, sub_category = sub,
             parameter = rows$p, mean = rows$m,
             uncertainty_pct = rows$u, distribution = rows$d,
             lower = lower, upper = upper,
             data_source = "sample dataset", stringsAsFactors = FALSE)
}
P <- function(p, m, u, d) list(p = p, m = m, u = u, d = d)
# helper to stack named param specs into vectors
spec <- function(...) {
  L <- list(...)
  list(p = vapply(L, `[[`, "", "p"),
       m = vapply(L, `[[`, numeric(1), "m"),
       u = vapply(L, `[[`, numeric(1), "u"),
       d = vapply(L, `[[`, "", "d"))
}

params <- rbind(
  mk_params("dairy", "Commercial dairy", "cows", spec(
    P("N", 40000, 10, "normal"),  P("BW", 450, 8, "normal"),
    P("MW", 460, 8, "normal"),    P("WG", 0, 0, "constant"),
    P("Milk", 12, 15, "normal"),  P("Fat", 4.0, 10, "normal"),
    P("pct_pregnant", 0.75, 10, "beta"), P("DE", 65, 8, "normal"),
    P("CP", 14, 12, "normal"),    P("Ym", 6.5, 20, "pert"),
    P("Bo", 0.24, 20, "pert"))),
  mk_params("dairy", "Commercial dairy", "heifers", spec(
    P("N", 15000, 10, "normal"),  P("BW", 280, 8, "normal"),
    P("MW", 460, 8, "normal"),    P("WG", 0.40, 15, "normal"),
    P("Milk", 0, 0, "constant"),  P("pct_pregnant", 0, 0, "constant"),
    P("DE", 62, 8, "normal"),     P("CP", 13, 12, "normal"),
    P("Ym", 6.5, 20, "pert"),     P("Bo", 0.13, 20, "pert"))),
  mk_params("non_dairy", "Extensive beef", "cows", spec(
    P("N", 200000, 12, "normal"), P("BW", 350, 10, "normal"),
    P("MW", 360, 10, "normal"),   P("WG", 0.10, 20, "normal"),
    P("Milk", 1.5, 20, "normal"), P("Fat", 4.0, 10, "normal"),
    P("pct_pregnant", 0.60, 12, "beta"), P("DE", 55, 8, "normal"),
    P("CP", 9, 12, "normal"),     P("Ym", 7.0, 20, "pert"),
    P("Bo", 0.13, 20, "pert"))),
  mk_params("non_dairy", "Extensive beef", "oxen", spec(
    P("N", 80000, 12, "normal"),  P("BW", 420, 10, "normal"),
    P("MW", 420, 10, "normal"),   P("WG", 0.05, 20, "normal"),
    P("Milk", 0, 0, "constant"),  P("pct_pregnant", 0, 0, "constant"),
    P("hours", 6, 20, "normal"),  P("DE", 54, 8, "normal"),
    P("CP", 8, 12, "normal"),     P("Ym", 7.0, 20, "pert"),
    P("Bo", 0.13, 20, "pert")))
)

# ---- Manure management -------------------------------------------------------
# 2 MMS per group (pasture + solid_storage; valid in both IPCC versions),
# fractions sum to 100. Coefficient values mirror the app's own vetted example
# rows (generate_country_x/y_manure): MCF/Frac_* are PERCENT, EF3 a fraction.
mk_manure <- function(ct, agg, sub, past, solid) {
  data.frame(
    cattle_type = ct, aggregation_level = agg, sub_category = sub,
    mms_type = c("pasture", "solid_storage"),
    fraction_pct = c(past, solid),
    lower_fraction = c(max(past - 10, 0), max(solid - 10, 0)),
    upper_fraction = c(min(past + 10, 100), min(solid + 10, 100)),
    distribution_fraction = "pert",
    MCF_pct = c(1.5, 4.0),
    EF3 = c(0.020, 0.005),
    Frac_GasMS_pct = c(21, 45),
    Frac_LeachMS_pct = c(30, 2),
    stringsAsFactors = FALSE)
}
manure <- rbind(
  mk_manure("dairy", "Commercial dairy", "cows", 30, 70),
  mk_manure("dairy", "Commercial dairy", "heifers", 40, 60),
  mk_manure("non_dairy", "Extensive beef", "cows", 85, 15),
  mk_manure("non_dairy", "Extensive beef", "oxen", 80, 20)
)

# ---- Parameter time series (2018-2022) --------------------------------------
# Population (N) growing ~ few % / yr, ending at the Parameters value in 2022,
# plus BW. Gives the Correlations tab a non-empty, >=5-year, >=2-column matrix.
mk_ts <- function(ct, agg, sub, N2022, BW2022) {
  yrs <- 2018:2022
  f <- c(0.88, 0.91, 0.94, 0.97, 1.00)          # growth toward the 2022 value
  data.frame(cattle_type = ct, aggregation_level = agg, sub_category = sub,
             year = yrs, N = round(N2022 * f),
             BW = round(BW2022 * seq(0.98, 1.00, length.out = 5), 1),
             stringsAsFactors = FALSE)
}
ts <- rbind(
  mk_ts("dairy", "Commercial dairy", "cows", 40000, 450),
  mk_ts("dairy", "Commercial dairy", "heifers", 15000, 280),
  mk_ts("non_dairy", "Extensive beef", "cows", 200000, 350),
  mk_ts("non_dairy", "Extensive beef", "oxen", 80000, 420)
)

# ---- Assemble + write via the app's official writer --------------------------
parsed <- list(
  inventory_metadata = list(
    country = "Country", region = "africa", inventory_year = 2022,
    species = "cattle_non_dairy", ipcc_version = "2019_refinement",
    prepared_by = "GMH beta-test sample",
    notes = "Anonymized practice dataset for beta testers — not real inventory data."),
  parameters = params,
  manure_management = manure,
  parameter_timeseries = ts
)

# NOTE: run from the repo root — `Rscript feedback_workflow/_make_sample_inventory.R`
# (it sources R/… relative to the working dir).
out <- "feedback_workflow/beta_sample_inventory.xlsx"
.translator_write_official_template(parsed, out)
cat("Saved:", out, "|", nrow(params), "parameter rows,", nrow(manure),
    "manure rows,", nrow(ts), "time-series rows across 4 groups\n")
