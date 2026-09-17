# Worked example -- complete template-ready JSON for a small inventory

Below is one full reference output to pattern-match against when emitting the `template-ready` JSON. It is INTENTIONALLY different from the user's data (Country Z, an Asian smallholder dairy with one heifer group, not African and not multi-sub-category beef) so you cannot copy values blindly. Copy the SHAPE.

What the example demonstrates:

- `inventory_metadata` filled completely, using only the fields the tool's schema accepts.
- `parameters` contains EVERY catalogue parameter, repeated for EVERY sub-category. List them all; never write a placeholder like `// repeat for X` or `// for brevity not shown`.
- `manure_management` has one row per (sub_category, mms_type) with `MCF_pct`, `EF3`, `Frac_GasMS_pct` AND `Frac_LeachMS_pct` on every row. The last two are the ones most often forgotten and they MUST be present.
- `param_type` is `activity_data` for the population parameter only. Every other parameter is a `coefficient`, no matter how measurable it is on-farm. This is the single most common mistake.
- Asymmetric parameters carry absolute `lower` and `upper` bounds instead of a symmetric `uncertainty_pct`.
- Strict JSON: no comments, no expressions, no trailing commas, no unquoted keys.
- Every value is a literal. Never write `4.5*1.032`; compute `4.644` yourself before emitting.

The country-specific values here (herd sizes, weights, milk yield, feed quality) are what a user would supply. Everything else is the IPCC default the tool would otherwise fill in for them.

This example has 2 sub-categories, so 2 x 25 = 50 parameter rows. An inventory with 8 sub-categories would need 8 x 25 = 200.

