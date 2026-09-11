<!-- Intro prose for worked_example.md. Keep free of numbers: the generator
injects the row arithmetic, and the JSON below is built from the R constants.
The previous hand-written version mis-tagged 17 of 50 rows as activity_data,
stated the wrong param_type rule outright, and carried superseded values. -->

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
