# Usage: Rscript scripts/test_translator_conversions.R   (no API call, about 20 s)
#
# Stage 6 of the 31 October plan (2026-11-01): conversions declared by the
# AI on a Parameters row (source_value, source_unit, conversion,
# lactation_days / conversion_factor, source_lower / source_upper) are
# recomputed by the server; the time-series cells of a converted parameter
# are checked against their own year's file value times the factor.
suppressMessages({for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
n_ok <- 0L; n_bad <- 0L
ok <- function(cond, what) { if (isTRUE(cond)) { n_ok <<- n_ok + 1L; cat("PASS", what, "\n") } else { n_bad <<- n_bad + 1L; cat("FAIL", what, "\n"); stop(what) } }

row <- function(parameter, mean, ..., sub_category = "dairy_cows", level = "sys_a") {
  c(list(cattle_type = "dairy", aggregation_level = level, sub_category = sub_category, parameter = parameter, mean = mean,
         distribution = "normal", param_type = "coefficient", data_source = "user_file"), list(...))
}
mk <- function(rows) {
  cols <- unique(unlist(lapply(rows, names)))
  as.data.frame(do.call(rbind, lapply(rows, function(r) { r[setdiff(cols, names(r))] <- NA; r[cols] })), stringsAsFactors = FALSE) |>
    (function(d) { for (cn in names(d)) d[[cn]] <- unlist(lapply(d[[cn]], function(v) if (is.null(v)) NA else v)); d })()
}
ps <- mk(list(
  row("Milk", 2.9836, source_value = 4.2375, source_unit = "kg/lactating day", conversion = "milk_lactating_to_head", lactation_days = 257),
  row("Milk", 2.95, source_value = 4.2375, source_unit = "kg/lactating day", conversion = "milk_lactating_to_head", lactation_days = 257, sub_category = "other_cows"),
  row("BW", 598.74, source_value = 1320, source_unit = "lb", conversion = "lb_to_kg", sub_category = "bulls"),
  row("Milk", 3.0, source_value = 4.2, source_unit = "kg/lactating day", conversion = "milk_lactating_to_head", sub_category = "heifers"),
  row("Milk", 3.115, lower = 3, upper = 7.5, source_value = 4.46, source_unit = "kg/lactating day", conversion = "milk_lactating_to_head",
      lactation_days = 255, sub_category = "calves"),
  row("Milk", 3.115, lower = 2.096, upper = 5.240, source_value = 4.46, conversion = "milk_lactating_to_head", lactation_days = 255,
      source_lower = 3, source_upper = 7.5, sub_category = "growing_males"),
  row("N", 1000, sub_category = "feedlot_cattle")))
piece <- list(parameters = ps, manure_management = data.frame(), parameter_timeseries = data.frame())
out <- .translator_verify_conversions(piece)
sc <- out$server_corrections
ok(is.data.frame(sc) && all(c("check", "severity", "group", "parameter") %in% names(sc)), "server_corrections rows have the common shape")
get <- function(group_part, sev = NULL) { r <- sc[grepl(group_part, sc$group, fixed = TRUE), ]; if (!is.null(sev)) r <- r[r$severity == sev, ]; r }
ok(nrow(get("dairy_cows", "info")) == 1L && grepl("4.2375 x 257 / 365 = 2.9836", get("dairy_cows", "info")$issue, fixed = TRUE) &&
   get("dairy_cows")$check == "unit conversion verified", "milk 4.2375 x 257/365 = 2.9836: info row, verified")
ok(nrow(get("other_cows", "fail")) == 1L && grepl("the AI wrote 2.95", get("other_cows", "fail")$issue, fixed = TRUE) &&
   get("other_cows", "fail")$check == "unit conversion", "a mean 1.1 % off is a failure naming the AI's value and the file's")
ok(nrow(get("bulls", "info")) == 1L && grepl("598.74", get("bulls", "info")$issue, fixed = TRUE), "1320 lb -> 598.74 kg verified")
ok(nrow(get("heifers", "warn")) == 1L && grepl("no lactation length", get("heifers", "warn")$issue, fixed = TRUE) &&
   get("heifers", "warn")$check == "unit conversion not verified", "milk conversion without lactation_days: warning, not verified")
ok(nrow(get("calves", "warn")) == 1L && grepl("file's bounds were not stated", get("calves", "warn")$issue, fixed = TRUE),
   "bounds of a converted value without the file's bounds: warning")
ok(nrow(get("growing_males", "fail")) == 0L && nrow(get("growing_males", "info")) == 1L, "bounds converted with the same factor pass")
ok(!any(grepl("feedlot", sc$group)), "a row without a conversion is not touched")
ok(isTRUE(all.equal(out$parameters$conversion_factor[1], 257 / 365)) && is.na(out$parameters$conversion_factor[7]),
   "the factor is kept on the row for the series check")
ok(identical(out$parameters$mean, ps$mean), "the mean is never overwritten")

# ---- the series of a converted parameter ------------------------------------------
yv <- list("2022" = sort(c(4.1, 50, 1000)), "2023" = sort(c(4.2, 51, 1100)), "2024" = sort(c(4.2375, 52, 1200)))
f <- 257 / 365
tsd <- data.frame(cattle_type = "dairy", aggregation_level = "sys_a", sub_category = "dairy_cows", year = c(2022L, 2023L, 2024L),
                  Milk = c(4.1 * f, 4.2 * f, 4.2375 * f), stringsAsFactors = FALSE)
near_in <- function(x, s, tol = 1e-6, tol_abs = 0) any(abs(s - x) <= max(tol * max(1, abs(x)), tol_abs))
fmt <- function(x) format(signif(x, 6))
gk <- function(ps, i) paste(ps$aggregation_level[i], ps$sub_category[i], sep = " / ")
p1 <- out$parameters[1, , drop = FALSE]
ok(length(.translator_ts_conversion_issues(p1, tsd, yv, near_in, fmt, gk)) == 0L, "a series converted year by year passes")
ts_un <- tsd; ts_un$Milk <- c(4.1, 4.2, 4.2375)
iss <- .translator_ts_conversion_issues(p1, ts_un, yv, near_in, fmt, gk)
ok(length(iss) == 1L && grepl("not converted in 3 year", iss[[1]]$issue) && iss[[1]]$severity == "fail", "an unconverted series is a failure")
ts_24 <- tsd; ts_24$Milk <- rep(4.2375 * f, 3)   # every year from the 2024 value (the 31 October error)
iss <- .translator_ts_conversion_issues(p1, ts_24, yv, near_in, fmt, gk)
ok(length(iss) == 1L && grepl("does not match the file in 2 year", iss[[1]]$issue) && grepl("2022, 2023|2022 to 2023", iss[[1]]$issue),
   "a series copied from the inventory year's converted value fails for the other years")
ok(length(.translator_ts_conversion_issues(out$parameters[7, , drop = FALSE], tsd, yv, near_in, fmt, gk)) == 0L,
   "a parameter without a conversion has no series check")

# ---- through the fix-up pipeline ----------------------------------------------------
json <- as.character(jsonlite::toJSON(piece, auto_unbox = TRUE, na = "null", digits = NA, dataframe = "rows", null = "null"))
fixed <- jsonlite::fromJSON(.translator_fix_piece_json(json), simplifyVector = TRUE)
ok(is.data.frame(fixed$server_corrections) && any(fixed$server_corrections$check == "unit conversion"),
   ".translator_fix_piece_json carries the conversion rows")

cat(sprintf("\n%d passed, %d failed\n", n_ok, n_bad))
if (n_bad == 0L) cat("CONVERSION TESTS PASSED\n")
