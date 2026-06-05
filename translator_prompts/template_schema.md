# Template schema

The app expects an `.xlsx` workbook with the sheets and columns below.
Sheet names and column headers are **case-sensitive and must match exactly**.

## Workbook overview

| sheet | required? | purpose |
|-------|-----------|---------|
| `_Lists` | optional (hidden) | dropdown vocabularies — created automatically when the user downloads the blank template; safe to omit when you (Claude) build a workbook from scratch |
| `README` | optional | human-readable quick-start — safe to omit |
| `Inventory_Metadata` | **required** | country, year, IPCC version, species |
| `Parameters` | **required** | the 27 parameters per cattle sub-category |
| `Manure_Management` | **required** | per-MMS allocation; per-group fractions must sum to 100% |
| `Parameter_TimeSeries` | optional | 5+ years of annual values for auto-correlation |
| `Vocab` | optional | reference catalogue — safe to omit |

## Sheet: `Inventory_Metadata`

Transposed (label/value) layout. Column A is the label, column B is the value.

| label | value | notes |
|-------|-------|-------|
| country | (free text) | e.g. `Zimbabwe`. Used in the report header. |
| region | one of: africa / asia / europe / americas / oceania / global | Continental region — drives the BW deviation benchmark (IPCC Vol.4 Ch.10 Annex 10A.1/10A.2/10A.3). Dropdown-constrained in the latest template. Legacy uploads with only a single free-text country cell are auto-mapped by the parser. |
| inventory_year | (integer) | e.g. `2022` |
| species | one of: cattle_dairy / cattle_non_dairy / buffalo | controlled vocabulary |
| ipcc_version | one of: 2006 / 2019_refinement | drives MMS list filtering |
| prepared_by | (free text) | name / institution |
| notes | (free text) | optional |

## Sheet: `Parameters`

Header row in row 3. Data starts at row 4. One row per (cattle_type × aggregation_level × sub_category × parameter).

| col | header | required? | notes |
|-----|--------|-----------|-------|
| A | cattle_type | yes | e.g. `dairy`, `non_dairy` |
| B | aggregation_level | yes | free text label for the inventory grouping |
| C | sub_category | yes | one of the ANIMAL_SUBCATEGORIES below (or free-text if the inventory uses custom groups) |
| D | parameter | yes | the parameter code from param_catalogue.md |
| E | definition | no | optional human label (mirrors param_catalogue) |
| F | unit | no | optional unit (mirrors param_catalogue) |
| G | value | yes | the central value — **the number the user is providing** |
| H | uncertainty_pct | one of (H) or (I/J) | symmetric ±% half-width of 95% CI |
| I | lower_bound | one of (H) or (I/J) | explicit lower bound (use for asymmetric params) |
| J | upper_bound | one of (H) or (I/J) | explicit upper bound |
| K | distribution | yes | one of the codes above |
| L | lower | no | auto-computed from H or I; safe to leave blank |
| M | upper | no | auto-computed from H or J; safe to leave blank |
| N | param_type | yes | `activity_data` (only for `N`) or `coefficient` |
| O | ipcc_ref | no | citation, e.g. `Table 10.4` |
| P | data_source | no | free text: where the value came from |

### Sub-category codes (ANIMAL_SUBCATEGORIES)

- `dairy_cows` — Dairy Cows (mature lactating females)
- `other_cows` — Other Cows (mature non-dairy females, inc. dry)
- `bulls` — Bulls (mature intact males, breeding)
- `oxen` — Oxen (mature castrated males)
- `heifers` — Heifers (young females 1-3yr, not yet calved)
- `growing_males` — Growing Males (young males 1-3yr, steers/bulls)
- `calves_female` — Calves - Female (<1yr)
- `calves_male` — Calves - Male (<1yr)
- `feedlot_cattle` — Feedlot Cattle (concentrated feeding)

## Sheet: `Manure_Management`

One row per (cattle_type × aggregation_level × sub_category × mms_type). Per-group rows must sum to fraction_pct = 100.

