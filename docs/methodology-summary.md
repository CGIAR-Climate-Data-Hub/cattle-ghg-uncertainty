# Methodology summary: Cattle GHG Uncertainty Calculator

Condensed from the full methodology document (https://cgiar-climate-data-hub.github.io/cattle-ghg-uncertainty/assets/methodology.pdf). The tool implements IPCC Approach 2 (Monte Carlo) uncertainty analysis over the IPCC 2006 Tier 2 cattle equation chain.

## Emission model

For each cattle sub-category (defined by cattle type, production system and animal class), the tool computes, per IPCC 2006 Vol. 4 Ch. 10 and 11:

1. Net energy requirements: maintenance (Eq 10.3, body weight to the power 0.75, with cold-climate adjustment Eq 10.2), activity (10.4), growth (10.6), lactation (10.8), work (10.11), pregnancy (10.13).
2. Gross energy intake GE (Eq 10.16) via the REM/REG ratios (10.14, 10.15), which are polynomial functions of digestible energy (DE, clamped to its biologically valid 45-85% domain).
3. Enteric fermentation CH4 (Eq 10.21) from GE and the methane conversion factor Ym.
4. Volatile solids (Eq 10.24) and manure management CH4 (Eq 10.23) via Bo and climate-zone MCF per manure system.
5. Nitrogen excretion (Eqs 10.32-10.33), then direct and indirect N2O from managed manure (10.25, 10.26, 10.28) and from pasture deposition (Ch. 11 Eqs 11.1, 11.9, 11.10).
6. CO2-equivalent totals under AR4, AR5 (default) or AR6 GWP values (biogenic CH4 = 27.0 under AR6).

## Uncertainty propagation

- Each parameter carries a probability distribution (normal, positive-normal, lognormal, beta, triangular, PERT, uniform, constant); entered bounds are interpreted as the 95% interval. Lognormal central values are treated as medians per IPCC good-practice guidance.
- Sampling is by rank-correlation-preserving restricted pairing (Iman-Conover) per IPCC Vol. 1 Ch. 3 section 3.2.3.2, preserving each marginal distribution exactly while hitting a target Spearman correlation matrix.
- Correlation options: none (default), an expert-elicited structural-defaults preset of seven documented parameter pairs (e.g. digestible energy with Ym), a matrix estimated from an uploaded historical time series (Spearman, detrended, projected to the nearest positive-definite matrix), or a user matrix.
- Headline metric: the 95% margin of error, MoE% = (Q97.5 - Q2.5) / (2 x mean) x 100, the IPCC Table 3.3 "% uncertainty" convention, with asymmetric upper/lower half-widths also computed.
- Decomposition: three simulation runs (all parameters varying; emission factors fixed; activity data fixed) give combined, AD-only and EF-only uncertainty per source.
- Sensitivity: SRC (standardised linear regression) and PRCC (partial rank correlation) rankings of inputs against total CO2eq.
- Trend mode: per IPCC Vol. 1 Ch. 3 section 3.2.2.4, emission-factor draws can be reused across years (full correlation), AR(1)-correlated, or independent; slope and first-to-last-year delta are reported with empirical 95% intervals.
- Convergence diagnostics: Monte Carlo standard error, half-sample drift, CI drift, skewness, with pass/warn thresholds; recommended 10,000 iterations minimum, 25,000-30,000 for final reporting.

## Verification

The equation chain is verified against a hand-computed golden case and an automated regression suite (120 checks at last run) covering the equations, the sampler's correlation targets, application routes, validators and exports. Default values carry inline IPCC table/equation provenance and were audited against the 2006 Guidelines and 2019 Refinement source text.
