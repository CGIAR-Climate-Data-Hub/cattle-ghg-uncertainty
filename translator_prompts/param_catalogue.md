# Parameter catalogue

Single source of truth for the 27 IPCC-aligned parameters the cattle uncertainty app expects.
When you (Claude) translate a user's raw column to a template field, use this table.
All parameter codes are case-sensitive.

| code | tier | type | unit | IPCC default | suggested ±% | distribution | IPCC ref | aliases accepted | definition |
|------|------|------|------|--------------|--------------|--------------|----------|------------------|------------|
| `N` | core | activity_data | head |  | 10% | normal | — | cattle_pop | Number of animals in this sub-category |
| `BW` | core | coefficient | kg | 275 | 15% | normal | Table 10A.2 | W, live_weight | Average live body weight of the animals |
| `MW` | core | coefficient | kg | 300 | 10% | normal | Table 10A.2 | mature_weight | Mature (adult) body weight of the animals |
| `WG` | core | coefficient | kg/day | 0 | 30% | pert | Table 10A.1 | weight_gain | Average daily weight gain — set 0 for non-growing (adult) animals |
| `Milk` | core | coefficient | kg/head/day | 3.5 | 20% | normal | — | milk_yield | Daily milk yield per lactating cow (not sub-category-average — the tool multiplies by pct_pregnant internally). Set 0 for sub-categories that do not lactate. |
| `Fat` | core | coefficient | % | 4.3 | 10% | normal | — | milk_fat | Fat content of milk (% by weight) |
| `pct_pregnant` | core | coefficient | fraction (0-1) | 0.6 | 20% | beta | — | pct_lactating, pct_calving | Fraction of females in this sub-category that are pregnant during the year, between 0 and 1 — includes pregnant heifers that have not yet calved. Weights Cpregnancy in IPCC Eq 10.13 (NEp) and the milk-N retention term in Eq 10.33; the tool also applies it as the lactation-weight in Eq 10.8 (NEl). For sub-categories where lactation and pregnancy populations differ, enter the pregnancy fraction. |
| `DE` | core | coefficient | % | 55 | 15% | normal | Eq 10.14--16 | DE_pct | Digestible energy as a percentage of gross energy — typical range 45-75% |
| `Cfi` | advanced | coefficient | MJ/day/kg^0.75 | 0.386 | 30% | pert | Table 10.4 | (none) | Maintenance energy coefficient — depends on sex and lactation status (IPCC Table 10.4) |
| `Ca` | advanced | coefficient | dimensionless | 0.17 | 30% | triangular | Table 10.5 | (none) | Activity coefficient for locomotion energy — depends on feeding situation (IPCC Table 10.5) |
| `C` | advanced | coefficient | dimensionless | 0.8 | 30% | triangular | Eq 10.6 | C_growth | Growth coefficient for the NEg equation — depends on sex and physiological status (IPCC Eq 10.6) |
| `Cp` | advanced | coefficient | dimensionless | 0.1 | 10% | beta | Table 10.7 | (none) | Pregnancy coefficient — 0.10 for pregnant animals (IPCC Table 10.7) |
| `hours` | core | coefficient | hours/day | 0 | 20% | pert | Eq 10.11 | (none) | Daily working hours (Eq. 10.11) — set 0 if animals do no work; relevant only where animals are used for traction/load |
| `CP` | core | coefficient | % | 10 | 15% | normal | Eq 10.32 | CP_pct | Crude protein (CP%) content of the diet — used to estimate nitrogen excretion |
| `Ym` | advanced | coefficient | % | 6.5 | 8% | pert | Table 10.12 | Ym_pct | Methane conversion factor: % of gross energy in feed converted to methane (IPCC Table 10.12) |
| `Bo` | advanced | coefficient | m3 CH₄/kg VS | 0.13 | 20% | pert | Table 10.16 | (none) | Maximum CH₄ producing capacity of manure (IPCC Table 10.16) |
| `ASH` | advanced | coefficient | fraction | 0.08 | 25% | pert | Eq 10.24 | ash | Ash content of manure — IPCC default 0.08 (Eq 10.24 footnote) |
| `UE` | advanced | coefficient | fraction | 0.04 | 25% | pert | Eq 10.24 | (none) | Urinary energy as fraction of gross energy — IPCC default 0.04 (Eq 10.24 footnote) |
| `EF3_PRP` | advanced | coefficient | kg N2O-N/kg N | 0.004 | (asymmetric — use bounds) | pert | Ch.11 Table 11.1 | (none) | N₂O emission factor for dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.1). 2019R EF3_PRP,CPP for cattle/poultry/pigs: aggregated 0.004; wet climate 0.006; dry climate 0.002. 2006 = 0.02. |
| `EF4` | advanced | coefficient | kg N2O-N/kg N | 0.01 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for atmospheric N deposition (IPCC Vol.4 Ch.11 Table 11.3). 2019R aggregated EF4 = 0.010 (range 0.002-0.018); wet climate 0.014; dry climate 0.005. 2006 = 0.010. |
| `EF5` | advanced | coefficient | kg N2O-N/kg N | 0.011 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for N leaching/runoff (IPCC Vol.4 Ch.11 Table 11.3). 2019R EF5 = 0.011 (range 0.000-0.020), no climate disaggregation. 2006 = 0.0075. |
| `Frac_GASM_PRP` | advanced | coefficient | fraction | 0.21 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_GasPRP | Fraction of N volatilised from dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.3, FracGASM). 2019R = 0.21 (range 0.00-0.31); 2006 = 0.20. |
| `Frac_LEACH_PRP` | advanced | coefficient | fraction | 0.24 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_LeachPRP | Fraction of N leached from pasture deposition (IPCC Vol.4 Ch.11 Table 11.3, FracLEACH-(H), wet climates only). 2019R = 0.24 (range 0.01-0.73); 2006 = 0.30; in dry climates = 0. |
| `MilkPR` | core | coefficient | % | 3.3 | 10% | normal | Eq 10.33 | protein_milk | Protein content of milk — feeds the milk-N term in IPCC Vol.4 Ch.10 Eq 10.33 (N retention for cattle, where the 6.38 milk-protein-to-N conversion is defined) |
| `Tw` | advanced | coefficient | °C | 20 | 25% | normal | Eq 10.2 | (none) | Mean daily temperature in winter (°C) — Cfi cold-climate adjustment per IPCC Vol.4 Ch.10 Eq 10.2 (modifies the Cfi from Eq 10.3). Leave blank or set 20 to disable adjustment |