| col | header | required? | notes |
|-----|--------|-----------|-------|
| A | cattle_type | yes | matches Parameters sheet |
| B | aggregation_level | yes | matches Parameters sheet |
| C | sub_category | yes | matches Parameters sheet (auto-matched on upload if a near-spelling exists in Parameters, e.g. `DINT_heif` ↔ `DINT_heifer`) |
| D | mms_type | yes | controlled vocabulary (below) |
| E | fraction_pct | yes | % of manure to this MMS; rows per group must sum to 100 |
| F | lower_fraction | no | min % for fraction_pct uncertainty (optional, enables per-MMS allocation sampling) |
| G | upper_fraction | no | max % for fraction_pct uncertainty (optional, enables per-MMS allocation sampling) |
| H | distribution_fraction | no | distribution code for fraction_pct (default `pert`). Rows are renormalised per iteration so the simplex (sum = 100) is preserved. |
| I | MCF_pct | yes | methane conversion factor (%) — see climate-zone lookup |
| J | lower_mcf | no | for asymmetric ranges |
| K | upper_mcf | no | for asymmetric ranges |
| L | distribution_mcf | no | distribution code for MCF |
| M | EF3 | yes | direct N₂O EF (kg N₂O-N/kg N) for this MMS |
| N | lower_ef3 | no | |
| O | upper_ef3 | no | |
| P | distribution_ef3 | no | |
| Q | Frac_GasMS_pct | no | per-MMS volatilisation fraction (%) — defaults from IPCC 2019 Table 10.22 |
| R | lower_frac_gas | no | |
| S | upper_frac_gas | no | |
| T | distribution_frac_gas | no | |
| U | Frac_LeachMS_pct | no | per-MMS leaching fraction (%) — defaults from IPCC 2019 Table 10.23 |
| V | lower_frac_leach | no | |
| W | upper_frac_leach | no | |
| X | distribution_frac_leach | no | |

### MMS types — by IPCC version

| id | label | 2006? | 2019R? | MCF tropical | MCF temperate | EF3 |
|----|-------|-------|--------|--------------|----------------|-----|
| `pasture` | Pasture/Paddock/Range | ✓ | ✓ | 1.5 | 1 | 0.02 |
| `daily_spread` | Daily Spread | ✓ | ✓ | 1 | 0.5 | 0 |
| `solid_storage` | Solid Storage | ✓ | ✓ | 5 | 4 | 0.005 |
| `solid_storage_covered` | Solid Storage – Covered/Compacted (2019) |  | ✓ | 4 | 2 | 0.005 |
| `dry_lot` | Dry Lot | ✓ | ✓ | 5 | 1.5 | 0.02 |
| `deep_bedding` | Deep Bedding (>1 month) | ✓ | ✓ | 30 | 17 | 0.01 |
| `liquid_slurry` | Liquid/Slurry | ✓ | ✓ | 80 | 35 | 0.005 |
| `composting` | Composting | ✓ | ✓ | 1.5 | 1 | 0.006 |
| `lagoon` | Anaerobic Lagoon | ✓ | ✓ | 80 | 66 | 0 |
| `anaerobic_digester` | Anaerobic Digester / Biogas (2019) |  | ✓ | 3.5 | 1 | 0.0006 |
| `aerobic_treatment` | Aerobic Treatment (2019) |  | ✓ | 0 | 0 | 0.005 |
| `burned_for_fuel` | Burned for Fuel (2019) |  | ✓ | 10 | 10 | 0 |

### Per-MMS volatilisation & leaching defaults (IPCC 2019 Refinement)

Use these when filling Frac_GasMS_pct and Frac_LeachMS_pct.

