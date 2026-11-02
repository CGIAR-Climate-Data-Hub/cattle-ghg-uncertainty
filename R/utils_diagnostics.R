# 2026-11-02: the four Monte Carlo quality checks and the convergence trace
# of one simulated quantity, shared by the single-year results (total
# CO2eq) and the trend results (year t total, and the change since the
# base year). `scale` is the mean the percentages refer to: the quantity's
# own mean by default; for a change, whose mean can be near zero, the
# caller passes the year t total. With a scale given, the interval drift
# is also measured against it rather than against the bounds themselves.
mc_diagnostics <- function(x, scale = NULL) {
  x   <- x[is.finite(x)]
  n   <- length(x)
  n2  <- floor(n / 2L)
  h1  <- x[seq_len(n2)]
  h2  <- x[seq(n2 + 1L, n)]
  om  <- mean(x)
  oci <- quantile(x, c(0.025, 0.975), names = FALSE)
  ci1 <- quantile(h1, c(0.025, 0.975), names = FALSE)
  ci2 <- quantile(h2, c(0.025, 0.975), names = FALSE)
  own <- is.null(scale)
  sc  <- if (own) om else scale
  list(
    n            = n,
    mcse_pct     = (sd(x) / sc) / sqrt(n) * 100,
    drift_pct    = abs(mean(h1) - mean(h2)) / sc * 100,
    ci_drift_pct = if (own) mean(abs(ci1 - ci2) / pmax(abs(oci), .Machine$double.eps)) * 100
                   else mean(abs(ci1 - ci2)) / sc * 100,
    skew_val     = mean(((x - om) / sd(x))^3),
    trace        = compute_diag_trace(x)
  )
}

compute_diag_trace <- function(co2e, n_checkpoints = 200L) {
  n      <- length(co2e)
  start  <- min(50L, n)
  idx    <- unique(round(seq(start, n, length.out = n_checkpoints)))
  cs  <- cumsum(co2e)
  list(
    iter         = idx,
    running_mean = cs[idx] / idx,
    running_lo   = sapply(idx, function(i) quantile(co2e[seq_len(i)], 0.025, names = FALSE)),
    running_hi   = sapply(idx, function(i) quantile(co2e[seq_len(i)], 0.975, names = FALSE)),
    final_mean   = mean(co2e),
    final_lo     = quantile(co2e, 0.025, names = FALSE),
    final_hi     = quantile(co2e, 0.975, names = FALSE)
  )
}

make_diag_badge <- function(label, tooltip_text, value_text, status) {
  badge_css <- switch(status,
    pass = "color:#166534; background:#DCFCE7; border:1px solid #22C55E;",
    warn = "color:#92400E; background:#FEF3C7; border:1px solid #F59E0B;",
    fail = "color:#991B1B; background:#FEE2E2; border:1px solid #EF4444;",
    info = "color:#1E40AF; background:#DBEAFE; border:1px solid #3B82F6;"
  )
  badge_label <- switch(status, pass = "Pass", warn = "Warn", fail = "Fail", info = "Info")
  div(
    style = paste0("background:#FFFFFF; border:1px solid #E0DDD5; border-radius:8px;",
                   "padding:14px 16px; display:flex; flex-direction:column; gap:6px;"),
    div(
      style = "display:flex; align-items:center; gap:6px;",
      tags$span(
        style = "font-size:0.78rem; color:#444; font-weight:600; text-transform:uppercase; letter-spacing:0.04em;",
        label
      ),
      bslib::tooltip(
        span(icon("circle-question"), style = "color:#6B6B6B; cursor:help; font-size:0.85rem;"),
        tooltip_text,
        placement = "top"
      )
    ),
    div(
      style = "display:flex; align-items:center; flex-wrap:wrap; gap:8px;",
      tags$span(style = "font-size:1.05rem; font-weight:700;", value_text),
      tags$span(
        style = paste0(badge_css,
                       "display:inline-block; font-weight:700; font-size:0.75rem;",
                       "border-radius:4px; padding:2px 10px;"),
        badge_label
      )
    )
  )
}
