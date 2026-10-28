# Usage: Rscript scripts/test_qaqc_checks.R   (no API call, about 20 s)
# The QA/QC checks after the 2026-10-28 review: unit confusion (percent vs
# fraction), the DE and Ym checks that never ran, plausible ranges with
# their source, beta and log-normal as the sampler reads them, fractions
# under an unbounded distribution by the share of draws outside [0, 1], the
# asymmetric-bounds note (info, EF3_PRP and Frac_LEACH_PRP only), rows
# without uncertainty, the temperature below zero.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
row <- function(parameter, mean, lower, upper, distribution = "normal", uncertainty_pct = NA)
  data.frame(cattle_type = "dairy", aggregation_level = "herd", sub_category = "dairy_cows",
             parameter = parameter, mean = mean, uncertainty_pct = uncertainty_pct,
             distribution = distribution, lower = lower, upper = upper,
             param_type = "coefficient", stringsAsFactors = FALSE)
qa <- function(...) run_qaqc(do.call(rbind, list(...)))
one <- function(df, parameter, check) { r <- df[df$parameter == parameter & df$check == check, ]; if (nrow(r) != 1) stop(sprintf("%s/%s: %d rows", parameter, check, nrow(r))); r }
none <- function(df, parameter, check) nrow(df[df$parameter == parameter & df$check == check, ]) == 0

# 1. DE and Ym range checks run on the names the upload produces
d <- qa(row("DE", 65, 55, 75), row("Ym", 6.5, 5.5, 7.5))
ok(one(d, "DE", "range_check")$status == "pass" && one(d, "Ym", "range_check")$status == "pass", "DE and Ym: the range check runs under their real names")
d <- qa(row("DE", 150, 140, 160))
ok(one(d, "DE", "range_check")$status == "fail", "DE above 100: fail")

# 2. unit confusion
d <- qa(row("DE", 0.65, 0.55, 0.75), row("Ym", 0.065, 0.05, 0.08), row("pct_pregnant", 52, 45, 60, "beta"), row("Fat", 0.04, 0.03, 0.05))
r <- one(d, "DE", "range_check"); ok(r$status == "fail" && grepl("looks like a fraction", r$message) && grepl("enter 65", r$message), "DE = 0.65: fail, names the fraction and the converted value")
ok(one(d, "Ym", "range_check")$status == "fail" && one(d, "Fat", "range_check")$status == "fail", "Ym = 0.065 and Fat = 0.04: fail as fractions")
r <- one(d, "pct_pregnant", "range_check"); ok(r$status == "fail" && grepl("looks like a percentage", r$message) && grepl("enter 0.52", r$message), "pct_pregnant = 52: fail, names the percentage and 0.52")
ok(none(d, "DE", "plausibility"), "a unit failure is not doubled by a plausibility warning")

# 3. plausible ranges with their source
d <- qa(row("DE", 40, 35, 45), row("Ym", 12, 10, 14), row("Cfi", 0.386, 0.35, 0.42), row("Cfi", 0.9, 0.8, 1.0), row("Tw", -5, -12, 2))
r <- d[d$parameter == "DE" & d$check == "plausibility", ]; ok(nrow(r) == 1 && r$status == "warn" && grepl("Table 10.2", r$message) && grepl("45 to 85", r$message), "DE = 40: warning with Table 10.2 and the sampler's range")
r <- one(d, "Ym", "plausibility"); ok(r$status == "warn" && grepl("Table 10.12", r$message), "Ym = 12: warning with Table 10.12")
rc <- d[d$parameter == "Cfi" & d$check == "plausibility", ]; ok(nrow(rc) == 2 && identical(sort(rc$status), c("pass", "warn")) && grepl("Table 10.4", rc$message[rc$status == "warn"]), "Cfi: 0.386 passes, 0.9 warns with Table 10.4")
d0 <- qa(row("Fat", 0, 0, 0, "constant"), row("GE", 0, 0, 0, "constant"), row("Cfi", 0, 0, 0, "constant"))
ok(one(d0, "Fat", "plausibility")$status == "pass" && grepl("not used", one(d0, "Fat", "plausibility")$message) && one(d0, "GE", "plausibility")$status == "pass", "Fat = 0 and GE = 0: not used for this group, no warning")
ok(one(d0, "Cfi", "plausibility")$status == "warn", "Cfi = 0: still a warning (a zero is never right there)")
ok(none(d, "Tw", "non_negative") && one(d, "Tw", "plausibility")$status == "pass", "Tw = -5: no negative-bound warning, within the usual range")

