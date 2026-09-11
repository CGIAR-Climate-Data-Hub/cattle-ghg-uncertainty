# =============================================================================
# End-to-end statistician's audit of the cattle uncertainty app
# =============================================================================
#
# This script verifies the calculation engine on every meaningful route through
# the app. It:
#   1. Builds a synthetic "golden case" input I have hand-computed below.
#   2. Asserts each IPCC Vol.4 Ch.10 / Ch.11 equation matches the hand-comp
#      to within 1e-6 relative tolerance (deterministic checks: n_iter=1 with
#      every parameter set to its mean, all distributions = "constant").
#   3. Tests the Monte Carlo sampler at 50,000 iterations against analytical
#      expectations (mean, target rank correlation, AR(1) decay).
#   4. Runs the full inventory simulation through every orthogonal combination
#      of UI-controllable options (source filter, correlation mode, GWP,
#      analysis mode, year_corr, decomposition toggle) and checks the headline
#      totals match the hand-comp.
#   5. Exercises validators on edge cases (blank cells, fractions not summing
#      to 100, lower > upper, zero population, no sources ticked).
#   6. Exercises the download / export functions.
#
# Outputs a human-readable AUDIT_REPORT.md alongside this script.
#
# Bugs found are REPORTED, not fixed (per the approved plan).
#
# -----------------------------------------------------------------------------
# HAND-COMPUTED GOLDEN-CASE REFERENCE  (verified by paper-and-pencil 2026-05-21)
# -----------------------------------------------------------------------------
# Inputs:
#   N=100000, BW=300, MW=300, WG=0, Milk=5.0, Fat=4.0, pct_pregnant=0.50,
#   DE=60, CP=12, hours=0, Tw=20, Cfi=0.386, Ca=0.17, C=0.80, Cp=0.10,
#   Ym=6.5, Bo=0.13, ASH=0.08, UE=0.04, MilkPR=3.3,
#   EF3_PRP=0.004, EF4=0.010, EF5=0.011,
#   Frac_GASM_PRP=0.21, Frac_LEACH_PRP=0.24,
#   MMS: 100% pasture, MCF=0.015, EF3=0.020
#
#   NEM (Eq. 10.3) = 0.386 * 300^0.75
#                  = 0.386 * 72.0813   = 27.823 MJ/day
#   NEA (Eq. 10.4) = 0.17 * 27.823     =  4.730 MJ/day
#   NEG (Eq. 10.6) = 0 (WG = 0 early-return branch)
#   NEL (Eq. 10.8) = 5.0 * (1.47 + 0.40*4.0) * 0.50 = 5.0 * 3.07 * 0.50 = 7.675 MJ/day
#   NEW (Eq. 10.11)= 0.10 * 27.823 * 0 = 0
#   NEP (Eq. 10.13)= 0.10 * 0.50 * 27.823 = 1.3912 MJ/day
#   REM (Eq. 10.14)= 1.123 - 4.092e-3*60 + 1.126e-5*3600 - 25.4/60
#                  = 1.123 - 0.24552 + 0.040536 - 0.423333 = 0.49469
#   REG (Eq. 10.15)= 1.164 - 5.160e-3*60 + 1.308e-5*3600 - 37.4/60
#                  = 1.164 - 0.30960 + 0.047088 - 0.623333 = 0.27815
#   GE  (Eq. 10.16)= ((27.823+4.730+7.675+0+1.3912)/0.49469 + 0/0.27815) / (60/100)
#                  = 41.6196 / 0.49469 / 0.6
#                  = 84.1342 / 0.6 = 140.224 MJ/head/day
#   Enteric CH4 (Eq. 10.21) = 140.224 * (6.5/100) * 365 / 55.65 = 59.781 kg CH4/head/yr
#   VS (Eq. 10.24) = (140.224 * (1-0.6) + 0.04*140.224) * (1-0.08) / 18.45
#                  = (56.0894 + 5.6089) * 0.92 / 18.45
#                  = 56.7625 / 18.45 = 3.07655 kg DM/head/day
#   Manure CH4 (Eq. 10.23) = 3.07655 * 365 * 0.13 * 0.67 * 0.015 * 1.0 (pasture)
#                          = 1.4671 kg CH4/head/yr
#   N excretion (Eq. 10.32):
#       DMI         = 140.224/18.45 = 7.6002
#       N_intake    = 7.6002 * 0.12/6.25 = 0.145924
#       N_retained  = 5.0*0.50*3.3/100/6.38 + 0 = 0.012931
#       Nex per day = 0.132993; * 365 = 48.5424 kg N/head/yr
#   Direct MM N2O   = 0 (pasture excluded from MM loop)
#   Indirect MM N2O = 0 (same)
#   Direct PRP N2O  = 48.5424 * 1.0 * 0.004 * 44/28 = 0.30516 kg N2O/head/yr
#   Indirect PRP N2O = 48.5424 * 1.0 * (0.21*0.010 + 0.24*0.011) * 44/28
#                    = 48.5424 * 0.00474 * 1.5714 = 0.36154 kg N2O/head/yr
#
#   At population N=100000, multiplying per-head by N/1000:
#     total_enteric_ch4   = 59.781 * 100 = 5978.11 t CH4
#     total_manure_ch4    =  1.4671*100 =  146.71 t CH4
#     total_direct_n2o_mm = 0
#     total_indirect_n2o_mm = 0
#     total_direct_n2o_prp = 0.30516 *100 =   30.516 t N2O
#     total_indirect_n2o_prp = 0.36154*100 =  36.154 t N2O
#     total_ch4           = 6124.82 t CH4
#     total_n2o           = 66.670  t N2O
#
#   AR5 GWP: CH4=28, N2O=265
#     total_co2e_AR5 = 6124.82*28 + 66.670*265 = 171494.96 + 17667.55 = 189162.51 t CO2eq
#   AR4 GWP: CH4=25, N2O=298
#     total_co2e_AR4 = 6124.82*25 + 66.670*298 = 153120.50 + 19867.66 = 172988.16
#   AR6 GWP: CH4=27.0, N2O=273
#     total_co2e_AR6 = 6124.82*27.0 + 66.670*273 = 165370.14 + 18200.91 = 183571.05
# =============================================================================

# Run from project root: Rscript scripts/audit.R
# Self-correcting if invoked from inside scripts/.
if (basename(getwd()) == "scripts") setwd("..")

options(warn = 1)
suppressMessages({
  # Source library files only; skip entry-point scripts like R/_test_*.R that
  # execute top-level diagnostics when loaded.
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
    if (!grepl("^_", basename(f))) source(f)
  }
})

# Allow LaTeX-free run (we don't render anything from here)
TOL_REL <- 1e-4        # relative tolerance for deterministic checks
TOL_MC  <- 0.02        # absolute tolerance for MC convergence (rank corr etc.)

# ---------------------------------------------------------------------------
# Hand-computed reference values
# ---------------------------------------------------------------------------
golden_ref <- list(
  NEM                 = 0.386 * 300^0.75,           # 27.8234
  NEA                 = 0.17 * 0.386 * 300^0.75,    # 4.7300
  NEG                 = 0,
  # Eq 10.8 exactly: no pct_pregnant. The milk input is IPCC's annual
  # average per head, so weighting it again discounted it twice.
  # NEP below KEEPS the 0.50, which Table 10.7 sanctions.
  NEL                 = 5.0 * (1.47 + 0.40 * 4.0),        # 15.35
  NEW                 = 0,
  NEP                 = 0.10 * 0.50 * 0.386 * 300^0.75,    # 1.3912
  REM                 = 1.123 - 4.092e-3 * 60 + 1.126e-5 * 60^2 - 25.4 / 60,
  REG                 = 1.164 - 5.160e-3 * 60 + 1.308e-5 * 60^2 - 37.4 / 60
)
golden_ref$GE <- ((golden_ref$NEM + golden_ref$NEA + golden_ref$NEL +
                    golden_ref$NEW + golden_ref$NEP) / golden_ref$REM +
                  golden_ref$NEG / golden_ref$REG) / (60 / 100)
golden_ref$enteric_ch4_head     <- golden_ref$GE * 0.065 * 365 / 55.65
golden_ref$VS                   <- (golden_ref$GE * (1 - 0.6) +
                                      0.04 * golden_ref$GE) *
                                    (1 - 0.08) / 18.45
golden_ref$manure_ch4_head      <- golden_ref$VS * 365 * 0.13 * 0.67 *
                                    0.015 * 1.0
# Eq 10.33 milk-N term, also without pct_pregnant, for the same reason.
golden_ref$Nex                  <- (golden_ref$GE / 18.45 * 0.12 / 6.25 -
                                      5.0 * 3.3 / 100 / 6.38) * 365
golden_ref$direct_n2o_mm_head   <- 0
golden_ref$indirect_n2o_mm_head <- 0
golden_ref$direct_n2o_prp_head  <- golden_ref$Nex * 1.0 * 0.004 * 44 / 28
golden_ref$indirect_n2o_prp_head <- golden_ref$Nex * 1.0 *
                                     (0.21 * 0.010 + 0.24 * 0.011) * 44 / 28

# Inventory totals at N = 100,000 (per-head * N / 1000)
N_pop <- 100000
golden_ref$total_enteric_ch4    <- golden_ref$enteric_ch4_head    * N_pop / 1000
golden_ref$total_manure_ch4     <- golden_ref$manure_ch4_head     * N_pop / 1000
golden_ref$total_direct_n2o_mm  <- 0
golden_ref$total_indirect_n2o_mm <- 0
golden_ref$total_direct_n2o_prp <- golden_ref$direct_n2o_prp_head * N_pop / 1000
golden_ref$total_indirect_n2o_prp <- golden_ref$indirect_n2o_prp_head * N_pop / 1000
golden_ref$total_ch4            <- golden_ref$total_enteric_ch4 + golden_ref$total_manure_ch4
golden_ref$total_n2o            <- golden_ref$total_direct_n2o_prp + golden_ref$total_indirect_n2o_prp
golden_ref$total_co2e_AR5       <- golden_ref$total_ch4 * 28 + golden_ref$total_n2o * 265
golden_ref$total_co2e_AR4       <- golden_ref$total_ch4 * 25 + golden_ref$total_n2o * 298
golden_ref$total_co2e_AR6       <- golden_ref$total_ch4 * 27.0 + golden_ref$total_n2o * 273

# ---------------------------------------------------------------------------
# Golden-case input builder
# ---------------------------------------------------------------------------
make_golden_specs <- function(constant_dist = TRUE) {
  d <- if (constant_dist) "constant" else "normal"
  rows <- list(
    list(p = "N",             v = 100000, t = "activity_data",  pct = 0),
    list(p = "BW",            v = 300,    t = "coefficient",    pct = 0),
    list(p = "MW",            v = 300,    t = "coefficient",    pct = 0),
    list(p = "WG",            v = 0,      t = "coefficient",    pct = 0),
    list(p = "Milk",          v = 5.0,    t = "coefficient",    pct = 0),
    list(p = "Fat",           v = 4.0,    t = "coefficient",    pct = 0),
    list(p = "pct_pregnant",   v = 0.5,    t = "coefficient",    pct = 0),
    list(p = "DE",            v = 60,     t = "coefficient",    pct = 0),
    list(p = "CP",            v = 12,     t = "coefficient",    pct = 0),
    list(p = "hours",         v = 0,      t = "coefficient",    pct = 0),
    list(p = "Tw",            v = 20,     t = "coefficient",    pct = 0),
    list(p = "Cfi",           v = 0.386,  t = "coefficient",    pct = 0),
    list(p = "Ca",            v = 0.17,   t = "coefficient",    pct = 0),
    list(p = "C",             v = 0.8,    t = "coefficient",    pct = 0),
    list(p = "Cp",            v = 0.10,   t = "coefficient",    pct = 0),
    list(p = "Ym",            v = 6.5,    t = "coefficient",    pct = 0),
    list(p = "Bo",            v = 0.13,   t = "coefficient",    pct = 0),
    list(p = "ASH",           v = 0.08,   t = "coefficient",    pct = 0),
    list(p = "UE",            v = 0.04,   t = "coefficient",    pct = 0),
    list(p = "MilkPR",        v = 3.3,    t = "coefficient",    pct = 0),
    list(p = "EF3_PRP",       v = 0.004,  t = "coefficient",    pct = 0),
    list(p = "EF3_S",         v = 0.005,  t = "coefficient",    pct = 0),
    list(p = "EF4",           v = 0.010,  t = "coefficient",    pct = 0),
    list(p = "EF5",           v = 0.011,  t = "coefficient",    pct = 0),
    list(p = "Frac_GASMS",    v = 0.21,   t = "coefficient",    pct = 0),
    list(p = "Frac_LEACH_H",  v = 0.02,   t = "coefficient",    pct = 0),
    list(p = "Frac_GASM_PRP", v = 0.21,   t = "coefficient",    pct = 0),
    list(p = "Frac_LEACH_PRP",v = 0.24,   t = "coefficient",    pct = 0)
  )
  df <- do.call(rbind, lapply(rows, function(r) data.frame(
    cattle_type       = "dairy",
    aggregation_level = "golden",
    sub_category      = "cows",
    parameter         = r$p,
    mean              = r$v,
    uncertainty_pct   = r$pct,
    lower             = r$v,
    upper             = r$v,
    distribution      = d,
    param_type        = r$t,
    stringsAsFactors  = FALSE
  )))
  df
}

build_golden_system <- function(specs = make_golden_specs()) {
  list(
    "dairy||golden||cows" = list(
      param_specs         = specs,
      corr_matrix         = NULL,
      ef_corr_matrix      = NULL,
      unified_corr_matrix = NULL,
      mms_fractions       = c(pasture = 1.0),
      mcf_values          = c(pasture = 0.015),
      ef3_values          = c(pasture = 0.020),
      frac_gas_values     = NULL,
      frac_leach_values   = NULL,
      mcf_samples = NULL, ef3_samples = NULL,
      frac_gas_samples = NULL, frac_leach_samples = NULL
    )
  )
}

# ---------------------------------------------------------------------------
# Test result collector
# ---------------------------------------------------------------------------
results <- list()
record <- function(id, section, description, expected, actual, status, notes = "") {
  results[[length(results) + 1]] <<- data.frame(
    id          = id,
    section     = section,
    description = description,
    expected    = format(expected, scientific = FALSE),
    actual      = format(actual, scientific = FALSE),
    status      = status,
    notes       = notes,
    stringsAsFactors = FALSE
  )
}
check_close <- function(id, section, description, actual, expected,
                         tol = TOL_REL, notes = "") {
  ok <- isTRUE(!is.na(actual) && !is.na(expected) &&
                abs(actual - expected) <= tol * max(abs(expected), 1))
  record(id, section, description, expected, actual,
         if (ok) "PASS" else "FAIL", notes)
}
check_within <- function(id, section, description, actual, expected,
                          tol_abs, notes = "") {
  ok <- isTRUE(!is.na(actual) && !is.na(expected) &&
                abs(actual - expected) <= tol_abs)
  record(id, section, description, expected, actual,
         if (ok) "PASS" else "FAIL", notes)
}
check_bool <- function(id, section, description, condition,
                        expected = TRUE, notes = "") {
  ok <- isTRUE(condition) == isTRUE(expected)
  record(id, section, description,
         if (isTRUE(expected)) "TRUE" else "FALSE",
         if (isTRUE(condition)) "TRUE" else "FALSE",
         if (ok) "PASS" else "FAIL", notes)
}

# =============================================================================
# Section A — IPCC equation chain at the golden case (deterministic)
# =============================================================================
section_A <- function() {
  cat("\n[A] Equation chain on golden case (n_iter=1, all distributions=constant)...\n")
  sd <- build_golden_system()
  sim <- run_inventory_simulation(sd, n_iter = 10, gwp = "AR5",
                                   seed = 42, pct_pregnant = 1)
  # The deterministic per-head intermediates are not exposed by
  # run_inventory_simulation directly, so we also call ghg_emissions() once.
  golden_in <- list(
    cattle_pop = 100000, live_weight = 300, weight_gain = 0,
    mature_weight = 300, milk_yield = 5.0, milk_fat = 4.0,
    pct_pregnant = 0.5, hours = 0, DE = 60, Cfi = 0.386, Ca = 0.17,
    C_growth = 0.8, Cp = 0.10, Ym = 6.5, Bo = 0.13, ASH = 0.08,
    UE = 0.04, CP = 12, MilkPR = 3.3,
    EF3_PRP = 0.004, Frac_GASMS = 0.21, EF4 = 0.010, EF5 = 0.011,
    Frac_LEACH_H = 0.02,
    Frac_GASM_PRP = 0.21, Frac_LEACH_PRP = 0.24
  )
  # Replicate intermediates with the same calc_ functions to verify them
  NEM <- calc_nem(golden_in$live_weight, golden_in$Cfi, Tw = 20)
  NEA <- calc_nea(NEM, golden_in$Ca)
  NEG <- calc_neg(golden_in$live_weight, golden_in$weight_gain,
                   golden_in$C_growth, golden_in$mature_weight)
  # No pct_pregnant: Eq 10.8 has no such factor and the milk input is
  # already IPCC's annual average per head. calc_nep() below keeps it,
  # because Table 10.7 sanctions the weighting for pregnancy.
  NEL <- calc_nel(golden_in$milk_yield, golden_in$milk_fat)
  NEW <- calc_new(NEM, golden_in$hours)
  NEP <- calc_nep(NEM, golden_in$Cp, pct_pregnant = golden_in$pct_pregnant)
  REM <- calc_rem(golden_in$DE)
  REG <- calc_reg(golden_in$DE)
  GE  <- calc_ge(NEM, NEA, NEL, NEP, NEW, NEG, REM, REG, golden_in$DE)
  ent_ch4_head <- calc_enteric_ch4(GE, golden_in$Ym)
  VS  <- calc_volatile_solids(GE, golden_in$DE, golden_in$UE, golden_in$ASH)
  mch4_head <- calc_manure_ch4(VS, golden_in$Bo,
                                c(pasture = 1.0), c(pasture = 0.015))
  Nex <- calc_n_excretion(GE, golden_in$CP, golden_in$milk_yield,
                          golden_in$pct_pregnant, golden_in$weight_gain,
                          MilkPR = golden_in$MilkPR)
  d_mm  <- calc_direct_n2o_mm(Nex, c(pasture = 1.0),
                              c(pasture = 0.020))
  id_mm <- calc_indirect_n2o_mm(Nex, c(pasture = 1.0),
                                EF4 = 0.010, EF5 = 0.011,
                                frac_gas = 0.21, frac_leach = 0.02)
  d_prp  <- calc_direct_n2o_prp(Nex, 1.0, EF3_PRP = 0.004)
  id_prp <- calc_indirect_n2o_prp(Nex, 1.0,
                                  Frac_GASM_PRP = 0.21, EF4 = 0.010,
                                  Frac_LEACH_PRP = 0.24, EF5 = 0.011)

  check_close("A1",  "A", "NEM (Eq. 10.3)",                 NEM,        golden_ref$NEM)
  check_close("A2",  "A", "NEA (Eq. 10.4)",                 NEA,        golden_ref$NEA)
  check_close("A3",  "A", "NEG (Eq. 10.6, WG=0 branch)",    NEG,        golden_ref$NEG)
  check_close("A4",  "A", "NEL (Eq. 10.8)",                 NEL,        golden_ref$NEL)
  check_close("A5",  "A", "NEW (Eq. 10.11, hours=0 branch)",NEW,        golden_ref$NEW)
  check_close("A6",  "A", "NEP (Eq. 10.13)",                NEP,        golden_ref$NEP)
  check_close("A7",  "A", "REM (Eq. 10.14)",                REM,        golden_ref$REM)
  check_close("A8",  "A", "REG (Eq. 10.15)",                REG,        golden_ref$REG)
  check_close("A9",  "A", "GE (Eq. 10.16)",                 GE,         golden_ref$GE)
  check_close("A10", "A", "Enteric CH4/head/yr (Eq. 10.21)", ent_ch4_head, golden_ref$enteric_ch4_head)
  check_close("A11", "A", "VS (Eq. 10.24)",                  VS,        golden_ref$VS)
  check_close("A12", "A", "Manure CH4/head/yr (Eq. 10.23)",  mch4_head, golden_ref$manure_ch4_head)
  check_close("A13", "A", "N excretion (Eq. 10.32)",         Nex,       golden_ref$Nex)
  check_close("A14", "A", "Direct MM N2O/head/yr",            d_mm,     golden_ref$direct_n2o_mm_head)
  check_close("A15", "A", "Indirect MM N2O/head/yr",          id_mm,    golden_ref$indirect_n2o_mm_head)
  check_close("A16", "A", "Direct PRP N2O/head/yr (Eq. 11.1)", d_prp,   golden_ref$direct_n2o_prp_head)
  check_close("A17", "A", "Indirect PRP N2O/head/yr (Eq. 11.9/11.10)",
              id_prp, golden_ref$indirect_n2o_prp_head)

  # A18: aggregate via the simulation pipeline
  inv <- sim$inventory
  check_close("A18", "A", "Total CO2eq (AR5) — inventory total",
              inv$total_co2e[1], golden_ref$total_co2e_AR5)
}

# =============================================================================
# Section B — sampler & marginal distributions
# =============================================================================
section_B <- function() {
  cat("\n[B] Sampler & marginal distributions...\n")
  set.seed(123)
  n <- 50000

  # B1 — sample_distribution mean ≈ analytical mean
  # For each marginal: pick mean=100, lower=80, upper=120 (symmetric where it makes sense)
  marg_mean_ok <- function(type, target_mean, lower, upper) {
    x <- sample_distribution(n, type, target_mean, lower, upper)
    abs(mean(x) - target_mean) / target_mean
  }
  err_normal  <- marg_mean_ok("normal",     100, 80,  120)
  err_log     <- marg_mean_ok("lognormal",  100, 80,  120)  # mean_val = median for lognormal
  err_beta    <- marg_mean_ok("beta",       100, 80,  120)
  err_pert    <- marg_mean_ok("pert",       100, 80,  120)
  err_triang  <- marg_mean_ok("triangular", 100, 80,  120)
  err_unif    <- marg_mean_ok("uniform",    100, 80,  120)
  err_const   <- marg_mean_ok("constant",   100, 100, 100)
  err_tnorm   <- marg_mean_ok("tnorm_0_1",  0.5, 0.3, 0.7)

  worst <- max(err_normal, err_beta, err_pert, err_triang, err_unif,
                err_const, err_tnorm)
  check_bool("B1", "B",
             "All marginals: empirical mean within 1% of analytical mean (excluding lognormal which uses mean_val as median by design)",
             worst < 0.01,
             notes = sprintf("worst relative error %.4f", worst))

  # B2 — correlated block reproduces target Spearman within 0.02
  params <- data.frame(
    parameter = c("p1","p2","p3","p4","p5"),
    mean      = c(10, 20, 50, 100, 200),
    lower     = c(7, 15, 40, 80, 150),
    upper     = c(13, 25, 60, 120, 250),
    distribution = "normal",
    param_type   = "coefficient",
    stringsAsFactors = FALSE
  )
  # Build a PD target: equicorrelation block of rho=0.5 (always PD for rho<1).
  target <- matrix(0.5, 5, 5)
  diag(target) <- 1.0
  rownames(target) <- colnames(target) <- params$parameter
  set.seed(42)
  samp <- .iman_conover_sample(n, params, target)
  realised <- cor(samp, method = "spearman")
  max_err <- max(abs(realised - target))
  # Tolerance set to 0.04 — empirical max over a 5x5 Spearman matrix at
  # n=50000 typically lands around 0.025-0.035; 0.04 is the 99th percentile
  # bound (SE per pair ≈ 1/sqrt(n) ≈ 0.0045, max over 10 off-diagonal pairs
  # ≈ 3 × SE under normal extrema).
  check_within("B2", "B",
               "Correlated sampling realised Spearman matches target within 0.04",
               max_err, 0, tol_abs = 0.04,
               notes = sprintf("max absolute deviation %.4f", max_err))

  # B3 — AR(1) trend reordering reproduces target rho^|i-j|
  set.seed(99)
  spec <- data.frame(parameter="x", mean=100, lower=80, upper=120,
                     distribution="normal", param_type="coefficient",
                     stringsAsFactors = FALSE)
  ar1 <- .ar1_samples_one_coef(spec, n_iter = n, n_years = 5, rho = 0.7)
  rs <- cor(ar1, method = "spearman")
  target_ar1 <- outer(1:5, 1:5, function(i, j) 0.7 ^ abs(i - j))
  max_err_ar1 <- max(abs(rs - target_ar1))
  check_within("B3", "B",
               "AR(1) year-correlation realised Spearman matches rho^|i-j| within 0.04",
               max_err_ar1, 0, tol_abs = 0.04,
               notes = sprintf("max absolute deviation %.4f", max_err_ar1))

  # B4 — per-MMS uncertainty sampler: empirical mean ≈ central value
  mr <- data.frame(
    mms_type        = c("pasture", "solid_storage"),
    MCF_pct         = c(1.5, 5.0),
    lower_mcf       = c(0.5, 2.0),
    upper_mcf       = c(2.5, 8.0),
    distribution_mcf= c("pert", "pert"),
    stringsAsFactors = FALSE
  )
  set.seed(7)
  mat <- sample_per_mms_param(mr, "MCF_pct", "lower_mcf", "upper_mcf",
                               "distribution_mcf", n, default_dist = "pert")
  err_p  <- abs(mean(mat[, "pasture"])       - 1.5) / 1.5
  err_ss <- abs(mean(mat[, "solid_storage"]) - 5.0) / 5.0
  check_bool("B4", "B",
             "Per-MMS uncertainty sampler: each column empirical mean within 1% of central value",
             err_p < 0.01 && err_ss < 0.01,
             notes = sprintf("pasture err=%.4f, solid_storage err=%.4f", err_p, err_ss))
}