| mms_type | Frac_Gas (mean / low / high) | Frac_Leach (mean / low / high) |
|----------|------------------------------|--------------------------------|
| `pasture` | 0 / 0 / 0 | 0 / 0 / 0 |
| `daily_spread` | 0.07 / 0.04 / 0.1 | 0 / 0 / 0 |
| `solid_storage` | 0.45 / 0.23 / 0.68 | 0.02 / 0.01 / 0.03 |
| `solid_storage_covered` | 0.1 / 0.05 / 0.15 | 0.02 / 0.01 / 0.03 |
| `dry_lot` | 0.3 / 0.15 / 0.45 | 0 / 0 / 0 |
| `deep_bedding` | 0.3 / 0.15 / 0.45 | 0.02 / 0.01 / 0.03 |
| `liquid_slurry` | 0.48 / 0.24 / 0.72 | 0 / 0 / 0 |
| `anaerobic_digester` | 0.05 / 0.02 / 0.08 | 0 / 0 / 0 |
| `composting` | 0.65 / 0.33 / 0.98 | 0.02 / 0.01 / 0.03 |
| `aerobic_treatment` | 0.4 / 0.2 / 0.6 | 0 / 0 / 0 |
| `lagoon` | 0.78 / 0.39 / 1 | 0 / 0 / 0 |
| `burned_for_fuel` | 0 / 0 / 0 | 0 / 0 / 0 |

## Sheet: `Parameter_TimeSeries` (optional)

Annual values, used to compute Spearman-rank correlations between activity-data parameters. Minimum 5 years (or 4 if first-difference detrending is used).

| col | header | notes |
|-----|--------|-------|
| A | cattle_type | optional — blank = applies to all groups |
| B | aggregation_level | optional |
| C | sub_category | optional |
| D | year | required (integer) |
| E–N | N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, CP, MilkPR | the 10 parameters the app correlates; leave columns blank for parameters not measured |

## Validation rules the app applies

These are the checks Claude should run before declaring the workbook ready:

- **bounds**: `lower ≤ value ≤ upper` for every Parameters row (exception: when `distribution = constant` and all three = 0, e.g. WG for adults, hours for non-working cattle)
- **N ≥ 0** (cattle population can't be negative)
- **DE ∈ [0, 100]**, **Ym > 0**, fractions (`Frac_*`, `pct_pregnant`, `ASH`, `UE`) ∈ [0, 1]
- **distribution** ∈ DISTRIBUTION_TYPES
- **param_type** ∈ {`activity_data`, `coefficient`}
- **Manure_Management**: per (cattle_type, aggregation_level, sub_category), `fraction_pct` central values sum to 100 ± 1 (bounds may widen; the app renormalises each Monte Carlo iteration to preserve the simplex when `lower_fraction` / `upper_fraction` are supplied)
- **Manure_Management**: `lower_fraction ≤ fraction_pct ≤ upper_fraction` for every row that supplies the uncertainty columns; blank = deterministic
- **Manure_Management**: `sub_category` should match the Parameters sheet exactly. Near-spellings (e.g. `DINT_heif` vs `DINT_heifer`) are auto-matched on upload and shown as a `warn` row in the QAQC tab; multi-candidate ambiguity blocks the run
- **Manure_Management**: mms_type must be a valid id for the selected IPCC version
- **Inventory_Metadata.species** ∈ SPECIES_OPTIONS; **ipcc_version** ∈ IPCC_VERSIONS

## Distribution choice guide

When the user gives you a value but no distribution, pick from this priority list:

1. If the parameter has an asymmetric IPCC range (EF3_PRP, EF3_S, EF4, EF5, Frac_GASMS, Frac_LEACH_*) → use **`lognormal`** or **`pert`** with the absolute bounds from the asymmetric table in param_catalogue.md.
2. If the parameter is a fraction bounded in [0, 1] (pct_pregnant, ASH, UE, manure fractions) → **`beta`** or **`tnorm_0_1`**.
3. If the central value comes from a measured mean ± SD or ±CV → **`normal`**.
4. If only min / mode / max are known (expert judgement) → **`pert`** (preferred) or **`triangular`**.
5. If the parameter is structurally constant (WG = 0 for adults, hours = 0 for non-working cattle) → **`constant`**, lower = value = upper.

