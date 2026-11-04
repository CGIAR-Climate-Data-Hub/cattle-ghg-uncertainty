<!-- Prose for the '## Asymmetric (non-symmetric) bounds' section.
The bounds TABLE that follows is generated from PARAM_CATALOGUE. Do NOT
restate those numbers here: an earlier version of this file reproduced the
entire table in prose four lines above it, which is exactly the duplication
the generator was rewritten to remove. The dry-climate, aggregated and 2006
figures are named in the prose below; the app recognises them too
(IPCC_ALT_DEFAULTS in R/utils_validation.R, 2026-11-04). -->

These parameters use absolute IPCC-derived lower/upper bounds rather than a symmetric ±% around the central value.

The values below are the IPCC 2019 Refinement Vol.4 Ch.11 figures (Table 11.1 for EF3_PRP; Table 11.3 for EF4, EF5, Frac_GASM_PRP and Frac_LEACH_PRP) for the **wet climate** classification, because most users of this tool operate in wet climates (sub-Saharan Africa, South and Southeast Asia, Latin American smallholder and commercial systems).

The app also recognises the other IPCC default values of these parameters and gives each its own IPCC range when the range is left blank: EF3_PRP dry climate 0.002 (0.000 to 0.007), aggregated 0.004 (0.000 to 0.014), 2006 0.02 (0.007 to 0.06); EF4 dry climate 0.005 (0.000 to 0.011), aggregated 0.010 (0.002 to 0.018), 2006 0.010 (0.002 to 0.05); EF5 2006 0.0075 (0.0005 to 0.025); Frac_GASM_PRP 2006 0.20 (0.05 to 0.5); Frac_LEACH_PRP 2006 0.30 (0.1 to 0.8). When the file uses one of these values, copy the value exactly, tag the row `ipcc_default` and leave the range blank: the app fills the matching IPCC range. Do not write the wet-climate bounds next to a dry-climate value. Frac_LEACH_PRP is zero in dry climates; a zero needs no range.

Three of the lower bounds are deliberately set to a small positive number rather than the strict IPCC zero, because PERT and lognormal distributions break or produce extreme samples at an exact-zero lower bound. The bumped values are small enough that the IPCC sense is preserved. Do not "correct" them back to zero.
