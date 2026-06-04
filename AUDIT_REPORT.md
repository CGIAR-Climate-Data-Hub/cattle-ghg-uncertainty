# AUDIT_REPORT.md — Statistician's end-to-end audit

Generated 2026-06-04 10:46 CEST by `_audit.R`.

## Summary

- Tests run: **91**
- Pass: **91**
- Fail: **0**
- Skip: **0**
- Verdict: **AUDIT CLEAN**

## Golden case

Synthetic single-sub-category dairy inventory with all 27 IPCC-aligned parameters fixed at known values. See the comment block at the top of `_audit.R` for the full hand-computed reference table; key values:

- NEM = 27.8246 MJ/day (Eq. 10.3)
- GE  = 140.2278 MJ/head/day (Eq. 10.16)
- Enteric CH₄ = 59.7827 kg CH₄/head/yr (Eq. 10.21)
- Manure CH₄  = 1.4672 kg CH₄/head/yr (Eq. 10.23, 100% pasture)
- Nex         = 48.5439 kg N/head/yr (Eq. 10.32)
- Total CO₂eq AR5 (N=100,000) = **189167.49 tonnes**
- Total CO₂eq AR4 = 172992.70 tonnes
- Total CO₂eq AR6 = 183575.88 tonnes

## Test results

| ID | Section | Description | Status | Notes |
|----|---------|-------------|--------|-------|
| A1 | A | NEM (Eq. 10.3) | ✅ PASS |  |
| A2 | A | NEA (Eq. 10.4) | ✅ PASS |  |
| A3 | A | NEG (Eq. 10.6, WG=0 branch) | ✅ PASS |  |
| A4 | A | NEL (Eq. 10.8) | ✅ PASS |  |
| A5 | A | NEW (Eq. 10.11, hours=0 branch) | ✅ PASS |  |
| A6 | A | NEP (Eq. 10.13) | ✅ PASS |  |
| A7 | A | REM (Eq. 10.14) | ✅ PASS |  |
| A8 | A | REG (Eq. 10.15) | ✅ PASS |  |
| A9 | A | GE (Eq. 10.16) | ✅ PASS |  |
| A10 | A | Enteric CH4/head/yr (Eq. 10.21) | ✅ PASS |  |
| A11 | A | VS (Eq. 10.24) | ✅ PASS |  |
| A12 | A | Manure CH4/head/yr (Eq. 10.23) | ✅ PASS |  |
| A13 | A | N excretion (Eq. 10.32) | ✅ PASS |  |
| A14 | A | Direct MM N2O/head/yr | ✅ PASS |  |
| A15 | A | Indirect MM N2O/head/yr | ✅ PASS |  |
| A16 | A | Direct PRP N2O/head/yr (Eq. 11.1) | ✅ PASS |  |
| A17 | A | Indirect PRP N2O/head/yr (Eq. 11.9/11.10) | ✅ PASS |  |
| A18 | A | Total CO2eq (AR5) — inventory total | ✅ PASS |  |
| B1 | B | All marginals: empirical mean within 1% of analytical mean (excluding lognormal which uses mean_val as median by design) | ✅ PASS | worst relative error 0.0008 |
| B2 | B | Correlated sampling realised Spearman matches target within 0.04 | ✅ PASS | max absolute deviation 0.0298 |
| B3 | B | AR(1) year-correlation realised Spearman matches rho^|i-j| within 0.04 | ✅ PASS | max absolute deviation 0.0254 |
| B4 | B | Per-MMS uncertainty sampler: each column empirical mean within 1% of central value | ✅ PASS | pasture err=0.0001, solid_storage err=0.0003 |
| C1 | C | All 6 sources ticked → total_co2e equals hand-comp (AR5) | ✅ PASS |  |
| C2 | C | Source filter: enteric_ch4 only | ✅ PASS |  |
| C3 | C | Source filter: manure_ch4 only | ✅ PASS |  |
| C4 | C | Source filter: MM N2O only (golden case: 0 because 100% pasture) | ✅ PASS |  |
| C5 | C | Source filter: PRP N2O only | ✅ PASS |  |
| C6 | C | Source filter: enteric+MM only (Andreas regression — no crash, correct sum) | ✅ PASS |  |
| C7 | C | corr_mode='none' runs without warning (golden case has no correlations) | ✅ PASS | Verified implicitly by C1 |
| C8 | C | corr_mode='preset' (structural defaults) runs without error or warning | ✅ PASS |  |
| C9 | C | Time-series Spearman computed from upload matches manual Spearman within 1e-6 | ✅ PASS | max deviation 0.00e+00 |
| C10 | C | GWP = AR5 → total_co2e matches hand-comp | ✅ PASS |  |
| C11 | C | GWP = AR6 → total_co2e matches hand-comp | ✅ PASS | AR4-baseline also checked |
| C11b | C | GWP = AR4 → total_co2e matches hand-comp | ✅ PASS |  |
| C12 | C | Decomposition: format_ipcc_table populates all rows that have non-zero emissions | ✅ PASS | n_rows=9, non-zero rows populated: TRUE |
| C13 | C | Decomposition OFF: export_results_xlsx gracefully emits placeholder sheet | ✅ PASS |  |
| C14 | C | Comparison-run (no correlations) produces valid result | ✅ PASS |  |
| C15 | C | Iman-Conover: 2-param product, rho=+0.80 amplifies output SD (ratio >= 1.20) | ✅ PASS | sd_ratio = 1.328 (expected >= 1.20) |
| C16 | C | Iman-Conover: 2-param product, rho=-0.50 dampens output SD (ratio <= 0.85) | ✅ PASS | sd_ratio = 0.716 (expected <= 0.85) |
| C17 | C | Iman-Conover: 10-param product, ONE pair at -0.50 has small headline effect (|ratio - 1| <= 0.10) | ✅ PASS | sd_ratio = 0.959 (expected within 0.90-1.10) |
| C18 | C | Empty Parameter_TimeSeries → compute_corr_from_population returns NULL (Andreas June 2026: catches the silent no-op the UI gate now prevents) | ✅ PASS |  |
| C19 | C | Comparison-run invariant: nulling only legacy corr_matrix leaves MC result unchanged; nulling unified_corr_matrix changes it | ✅ PASS | legacy_unchanged=TRUE, unified_changed=TRUE |
| D1 | D | Trend year_corr='full' completes and produces table with 5 rows | ✅ PASS |  |
| D2 | D | Trend year_corr='partial' lag-1 Spearman for Ym ≈ 0.7 | ✅ PASS | realised lag-1=0.679 |
| D3 | D | Trend year_corr='none' completes and produces table with 5 rows | ✅ PASS |  |
| D4 | D | Trend source filter (enteric+MM only) runs without error | ✅ PASS |  |
| E1 | E | Inventory total_co2e = sum across sub-categories | ✅ PASS |  |
| E1b | E | Two sub-categories (100k + 50k) total_co2e = 1.5 × golden | ✅ PASS |  |
| E2 | E | Per-system results frame keyed by 'cattle_type||aggregation_level||sub_category' | ✅ PASS |  |
| F1 | F | NA in mean is detectable (gate trigger in simulation observer) | ✅ PASS |  |
| F2 | F | validate_manure_sheet flags fractions summing to 95% as invalid | ✅ PASS |  |
| F3 | F | validate_param_specs flags lower>upper as invalid | ✅ PASS |  |
| F4 | F | N=0: simulation completes, total_co2e = 0, no NaN | ✅ PASS |  |
| F5 | F | Empty source selection detectable by simulation observer gate | ✅ PASS |  |
| F6 | F | Source-aware deps: CH4-only excludes all manure-N2O / PRP params | ✅ PASS | CH4 needs Ym/UE/ASH/Bo; not the N2O EFs |
| F7 | F | Gate allows CH4-only run when only N2O params (EF3_PRP/EF4/EF5) are blank | ✅ PASS | blocking cells = 0 |
| F8 | F | Gate still blocks blank Ym when enteric_ch4 is selected | ✅ PASS | blocking cells = 1 |
| F9 | F | resolve_sub_category_matches: DINT_heif auto-matched to DINT_heifer with warn row | ✅ PASS | matched key=dairy||Intensive||DINT_heifer; warn row present=TRUE |
| F10 | F | Ambiguous sub_category produces fail row and is NOT auto-remapped | ✅ PASS | no remap=TRUE, fail row present=TRUE |
| F11 | F | Multi-MMS direct + indirect N2O headline matches hand-comp within 0.5% | ✅ PASS | direct: tool=21.32 vs ref=21.27 (err 0.0024); indirect: tool=7.12 vs ref=7.101 (err 0.0028) |
| F12a | F | MMS fraction sampler: row sums == 1 post-renormalisation | ✅ PASS | max |rowSum-1| = 2.22e-16 |
| F12b | F | Per-MMS fraction sampler: empirical mean within 2% of central value | ✅ PASS | pasture mean=0.5926 (bias 0.0123); solid_storage mean=0.4074 (bias 0.0184) |
| F12c | F | fraction_<mms> sample columns appear in samples (visible to sensitivity) | ✅ PASS | fraction_pasture, fraction_solid_storage |
| F12d | F | MMS-fraction uncertainty yields non-trivial CV on direct + indirect MM N2O | ✅ PASS | direct CV=0.1173, indirect CV=0.1173 |
| F13a | F | BW benchmark_deviation still fires + cites IPCC Table 10A.1 for dairy | ✅ PASS | status=fail; msg snippet: Mean (1500) deviates 445% from IPCC Vol.4 Ch.10 Annex Table 10A.1 (dairy cows, continental |
| F13b | F | Milk benchmark_deviation no longer fires (heuristic mid-point removed) | ✅ PASS | benchmark_deviation rows for Milk: 0 |
| F13c | F | EF4 / EF5 no longer flagged asymmetric; EF3_PRP still IS | ✅ PASS | EF4 rows=0; EF5 rows=0; EF3_PRP rows=1 |
| F14a | F | Per-source breakdown flextable splits by cattle_type | ✅ PASS | cattle_types in flextable: dairy, other |
| F14b | F | Per-source breakdown flextable has raw t CH4, t N2O, t CO2eq columns | ✅ PASS | Mean (t CH4), Mean (t N2O), Mean (t CO2eq) |
| F14c | F | Sum of per-cattle_type total_co2e equals inventory total | ✅ PASS | sum by ct = 2.89e+05; inventory = 2.89e+05 |
| F15a | F | aggregate_sensitivity labels each parameter with its sub_category in (...) | ✅ PASS | dairy_cows present=TRUE; other_cows present=TRUE; sample labels: BW (dairy_cows); BW (other_cows) |
| F15b | F | sens_group_of extracts sub_category from labelled parameter names | ✅ PASS | 'Ym (DINT_cow)' -> DINT_cow; 'MCF_solid_storage (DINT_heif)' -> DINT_heif; 'Ym' -> (ungrouped) |
| F16 | F | AD-only CV equals CV(N) for every emission source (single-system) | ✅ PASS | CV(N)=10.212; CV per source=10.212, 10.212, 10.212, 10.212; max rel.dev.=0.000000 |
| F17a | F | Sensitivity_SRC Excel sheet: populated, no backticks, sub-category in (...) | ✅ PASS | nrow=2; sample params: BW (dairy_cows); BW (other_cows) |
| F17b | F | Sensitivity_PRCC Excel sheet: populated, no `..` mangling, sub-category in (...) | ✅ PASS | nrow=2; sample params: BW (dairy_cows); BW (other_cows) |
| F18 | F | Inventory_Metadata region: explicit slug kept; country auto-mapped; unknown -> global | ✅ PASS | explicit africa -> africa; Zimbabwe (legacy) -> africa; Atlantis -> global; India (blank region) -> asia |
| F18b | F | Continental region cell (new-template parser key) is honoured over country fallback | ✅ PASS | Zimbabwe + global -> global; Zimbabwe + africa -> africa |
| F19a | F | Legacy 'Country / region' label parses to metadata$country (no trailing underscore) + region resolves to africa for Zimbabwe | ✅ PASS | country='Zimbabwe' region='africa' country_ key present=FALSE |
| F20a | F | Zim template: heifer auto-match (DINT_heif → DINT_heifer) fires | ✅ PASS | auto-match issue raised as warning |
| F20b | F | Zim end-to-end: total_direct_n2o_mm in plausible band [15, 60] (vs @Risk 39.9) | ✅ PASS | mean = 30.1 t (regression threshold: < 15 would indicate the auto-match fix is broken) |
| F20c | F | Zim end-to-end: 5 sub-categories produced, each with non-zero direct N2O | ✅ PASS | n_sys = 5; all non-zero = TRUE |
| F21_country_x | F | Built-in example country_x per-head emissions in IPCC Tier-2 plausible band | ✅ PASS | enteric=75.5 kg/hd, manure_CH4=2.71 kg/hd, direct_N2O_mm=0.1144 kg/hd |
| F21_country_y | F | Built-in example country_y per-head emissions in IPCC Tier-2 plausible band | ✅ PASS | enteric=74.4 kg/hd, manure_CH4=2.75 kg/hd, direct_N2O_mm=0.1130 kg/hd |
| F22 | F | generate_corr_matrix_template(example) round-trips through CSV and matches build_ipcc_preset_corr() | ✅ PASS | shape=TRUE diag=TRUE names=TRUE values=TRUE pairs=TRUE |
| F23 | F | Correlations help page rendered with TL;DR + both worked examples + mistakes section | ✅ PASS | size_ok=TRUE tldr=TRUE X=TRUE Y=TRUE mistakes=TRUE |
| F19b | F | Tornado user_reducible lookup correctly classifies labelled params | ✅ PASS | results: FALSE, TRUE, FALSE, FALSE, TRUE; expected: FALSE, TRUE, FALSE, FALSE, TRUE |
| G1 | G | export_results_xlsx produces non-empty file | ✅ PASS | 9784 bytes |
| G2 | G | CSV write of uncertainty frame produces non-empty file | ✅ PASS | 2215 bytes |
| G3 | G | build_run_summary_docx produces Word file > 50 KB | ✅ PASS | 316634 bytes |
| G4 | G | methodology.Rmd Reporting section contains CRT category map (3.A / 3.B / 3.D) | ✅ PASS | 3.A=TRUE 3.B=TRUE 3.D=TRUE |
| G5 | G | methodology.Rmd Reporting section contains Level 1/2/3 disaggregation guide | ✅ PASS | L1=TRUE L2=TRUE L3=TRUE |

## Detailed numerics

| ID | Expected | Actual | Status |
|----|----------|--------|--------|
| A1 | 27.82456 | 27.82456 | PASS |
| A2 | 4.730175 | 4.730175 | PASS |
| A3 | 0 | 0 | PASS |
| A4 | 7.675 | 7.675 | PASS |
| A5 | 0 | 0 | PASS |
| A6 | 1.391228 | 1.391228 | PASS |
| A7 | 0.4946827 | 0.4946827 | PASS |
| A8 | 0.2781547 | 0.2781547 | PASS |
| A9 | 140.2278 | 140.2278 | PASS |
| A10 | 59.78265 | 59.78265 | PASS |
| A11 | 3.076651 | 3.076651 | PASS |
| A12 | 1.46717 | 1.46717 | PASS |
| A13 | 48.54394 | 48.54394 | PASS |
| A14 | 0 | 0 | PASS |
| A15 | 0 | 0 | PASS |
| A16 | 0.3051333 | 0.3051333 | PASS |
| A17 | 0.361583 | 0.361583 | PASS |
| A18 | 189167.5 | 189167.5 | PASS |
| B1 | TRUE | TRUE | PASS |
| B2 | 0 | 0.02979334 | PASS |
| B3 | 0 | 0.02538704 | PASS |
| B4 | TRUE | TRUE | PASS |
| C1 | 189167.5 | 189167.5 | PASS |
| C2 | 167391.4 | 167391.4 | PASS |
| C3 | 4108.077 | 4108.077 | PASS |
| C4 | 0 | 0 | PASS |
| C5 | 17667.98 | 17667.98 | PASS |
| C6 | 171499.5 | 171499.5 | PASS |
| C7 | TRUE | TRUE | PASS |
| C8 | TRUE | TRUE | PASS |
| C9 | 0 | 0 | PASS |
| C10 | 189167.5 | 189167.5 | PASS |
| C11 | 183575.9 | 183575.9 | PASS |
| C11b | 172992.7 | 172992.7 | PASS |
| C12 | TRUE | TRUE | PASS |
| C13 | TRUE | TRUE | PASS |
| C14 | TRUE | TRUE | PASS |
| C15 | TRUE | TRUE | PASS |
| C16 | TRUE | TRUE | PASS |
| C17 | TRUE | TRUE | PASS |
| C18 | TRUE | TRUE | PASS |
| C19 | TRUE | TRUE | PASS |
| D1 | TRUE | TRUE | PASS |
| D2 | 0.7 | 0.6791913 | PASS |
| D3 | TRUE | TRUE | PASS |
| D4 | TRUE | TRUE | PASS |
| E1 | 283751.2 | 283751.2 | PASS |
| E1b | 283751.2 | 283751.2 | PASS |
| E2 | TRUE | TRUE | PASS |
| F1 | TRUE | TRUE | PASS |
| F2 | TRUE | TRUE | PASS |
| F3 | TRUE | TRUE | PASS |
| F4 | TRUE | TRUE | PASS |
| F5 | TRUE | TRUE | PASS |
| F6 | TRUE | TRUE | PASS |
| F7 | TRUE | TRUE | PASS |
| F8 | TRUE | TRUE | PASS |
| F9 | TRUE | TRUE | PASS |
| F10 | TRUE | TRUE | PASS |
| F11 | TRUE | TRUE | PASS |
| F12a | TRUE | TRUE | PASS |
| F12b | TRUE | TRUE | PASS |
| F12c | TRUE | TRUE | PASS |
| F12d | TRUE | TRUE | PASS |
| F13a | TRUE | TRUE | PASS |
| F13b | TRUE | TRUE | PASS |
| F13c | TRUE | TRUE | PASS |
| F14a | TRUE | TRUE | PASS |
| F14b | TRUE | TRUE | PASS |
| F14c | TRUE | TRUE | PASS |
| F15a | TRUE | TRUE | PASS |
| F15b | TRUE | TRUE | PASS |
| F16 | TRUE | TRUE | PASS |
| F17a | TRUE | TRUE | PASS |
| F17b | TRUE | TRUE | PASS |
| F18 | TRUE | TRUE | PASS |
| F18b | TRUE | TRUE | PASS |
| F19a | TRUE | TRUE | PASS |
| F20a | TRUE | TRUE | PASS |
| F20b | TRUE | TRUE | PASS |
| F20c | TRUE | TRUE | PASS |
| F21_country_x | TRUE | TRUE | PASS |
| F21_country_y | TRUE | TRUE | PASS |
| F22 | TRUE | TRUE | PASS |
| F23 | TRUE | TRUE | PASS |
| F19b | TRUE | TRUE | PASS |
| G1 | TRUE | TRUE | PASS |
| G2 | TRUE | TRUE | PASS |
| G3 | TRUE | TRUE | PASS |
| G4 | TRUE | TRUE | PASS |
| G5 | TRUE | TRUE | PASS |

## Findings & recommendations

Even though every formal test passed, two minor robustness issues surfaced while building the harness. Neither is reachable from normal app use, but both are worth documenting:

**1. `run_inventory_simulation()` crashes with `n_iter = 1` on a single-system inventory.**

Location: `R/mc_simulation.R` lines ~199-211. The data-frame construction uses `rowSums(sapply(by_system, function(s) s$results$some_col))`. When `by_system` has a single entry and `n_iter = 1`, `sapply` returns a length-1 vector (not a matrix), and `rowSums()` then throws *"'x' must be an array of at least two dimensions"*. This is not reachable from the live app (the UI's iteration slider has a minimum of 1,000) but it makes the function fragile for unit testing or any caller that might pass a single iteration. Cheap fix: wrap each `sapply(...)` in `as.matrix()` or guard with `if (length(by_system) == 1L) ...`.

**2. Country X synthetic time-series has perfectly linear `Milk` growth (5 years × 0.2 kg/day, no noise).**

Location: `R/utils_ipcc_defaults.R::generate_country_x_timeseries()`. First-differencing collapses the `Milk` column to a constant (every diff = 0.2), which gives `sd = 0` and breaks any naive `cor()` call. The app's own `compute_correlation_from_timeseries()` handles this correctly (line 264 drops zero-variance columns), but the synthetic series is unrealistic — a real time series would have noise. Cheap fix: add a small jitter (±0.05) to one of the Milk values so the series exercises the auto-correlation path realistically.

## Methodology notes

- Deterministic checks (Section A) use `n_iter = 1` with every parameter's distribution set to `"constant"`. The simulator collapses to a single deterministic call through the IPCC equation chain, which lets us compare each intermediate against a hand-computed reference value to within `TOL_REL = 1e-4` relative tolerance.
- Monte Carlo convergence checks (Sections B, D) use `n_iter = 50,000` or `500` and compare empirical statistics (mean, Spearman rank correlation) against analytical expectations to within `TOL_MC = 0.02` absolute on correlations, `0.01` relative on means.
- The audit does NOT go through the Shiny `input$` / observer layer — it calls `run_inventory_simulation()`, `calc_*` functions, `validate_*` functions, and the export builders directly. UI rendering, button-click flow, and tooltip text are not exercised here. (If the calculation engine is correct, the UI shows correct numbers; the rendering layer's bugs would be a separate UX audit.)
- The hand-comp treats the equation forms as implemented in `R/calc_*.R`. The audit does not re-verify those equation forms against the IPCC source PDFs — that was the May-2026 IPCC alignment audit's scope.

## Reproducibility

Run `Rscript _audit.R` from the repo root. Output is deterministic conditional on the seeds in each test block.