## Asymmetric (non-symmetric) bounds

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

| code | lower | central | upper |
|------|-------|---------|-------|
| `EF3_PRP` | 0.007 | 0.004 | 0.06 |
| `EF4` | 0.002 | 0.01 | 0.02 |
| `EF5` | 0.0005 | 0.011 | 0.025 |
| `Frac_GASM_PRP` | 0.05 | 0.21 | 0.5 |
| `Frac_LEACH_PRP` | 0.05 | 0.24 | 0.8 |

## Tier meaning

- **core** = user must provide a value (or accept the IPCC default). These are the activity-data parameters and a handful of high-impact coefficients (DE, CP, MilkPR).
- **advanced** = IPCC equation coefficient. Pre-filled with the IPCC default from the column above; only override if the user has a country-specific measurement.

## param_type

- **activity_data** = `N` only (animal population). This is the one true activity-data variable.
- **coefficient** = everything else (production parameters, energy/methane/N₂O coefficients).

## Distribution codes accepted

`normal`, `posnorm`, `lognormal`, `beta`, `triangular`, `pert`, `uniform`, `constant`, `tnorm_0_1`

Use `pert` or `triangular` when only a mode + bounds are known; `normal` for symmetric ±% around a measured mean; `beta` or `tnorm_0_1` for fractions that must stay in [0, 1]; `lognormal` for strictly-positive values with right skew (typical for emission factors).
