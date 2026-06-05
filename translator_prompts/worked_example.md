# Worked example — complete template-ready JSON for a small inventory

Below is one full reference output you can pattern-match against when emitting the `template-ready` JSON. It is INTENTIONALLY different from the user's data (Country Z = Asian smallholder dairy with one heifer group; not African, not multi-sub-category beef) so you cannot copy values blindly — only the SHAPE.

Key things the example demonstrates:

- `inventory_metadata` filled completely with realistic values.
- `parameters` array contains EVERY one of the 25 catalogue parameters, repeated for EVERY sub-category. Two sub-categories here → 2 × 25 = 50 parameter rows. For an inventory with 8 sub-categories you would emit 8 × 25 = 200 rows. List them all. Never use placeholder comments like `// repeat for X` or `// for brevity not shown`.
- `manure_management` has one row per (sub_category, mms_type) combination, with `MCF_pct`, `EF3`, `Frac_GasMS_pct`, AND `Frac_LeachMS_pct` filled on every row (the last two are commonly forgotten — they MUST be present, with IPCC 2019 Refinement defaults if the user had no country-specific value).
- Strict JSON: no comments, no expressions, no trailing commas, no unquoted keys.
- Every value is a literal — never write `4.5*1.032`; compute `4.644` yourself before emitting.

When the user defers to your judgement, your job is to emit this full shape for THEIR sub-categories. Use IPCC defaults from `param_catalogue.md` for values you don't have. Use IPCC 2019R Table 10.17 / 11.1 / 11.3 defaults for MMS coefficient columns. Mark every IPCC-defaulted Parameters row with `data_source = "IPCC default — user deferred"` (the field is optional in the schema but useful for the user's QA review).

## Reference output

```template-ready
{
  "inventory_metadata": {
    "country": "Country Z",
    "region": "asia",
    "inventory_year": 2024,
    "species": "cattle_dairy",
    "ipcc_version": "2019_refinement",
    "prepared_by": "Country Z Ministry of Environment, 2025",
    "notes": "Reference example — 2 sub-categories, IPCC 2019R defaults applied where country-specific data unavailable."
  },
  "parameters": [
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "N", "mean": 12000, "uncertainty_pct": 5, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "BW", "mean": 420, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "MW", "mean": 450, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "WG", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Milk", "mean": 8.5, "uncertainty_pct": 15, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Fat", "mean": 3.8, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "pct_pregnant", "mean": 0.85, "uncertainty_pct": 15, "distribution": "beta", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "DE", "mean": 65, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Cfi", "mean": 0.386, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Ca", "mean": 0.17, "uncertainty_pct": 25, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "C", "mean": 0.8, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Cp", "mean": 0.10, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "hours", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "CP", "mean": 14, "uncertainty_pct": 15, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Ym", "mean": 6.5, "uncertainty_pct": 10, "distribution": "pert", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Bo", "mean": 0.13, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "ASH", "mean": 0.08, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "UE", "mean": 0.04, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF3_PRP", "mean": 0.02, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF4", "mean": 0.014, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF5", "mean": 0.011, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Frac_GASM_PRP", "mean": 0.21, "uncertainty_pct": 30, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Frac_LEACH_PRP", "mean": 0.24, "uncertainty_pct": 30, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "MilkPR", "mean": 3.3, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Tw", "mean": 25, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient"},

    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "N", "mean": 4500, "uncertainty_pct": 5, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "BW", "mean": 280, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "MW", "mean": 450, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "WG", "mean": 0.45, "uncertainty_pct": 20, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Milk", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Fat", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "pct_pregnant", "mean": 0.5, "uncertainty_pct": 20, "distribution": "beta", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "DE", "mean": 60, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Cfi", "mean": 0.322, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Ca", "mean": 0.17, "uncertainty_pct": 25, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "C", "mean": 0.8, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Cp", "mean": 0.10, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "hours", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "CP", "mean": 12, "uncertainty_pct": 15, "distribution": "normal", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Ym", "mean": 6.5, "uncertainty_pct": 10, "distribution": "pert", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Bo", "mean": 0.13, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "ASH", "mean": 0.08, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "UE", "mean": 0.04, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF3_PRP", "mean": 0.02, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF4", "mean": 0.014, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF5", "mean": 0.011, "uncertainty_pct": 50, "distribution": "lognormal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Frac_GASM_PRP", "mean": 0.21, "uncertainty_pct": 30, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Frac_LEACH_PRP", "mean": 0.24, "uncertainty_pct": 30, "distribution": "normal", "param_type": "coefficient"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "MilkPR", "mean": 0, "uncertainty_pct": 0, "distribution": "constant", "param_type": "activity_data"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Tw", "mean": 25, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient"}
  ],
  "manure_management": [
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "pasture", "fraction_pct": 30, "MCF_pct": 1.5, "EF3": 0.02, "Frac_GasMS_pct": 0, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "solid_storage", "fraction_pct": 50, "MCF_pct": 4, "EF3": 0.005, "Frac_GasMS_pct": 30, "Frac_LeachMS_pct": 2},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "daily_spread", "fraction_pct": 15, "MCF_pct": 1, "EF3": 0, "Frac_GasMS_pct": 7, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "lagoon", "fraction_pct": 5, "MCF_pct": 71, "EF3": 0, "Frac_GasMS_pct": 35, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "pasture", "fraction_pct": 70, "MCF_pct": 1.5, "EF3": 0.02, "Frac_GasMS_pct": 0, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "solid_storage", "fraction_pct": 25, "MCF_pct": 4, "EF3": 0.005, "Frac_GasMS_pct": 30, "Frac_LeachMS_pct": 2},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "daily_spread", "fraction_pct": 5, "MCF_pct": 1, "EF3": 0, "Frac_GasMS_pct": 7, "Frac_LeachMS_pct": 0}
  ]
}
```

