<!-- Translator-facing definition overrides.

These are DELIBERATELY richer than PARAM_CATALOGUE$definition. The catalogue
definition describes the parameter for a human reading the app's Definitions
tab; these versions additionally carry instructions to the model about how to
map, when to refuse a mapping, and what to raise as a clarifying question.
Putting them in the catalogue would leak translator instructions into the app UI.

Keyed by parameter code. Any code here must exist in PARAM_CATALOGUE or the
build fails. Parameters absent from this file use the catalogue definition. -->

## pct_pregnant

Fraction of females in this sub-category that are pregnant during the year, between 0 and 1 — includes pregnant heifers that have not yet calved. Weights Cpregnancy in IPCC Eq 10.13 (NEp) and the milk-N retention term in Eq 10.33; the tool also applies it as the lactation-weight in Eq 10.8 (NEl). For sub-categories where lactation and pregnancy populations differ, enter the pregnancy fraction. Do NOT auto-map a source column labelled `pct_lactating` or `pct_calving` to this field — the parser DOES accept them as aliases, but they are not semantically identical (a herd can have non-pregnant lactating cows, and calving rate ≠ pregnancy rate at any given moment). If the source file gives only lactating or only calving rate, flag it in section D and confirm the conversion with the user.

## Ym

Methane conversion factor: % of gross energy in feed converted to methane (IPCC Vol.4 Ch.10 Table 10.12). Default uncertainty 20% per Penman et al. (2000) and IPCC 2019R Vol.1 Ch.3 Tier 2 guidance — Ym is one of the most uncertain parameters in cattle CH₄ inventories and a tight ±% misstates that. Sub-category values vary: dairy cows ≈ 5.7–6.5%, other cattle 6.3–7.0%, feedlot 4.0–5.0%, pre-weaned calves effectively 0%.

## Bo

Maximum CH₄ producing capacity of manure (IPCC Vol.4 Ch.10 Table 10.16a, 2019R). For **Other regions, low productivity** (the Sub-Saharan Africa / South Asia default that most users of this tool fall under) BOTH dairy and non-dairy cattle = **0.13**. The 0.24 value applies ONLY to dairy cattle in North America / Western Europe (high-productivity systems); non-dairy cattle there range 0.17–0.19. Buffalo = 0.10 (do not use buffalo's value for cattle). For a high-productivity commercial dairy herd the compiler may override dairy_cows to 0.24.

## EF3_PRP

N₂O emission factor for dung/urine on pasture, EF3PRP,CPP (IPCC Vol.4 Ch.11 Table 11.1, 2019R, **wet climate**: 0.006, range **0.000–0.027**). For dry climate use 0.002 (range 0.000–0.007). For aggregated-across-climates use 0.004 (range 0.000–0.014). 2006 = 0.02. The wide wet-climate range is genuine — EF3PRP is one of the most uncertain N₂O parameters and a dominant driver of pasture-N₂O uncertainty.

## EF4

N₂O EF for atmospheric N deposition (IPCC Vol.4 Ch.11 Table 11.3, 2019R, **wet climate**: 0.014, range 0.011-0.017). For dry climate use 0.005. For aggregated use 0.010 (range 0.002-0.018). 2006 = 0.010.

