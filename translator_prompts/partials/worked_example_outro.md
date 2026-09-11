<!-- Closing prose for worked_example.md. Numberless by design. -->

What to carry across to the user's inventory:

1. One row per (sub_category, parameter) for every catalogue parameter, with nothing omitted.
2. `param_type` taken from the catalogue, never inferred from whether a farmer could measure the quantity.
3. Sub-category-specific `Cfi` and `C` from the override table in `param_catalogue.md`, not the lactating-cow value for everyone.
4. Biological zeros where they apply: no milk, fat or milk protein for males, no pregnancy fraction for males or calves, no work hours for anything but oxen.
5. Asymmetric parameters with bounds, symmetric ones with a percentage.
6. Manure rows whose `fraction_pct` sums to 100 within each sub-category, every coefficient column filled.