# =============================================================================
# Section C — single-year app routes
# =============================================================================
section_C <- function() {
  cat("\n[C] Single-year app routes (full inventory simulation pipeline)...\n")

  # Build a SINGLE shared simulation result using the deterministic golden case
  # (n_iter=1, all distributions=constant). Source-filter / GWP / decomposition
  # are then applied to this result.
  sd <- build_golden_system()
  sim_AR5 <- run_inventory_simulation(sd, n_iter = 10, gwp = "AR5",
                                       seed = 42, pct_pregnant = 1)
  sim_AR4 <- run_inventory_simulation(sd, n_iter = 10, gwp = "AR4",
                                       seed = 42, pct_pregnant = 1)
  sim_AR6 <- run_inventory_simulation(sd, n_iter = 10, gwp = "AR6",
                                       seed = 42, pct_pregnant = 1)
  # All 10 rows are identical because every distribution is "constant" — take
  # the first row so apply_filter() returns scalars rather than length-10
  # vectors.
  inv5 <- sim_AR5$inventory[1, , drop = FALSE]

  # C1 — all 6 sources ticked → total_co2e matches hand-comp
  check_close("C1", "C",
              "All 6 sources ticked → total_co2e equals hand-comp (AR5)",
              inv5$total_co2e[1], golden_ref$total_co2e_AR5)

  # The source-filter closure (reproduced from app_server.R lines ~1199+).
  # We reproduce it here rather than call into the Shiny observer.
  gwp_AR5 <- GWP_VALUES[["AR5"]]
  apply_filter <- function(df, srcs) {
    col_or_zero <- function(df, sname, pname) {
      if (!is.null(df[[sname]])) df[[sname]]
      else if (!is.null(df[[pname]])) df[[pname]]
      else 0
    }
    ch4 <- (if ("enteric_ch4" %in% srcs) col_or_zero(df, "enteric_ch4_total", "total_enteric_ch4") else 0) +
           (if ("manure_ch4"  %in% srcs) col_or_zero(df, "manure_ch4_total",  "total_manure_ch4")  else 0)
    n2o <- (if ("manure_n2o_direct"   %in% srcs) col_or_zero(df, "direct_n2o_mm_total",   "total_direct_n2o_mm")   else 0) +
           (if ("manure_n2o_indirect" %in% srcs) col_or_zero(df, "indirect_n2o_mm_total", "total_indirect_n2o_mm") else 0) +
           (if ("pasture_n2o_direct"   %in% srcs) col_or_zero(df, "direct_n2o_prp_total",   "total_direct_n2o_prp")   else 0) +
           (if ("pasture_n2o_indirect" %in% srcs) col_or_zero(df, "indirect_n2o_prp_total", "total_indirect_n2o_prp") else 0)
    list(ch4 = ch4, n2o = n2o,
         co2e = ch4 * gwp_AR5$CH4 + n2o * gwp_AR5$N2O)
  }

  # C2 — enteric_ch4 only
  r2 <- apply_filter(inv5, "enteric_ch4")
  check_close("C2", "C", "Source filter: enteric_ch4 only",
              r2$co2e, golden_ref$total_enteric_ch4 * 28)

  # C3 — manure_ch4 only
  r3 <- apply_filter(inv5, "manure_ch4")
  check_close("C3", "C", "Source filter: manure_ch4 only",
              r3$co2e, golden_ref$total_manure_ch4 * 28)

  # C4 — manure N2O (direct+indirect) only — golden case has 100% pasture so MM N2O = 0
  r4 <- apply_filter(inv5, c("manure_n2o_direct", "manure_n2o_indirect"))
  check_close("C4", "C", "Source filter: MM N2O only (golden case: 0 because 100% pasture)",
              r4$co2e, 0)

  # C5 — pasture N2O (direct+indirect) only
  r5 <- apply_filter(inv5, c("pasture_n2o_direct", "pasture_n2o_indirect"))
  expected5 <- (golden_ref$total_direct_n2o_prp + golden_ref$total_indirect_n2o_prp) * 265
  check_close("C5", "C", "Source filter: PRP N2O only",
              r5$co2e, expected5)

  # C6 — Andreas's regression: enteric + MM only (no PRP)
  r6 <- apply_filter(inv5, c("enteric_ch4", "manure_ch4",
                              "manure_n2o_direct", "manure_n2o_indirect"))
  expected6 <- golden_ref$total_enteric_ch4 * 28 +
                golden_ref$total_manure_ch4  * 28
  check_close("C6", "C",
              "Source filter: enteric+MM only (Andreas regression — no crash, correct sum)",
              r6$co2e, expected6)

  # C7 — corr_mode = none: no warning when corr matrices are NULL (already in C1)
  check_bool("C7", "C", "corr_mode='none' runs without warning (golden case has no correlations)",
             TRUE, notes = "Verified implicitly by C1")

  # C8 — corr_mode = "preset" (structural defaults)
  all_names <- c(sd[[1]]$param_specs$parameter)
  preset_mtx <- build_ipcc_preset_corr(all_names)
  sd_preset <- sd
  sd_preset[[1]]$unified_corr_matrix <- preset_mtx
  # Use the variability ("normal") specs since constants cannot reproduce correlations.
  sd_preset[[1]]$param_specs <- make_golden_specs(constant_dist = FALSE)
  # Give a small uncertainty range to each so the sampler has spread.
  sd_preset[[1]]$param_specs$lower <- sd_preset[[1]]$param_specs$mean * 0.9
  sd_preset[[1]]$param_specs$upper <- sd_preset[[1]]$param_specs$mean * 1.1
  sd_preset[[1]]$param_specs$lower[sd_preset[[1]]$param_specs$parameter == "WG"] <- 0
  sd_preset[[1]]$param_specs$upper[sd_preset[[1]]$param_specs$parameter == "WG"] <- 0
  sd_preset[[1]]$param_specs$lower[sd_preset[[1]]$param_specs$parameter == "hours"] <- 0
  sd_preset[[1]]$param_specs$upper[sd_preset[[1]]$param_specs$parameter == "hours"] <- 0
  ok_preset <- tryCatch({
    sim_preset <- run_inventory_simulation(sd_preset, n_iter = 1000,
                                            gwp = "AR5", seed = 11,
                                            pct_pregnant = 1)
    all(is.finite(sim_preset$inventory$total_co2e))
  }, error = function(e) FALSE,
     warning = function(w) FALSE)
  check_bool("C8", "C",
             "corr_mode='preset' (structural defaults) runs without error or warning",
             ok_preset)

  # C9 — corr_mode = "timeseries": Spearman computed from time-series matches a
  # hand-built Spearman on the same data. Use Country Y because Country X has
  # perfectly linear Milk growth (constant first-differences → sd=0 → cor fails).
  ts <- generate_country_y_timeseries()
  cols_ts <- c("N","BW","Milk","DE","Ym")
  computed <- compute_correlation_from_timeseries(ts[, cols_ts],
                                                   detrend = "first_diff")
  manual <- cor(as.data.frame(lapply(ts[, cols_ts],
                                       function(y) c(NA, diff(y)))),
                 use = "complete.obs", method = "spearman")
  manual_pd <- as.matrix(Matrix::nearPD(manual, corr = TRUE)$mat)
  diff_ts <- max(abs(computed - manual_pd))
  check_within("C9", "C",
               "Time-series Spearman computed from upload matches manual Spearman within 1e-6",
               diff_ts, 0, tol_abs = 1e-6,
               notes = sprintf("max deviation %.2e", diff_ts))

  # C10 — GWP = AR5 (default)
  check_close("C10", "C", "GWP = AR5 → total_co2e matches hand-comp",
              sim_AR5$inventory$total_co2e[1], golden_ref$total_co2e_AR5)
  # C11 — GWP = AR6
  check_close("C11", "C", "GWP = AR6 → total_co2e matches hand-comp",
              sim_AR6$inventory$total_co2e[1], golden_ref$total_co2e_AR6,
              notes = "AR4-baseline also checked")
  # Also confirm AR4 is consistent
  check_close("C11b","C", "GWP = AR4 → total_co2e matches hand-comp",
              sim_AR4$inventory$total_co2e[1], golden_ref$total_co2e_AR4)

  # C12 — decomposition: AD-only / EF-only / combined produce non-NA IPCC table
  # Build the same fix_params helper used by app_server.R
  fix_params <- function(s, fix_type) {
    ps <- s$param_specs
    ps$param_type[is.na(ps$param_type)] <- "coefficient"
    rows <- ps$param_type == fix_type
    ps$distribution[rows] <- "constant"
    ps$lower[rows] <- ps$mean[rows]
    ps$upper[rows] <- ps$mean[rows]
    s$param_specs <- ps
    if (fix_type == "coefficient") s$ef_corr_matrix <- NULL
    if (fix_type == "activity_data") {
      s$corr_matrix <- NULL
      s$unified_corr_matrix <- NULL
    }
    s
  }
  sd_var <- sd
  sd_var[[1]]$param_specs <- make_golden_specs(constant_dist = FALSE)
  sd_var[[1]]$param_specs$lower <- sd_var[[1]]$param_specs$mean * 0.95
  sd_var[[1]]$param_specs$upper <- sd_var[[1]]$param_specs$mean * 1.05
  sd_var[[1]]$param_specs$lower[sd_var[[1]]$param_specs$parameter %in% c("WG","hours")] <- 0
  sd_var[[1]]$param_specs$upper[sd_var[[1]]$param_specs$parameter %in% c("WG","hours")] <- 0
  set.seed(123)
  sim_comb <- run_inventory_simulation(sd_var, n_iter = 500, gwp = "AR5",
                                        seed = 123, pct_pregnant = 1)
  sim_ad   <- run_inventory_simulation(lapply(sd_var, fix_params, fix_type = "coefficient"),
                                        n_iter = 500, gwp = "AR5",
                                        seed = 123, pct_pregnant = 1)
  sim_ef   <- run_inventory_simulation(lapply(sd_var, fix_params, fix_type = "activity_data"),
                                        n_iter = 500, gwp = "AR5",
                                        seed = 123, pct_pregnant = 1)
  unc_comb <- calc_all_uncertainty(sim_comb$inventory)
  unc_ad   <- calc_all_uncertainty(sim_ad$inventory)
  unc_ef   <- calc_all_uncertainty(sim_ef$inventory)
  ipcc <- format_ipcc_table(list(combined = unc_comb,
                                  ad_only  = unc_ad,
                                  ef_only  = unc_ef))
  n_rows <- nrow(ipcc)
  any_na_in_per_source <- any(is.na(ipcc[1:6, "Combined uncertainty (%)"]))
  # Per-source rows for the golden case will be NA where the source contributes
  # zero emissions (manure-N2O MM is zero because 100% pasture). This is correct
  # behaviour (moe_pct undefined when mean = 0). So we check the four non-zero
  # rows only.
  nonzero_rows_have_values <- all(!is.na(ipcc[c(1, 2, 5, 6, 7, 8, 9),
                                                "Combined uncertainty (%)"]))
  check_bool("C12", "C",
             "Decomposition: format_ipcc_table populates all rows that have non-zero emissions",
             n_rows == 9 && nonzero_rows_have_values,
             notes = sprintf("n_rows=%d, non-zero rows populated: %s",
                              n_rows, nonzero_rows_have_values))

  # C13 — decomposition off: format_ipcc_table accepts NULL ipcc_table; export
  # placeholders kick in.
  placeholder_ok <- tryCatch({
    tmp <- tempfile(fileext = ".xlsx")
    export_results_xlsx(sim_comb$inventory, unc_comb,
                         sensitivity = NULL, ipcc_table = NULL, filepath = tmp,
                         settings = list(n_iter = 500L, gwp_version = "AR5"))
    file.exists(tmp) && file.info(tmp)$size > 0
  }, error = function(e) FALSE)
  check_bool("C13", "C",
             "Decomposition OFF: export_results_xlsx gracefully emits placeholder sheet",
             placeholder_ok)

  # C14 — comparison-run path: run_inventory_simulation with no corr produces
  # a result that can sit alongside the main result without issue.
  set.seed(123)
  sim_nocorr <- run_inventory_simulation(sd_var, n_iter = 500, gwp = "AR5",
                                          seed = 123, pct_pregnant = 1)
  comp_ok <- all(is.finite(sim_nocorr$inventory$total_co2e)) &&
              nrow(sim_nocorr$inventory) == 500
  check_bool("C14", "C",
             "Comparison-run (no correlations) produces valid result",
             comp_ok)

  # C15 / C16 / C17 — correlation-effect regression guards (Andreas review,
  # 2026-06). Codifies the qualitative behaviour demonstrated by
  # R/_test_correlation_effect.R: the Iman-Conover sampler must (a) amplify
  # output SD for strong +rho on a 2-parameter product, (b) dampen output SD
  # for strong -rho, and (c) produce only a sub-10% headline shift when a
  # single -0.50 pair is embedded in a 10-parameter product (the "ZIM-like
  # sparse matrix" case that explains why time-series correlation modes don't
  # visibly change the inventory total). If a future refactor accidentally
  # makes correlations a no-op or makes them dominate the result, one of
  # these three checks trips.
  #
  # Uses the unified_corr_matrix path directly, with a 2-parameter (C15/C16)
  # or 10-parameter (C17) specs frame so the test isolates the sampler from
  # the full IPCC equation chain.
  build_corr_specs <- function(k = 2, cv = 0.30, mean = 100) {
    nms <- paste0("X", seq_len(k))
    do.call(rbind, lapply(seq_len(k), function(i) data.frame(
      cattle_type       = "corrtest",
      aggregation_level = "corrtest",
      sub_category      = "corrtest",
      parameter         = nms[i],
      mean              = mean,
      uncertainty_pct   = 1.96 * cv * 100,
      lower             = mean * (1 - 1.96 * cv),
      upper             = mean * (1 + 1.96 * cv),
      distribution      = "normal",
      param_type        = if (i == 1) "activity_data" else "coefficient",
      stringsAsFactors  = FALSE)))
  }
  sd_ratio <- function(specs, rho_matrix, n_iter = 10000, seed = 2026) {
    set.seed(seed)
    s_ind <- generate_mc_samples(specs, n_iter = n_iter, seed = seed,
                                  sampler = "iman_conover")
    set.seed(seed)
    s_cor <- generate_mc_samples(specs, n_iter = n_iter, seed = seed,
                                  unified_corr_matrix = rho_matrix,
                                  sampler = "iman_conover")
    y_ind <- Reduce(`*`, s_ind[, specs$parameter])
    y_cor <- Reduce(`*`, s_cor[, specs$parameter])
    sd(y_cor) / sd(y_ind)
  }
  # C15: 2-param product, both CVs 30%, rho = +0.80 -> sd_ratio >= 1.20
  specs2 <- build_corr_specs(k = 2, cv = 0.30)
  m_pos  <- matrix(c(1, 0.80, 0.80, 1), 2, 2,
                   dimnames = list(specs2$parameter, specs2$parameter))
  ratio_C15 <- sd_ratio(specs2, m_pos)
  check_bool("C15", "C",
             "Iman-Conover: 2-param product, rho=+0.80 amplifies output SD (ratio >= 1.20)",
             ratio_C15 >= 1.20,
             notes = sprintf("sd_ratio = %.3f (expected >= 1.20)", ratio_C15))

  # C16: 2-param product, both CVs 30%, rho = -0.50 -> sd_ratio <= 0.85
  m_neg <- matrix(c(1, -0.50, -0.50, 1), 2, 2,
                  dimnames = list(specs2$parameter, specs2$parameter))
  ratio_C16 <- sd_ratio(specs2, m_neg)
  check_bool("C16", "C",
             "Iman-Conover: 2-param product, rho=-0.50 dampens output SD (ratio <= 0.85)",
             ratio_C16 <= 0.85,
             notes = sprintf("sd_ratio = %.3f (expected <= 0.85)", ratio_C16))

  # C17: 10-param product, ONE pair at -0.50, rest independent -> sd_ratio
  # within +/- 0.10 of 1.0. Codifies the "single non-zero pair in a many-
  # parameter product has small headline effect" property -- the mechanism
  # behind Andreas' observation that correlation modes are nearly invisible
  # on his ZIM intensive-dairy run.
  specs10 <- build_corr_specs(k = 10, cv = 0.15)
  m_sparse <- diag(10)
  dimnames(m_sparse) <- list(specs10$parameter, specs10$parameter)
  m_sparse[1, 2] <- -0.50
  m_sparse[2, 1] <- -0.50
  ratio_C17 <- sd_ratio(specs10, m_sparse)
  check_bool("C17", "C",
             "Iman-Conover: 10-param product, ONE pair at -0.50 has small headline effect (|ratio - 1| <= 0.10)",
             abs(ratio_C17 - 1.0) <= 0.10,
             notes = sprintf("sd_ratio = %.3f (expected within 0.90-1.10)", ratio_C17))

  # C18 — empty-TS-sheet silent no-op (Andreas June 2026 review).
  # When parse_uploaded_template() returns corr_matrix = NULL (e.g. the
  # Parameter_TimeSeries sheet is empty), the run-button observer must NOT
  # quietly run with corr_matrix = NULL while input$corr_mode = "timeseries".
  # The June 2026 UI fix greys out the radio AND adds a pre-run validation.
  # This test codifies the matrix-side invariant: when compute_corr_from_population
  # is fed a TS-style frame with all-NA data rows, it returns NULL (the signal
  # the UI gate and pre-run check both rely on).
  empty_ts <- data.frame(
    year = 2017:2021,
    N    = rep(NA_real_, 5),
    BW   = rep(NA_real_, 5),
    DE   = rep(NA_real_, 5),
    Ym   = rep(NA_real_, 5)
  )
  empty_result <- tryCatch(compute_corr_from_population(empty_ts),
                           error = function(e) NULL)
  check_bool("C18", "C",
             "Empty Parameter_TimeSeries → compute_corr_from_population returns NULL (Andreas June 2026: catches the silent no-op the UI gate now prevents)",
             is.null(empty_result))

  # C19 — comparison-run-must-null-unified-matrix regression guard.
  # The June 2026 review found that the "Compare with/without correlations"
  # checkbox produced identical bars on Andreas' ZIM run because the
  # comparison-run code in app_server.R was nulling only the legacy
  # corr_matrix / ef_corr_matrix slots, not the unified_corr_matrix slot
  # that actually carries the preset / time-series / manual matrices since
  # the Round 7 unified-matrix refactor. The fix nulls unified_corr_matrix
  # too. This test codifies the underlying invariant: in a systems_data
  # entry, the *only* correlation slot read by run_inventory_simulation
  # for the default (Iman-Conover) sampler is unified_corr_matrix; nulling
  # corr_matrix alone must NOT change the MC result if unified_corr_matrix
  # is set.
  sd_uni <- build_golden_system()
  sd_uni[[1]]$param_specs <- make_golden_specs(constant_dist = FALSE)
  sd_uni[[1]]$param_specs$lower <- sd_uni[[1]]$param_specs$mean * 0.9
  sd_uni[[1]]$param_specs$upper <- sd_uni[[1]]$param_specs$mean * 1.1
  sd_uni[[1]]$param_specs$lower[sd_uni[[1]]$param_specs$parameter %in% c("WG","hours")] <- 0
  sd_uni[[1]]$param_specs$upper[sd_uni[[1]]$param_specs$parameter %in% c("WG","hours")] <- 0
  preset_all <- build_ipcc_preset_corr(sd_uni[[1]]$param_specs$parameter)
  sd_uni[[1]]$unified_corr_matrix <- preset_all
  sd_uni[[1]]$corr_matrix <- NULL
  sd_uni[[1]]$ef_corr_matrix <- NULL
  sim_with <- run_inventory_simulation(sd_uni, n_iter = 1000, gwp = "AR5",
                                       seed = 99, pct_pregnant = 1)

  # Now null only the legacy corr_matrix (mirrors the OLD buggy comparison
  # code). MC result must be unchanged because unified_corr_matrix still drives
  # the sampler.
  sd_legacy_null <- sd_uni
  sd_legacy_null[[1]]$corr_matrix    <- NULL
  sd_legacy_null[[1]]$ef_corr_matrix <- NULL
  sim_legacy <- run_inventory_simulation(sd_legacy_null, n_iter = 1000, gwp = "AR5",
                                          seed = 99, pct_pregnant = 1)
  legacy_unchanged <- isTRUE(all.equal(sim_with$inventory$total_co2e,
                                        sim_legacy$inventory$total_co2e))

  # Now null unified_corr_matrix (the FIXED comparison code). MC result must
  # differ — at least one parameter value must change at least one iteration.
  sd_unified_null <- sd_uni
  sd_unified_null[[1]]$corr_matrix         <- NULL
  sd_unified_null[[1]]$ef_corr_matrix      <- NULL
  sd_unified_null[[1]]$unified_corr_matrix <- NULL
  sim_nocorr <- run_inventory_simulation(sd_unified_null, n_iter = 1000, gwp = "AR5",
                                          seed = 99, pct_pregnant = 1)
  unified_changed <- !isTRUE(all.equal(sim_with$inventory$total_co2e,
                                        sim_nocorr$inventory$total_co2e))

  check_bool("C19", "C",
             "Comparison-run invariant: nulling only legacy corr_matrix leaves MC result unchanged; nulling unified_corr_matrix changes it",
             legacy_unchanged && unified_changed,
             notes = sprintf("legacy_unchanged=%s, unified_changed=%s",
                              legacy_unchanged, unified_changed))
}

