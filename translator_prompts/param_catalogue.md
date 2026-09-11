# Parameter catalogue

## What these defaults assume

Every default in the table below is one cell of a much larger IPCC table. Reaching it means choosing a region, a productivity class, a climate and, for manure, a specific system variant. When the user's data shows that one of these choices does not describe their herd, say so in section D and use their value instead of the default.

| choice | this tool uses | IPCC also publishes | affects | why, and what to do otherwise |
|---|---|---|---|---|
| **Geography** | Africa | North America; Western Europe; Eastern Europe; Oceania; Latin America; Asia; Middle East; Indian subcontinent | `BW`, `MW`, `WG`, `Milk`, `Fat`, `MilkPR`, `pct_pregnant`, `DE`, `CP`, `hours` | The tool is built for developing-country inventory compilers. Country-specific values should replace these wherever they exist. |
| **Productivity class** | Low productivity | Regional aggregate (Milk 3.5, BW 260); high productivity (Milk 5.8, BW 250) | `BW`, `Milk`, `MilkPR`, `pct_pregnant`, `DE`, `CP`, `Bo`, `Ym` | Adopted 2026-09-11. Table 10.16A footnote 1 makes low productivity the Tier 1 default for other regions, and the low-productivity row's Pasture/Range feeding situation is the one that matches the activity coefficient the tool uses. Before this the defaults mixed the aggregate and non-dairy rows and described no animal IPCC published. |
| **Feeding situation** | Pasture / Range, flat terrain | Stall-fed (Ca 0); grazing large areas or hilly terrain (Ca 0.36) | `Ca` | Matches the low-productivity row, which Annex 10A.1 characterises as Pasture/Range. Stall-fed herds must override it. |
| **Lactation state** | Lactating | Dry phase (Cfi 0.322; Ym 7.0 in low-productivity systems) | `Cfi`, `Ym`, `Milk`, `Fat`, `MilkPR` | The generic catalogue default describes a lactating dairy cow. Footnote 4 of Table 10.12 restricts the dairy Ym rows to lactating animals. Every other sub-category is resolved separately. |
| **Animal class for manure nitrogen** | Other Cattle | Dairy Cow; Swine; Poultry; Other animals | `FRAC` | Table 10.22 publishes a separate column per animal class and the values differ substantially, for instance solid storage volatilisation 0.45 for Other Cattle against 0.30 for Dairy Cow. |
| **Climate, soils pathway** | Wet | Dry (EF3_PRP 0.002, EF4 0.005, Frac_LEACH_PRP 0); climate-aggregated (EF3_PRP 0.004, EF4 0.010) | `EF3_PRP`, `EF4`, `Frac_LEACH_PRP` | DRY-CLIMATE INVENTORIES MUST OVERRIDE THESE THREE. Keeping the wet-climate defaults in a dry climate overstates direct pasture N2O roughly threefold, overstates indirect N2O from deposition almost threefold, and reports a leaching pathway that IPCC treats as absent. |
| **Climate zone, manure methane** | Chosen per inventory. Reference values are read at <=10 C for boreal, 19 C for temperate and >=28 C for tropical | The 2019 Refinement resolves ten climate zones; this tool resolves four, and its tropical-dry column mirrors tropical | `MCF` | The same three columns are used for every temperature-dependent system, so the systems stay comparable with each other. |
| **Manure system variant** | One IPCC sub-type per manure system, named on every row of the manure-system table | Liquid slurry WITH versus without a natural crust; composting static pile versus in-vessel versus windrow; solid storage plain versus bulking agent versus additives; deep bedding with versus without mixing | `MCF`, `EF3`, `FRAC` | IPCC splits several systems into variants whose coefficients differ by a factor of two or more. Every coefficient on one of our rows comes from the single variant that row declares, so the row describes one real system rather than a blend. |
| **Guidelines edition** | Selected by the user in Inventory_Metadata: 2006 or 2019 Refinement | n/a | `Ym`, `MCF` | Ym is the only default whose value differs between the two editions. The pasture MCF is deliberately held on the 2006 convention, because the 2019 Refinement pasture MCF of 0.47% has to be paired with a pasture-specific Bo of 0.19 that the engine does not carry. |
| **Species** | Cattle | Buffalo (Bo 0.10) | `Bo`, `Cp`, `ASH` | The tool is a cattle tool. Buffalo values differ and are not carried. |