```template-ready
{
  "inventory_metadata": {
    "country": "Country Z", "region": "asia", "year": 2023, "species": "cattle_dairy",
    "ipcc_version": "2019_refinement", "prepared_by": "National Inventory Team"
  },
  "parameters": [
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "N", "mean": 12000, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "BW", "mean": 420, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "MW", "mean": 450, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "WG", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Milk", "mean": 8.5, "uncertainty_pct": 20, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Fat", "mean": 4, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "pct_pregnant", "mean": 0.52, "uncertainty_pct": 20, "distribution": "beta", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "DE", "mean": 62, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Cfi", "mean": 0.386, "uncertainty_pct": 30, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Ca", "mean": 0.17, "uncertainty_pct": 30, "distribution": "triangular", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "C", "mean": 0.8, "uncertainty_pct": 30, "distribution": "triangular", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Cp", "mean": 0.1, "uncertainty_pct": 10, "distribution": "beta", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "hours", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "biological_zero"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "CP", "mean": 14, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Ym", "mean": 6.5, "uncertainty_pct": 20, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Bo", "mean": 0.13, "uncertainty_pct": 15, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "ASH", "mean": 0.08, "uncertainty_pct": 25, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "UE", "mean": 0.04, "uncertainty_pct": 25, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF3_PRP", "mean": 0.006, "lower": 0.0005, "upper": 0.027, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF4", "mean": 0.014, "lower": 0.011, "upper": 0.017, "distribution": "lognormal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "EF5", "mean": 0.011, "lower": 0.0005, "upper": 0.02, "distribution": "lognormal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Frac_GASM_PRP", "mean": 0.21, "lower": 0.005, "upper": 0.31, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Frac_LEACH_PRP", "mean": 0.24, "lower": 0.01, "upper": 0.73, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "MilkPR", "mean": 3.6, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "parameter": "Tw", "mean": 20, "uncertainty_pct": 25, "distribution": "normal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "N", "mean": 3000, "uncertainty_pct": 10, "distribution": "normal", "param_type": "activity_data", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "BW", "mean": 250, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "MW", "mean": 450, "uncertainty_pct": 10, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "WG", "mean": 0.25, "uncertainty_pct": 30, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Milk", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "biological_zero"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Fat", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "biological_zero"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "pct_pregnant", "mean": 0.5, "uncertainty_pct": 20, "distribution": "beta", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "DE", "mean": 58, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Cfi", "mean": 0.322, "uncertainty_pct": 30, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Ca", "mean": 0.17, "uncertainty_pct": 30, "distribution": "triangular", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "C", "mean": 0.8, "uncertainty_pct": 30, "distribution": "triangular", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Cp", "mean": 0.1, "uncertainty_pct": 10, "distribution": "beta", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "hours", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "biological_zero"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "CP", "mean": 12, "uncertainty_pct": 15, "distribution": "normal", "param_type": "coefficient", "data_source": "user_file"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Ym", "mean": 7, "uncertainty_pct": 20, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Bo", "mean": 0.13, "uncertainty_pct": 15, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "ASH", "mean": 0.08, "uncertainty_pct": 25, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "UE", "mean": 0.04, "uncertainty_pct": 25, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF3_PRP", "mean": 0.006, "lower": 0.0005, "upper": 0.027, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF4", "mean": 0.014, "lower": 0.011, "upper": 0.017, "distribution": "lognormal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "EF5", "mean": 0.011, "lower": 0.0005, "upper": 0.02, "distribution": "lognormal", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Frac_GASM_PRP", "mean": 0.21, "lower": 0.005, "upper": 0.31, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Frac_LEACH_PRP", "mean": 0.24, "lower": 0.01, "upper": 0.73, "distribution": "pert", "param_type": "coefficient", "data_source": "ipcc_default"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "MilkPR", "mean": 0, "lower": 0, "upper": 0, "distribution": "constant", "param_type": "coefficient", "data_source": "biological_zero"},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "parameter": "Tw", "mean": 20, "uncertainty_pct": 25, "distribution": "normal", "param_type": "coefficient", "data_source": "ipcc_default"}
  ],
  "manure_management": [
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "pasture", "fraction_pct": 30, "MCF_pct": 2, "EF3": 0.02, "Frac_GasMS_pct": 0, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "solid_storage", "fraction_pct": 50, "MCF_pct": 5, "EF3": 0.01, "Frac_GasMS_pct": 45, "Frac_LeachMS_pct": 2},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "daily_spread", "fraction_pct": 15, "MCF_pct": 1, "EF3": 0, "Frac_GasMS_pct": 7, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "dairy_cows", "mms_type": "liquid_slurry", "fraction_pct": 5, "MCF_pct": 50, "EF3": 0.005, "Frac_GasMS_pct": 30, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "pasture", "fraction_pct": 70, "MCF_pct": 2, "EF3": 0.02, "Frac_GasMS_pct": 0, "Frac_LeachMS_pct": 0},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "solid_storage", "fraction_pct": 25, "MCF_pct": 5, "EF3": 0.01, "Frac_GasMS_pct": 45, "Frac_LeachMS_pct": 2},
    {"cattle_type": "dairy", "aggregation_level": "all", "sub_category": "heifers", "mms_type": "daily_spread", "fraction_pct": 5, "MCF_pct": 1, "EF3": 0, "Frac_GasMS_pct": 7, "Frac_LeachMS_pct": 0}
  ],
  "parameter_timeseries": []
}
```

What to carry across to the user's inventory:

1. One row per (sub_category, parameter) for every catalogue parameter, with nothing omitted.
2. `param_type` taken from the catalogue, never inferred from whether a farmer could measure the quantity.
3. Sub-category-specific `Cfi` and `C` from the override table in `param_catalogue.md`, not the lactating-cow value for everyone.
4. Biological zeros where they apply: no milk, fat or milk protein except in MATURE FEMALES (so zero for males, and zero for heifers, calves and feedlot cattle, which have not calved), no pregnancy fraction for males or calves, no work hours for anything but oxen.
5. Asymmetric parameters with bounds, symmetric ones with a percentage.
6. Manure rows whose `fraction_pct` sums to 100 within each sub-category, every coefficient column filled.