# 4. distributions as the sampler reads them
d <- qa(row("Fat", 3.4, 3.0, 3.8, "beta"), row("Fat", 3.4, 3.4, 3.8, "beta"), row("Bo", 0.13, 0, 0.2, "lognormal"), row("Bo", 0.13, 0.1, 0.2, "lognormal"))
rb <- d[d$parameter == "Fat" & d$check == "dist_suitability", ]; ok(nrow(rb) == 2 && identical(sort(rb$status), c("fail", "pass")), "beta: valid on milk fat at 3.4 %; fails only when a bound equals the mean")
rl <- d[d$parameter == "Bo" & d$check == "dist_suitability", ]; ok(nrow(rl) == 2 && identical(sort(rl$status), c("fail", "pass")) && grepl("lower bound", rl$message[rl$status == "fail"]), "log-normal: fails with a lower bound of 0, passes with 0.1")

# 5. fractions under an unbounded distribution: by the share of draws outside [0, 1]
d <- qa(row("ASH", 0.5, 0.4, 0.6, "normal"), row("ASH", 0.08, 0.0, 0.2, "normal"), row("UE", 0.9, 0.6, 1.2, "lognormal"), row("UE", 0.04, 0.02, 0.06, "pert"))
ra <- d[d$parameter == "ASH" & d$check == "fraction_distribution", ]
ok(identical(sort(ra$status), c("pass", "warn")) && grepl("% of the draws", ra$message[ra$status == "warn"]), "ASH normal: 0.4 to 0.6 passes; 0 to 0.2 warns with the share of draws below 0")
ru <- d[d$parameter == "UE" & d$check == "fraction_distribution", ]
ok(identical(sort(ru$status), c("pass", "warn")), "UE: log-normal reaching above 1 warns; pert passes")

# 6. the asymmetric-bounds note
cat_row <- function(p) PARAM_CATALOGUE[PARAM_CATALOGUE$parameter == p, ]
g <- cat_row("Frac_GASM_PRP"); e <- cat_row("EF3_PRP"); l <- cat_row("Frac_LEACH_PRP")
d <- qa(row("Frac_GASM_PRP", g$ipcc_default, g$suggested_lower_bound, g$suggested_upper_bound, "pert"),
        row("EF3_PRP", e$ipcc_default, e$suggested_lower_bound, e$suggested_upper_bound, "pert"),
        row("EF3_PRP", 0.004, 0.0035, 0.0045, "pert"),
        row("Frac_LEACH_PRP", l$ipcc_default, l$suggested_lower_bound, l$suggested_upper_bound, "pert"))
ok(none(d, "Frac_GASM_PRP", "asymmetric_bounds"), "Frac_GASM_PRP (IPCC range left-skewed): no asymmetric-bounds finding at all")
re3 <- d[d$parameter == "EF3_PRP" & d$check == "asymmetric_bounds", ]
ok(identical(sort(re3$status), c("info", "pass")) && grepl("Table 11.1", re3$message[re3$status == "info"]) && grepl("0.0005 to 0.027", re3$message[re3$status == "info"]), "EF3_PRP: catalogue bounds pass; symmetric bounds give an info with the IPCC range")
ok(one(d, "Frac_LEACH_PRP", "asymmetric_bounds")$status == "pass", "Frac_LEACH_PRP: catalogue bounds pass")
ok(!any(d$status == "warn" & d$check == "asymmetric_bounds"), "asymmetric bounds are never a warning")

# 7. rows without uncertainty
d <- qa(row("Milk", 10, NA, NA, "normal"), row("Milk", 10, 10, 10, "pert"), row("hours", 0, 0, 0, "normal"), row("WG", 0.3, NA, NA, "constant"))
rm <- d[d$parameter == "Milk" & d$check == "bounds_order", ]
ok(identical(sort(rm$status), c("info", "warn")) && grepl("sampled as a constant", rm$message[rm$status == "warn"]) && grepl("no uncertainty", rm$message[rm$status == "info"]), "Milk: no bounds warns; lower = upper = mean is an info; both say the row is sampled as a constant")
ok(one(d, "hours", "bounds_order")$status == "pass", "hours = 0 with zero bounds: pass (degenerate constant)")
ok(none(d, "WG", "bounds_order"), "a constant without bounds: no finding")
cat("QAQC CHECKS TEST PASSED
")
