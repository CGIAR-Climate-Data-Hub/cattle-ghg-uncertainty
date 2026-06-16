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
| `pct_pregnant` | core | coefficient | fraction (0-1) | 0.6 | 20% | beta | — | (none) | Fraction of females in this sub-category that are pregnant during the year, between 0 and 1 — includes pregnant heifers that have not yet calved. Weights Cpregnancy in IPCC Eq 10.13 (NEp) and the milk-N retention term in Eq 10.33; the tool also applies it as the lactation-weight in Eq 10.8 (NEl). For sub-categories where lactation and pregnancy populations differ, enter the pregnancy fraction. Do NOT auto-map a source column labelled `pct_lactating` or `pct_calving` to this field — they are NOT synonyms (a herd can have non-pregnant lactating cows, and calving rate ≠ pregnancy rate at any given moment). If the source file gives only lactating or only calving rate, flag it in section D and confirm the conversion with the user. |
| `DE` | core | coefficient | % | 55 | 15% | normal | Eq 10.14--16 | DE_pct | Digestible energy as a percentage of gross energy — typical range 45-75% |
| `Cfi` | advanced | coefficient | MJ/day/kg^0.75 | 0.386 | 30% | pert | Table 10.4 | (none) | Maintenance energy coefficient — depends on sex and lactation status (IPCC Table 10.4) |
| `Ca` | advanced | coefficient | dimensionless | 0.17 | 30% | triangular | Table 10.5 | (none) | Activity coefficient for locomotion energy — depends on feeding situation (IPCC Table 10.5) |
| `C` | advanced | coefficient | dimensionless | 0.8 | 30% | triangular | Eq 10.6 | C_growth | Growth coefficient for the NEg equation — depends on sex and physiological status (IPCC Eq 10.6) |
| `Cp` | advanced | coefficient | dimensionless | 0.1 | 10% | beta | Table 10.7 | (none) | Pregnancy coefficient — 0.10 for pregnant animals (IPCC Table 10.7) |
| `hours` | core | coefficient | hours/day | 0 | 20% | pert | Eq 10.11 | (none) | Daily working hours (Eq. 10.11) — set 0 if animals do no work; relevant only where animals are used for traction/load |
| `CP` | core | coefficient | % | 10 | 15% | normal | Eq 10.32 | CP_pct | Crude protein (CP%) content of the diet — used to estimate nitrogen excretion |
| `Ym` | advanced | coefficient | % | 6.5 | 20% | pert | Table 10.12 | Ym_pct | Methane conversion factor: % of gross energy in feed converted to methane (IPCC Vol.4 Ch.10 Table 10.12). Default uncertainty 20% per Penman et al. (2000) and IPCC 2019R Vol.1 Ch.3 Tier 2 guidance — Ym is one of the most uncertain parameters in cattle CH₄ inventories and a tight ±% misstates that. Sub-category values vary: dairy cows ≈ 5.7–6.5%, other cattle 6.3–7.0%, feedlot 4.0–5.0%, pre-weaned calves effectively 0%. |
| `Bo` | advanced | coefficient | m3 CH₄/kg VS | 0.13 | 20% | pert | Table 10.16a | (none) | Maximum CH₄ producing capacity of manure (IPCC Vol.4 Ch.10 Table 10.16a, 2019R). For **Other regions, low productivity** (the Sub-Saharan Africa / South Asia default that most users of this tool fall under) BOTH dairy and non-dairy cattle = **0.13**. The 0.24 value applies ONLY to dairy cattle in North America / Western Europe (high-productivity systems); non-dairy cattle there range 0.17–0.19. Buffalo = 0.10 (do not use buffalo's value for cattle). For a high-productivity commercial dairy herd the compiler may override dairy_cows to 0.24. |
| `ASH` | advanced | coefficient | fraction | 0.08 | 25% | pert | Eq 10.24 | ash | Ash content of manure — IPCC default 0.08 (Eq 10.24 footnote) |
| `UE` | advanced | coefficient | fraction | 0.04 | 25% | pert | Eq 10.24 | (none) | Urinary energy as fraction of gross energy — IPCC default 0.04 (Eq 10.24 footnote) |
| `EF3_PRP` | advanced | coefficient | kg N2O-N/kg N | 0.006 | (asymmetric — use bounds) | pert | Ch.11 Table 11.1 | (none) | N₂O emission factor for dung/urine on pasture, EF3PRP,CPP (IPCC Vol.4 Ch.11 Table 11.1, 2019R, **wet climate**: 0.006, range **0.000–0.027**). For dry climate use 0.002 (range 0.000–0.007). For aggregated-across-climates use 0.004 (range 0.000–0.014). 2006 = 0.02. The wide wet-climate range is genuine — EF3PRP is one of the most uncertain N₂O parameters and a dominant driver of pasture-N₂O uncertainty. |
| `EF4` | advanced | coefficient | kg N2O-N/kg N | 0.014 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for atmospheric N deposition (IPCC Vol.4 Ch.11 Table 11.3, 2019R, **wet climate**: 0.014, range 0.011-0.017). For dry climate use 0.005. For aggregated use 0.010 (range 0.002-0.018). 2006 = 0.010. |
| `EF5` | advanced | coefficient | kg N2O-N/kg N | 0.011 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for N leaching/runoff (IPCC Vol.4 Ch.11 Table 11.3). 2019R EF5 = 0.011 (range 0.000-0.020), no climate disaggregation. 2006 = 0.0075. |
| `Frac_GASM_PRP` | advanced | coefficient | fraction | 0.21 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_GasPRP | Fraction of N volatilised from dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.3, FracGASM). 2019R = 0.21 (range 0.00-0.31); 2006 = 0.20. |
| `Frac_LEACH_PRP` | advanced | coefficient | fraction | 0.24 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_LeachPRP | Fraction of N leached from pasture deposition (IPCC Vol.4 Ch.11 Table 11.3, FracLEACH-(H), wet climates only). 2019R = 0.24 (range 0.01-0.73); 2006 = 0.30; in dry climates = 0. |
| `MilkPR` | core | coefficient | % | 3.3 | 10% | normal | Eq 10.33 | milk_protein, protein_milk | Protein content of milk — feeds the milk-N term in IPCC Vol.4 Ch.10 Eq 10.33 (N retention for cattle, where the 6.38 milk-protein-to-N conversion is defined) |
| `Tw` | advanced | coefficient | °C | 20 | 25% | normal | Eq 10.2 | (none) | Mean daily temperature in winter (°C) — Cfi cold-climate adjustment per IPCC Vol.4 Ch.10 Eq 10.2 (modifies the Cfi from Eq 10.3). Leave blank or set 20 to disable adjustment |