## What this shows (read carefully)

1. **Every sub-category gets ALL 25 parameter rows.** Even the ones that are zero for that animal type (Milk = 0 for heifers, WG = 0 for adult dairy_cows, hours = 0 for non-draught animals). The Monte Carlo needs the row present; a `constant` distribution with `mean = 0` keeps the calculation correct.

2. **Manure_Management has rows for EVERY sub-category in `parameters`.** This inventory has 2 sub-categories, so both appear. If your user's inventory has 8 sub-categories, you would emit 8 × N MMS rows where N is the number of MMS types in use. Never leave a sub-category with no MMS rows — manure-CH4 and -N2O collapse to zero for that animal type.

3. **`fraction_pct` sums to 100 within each sub-category.** Verify before emitting.

4. **`MCF_pct`, `EF3`, `Frac_GasMS_pct`, `Frac_LeachMS_pct` are all filled** on every MMS row. The last two are the ones most often skipped — they're easy to forget because they're optional in the schema. Fill them anyway with IPCC 2019R defaults; the schema accepts numeric zero where the IPCC value is zero (e.g. `Frac_GasMS_pct = 0` for pasture).

5. **`param_type` is "activity_data" or "coefficient"** — the catalogue tells you which. As a rule of thumb: anything the user could measure on their farm (N, BW, MW, WG, Milk, Fat, pct_pregnant, DE, CP, hours, MilkPR) is `activity_data`; anything that comes from an IPCC table (Cfi, Ca, C, Cp, Ym, Bo, ASH, UE, EF3_PRP, EF4, EF5, Frac_*, Tw) is `coefficient`.

6. **Distributions:** `normal` for symmetric ±%, `pert` or `triangular` for asymmetric ranges, `beta` for fractions bounded in [0, 1] (pct_pregnant), `lognormal` for highly-skewed positive quantities (emission factors), `constant` for hard zeros that should not be sampled.

7. **No comments, no expressions, no shortcuts.** This entire block is plain JSON.