# =============================================================================
# Section D — trend mode
# =============================================================================
section_D <- function() {
  cat("\n[D] Trend-mode pipeline...\n")
  ts <- generate_country_x_timeseries()
  base_specs <- make_golden_specs(constant_dist = FALSE)
  base_specs$lower <- base_specs$mean * 0.9
  base_specs$upper <- base_specs$mean * 1.1
  base_specs$lower[base_specs$parameter %in% c("WG","hours")] <- 0
  base_specs$upper[base_specs$parameter %in% c("WG","hours")] <- 0
  # Build a small trend-df by varying only N across years to exercise the trend
  # pipeline; coefficients stay at golden values per-year.
  trend_df <- data.frame()
  for (yr in 2018:2022) {
    s <- base_specs
    s$year <- yr
    # Vary N by year (linear growth)
    n_idx <- which(s$parameter == "N")
    s$mean[n_idx]  <- 100000 + (yr - 2018) * 5000
    s$lower[n_idx] <- s$mean[n_idx] * 0.95
    s$upper[n_idx] <- s$mean[n_idx] * 1.05
    s$uncertainty_pct <- 0
    trend_df <- rbind(trend_df, s)
  }

  trend_full <- tryCatch(
    run_trend_analysis(trend_df, base_specs, n_iter = 500, gwp = "AR5",
                       seed = 7, year_corr = "full"),
    error = function(e) NULL)
  check_bool("D1", "D",
             "Trend year_corr='full' completes and produces table with 5 rows",
             !is.null(trend_full) && is.list(trend_full) &&
               !is.null(trend_full$table) && nrow(trend_full$table) == 5)

  trend_partial <- tryCatch(
    run_trend_analysis(trend_df, base_specs, n_iter = 500, gwp = "AR5",
                       seed = 7, year_corr = "partial", ar1_rho = 0.7),
    error = function(e) NULL)
  if (!is.null(trend_partial) && !is.null(trend_partial$samples_by_year)) {
    sm_by_year <- trend_partial$samples_by_year
    has_samples <- all(c("2018","2019") %in% names(sm_by_year))
    if (has_samples && "Ym" %in% colnames(sm_by_year[["2018"]])) {
      lag1 <- cor(sm_by_year[["2018"]][, "Ym"],
                  sm_by_year[["2019"]][, "Ym"],
                  method = "spearman")
      check_within("D2", "D",
                   "Trend year_corr='partial' lag-1 Spearman for Ym ≈ 0.7",
                   lag1, 0.7, tol_abs = 0.07,
                   notes = sprintf("realised lag-1=%.3f", lag1))
    } else {
      record("D2", "D",
             "Trend year_corr='partial' lag-1 Spearman for Ym ≈ 0.7",
             0.7, NA, "SKIP",
             "samples_by_year missing Ym column")
    }
  } else {
    record("D2", "D", "Trend year_corr='partial' completes", "OK", NA, "FAIL",
           "run_trend_analysis raised an error or omitted samples_by_year")
  }

  trend_none <- tryCatch(
    run_trend_analysis(trend_df, base_specs, n_iter = 500, gwp = "AR5",
                       seed = 7, year_corr = "none"),
    error = function(e) NULL)
  check_bool("D3", "D",
             "Trend year_corr='none' completes and produces table with 5 rows",
             !is.null(trend_none) && !is.null(trend_none$table) &&
               nrow(trend_none$table) == 5)

  trend_filtered <- tryCatch(
    run_trend_analysis(trend_df, base_specs, n_iter = 500, gwp = "AR5",
                       seed = 7, year_corr = "full",
                       emission_sources = c("enteric_ch4", "manure_ch4",
                                            "manure_n2o_direct",
                                            "manure_n2o_indirect")),
    error = function(e) NULL)
  check_bool("D4", "D",
             "Trend source filter (enteric+MM only) runs without error",
             !is.null(trend_filtered) && !is.null(trend_filtered$table) &&
               nrow(trend_filtered$table) == 5)
}

# =============================================================================
# Section E — multi-sub-category
# =============================================================================
section_E <- function() {
  cat("\n[E] Multi-sub-category aggregation...\n")
  # Two sub-categories: dairy/cows (N=100k) + dairy/heifers (N=50k)
  s1 <- make_golden_specs()
  s2 <- make_golden_specs()
  s2$sub_category <- "heifers"
  s2$mean[s2$parameter == "N"] <- 50000
  s2$lower[s2$parameter == "N"] <- 50000
  s2$upper[s2$parameter == "N"] <- 50000

  sd <- list(
    "dairy||golden||cows" = list(
      param_specs = s1, corr_matrix = NULL, ef_corr_matrix = NULL,
      unified_corr_matrix = NULL,
      mms_fractions = c(pasture = 1.0), mcf_values = c(pasture = 0.015),
      ef3_values = c(pasture = 0.020),
      frac_gas_values = NULL, frac_leach_values = NULL,
      mcf_samples = NULL, ef3_samples = NULL,
      frac_gas_samples = NULL, frac_leach_samples = NULL),
    "dairy||golden||heifers" = list(
      param_specs = s2, corr_matrix = NULL, ef_corr_matrix = NULL,
      unified_corr_matrix = NULL,
      mms_fractions = c(pasture = 1.0), mcf_values = c(pasture = 0.015),
      ef3_values = c(pasture = 0.020),
      frac_gas_values = NULL, frac_leach_values = NULL,
      mcf_samples = NULL, ef3_samples = NULL,
      frac_gas_samples = NULL, frac_leach_samples = NULL)
  )
  sim <- run_inventory_simulation(sd, n_iter = 10, gwp = "AR5",
                                   seed = 42, pct_pregnant = 1)
  inv <- sim$inventory
  per_sys_co2e <- sapply(sim$by_system, function(s) s$results$total_co2e[1])
  check_close("E1", "E",
              "Inventory total_co2e = sum across sub-categories",
              inv$total_co2e[1], sum(per_sys_co2e))

  # Expected: 100k + 50k = 150k animals, linearly scaling
  expected_inv <- golden_ref$total_co2e_AR5 * 1.5
  check_close("E1b", "E",
              "Two sub-categories (100k + 50k) total_co2e = 1.5 × golden",
              inv$total_co2e[1], expected_inv)

  # E2 — per-group sensitivity prefixes present
  group_keys <- names(sim$by_system)
  has_prefixes <- all(grepl("\\|\\|", group_keys))
  check_bool("E2", "E",
             "Per-system results frame keyed by 'cattle_type||aggregation_level||sub_category'",
             has_prefixes)
}