## Asymmetric (non-symmetric) bounds

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

Values below are the **IPCC 2019 Refinement Vol.4 Ch.11 Tables 11.1 (EF3_PRP) and 11.3 (EF4, EF5, Frac_GASM_PRP, Frac_LEACH_PRP)** for the **wet climate** classification, since most users of this tool (SSA, South/Southeast Asia, Latin America smallholder + commercial systems) operate in wet climates. Dry-climate values (lower EF3_PRP ≈ 0.002, Frac_LEACH_PRP ≈ 0) are documented in the description column above. For an arid-country inventory the user can edit these five bounds in the Parameters sheet before uploading.

Central values and ranges verified 2026-06-15 directly against the IPCC 2019 Refinement source text (Vol.4 Ch.11 Table 11.1 EF3PRP,CPP wet = 0.006, range 0.000–0.027; Table 11.3 EF4 wet = 0.014, range 0.011–0.017; EF5 = 0.011, range 0.000–0.020; FracGASM = 0.21, range 0.00–0.31; FracLEACH-(H) = 0.24, range 0.01–0.73).

Three lower bounds (`EF3_PRP`, `EF5`, `Frac_GASM_PRP`) are bumped from the strict-IPCC 0 to a small positive number (0.0005, 0.0005, 0.005) because PERT and lognormal distributions break or produce extreme samples when the lower bound is exactly 0. The bumped values are tiny enough that the IPCC sense is preserved.

