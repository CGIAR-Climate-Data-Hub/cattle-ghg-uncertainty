<!-- Prose for the '## Asymmetric (non-symmetric) bounds' section.
The bounds TABLE that follows is generated from PARAM_CATALOGUE. Do NOT
restate those numbers here: an earlier version of this file reproduced the
entire table in prose four lines above it, which is exactly the duplication
the generator was rewritten to remove. Dry-climate figures are fine to name,
because the app does not store them. -->

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

The values below are the IPCC 2019 Refinement Vol.4 Ch.11 figures (Table 11.1 for EF3_PRP; Table 11.3 for EF4, EF5, Frac_GASM_PRP and Frac_LEACH_PRP) for the **wet climate** classification, because most users of this tool operate in wet climates (sub-Saharan Africa, South and Southeast Asia, Latin American smallholder and commercial systems). The dry-climate alternatives are lower (EF3_PRP about 0.002, and Frac_LEACH_PRP effectively zero where evapotranspiration exceeds precipitation). For an arid-country inventory the user can edit these five bounds in the Parameters sheet before uploading; flag the choice in section D if the country is clearly arid.

Three of the lower bounds are deliberately set to a small positive number rather than the strict IPCC zero, because PERT and lognormal distributions break or produce extreme samples at an exact-zero lower bound. The bumped values are small enough that the IPCC sense is preserved. Do not "correct" them back to zero.
