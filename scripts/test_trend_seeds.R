# Usage: Rscript scripts/test_trend_seeds.R   (no API call, about 1 min)
# Trend mode gives every year and every group its own random stream. Until
# 2026-10-28 the year seed was seed + year index, so year y group g + 1 and
# year y + 1 group g drew the same numbers: their animal numbers (N) had a
# rank correlation of 1.000. This test runs two consecutive years of the
# Country X example with the year seeds run_trend_analysis() uses and checks
# that no pair of different groups in different years shares its N draws,
# and that every stream seed of the trend run is distinct.
suppressMessages({for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }

# four groups: the example copied under four region names
base <- fill_bounds(generate_country_x_example())
specs <- do.call(rbind, lapply(paste0("region_", 1:4), function(r) { x <- base; x$aggregation_level <- r; x }))
n <- 1000L; s <- 42L
blocks <- build_full_coefficient_blocks(specs, n, seed = s, crossgroup = "independent")
one_year <- function(yi) {
  b <- build_systems_data(specs, manure = NULL, n_iter = n,
                          seed = .trend_year_seed(s, yi), crossgroup = "independent",
                          pre_sampled_blocks = blocks)
  run_inventory_simulation(b$systems, n_iter = n, gwp = "AR6", seed = .trend_year_seed(s, yi))
}
y1 <- one_year(1L); y2 <- one_year(2L)
G <- length(y1$by_system)
ok(G >= 2L, sprintf("the example has several groups (%d)", G))
worst <- 0
for (g1 in seq_len(G)) for (g2 in seq_len(G)) {
  a <- y1$by_system[[g1]]$samples$N; b <- y2$by_system[[g2]]$samples$N
  if (is.null(a) || is.null(b) || sd(a) == 0 || sd(b) == 0) next
  worst <- max(worst, abs(cor(a, b, method = "spearman")))
}
ok(worst < 0.15, sprintf("animal numbers: largest rank correlation between any group in year 1 and any group in year 2 is %.3f (was 1.000)", worst))

# every stream seed in a 60-year, 300-group run is distinct
Y <- 60L; Gs <- 300L
seeds <- c(s,                                            # full coefficient blocks
           s + seq_len(Y),                               # partial-correlation generator
           unlist(lapply(seq_len(Y), function(yi) {
             ys <- .trend_year_seed(s, yi)
             c(ys, ys + seq_len(Gs), ys + 1000003L)       # shared draws, groups, per-MMS draws
           })))
ok(!anyDuplicated(seeds), sprintf("all %d stream seeds of a %d-year, %d-group trend run are distinct", length(seeds), Y, Gs))
cat("TREND SEEDS TEST PASSED\n")