| code | lower | central | upper |
|------|-------|---------|-------|
| `EF3_PRP` | 0.0005 | 0.006 | 0.027 |
| `EF4` | 0.011 | 0.014 | 0.017 |
| `EF5` | 0.0005 | 0.011 | 0.020 |
| `Frac_GASM_PRP` | 0.005 | 0.21 | 0.31 |
| `Frac_LEACH_PRP` | 0.01 | 0.24 | 0.73 |

## Sex- and physiology-specific coefficient overrides

The `ipcc_default` column above lists the **lactating-female** value because that's the most common case. For other sub-categories you MUST override these three coefficients (`Cfi`, `Ca`, `C`) according to IPCC Vol.4 Ch.10 Tables 10.4 / 10.5 / Eq 10.6. Do NOT use 0.8 for every C, do NOT use 0.386 for every Cfi.

| sub-category | Cfi (Table 10.4) | Ca (Table 10.5) | C (Eq 10.6) |
|---|---|---|---|
| `dairy_cows` (lactating) | 0.386 | 0.17 (grazing, hilly) / 0.17 (large area) / 0.36 (stall-fed) | n/a (adult, WG≈0) |
| `other_cows` (non-dairy, lactating) | 0.386 | as above | 0.8 |
| `other_cows` (non-dairy, non-lactating) | 0.322 | as above | 0.8 |
| `bulls` (intact adult male) | 0.370 | as above | **1.2** |
| `oxen` (castrate adult male) | 0.322 | 0.17 (light work) / 0.36 (moderate) / 0.50 (heavy) | **1.0** |
| `heifers` (replacement female) | 0.322 | as above | 0.8 |
| `growing_males` / `steers` (castrate, growing) | 0.322 | as above | **1.0** (NOTE: the controlled-vocab code `growing_males` is genuinely ambiguous — different countries use the term for both castrate steers (C=1.0) and intact pre-castration bulls (C=1.2). If a source file's "growing males" entry has C=1.2 in its Coefficients sheet, that means the inventory team treats them as intact — honor the file value with `data_source = user_file`. If the file is silent on C, default to 1.0 (castrate-steer assumption) and surface this in section D as a clarifying question.) |
| `calves_female` | 0.322 | as above | 1.0 (= pooled-calves IPCC default; only drop to 0.8 if the file genuinely sex-disaggregates post-weaning female-calf growth as heifer-track) |
| `calves_male` (uncastrated, pre-pubertal) | 0.322 | as above | 1.0 (= pooled-calves IPCC default; rises to 1.2 only on the intact-bull development path post-puberty, and DROPS to 1.0 / steer if castrated — castration LOWERS C, it does not raise it) |

**The C-coefficient (growth coefficient) is the one most commonly missed.** When applying a sub-category-specific value (`bulls` → 1.2, `oxen`/`growing_males` → 1.0), keep `data_source = "ipcc_default"` (the sex-specific value is itself an IPCC default) and call out the deliberate override in your end-of-run summary so the user can spot-check it in the QA tab.

For `Ca` specifically: pick the row based on the feeding situation the user describes — stall-fed (intensive) sits around 0.0–0.17, grazing on flat pasture around 0.17, grazing on hilly pasture around 0.36, working oxen up to 0.50. If the user doesn't specify, use 0.17 (grazing) for smallholder/extensive systems and 0.36 (stall-fed) for confined dairy systems.

## Tier meaning

- **core** = user must provide a value (or accept the IPCC default). These are the activity-data parameters and a handful of high-impact coefficients (DE, CP, MilkPR).
- **advanced** = IPCC equation coefficient. Pre-filled with the IPCC default from the column above; only override if the user has a country-specific measurement.

## param_type

- **activity_data** = `N` only (animal population). This is the one true activity-data variable.
- **coefficient** = everything else (production parameters, energy/methane/N₂O coefficients).

## Distribution codes accepted

`normal`, `posnorm`, `lognormal`, `beta`, `triangular`, `pert`, `uniform`, `constant`, `tnorm_0_1`

Use `pert` or `triangular` when only a mode + bounds are known; `normal` for symmetric ±% around a measured mean; `beta` or `tnorm_0_1` for fractions that must stay in [0, 1]; `lognormal` for strictly-positive values with right skew (typical for emission factors).