### Which IPCC variant each manure system models

Every coefficient on a manure row (MCF, EF3, and the volatilisation and leaching fractions) comes from the single variant named here, so the row describes one real system rather than a blend. If the user's file describes a different variant, flag it.

| mms_type | IPCC variant modelled |
|---|---|
| `pasture` | PRP (Ch.11 pathway; MCF from 2006 Table 10.17 Pasture/Range/Paddock) |
| `daily_spread` | Daily spread |
| `solid_storage` | Solid storage (plain) |
| `solid_storage_covered` | Solid storage - Covered/compacted (2019R Table 10.17) |
| `dry_lot` | Dry lot |
| `deep_bedding` | Deep bedding, >1 month accumulation |
| `liquid_slurry` | Liquid/Slurry, with natural crust cover |
| `composting` | Composting - Static Pile (forced aeration) |
| `lagoon` | Uncovered anaerobic lagoon |
| `anaerobic_digester` | Anaerobic digester, low leakage, high-quality industrial technology, open storage |
| `aerobic_treatment` | Aerobic treatment, forced aeration |
| `burned_for_fuel` | Burned for fuel |

Single source of truth for the 25 IPCC-aligned parameters the cattle uncertainty app expects.
When you (Claude) translate a user's raw column to a template field, use this table.
All parameter codes are case-sensitive.