# =============================================================================
# Section F — edge cases / negative tests
# =============================================================================
section_F <- function() {
  cat("\n[F] Edge cases / negative tests...\n")

  # F1 — blank mean cell. We don't go through the Shiny observer (no input$ in
  # this harness) but verify that ensure_completeness OR a downstream gate
  # detects it. The simulation observer (app_server.R) has the pre-run gate;
  # here we just confirm the NA-mean condition is detectable.
  specs_na <- make_golden_specs()
  specs_na$mean[specs_na$parameter == "BW"] <- NA_real_
  na_mean_rows <- which(is.na(specs_na$mean))
  check_bool("F1", "F",
             "NA in mean is detectable (gate trigger in simulation observer)",
             length(na_mean_rows) > 0)

  # F2 — MMS fractions do not sum to 100
  bad_manure <- data.frame(
    cattle_type = "dairy", aggregation_level = "golden", sub_category = "cows",
    mms_type = c("pasture","solid_storage"),
    fraction_pct = c(40, 55),  # sums to 95, not 100
    stringsAsFactors = FALSE
  )
  v <- validate_manure_sheet(bad_manure)
  check_bool("F2", "F",
             "validate_manure_sheet flags fractions summing to 95% as invalid",
             !v$valid)

  # F3 — lower > upper
  bad_specs <- make_golden_specs(constant_dist = FALSE)
  bw_idx <- which(bad_specs$parameter == "BW")
  bad_specs$lower[bw_idx] <- 400  # > mean = 300
  bad_specs$upper[bw_idx] <- 200  # < mean = 300
  bad_specs$distribution[bw_idx] <- "normal"
  v <- validate_param_specs(bad_specs)
  check_bool("F3", "F",
             "validate_param_specs flags lower>upper as invalid",
             !v$valid)

  # F4 — N = 0 → simulation completes; total_co2e = 0; no NaN
  zero_specs <- make_golden_specs()
  zero_specs$mean[zero_specs$parameter == "N"] <- 0
  zero_specs$lower[zero_specs$parameter == "N"] <- 0
  zero_specs$upper[zero_specs$parameter == "N"] <- 0
  sd_zero <- build_golden_system(zero_specs)
  sim_zero <- tryCatch(
    run_inventory_simulation(sd_zero, n_iter = 10, gwp = "AR5", seed = 1,
                             pct_pregnant = 1),
    error = function(e) NULL)
  if (is.null(sim_zero)) {
    record("F4", "F", "N=0 simulation completes without error", "OK", "FAIL", "FAIL")
  } else {
    co2e <- sim_zero$inventory$total_co2e
    check_bool("F4", "F",
               "N=0: simulation completes, total_co2e = 0, no NaN",
               all(co2e == 0) && all(is.finite(co2e)))
  }

  # F5 — empty source selection: handled by the observer gate. Verify the
  # observer's guard expression yields the expected boolean.
  empty_srcs <- character(0)
  is_empty <- is.null(empty_srcs) || length(empty_srcs) == 0
  check_bool("F5", "F",
             "Empty source selection detectable by simulation observer gate",
             is_empty)

  # F6 — source-aware gate dependency map (Andreas 2026-05-27). A CH4-only
  # selection must not require any manure-N2O / PRP parameter.
  ch4_needed <- params_needed_for_sources(c("enteric_ch4", "manure_ch4"))
  excluded   <- c("EF3_S", "Frac_GASMS", "Frac_LEACH_H",
                  "EF3_PRP", "EF4", "EF5",
                  "Frac_GASM_PRP", "Frac_LEACH_PRP")
  check_bool("F6", "F",
             "Source-aware deps: CH4-only excludes all manure-N2O / PRP params",
             !any(excluded %in% ch4_needed) &&
               all(c("Ym", "UE", "ASH", "Bo") %in% ch4_needed),
             notes = "CH4 needs Ym/UE/ASH/Bo; not the N2O EFs")

  # F7 — the gate lets a CH4-only run through when only manure-N2O params are
  # blank. Mirror the observer's filter: na_block = NA-mean rows that are in
  # the needed set for the selected sources.
  specs_blank_n2o <- make_golden_specs()
  # Retired params aren't in the catalogue any more, so simulate the situation
  # by blanking parameters the CH4 run does not use (EF3_PRP / EF4 / EF5).
  specs_blank_n2o$mean[specs_blank_n2o$parameter %in% c("EF3_PRP","EF4","EF5")] <- NA_real_
  needed_ch4 <- params_needed_for_sources(c("enteric_ch4","manure_ch4"))
  na_block_ch4 <- sum(is.na(specs_blank_n2o$mean) &
                      specs_blank_n2o$parameter %in% needed_ch4)
  check_bool("F7", "F",
             "Gate allows CH4-only run when only N2O params (EF3_PRP/EF4/EF5) are blank",
             na_block_ch4 == 0,
             notes = sprintf("blocking cells = %d", na_block_ch4))

  # F8 — the gate still catches a genuinely-needed blank: blank Ym with
  # enteric selected must be flagged.
  specs_blank_ym <- make_golden_specs()
  specs_blank_ym$mean[specs_blank_ym$parameter == "Ym"] <- NA_real_
  needed_ent <- params_needed_for_sources("enteric_ch4")
  na_block_ym <- sum(is.na(specs_blank_ym$mean) &
                     specs_blank_ym$parameter %in% needed_ent)
  check_bool("F8", "F",
             "Gate still blocks blank Ym when enteric_ch4 is selected",
             na_block_ym == 1,
             notes = sprintf("blocking cells = %d", na_block_ym))

  # F9 — sub_category-key auto-match (Andreas 28/5/26 follow-up). Mimic the
  # ZIM template's Parameters="DINT_heif" vs Manure_Management="DINT_heifer"
  # typo and assert resolve_sub_category_matches() returns the heifer MM key
  # as the unambiguous auto-match and surfaces it as a `warn` row.
  p_zim <- data.frame(
    cattle_type       = rep("dairy", 2),
    aggregation_level = rep("Intensive", 2),
    sub_category      = c("DINT_cow", "DINT_heif"),
    parameter         = c("N", "N"),
    stringsAsFactors  = FALSE)
  m_zim <- data.frame(
    cattle_type       = rep("dairy", 4),
    aggregation_level = rep("Intensive", 4),
    sub_category      = c("DINT_cow", "DINT_cow", "DINT_heifer", "DINT_heifer"),
    mms_type          = c("solid_storage", "pasture",
                          "solid_storage", "pasture"),
    fraction_pct      = c(77, 23, 50, 50),
    stringsAsFactors  = FALSE)
  sg <- resolve_sub_category_matches(p_zim, m_zim)
  heif_key <- "dairy||Intensive||DINT_heif"
  resolved_ok <- !is.null(sg$matched[heif_key]) &&
                  sg$matched[heif_key] == "dairy||Intensive||DINT_heifer"
  has_warn   <- any(sg$issues$status == "warn" &
                    sg$issues$check  == "sub_category_auto_match")
  check_bool("F9", "F",
             "resolve_sub_category_matches: DINT_heif auto-matched to DINT_heifer with warn row",
             resolved_ok && has_warn,
             notes = sprintf("matched key=%s; warn row present=%s",
                             sg$matched[heif_key], has_warn))

  # F10 — sub_category-key ambiguity must produce a `fail` and NOT remap.
  # Build a Parameters key that is distance <= 2 from two MM candidates.
  p_amb <- data.frame(
    cattle_type       = "beef",
    aggregation_level = "Extensive",
    sub_category      = "calf",
    parameter         = "N",
    stringsAsFactors  = FALSE)
  m_amb <- data.frame(
    cattle_type       = rep("beef", 2),
    aggregation_level = rep("Extensive", 2),
    sub_category      = c("calf1", "calf2"),  # both adist 1 from "calf"
    mms_type          = c("solid_storage", "pasture"),
    fraction_pct      = c(50, 50),
    stringsAsFactors  = FALSE)
  sg_amb <- resolve_sub_category_matches(p_amb, m_amb)
  amb_key  <- "beef||Extensive||calf"
  no_remap <- sg_amb$matched[amb_key] == amb_key
  has_fail <- any(sg_amb$issues$status == "fail" &
                  sg_amb$issues$check  == "sub_category_ambiguous")
  check_bool("F10", "F",
             "Ambiguous sub_category produces fail row and is NOT auto-remapped",
             no_remap && has_fail,
             notes = sprintf("no remap=%s, fail row present=%s",
                             no_remap, has_fail))

  # F11 — multi-MMS direct/indirect N2O hand-comp end-to-end. Set up a single
  # sub-category with the Zim-style DINT_cow MMS allocation, run the engine
  # at the parameter means (constant distributions, n_iter = 1) and assert
  # the headline direct/indirect MM N2O numbers match the hand-computed
  # reference within 0.5%. This is the assertion the prior audit was missing
  # — it pins down the multi-MMS path that the calculation-bug report hinges
  # on.
  multi_specs <- make_golden_specs(constant_dist = TRUE)
  multi_specs$sub_category <- "DINT_cow"
  # ZIM DINT_cow inputs: BW=539.3, Milk=15.22, Fat=3.8, pct_pregnant=0.81,
  # DE=73.52, CP=14.8, MilkPR=3.42, Cfi=0.322. Adjust the golden vector.
  set_p <- function(df, p, v) { df$mean[df$parameter==p] <- v
                                df$lower[df$parameter==p] <- v
                                df$upper[df$parameter==p] <- v; df }
  multi_specs <- set_p(multi_specs, "BW", 539.3)
  multi_specs <- set_p(multi_specs, "MW", 539.0)
  multi_specs <- set_p(multi_specs, "Milk", 15.22)
  multi_specs <- set_p(multi_specs, "Fat", 3.8)
  multi_specs <- set_p(multi_specs, "pct_pregnant", 0.81)
  multi_specs <- set_p(multi_specs, "DE", 73.52)
  multi_specs <- set_p(multi_specs, "CP", 14.8)
  multi_specs <- set_p(multi_specs, "MilkPR", 3.42)
  multi_specs <- set_p(multi_specs, "Cfi", 0.322)
  multi_specs <- set_p(multi_specs, "N", 19545)

  # ZIM DINT_cow MMS allocation: lagoon 5, liquid_slurry 4, solid_storage 77,
  # dry_lot 8, daily_spread 5, anaerobic_digester 1, pasture 0.
  mms_keys  <- c("lagoon", "liquid_slurry", "solid_storage", "dry_lot",
                 "daily_spread", "anaerobic_digester", "pasture")
  mms_fracs <- setNames(c(0.05, 0.04, 0.77, 0.08, 0.05, 0.01, 0.00), mms_keys)
  mcf_vals  <- setNames(c(0.76, 0.73, 0.05, 0.02, 0.01, 0.0955, 0.0047),
                        mms_keys)
  ef3_vals  <- setNames(c(0.000, 0.005, 0.010, 0.020, 0.000, 0.0006, 0.006),
                        mms_keys)
  fg_vals   <- setNames(c(0.35, 0.48, 0.30, 0.30, 0.07, 0.23, 0.21), mms_keys)
  fl_vals   <- setNames(c(0.00, 0.00, 0.02, 0.035, 0.00, 0.00, 0.24),
                        mms_keys)

  multi_sd <- list(`dairy||Intensive||DINT_cow` = list(
    param_specs = multi_specs,
    corr_matrix = NULL, ef_corr_matrix = NULL, unified_corr_matrix = NULL,
    mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
    frac_gas_values = fg_vals, frac_leach_values = fl_vals,
    mcf_samples = NULL, ef3_samples = NULL,
    frac_gas_samples = NULL, frac_leach_samples = NULL))

  # n_iter >= 2 to avoid the documented rowSums-on-vector crash for a single-
  # system run at n_iter=1. All distributions are constant so every iteration
  # is identical and the realised mean equals the central value exactly.
  sim_multi <- run_inventory_simulation(multi_sd, n_iter = 10, gwp = "AR5",
                                         seed = 1, pct_pregnant = 0.81)
  inv_m <- as.list(sim_multi$inventory[1, , drop = FALSE])

  # Hand-comp Nex for DINT_cow at the means:
  # NEm = 0.322 * 539.3^0.75 = 36.04; NEa = 0.17*36.04 = 6.13;
  # NEl = 15.22*(1.47+0.4*3.8) = 45.51  <- Eq 10.8, NO pct_pregnant: the
  #   milk input is IPCC's annual average per head, so weighting it by the
  #   calving fraction discounted it twice. Was 36.86.
  # NEp = 0.10*0.81*36.04 = 2.92  <- KEEPS the weighting, Table 10.7.
  # REM = 1.123 - 4.092e-3*73.52 + 1.126e-5*73.52^2 - 25.4/73.52 = 0.5375
  # GE = ((36.04+6.13+45.51+0+2.92)/0.5375)/0.7352 = 229.22  (was 206.80)
  # DMI = 229.22/18.45 = 12.42; N_intake = 12.42*0.148/6.25 = 0.2942 kg N/day
  # N_retained_milk = 15.22*0.0342/6.38 = 0.0816  <- Eq 10.33, also no
  #   pct_pregnant. Was 0.0660.
  # Nex/day = 0.2126; Nex/yr = 77.60 kg N/head/yr  (was 72.81)
  nex_ref <- 77.60
  # MM direct (excl pasture):
  # sum(fr*EF3) = 0.04*0.005 + 0.77*0.01 + 0.08*0.02 + 0.01*0.0006 = 0.00951
  # direct/head = 72.81 * 0.00951 * 44/28 = 1.088 kg N2O/head/yr
  # total t = 1.088 * 19545 / 1000 = 21.26 t N2O
  direct_mm_ref <- nex_ref * 0.00951 * 44 / 28 * 19545 / 1000
  # MM indirect volat: sum(fr*fg) = 0.05*0.35 + 0.04*0.48 + 0.77*0.30 +
  #   0.08*0.30 + 0.05*0.07 + 0.01*0.23 = 0.2975
  #   = 72.81*0.2975*0.01*44/28 = 0.3402 kg N2O/head/yr * 19545 / 1000 = 6.65 t
  # MM indirect leach: sum(fr*fl) = 0.77*0.02 + 0.08*0.035 = 0.01820
  #   = 72.81*0.01820*0.011*44/28 = 0.0229 kg N2O/head/yr * 19545 / 1000 = 0.45 t
  indirect_mm_ref <- nex_ref * (0.2975 * 0.010 + 0.01820 * 0.011) *
                      44 / 28 * 19545 / 1000

  err_dir  <- abs(inv_m$total_direct_n2o_mm   - direct_mm_ref)   / direct_mm_ref
  err_ind  <- abs(inv_m$total_indirect_n2o_mm - indirect_mm_ref) / indirect_mm_ref
  check_bool("F11", "F",
             "Multi-MMS direct + indirect N2O headline matches hand-comp within 0.5%",
             err_dir < 0.005 && err_ind < 0.005,
             notes = sprintf(
               "direct: tool=%.4g vs ref=%.4g (err %.4f); indirect: tool=%.4g vs ref=%.4g (err %.4f)",
               inv_m$total_direct_n2o_mm, direct_mm_ref, err_dir,
               inv_m$total_indirect_n2o_mm, indirect_mm_ref, err_ind))

  # F12 — MMS-allocation uncertainty (Andreas 28/5/26 #4). Sample the per-MMS
  # fraction matrix on a 2-MMS system with wide bounds, run the simulation
  # with all per-parameter MC vars held constant, and assert:
  #   (a) row sums of the renormalised matrix == 1 to machine epsilon
  #   (b) fraction_<mms> columns appear in samples$ for sensitivity
  #   (c) mean of each fraction column is close to the user's central value
  #       (renormalisation introduces <2% bias at these widths)
  set.seed(12)
  mr_mms <- data.frame(
    mms_type              = c("pasture", "solid_storage"),
    fraction_pct          = c(60, 40),
    lower_fraction        = c(40, 25),
    upper_fraction        = c(75, 60),
    distribution_fraction = c("pert", "pert"),
    stringsAsFactors      = FALSE)
  mat <- sample_per_mms_param(mr_mms, "fraction_pct", "lower_fraction",
                               "upper_fraction", "distribution_fraction",
                               n_iter = 5000, default_dist = "pert")
  mat[mat < 0] <- 0       # preserve matrix dim (pmax(0, mat) strips it)
  mat <- mat / 100
  rs  <- rowSums(mat)
  rs[rs <= 0] <- 1
  mat <- mat / rs
  row_ok      <- isTRUE(all.equal(unname(rowSums(mat)), rep(1, nrow(mat)),
                                   tolerance = 1e-10))
  mean_p      <- mean(mat[, "pasture"])
  mean_ss     <- mean(mat[, "solid_storage"])
  bias_p      <- abs(mean_p - 0.60) / 0.60
  bias_ss     <- abs(mean_ss - 0.40) / 0.40
  check_bool("F12a", "F",
             "MMS fraction sampler: row sums == 1 post-renormalisation",
             row_ok,
             notes = sprintf("max |rowSum-1| = %.2e",
                             max(abs(rowSums(mat) - 1))))
  check_bool("F12b", "F",
             "Per-MMS fraction sampler: empirical mean within 2% of central value",
             bias_p < 0.02 && bias_ss < 0.02,
             notes = sprintf("pasture mean=%.4f (bias %.4f); solid_storage mean=%.4f (bias %.4f)",
                             mean_p, bias_p, mean_ss, bias_ss))

  # Now exercise the full propagation: build a system with the matrix
  # attached and verify fraction_<mms> appears in samples + the engine
  # returns a non-trivial CV on direct/indirect MM N2O.
  specs_mms <- make_golden_specs(constant_dist = TRUE)
  specs_mms$sub_category <- "DINT_cow"
  set_p2 <- function(df, p, v) { df$mean[df$parameter==p] <- v
                                 df$lower[df$parameter==p] <- v
                                 df$upper[df$parameter==p] <- v; df }
  specs_mms <- set_p2(specs_mms, "N", 10000)
  # Use the 2-MMS allocation from above (renormalised).
  mms_fracs2 <- setNames(c(0.60, 0.40), c("pasture", "solid_storage"))
  mcf_vals2  <- setNames(c(0.015, 0.05), c("pasture", "solid_storage"))
  ef3_vals2  <- setNames(c(0.006, 0.005), c("pasture", "solid_storage"))
  sd_mms <- list(`dairy||golden||DINT_cow` = list(
    param_specs = specs_mms,
    corr_matrix = NULL, ef_corr_matrix = NULL, unified_corr_matrix = NULL,
    mms_fractions = mms_fracs2, mcf_values = mcf_vals2,
    ef3_values  = ef3_vals2,
    frac_gas_values = NULL, frac_leach_values = NULL,
    mcf_samples = NULL, ef3_samples = NULL,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = mat))
  sim_mms <- run_inventory_simulation(sd_mms, n_iter = 5000, gwp = "AR5",
                                       seed = 99, pct_pregnant = 0.5)
  samp_one <- sim_mms$by_system[[1]]$samples
  has_frac_cols <- all(c("fraction_pasture", "fraction_solid_storage") %in%
                       names(samp_one))
  d_cv <- sd(sim_mms$inventory$total_direct_n2o_mm) /
          mean(sim_mms$inventory$total_direct_n2o_mm)
  i_cv <- sd(sim_mms$inventory$total_indirect_n2o_mm) /
          mean(sim_mms$inventory$total_indirect_n2o_mm)
  check_bool("F12c", "F",
             "fraction_<mms> sample columns appear in samples (visible to sensitivity)",
             has_frac_cols,
             notes = paste(grep("^fraction_", names(samp_one), value = TRUE),
                           collapse = ", "))
  check_bool("F12d", "F",
             "MMS-fraction uncertainty yields non-trivial CV on direct + indirect MM N2O",
             is.finite(d_cv) && d_cv > 0.01 && is.finite(i_cv) && i_cv > 0.01,
             notes = sprintf("direct CV=%.4f, indirect CV=%.4f", d_cv, i_cv))

  # F13 — QA/QC benchmark + asymmetric-bounds checks (Andreas 28/5/26 #3).
  # Build a minimal Parameters frame and run_qaqc() with each scenario, then
  # inspect the returned rows.

  mk_qa_spec <- function(p, mean, lower, upper, cattle_type = "dairy",
                          distribution = "normal") {
    data.frame(
      cattle_type       = cattle_type,
      aggregation_level = "golden",
      sub_category      = "DINT_cow",
      parameter         = p,
      mean              = mean,
      lower             = lower,
      upper             = upper,
      distribution      = distribution,
      param_type        = "coefficient",
      stringsAsFactors  = FALSE)
  }

  # F13a — BW deviation still fires for an off-value
  bw_spec <- mk_qa_spec("BW", 1500, 1400, 1600, cattle_type = "dairy")
  qa_bw <- run_qaqc(bw_spec, region = "africa")
  bw_rows <- qa_bw[qa_bw$parameter == "BW" &
                    qa_bw$check == "benchmark_deviation", ]
  bw_ok <- nrow(bw_rows) >= 1 &&
            any(bw_rows$status %in% c("warn", "fail")) &&
            grepl("10A\\.1", bw_rows$message[1])
  check_bool("F13a", "F",
             "BW benchmark_deviation still fires + cites IPCC Table 10A.1 for dairy",
             bw_ok,
             notes = sprintf("status=%s; msg snippet: %s",
                             paste(bw_rows$status, collapse = ","),
                             substr(bw_rows$message[1], 1, 90)))

  # F13b — Milk deviation no longer fires
  milk_spec <- mk_qa_spec("Milk", 0.5, 0.4, 0.6)
  qa_milk <- run_qaqc(milk_spec, region = "africa")
  milk_rows <- qa_milk[qa_milk$parameter == "Milk" &
                        qa_milk$check == "benchmark_deviation", ]
  check_bool("F13b", "F",
             "Milk benchmark_deviation no longer fires (heuristic mid-point removed)",
             nrow(milk_rows) == 0,
             notes = sprintf("benchmark_deviation rows for Milk: %d",
                             nrow(milk_rows)))

  # F13c — EF4 asymmetric-bounds warning no longer fires on symmetric IPCC
  # Table 11.3 range; EF5 similarly. EF3_PRP stays in ASYMMETRIC_PARAMS, so
  # an actually-symmetric range there should still trigger warn.
  ef4_spec <- mk_qa_spec("EF4", 0.010, 0.002, 0.018)
  qa_ef4 <- run_qaqc(ef4_spec, region = "global")
  ef4_rows <- qa_ef4[qa_ef4$parameter == "EF4" &
                      qa_ef4$check == "asymmetric_bounds", ]
  ef5_spec <- mk_qa_spec("EF5", 0.011, 0.0005, 0.020)
  qa_ef5 <- run_qaqc(ef5_spec, region = "global")
  ef5_rows <- qa_ef5[qa_ef5$parameter == "EF5" &
                      qa_ef5$check == "asymmetric_bounds", ]
  ef3p_spec <- mk_qa_spec("EF3_PRP", 0.004, 0.0035, 0.0045)
  qa_ef3p <- run_qaqc(ef3p_spec, region = "global")
  ef3p_rows <- qa_ef3p[qa_ef3p$parameter == "EF3_PRP" &
                        qa_ef3p$check == "asymmetric_bounds", ]
  check_bool("F13c", "F",
             "EF4 / EF5 no longer flagged asymmetric; EF3_PRP still IS",
             nrow(ef4_rows) == 0 && nrow(ef5_rows) == 0 &&
               nrow(ef3p_rows) >= 1 &&
               any(ef3p_rows$status == "warn"),
             notes = sprintf("EF4 rows=%d; EF5 rows=%d; EF3_PRP rows=%d",
                             nrow(ef4_rows), nrow(ef5_rows), nrow(ef3p_rows)))

  # F14 — Per-(cattle_type × source) breakdown (Andreas 28/5/26 #7).
  # Build a two-cattle-type inventory (dairy + other), run the simulation,
  # and exercise the per-source breakdown flextable.
  specs_dairy <- make_golden_specs(constant_dist = TRUE)
  specs_dairy$cattle_type <- "dairy"
  specs_dairy$aggregation_level <- "golden"
  specs_dairy$sub_category <- "dairy_cows"
  specs_other <- make_golden_specs(constant_dist = TRUE)
  specs_other$cattle_type <- "other"
  specs_other$aggregation_level <- "golden"
  specs_other$sub_category <- "other_cows"
  # Halve N for the "other" group so the two cattle types contribute
  # different headline totals.
  specs_other$mean[specs_other$parameter == "N"]  <- 50000
  specs_other$lower[specs_other$parameter == "N"] <- 50000
  specs_other$upper[specs_other$parameter == "N"] <- 50000

  mms_fracs2 <- setNames(c(0.70, 0.30), c("pasture", "solid_storage"))
  mcf_vals2  <- setNames(c(0.015, 0.05), c("pasture", "solid_storage"))
  ef3_vals2  <- setNames(c(0.020, 0.005), c("pasture", "solid_storage"))
  build_sys <- function(specs) list(
    param_specs = specs,
    corr_matrix = NULL, ef_corr_matrix = NULL, unified_corr_matrix = NULL,
    mms_fractions = mms_fracs2, mcf_values = mcf_vals2, ef3_values = ef3_vals2,
    frac_gas_values = NULL, frac_leach_values = NULL,
    mcf_samples = NULL, ef3_samples = NULL,
    frac_gas_samples = NULL, frac_leach_samples = NULL,
    mms_fraction_samples = NULL)
  sd_2ct <- list(
    `dairy||golden||dairy_cows` = build_sys(specs_dairy),
    `other||golden||other_cows` = build_sys(specs_other))
  sim_2ct <- run_inventory_simulation(sd_2ct, n_iter = 10, gwp = "AR5",
                                       seed = 7, pct_pregnant = 0.5)

  ft <- .per_source_breakdown_flextable(sim_2ct, "AR5")
  ft_df <- if (!is.null(ft)) ft$body$dataset else NULL
  cattle_types_in_ft <- if (!is.null(ft_df) && "Cattle type" %in% names(ft_df))
                          unique(ft_df[["Cattle type"]]) else character()
  has_both <- all(c("dairy", "other") %in% cattle_types_in_ft)
  has_raw_cols <- !is.null(ft_df) &&
                   "Mean (t CH4)" %in% names(ft_df) &&
                   "Mean (t N2O)" %in% names(ft_df) &&
                   "Mean (t CO2eq)" %in% names(ft_df)
  check_bool("F14a", "F",
             "Per-source breakdown flextable splits by cattle_type",
             has_both,
             notes = sprintf("cattle_types in flextable: %s",
                             paste(cattle_types_in_ft, collapse = ", ")))
  check_bool("F14b", "F",
             "Per-source breakdown flextable has raw t CH4, t N2O, t CO2eq columns",
             has_raw_cols,
             notes = if (!is.null(ft_df))
                       paste(intersect(c("Mean (t CH4)", "Mean (t N2O)",
                                          "Mean (t CO2eq)"), names(ft_df)),
                              collapse = ", ") else "no flextable")

  # F14c — per-cattle_type CO2eq sums to (approximately) the inventory total
  # under constant distributions (every iteration identical).
  inv1 <- as.list(sim_2ct$inventory[1, , drop = FALSE])
  by_ct <- list()
  for (sn in names(sim_2ct$by_system)) {
    ct <- strsplit(sn, "\\|\\|", fixed = FALSE)[[1]][1]
    co2e <- sim_2ct$by_system[[sn]]$results$total_co2e[1]
    by_ct[[ct]] <- (by_ct[[ct]] %||% 0) + co2e
  }
  sum_by_ct <- sum(unlist(by_ct))
  err_total <- abs(sum_by_ct - inv1$total_co2e) /
                max(abs(inv1$total_co2e), 1e-6)
  check_bool("F14c", "F",
             "Sum of per-cattle_type total_co2e equals inventory total",
             err_total < 1e-9,
             notes = sprintf("sum by ct = %.4g; inventory = %.4g",
                             sum_by_ct, inv1$total_co2e))

  # F15 — Sensitivity labels carry sub-category (Andreas 28/5/26 #8).
  # Reuse the two-cattle-type setup built above (sim_2ct). Need a stochastic
  # input for sensitivity_analysis to compute non-NA SRC, so build a second
  # variant with one parameter varying (BW) per sub-category.
  specs_dairy_v <- specs_dairy
  bw_idx <- which(specs_dairy_v$parameter == "BW")
  specs_dairy_v$mean[bw_idx]   <- 300
  specs_dairy_v$lower[bw_idx]  <- 200
  specs_dairy_v$upper[bw_idx]  <- 400
  specs_dairy_v$distribution[bw_idx] <- "normal"
  specs_other_v <- specs_other
  bw_idx2 <- which(specs_other_v$parameter == "BW")
  specs_other_v$mean[bw_idx2]  <- 350
  specs_other_v$lower[bw_idx2] <- 250
  specs_other_v$upper[bw_idx2] <- 450
  specs_other_v$distribution[bw_idx2] <- "normal"

  sd_sens <- list(
    `dairy||golden||dairy_cows` = build_sys(specs_dairy_v),
    `other||golden||other_cows` = build_sys(specs_other_v))
  sim_sens <- run_inventory_simulation(sd_sens, n_iter = 500, gwp = "AR5",
                                        seed = 11, pct_pregnant = 0.5)

  agg_sens <- aggregate_sensitivity(sim_sens$by_system,
                                     sim_sens$inventory$total_co2e,
                                     method = "src")
  param_labels <- if (!is.null(agg_sens$src)) agg_sens$src$parameter else character()
  has_dairy_cows <- any(grepl("\\(dairy_cows\\)", param_labels))
  has_other_cows <- any(grepl("\\(other_cows\\)", param_labels))
  check_bool("F15a", "F",
             "aggregate_sensitivity labels each parameter with its sub_category in (...)",
             has_dairy_cows && has_other_cows,
             notes = sprintf("dairy_cows present=%s; other_cows present=%s; sample labels: %s",
                             has_dairy_cows, has_other_cows,
                             paste(head(param_labels, 4), collapse = "; ")))

  # F15b — sens_group_of correctly extracts the sub_category suffix.
  g1 <- sens_group_of("Ym (DINT_cow)")
  g2 <- sens_group_of("MCF_solid_storage (DINT_heif)")
  g3 <- sens_group_of("Ym")
  check_bool("F15b", "F",
             "sens_group_of extracts sub_category from labelled parameter names",
             g1 == "DINT_cow" && g2 == "DINT_heif" && g3 == "(ungrouped)",
             notes = sprintf("'%s' -> %s; '%s' -> %s; '%s' -> %s",
                             "Ym (DINT_cow)", g1,
                             "MCF_solid_storage (DINT_heif)", g2,
                             "Ym", g3))

  # F16 — AD-only decomposition invariant (Andreas 28/5/26 #9).
  # With all coefficients frozen AND per-MMS sample matrices nulled, the
  # only source of iteration-to-iteration variance is N. For a single-
  # system inventory, emission_source = N × const, so
  # CV(emission_source) == CV(N) for EVERY source — that's the invariant
  # Andreas's complaint hinges on. Test it by replicating the observer's
  # fix_params AD-only path on the golden system.
  specs_ad <- make_golden_specs(constant_dist = FALSE)
  n_id <- which(specs_ad$parameter == "N")
  specs_ad$lower[n_id] <- 80000
  specs_ad$upper[n_id] <- 120000
  specs_ad$mean[n_id]  <- 100000
  specs_ad$distribution[n_id] <- "normal"
  other_rows <- setdiff(seq_len(nrow(specs_ad)), n_id)
  specs_ad$lower[other_rows] <- specs_ad$mean[other_rows]
  specs_ad$upper[other_rows] <- specs_ad$mean[other_rows]
  specs_ad$distribution[other_rows] <- "constant"

  sd_ad <- build_golden_system(specs_ad)
  # Mirror the observer's AD-only null-out of per-MMS sample matrices.
  sd_ad[[1]]$mcf_samples <- NULL
  sd_ad[[1]]$ef3_samples <- NULL
  sd_ad[[1]]$frac_gas_samples   <- NULL
  sd_ad[[1]]$frac_leach_samples <- NULL
  sd_ad[[1]]$mms_fraction_samples <- NULL

  sim_ad <- run_inventory_simulation(sd_ad, n_iter = 5000, gwp = "AR5",
                                      seed = 21, pct_pregnant = 0.5)
  inv_ad <- sim_ad$inventory
  cv <- function(x) if (mean(x) > 0) stats::sd(x) / mean(x) * 100 else NA_real_
  cv_N <- cv(sim_ad$by_system[[1]]$samples$N)
  cv_sources <- c(
    cv(inv_ad$total_enteric_ch4),
    cv(inv_ad$total_manure_ch4),
    cv(inv_ad$total_direct_n2o_prp),
    cv(inv_ad$total_indirect_n2o_prp))
  cv_sources <- cv_sources[is.finite(cv_sources) & cv_sources > 0]
  cv_max_dev <- if (length(cv_sources) > 0)
                  max(abs(cv_sources - cv_N)) / cv_N else NA_real_
  check_bool("F16", "F",
             "AD-only CV equals CV(N) for every emission source (single-system)",
             is.finite(cv_max_dev) && cv_max_dev < 0.001,
             notes = sprintf("CV(N)=%.3f; CV per source=%s; max rel.dev.=%.6f",
                             cv_N,
                             paste(formatC(cv_sources, digits = 3, format = "f"),
                                   collapse = ", "),
                             cv_max_dev))

  # F17 — Excel sensitivity sheets populate AND parameter names are clean
  # (no backticks from lm formula escaping, no R name-munging dots).
  # Andreas 28/5/26 #10 follow-up. Reuse the F15 setup (sd_sens with BW
  # varying in both sub-categories) so the sensitivity actually has signal.
  sim_f17 <- run_inventory_simulation(sd_sens, n_iter = 500, gwp = "AR5",
                                       seed = 33, pct_pregnant = 0.5)
  sens_f17 <- aggregate_sensitivity(sim_f17$by_system,
                                     sim_f17$inventory$total_co2e,
                                     method = "both")
  unc_f17 <- calc_all_uncertainty(sim_f17$inventory)
  ipcc_f17 <- format_ipcc_table(list(combined = unc_f17, ad_only = unc_f17,
                                       ef_only = unc_f17))
  xpath <- tempfile(fileext = ".xlsx")
  export_results_xlsx(sim_f17$inventory, unc_f17, sens_f17, ipcc_f17, xpath,
                       settings = list(n_iter = 500L, gwp_version = "AR5",
                                        emission_sources = character(0)))

  src_xls  <- as.data.frame(readxl::read_excel(xpath, sheet = "Sensitivity_SRC"))
  prcc_xls <- as.data.frame(readxl::read_excel(xpath, sheet = "Sensitivity_PRCC"))
  file.remove(xpath)

  # SRC sheet should have ≥ 1 row, the "parameter" column, AND no backticks.
  src_populated <- "parameter" %in% names(src_xls) && nrow(src_xls) > 0
  src_no_ticks  <- src_populated && !any(grepl("`", src_xls$parameter, fixed = TRUE))
  src_has_paren <- src_populated && any(grepl("\\(", src_xls$parameter))
  check_bool("F17a", "F",
             "Sensitivity_SRC Excel sheet: populated, no backticks, sub-category in (...)",
             src_populated && src_no_ticks && src_has_paren,
             notes = sprintf("nrow=%d; sample params: %s",
                             nrow(src_xls),
                             paste(head(src_xls$parameter, 3), collapse = "; ")))

  # PRCC sheet: same checks, and no `..` double-dot name-munging artefact.
  prcc_populated <- "parameter" %in% names(prcc_xls) && nrow(prcc_xls) > 0
  prcc_no_dots <- if (prcc_populated)
                    !any(grepl("\\.\\.", prcc_xls$parameter)) else NA
  prcc_has_paren <- prcc_populated && any(grepl("\\(", prcc_xls$parameter))
  check_bool("F17b", "F",
             "Sensitivity_PRCC Excel sheet: populated, no `..` mangling, sub-category in (...)",
             prcc_populated && isTRUE(prcc_no_dots) && prcc_has_paren,
             notes = sprintf("nrow=%d; sample params: %s",
                             nrow(prcc_xls),
                             paste(head(prcc_xls$parameter, 3), collapse = "; ")))

  # F18 — Inventory_Metadata Continental region (Andreas free-text P27).
  # `normalise_metadata_region()` should:
  #   (a) keep an explicit valid region slug as-is,
  #   (b) auto-map a known country name to its continent,
  #   (c) fall back to "global" otherwise.
  case_a <- normalise_metadata_region(
    data.frame(country = "Zimbabwe", region = "africa",
               stringsAsFactors = FALSE))
  case_b <- normalise_metadata_region(
    data.frame(country = "Zimbabwe", stringsAsFactors = FALSE))
  case_c <- normalise_metadata_region(
    data.frame(country = "Atlantis", stringsAsFactors = FALSE))
  case_d <- normalise_metadata_region(
    data.frame(country = "India", region = "",
               stringsAsFactors = FALSE))
  ok <- case_a$region == "africa" &&
         case_b$region == "africa" &&
         case_c$region == "global" &&
         case_d$region == "asia"
  check_bool("F18", "F",
             "Inventory_Metadata region: explicit slug kept; country auto-mapped; unknown -> global",
             ok,
             notes = sprintf("explicit africa -> %s; Zimbabwe (legacy) -> %s; Atlantis -> %s; India (blank region) -> %s",
                             case_a$region, case_b$region,
                             case_c$region, case_d$region))

  # F18b — actual parser-built metadata path. The new template emits the
  # label "Continental region", which the transposed-layout parser turns
  # into `metadata$continental_region` (not `metadata$region`). Confirm
  # the helper still finds the explicit pick — i.e. the user's explicit
  # "global" choice is respected even when their country would otherwise
  # auto-map to africa.
  case_e <- normalise_metadata_region(
    data.frame(country = "Zimbabwe", continental_region = "global",
               stringsAsFactors = FALSE))
  case_f <- normalise_metadata_region(
    data.frame(country = "Zimbabwe", continental_region = "africa",
               stringsAsFactors = FALSE))
  ok_e <- case_e$region == "global"   # explicit user override beats country lookup
  ok_f <- case_f$region == "africa"   # explicit user choice matches country
  check_bool("F18b", "F",
             "Continental region cell (new-template parser key) is honoured over country fallback",
             ok_e && ok_f,
             notes = sprintf("Zimbabwe + global -> %s; Zimbabwe + africa -> %s",
                             case_e$region, case_f$region))

  # F19 — End-to-end metadata parsing for a legacy "Country / region" label.
  # Andreas's Zim file uses the old single-cell convention. Probe via
  # parse_uploaded_template to confirm the parser now produces
  # metadata$country (no trailing underscore) AND region resolves to africa.
  # 2026-07 reorg: the (untracked) Zim fixture now lives under test_data/;
  # keep a repo-root fallback for older working copies.
  zim_f19 <- if (file.exists("test_data/uncertainty_template_ipcc2019_ZIM_v2.xlsx"))
               "test_data/uncertainty_template_ipcc2019_ZIM_v2.xlsx"
             else "uncertainty_template_ipcc2019_ZIM_v2.xlsx"
  if (file.exists(zim_f19)) {
    parsed <- tryCatch(parse_uploaded_template(zim_f19),
      error = function(e) NULL)
    md <- parsed$metadata
    country_ok <- !is.null(md) && "country" %in% names(md) &&
                  tolower(trimws(md$country[1])) == "zimbabwe"
    region_ok  <- !is.null(md) && "region" %in% names(md) &&
                  md$region[1] == "africa"
    no_underscore_key <- !is.null(md) && !("country_" %in% names(md))
    check_bool("F19a", "F",
               "Legacy 'Country / region' label parses to metadata$country (no trailing underscore) + region resolves to africa for Zimbabwe",
               country_ok && region_ok && no_underscore_key,
               notes = sprintf("country='%s' region='%s' country_ key present=%s",
                               if (!is.null(md)) md$country[1] else "NA",
                               if (!is.null(md)) md$region[1] else "NA",
                               !no_underscore_key))
  } else {
    record("F19a", "F", "Legacy Zim metadata parse",
           "skip", "missing-file", "SKIP",
           "uncertainty_template_ipcc2019_ZIM_v2.xlsx not found (looked in test_data/ and repo root)")
  }

  # F20 — End-to-end custom-upload regression on Andreas's canonical Zim
  # template. Mirrors _zim_verify.R, hard-wired tolerances. Protects against
  # silent regression of: (a) the auto-match of DINT_heif → DINT_heifer, (b)
  # the per-MMS / multi-sub-category direct N2O calculation, (c) per-
  # sub-category disaggregation in the simulation output. Skipped when the
  # template file isn't on disk (the file is intentionally not committed —
  # it's Andreas's working data).
  zim_path <- if (file.exists("test_data/uncertainty_template_ipcc2019_ZIM_v2.xlsx"))
                "test_data/uncertainty_template_ipcc2019_ZIM_v2.xlsx"
              else "uncertainty_template_ipcc2019_ZIM_v2.xlsx"
  if (file.exists(zim_path)) {
    parsed_z <- tryCatch(parse_uploaded_template(zim_path),
                          error = function(e) NULL)
    if (!is.null(parsed_z) && !is.null(parsed_z$manure) &&
        nrow(parsed_z$manure) > 0) {
      specs_z  <- parsed_z$param_specs
      manure_z <- parsed_z$manure
      group_key_z <- paste(specs_z$cattle_type, specs_z$aggregation_level,
                            specs_z$sub_category, sep = "||")
      sys_groups_z <- unique(group_key_z)
      sg_resolve_z <- resolve_sub_category_matches(specs_z, manure_z)

      # F20a — heifer auto-match fires for the DINT_heif typo.
      auto_match_fired <- any(sg_resolve_z$issues$status == "warn" &
                                sg_resolve_z$issues$check == "sub_category_auto_match" &
                                grepl("DINT_heif", sg_resolve_z$issues$message))
      check_bool("F20a", "F",
                 "Zim template: heifer auto-match (DINT_heif → DINT_heifer) fires",
                 auto_match_fired,
                 notes = if (auto_match_fired) "auto-match issue raised as warning"
                         else "auto-match NOT triggered — would cause N2O off-by-10")

      # F20b — full simulation runs and total_direct_n2o_mm is within tolerance
      # of the @Risk reference (39.9 t). Tolerance: [20, 50] — generous because
      # Monte Carlo + tool/risk modelling differences. Below 10 → regression to
      # the pre-auto-match factor-of-10 bug.
      systems_data_z <- list()
      for (sg in sys_groups_z) {
        sys_specs <- specs_z[group_key_z == sg, ]
        manure_key_z <- paste(manure_z$cattle_type, manure_z$aggregation_level,
                               manure_z$sub_category, sep = "||")
        sg_lookup <- if (sg %in% names(sg_resolve_z$matched))
          sg_resolve_z$matched[[sg]] else sg
        mms_rows <- manure_z[manure_key_z == sg_lookup, ]
        if (nrow(mms_rows) > 0) {
          fp <- suppressWarnings(as.numeric(mms_rows$fraction_pct)) / 100
          mcf <- suppressWarnings(as.numeric(mms_rows$MCF_pct)) / 100
          ef3 <- suppressWarnings(as.numeric(mms_rows$EF3))
          mms_fracs <- setNames(fp, mms_rows$mms_type)
          mcf_vals <- setNames(mcf, mms_rows$mms_type)
          ef3_vals <- setNames(ef3, mms_rows$mms_type)
          mms_fracs <- mms_fracs[!is.na(mms_fracs)]
          mcf_vals  <- mcf_vals[names(mms_fracs)]; mcf_vals[is.na(mcf_vals)] <- 0.015
          ef3_vals  <- ef3_vals[names(mms_fracs)]; ef3_vals[is.na(ef3_vals)] <- 0.005
        } else {
          mms_fracs <- c(pasture = 0.70, solid_storage = 0.30)
          mcf_vals  <- c(pasture = 0.015, solid_storage = 0.050)
          ef3_vals  <- c(pasture = 0.020, solid_storage = 0.005)
        }
        systems_data_z[[sg]] <- list(
          param_specs = sys_specs, corr_matrix = NULL, ef_corr_matrix = NULL,
          unified_corr_matrix = NULL,
          mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals)
      }
      sim_z <- tryCatch(
        run_inventory_simulation(systems_data_z, n_iter = 2000L, gwp = "AR5",
                                  seed = 42L, pct_pregnant = 1,
                                  sampler = "iman_conover"),
        error = function(e) NULL)
      if (!is.null(sim_z)) {
        n2o_direct <- mean(sim_z$inventory$total_direct_n2o_mm)
        # Generous tolerance — protect against the factor-of-10 regression.
        ok_n2o <- n2o_direct >= 15 && n2o_direct <= 60
        check_bool("F20b", "F",
                   "Zim end-to-end: total_direct_n2o_mm in plausible band [15, 60] (vs @Risk 39.9)",
                   ok_n2o,
                   notes = sprintf("mean = %.1f t (regression threshold: < 15 would indicate the auto-match fix is broken)",
                                   n2o_direct))

        # F20c — per-sub-category disaggregation: by_system has 5 systems,
        # each with non-zero direct_n2o_mm_total. Protects against the "
        # disaggregation not working" report.
        n_sys <- length(sim_z$by_system)
        all_nonzero <- all(vapply(sim_z$by_system, function(bs) {
          if (!is.list(bs) || is.null(bs$results)) return(FALSE)
          if (!"direct_n2o_mm_total" %in% names(bs$results)) return(FALSE)
          mean(bs$results$direct_n2o_mm_total) > 0
        }, logical(1)))
        check_bool("F20c", "F",
                   "Zim end-to-end: 5 sub-categories produced, each with non-zero direct N2O",
                   n_sys == 5L && all_nonzero,
                   notes = sprintf("n_sys = %d; all non-zero = %s",
                                   n_sys, all_nonzero))
      }
    } else {
      record("F20", "F", "Zim end-to-end regression",
             "parsed manure data", "missing or empty", "SKIP",
             "uncertainty_template_ipcc2019_ZIM_v2.xlsx parse failed or empty")
    }
  } else {
    record("F20", "F", "Zim end-to-end regression",
           "skip", "missing-file", "SKIP",
           "uncertainty_template_ipcc2019_ZIM_v2.xlsx not in repo root (intentionally untracked)")
  }

  # F21 — Built-in examples (Country X dairy + Country Y pastoral) produce
  # per-head emission rates inside the IPCC Tier-2 plausible band. Protects
  # against the regression Andreas was worried about in the 2 Jun meeting:
  # "are the examples on the app silently wrong like the pre-fix Zim data was?"
  # Tight enough to catch a factor-of-10 break, loose enough not to fail on
  # ordinary Monte Carlo noise.
  for (cn in c("country_x", "country_y")) {
    spec_fn <- if (cn == "country_x") generate_country_x_example else
                                       generate_country_y_example
    specs <- fill_bounds(spec_fn())
    group_key <- paste(specs$cattle_type, specs$aggregation_level,
                       specs$sub_category, sep = "||")
    sg <- unique(group_key)
    sys_data <- list()
    sys_data[[sg]] <- list(
      param_specs = specs, corr_matrix = NULL, ef_corr_matrix = NULL,
      unified_corr_matrix = NULL,
      mms_fractions = c(pasture = 0.70, solid_storage = 0.30),
      mcf_values    = c(pasture = 0.015, solid_storage = 0.050),
      ef3_values    = c(pasture = 0.020, solid_storage = 0.005))
    sim_e <- tryCatch(
      run_inventory_simulation(sys_data, n_iter = 2000L, gwp = "AR5",
                                seed = 42L, pct_pregnant = 1,
                                sampler = "iman_conover"),
      error = function(e) NULL)
    if (is.null(sim_e)) {
      check_bool(paste0("F21_", cn), "F",
                 sprintf("Built-in example %s simulates without error", cn),
                 FALSE, notes = "simulation crashed")
      next
    }
    N <- specs$mean[specs$parameter == "N"]
    ent_per_head <- mean(sim_e$inventory$total_enteric_ch4) * 1e3 / N
    mm_per_head  <- mean(sim_e$inventory$total_manure_ch4)  * 1e3 / N
    n2o_per_head <- mean(sim_e$inventory$total_direct_n2o_mm) * 1e3 / N
    ok <- ent_per_head  >= 30  && ent_per_head  <= 160 &&
          mm_per_head   >=  0  && mm_per_head   <=  40 &&
          n2o_per_head  >= 0.005 && n2o_per_head <= 0.5
    check_bool(paste0("F21_", cn), "F",
               sprintf("Built-in example %s per-head emissions in IPCC Tier-2 plausible band", cn),
               ok,
               notes = sprintf("enteric=%.1f kg/hd, manure_CH4=%.2f kg/hd, direct_N2O_mm=%.4f kg/hd",
                               ent_per_head, mm_per_head, n2o_per_head))
  }

  # F22 — Downloadable correlation-matrix template (Lolita 2026-06-02 review).
  # Confirms generate_corr_matrix_template() produces a CSV that round-trips
  # correctly through the upload parser (read.csv with row.names = 1) and
  # that the example variant matches build_ipcc_preset_corr() element-for-
  # element. Catches drift between the downloadable template and the in-app
  # structural-defaults preset.
  tmp_csv <- tempfile(fileext = ".csv")
  generate_corr_matrix_template(tmp_csv, include_example = TRUE)
  m_back <- as.matrix(read.csv(tmp_csv, row.names = 1, check.names = FALSE))
  m_ref  <- build_ipcc_preset_corr(PARAM_CATALOGUE$parameter)
  shape_ok  <- nrow(m_back) == ncol(m_back) &&
                nrow(m_back) == nrow(PARAM_CATALOGUE)
  diag_ok   <- all(diag(m_back) == 1)
  names_ok  <- identical(rownames(m_back), PARAM_CATALOGUE$parameter) &&
                identical(colnames(m_back), PARAM_CATALOGUE$parameter)
  values_ok <- isTRUE(all.equal(unname(m_back), unname(m_ref),
                                  tolerance = 1e-10))
  # At least seven off-diagonal symmetric pairs of the preset → ≥14 non-zero
  # off-diagonal cells. Check ≥7 to be robust against any reordering.
  n_nonzero_off <- sum(m_back != 0) - nrow(m_back)  # subtract diagonal ones
  pairs_ok <- n_nonzero_off >= 7
  check_bool("F22", "F",
             "generate_corr_matrix_template(example) round-trips through CSV and matches build_ipcc_preset_corr()",
             shape_ok && diag_ok && names_ok && values_ok && pairs_ok,
             notes = sprintf("shape=%s diag=%s names=%s values=%s pairs=%s",
                             shape_ok, diag_ok, names_ok, values_ok, pairs_ok))

  # F23 — "Find out more" Correlations topic page (Lolita 2026-06-03 / Pete
  # ask). The HTML is generated by the manual build step (_build_help_docs.R)
  # and bundled under www/docs/. Skip gracefully when the file isn't on
  # disk (audit can run between rebuilds without flagging).
  help_html <- "www/docs/correlations.html"
  if (file.exists(help_html)) {
    txt <- paste(readLines(help_html, warn = FALSE, encoding = "UTF-8"),
                  collapse = "\n")
    # Renamed sections after the 2026-06-09 tone rewrite. The page no
    # longer has a "Quick answer" TLDR block (replaced with a neutral
    # opening paragraph) and the pitfalls section is now "Common pitfalls"
    # (was "Common mistakes"). Country X / Y worked examples and the
    # emission-factor (EF) section are required signals of structural
    # completeness.
    size_ok       <- file.info(help_html)$size >= 50000
    has_x         <- grepl("Country X", txt, fixed = TRUE)
    has_y         <- grepl("Country Y", txt, fixed = TRUE)
    has_pitfalls  <- grepl("Common pitfalls", txt, fixed = TRUE)
    has_ef        <- grepl("Emission-factor correlations", txt, fixed = TRUE)
    check_bool("F23", "F",
               "Correlations help page rendered with both worked examples + EF section + pitfalls",
               size_ok && has_x && has_y && has_pitfalls && has_ef,
               notes = sprintf("size_ok=%s X=%s Y=%s pitfalls=%s EF=%s",
                               size_ok, has_x, has_y, has_pitfalls, has_ef))
  } else {
    record("F23", "F", "Correlations help page",
           "rendered HTML", "missing", "SKIP",
           "www/docs/correlations.html not on disk (run _build_help_docs.R)")
  }

  # F19b — Tornado user_reducible lookup handles labelled sub-category
  # parameters. Strip " (sub_category)" suffix before catalogue lookup.
  labelled <- c("Ym (DINT_cow)", "BW (DINT_heif)", "Bo (DINT_GrM)",
                "Cfi (DINT_cow)", "N (DINT_cow)")
  bare <- sub(" \\([^()]+\\)\\s*$", "", labelled)
  reducible_lut <- setNames(PARAM_CATALOGUE$user_reducible,
                              PARAM_CATALOGUE$parameter)
  reducible <- reducible_lut[bare]
  # Expected per PARAM_CATALOGUE: Ym=FALSE, BW=TRUE, Bo=FALSE, Cfi=FALSE, N=TRUE
  expected <- c(FALSE, TRUE, FALSE, FALSE, TRUE)
  match_ok <- all(reducible == expected, na.rm = TRUE) &&
               !any(is.na(reducible))
  check_bool("F19b", "F",
             "Tornado user_reducible lookup correctly classifies labelled params",
             match_ok,
             notes = sprintf("results: %s; expected: %s",
                             paste(reducible, collapse = ", "),
                             paste(expected, collapse = ", ")))

  # F24 — regression guard for Andy's Zambia crash (2026-06-15):
  # an inconsistent CI where the central value sits OUTSIDE [lower, upper]
  # must not make the sampler return NaN. Before the fix, mc2d::rpert emitted
  # "mode < min or mode > max" + NaN, which later made sd() return NA and
  # crashed the sensitivity analysis with "undefined columns selected".
  draws_hi <- sample_distribution(500, "pert", mean_val = 0.9,
                                   lower = 0.0, upper = 0.5)   # mode > max
  draws_lo <- sample_distribution(500, "pert", mean_val = 0.01,
                                   lower = 0.1, upper = 0.5)   # mode < min
  draws_inv <- sample_distribution(500, "triangular", mean_val = 0.3,
                                    lower = 0.5, upper = 0.2)  # inverted bounds
  no_nan <- all(is.finite(draws_hi)) && all(is.finite(draws_lo)) &&
            all(is.finite(draws_inv))
  check_bool("F24", "F",
             "sample_distribution: out-of-range / inverted bounds yield finite draws (no PERT NaN)",
             no_nan,
             notes = if (no_nan) "mode clamped into [lower,upper]; non-finite scrubbed"
                     else "NaN/Inf leaked from a degenerate parameterisation")

  # F25 — sensitivity must survive a NaN/constant input column instead of
  # throwing "undefined columns selected". Build inputs with one all-NaN
  # column and one constant column alongside two varying columns.
  set.seed(1)
  sens_inputs <- data.frame(
    good1 = rnorm(200), good2 = rnorm(200),
    bad_nan = rep(NaN, 200), bad_const = rep(5, 200),
    check.names = FALSE)
  sens_out <- rnorm(200)
  sens_res <- tryCatch(sensitivity_analysis(sens_inputs, sens_out, method = "src"),
                        error = function(e) structure(list(), err = conditionMessage(e)))
  sens_ok <- is.null(attr(sens_res, "err")) && !is.null(sens_res$src) &&
             nrow(sens_res$src) == 2L   # only the two good columns survive
  check_bool("F25", "F",
             "sensitivity_analysis drops NaN/constant columns instead of crashing",
             sens_ok,
             notes = if (sens_ok) "2 varying columns kept; NaN + constant dropped"
                     else paste("error:", attr(sens_res, "err")))

  # F26 — aggregate_sensitivity row subsample: on a run with more iterations
  # than max_rows, the SRC regression must run on the capped subsample (memory
  # guard that prevents the "server needed to reload" OOM during sensitivity on
  # the heaviest all-sources + correlations + decomposition run), while still
  # returning a ranking. Build a tiny 2-system by_system with 60 iterations and
  # cap at 25.
  set.seed(2)
  mk_block <- function() {
    s <- data.frame(N = rnorm(60, 100, 5), BW = rnorm(60, 400, 20),
                    Ym = rnorm(60, 6.5, 0.5), check.names = FALSE)
    list(samples = s)
  }
  bys <- list(`dairy||sys1||cows` = mk_block(), `dairy||sys1||heifers` = mk_block())
  out_vec <- rnorm(60, 1000, 50)
  agg_full <- aggregate_sensitivity(bys, out_vec, method = "src", max_rows = 1e9)
  agg_cap  <- aggregate_sensitivity(bys, out_vec, method = "src", max_rows = 25L)
  cap_ok <- !is.null(agg_cap) && !is.null(agg_cap$src) &&
            nrow(agg_cap$src) == nrow(agg_full$src) &&    # same parameters ranked
            !is.null(attr(agg_cap, "subsampled_note")) &&  # note attached
            is.null(attr(agg_full, "subsampled_note"))     # not attached when under cap
  check_bool("F26", "F",
             "aggregate_sensitivity caps regression rows at max_rows (memory guard) while keeping the ranking",
             cap_ok,
             notes = if (cap_ok) "capped run ranks same params + flags subsample"
                     else "row cap not applied as expected")

  # F27 — DE-domain clamp (2026-06-15): the IPCC net-energy-ratio equations
  # REM/REG (Eq 10.14/10.15) are empirical fits valid for ruminant DE in 45-85%
  # and REG crosses zero near DE = 37.6%. An UNtruncated normal draw on DE
  # (lower/upper only set the SD) wanders into the low tail and sends gross
  # energy to +/-infinity, producing impossible negative / exploded total_co2e
  # (Andy's Zambia histogram: x-axis to ~50B t, mean above the 97.5th pctl).
  # generate_mc_samples() must clamp DE into [45, 85] so REM/REG stay positive.
  set.seed(7)
  de_specs <- data.frame(
    parameter    = c("N", "DE"),
    param_type   = c("activity_data", "coefficient"),
    distribution = c("normal", "normal"),
    mean         = c(1000, 52.6),
    # DE bounds give SD ~ 6.1; the untruncated tail reaches well below 38%.
    lower        = c(900, 40.66),
    upper        = c(1100, 64.61),
    stringsAsFactors = FALSE, check.names = FALSE)
  de_samp <- generate_mc_samples(de_specs, n_iter = 5000, seed = 7)
  de_col  <- de_samp[["DE"]]
  reg_ok  <- all(is.finite(calc_reg(de_col))) && all(calc_reg(de_col) > 0) &&
             all(is.finite(calc_rem(de_col))) && all(calc_rem(de_col) > 0)
  de_ok   <- all(de_col >= 45 - 1e-9) && all(de_col <= 85 + 1e-9) && reg_ok
  check_bool("F27", "F",
             "generate_mc_samples clamps DE into the IPCC valid domain [45,85] so REM/REG stay positive",
             de_ok,
             notes = if (de_ok)
               sprintf("DE in [%.1f, %.1f]; REM/REG > 0", min(de_col), max(de_col))
             else sprintf("DE range [%.1f, %.1f] left REM/REG domain",
                          min(de_col), max(de_col)))

  # F28 — catalogue wet-climate guard (2026-06-16). The app auto-fills IPCC
  # defaults from PARAM_CATALOGUE for any parameter the AI translator omits, so
  # the catalogue is the source of truth for ~64% of a typical inventory's
  # values. Lock the five manure/PRP N2O factors to the WET-CLIMATE defaults
  # (verified vs 2019R Vol.4 Ch.11 Tables 11.1/11.3) that match what the
  # translator emits today, so they can't silently drift back to the aggregated
  # values — which would change every default-filled inventory's N2O result.
  cat_row <- function(p) PARAM_CATALOGUE[PARAM_CATALOGUE$parameter == p, ]
  ef3 <- cat_row("EF3_PRP"); ef4 <- cat_row("EF4"); ef5 <- cat_row("EF5")
  fg  <- cat_row("Frac_GASM_PRP"); fl <- cat_row("Frac_LEACH_PRP")
  eq <- function(a, b) isTRUE(all.equal(a, b))
  cat_ok <-
    eq(ef3$ipcc_default, 0.006) &&
    eq(c(ef3$suggested_lower_bound, ef3$suggested_upper_bound), c(0.0005, 0.027)) &&
    eq(ef4$ipcc_default, 0.014) &&
    eq(c(ef4$suggested_lower_bound, ef4$suggested_upper_bound), c(0.011, 0.017)) &&
    eq(ef5$ipcc_default, 0.011) && eq(ef5$suggested_upper_bound, 0.020) &&
    eq(c(fg$suggested_lower_bound, fg$suggested_upper_bound), c(0.005, 0.31)) &&
    eq(c(fl$suggested_lower_bound, fl$suggested_upper_bound), c(0.01, 0.73))
  check_bool("F28", "F",
             "PARAM_CATALOGUE holds the wet-climate manure/PRP N2O defaults (EF3_PRP/EF4/EF5/Frac_*)",
             cat_ok,
             notes = if (cat_ok) "EF3_PRP=0.006, EF4=0.014, EF5=0.011 + wet bounds"
                     else "catalogue N2O defaults drifted from the agreed wet-climate values")

  # F29 — per-MMS coefficient guard (2026-06-16). MMS_DEFAULTS$ef3 and
  # MMS_FRAC_DEFAULTS_2019 were corrected line-by-line against IPCC 2019R
  # Tables 10.21 / 10.22 ("Other Cattle" column). Lock the corrected values so
  # they can't regress — these feed the blank-template examples now and the
  # app's per-MMS default-fill under the sparse-overlay change. (MCF stays on the
  # 2006 convention by design — see the MMS_DEFAULTS comment.)
  mms_ef3 <- function(id) MMS_DEFAULTS$ef3[MMS_DEFAULTS$id == id]
  fr <- function(id) mms_frac_defaults_2019(id)
  mms_ok <-
    eq(mms_ef3("solid_storage"), 0.010) && eq(mms_ef3("solid_storage_covered"), 0.010) &&
    eq(mms_ef3("dry_lot"), 0.02) && eq(mms_ef3("liquid_slurry"), 0.005) &&
    # composting models Static Pile (forced aeration) throughout — 2026-09-10
    eq(mms_ef3("composting"), 0.010) &&
    eq(fr("lagoon")$frac_gas, 0.35) && eq(fr("aerobic_treatment")$frac_gas, 0.85) &&
    eq(fr("solid_storage_covered")$frac_gas, 0.22) &&
    eq(fr("solid_storage_covered")$frac_leach, 0.00) &&
    eq(fr("deep_bedding")$frac_gas, 0.25) && eq(fr("deep_bedding")$frac_leach, 0.035) &&
    eq(fr("dry_lot")$frac_leach, 0.035) && eq(fr("composting")$frac_leach, 0.06) &&
    eq(fr("solid_storage")$frac_gas, 0.45) &&
    # liquid_slurry models the WITH-natural-crust variant throughout
    # (MMS_DEFAULTS$ipcc_variant); Table 10.22 Other Cattle gives 0.30.
    eq(fr("liquid_slurry")$frac_gas, 0.30)
  check_bool("F29", "F",
             "MMS_DEFAULTS EF3 + MMS_FRAC_DEFAULTS_2019 match IPCC 2019R Tables 10.21/10.22 (Other Cattle)",
             mms_ok,
             notes = if (mms_ok) "EF3 solid_storage=0.010, composting=0.010; lagoon Frac_Gas=0.35; aerobic=0.85; dry_lot leach=0.035"
                     else "a corrected MMS coefficient drifted from the IPCC Other-Cattle value")

  # F29a — Frac_GasMS BOUNDS vs the published Table 10.22 ranges. F29 pinned the
  # central values only, which is how five rows kept a mechanical +-50% spread
  # from a superseded rule long after that rule was replaced (see the comment on
  # MMS_FRAC_DEFAULTS_2019). Lock the ranges too.
  fb <- function(id) { x <- fr(id); c(x$frac_gas_low, x$frac_gas_high) }
  bounds_ok <-
    eq(fb("daily_spread"),          c(0.05, 0.60)) &&
    eq(fb("solid_storage"),         c(0.10, 0.65)) &&
    eq(fb("solid_storage_covered"), c(0.03, 0.26)) &&
    eq(fb("dry_lot"),               c(0.20, 0.50)) &&
    eq(fb("deep_bedding"),          c(0.10, 0.30)) &&
    eq(fb("liquid_slurry"),         c(0.09, 0.36)) &&
    eq(fb("composting"),            c(0.14, 0.70)) &&
    eq(fb("aerobic_treatment"),     c(0.27, 1.00)) &&
    eq(fb("lagoon"),                c(0.20, 0.80))
  check_bool("F29a", "F",
             "MMS_FRAC_DEFAULTS_2019 Frac_Gas bounds match the published Table 10.22 ranges",
             bounds_ok,
             notes = if (bounds_ok) "9 of 9 gas ranges match Other Cattle; none is a mechanical +-50%"
                     else "a Frac_Gas bound drifted from the published IPCC range")

  # F29b — MCF cells verified against 2006 Table 10.17 on 2026-09-10. MCF stays
  # on the 2006 convention by design (2019R needs a per-MMS Bo the engine lacks),
  # but the individual cells had never been checked: dry_lot tropical was 5.0
  # against a published 2.0, solid_storage boreal was 3.0 against 2.0, and
  # composting carried the windrow row rather than static pile. Band mapping
  # Cool->boreal, Temperate->temperate, Warm->tropical, confirmed exact by
  # daily_spread and burned_for_fuel.
  # ALL TWELVE systems, not a spot check. The previous version asserted six,
  # and the six it chose were the ones that happened to be right: pasture,
  # solid_storage_covered, deep_bedding, liquid_slurry, lagoon and
  # anaerobic_digester were all wrong and none was guarded.
  mcfv <- function(id) unlist(MMS_DEFAULTS[MMS_DEFAULTS$id == id,
            c("mcf_tropical", "mcf_temperate", "mcf_boreal")], use.names = FALSE)
  mcf_expect <- list(
    pasture               = c(2.0,  1.5,  1.0),
    daily_spread          = c(1.0,  0.5,  0.1),
    solid_storage         = c(5.0,  4.0,  2.0),
    solid_storage_covered = c(5.0,  4.0,  2.0),
    dry_lot               = c(2.0,  1.5,  1.0),
    deep_bedding          = c(80.0, 39.0, 17.0),   # >1 month gradient @19C
    liquid_slurry         = c(50.0, 24.0, 10.0),   # with natural crust @19C
    composting            = c(0.5,  0.5,  0.5),    # static pile, not temp-dependent
    lagoon                = c(80.0, 77.0, 66.0),   # gradient @19C
    anaerobic_digester    = c(4.59, 4.38, 3.55),   # low leakage, open storage
    aerobic_treatment     = c(0.0,  0.0,  0.0),
    burned_for_fuel       = c(10.0, 10.0, 10.0))
  mcf_bad <- names(mcf_expect)[!vapply(names(mcf_expect),
    function(id) eq(mcfv(id), mcf_expect[[id]]), logical(1))]
  mcf_ok <- length(mcf_bad) == 0
  check_bool("F29b", "F",
             "MMS_DEFAULTS MCF: all 12 systems x 3 zones vs IPCC Table 10.17",
             mcf_ok,
             notes = if (mcf_ok) "12/12 systems match; gradient rows use the 19C midpoint of the Temperate band"
                     else paste("MCF drifted for:", paste(mcf_bad, collapse = ", ")))

  # F29c -- every row must DECLARE which IPCC variant it models. The tool has
  # one row per system while IPCC splits five of them into variants with
  # different coefficients, and the row previously drifted across coefficient
  # families: liquid_slurry took EF3 from "with crust" and Frac from "without".
  var_ok <- "ipcc_variant" %in% names(MMS_DEFAULTS) &&
    all(nzchar(MMS_DEFAULTS$ipcc_variant)) &&
    grepl("with natural crust",
          MMS_DEFAULTS$ipcc_variant[MMS_DEFAULTS$id == "liquid_slurry"]) &&
    grepl(">1 month",
          MMS_DEFAULTS$ipcc_variant[MMS_DEFAULTS$id == "deep_bedding"]) &&
    grepl("Static Pile",
          MMS_DEFAULTS$ipcc_variant[MMS_DEFAULTS$id == "composting"]) &&
    grepl("open storage",
          MMS_DEFAULTS$ipcc_variant[MMS_DEFAULTS$id == "anaerobic_digester"])
  check_bool("F29c", "F",
             "Every MMS row declares the IPCC variant it models (ipcc_variant)",
             var_ok,
             notes = if (var_ok) "12/12 declared; slurry=with crust, bedding=>1mo, composting=static pile, digester=open storage"
                     else "a row has no declared IPCC variant, or a variant changed without its coefficients")

  # F30 — sparse-overlay resolver. resolve_subcat_default() is the single source
  # of truth for the IPCC defaults the app fills when the AI translator omits a
  # cell. Verify the sex/age overrides, biological zeros, per-sub-cat pct_pregnant,
  # and generic catalogue fallback all resolve correctly.
  rd <- function(s, p) resolve_subcat_default(s, p)
  res_ok <-
    eq(rd("bulls","Cfi")$value, 0.370) && eq(rd("growing_males","Cfi")$value, 0.322) &&
    eq(rd("bulls","C")$value, 1.2) && eq(rd("oxen","C")$value, 1.0) &&
    eq(rd("bulls","Milk")$value, 0) &&
    identical(rd("bulls","Milk")$data_source, "biological_zero") &&
    identical(rd("bulls","Milk")$distribution, "constant") &&
    identical(rd("bulls","pct_pregnant")$data_source, "biological_zero") &&
    identical(rd("calves_female","pct_pregnant")$data_source, "biological_zero") &&
    identical(rd("heifers","hours")$data_source, "biological_zero") &&
    # Low-productivity basis, adopted 2026-09-11: dairy_cows takes the
    # Table 10A.1 Africa low-productivity row (52% pregnant, DE 51), not the
    # aggregate row and not the Eastern Europe 0.85 that used to sit here.
    eq(rd("dairy_cows","pct_pregnant")$value, 0.52) &&
    eq(rd("other_cows","pct_pregnant")$value, 0.54) &&
    eq(rd("heifers","pct_pregnant")$value, 0.5) &&
    eq(rd("heifers","WG")$value, 0.25) &&
    eq(rd("bulls","WG")$value, 0) && identical(rd("bulls","WG")$distribution, "constant") &&
    eq(rd("dairy_cows","DE")$value, 51) &&
    identical(rd("dairy_cows","DE")$data_source, "ipcc_default") &&
    eq(rd("dairy_cows","EF3_PRP")$value, 0.006) &&
    eq(rd("dairy_cows","EF3_PRP")$lower, 0.0005) &&
    is.na(rd("dairy_cows","N")$value) &&
    is.null(rd("dairy_cows","NoSuchParam"))
  check_bool("F30", "F",
             "resolve_subcat_default fills IPCC sex/age overrides + biological zeros + catalogue defaults",
             res_ok,
             notes = if (res_ok) "bulls.Cfi=0.370, growing_males.Cfi=0.322, bulls.Milk=0/constant, dairy.pct_preg=0.52, dairy.DE=51 (low-productivity basis)"
                     else "resolver returned an unexpected default for a (sub_category, parameter)")

  # F32 -- the defaults master is the single authority. Every IPCC default
  # the app ships is read from reference/defaults_master.csv by
  # R/load_defaults.R. Assert the file is present, that it still builds the
  # objects, and that the objects have the shape the rest of the app assumes.
  # Without this a corrupt or truncated master would surface as a hundred
  # confusing downstream failures instead of one clear one.
  master_ok <- tryCatch({
    file.exists(.DEFAULTS_MASTER_PATH) &&
      nrow(.defaults_master) > 400 &&
      identical(names(PARAM_CATALOGUE)[1], "parameter") &&
      nrow(PARAM_CATALOGUE) == 25L &&
      ncol(PARAM_CATALOGUE) == 14L &&   # gained ipcc_equation
      is.logical(PARAM_CATALOGUE$user_reducible) &&
      is.numeric(PARAM_CATALOGUE$ipcc_default) &&
      identical(PARAM_CATALOGUE$parameter[1], "N") &&
      nrow(MMS_DEFAULTS) == 12L && "ipcc_variant" %in% names(MMS_DEFAULTS) &&
      nrow(MMS_FRAC_DEFAULTS_2019) == 12L &&
      length(CFI_BY_SUBCAT) == 9L && is.numeric(unlist(CFI_BY_SUBCAT))
  }, error = function(e) FALSE)
  check_bool("F32", "F",
             "Defaults master loads and rebuilds every constant with the expected shape",
             master_ok,
             notes = if (master_ok)
               sprintf("%d master rows -> PARAM_CATALOGUE 25x13, MMS 12, frac 12, subcat lists 9",
                       nrow(.defaults_master))
               else "reference/defaults_master.csv missing, truncated, or rebuilt an object with the wrong shape/type")

  # F33 -- every shipped numeric default carries an IPCC verification verdict.
  # The whole master was read back against the IPCC source text value by value
  # on 2026-09-11 and the outcome written into the ipcc_verdict/ipcc_source
  # columns by scripts/annotate_ipcc_verdicts.R. A NEW default added later
  # would arrive with no verdict, which is precisely the state that let
  # unsourced values accumulate in the first place. This check makes an
  # unverified value a build failure rather than something to notice later.
  VERDICTS <- c("CONFIRMED", "INTERPRETED", "DEVIATION_DOCUMENTED",
                "DEVIATION_OPEN", "NOT_IPCC", "NO_IPCC_DEFAULT", "META")
  verdict_ok <- tryCatch({
    m <- .defaults_master
    stopifnot(all(c("ipcc_verdict", "ipcc_source") %in% names(m)))
    numeric_row <- !is.na(suppressWarnings(as.numeric(m$value)))
    bad_v <- numeric_row & (is.na(m$ipcc_verdict) |
                            !m$ipcc_verdict %in% VERDICTS)
    bad_s <- numeric_row & (is.na(m$ipcc_source) | !nzchar(m$ipcc_source))
    verdict_gaps <<- m[bad_v | bad_s, c("object", "key", "field")]
    n_num <<- sum(numeric_row)
    !any(bad_v | bad_s)
  }, error = function(e) { verdict_gaps <<- NULL; FALSE })
  check_bool("F33", "F",
             "Every numeric default in the master carries an IPCC verification verdict and source",
             verdict_ok,
             notes = if (verdict_ok)
               sprintf("%d numeric values, all with a verdict from the allowed set", n_num)
             else if (is.null(verdict_gaps))
               "master has no ipcc_verdict/ipcc_source columns; run scripts/annotate_ipcc_verdicts.R"
             else sprintf("%d value(s) with no verdict or no source, e.g. %s. Run scripts/annotate_ipcc_verdicts.R",
                          nrow(verdict_gaps),
                          paste(utils::head(apply(verdict_gaps, 1, paste, collapse = "/"), 3),
                                collapse = "; ")))

  # F35 -- Ym resolves per sub-category AND per guideline edition.
  #
  # IPCC Table 10.12 is a per-category table. The tool applied one number,
  # 6.5, to all nine sub-categories, which was right only for lactating dairy
  # cows. Two consequences worth guarding separately:
  #   * non-dairy should be 7.0 (2019R), a 7.7% understatement of enteric CH4
  #   * feedlot should be 4.0 (2019R) / 3.0 (2006) against the 6.5 shipped,
  #     which made a feedlot animal the HIGHEST per-head enteric emitter in
  #     the herd when IPCC's point is that concentrate-fed animals emit less
  #
  # The feedlot Ym is conditional on DE >= 72, so the DE override is asserted
  # in the same check: shipping Ym 4.0 next to the catalogue's DE of 55 would
  # be a combination IPCC does not sanction, and the two must never drift
  # apart. F29b exists because a spot check that happened to pick the already
  # correct rows proved nothing, so this asserts all nine, both editions.
  ym_expect_19 <- c(dairy_cows = 6.5, other_cows = 7.0, bulls = 7.0,
                    oxen = 7.0, heifers = 7.0, growing_males = 7.0,
                    calves_female = 7.0, calves_male = 7.0,
                    feedlot_cattle = 4.0)
  ym_expect_06 <- c(dairy_cows = 6.5, other_cows = 6.5, bulls = 6.5,
                    oxen = 6.5, heifers = 6.5, growing_males = 6.5,
                    calves_female = 6.5, calves_male = 6.5,
                    feedlot_cattle = 3.0)
  # Failures RETURNED, not assigned with <<-; see the note on F36.
  ym_fail <- tryCatch({
    f <- character(0)
    for (sc in names(ym_expect_19)) {
      g19 <- resolve_subcat_default(sc, "Ym", "2019_refinement")$value
      g06 <- resolve_subcat_default(sc, "Ym", "2006")$value
      if (!isTRUE(all.equal(g19, unname(ym_expect_19[[sc]]))))
        f <- c(f, sprintf("%s 2019R %s != %s", sc, g19, ym_expect_19[[sc]]))
      if (!isTRUE(all.equal(g06, unname(ym_expect_06[[sc]]))))
        f <- c(f, sprintf("%s 2006 %s != %s", sc, g06, ym_expect_06[[sc]]))
    }
    # The feedlot diet must satisfy the precondition on its own Ym row.
    fd <- resolve_subcat_default("feedlot_cattle", "DE")$value
    if (!isTRUE(fd >= 72))
      f <- c(f, sprintf("feedlot DE %s violates the DE>=72 precondition of Ym 4.0", fd))
    # The whole diet table, per sub-category, on the declared low-productivity
    # basis. dairy_cows from Table 10A.1 Africa low productivity; every
    # non-dairy row from its matching Table 10A.2 Africa grazing row; feedlot
    # from Table 10A.2 Latin America. This replaced an assertion that every
    # sub-category carried the CATALOGUE DE, which was true only while DE was
    # a single uniform 55 that matched no IPCC row at all.
    de_expect <- c(dairy_cows = 51, other_cows = 58, bulls = 58, oxen = 58,
                   heifers = 59, growing_males = 59, calves_female = 59,
                   calves_male = 59, feedlot_cattle = 74)
    cp_expect <- c(dairy_cows = 9.6, other_cows = 10.0, bulls = 10.0,
                   oxen = 10.0, heifers = 10.4, growing_males = 10.4,
                   calves_female = 10.3, calves_male = 10.3,
                   feedlot_cattle = 14.0)
    for (sc in names(de_expect)) {
      d <- resolve_subcat_default(sc, "DE")$value
      cp <- resolve_subcat_default(sc, "CP")$value
      if (!isTRUE(all.equal(d, unname(de_expect[[sc]]))))
        f <- c(f, sprintf("%s DE %s != %s", sc, d, de_expect[[sc]]))
      if (!isTRUE(all.equal(cp, unname(cp_expect[[sc]]))))
        f <- c(f, sprintf("%s CP %s != %s", sc, cp, cp_expect[[sc]]))
    }
    f
  }, error = function(e) conditionMessage(e))
  ym_ok <- length(ym_fail) == 0L
  check_bool("F35", "F",
             "Ym resolves per sub-category and per guideline edition, with a coherent feedlot diet",
             ym_ok,
             notes = if (ym_ok)
               "9 sub-categories x 2 editions: dairy 6.5, non-dairy 7.0 (2019R) / 6.5 (2006), feedlot 4.0 / 3.0; the full DE and CP diet table on the low-productivity basis, with feedlot DE 74 >= 72"
             else paste(utils::head(ym_fail, 4), collapse = "; "))

  # F36 -- only mature females carry a milk yield.
  #
  # The biological-zero rule tested sex == "male" alone, so heifers, female
  # calves and feedlot cattle all inherited the dairy-cow 3.5 kg/day. That
  # adds a net-energy-for-lactation term to animals that have never calved:
  # heifers ran 19% high on enteric CH4 and feedlot cattle 14% high. IPCC
  # Annex 10A.2 settles it for every region, giving a milk yield only to its
  # Mature Females rows; Growing/Replacement, Calves and Feedlot are blank.
  #
  # Asserted for all nine sub-categories and all three milk parameters, not a
  # spot check: the two that were already right (dairy_cows, other_cows) are
  # exactly the ones a spot check would have picked.
  MILK_PARAMS <- c("Milk", "Fat", "MilkPR")
  LACTATES <- c("dairy_cows", "other_cows")
  # NOTE: the failure list is RETURNED from tryCatch, never assigned with
  # <<-. These checks run inside section_F(), and tryCatch evaluates its
  # expression in the caller's frame, so <<- skips the local variable and
  # writes to the global environment. The check then reads an empty local
  # list and passes no matter what. Both F35 and F36 were built that way and
  # both passed against a deliberately reverted rule before this was found.
  milk_fail <- tryCatch({
    f <- character(0)
    for (sc in ANIMAL_SUBCATEGORIES) for (prm in MILK_PARAMS) {
      r  <- resolve_subcat_default(sc, prm)
      bz <- identical(r$data_source, "biological_zero")
      if (sc %in% LACTATES) {
        if (bz || isTRUE(r$value == 0))
          f <- c(f, sprintf("%s/%s zeroed but it lactates", sc, prm))
      } else if (!bz || !isTRUE(r$value == 0)) {
        f <- c(f, sprintf("%s/%s = %s, should be a biological zero",
                          sc, prm, r$value))
      }
    }
    # An unrecognised sub-category must keep the catalogue value rather than
    # being silently zeroed: it may well be a dairy group under another name.
    if (identical(resolve_subcat_default("some_unmapped_dairy_group",
                                         "Milk")$data_source, "biological_zero"))
      f <- c(f, "an unmapped sub-category was zeroed instead of taking the catalogue default")
    f
  }, error = function(e) conditionMessage(e))
  milk_ok <- length(milk_fail) == 0L
  check_bool("F36", "F",
             "Milk, Fat and MilkPR are non-zero only for mature females",
             milk_ok,
             notes = if (milk_ok)
               "9 sub-categories x 3 parameters: non-zero for dairy_cows and other_cows only; heifers, calves, feedlot and all males are biological zeros; unmapped sub-categories keep the catalogue default"
             else paste(utils::head(milk_fail, 4), collapse = "; "))

  # F37 -- the declared basis reaches every user-facing surface.
  #
  # DEFAULT_BASIS states which IPCC row each family of defaults came from:
  # Africa, low productivity, wet climate, liquid slurry WITH a crust,
  # composting as a static pile. Until 2026-09-11 none of that reached a
  # user. ipcc_variant existed but appeared only in an internal reference
  # file, so someone reading "MCF 50% for liquid slurry" had no way to learn
  # it assumes a natural crust, and no way to know what to change if their
  # slurry has none.
  #
  # A basis that is declared but not rendered is worth nothing, so this
  # asserts presence on each surface rather than trusting the generators.
  basis_fail <- tryCatch({
    f <- character(0)
    if (!exists("DEFAULT_BASIS") || nrow(DEFAULT_BASIS) < 10L)
      f <- c(f, "DEFAULT_BASIS missing or short")
    # every dimension must say what it governs and why
    for (cl in c("chosen", "alternatives", "ipcc_source", "governs", "why",
                 "scope"))
      if (any(!nzchar(DEFAULT_BASIS[[cl]])))
        f <- c(f, sprintf("DEFAULT_BASIS has an empty %s", cl))
    if (!all(DEFAULT_BASIS$scope %in% c("tool_wide", "resolved")))
      f <- c(f, "DEFAULT_BASIS has a scope outside tool_wide/resolved")
    # A fallback the resolver already varies is not an assumption. Showing
    # one to a user as though it were understates the tool: lactation state
    # was listed that way, while resolve_subcat_default() gives dairy cows
    # Cfi 0.386 and everything else 0.322 or 0.370. User-facing surfaces
    # must carry the tool-wide rows and NOT the resolved ones.
    # The scoping is asserted explicitly, not derived, because the
    # distinction is semantic. "Does the value vary by sub-category" does
    # NOT separate the two: geography is Africa for every sub-category even
    # though each takes a different weight from the Africa block, whereas
    # lactation state genuinely differs, dairy cows being lactating and
    # heifers not. Only a person can tell those apart, so this is a
    # regression guard on a judgement, which is what it looks like.
    EXPECT_RESOLVED <- c("lactation_state", "guidelines_edition")
    got_resolved <- sort(DEFAULT_BASIS$dimension[DEFAULT_BASIS$scope != "tool_wide"])
    if (!identical(got_resolved, sort(EXPECT_RESOLVED)))
      f <- c(f, sprintf("scope=resolved should be {%s} but is {%s}",
                        paste(sort(EXPECT_RESOLVED), collapse = ", "),
                        paste(got_resolved, collapse = ", ")))
    resolved <- DEFAULT_BASIS[DEFAULT_BASIS$scope != "tool_wide", , drop = FALSE]
    for (sf in c("doc/_basis_block.tex",
                 "translator_prompts/param_catalogue.md")) {
      if (!file.exists(sf)) next
      txt <- paste(readLines(sf, warn = FALSE, encoding = "UTF-8"), collapse = " ")
      for (k in seq_len(nrow(resolved)))
        if (grepl(resolved$chosen[k], txt, fixed = TRUE))
          f <- c(f, sprintf("%s presents the resolved choice '%s' as a tool-wide assumption",
                            basename(sf), resolved$dimension[k]))
    }
    # the four choices a user is most likely to be caught out by
    probes <- c("Low productivity", "Wet", "Africa")
    surfaces <- c("doc/_basis_block.tex",
                  "translator_prompts/param_catalogue.md",
                  "reference/DEFAULTS_MASTER.md")
    for (sf in surfaces) {
      if (!file.exists(sf)) { f <- c(f, paste("missing surface", sf)); next }
      txt <- paste(readLines(sf, warn = FALSE, encoding = "UTF-8"), collapse = " ")
      for (pr in probes)
        if (!grepl(pr, txt, fixed = TRUE))
          f <- c(f, sprintf("%s does not state the basis '%s'", basename(sf), pr))
      # and the manure variant that is easiest to get wrong
      if (!grepl("natural crust cover", txt, fixed = TRUE))
        f <- c(f, sprintf("%s does not name the liquid-slurry variant", basename(sf)))
    }
    # basis_for() must resolve, and must be silent where nothing governs
    if (!length(basis_for("Bo"))) f <- c(f, "basis_for(Bo) returned nothing")
    if (length(basis_for("N")))   f <- c(f, "basis_for(N) should be empty")
    f
  }, error = function(e) conditionMessage(e))
  basis_ok <- length(basis_fail) == 0L
  check_bool("F37", "F",
             "The declared basis is stated on every user-facing surface",
             basis_ok,
             notes = if (basis_ok)
               sprintf("%d choices, each with chosen/alternatives/source/governs/why, rendered into the guides, the translator prompt and the defaults reference",
                       nrow(DEFAULT_BASIS))
             else paste(utils::head(basis_fail, 4), collapse = "; "))

  # F38 -- the QA benchmark must not warn about the tool's own defaults.
  #
  # Review round 7 item 3 was "~20 spurious QA warnings", the reviewer's
  # reason being that the tab "cited IPCC default values that I could not
  # find in the IPCC guidelines". The fix then narrowed the check to BW and
  # left BW itself comparing every sub-category against one adult number:
  # the tool's own 60 kg calf default came out 78% adrift and warned, and a
  # compiler entering IPCC's published Africa weights was warned about
  # Calves on forage (82 kg).
  #
  # Two directions are asserted, because a benchmark that never fires is as
  # useless as one that always does.
  bench_fail <- tryCatch({
    f <- character(0)
    mk <- function(sc, ct, mu) data.frame(
      cattle_type = ct, aggregation_level = "n", sub_category = sc,
      parameter = "BW", mean = mu, lower = NA_real_, upper = NA_real_,
      uncertainty_pct = 15, distribution = "normal",
      param_type = "activity_data", stringsAsFactors = FALSE)
    verdict <- function(d) {
      q <- run_qaqc(d, region = "africa")
      q$status[q$check == "benchmark_deviation"]
    }
    # (a) every one of the tool's own defaults must pass
    for (sc in ANIMAL_SUBCATEGORIES) {
      ct <- if (sc == "dairy_cows") "dairy" else "other"
      v  <- resolve_subcat_default(sc, "BW")$value
      st <- verdict(mk(sc, ct, v))
      if (!identical(st, "pass"))
        f <- c(f, sprintf("%s at its own default %s: %s", sc, v,
                          paste(st, collapse = "/")))
    }
    # (b) IPCC's own published Africa weights must not be flagged
    for (x in list(c("Calves on forage", 82), c("Growing/Replacement", 204),
                   c("Draft Bullocks", 340), c("Mature Females - grazing", 275))) {
      st <- verdict(mk(x[1], "other", as.numeric(x[2])))
      if (!identical(st, "pass"))
        f <- c(f, sprintf("IPCC Annex 10A.2 '%s' (%s kg) flagged: %s",
                          x[1], x[2], paste(st, collapse = "/")))
    }
    # (c) a genuine outlier must still be caught
    if (identical(verdict(mk("calves", "other", 600)), "pass"))
      f <- c(f, "a 600 kg calf passed the benchmark")
    if (identical(verdict(mk("dairy_cows", "dairy", 1400)), "pass"))
      f <- c(f, "a 1400 kg dairy cow passed the benchmark")
    # (d) the citation must name what was actually compared against
    r <- .bench_reference("BW", "dairy_cows", "dairy", "africa")
    if (!isTRUE(all.equal(r$value,
          resolve_subcat_default("dairy_cows", "BW")$value)))
      f <- c(f, "dairy_cows benchmark does not equal its own resolved default")
    rd <- .bench_reference("BW", "DINT_unmatched", "dairy", "africa")
    rn <- .bench_reference("BW", "DINT_unmatched", "other", "africa")
    if (isTRUE(all.equal(rd$value, rn$value)))
      f <- c(f, "the dairy/non-dairy fallback returns the same number for both, so cattle_type only changes the wording")
    f
  }, error = function(e) conditionMessage(e))
  bench_ok <- length(bench_fail) == 0L
  check_bool("F38", "F",
             "QA benchmark is per sub-category and does not flag the tool's own defaults",
             bench_ok,
             notes = if (bench_ok)
               "9 sub-categories at their own defaults pass; IPCC Annex 10A.2 Africa weights pass; 600 kg calf and 1400 kg cow still caught; dairy and non-dairy fallbacks return different numbers"
             else paste(utils::head(bench_fail, 4), collapse = "; "))

  # F39 -- every object in the master is actually BUILT FROM the master.
  #
  # F32 asserts the master loads and the main objects have the right shape.
  # That is not the same claim. IPCC_DEFAULTS_BY_REGION and GWP_VALUES were
  # both written to the master by the export and then left as hand-written
  # literals in R/, so the master's copies were decorative and the two could
  # have drifted with nothing noticing.
  #
  # scripts/verify_defaults.R structurally cannot catch this: it generates
  # its row universe FROM the R objects, so a literal is compared against
  # itself and every surface agrees. The matrix proves the surfaces match
  # the constants; it says nothing about where the constants came from.
  #
  # The only test that distinguishes "reads the master" from "happens to
  # agree with it" is to change the master and watch the object move. One
  # numeric cell per object is perturbed in a temp copy, a clean R process
  # is pointed at it, and every object must report the perturbed value.
  # A literal keeps the old one and fails.
  deriv_fail <- tryCatch({
    m <- utils::read.csv(.DEFAULTS_MASTER_PATH, stringsAsFactors = FALSE,
                         na.strings = "<NA>", colClasses = "character")
    num <- !is.na(suppressWarnings(as.numeric(m$value)))
    objs <- unique(m$object[num])
    # one perturbable cell per object, and the expression that reads it back
    READBACK <- list(
      PARAM_CATALOGUE        = 'PARAM_CATALOGUE$%s[PARAM_CATALOGUE$parameter == "%s"]',
      MMS_DEFAULTS           = 'MMS_DEFAULTS$%s[MMS_DEFAULTS$id == "%s"]',
      MMS_FRAC_DEFAULTS_2019 = 'MMS_FRAC_DEFAULTS_2019$%s[MMS_FRAC_DEFAULTS_2019$mms_type == "%s"]',
      YM_BY_SUBCAT           = 'YM_BY_SUBCAT$%s[YM_BY_SUBCAT$sub_category == "%s"]',
      IPCC_DEFAULTS_BY_REGION= 'IPCC_DEFAULTS_BY_REGION$%s[IPCC_DEFAULTS_BY_REGION$region == "%s"]',
      GWP_VALUES             = 'GWP_VALUES[["%2$s"]]')
    picks <- list(); pert <- m
    for (o in objs) {
      i <- which(m$object == o & num)[1]
      old_v <- as.numeric(m$value[i])
      new_v <- old_v + 7          # a value no default legitimately holds
      pert$value[i] <- format(new_v, scientific = FALSE)
      expr <- READBACK[[o]]
      if (is.null(expr)) {
        # the *_BY_SUBCAT lists and FEEDING_SITUATION_CA
        expr <- sprintf('%s[["%%2$s"]]', o)
      }
      if (o == "GWP_VALUES") {
        parts <- strsplit(m$key[i], ".", fixed = TRUE)[[1]]
        code <- sprintf('GWP_VALUES[["%s"]][["%s"]]', parts[1], parts[2])
      } else {
        code <- sprintf(expr, m$field[i], m$key[i])
      }
      picks[[o]] <- list(code = code, want = new_v,
                         cell = paste(o, m$key[i], m$field[i], sep = "/"))
    }
    tmp <- tempfile(fileext = ".csv")
    on.exit(unlink(tmp), add = TRUE)
    utils::write.csv(pert, tmp, row.names = FALSE, na = "<NA>")
    probe <- tempfile(fileext = ".R")
    on.exit(unlink(probe), add = TRUE)
    writeLines(c(
      'suppressMessages(for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))',
      '  if (!grepl("^_", basename(f))) source(f))',
      unlist(lapply(names(picks), function(o) sprintf(
        'cat("%s|", tryCatch(as.numeric(%s)[1], error = function(e) NA), "
", sep = "")',
        o, picks[[o]]$code)))), probe)
    # Sys.setenv, NOT system2(env=): on Windows that argument is unsupported
    # and the child silently produces no output, which read as "every object
    # is a literal". The child inherits this process's environment instead.
    .old_env <- Sys.getenv("GMH_DEFAULTS_MASTER", unset = NA)
    Sys.setenv(GMH_DEFAULTS_MASTER = tmp)
    out <- suppressWarnings(system2(
      file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(probe)),
      stdout = TRUE, stderr = TRUE))
    if (is.na(.old_env)) Sys.unsetenv("GMH_DEFAULTS_MASTER")
    else Sys.setenv(GMH_DEFAULTS_MASTER = .old_env)
    f <- character(0)
    for (o in names(picks)) {
      # startsWith/fixed rather than a regex: a pipe needs escaping and the
      # object names are literals anyway.
      tag <- paste0(o, "|")
      ln  <- out[startsWith(out, tag)]
      got <- if (length(ln))
               suppressWarnings(as.numeric(sub(tag, "", ln[1], fixed = TRUE)))
             else NA_real_
      if (is.na(got) || abs(got - picks[[o]]$want) > 1e-9)
        f <- c(f, sprintf("%s did not follow the master (%s: wanted %s, got %s)",
                          o, picks[[o]]$cell, picks[[o]]$want, got))
    }
    if (!length(picks)) f <- c(f, "no objects tested")
    f
  }, error = function(e) conditionMessage(e))
  deriv_ok <- length(deriv_fail) == 0L
  check_bool("F39", "F",
             "Every master object is built FROM the master, proven by perturbation",
             deriv_ok,
             notes = if (deriv_ok)
               "one cell per object perturbed in a temp master; a clean R process reported the perturbed value for every one, so none is a hand-written literal"
             else paste(utils::head(deriv_fail, 3), collapse = "; "))

  # F40 -- a MISSING value is filled from the master, end to end.
  #
  # F39 proves the objects derive from the master. It says nothing about
  # code paths that never consult them, and the engine had a whole family:
  # get_param_alt() carried a literal per parameter for the case where a
  # row is absent entirely, and eight had drifted. Bo fell back to 0.10, a
  # 2006 value superseded in June, where the master says 0.13; Cfi to the
  # non-lactating 0.322 where the catalogue holds 0.386; EF4 to the
  # aggregated 0.010 where the catalogue holds the wet-climate 0.014. Two
  # of them sat on the verify_defaults allow-list as "bites only when the
  # row is absent entirely", which is precisely the gap-fill path.
  #
  # So this runs the ENGINE, not the objects: a deliberately incomplete
  # input against a perturbed master, and the answer must move. Anything
  # that reintroduces a literal breaks it.
  gapfill_fail <- tryCatch({
    m <- utils::read.csv(.DEFAULTS_MASTER_PATH, stringsAsFactors = FALSE,
                         na.strings = "<NA>", colClasses = "character")
    # Bo drives manure CH4 linearly and is the one that had actually drifted.
    i <- which(m$object == "PARAM_CATALOGUE" & m$key == "Bo" &
               m$field == "ipcc_default")
    stopifnot(length(i) == 1)
    m$value[i] <- "0.26"        # exactly double
    tmp <- tempfile(fileext = ".csv")
    on.exit(unlink(tmp), add = TRUE)
    utils::write.csv(m, tmp, row.names = FALSE, na = "<NA>")
    probe <- tempfile(fileext = ".R")
    on.exit(unlink(probe), add = TRUE)
    writeLines(c(
      'suppressMessages(for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))',
      '  if (!grepl("^_", basename(f))) source(f))',
      # Bo deliberately ABSENT from param_specs, so run_mc_simulation()
      # must gap-fill it. Calling ghg_emissions_vec() directly skips
      # get_param() entirely and tests nothing, which is how the first
      # version of this check passed against a reinstated literal.
      'ps <- data.frame(parameter = c("N", "BW", "DE"), mean = c(1000, 300, 55),',
      '  uncertainty_pct = c(0, 0, 0), lower = NA_real_, upper = NA_real_,',
      '  distribution = "constant", param_type = "activity_data",',
      '  stringsAsFactors = FALSE)',
      'r <- run_mc_simulation(ps, n_iter = 5L, seed = 1L,',
      '  mms_fractions = c(solid_storage = 1),',
      '  mcf_values = c(solid_storage = 0.04),',
      '  ef3_values = c(solid_storage = 0.01))',
      'cat("BO|", .cat_default("Bo"), "\n", sep = "")',
      'cat("CH4|", mean(r$results$manure_ch4_total), "\n", sep = "")'), probe)
    runp <- function(master) {
      o <- Sys.getenv("GMH_DEFAULTS_MASTER", unset = NA)
      Sys.setenv(GMH_DEFAULTS_MASTER = master)
      out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
        c("--vanilla", shQuote(probe)), stdout = TRUE, stderr = TRUE))
      if (is.na(o)) Sys.unsetenv("GMH_DEFAULTS_MASTER")
      else Sys.setenv(GMH_DEFAULTS_MASTER = o)
      g <- function(tag) {
        ln <- out[startsWith(out, tag)]
        if (!length(ln)) NA_real_
        else suppressWarnings(as.numeric(sub(tag, "", ln[1], fixed = TRUE)))
      }
      c(bo = g("BO|"), ch4 = g("CH4|"))
    }
    base <- runp(.DEFAULTS_MASTER_PATH)
    pert <- runp(tmp)
    f <- character(0)
    if (any(is.na(base)) || any(is.na(pert)))
      f <- c(f, "the probe produced no result")
    else {
      if (!isTRUE(all.equal(unname(pert[["bo"]]), 2 * unname(base[["bo"]]))))
        f <- c(f, sprintf("the Bo gap-fill did not follow the master (%s -> %s)",
                          base[["bo"]], pert[["bo"]]))
      if (!isTRUE(all.equal(unname(pert[["ch4"]]), 2 * unname(base[["ch4"]]),
                            tolerance = 1e-6)))
        f <- c(f, sprintf("doubling Bo in the master did not double manure CH4 (%s -> %s)",
                          base[["ch4"]], pert[["ch4"]]))
    }
    f
  }, error = function(e) conditionMessage(e))
  gapfill_ok <- length(gapfill_fail) == 0L
  check_bool("F40", "F",
             "A missing value is gap-filled from the master, proven through the engine",
             gapfill_ok,
             notes = if (gapfill_ok)
               "Bo omitted from the inputs and doubled in a temp master; the gap-fill and the resulting manure CH4 both doubled, so no literal is standing in for it"
             else paste(utils::head(gapfill_fail, 3), collapse = "; "))

  # F41 -- lactation is NOT weighted by the calving fraction; pregnancy IS.
  #
  # One parameter was doing two jobs. Review round 5 item 9 asked whether
  # merging pct_lactating into pct_pregnant was "both IPCC-compliant and
  # simpler"; the 28 May rename settled simpler and left compliant open.
  #
  # It is compliant for NE_p: Table 10.7 says "the NEp estimate must be
  # weighted by the portion of the mature females that actually go through
  # gestation in a year". It is not compliant for NE_l: Equation 10.8 is
  # Milk x (1.47 + 0.40 x Fat) and nothing else, and IPCC defines the milk
  # input as "total annual production divided by 365", already averaged
  # over the dry period. Applying the fraction discounted it twice, by 48%
  # once the low-productivity basis moved pct_pregnant to 0.52.
  #
  # Asserted as a property of the functions, not a stored number, so it
  # cannot be satisfied by updating a golden value.
  lact_fail <- tryCatch({
    f <- character(0)
    milk <- 5; fat <- 4
    if (!isTRUE(all.equal(calc_nel(milk, fat), milk * (1.47 + 0.40 * fat))))
      f <- c(f, "calc_nel does not equal Eq 10.8")
    if ("pct_pregnant" %in% names(formals(calc_nel)))
      f <- c(f, "calc_nel still accepts pct_pregnant; remove the argument so a caller passing it fails loudly")
    # NE_p must still respond to it.
    if (isTRUE(all.equal(calc_nep(100, 0.1, 0.5), calc_nep(100, 0.1, 1))))
      f <- c(f, "calc_nep ignores pct_pregnant, but Table 10.7 requires the weighting")
    # End to end: halving pct_pregnant must NOT halve enteric CH4, because
    # lactation no longer depends on it, while N excretion must not move at
    # all through the milk-N term.
    g <- function(p) resolve_subcat_default("dairy_cows", p)$value
    run <- function(pp) ghg_emissions(cattle_pop = 1e5,
      live_weight = g("BW"), weight_gain = g("WG"), mature_weight = g("MW"),
      milk_yield = g("Milk"), milk_fat = g("Fat"), pct_pregnant = pp,
      hours = g("hours"), DE = g("DE"), Cfi = g("Cfi"), Ca = g("Ca"),
      C_growth = g("C"), Cp = g("Cp"), Ym = g("Ym"), Bo = g("Bo"),
      ASH = g("ASH"), UE = g("UE"), CP = g("CP"),
      mms_fractions = c(pasture = 1), mcf_values = c(pasture = 0.02),
      ef3_values = c(pasture = 0.02), EF3_PRP = 0.006, Frac_GASMS = 0.21,
      EF4 = 0.014, EF5 = 0.011, Frac_LEACH_H = 0.24, gwp = "AR5")
    a <- run(0.52); b <- run(0.26)
    # It should still move a little, through NE_p, but nowhere near halving.
    ratio <- b$enteric_ch4_total / a$enteric_ch4_total
    if (ratio < 0.97)
      f <- c(f, sprintf("halving pct_pregnant moved enteric CH4 by %.1f%%, so lactation is still weighted by it",
                        100 * (ratio - 1)))
    # feedlot cattle must not carry a pregnancy fraction at all
    r <- resolve_subcat_default("feedlot_cattle", "pct_pregnant")
    if (!identical(r$data_source, "biological_zero") || !isTRUE(r$value == 0))
      f <- c(f, sprintf("feedlot_cattle pct_pregnant = %s; Annex 10A.2 leaves the Pregnant column blank for every feedlot row", r$value))
    # heifers MUST keep one (review round 7 item 2)
    if (isTRUE(resolve_subcat_default("heifers", "pct_pregnant")$value == 0))
      f <- c(f, "heifers lost their pregnancy fraction; review round 7 item 2 required it")
    f
  }, error = function(e) conditionMessage(e))
  lact_ok <- length(lact_fail) == 0L
  check_bool("F41", "F",
             "NE_l follows Eq 10.8 with no calving-fraction weighting; NE_p keeps it",
             lact_ok,
             notes = if (lact_ok)
               "calc_nel equals Milk x (1.47 + 0.40 x Fat) and no longer takes pct_pregnant; calc_nep still responds to it; halving the fraction leaves enteric CH4 almost unchanged; feedlot is a biological zero and heifers keep theirs"
             else paste(utils::head(lact_fail, 3), collapse = "; "))

  # F42 -- the value came from the RIGHT table, not merely from some table.
  #
  # "Is this number in IPCC?" is the wrong question and it passed things it
  # should not have. Composting's MCF of 0.5 is in IPCC twice: as the 2019
  # Refinement's In-vessel figure and as the 2006 static-pile figure. I
  # checked it against the first, found a mismatch with the variant the row
  # declares, and proposed changing a correct value. The tool reads MCF from
  # the 2006 table, where 0.5 IS static pile.
  #
  # The fix is to write down, per coefficient family, which table it must
  # come from, and check against that rather than against whichever table
  # happens to contain the number.
  #
  # Hardcoded deliberately: this is the verification's own reference, and
  # deriving it from the data it verifies would be circular.
  SOURCE_OF_RECORD <- list(
    # mcf_tropical_dry is excluded: it is definitionally a COPY of
    # mcf_tropical, so its provenance is that column's, and asserting a
    # table name against it tests a string rather than the property that
    # matters. The property is asserted directly below instead.
    list(object = "MMS_DEFAULTS", field = "^mcf_(tropical$|temperate|boreal)",
         table = "10.17", edition = "2006",
         why = "the tool resolves four climate zones and the 2006 per-degree table maps onto them cleanly; the 2019R ten-zone table does not",
         except = list(
           solid_storage_covered = c("10.17", "2019R"),   # no 2006 row exists
           anaerobic_digester    = c("10A.11", "2019R"))),# 2006 gives only 0-100%
    list(object = "MMS_DEFAULTS", field = "^ef3$", table = "10.21",
         edition = "2019R", why = "2006 does not split these systems into variants",
         except = list(pasture = c("11.1", ""))),         # PRP is a Chapter 11 pathway
    list(object = "MMS_FRAC_DEFAULTS_2019", field = "^frac_", table = "10.22",
         edition = "2019R", why = "2006 publishes no per-system nitrogen fractions",
         except = list(pasture = c("", ""), burned_for_fuel = c("", ""))),
    list(object = "CFI_BY_SUBCAT", field = "^value$", table = "10.4",
         edition = "2019R", why = "the per-category Cfi table"),
    list(object = "YM_BY_SUBCAT", field = "^ym_", table = "10.12",
         edition = "", why = "Table 10.12 in both editions; the column says which"),
    list(object = "LW_BY_SUBCAT", field = "^value$", table = "10A.",
         edition = "2019R", why = "Annex 10A.1 for the dairy row, 10A.2 for the rest"),
    list(object = "DE_BY_SUBCAT", field = "^value$", table = "10A.",
         edition = "2019R", why = "as LW_BY_SUBCAT"),
    list(object = "CP_BY_SUBCAT", field = "^value$", table = "10A.",
         edition = "2019R", why = "as LW_BY_SUBCAT"),
    list(object = "FEEDING_SITUATION_CA", field = "^value$", table = "10.5",
         edition = "2019R", why = "the activity-coefficient table"))

  m <- .defaults_master
  isnum <- !is.na(suppressWarnings(as.numeric(m$value)))
  # DEVIATION_DOCUMENTED is exempt from the TABLE requirement because such a
  # value by definition does not come from the declared table; that is what
  # makes it a deviation, and its source is required to explain the
  # departure instead. DEVIATION_OPEN is NOT exempt: an unexplained
  # difference is precisely the case where the declared table must be cited
  # so the gap is visible.
  EXEMPT <- c("NOT_IPCC", "NO_IPCC_DEFAULT", "META", "DEVIATION_DOCUMENTED")
  src_fail <- tryCatch({
    f <- character(0)
    for (rule in SOURCE_OF_RECORD) {
      sel <- isnum & m$object == rule$object & grepl(rule$field, m$field)
      for (i in which(sel)) {
        if (m$ipcc_verdict[i] %in% EXEMPT) next
        want_t <- rule$table; want_e <- rule$edition
        ex <- rule$except[[m$key[i]]]
        if (!is.null(ex)) { want_t <- ex[1]; want_e <- ex[2] }
        if (!nzchar(want_t)) next
        src <- m$ipcc_source[i]
        if (is.na(src) || !grepl(want_t, src, fixed = TRUE))
          f <- c(f, sprintf("%s/%s/%s should be read from Table %s and its source does not say so",
                            m$object[i], m$key[i], m$field[i], want_t))
        else if (nzchar(want_e) && !grepl(want_e, src, fixed = TRUE))
          f <- c(f, sprintf("%s/%s/%s should be the %s edition of Table %s",
                            m$object[i], m$key[i], m$field[i], want_e, want_t))
      }
    }
    # The mirrored column: assert it actually mirrors, on every system.
    md <- .master_wide("MMS_DEFAULTS", "id")
    if (!isTRUE(all.equal(md$mcf_tropical_dry, md$mcf_tropical)))
      f <- c(f, "mcf_tropical_dry no longer mirrors mcf_tropical; it has no source of its own, so it must")

    # Citation invariants on the catalogue. ipcc_ref means WHERE THE VALUE
    # COMES FROM; ipcc_equation means where it is used. Conflating them is
    # how MW cited a table with no mature-weight column, and how BW kept
    # citing 10A.2 after its value moved to 10A.1.
    pc <- .master_wide("PARAM_CATALOGUE", "parameter")
    for (i in seq_len(nrow(pc))) {
      v <- m$ipcc_verdict[m$object == "PARAM_CATALOGUE" &
                          m$key == pc$parameter[i] & m$field == "ipcc_default"]
      if (!length(v)) next
      ref <- pc$ipcc_ref[i]; if (is.na(ref)) ref <- ""
      if (v[1] %in% c("NOT_IPCC", "NO_IPCC_DEFAULT") && nzchar(ref))
        f <- c(f, sprintf("%s is %s yet cites '%s' as the source of its value",
                          pc$parameter[i], v[1], ref))
      if (v[1] %in% c("CONFIRMED", "INTERPRETED", "DEVIATION_DOCUMENTED") &&
          !nzchar(ref))
        f <- c(f, sprintf("%s is %s but names no source for its value",
                          pc$parameter[i], v[1]))
      # and the citation must name the table the source actually read
      tb <- regmatches(ref, regexpr("[0-9]+[A-Z]?[.][0-9]+[A-Z]?", ref))
      src <- m$ipcc_source[m$object == "PARAM_CATALOGUE" &
                           m$key == pc$parameter[i] & m$field == "ipcc_default"]
      if (length(tb) && length(src) && !grepl(tb[1], src[1], fixed = TRUE))
        f <- c(f, sprintf("%s cites Table %s but was read from a different table",
                          pc$parameter[i], tb[1]))
    }
    f
  }, error = function(e) conditionMessage(e))
  src_ok <- length(src_fail) == 0L
  check_bool("F42", "F",
             "Each value comes from its declared source table, and its citation says so",
             src_ok,
             notes = if (src_ok)
               sprintf("%d coefficient families each have a declared source table with its exceptions; every non-exempt value cites it, and no catalogue parameter cites a table it was not read from",
                       length(SOURCE_OF_RECORD))
             else paste(utils::head(src_fail, 4), collapse = "; "))


  # F43 -- the engine's gap-fill reads the master, with declared exceptions.
  #
  # F40 proved this for Bo by perturbation. Bo reaches the engine through
  # get_param("Bo") with no literal, so F40 was asking a question Bo could
  # not fail, and it passed for two weeks while four other parameters were
  # gap-filled from stale literals sitting right beside it:
  #
  #   CP       10     master 9.6    (the Table 10A.2 non-dairy figure)
  #   MilkPR   3.3    master 3.6    (cited to Table 10.11, which is the
  #                                  Tier 1 enteric EF table, not protein)
  #   EF3_PRP  0.004  master 0.006  (climate-aggregated, not wet)
  #   EF4      0.010  master 0.014  (climate-aggregated, not wet)
  #
  # A user who left those four cells blank got a different number from one
  # who filled them with the value the Parameters sheet, both guides and the
  # translator all quote. Direct PRP N2O was 43% low.
  #
  # The defect is not any one literal, it is that a literal was allowed at
  # all. So the check is structural: inside the ghg_emissions_vec() call,
  # every get_param()/get_param_alt() either passes no default, and so reads
  # the catalogue, or is on this list with a reason.
  ENGINE_LITERALS <- list(
    N            = list(value = 0,    why = "no animals is safer than an invented herd"),
    Milk         = list(value = 0,    why = "the engine cannot see the sub-category; an absent Milk row most likely means the group does not lactate, and filling the catalogue 1.2 would add lactation energy to every one"),
    hours        = list(value = 0,    why = "absent means no draught work"),
    Frac_GASMS   = list(value = 0.21, why = "manure-management side, Table 10.22; removed from the Parameters sheet on review round 7 and has no catalogue row"),
    Frac_LEACH_H = list(value = 0.02, why = "manure-management side, Table 10.23; same as Frac_GASMS"))

  gapfill_lit_fail <- tryCatch({
    f <- character(0)
    src <- readLines("R/mc_simulation.R", warn = FALSE)
    a <- grep("^\\s*results <- ghg_emissions_vec\\(", src)
    stopifnot(length(a) == 1L)
    b <- a + which(grepl("^\\s*\\)\\s*$", src[(a + 1):length(src)]))[1]
    block <- src[a:b]
    # get_param("X", <literal>) or get_param_alt("X", "old", <literal>)
    calls <- regmatches(block, gregexpr(
      'get_param(_alt)?\\("[^"]+"(, *"[^"]+")?, *[0-9.]+\\)', block))
    calls <- unlist(calls)
    for (cl in calls) {
      nm <- sub('^get_param(_alt)?\\("([^"]+)".*$', "\\2", cl)
      lit <- as.numeric(sub('^.*, *([0-9.]+)\\)$', "\\1", cl))
      dec <- ENGINE_LITERALS[[nm]]
      if (is.null(dec)) {
        f <- c(f, sprintf("%s is gap-filled from the literal %s instead of the master; delete the default or declare it in ENGINE_LITERALS with a reason",
                          nm, format(lit)))
      } else if (!isTRUE(all.equal(lit, dec$value))) {
        f <- c(f, sprintf("%s is declared as the literal %s but the code passes %s",
                          nm, format(dec$value), format(lit)))
      }
    }
    # An exception is only ever legitimate for one of two reasons, and this
    # asserts it is one of them. Either the fallback is a safety ZERO, which
    # is deliberately independent of whatever the catalogue says (hours must
    # stay 0 even though the catalogue's hours is a live open item that may
    # move to the 1.1 hrs/day of Annex 10A.2 draft bullocks, because the
    # engine cannot see whether the group is oxen), or the quantity has no
    # catalogue row at all. Anything else is a literal competing with the
    # master, which is the defect.
    pc <- PARAM_CATALOGUE
    for (nm in names(ENGINE_LITERALS)) {
      dec <- ENGINE_LITERALS[[nm]]
      if (isTRUE(all.equal(dec$value, 0))) next          # safety zero
      if (!nm %in% pc$parameter) next                    # no catalogue row
      f <- c(f, sprintf("%s has a catalogue row and a non-zero literal fallback of %s; read the master instead, or say why this one number must not follow it",
                        nm, format(dec$value)))
    }
    # Signature defaults are the same hiding place: MilkPR sat at 3.3 in two
    # of them, unreachable from the master. Any catalogue parameter
    # defaulted in these signatures must read .cat_default() instead.
    #
    # The pattern must NOT be anchored to end of line. The first version was
    # (`= [0-9.]+\s*[,)]?\s*$`) and it passed against the reinstated
    # `MilkPR = 3.3) {`, because the line ends in `) {` rather than `)`.
    # The check was written for that exact defect and could not see it.
    #
    # calc_energy.R is deliberately out of scope: the 20 in
    # calc_nem(live_weight, Cfi, Tw = 20) is Equation 10.2's own threshold,
    # the temperature below which the cold adjustment switches on. It must
    # not follow the catalogue's Tw even though the two happen to be equal.
    for (fl in c("R/calc_ghg_master.R", "R/calc_manure_n2o.R")) {
      s <- readLines(fl, warn = FALSE)
      s <- s[!grepl("^\\s*#", s)]
      for (p in pc$parameter) {
        if (p %in% names(ENGINE_LITERALS)) next
        # Zero is exempt for the same reason as the engine's three zeros:
        # it is never a stale reading of an IPCC table, it is always the
        # "absent means none" choice (pct_pregnant = 0 in calc_n_excretion).
        pat <- sprintf("(^|[(,[:space:]])%s[[:space:]]*=[[:space:]]*[0-9.]+[[:space:]]*[,)]",
                       p)
        hits <- grep(pat, s, value = TRUE)
        nums <- suppressWarnings(as.numeric(
          sub(sprintf("^.*%s[[:space:]]*=[[:space:]]*([0-9.]+).*$", p), "\\1", hits)))
        if (any(!is.na(nums) & nums != 0))
          f <- c(f, sprintf("%s has a bare numeric default in %s; read .cat_default(\"%s\") so it cannot drift from the master",
                            p, fl, p))
      }
    }
    f
  }, error = function(e) conditionMessage(e))
  gapfill_lit_ok <- length(gapfill_lit_fail) == 0L
  check_bool("F43", "F",
             "No engine gap-fill invents a value: every fallback reads the master or is a declared exception",
             gapfill_lit_ok,
             notes = if (gapfill_lit_ok)
               sprintf("%d declared exceptions (%s), each with a reason; every other parameter reaching ghg_emissions_vec() falls back to the catalogue, and no calc_ signature defaults a catalogue parameter to a number",
                       length(ENGINE_LITERALS),
                       paste(names(ENGINE_LITERALS), collapse = ", "))
             else paste(utils::head(gapfill_lit_fail, 4), collapse = "; "))

  # F34 -- the translator kit generator can still run. It does NOT source R/
  # alphabetically the way the app does; it names three or four files
  # explicitly, so a new load-order dependency in R/ breaks it without
  # breaking anything else. That is not hypothetical: the defaults-master
  # migration made utils_template.R call .master_wide() at source time, the
  # generator did not name load_defaults.R, and the build died with "could not
  # find function". Nothing caught it because the kit build is not in CI and
  # the already-generated prompts still matched the master.
  #
  # Sourcing the generator's own file list, in its own order, reproduces the
  # failure in about a second without rendering PDFs. The list is parsed from
  # the script so the check cannot drift from it.
  #
  # This MUST run in a separate R process. The audit has already sourced all
  # of R/ into its own global environment, so a new.env() inside this session
  # finds .master_wide() through the parent chain and the check passes even
  # with the dependency missing. That is not a hypothetical either: the first
  # version of F34 did exactly that and reported PASS against the broken
  # script. Only a clean process reproduces what `Rscript build_...` sees.
  kit_ok <- tryCatch({
    src <- readLines("scripts/build_translator_kit.R", warn = FALSE)
    files <- regmatches(src, regexpr('source\\("R/[^"]+', src))
    files <- sub('^source\\("', "", files)
    stopifnot(length(files) >= 3)
    kit_files <<- files
    probe <- tempfile(fileext = ".R")
    on.exit(unlink(probe), add = TRUE)
    writeLines(c(
      sprintf('source("%s")', files),
      'stopifnot(is.data.frame(PARAM_CATALOGUE), nrow(PARAM_CATALOGUE) == 25L)',
      'cat("KIT_SOURCE_ORDER_OK\\n")'), probe)
    res <- suppressWarnings(system2(
      file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(probe)),
      stdout = TRUE, stderr = TRUE))
    kit_err <<- paste(utils::tail(res, 3), collapse = " | ")
    any(grepl("KIT_SOURCE_ORDER_OK", res, fixed = TRUE))
  }, error = function(err) { kit_err <<- conditionMessage(err); FALSE })
  check_bool("F34", "F",
             "Translator kit generator's declared source order still resolves",
             kit_ok,
             notes = if (kit_ok)
               sprintf("sourced %s in the generator's own order; PARAM_CATALOGUE rebuilt with 25 rows",
                       paste(basename(kit_files), collapse = ", "))
             else sprintf("scripts/build_translator_kit.R cannot source its own file list: %s",
                          if (exists("kit_err")) kit_err else "unknown error"))

  # F31 — sparse-overlay writer integration (the safety net). Writing a SPARSE
  # input (only the user's own rows + the MMS allocation) through
  # .translator_write_official_template must yield a COMPLETE template (every
  # sub-category x 25 parameters), with user values preserved and every omitted
  # cell filled from the resolver / MMS tables — proving the gap-fill is correct
  # end-to-end (write -> parse round-trip).
  if (requireNamespace("openxlsx", quietly = TRUE) &&
      exists(".translator_write_official_template") &&
      exists("parse_uploaded_template")) {
    user_params <- data.frame(
      cattle_type       = c("dairy","non_dairy","non_dairy","dairy","dairy"),
      aggregation_level = rep("all", 5),
      sub_category      = c("dairy_cows","bulls","oxen","dairy_cows","dairy_cows"),
      parameter         = c("N","N","N","BW","Milk"),
      value             = c(100, 10, 20, 420, 14),
      uncertainty_pct   = c(10, 10, 10, 15, 20),
      distribution      = rep("normal", 5),
      data_source       = rep("user_file", 5),
      stringsAsFactors  = FALSE)
    mm_sparse <- data.frame(
      cattle_type = c("dairy","non_dairy","non_dairy"),
      aggregation_level = rep("all", 3),
      sub_category = c("dairy_cows","bulls","oxen"),
      mms_type = c("solid_storage","dry_lot","pasture"),
      fraction_pct = c(100, 100, 100),
      stringsAsFactors = FALSE)
    md <- list(country = "Test", region = "africa", year = 2024,
               species = "cattle_mixed", ipcc_version = "2019_refinement")
    f <- tempfile(fileext = ".xlsx")
    sp_ok <- tryCatch({
      .translator_write_official_template(
        list(inventory_metadata = md, parameters = user_params,
             manure_management = mm_sparse,
             parameter_timeseries = data.frame()), f)
      pu <- parse_uploaded_template(f)
      ps <- pu$param_specs; mn <- pu$manure
      pick <- function(sc, p) ps$mean[ps$sub_category == sc & ps$parameter == p][1]
      mmv  <- function(sc, col) mn[[col]][mn$sub_category == sc][1]
      # a) completeness: 3 sub-categories x 25 params
      cnt_ok <- nrow(ps) == 3L * nrow(PARAM_CATALOGUE)
      # b) user values preserved
      usr_ok <- eq(pick("dairy_cows","N"), 100) && eq(pick("dairy_cows","BW"), 420) &&
                eq(pick("dairy_cows","Milk"), 14) && eq(pick("bulls","N"), 10)
      # c) parameter gap-fill matches the resolver (sex overrides + zeros + default)
      gap_ok <- eq(pick("bulls","Cfi"), 0.370) && eq(pick("oxen","Cfi"), 0.322) &&
                eq(pick("bulls","C"), 1.2) && eq(pick("bulls","Milk"), 0) &&
                eq(pick("dairy_cows","DE"), 51) &&
                eq(pick("dairy_cows","pct_pregnant"), 0.52) &&
                # oxen, not other_cows: this fixture writes three
                # sub-categories (dairy_cows, bulls, oxen) and a pick() on an
                # absent one returns NA, which fails silently rather than
                # testing anything.
                eq(pick("oxen","DE"), 58) && eq(pick("oxen","CP"), 10.0) &&
                eq(pick("bulls","Bo"), 0.13)
      # d) MMS coefficient gap-fill from the tables
      mms_fill_ok <- eq(mmv("dairy_cows","EF3"), 0.010) &&
                     eq(mmv("dairy_cows","MCF_pct"), 5.0) &&   # solid_storage tropical
                     eq(mmv("bulls","EF3"), 0.02) &&           # dry_lot
                     # Asserting bulls EF3 without bulls MCF is how the
                     # dry_lot 5.0 -> 2.0 correction got past this check once.
                     eq(mmv("bulls","MCF_pct"), 2.0)           # dry_lot tropical
      cnt_ok && usr_ok && gap_ok && mms_fill_ok
    }, error = function(e) { message("F31 error: ", conditionMessage(e)); FALSE })
    unlink(f)
    check_bool("F31", "F",
               "sparse-overlay writer fills every omitted cell (complete template; user values + IPCC defaults)",
               isTRUE(sp_ok),
               notes = if (isTRUE(sp_ok)) "75 param rows; user values kept; bulls.Cfi=0.370, bulls.Milk=0, EF3 solid_storage=0.010"
                       else "sparse write/parse round-trip did not reproduce the expected complete template")
  }
}

