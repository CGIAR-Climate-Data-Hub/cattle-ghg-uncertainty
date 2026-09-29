# Cattle GHG Uncertainty Calculator (IPCC Tier 2 Livestock GHG Uncertainty Calculator)

A free, open-source (MIT) web tool for national greenhouse-gas inventory teams to quantify and report uncertainty in IPCC Tier 2 cattle emission estimates. Live app: https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/ . Source: https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty . Website: https://cgiar-climate-data-hub.github.io/cattle-ghg-uncertainty/

Developed by the Alliance of Bioversity International and CIAT (CGIAR) under the CGIAR Climate Action Programme, funded by the Global Methane Hub (grant R-2026-01051).

## What it does

- Propagates parameter uncertainty through the full IPCC 2006 Vol. 4 Ch. 10/11 Tier 2 equation chain for cattle by Monte Carlo simulation (IPCC Approach 2, Vol. 1 Ch. 3).
- Emission sources: enteric fermentation CH4, manure management CH4, direct and indirect N2O from managed manure, direct and indirect N2O from pasture/range/paddock deposition.
- Reports the 95% margin of error (half-width of the 95% confidence interval as a percentage of the mean), the IPCC Table 3.3 convention, decomposed into activity-data, emission-factor and combined components.
- Correlated sampling (rank-correlation-preserving restricted pairing) with a documented structural-defaults preset, time-series-derived matrices, or manual matrices.
- Sensitivity analysis: standardised regression coefficients (SRC) and partial rank correlation coefficients (PRCC), with a tornado chart separating user-reducible parameters from fixed IPCC coefficients.
- Trend mode: multi-year Monte Carlo with year-to-year emission-factor correlation, trend slope and delta with their own confidence intervals.
- Outputs: IPCC Table 3.3 formatted Excel and CSV, and a complete Word report with all charts and the full input audit trail.
- Input: an Excel template with dropdowns, formulas and IPCC defaults pre-filled, or a built-in AI assistant that converts raw country files into the template.
- GWP sets: AR4, AR5 (default), AR6. Reproducible via a fixed random seed.

## Who it is for

National inventory compilers preparing Biennial Transparency Reports (BTRs), Biennial Update Reports (BURs) and National Inventory Reports (NIRs) under the UNFCCC Enhanced Transparency Framework who need IPCC Approach 2 (Monte Carlo) uncertainty estimates for livestock instead of Approach 1 error propagation. No coding, installation or account is required; two hypothetical example inventories are pre-loaded.

## Citation

Alliance of Bioversity International and CIAT (CGIAR) (2026). IPCC Tier 2 Livestock GHG Uncertainty Calculator (software). https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty
