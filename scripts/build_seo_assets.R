# Build the SEO/social image assets: favicon, Open Graph card, and the
# example-output charts shown on the website (docs/). One-time tooling,
# re-run only if the branding or example numbers change.
#
# All charts use synthetic data in the shape of the hypothetical Country X
# example (never real national inventories) and the app's green palette.
# Usage: Rscript scripts/build_seo_assets.R   (from the repo root)

dir.create("docs/assets", recursive = TRUE, showWarnings = FALSE)

C_BG     <- "#F7F5F0"
C_GREEN  <- "#2D6A4F"
C_DGREEN <- "#1B4332"
C_RED    <- "#C1121F"
C_GREY   <- "#78909C"

set.seed(42)
co2e <- rlnorm(10000, meanlog = log(189000), sdlog = 0.11)
ci   <- quantile(co2e, c(0.025, 0.975))

# ---- favicon (64 px), copied to www/ for the app and docs/assets for the site
draw_favicon <- function(path, px) {
  png(path, width = px, height = px, bg = "transparent")
  par(mar = c(0, 0, 0, 0))
  plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
  rect(0.02, 0.02, 0.98, 0.98, col = C_DGREEN, border = NA)
  bars <- c(0.35, 0.72, 0.5)
  for (i in seq_along(bars)) {
    x0 <- 0.14 + (i - 1) * 0.28
    rect(x0, 0.14, x0 + 0.2, 0.14 + bars[i] * 0.72,
         col = "#95D5B2", border = NA)
  }
  dev.off()
}
draw_favicon("www/favicon.png", 64)
draw_favicon("docs/assets/favicon.png", 64)

# ---- Open Graph card, 1280x640
png("docs/assets/og_image.png", width = 1280, height = 640, res = 96, bg = C_BG)
layout(matrix(c(1, 2), nrow = 1), widths = c(1.15, 1))
par(mar = c(0, 2, 0, 0), family = "sans")
plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
text(0.03, 0.82, "Cattle GHG Uncertainty\nCalculator", adj = c(0, 1),
     cex = 3.4, font = 2, col = C_DGREEN)
text(0.03, 0.52, "IPCC Tier 2 Monte Carlo (Approach 2)\nuncertainty analysis for national inventories",
     adj = c(0, 1), cex = 1.7, col = "#1A1A1A")
text(0.03, 0.30, "Free web tool  ·  no installation  ·  IPCC Table 3.3 outputs",
     adj = c(0, 1), cex = 1.35, col = C_GREEN, font = 2)
text(0.03, 0.16, "Alliance of Bioversity International and CIAT (CGIAR)\nFunded by the Global Methane Hub",
     adj = c(0, 1), cex = 1.1, col = C_GREY)
par(mar = c(5, 4, 4, 2))
hist(co2e, breaks = 48, col = C_GREEN, border = C_DGREEN,
     main = "Total CO2eq: 10,000 Monte Carlo iterations",
     xlab = "t CO2eq (example data)", ylab = "", yaxt = "n",
     cex.main = 1.4, col.main = C_DGREEN)
abline(v = ci, col = C_RED, lwd = 3, lty = 2)
mtext("95% CI", side = 3, at = mean(ci), col = C_RED, cex = 1.1, line = -1.2)
dev.off()

# ---- Website example chart 1: results histogram (960x540)
png("docs/assets/example_histogram.png", width = 960, height = 540, res = 96, bg = "white")
par(mar = c(5, 4, 4, 2), family = "sans")
hist(co2e, breaks = 60, col = C_GREEN, border = C_DGREEN,
     main = "Monte Carlo distribution of total CO2eq with 95% confidence interval",
     xlab = "Total emissions, t CO2eq (hypothetical Country X example)",
     ylab = "Iterations", cex.main = 1.15, col.main = C_DGREEN)
abline(v = ci, col = C_RED, lwd = 3, lty = 2)
abline(v = median(co2e), col = C_DGREEN, lwd = 2)
legend("topright", bty = "n",
       legend = c("95% CI bounds", "median"),
       col = c(C_RED, C_DGREEN), lwd = c(3, 2), lty = c(2, 1))
dev.off()

# ---- Website example chart 2: tornado (960x540)
png("docs/assets/example_tornado.png", width = 960, height = 540, res = 96, bg = "white")
par(mar = c(5, 9, 4, 2), family = "sans")
pars <- c("Cattle population (N)", "Body weight (BW)", "Digestible energy (DE)",
          "Methane conversion (Ym)", "Milk yield", "N excretion factor",
          "Manure Bo", "MCF (storage)")
src  <- c(0.62, 0.45, 0.41, 0.33, 0.21, 0.18, 0.12, 0.09)
redu <- c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE)
cols <- ifelse(redu, C_GREEN, C_GREY)
barplot(rev(src), horiz = TRUE, names.arg = rev(pars), las = 1,
        col = rev(cols), border = NA,
        main = "Which parameters drive the uncertainty (tornado, SRC)",
        xlab = "Standardised regression coefficient (example data)",
        cex.main = 1.15, col.main = C_DGREEN, cex.names = 0.95)
legend("bottomright", bty = "n", fill = c(C_GREEN, C_GREY),
       legend = c("User-reducible with better local data", "Fixed IPCC coefficient"))
dev.off()

cat("Wrote: www/favicon.png, docs/assets/{favicon,og_image,example_histogram,example_tornado}.png\n")