| code | tier | type | unit | IPCC default | suggested ±% | distribution | IPCC ref | aliases accepted | definition |
|------|------|------|------|--------------|--------------|--------------|----------|------------------|------------|
| `N` | core | activity_data | head |  | 10% | normal | — | cattle_pop | Number of animals in this sub-category |
| `BW` | core | coefficient | kg | 270 | 15% | normal | Table 10A.2 | W, live_weight | Average live body weight of the animals |
| `MW` | core | coefficient | kg | 300 | 10% | normal | Table 10A.2 | mature_weight | Mature (adult) body weight of the animals |
| `WG` | core | coefficient | kg/day | 0 | 30% | pert | Table 10A.1 | weight_gain | Average daily weight gain — set 0 for non-growing (adult) animals |
| `Milk` | core | coefficient | kg/head/day | 1.2 | 20% | normal | — | milk_yield | Daily milk yield per lactating cow (not sub-category-average — the tool multiplies by pct_pregnant internally). Set 0 for sub-categories that do not lactate. |
| `Fat` | core | coefficient | % | 4.3 | 10% | normal | — | milk_fat | Fat content of milk (% by weight) |
| `pct_pregnant` | core | coefficient | fraction (0-1) | 0.52 | 20% | beta | — | pct_lactating, pct_calving | Fraction of females in this sub-category that are pregnant during the year, between 0 and 1 — includes pregnant heifers that have not yet calved. Weights Cpregnancy in IPCC Eq 10.13 (NEp) and the milk-N retention term in Eq 10.33; the tool also applies it as the lactation-weight in Eq 10.8 (NEl). For sub-categories where lactation and pregnancy populations differ, enter the pregnancy fraction. Do NOT auto-map a source column labelled `pct_lactating` or `pct_calving` to this field — the parser DOES accept them as aliases, but they are not semantically identical (a herd can have non-pregnant lactating cows, and calving rate ≠ pregnancy rate at any given moment). If the source file gives only lactating or only calving rate, flag it in section D and confirm the conversion with the user. |
| `DE` | core | coefficient | % | 51 | 15% | normal | Eq 10.14--16 | DE_pct | Digestible energy as a percentage of gross energy — typical range 45-75% |
| `Cfi` | advanced | coefficient | MJ/day/kg^0.75 | 0.386 | 30% | pert | Table 10.4 | (none) | Maintenance energy coefficient — depends on sex and lactation status (IPCC Table 10.4) |
| `Ca` | advanced | coefficient | dimensionless | 0.17 | 30% | triangular | Table 10.5 | (none) | Activity coefficient for locomotion energy — depends on feeding situation (IPCC Table 10.5) |
| `C` | advanced | coefficient | dimensionless | 0.8 | 30% | triangular | Eq 10.6 | C_growth | Growth coefficient for the NEg equation — depends on sex and physiological status (IPCC Eq 10.6) |
| `Cp` | advanced | coefficient | dimensionless | 0.1 | 10% | beta | Table 10.7 | (none) | Pregnancy coefficient — 0.10 for pregnant animals (IPCC Table 10.7) |
| `hours` | core | coefficient | hours/day | 0 | 20% | pert | Eq 10.11 | (none) | Daily working hours (Eq. 10.11) — set 0 if animals do no work; relevant only where animals are used for traction/load |
| `CP` | core | coefficient | % | 9.6 | 15% | normal | Eq 10.32 | CP_pct | Crude protein (CP%) content of the diet — used to estimate nitrogen excretion |
| `Ym` | advanced | coefficient | % | 6.5 | 20% | pert | Table 10.12 | Ym_pct | Methane conversion factor: % of gross energy in feed converted to methane (IPCC Vol.4 Ch.10 Table 10.12). Default uncertainty 20% per Penman et al. (2000) and IPCC 2019R Vol.1 Ch.3 Tier 2 guidance — Ym is one of the most uncertain parameters in cattle CH₄ inventories and a tight ±% misstates that. Sub-category values vary: dairy cows ≈ 5.7–6.5%, other cattle 6.3–7.0%, feedlot 4.0–5.0%, pre-weaned calves effectively 0%. |
| `Bo` | advanced | coefficient | m3 CH₄/kg VS | 0.13 | 15% | pert | Table 10.16A | (none) | Maximum CH₄ producing capacity of manure (IPCC Vol.4 Ch.10 Table 10.16a, 2019R). For **Other regions, low productivity** (the Sub-Saharan Africa / South Asia default that most users of this tool fall under) BOTH dairy and non-dairy cattle = **0.13**. The 0.24 value applies ONLY to dairy cattle in North America / Western Europe (high-productivity systems); non-dairy cattle there range 0.17–0.19. Buffalo = 0.10 (do not use buffalo's value for cattle). For a high-productivity commercial dairy herd the compiler may override dairy_cows to 0.24. |
| `ASH` | advanced | coefficient | fraction | 0.08 | 25% | pert | Eq 10.24 | ash | Ash content of manure — IPCC default 0.08 (Eq 10.24 footnote) |
| `UE` | advanced | coefficient | fraction | 0.04 | 25% | pert | Eq 10.24 | (none) | Urinary energy as fraction of gross energy — IPCC default 0.04 (Eq 10.24 footnote) |
| `EF3_PRP` | advanced | coefficient | kg N2O-N/kg N | 0.006 | (asymmetric — use bounds) | pert | Ch.11 Table 11.1 | (none) | N₂O emission factor for dung/urine on pasture, EF3PRP,CPP (IPCC Vol.4 Ch.11 Table 11.1, 2019R, **wet climate**: 0.006, range **0.000–0.027**). For dry climate use 0.002 (range 0.000–0.007). For aggregated-across-climates use 0.004 (range 0.000–0.014). 2006 = 0.02. The wide wet-climate range is genuine — EF3PRP is one of the most uncertain N₂O parameters and a dominant driver of pasture-N₂O uncertainty. |
| `EF4` | advanced | coefficient | kg N2O-N/kg N | 0.014 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for atmospheric N deposition (IPCC Vol.4 Ch.11 Table 11.3, 2019R, **wet climate**: 0.014, range 0.011-0.017). For dry climate use 0.005. For aggregated use 0.010 (range 0.002-0.018). 2006 = 0.010. |
| `EF5` | advanced | coefficient | kg N2O-N/kg N | 0.011 | (asymmetric — use bounds) | lognormal | Ch.11 Table 11.3 | (none) | N₂O EF for N leaching/runoff (IPCC Vol.4 Ch.11 Table 11.3). 2019R EF5 = 0.011 (range 0.000-0.020), no climate disaggregation. 2006 = 0.0075. |
| `Frac_GASM_PRP` | advanced | coefficient | fraction | 0.21 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_GasPRP | Fraction of N volatilised from dung/urine on pasture (IPCC Vol.4 Ch.11 Table 11.3, FracGASM). 2019R = 0.21 (range 0.00-0.31); 2006 = 0.20. |
| `Frac_LEACH_PRP` | advanced | coefficient | fraction | 0.24 | (asymmetric — use bounds) | pert | Ch.11 Table 11.3 | Frac_LeachPRP | Fraction of N leached from pasture deposition (IPCC Vol.4 Ch.11 Table 11.3, FracLEACH-(H), wet climates only). 2019R = 0.24 (range 0.01-0.73); 2006 = 0.30; in dry climates = 0. |
| `MilkPR` | core | coefficient | % | 3.6 | 10% | normal | Eq 10.33 | protein_milk | Protein content of milk — feeds the milk-N term in IPCC Vol.4 Ch.10 Eq 10.33 (N retention for cattle, where the 6.38 milk-protein-to-N conversion is defined) |
| `Tw` | advanced | coefficient | °C | 20 | 25% | normal | Eq 10.2 | (none) | Mean daily temperature in winter (°C) — Cfi cold-climate adjustment per IPCC Vol.4 Ch.10 Eq 10.2 (modifies the Cfi from Eq 10.3). Leave blank or set 20 to disable adjustment |

## Asymmetric (non-symmetric) bounds

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

The values below are the IPCC 2019 Refinement Vol.4 Ch.11 figures (Table 11.1 for EF3_PRP; Table 11.3 for EF4, EF5, Frac_GASM_PRP and Frac_LEACH_PRP) for the **wet climate** classification, because most users of this tool operate in wet climates (sub-Saharan Africa, South and Southeast Asia, Latin American smallholder and commercial systems). The dry-climate alternatives are lower (EF3_PRP about 0.002, and Frac_LEACH_PRP effectively zero where evapotranspiration exceeds precipitation). For an arid-country inventory the user can edit these five bounds in the Parameters sheet before uploading; flag the choice in section D if the country is clearly arid.

Three of the lower bounds are deliberately set to a small positive number rather than the strict IPCC zero, because PERT and lognormal distributions break or produce extreme samples at an exact-zero lower bound. The bumped values are small enough that the IPCC sense is preserved. Do not "correct" them back to zero.

| code | lower | central | upper |
|------|-------|---------|-------|
| `EF3_PRP` | 0.0005 | 0.006 | 0.027 |
| `EF4` | 0.011 | 0.014 | 0.017 |
| `EF5` | 0.0005 | 0.011 | 0.02 |
| `Frac_GASM_PRP` | 0.005 | 0.21 | 0.31 |
| `Frac_LEACH_PRP` | 0.01 | 0.24 | 0.73 |

## Sex- and physiology-specific coefficient overrides

The `IPCC default` column in the catalogue above lists the **lactating-female** value, because that is the most common case. For every other sub-category you MUST take `Cfi`, `C` and `Ym` from the table below, which is generated directly from the app's own resolver. Do not reuse the lactating-cow `Cfi` for non-dairy animals, and do not use the female `C` for males.

`Ym` is the only parameter that also depends on the guideline edition, so the table gives a column for each. Read the one matching `inventory_metadata.ipcc_version`. The 2019 Refinement separates lactating dairy cows from non-dairy and multi-purpose cattle and from feedlot cattle (IPCC Table 10.12); the 2006 table draws no distinction below feedlot. Using the lactating-dairy value for grazing cattle understates enteric methane, and using it for feedlot cattle overstates it badly.

Feedlot cattle also carry their own `DE` and `CP`, because the IPCC feedlot `Ym` applies only to a high-digestibility concentrate ration. Those three move together: if the source file shows a feedlot herd on a low-digestibility diet, it is not an IPCC feedlot, so map it to the appropriate grazing sub-category instead and say so.

`Ca` is handled separately: it depends on the feeding situation, not on the sub-category.

| sub-category | Cfi (Table 10.4) | C (Eq 10.6) | Ym 2019R (Table 10.12) | Ym 2006 | DE | CP | notes |
|---|---|---|---|---|---|---|---|
| `dairy_cows` | 0.386 | 0.8 | 6.5 | 6.5 | 51 | 9.6 |  |
| `other_cows` | 0.322 | 0.8 | 7 | 6.5 | 58 | 10 |  |
| `bulls` | 0.37 | 1.2 | 7 | 6.5 | 58 | 10 |  |
| `oxen` | 0.322 | 1 | 7 | 6.5 | 58 | 10 |  |
| `heifers` | 0.322 | 0.8 | 7 | 6.5 | 59 | 10.4 |  |
| `growing_males` | 0.322 | 1 | 7 | 6.5 | 59 | 10.4 | Genuinely ambiguous across countries: the term is used for both castrate steers and intact pre-castration bulls, which take different IPCC Eq 10.6 coefficients. The app assumes castrate. If the source file's Coefficients sheet gives the intact-bull value instead, that means the inventory team treats them as intact, so honour the file value with `data_source = user_file` and note it. If the file is silent, keep the generated value and surface the assumption in section D. |
| `calves_female` | 0.322 | 0.8 | 7 | 6.5 | 59 | 10.3 | Takes the female Eq 10.6 coefficient, on the heifer-replacement track. Some inventories do not sex-disaggregate calves at all and report a single pooled calf growth coefficient; if the source file does that, say so in section D rather than splitting it yourself. |
| `calves_male` | 0.322 | 1 | 7 | 6.5 | 59 | 10.3 | Takes the castrate Eq 10.6 coefficient. It rises to the intact-bull value only on the breeding-bull development path after puberty. Note the direction: castration LOWERS the growth coefficient, it does not raise it, so a file showing a higher value for castrated males than for intact ones has the two swapped. |
| `feedlot_cattle` | 0.322 | 1 | 4 | 3 | 74 | 14 |  |

`Ca` is not per-sub-category: it depends on the feeding situation (IPCC Table 10.5).

Values: stall_fed = 0; pasture_flat = 0.17; pasture_hilly = 0.36.

**The C-coefficient (growth coefficient) is the one most commonly missed.** When applying a sub-category-specific value, keep `data_source = "ipcc_default"` (the sex-specific value is itself an IPCC default) and call out the deliberate override in your end-of-run summary so the user can spot-check it in the QA tab.

For `Ca`, pick the value from the feeding-situation list above based on what the user describes, not on the sub-category: animals confined to a small area take the stall-fed value, animals on flat pasture the grazing value, and animals on open range or hilly terrain the highest value. If the user does not specify, assume grazing for smallholder and extensive systems, and stall-fed for confined dairy. Working oxen expend more energy than grazing animals; IPCC Table 10.5 gives no separate cattle value for draught work, so if the user reports heavy draught use, raise it in section D rather than inventing a coefficient.

## Tier meaning

- **core** = user must provide a value (or accept the IPCC default). These are the activity-data parameters and a handful of high-impact coefficients (DE, CP, MilkPR).
- **advanced** = IPCC equation coefficient. Pre-filled with the IPCC default from the column above; only override if the user has a country-specific measurement.

## param_type

- **activity_data** = `N` only (animal population). This is the one true activity-data variable.
- **coefficient** = everything else (production parameters, energy/methane/N₂O coefficients).

## Distribution codes accepted

`normal`, `posnorm`, `lognormal`, `beta`, `triangular`, `pert`, `uniform`, `constant`, `tnorm_0_1`

Use `pert` or `triangular` when only a mode + bounds are known; `normal` for symmetric ±% around a measured mean; `beta` or `tnorm_0_1` for fractions that must stay in [0, 1]; `lognormal` for strictly-positive values with right skew (typical for emission factors).
