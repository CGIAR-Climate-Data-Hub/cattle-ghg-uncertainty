<!-- Prose for the '## Asymmetric (non-symmetric) bounds' section of
param_catalogue.md. The bounds TABLE that follows is generated from
PARAM_CATALOGUE, so it cannot drift from the app. -->

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

Values below are the **IPCC 2019 Refinement Vol.4 Ch.11 Tables 11.1 (EF3_PRP) and 11.3 (EF4, EF5, Frac_GASM_PRP, Frac_LEACH_PRP)** for the **wet climate** classification, since most users of this tool (SSA, South/Southeast Asia, Latin America smallholder + commercial systems) operate in wet climates. Dry-climate values (lower EF3_PRP ≈ 0.002, Frac_LEACH_PRP ≈ 0) are documented in the description column above. For an arid-country inventory the user can edit these five bounds in the Parameters sheet before uploading.

Central values and ranges verified 2026-06-15 directly against the IPCC 2019 Refinement source text (Vol.4 Ch.11 Table 11.1 EF3PRP,CPP wet = 0.006, range 0.000–0.027; Table 11.3 EF4 wet = 0.014, range 0.011–0.017; EF5 = 0.011, range 0.000–0.020; FracGASM = 0.21, range 0.00–0.31; FracLEACH-(H) = 0.24, range 0.01–0.73).

Three lower bounds (`EF3_PRP`, `EF5`, `Frac_GASM_PRP`) are bumped from the strict-IPCC 0 to a small positive number (0.0005, 0.0005, 0.005) because PERT and lognormal distributions break or produce extreme samples when the lower bound is exactly 0. The bumped values are tiny enough that the IPCC sense is preserved.