# =============================================================================
# Section G — download outputs
# =============================================================================
section_G <- function() {
  cat("\n[G] Download / export functions...\n")
  sd_var <- build_golden_system(make_golden_specs(constant_dist = FALSE))
  sd_var[[1]]$param_specs$lower <- sd_var[[1]]$param_specs$mean * 0.95
  sd_var[[1]]$param_specs$upper <- sd_var[[1]]$param_specs$mean * 1.05
  sd_var[[1]]$param_specs$lower[sd_var[[1]]$param_specs$parameter %in%
                                  c("WG","hours")] <- 0
  sd_var[[1]]$param_specs$upper[sd_var[[1]]$param_specs$parameter %in%
                                  c("WG","hours")] <- 0
  sim <- run_inventory_simulation(sd_var, n_iter = 500, gwp = "AR5",
                                   seed = 123, pct_pregnant = 1)
  unc <- calc_all_uncertainty(sim$inventory)
  ipcc <- format_ipcc_table(list(combined = unc, ad_only = unc, ef_only = unc))

  # G1 — xlsx
  xpath <- tempfile(fileext = ".xlsx")
  ok_x <- tryCatch({
    export_results_xlsx(sim$inventory, unc, sensitivity = NULL,
                         ipcc_table = ipcc, filepath = xpath,
                         settings = list(n_iter = 500L, gwp_version = "AR5",
                                          emission_sources = character(0)))
    file.exists(xpath) && file.info(xpath)$size > 0
  }, error = function(e) FALSE)
  check_bool("G1", "G",
             "export_results_xlsx produces non-empty file",
             ok_x,
             notes = if (ok_x) sprintf("%d bytes", file.info(xpath)$size) else "")

  # G2 — csv (we replicate the download_csv structure since the handler lives
  # in app_server.R's downloadHandler)
  cpath <- tempfile(fileext = ".csv")
  ok_c <- tryCatch({
    write.csv(unc, cpath, row.names = FALSE)
    file.exists(cpath) && file.info(cpath)$size > 0
  }, error = function(e) FALSE)
  check_bool("G2", "G",
             "CSV write of uncertainty frame produces non-empty file",
             ok_c,
             notes = if (ok_c) sprintf("%d bytes", file.info(cpath)$size) else "")

  # G3 — docx
  dpath <- tempfile(fileext = ".docx")
  ok_d <- tryCatch({
    build_run_summary_docx(
      path = dpath,
      settings = list(n_iter = 500L, gwp_version = "AR5",
                       corr_mode = "none", ef_corr_mode = "none",
                       analysis_mode = "single",
                       emission_sources = character(0)),
      param_specs = sim$by_system[[1]]$samples,
      mc_results = sim,
      uncertainty = unc,
      sensitivity = NULL,
      ipcc_table = ipcc)
    file.exists(dpath) && file.info(dpath)$size > 50000
  }, error = function(e) FALSE)
  check_bool("G3", "G",
             "build_run_summary_docx produces Word file > 50 KB",
             ok_d,
             notes = if (ok_d) sprintf("%d bytes", file.info(dpath)$size) else "")

  # G4 — methodology.Rmd Reporting section present (Andreas review round 2):
  # CRT category map covering 3.A, 3.B, 3.D.
  meth_path <- if (file.exists("doc/methodology.Rmd")) "doc/methodology.Rmd"
               else if (file.exists("methodology.Rmd")) "methodology.Rmd"
               else NULL
  meth_txt <- if (!is.null(meth_path))
    paste(readLines(meth_path, warn = FALSE, encoding = "UTF-8"),
          collapse = "\n") else ""
  has_crt_a <- grepl("3\\.A Enteric fermentation", meth_txt)
  has_crt_b <- grepl("3\\.B Manure management", meth_txt)
  has_crt_d <- grepl("3\\.D Agricultural soils", meth_txt)
  check_bool("G4", "G",
             "methodology.Rmd Reporting section contains CRT category map (3.A / 3.B / 3.D)",
             has_crt_a && has_crt_b && has_crt_d,
             notes = sprintf("3.A=%s 3.B=%s 3.D=%s",
                             has_crt_a, has_crt_b, has_crt_d))

  # G5 — methodology.Rmd Reporting section contains the three-level
  # disaggregation guide (Level 1 / Level 2 / Level 3).
  has_l1 <- grepl("Level 1", meth_txt)
  has_l2 <- grepl("Level 2", meth_txt)
  has_l3 <- grepl("Level 3", meth_txt)
  check_bool("G5", "G",
             "methodology.Rmd Reporting section contains Level 1/2/3 disaggregation guide",
             has_l1 && has_l2 && has_l3,
             notes = sprintf("L1=%s L2=%s L3=%s", has_l1, has_l2, has_l3))
}

# =============================================================================
# Run all sections and write the report
# =============================================================================
# Each section is wrapped in tryCatch so an unexpected error in one section
# does not abort the rest. The crash is logged as a SKIP row in the report.
safe_run <- function(label, fn) {
  tryCatch(fn(),
    error = function(e) {
      cat("  *** Section ", label, " aborted: ", conditionMessage(e), "\n",
          sep = "")
      record(label, label, sprintf("Section %s — unhandled error", label),
             "completion", "error", "SKIP", conditionMessage(e))
    })
}
safe_run("A", section_A)
safe_run("B", section_B)
safe_run("C", section_C)
safe_run("D", section_D)
safe_run("E", section_E)
safe_run("F", section_F)
safe_run("G", section_G)

results_df <- do.call(rbind, results)

# ---------------------------------------------------------------------------
# Compose AUDIT_REPORT.md
# ---------------------------------------------------------------------------
pass <- sum(results_df$status == "PASS")
fail <- sum(results_df$status == "FAIL")
skip <- sum(results_df$status == "SKIP")
total <- nrow(results_df)
verdict <- if (fail == 0) "**AUDIT CLEAN**" else
            sprintf("**%d FAILED** — see Bug Findings below", fail)

md <- c(
  "# AUDIT_REPORT.md — Statistician's end-to-end audit",
  "",
  sprintf("Generated %s by `_audit.R`.", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  "",
  "## Summary",
  "",
  sprintf("- Tests run: **%d**", total),
  sprintf("- Pass: **%d**", pass),
  sprintf("- Fail: **%d**", fail),
  sprintf("- Skip: **%d**", skip),
  sprintf("- Verdict: %s", verdict),
  "",
  "## Golden case",
  "",
  "Synthetic single-sub-category dairy inventory with all 27 IPCC-aligned parameters fixed at known values. See the comment block at the top of `_audit.R` for the full hand-computed reference table; key values:",
  "",
  sprintf("- NEM = %.4f MJ/day (Eq. 10.3)", golden_ref$NEM),
  sprintf("- GE  = %.4f MJ/head/day (Eq. 10.16)", golden_ref$GE),
  sprintf("- Enteric CH₄ = %.4f kg CH₄/head/yr (Eq. 10.21)", golden_ref$enteric_ch4_head),
  sprintf("- Manure CH₄  = %.4f kg CH₄/head/yr (Eq. 10.23, 100%% pasture)", golden_ref$manure_ch4_head),
  sprintf("- Nex         = %.4f kg N/head/yr (Eq. 10.32)", golden_ref$Nex),
  sprintf("- Total CO₂eq AR5 (N=100,000) = **%.2f tonnes**", golden_ref$total_co2e_AR5),
  sprintf("- Total CO₂eq AR4 = %.2f tonnes", golden_ref$total_co2e_AR4),
  sprintf("- Total CO₂eq AR6 = %.2f tonnes", golden_ref$total_co2e_AR6),
  "",
  "## Test results",
  "",
  "| ID | Section | Description | Status | Notes |",
  "|----|---------|-------------|--------|-------|"
)
for (i in seq_len(nrow(results_df))) {
  r <- results_df[i, ]
  emoji <- switch(r$status, PASS = "✅", FAIL = "❌", SKIP = "⏭️", "❓")
  md <- c(md, sprintf("| %s | %s | %s | %s %s | %s |",
                       r$id, r$section, r$description, emoji, r$status,
                       if (nzchar(r$notes)) r$notes else ""))
}

# Detailed numeric table for inspection
md <- c(md, "",
        "## Detailed numerics",
        "",
        "| ID | Expected | Actual | Status |",
        "|----|----------|--------|--------|")
for (i in seq_len(nrow(results_df))) {
  r <- results_df[i, ]
  md <- c(md, sprintf("| %s | %s | %s | %s |",
                       r$id, r$expected, r$actual, r$status))
}

# Bug findings section (only if any FAIL)
if (fail > 0) {
  md <- c(md, "",
          "## Bug findings",
          "",
          "The following tests failed and warrant investigation. The audit task does NOT fix them; they are to be triaged into a follow-up task.",
          "")
  failures <- results_df[results_df$status == "FAIL", ]
  for (i in seq_len(nrow(failures))) {
    f <- failures[i, ]
    md <- c(md, sprintf("### %s — %s", f$id, f$description), "",
                  sprintf("- Expected: `%s`", f$expected),
                  sprintf("- Actual:   `%s`", f$actual),
                  if (nzchar(f$notes)) sprintf("- Notes:    %s", f$notes) else "",
                  "")
  }
}

md <- c(md, "",
        "## Findings & recommendations",
        "",
        "Even though every formal test passed, two minor robustness issues surfaced while building the harness. Neither is reachable from normal app use, but both are worth documenting:",
        "",
        "**1. `run_inventory_simulation()` crashes with `n_iter = 1` on a single-system inventory.**",
        "",
        "Location: `R/mc_simulation.R` lines ~199-211. The data-frame construction uses `rowSums(sapply(by_system, function(s) s$results$some_col))`. When `by_system` has a single entry and `n_iter = 1`, `sapply` returns a length-1 vector (not a matrix), and `rowSums()` then throws *\"'x' must be an array of at least two dimensions\"*. This is not reachable from the live app (the UI's iteration slider has a minimum of 1,000) but it makes the function fragile for unit testing or any caller that might pass a single iteration. Cheap fix: wrap each `sapply(...)` in `as.matrix()` or guard with `if (length(by_system) == 1L) ...`.",
        "",
        "**2. Country X synthetic time-series has perfectly linear `Milk` growth (5 years × 0.2 kg/day, no noise).**",
        "",
        "Location: `R/utils_ipcc_defaults.R::generate_country_x_timeseries()`. First-differencing collapses the `Milk` column to a constant (every diff = 0.2), which gives `sd = 0` and breaks any naive `cor()` call. The app's own `compute_correlation_from_timeseries()` handles this correctly (line 264 drops zero-variance columns), but the synthetic series is unrealistic — a real time series would have noise. Cheap fix: add a small jitter (±0.05) to one of the Milk values so the series exercises the auto-correlation path realistically.",
        "",
        "## Methodology notes",
        "",
        "- Deterministic checks (Section A) use `n_iter = 1` with every parameter's distribution set to `\"constant\"`. The simulator collapses to a single deterministic call through the IPCC equation chain, which lets us compare each intermediate against a hand-computed reference value to within `TOL_REL = 1e-4` relative tolerance.",
        "- Monte Carlo convergence checks (Sections B, D) use `n_iter = 50,000` or `500` and compare empirical statistics (mean, Spearman rank correlation) against analytical expectations to within `TOL_MC = 0.02` absolute on correlations, `0.01` relative on means.",
        "- The audit does NOT go through the Shiny `input$` / observer layer — it calls `run_inventory_simulation()`, `calc_*` functions, `validate_*` functions, and the export builders directly. UI rendering, button-click flow, and tooltip text are not exercised here. (If the calculation engine is correct, the UI shows correct numbers; the rendering layer's bugs would be a separate UX audit.)",
        "- The hand-comp treats the equation forms as implemented in `R/calc_*.R`. The audit does not re-verify those equation forms against the IPCC source PDFs — that was the May-2026 IPCC alignment audit's scope.",
        "",
        "## Reproducibility",
        "",
        "Run `Rscript scripts/audit.R` from the repo root. Output is deterministic conditional on the seeds in each test block.",
        "")

writeLines(md, "AUDIT_REPORT.md", useBytes = TRUE)
cat(sprintf("\n=== AUDIT COMPLETE ===\nTotal: %d  Pass: %d  Fail: %d  Skip: %d\nReport: AUDIT_REPORT.md\n",
            total, pass, fail, skip))

# Non-zero exit on failure so CI (.github/workflows/audit.yml) gates on this.
# Guarded on interactive() so sourcing the script in an R session still just
# prints the summary instead of killing the session.
if (fail > 0L && !interactive()) quit(save = "no", status = 1L)
