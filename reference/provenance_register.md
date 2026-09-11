# Parameter provenance register

**Purpose:** every numeric default the tool ships, checked against the IPCC source text, with a citation that a reader can resolve.

**Method.** Values were read from the live R constants, then compared against the plain-text extractions in `reference/.ipcc_text/` (six chapters: Vol.4 Ch.10, Vol.4 Ch.11 and Vol.1 Ch.3, in both the 2006 and 2019 Refinement editions). Page numbers are PDF page indices from the `=== page N ===` markers in those extractions.

**Verdicts.** `CONFIRMED` = found at the cited table with the stated basis. `DEVIATION_DOCUMENTED` = differs from IPCC deliberately, reason on record. `DEVIATION_UNDOCUMENTED` = differs with no recorded reason, action required. `NOT_IPCC` = a non-IPCC source, must never be presented as an IPCC default. `UNVERIFIABLE_FROM_TEXT` = the source table is too badly scrambled by PDF text extraction to read reliably; needs checking by eye against the PDF.

**Scope of this pass.** Energy coefficients, methane conversion factors, manure-management emission factors and nitrogen-loss fractions, and the five asymmetric Chapter 11 parameters. Animal-characteristic defaults (BW, MW, WG, Milk, Fat by sub-category) are not yet resolved; see the open items at the end.

---

## 1. Confirmed correct

### 1.1 Cfi, net energy for maintenance coefficient

**Source: 2019R Vol.4 Ch.10 Table 10.4 (Updated), PDF page 24.** The table gives three cattle values:

| IPCC row | Value | IPCC comment |
|---|---|---|
| Cattle/Buffalo | 0.322 | "All non-lactating cows, steers, heifers and calves" |
| Cattle/Buffalo (lactating cows) | 0.386 | "Maintenance energy requirements are 20% higher during lactation" |
| Cattle/Buffalo (bulls) | 0.370 | "15% higher for intact males than non lactating females" |

All nine entries in `CFI_BY_SUBCAT` are **CONFIRMED**: `dairy_cows` 0.386, `bulls` 0.370, and 0.322 for `other_cows`, `oxen`, `heifers`, `growing_males`, `calves_female`, `calves_male`, `feedlot_cattle`.

**Why the 2026-06-16 correction was right.** Growing males and calves previously carried 0.370. That was wrong: IPCC puts "steers, heifers and calves" explicitly in the 0.322 row, and reserves 0.370 for the row labelled *bulls*, glossed as "intact males". Oxen are castrated, so they are steers and take 0.322. The correction moved five sub-categories to 0.322 and left only mature intact bulls at 0.370. This is the strict reading of the table and it is correct.

**One interpretive choice worth stating in the paper.** A growing intact male is arguably an "intact male" and could take 0.370. The tool assigns 0.322 because IPCC's category label is *bulls*, which conventionally means mature breeding males. The choice is defensible and documented, but it is a reading, not a quotation.

`PARAM_CATALOGUE$Cfi` default is 0.386, the lactating-cow value. Correct for a dairy-oriented default, and the highest of the three, so it is conservative for non-dairy until the sub-category resolver overrides it.

### 1.2 Ca, activity coefficient

**Source: 2019R Vol.4 Ch.10 Table 10.5 (Updated), PDF page 25.** Stall 0, Pasture 0.17, "Grazing large areas" 0.36.

`FEEDING_SITUATION_CA` = `stall_fed` 0.00, `pasture_flat` 0.17, `pasture_hilly` 0.36. All three **CONFIRMED**. `PARAM_CATALOGUE$Ca` default 0.170 is the Pasture value, **CONFIRMED**.

### 1.3 Bo, maximum methane producing capacity

**Source: 2019R Vol.4 Ch.10 Table 10.16A (Updated), PDF page 67.** Dairy cattle and non-dairy cattle both read **0.13** in the "Other Regions, low productivity systems" column. Footnote 1 states low productivity is the Tier 1 default for other regions.

`PARAM_CATALOGUE$Bo` = 0.13. **CONFIRMED**, on the stated basis that the tool's user base maps to "Other regions, low productivity".

### 1.4 Ym, methane conversion factor

**Source: 2019R Vol.4 Ch.10 Table 10.12 (Updated).** Low-producing dairy cows (<5000 kg/head/yr, DE ≤ 62, NDF > 38) give **Ym = 6.5%**.

`PARAM_CATALOGUE$Ym` = 6.5. **CONFIRMED**, and consistent with the same low-productivity basis used for Bo.

### 1.5 UE and ASH

**UE.** 2019R Vol.4 Ch.10, Equation 10.24 notes: "Typically 0.04 GE can be considered urinary energy excretion by most ruminants". Code 0.04. **CONFIRMED**.

**ASH.** Code 0.08. **CONFIRMED, but against the 2006 edition, not 2019R.** 2006 Vol.4 Ch.10 Eq 10.24 reads "the ash content of manure ... (e.g., **0.08 for cattle**)". The 2019 Refinement rewrote the same note to "(e.g., 0.06 for **sows**: Dämmgen et al. 2011)", i.e. it swapped the worked example from cattle to swine. 0.06 is therefore not a cattle value and does not supersede 0.08. See finding 2.5 on the citation.

### 1.6 EF3, direct N2O from manure management

**Source: 2019R Vol.4 Ch.10 Table 10.21 (Updated), PDF pages 91-92.** Every entry in `MMS_DEFAULTS$ef3` **CONFIRMED**:

| System | Code | IPCC row |
|---|---|---|
| daily_spread | 0 | Daily spread, 0 |
| solid_storage | 0.010 | Solid storage, 0.010 |
| solid_storage_covered | 0.010 | Solid storage - Covered/compacted, 0.01 |
| dry_lot | 0.02 | Dry lot, 0.02 |
| liquid_slurry | 0.005 | Liquid/Slurry, with natural crust cover, 0.005 |
| lagoon | 0 | Uncovered anaerobic lagoon, 0 |
| deep_bedding | 0.01 | Cattle and swine deep bedding, no mixing, 0.01 |
| composting | 0.006 | Composting - In-Vessel, 0.006 |
| aerobic_treatment | 0.005 | Aerobic treatment, forced aeration, 0.005 |
| anaerobic_digester | 0.0006 | Anaerobic digester, 0.0006 |
| burned_for_fuel | 0 | Reported under Fuel Combustion, not here |

**The 2026-06-16 correction was right.** `solid_storage` and `solid_storage_covered` were 0.005 and are now 0.010. Table 10.21 gives 0.010 for both. The old 0.005 belongs to the *Bulking agent addition* and *Additives* variants, which are different systems.

### 1.7 Frac_GasMS and Frac_LeachMS central values

**Source: 2019R Vol.4 Ch.10 Table 10.22 (Updated), "Other Cattle" column, PDF pages 97-98.** Every central value **CONFIRMED**:

| System | Code gas / leach | IPCC "Other Cattle" |
|---|---|---|
| lagoon | 0.35 / 0 | 0.35 (0.20-0.80) / 0 |
| liquid_slurry | 0.48 / 0 | 0.48 (0.15-0.60), no crust / 0 |
| solid_storage | 0.45 / 0.02 | 0.45 (0.10-0.65) / 0.02 |
| solid_storage_covered | 0.22 / 0 | 0.22 (0.03-0.26) / 0 |
| dry_lot | 0.30 / 0.035 | 0.30 (0.20-0.50) / 0.035 (0-0.07) |
| deep_bedding | 0.25 / 0.035 | 0.25 (0.10-0.30) / 0.035 |
| daily_spread | 0.07 / 0 | 0.07 (0.05-0.60) / 0 |
| composting | 0.65 / 0.06 | 0.65 (0.14-0.70) Static Pile / 0.06 |
| aerobic_treatment | 0.85 / 0 | 0.85 (0.27-1) forced aeration / 0 |
| pasture | 0 / 0 | not in this table; PRP is Chapter 11 |

**The 2026-06-16 line-by-line correction was right on every central value**, including the one that prompted it: lagoon volatilisation was 0.78, which appears in no cattle column of Table 10.22. The correct "Other Cattle" figure is 0.35. Setting `pasture` to 0/0 is also correct, because pasture volatilisation and leaching are the Chapter 11 `Frac_*_PRP` pathway, not a managed-storage fraction.

**Four bound pairs match IPCC exactly**: `solid_storage_covered` (0.03-0.26), `deep_bedding` (0.10-0.30), `aerobic_treatment` (0.27-1.00) and `dry_lot` leaching (0-0.07, per the table's footnote 4). See finding 2.1 for the ones that do not.

### 1.8 The five asymmetric Chapter 11 parameters

**Sources: 2019R Vol.4 Ch.11 Table 11.1 (Updated) and Table 11.3 (Updated).**

| Parameter | Code (value, lower, upper) | IPCC | Verdict |
|---|---|---|---|
| EF3_PRP | 0.006, 0.0005, 0.027 | Table 11.1, EF3PRP,CPP wet climates: 0.006 (0.000-0.027) | CONFIRMED |
| EF4 | 0.014, 0.011, 0.017 | Table 11.3, wet climate: 0.014 (0.011-0.017) | CONFIRMED, exact including bounds |
| EF5 | 0.011, 0.0005, 0.020 | Table 11.3: 0.011 (0.000-0.020) | CONFIRMED |
| Frac_GASM_PRP | 0.21, 0.005, 0.31 | Table 11.3, FracGASM: 0.21 (0.00-0.31) | CONFIRMED |
| Frac_LEACH_PRP | 0.24, 0.010, 0.73 | Table 11.3, FracLEACH-(H): 0.24 (0.01-0.73) | CONFIRMED, exact including bounds |

**The wet-climate choice is correct and traceable.** Table 11.1 publishes EF3PRP,CPP as aggregated 0.004, wet 0.006, dry 0.002; Table 11.3 publishes EF4 as aggregated 0.010, wet 0.014, dry 0.005. The tool ships the wet-climate figures throughout, which is internally consistent and appropriate for a predominantly wet-climate user base. An inventory that classifies as dry climate should override both.

**The three raised lower bounds are a documented, deliberate deviation and should not be "corrected".** IPCC gives 0.000 as the lower bound for EF3_PRP, EF5 and Frac_GASM_PRP. The tool uses 0.0005, 0.0005 and 0.005 because the PERT and lognormal samplers are undefined at an exact-zero lower bound. Verdict `DEVIATION_DOCUMENTED`. The effect on the sampled distribution is negligible; the effect of not doing it is a crash.

### 1.9 Two MCF values that match exactly

`aerobic_treatment` MCF 0% (2019R Table 10.17, "Aerobic treatment 0.00%") and `burned_for_fuel` MCF 10% in all zones (2006 Table 10.17, "Burned for fuel 10% / 10% / 10%"). Both **CONFIRMED**. `daily_spread` also matches the 2006 table exactly across all three bands (see finding 2.3).

---

## 2. Findings: values that are wrong, or right for an undocumented reason

### 2.1 Frac bounds use ±50% where IPCC publishes an explicit range

**This is the most systematic finding.** The code comment at `R/utils_ipcc_defaults.R:161-166` states the rule as "bounds use the IPCC ranges where the table gives them, else ±50%". Five rows break that rule: IPCC *does* give a range and the code uses ±50% anyway.

| System | IPCC range (Other Cattle) | Code bounds | Effect |
|---|---|---|---|
| daily_spread | 0.05 - 0.60 | 0.04 - 0.10 | Upper bound 6x too narrow |
| solid_storage | 0.10 - 0.65 | 0.23 - 0.68 | Lower too high, upper slightly over |
| liquid_slurry | 0.15 - 0.60 | 0.24 - 0.72 | Understates the low tail, overstates the high |
| dry_lot | 0.20 - 0.50 | 0.15 - 0.45 | Whole interval shifted down |
| composting | 0.14 - 0.70 | 0.33 - 0.98 | Upper bound 0.98 exceeds the IPCC maximum of 0.70 |

**Correct values are the IPCC ranges in the middle column.** These are volatilisation fractions feeding indirect N2O, so the errors propagate into the reported confidence interval on that pathway, not into the mean. `daily_spread` and `composting` are the two worth fixing first: one materially understates uncertainty, the other pushes the sampler above a physically published ceiling.

### 2.2 Bo uncertainty is 20%, IPCC states 15%

2019R Table 10.16A closes with "**Uncertainty values are ±15 percent.**" `PARAM_CATALOGUE$suggested_uncertainty_pct` for Bo is 20.

This may be deliberate, since the project sources uncertainty percentages from Penman (2000) and Monni (2007) where IPCC is silent. But here IPCC is not silent. Either adopt 15% or record why 20% is preferred. Verdict `DEVIATION_UNDOCUMENTED`.

### 2.3 Methane conversion factors do not consistently match the 2006 table

MCF is deliberately held on the 2006 convention rather than 2019R, and that decision is well documented: 2019R Table 10.17 gives a pasture MCF of 0.47% which must be paired with a per-MMS Bo of 0.19, and the engine carries a single per-animal Bo. That deviation is `DEVIATION_DOCUMENTED` and correct.

But within the 2006 convention the values do not line up. 2006 Table 10.17 gives three temperature bands, Cool (≤10 °C), Temperate, Warm (≥28 °C), which map naturally onto the code's `boreal`, `temperate`, `tropical`:

| System | 2006 IPCC Cool / Temperate / Warm | Code boreal / temperate / tropical | Match |
|---|---|---|---|
| daily_spread | 0.1 / 0.5 / 1.0 | 0.1 / 0.5 / 1.0 | exact |
| burned_for_fuel | 10 / 10 / 10 | 10 / 10 / 10 | exact |
| solid_storage | 2.0 / 4.0 / 5.0 | 3.0 / 4.0 / 5.0 | boreal is 3.0, should be 2.0 |
| dry_lot | 1.0 / 1.5 / 2.0 | 1.0 / 1.5 / **5.0** | tropical is 2.5x the IPCC value |
| pasture | 1.0 / 1.5 / 2.0 | 1.0 / 1.0 / 1.5 | whole row shifted down one band |
| lagoon | 66 ... 80 (gradient) | 66 / 66 / 80 | temperate 66 is the ≤10 °C value; the temperate band runs 68-78 |

`dry_lot` is the one that matters most: 5.0% against a published 2.0% inflates manure CH4 for any dry-lot inventory by a factor of 2.5 on that pathway.

This row of the register is **not yet complete**: deep bedding, liquid slurry, composting and the 2019R-only systems still need checking, and the mapping from IPCC's temperature bands to the tool's four named climate zones should be written down explicitly before any value is changed. Flagged as the largest remaining piece of work.

### 2.4 Two internal inconsistencies in which system variant is being modelled

**Composting.** EF3 takes the *In-Vessel* value (0.006) while the volatilisation and leaching fractions take the *Static Pile* values (0.65, 0.06). Table 10.21 and Table 10.22 both disaggregate composting into four variants, and the tool's single `composting` row mixes two of them. In-Vessel would be 0.60 gas and 0 leach; Static Pile would be 0.010 EF3. Pick one variant, or split the row.

**Pasture EF3 — this one is deliberate, and is NOT a defect.** `MMS_DEFAULTS$ef3` carries 0.02 for `pasture`. The inline comment at `R/utils_ipcc_defaults.R:134` states it explicitly: *"pasture 0.02 is the PRP/Ch.11 pathway value (not a Table 10.21 MS), left as-is."* Table 10.21 does direct PRP to Chapter 11, so declining to put a managed-storage EF3 there is correct.

The residual question, which is a question and not an error: 0.02 is the **2006** EF3_PRP value, while the catalogue's `EF3_PRP` moved to the 2019R wet-climate 0.006 on 2026-06-16. The two PRP numbers in the codebase are now from different editions. Worth confirming that the manure-sheet fallback was intended to stay on 2006 when the catalogue moved.

### 2.5 ASH is cited to the wrong edition

The value 0.08 is correct, but it comes from the **2006** Guidelines, where the worked example is "0.08 for cattle". The 2019 Refinement replaced that example with "0.06 for sows". Anywhere the tool cites ASH as 2019R should cite 2006 instead, otherwise a reviewer checking the citation finds 0.06 and concludes the tool is wrong when it is not.

### 2.6 anaerobic_digester volatilisation takes a range minimum as a central value

Table 10.22 gives anaerobic digester as "0.05 – 0.50" with no central value, and footnote 3 explains the spread depends on digestate dry matter and storage cover. The code takes 0.05, the bottom of that range, as the central value, then applies ±50% to get 0.02-0.08. The resulting distribution cannot reach most of the published range. Either take a mid-range central with bounds 0.05-0.50, or record why the low end is the right default.

---

## 3. Not verifiable from the text extraction

`pypdf` does not preserve cell order in wide tables. Table 10.13A, for instance, extracts as an unreadable run of numbers across nineteen regional columns. The following therefore need checking by eye against the PDF and are **not** claimed as verified here:

- **Annex 10A.1 / 10A.2 / 10A.3** animal characteristics, which back the regional BW benchmark and the Milk 3.5 / Fat 4.3 defaults.
- **`IPCC_DEFAULTS_BY_REGION`** BW values (africa 275, asia 350, europe 600, americas 500, oceania 500, global 400). The code itself describes these as "illustrative regional midpoints", which suggests Tier 1 rather than a direct table lookup. Worth confirming, because this is the only benchmark the QA/QC tab still fires on.

## 4. Project assumptions, not IPCC values

These carry no IPCC table for cattle and should be labelled as project assumptions rather than IPCC defaults:

- `LW_BY_SUBCAT`, `MW_BY_SUBCAT`, `WG_BY_SUBCAT`, `C_GROWTH_BY_SUBCAT` per sub-category. IPCC publishes the C growth coefficient by sex class (0.8 female, 1.0 castrate, 1.2 bull) in Eq 10.6, which the code follows, but per-sub-category live weights and weight gains are not published.
- `PCT_PREGNANT_BY_SUBCAT` (0.85 / 0.85 / 0.50). No IPCC source. Currently cites the translator prompt, which is a documentation artifact citing itself.
- All `suggested_uncertainty_pct` values, which come from Penman (2000) and Monni (2007). This is already correctly disclosed in the user guide.
- `GWP_VALUES`. AR4 25/298, AR5 28/265, AR6 27/273 are correct against the respective Assessment Reports, but those reports are not in the local corpus, so they were not verified here. The AR6 CH4 value of 27 is the non-fossil figure, which is the right one for enteric and manure methane.

---

## 4a. Collision check against the audit and the review record

Before proposing any change, every finding was checked against the values the regression gate pins and against what the code records as deliberate. **No proposed change collides with a pinned or agreed value.**

**What the audit actually pins:**

| Check | Pins |
|---|---|
| F28 | `PARAM_CATALOGUE` EF3_PRP 0.006 (0.0005, 0.027), EF4 0.014 (0.011, 0.017), EF5 0.011 / upper 0.020, Frac_GASM_PRP bounds (0.005, 0.31), Frac_LEACH_PRP bounds (0.01, 0.73) |
| F29 | `MMS_DEFAULTS$ef3` for solid_storage, covered, dry_lot, liquid_slurry; and the **central** `frac_gas` / `frac_leach` for lagoon, aerobic, covered, deep_bedding, dry_lot, composting, solid_storage, liquid_slurry |
| F30 | Resolver outputs: bulls.Cfi 0.370, growing_males.Cfi 0.322, bulls.C 1.2, oxen.C 1.0, biological zeros, dairy_cows.pct_pregnant 0.85, heifers 0.5, heifers.WG 0.25, dairy_cows.DE 55, EF3_PRP 0.006/0.0005 |

**Verified as not pinned:**

- **No audit check pins any `frac_gas_low/high` or `frac_leach_low/high`.** F29 asserts central values only. Finding 2.1 is therefore free to act on.
- **No audit check pins any MCF value.** The single MCF reference in `scripts/audit.R:402` is an explicit fixture input to the B4 sampler test, not an assertion about `MMS_DEFAULTS`. The built-in Country X and Y examples hardcode their own `MCF_pct` (`R/utils_ipcc_defaults.R:649, 677`) rather than reading `MMS_DEFAULTS`, so correcting the table cannot move the F21 sanity bands.
- **No audit check pins any `suggested_uncertainty_pct`,** so Bo's 20% is free to change.

**What the record says is deliberate, and is therefore left alone:**

- The **2006 MCF convention** is deliberate and well justified (2019R's pasture MCF of 0.47% must pair with a per-MMS Bo of 0.19, which the engine does not have). Finding 2.3 does not challenge the convention. It observes that three cells do not match *either* edition's Table 10.17, which is a separate matter from the edition choice.
- The **three raised lower bounds** (EF3_PRP, EF5, Frac_GASM_PRP) are deliberate and pinned by F28. Not touched.
- **`pct_pregnant` 0.85 / 0.50** are pinned by F30. Section 4 proposes relabelling their provenance only, not changing the numbers.
- **Pasture EF3 0.02** is documented as deliberate. Downgraded from a defect to a question (2.4).

**One caveat on the MCF finding.** The comment at `R/utils_ipcc_defaults.R:127` says "Verified line-by-line vs Table 10.17 on 2026-06-16". That sits inside a paragraph whose subject is the 2019R-versus-2006 decision, so it most likely records verification of the *edition choice* rather than of each cell. But it is a verification claim, and three cells do not reconcile with either published table, so this should be confirmed with the original reviewer before any MCF cell is edited. The strongest evidence that the band mapping used here is the right one is that `daily_spread` (0.1 / 0.5 / 1.0) and `burned_for_fuel` (10 / 10 / 10) match the published rows **exactly** under the same mapping.

## 4b. Proof that the flagged values are unjustified, not deliberate

A second pass searched every text-readable file in the repository (`R/`, `scripts/`, `doc/`, `translator_prompts/`, `www/`, `knowledge/`, `reviews/`, `old/`, `AUDIT_REPORT.md`) plus the full git history, for any statement justifying the values in section 2.

### The five ±50% Frac bounds: proven to be migration residue

**Every divergent bound is exactly ±50% of its central value. Every bound that matches IPCC is not.**

| System | central | code bounds | ±50%? | IPCC range | |
|---|---|---|---|---|---|
| aerobic_treatment | 0.85 | 0.27 - 1.00 | no | 0.27 - 1.00 | matches |
| deep_bedding | 0.25 | 0.10 - 0.30 | no | 0.10 - 0.30 | matches |
| lagoon | 0.35 | 0.20 - 0.80 | no | 0.20 - 0.80 | matches |
| solid_storage_covered | 0.22 | 0.03 - 0.26 | no | 0.03 - 0.26 | matches |
| composting | 0.65 | 0.33 - 0.98 | **yes** | 0.14 - 0.70 | diverges |
| daily_spread | 0.07 | 0.04 - 0.10 | **yes** | 0.05 - 0.60 | diverges |
| dry_lot | 0.30 | 0.15 - 0.45 | **yes** | 0.20 - 0.50 | diverges |
| liquid_slurry | 0.48 | 0.24 - 0.72 | **yes** | 0.15 - 0.60 | diverges |
| solid_storage | 0.45 | 0.23 - 0.68 | **yes** | 0.10 - 0.65 | diverges |

The split is perfect: the four rows carrying IPCC ranges are **exactly** the four rows the 2026-06-16 changelog says had their gas value corrected. The five rows still on ±50% are exactly the rows that pass did not revisit.

**The git history proves the mechanism.** Commit `5e72ab7` (the 2026-06-16 correction) rewrote the rule. Before it, the comment read:

> "Uncertainty bounds set at **+-50% per Penman et al. (2000) / Monni et al. (2007)** for asymmetric N-fraction parameters."

That is a blanket ±50% for every row, and `old/claude_old/template_schema.md` confirms it: in the pre-correction table **all twelve rows** are ±50%, including `deep_bedding` at 0.3 / 0.15 / 0.45, identical to `dry_lot`. `5e72ab7` replaced that rule with:

> "bounds use the IPCC ranges where the table gives them, else +-50%"

and applied the new rule to the four rows it touched, moving `deep_bedding` to the IPCC 0.10 - 0.30 while leaving the otherwise-identical `dry_lot` on 0.15 - 0.45.

**Conclusion.** The five ±50% bounds are residue of a superseded rule, left behind by an incomplete migration. They are not a deliberate choice; the project's current stated rule and its own demonstrated practice (4 out of 4 rows it examined) both say the IPCC published range should be used. Table 10.22 publishes a range for all five.

### MCF: never edited since the initial commit

`git log -G` over the `mcf_*` assignment lines returns exactly two commits:

- `1b322dd` initial commit, which wrote the values
- `51f5e11`, which **only inserted the four 2019R systems** into the vectors. Diffing it shows every pre-existing value is byte-identical before and after

So `dry_lot` tropical 5.0, `solid_storage` boreal 3.0 and the `pasture` row have stood unchanged since day one and have never been corrected by any commit.

The "Verified line-by-line vs Table 10.17 on 2026-06-16" claim was added by `5e72ab7`, **and that commit changed no MCF value**. Combined with the fact that the sentence sits in a paragraph whose subject is the 2019R-versus-2006 decision, the most likely reading is that the verification settled the edition question rather than each cell. It remains a verification claim, so confirm with the reviewer before editing, but there is no commit, comment, review document or published doc anywhere that states 5.0 is the intended dry-lot value.

No other file justifies these numbers either. `old/TECHNICAL_SUMMARY.md`, `old/claude_old/template_schema.md`, `translator_prompts/template_schema.md` and `www/template_schema.md` all reproduce them, but every one of those is generated from the same R constant, so they are downstream copies rather than independent corroboration.

### Bo uncertainty: no mention anywhere

A search for any statement about Bo's uncertainty percentage returns **nothing** in any source file, doc, review response or commit message. The only recorded uncertainty decision in that line of `PARAM_CATALOGUE` is the Ym change from 8 to 20 on 2026-06-15. IPCC Table 10.16A's "Uncertainty values are ±15 percent" has never been referenced in the project.

### One further defect found during this pass

`doc/methodology.Rmd:151` cites **Table 10.23** as the source for `Frac_LeachMS`. That is the same wrong citation `5e72ab7` explicitly corrected in the R source ("leaching is Table 10.22, not 10.23; Table 10.23 is the N2:N2O loss ratio"). The correction reached the code but not the published methodology document.

## 4c. Change-surface map: every place each value appears

Traced by following the consumers of each constant, not by text search alone. **These values are not translator-only. They reach the engine, the downloadable Excel template, the app UI and the published documents.**

### Surfaces that exist at all

| Surface | Fed by | Reaches the user as |
|---|---|---|
| Monte Carlo engine | `mms_frac_defaults_2019()` centrals, via `calc_ghg_master.R:212`, `calc_manure_n2o.R:97,104` | Emission numbers |
| Blank Excel template, `Manure_Management` example rows | `utils_template.R:1138-1150` | Pre-filled cells the user edits |
| Blank Excel template, `Vocab` sheet | `utils_template.R:1435-1449` | A table captioned "IPCC Table 10.17 - MCF (%) by climate zone", which the sheet's own banner (`:662`) tells users to copy from |
| Blank Excel template, `_Lists` hidden sheet | `utils_template.R:621` | Dropdown backing data |
| Blank Excel template, `Parameters` rows | `utils_template.R:894, 1600, 1619` | Pre-filled `suggested_unc_%` per parameter |
| App Definitions tab | `app_server.R:2913`, reads `PARAM_CATALOGUE` | Columns: parameter, definition, unit, **ipcc_default**, suggested_distribution, param_tier, framing, **ipcc_ref**. No uncertainty column, no MMS rows |
| Translator system prompt | `translator_prompts/*.md`, read live by `openai_client.R:31` | Instructions to the model |
| Translator DIY kit | `www/*.md`, `www/translator_kit.zip` | Downloaded by users |
| Technical guide | `doc/methodology.Rmd` → `www/methodology.pdf/.docx` | Published document |
| User guide | `doc/user_guide.Rmd` → `www/user_guide.pdf/.docx` | Published document |

**Dead, therefore not a surface:** `build_ipcc_reference_sheet()` (`utils_template.R:1870`) assembles MCF, EF3, GWP, Ca, C_growth, LW and Ym tables with several independent hardcodes, and **has no caller anywhere**. It should be deleted or wired up, but it is not currently shipping anything.

### Per-change surface list

**Change A. Five Frac gas bound pairs** (`daily_spread`, `solid_storage`, `dry_lot`, `liquid_slurry`, `composting`)

| Must change | Why |
|---|---|
| `R/utils_ipcc_defaults.R:212-215` | The constant |
| `translator_prompts/template_schema.md:119-132` | Prompt table. Already carries 6 wrong **centrals** too, from the un-propagated 2026-06-16 fix |
| `www/template_schema.md`, `www/translator_kit.zip` | Shipped copies, rebuild |
| `scripts/audit.R` F29 | Add bound assertions; it currently pins centrals only |

Regenerates automatically, no edit needed: the template's `Manure_Management` example rows (`utils_template.R:1138-1150`) read the constant at build time, so the `solid_storage` bounds in every new template follow. Engine unaffected: it uses centrals only. Definitions tab unaffected: no MMS rows.

**Change B. Bo uncertainty 20 → 15**

| Must change | Why |
|---|---|
| `R/utils_template.R:301` | The `suggested_uncertainty_pct` vector |
| `doc/user_guide.Rmd:240` | States "±20\%" explicitly in the parameter table |
| `www/user_guide.pdf`, `www/user_guide.docx` | Rebuild after the Rmd edit |
| `translator_prompts/param_catalogue.md` + `www/` copies + kit | Generated from the catalogue |

Follows automatically: every blank template's `Parameters` sheet, which writes `suggested_uncertainty_pct` per row. Not affected: `doc/methodology.Rmd`, whose parameter table has no uncertainty column; the Definitions tab, same reason.

**Change C. ASH citation — WITHDRAWN, no defect**

`PARAM_CATALOGUE$ipcc_ref` for ASH is `"Eq 10.24"`, which is edition-neutral and correct in both editions. And `doc/methodology.Rmd:144` already states it precisely: *"0.08 (cattle; IPCC example 0.06 is pig-specific)"*. Nothing to fix. My earlier finding overstated this.

**Change D. MCF cells** (`dry_lot` tropical + tropical_dry, `solid_storage` boreal, `pasture` row) — **blocked pending reviewer confirmation**

| Would have to change | Why |
|---|---|
| `R/utils_ipcc_defaults.R:128-131` | The constant |
| `translator_prompts/template_schema.md:100-113` + `www/` + kit | Prompt MMS table |

Regenerates automatically: the `Vocab` sheet MCF table, the `Vocab` mms_type table, and the `_Lists` sheet, all of which read `MMS_DEFAULTS`.

**This is the highest-exposure error in the register.** The wrong `dry_lot` 5.0 is presented to every user in the template's `Vocab` sheet under the caption "IPCC Table 10.17 - MCF (%) by climate zone", and the sheet banner at `utils_template.R:662` instructs them to copy values from it. It is therefore not only used as an internal default; it is published to users as an IPCC reference value.

**Change E. Composting variant** (EF3 In-Vessel 0.006 vs Frac Static Pile 0.65/0.06) — **blocked pending a decision**. Changing EF3 would move an emission mean and would break audit F29, which pins `composting` leach 0.06.

**Change F. Two stale statements in the technical guide, found while building this map**

| Must change | Detail |
|---|---|
| `doc/methodology.Rmd:148` | States EF3 "e.g. **0.005** solid storage". The value was corrected to **0.010** on 2026-06-16 and is pinned at 0.010 by audit F29. The published methodology contradicts the shipped code |
| `doc/methodology.Rmd:151` | Cites **Table 10.23** for `Frac_LeachMS`. Commit `5e72ab7` corrected exactly this in the R source ("leaching is Table 10.22, not 10.23; Table 10.23 is the N2:N2O loss ratio"). The fix never reached the document |
| `www/methodology.pdf`, `www/methodology.docx` | Rebuild after the edits |

Correct as they stand, checked while here: `methodology.Rmd:149` (Frac_GasMS 0.45 solid storage), `:155` (Frac_GasPRP 0.21), `:144` (ASH), `:146` (Bo 0.13).

**Minor, optional:** `PARAM_CATALOGUE$ipcc_ref` for Bo reads `"Table 10.16"`; the 2019R table is 10.16A. `doc/methodology.Rmd:146` already writes "Table 10.16(a) (Updated)" correctly.

### Build order

The constants are upstream of everything else, so:

1. Edit the R constants (A, B).
2. Edit `doc/methodology.Rmd` (F) and `doc/user_guide.Rmd` (B).
3. Add the F29 bound assertions, run `Rscript scripts/audit.R`.
4. Unfreeze and refactor `scripts/build_translator_kit.R`, then regenerate `translator_prompts/`, `www/*.md` and the kit zip. **This is gated on the generator refactor**, because running the build script today destroys hand-added prompt content.
5. Rebuild `www/methodology.*` and `www/user_guide.*` via `scripts/build_methodology.R` and `scripts/build_user_guide.R` (needs LaTeX).
6. Redeploy: the live app reads `translator_prompts/` at runtime and serves `www/` documents.

## 4d. Decisions taken and applied, 2026-09-10

Authorised by the project lead after the evidence in 4a and 4b was reviewed. Audit went from 99/99 to **101/101** with two new guards added.

### Decision 1: MCF corrected to the published IPCC values

`dry_lot` tropical and tropical_dry **5.0 → 2.0**. 2006 and 2019R Table 10.17 both publish 1.0 / 1.5 / 2.0 for dry lot. The 5.0 duplicated the `solid_storage` value sitting directly above it in the same vector.

`solid_storage` boreal **3.0 → 2.0**, the published Cool value.

**Recorded as checked.** The 2026-06-16 note is now annotated to say it recorded verification of the *edition* choice (2006 versus 2019R), and a dated 2026-09-10 cell-level verification sits beside it naming each change and its published source. Locked by new audit check **F29b**.

Still deliberately unchanged, and flagged in the code comment: the `pasture` row, `lagoon` temperate, and `deep_bedding`, which appears to mix the "<1 month" and ">1 month" rows despite its label. These need the full systematic pass.

### Decision 2: composting is Static Pile (forced aeration) throughout

The row previously mixed two IPCC variants. It now models one:

| Field | Was | Now | Source |
|---|---|---|---|
| Label | "Composting" | "Composting - Static Pile (forced aeration)" | made explicit in the UI, template dropdown and prompt |
| EF3 | 0.006 (In-Vessel) | **0.010** | 2019R Table 10.21, Composting - Static Pile |
| MCF, all zones | 1.5 / 1.5 / 1.0 / 0.5 (windrow) | **0.5 flat** | 2006 Table 10.17, Static pile, "not temperature dependant" |
| Frac_Gas | 0.65 | 0.65, unchanged | already Static Pile |
| Frac_Gas bounds | 0.33 - 0.98 | **0.14 - 0.70** | Table 10.22 Static Pile, Other Cattle |
| Frac_Leach | 0.06 | 0.06, unchanged | already Static Pile |

The MCF change was not in the original finding. It surfaced only when aligning the variant: the old 0.5 / 1.0 / 1.5 is the *windrow* row, not static pile.

### Decision 3: the five Frac_Gas bounds brought onto the stated rule

`daily_spread` 0.05-0.60, `solid_storage` 0.10-0.65, `dry_lot` 0.20-0.50, `liquid_slurry` 0.15-0.60, `composting` 0.14-0.70. Locked by new audit check **F29a**, which asserts all nine gas ranges so no row can silently fall back to ±50% again.

Leach bounds unchanged: where Table 10.22 gives a single value and no range, ±50% remains correct under the rule. `anaerobic_digester` unchanged: the table gives "0.05 - 0.50" as a range with no central, so picking a central is a judgement, not a transcription. Still open.

### Decision 4: Bo uncertainty 20% → 15%

2019R Table 10.16A states "Uncertainty values are ±15 percent". An IPCC-published figure supersedes the Penman/Monni fallback used where IPCC is silent.

### Decision 5: two stale statements in the technical guide

`doc/methodology.Rmd:148` EF3 "0.005 solid storage" → **0.010**, matching the code and audit F29. `doc/methodology.Rmd:151` citation **Table 10.23 → 10.22**. `doc/user_guide.Rmd:240` Bo **±20% → ±15%**.

### Withdrawn

The ASH finding. `ipcc_ref` is "Eq 10.24", edition-neutral and correct in both, and `doc/methodology.Rmd:144` already states "0.08 (cattle; IPCC example 0.06 is pig-specific)". Nothing was wrong.

### Not yet propagated

The translator prompt assets, `www/*.md` and `translator_kit.zip` still carry the old values, and are additionally still on the pre-2026-06-16 Frac centrals. They are blocked on the generator refactor, because running `scripts/build_translator_kit.R` today destroys hand-added prompt content. The built `www/methodology.*` and `www/user_guide.*` also need regeneration, which needs LaTeX.

## 5. Priority actions

Ordered by confidence, not by size. Nothing here collides with a pinned or agreed value (section 4a).

**Safe to act on now:**

1. Fix the five Frac bound pairs to the published IPCC ranges (2.1). The largest group of wrong values, unpinned by the audit, contradicts the code's own stated rule, and the fix is a direct transcription from Table 10.22.
2. Decide Bo uncertainty: 15% per Table 10.16A, or a recorded reason for keeping 20% (2.2). Unpinned.
3. Repoint the ASH citation to the 2006 edition (2.5). Documentation only, the value is right.

**Needs a decision before acting:**

4. Composting variant: EF3 is In-Vessel while the fractions are Static Pile (2.4). Pick one variant or split the row. This one moves an emission mean.
5. Confirm with the original reviewer whether the 2026-06-16 MCF check covered individual cells, then correct `dry_lot` tropical (5.0 against a published 2.0), `solid_storage` boreal, and the `pasture` row (2.3). `dry_lot` moves a mean by 2.5x on that pathway, so it is the highest-impact item here, but it is also the one with a standing verification claim against it.
6. Confirm whether the pasture EF3 fallback was meant to stay on the 2006 value when the catalogue moved to 2019R wet (2.4).

**Still outstanding:**

7. Check Annex 10A by eye against the PDF (section 3). Not verifiable from the text extraction.
8. Complete the MCF table check for deep bedding, liquid slurry, composting and the four 2019R-only systems. Note that `deep_bedding` already looks like it mixes the "<1 month" and ">1 month" rows despite its label saying ">1 month".
9. Relabel section 4 items as project assumptions and give `PCT_PREGNANT_BY_SUBCAT` a real source or an explicit assumption note. Its values are pinned by F30, so this is a labelling change only.

Of items 1-6, only the composting EF3 choice and `dry_lot` MCF change an emission mean. Everything else changes reported uncertainty or documentation.

---
---

# Complete value-by-value verification, 2026-09-11

Second pass. Every one of the **249 numeric values** in `reference/defaults_master.csv` was read back against the IPCC source text, one at a time. The verdicts are not held in this document: they are written onto the master itself, in its `ipcc_verdict` and `ipcc_source` columns, so the single authority carries its own provenance. `reference/DEFAULTS_MASTER.md` renders them and audit check **F33** fails the build if a value is ever added without one.

**What made this pass possible.** The first pass gave up on the Annex 10A tables and marked them `UNVERIFIABLE_FROM_TEXT`, because the text extraction scrambles their column order into unreadable runs of numbers. Reading those pages from the PDF directly resolved all of them. Every value previously parked as unverifiable now has a verdict.

## Outcome

| Verdict | Values | Meaning |
|---|---|---|
| `CONFIRMED` | 162 | read at the cited IPCC table or equation |
| `DEVIATION_OPEN` | 27 | differs from IPCC with no recorded reason; needs a decision |
| `DEVIATION_DOCUMENTED` | 23 | differs deliberately, reason on record |
| `NOT_IPCC` | 21 | a non-IPCC source or a project assumption |
| `NO_IPCC_DEFAULT` | 10 | IPCC publishes no default for this quantity |
| `INTERPRETED` | 6 | a defensible reading of an IPCC category label, not a quotation |

Nothing in this section has been changed in the code. These are findings for decision, and several sit on values with review provenance, so changing them silently is exactly what the escalation rule exists to prevent.

## 1. Newly confirmed

**Table 10A.11 independently confirms the anaerobic digester correction.** PDF page 139, "High quality biogas digester, open storage", reads 3.55% cold / 4.38% temperate / 4.59% warm: exactly the values adopted, and exactly the band mapping. The table's own headers are cold/temperate/warm, which also corroborates the Cool to boreal and Warm to tropical mapping used throughout.

**The MCF band convention is real and consistent.** The 2006 Table 10.17 is per-degree-C, with nineteen columns. For every temperature-dependent system the tool reads the same three of them: boreal from the `<= 10` column, temperate from the `19` column, tropical from the `>= 28` column. Checked against all three such systems:

| System | boreal | temperate | tropical | IPCC at <= 10 / 19 / >= 28 |
|---|---|---|---|---|
| Liquid/Slurry with natural crust cover | 10 | 24 | 50 | 10 / 24 / 50 |
| Cattle and swine deep bedding > 1 month | 17 | 39 | 80 | 17 / 39 / 80 |
| Uncovered anaerobic lagoon | 66 | 77 | 80 | 66 / 77 / 80 |

Three systems agreeing on the same three columns is a convention, not three coincidences. It was undocumented until now, which is why those figures looked arbitrary. It is now recorded on every affected row.

**Footnote 8 of Table 10A.2 settles the oxen question.** "Draft bullocks were all assumed to be castrates and CFi values were adjusted accordingly." The June 2026 decision to move oxen to the 0.322 steers row was not merely a defensible reading: it is what IPCC itself did with the same animal.

**Equation 10.6 settles the growth coefficient.** "C = a coefficient with a value of 0.8 for females, 1.0 for castrates and 1.2 for bulls (NRC, 1996)." Six of the nine `C_GROWTH_BY_SUBCAT` entries are direct quotations. The three male growing categories are `INTERPRETED`, on the same castrate reading already applied to `Cfi`.

**All five Chapter 11 parameters confirmed exactly, bounds included.** Table 11.3 gives EF4 wet 0.014 (0.011-0.017), EF5 0.011 (0.000-0.020), FracGASM 0.21 (0.00-0.31), FracLEACH-(H) 0.24 (0.01-0.73); Table 11.1 gives EF3PRP 0.006 (0.000-0.027). The only departures are the small positive floors the tool substitutes for IPCC's 0.000 lower bounds, because a zero lower bound is degenerate for the bounded distributions. That is documented on each row.

**Table 10.22 confirmed line by line, and the variant harmonisation was right.** Every central and every published bound in `MMS_FRAC_DEFAULTS_2019` matches the "Other Cattle" column. Note that section 1.7 above, written before the harmonisation, records `liquid_slurry` volatilisation as 0.48. It is now **0.30 (0.09-0.36)**, the *with natural crust cover* figure, which is the variant the row declares and the variant its EF3 of 0.005 comes from. Section 1.7 is correct about the 0.48 cell; that cell is simply no longer the one this row uses.

**Cp 0.10** at Table 10.7 (Updated), "Cattle and Buffalo 0.10". **Aerobic treatment MCF 0/0/0**, **Burned for fuel 10/10/10**, **Solid storage 2/4/5** and **Covered/compacted 2/4/5** all confirmed against both editions where both publish them.

## 2. Findings that would move a reported number

### 2.1 The catalogue mixes the dairy and non-dairy annex tables

The generic defaults are drawn from two different IPCC tables describing two different animals, and three of them come from neither.

| Parameter | Catalogue | Table 10A.1 Africa **dairy** | Table 10A.2 Africa **non-dairy grazing** |
|---|---|---|---|
| BW | 275 | 260 | **275** |
| Milk | 3.5 | **3.5** | 1.2 |
| Fat | 4.3 | **4.3** | 4.1 |
| Ym | 6.5 | **6.5** | 7.0 |
| CP | 10.0 | 8.7 | **10.0** |
| MilkPR | 3.3 | 3.6 | 3.6 |
| pct_pregnant | 0.60 | 0.54 | 0.54 |
| DE | 55 | 51 | 58 |

Both source rows are individually defensible. The combination describes no animal IPCC published. This is the same variant-mixing pattern already found and fixed in the manure systems, one level up: there the fix was to declare a variant per row and make every coefficient follow it.

### 2.2 MilkPR 3.3 is supported by no reading

Both candidate rows give protein content **3.6%**, and the tool's own documented route, %MilkPR = 1.9 + 0.4 x %Fat, gives **3.62** at Fat 4.3. The value 3.3 is what that formula returns for Fat **3.5**, which is what Fat held before it was corrected to 4.3 at review round 8. This is a leftover from that correction, not an interpretive choice. It is the clearest single defect in the pass.

### 2.3 Ym is a per-category table applied as one number

Table 10.12 (Updated) gives Ym by livestock category, and the tool ships a single 6.5 for every sub-category:

| IPCC category | Ym | Tool | Effect |
|---|---|---|---|
| Dairy cows, low producing, DE <= 62 | **6.5** | 6.5 | correct |
| Non-dairy and multi-purpose, > 75% forage, DE <= 62 | **7.0** | 6.5 | 7.7% low |
| Feedlot, 0-15% forage, DE >= 72 | **4.0** | 6.5 | **63% high** |

Every non-dairy row of Annex 10A.2, in every region, carries 7.0. This has the identical structure to the `Cfi` defect already fixed: IPCC publishes a per-category table, the tool holds one value, and there is no `YM_BY_SUBCAT` to override it. The feedlot case is the large one, and it runs the wrong way, overstating enteric methane. Note that a feedlot Ym of 4.0 is conditional on DE >= 72, so the `DE` default would have to become per-sub-category at the same time.

### 2.4 Composting: the MCF is still on the other edition's reading

The composting row declares the **Static Pile** variant, and that variant was chosen explicitly. Two of its three coefficient families follow it under the 2019 Refinement. The MCF does not.

| Coefficient | Tool | Static Pile, 2019R | In-vessel, 2019R | Static pile, 2006 |
|---|---|---|---|---|
| EF3 | 0.010 | **0.010** | 0.006 | n/a |
| Frac_GasMS | 0.65 (0.14-0.70) | **0.65 (0.14-0.70)** | 0.60 (0.12-0.65) | n/a |
| MCF | 0.5 / 0.5 / 0.5 | 1.00 / 2.00 / 2.50 | **0.50** | **0.5 / 0.5 / 0.5** |

The row is offered under both editions. Under 2006 the MCF is right. Under 2019R it is the in-vessel figure, and a 2019R user gets a composting MCF between two and five times too low. This is the last surviving instance of the variant-mixing class, and it is in the row that still needs reviewer confirmation.

### 2.5 MW 300 carries an IPCC citation for a value IPCC does not publish

`PARAM_CATALOGUE$MW` cites `Table 10A.2`. That table has no mature-weight column: its columns are weight, weight gain, feeding situation, milk yield, fat, protein, work hours, pregnant, digestibility, CP, Ym, population mix, EF, VS, Nex and N retention. Neither does Table 10A.1. Mature weight enters Equation 10.6 as an input, but IPCC publishes no default for it.

Reviewer round 7 item #3 said exactly this: 300 kg MW was on his list of values he could not find in the guidelines. The companion value on that list, 400 kg BW for African dairy, was fixed. **MW kept its citation.** All nine `MW_BY_SUBCAT` entries are project assumptions and are now marked `NO_IPCC_DEFAULT`.

### 2.6 The anaerobic digester volatilisation range sits below IPCC's floor

Table 10.22 gives Anaerobic digester as a bare range, **0.05 to 0.50**, with no central value; footnote 3 assigns 0.05 to covered high-dry-matter digestate and up to 0.50 to uncovered. The tool takes 0.05 as the central and then samples 0.02 to 0.08 around it. Its entire sampled range therefore sits at or below IPCC's lower limit, and its upper bound is six times below IPCC's ceiling. Footnote 3 also advises using the uncovered liquid-slurry figure for uncovered digestate, which the tool does not do.

### 2.7 Sub-category weights are roundings presented as transcriptions

Against the Annex 10A.2 Africa column:

| Sub-category | Tool | IPCC row |
|---|---|---|
| other_cows BW | 275 | Mature Females - grazing 275 (exact) |
| bulls BW | 350 | Mature Males 540, Bulls - Grazing 340 |
| oxen BW | 300 | Draft Bullocks 340 |
| heifers, growing_males BW | 200 | Growing/Replacement 204 |
| calves BW | 60 | Calves on forage 82 |
| feedlot_cattle BW | 250 | no Africa row; North America 500, Latin America 460 |
| heifers WG | 0.25 | Growing/Replacement 0.24 |
| growing_males WG | 0.20 | Growing/Replacement 0.24 |
| calves WG | 0.30 | Calves on forage 0.33 |
| dairy_cows BW | 275 | Table 10A.1 Africa **dairy** is 260 |

Most are roundings and harmless. Two are not: the calf weight is 27% below any published calf row, and the feedlot weight is half the lower of the two published feedlot weights. The `dairy_cows` entry is the mixing of 2.1 reappearing at sub-category level.

### 2.8 Pregnancy rates are on a different regional basis from everything else

`PCT_PREGNANT_BY_SUBCAT` gives cows 0.85 and heifers 0.50. Africa is 54% in both annex tables. The figure 85% is the **Eastern Europe** dairy rate. Every other default in the tool is African; this object is not.

### 2.9 Two regional benchmarks match no row for their region

| Region | Tool | IPCC |
|---|---|---|
| africa | 275 | Table 10A.2 Africa grazing 275 (exact) |
| europe | 600 | Table 10A.1 Western Europe dairy 600 (exact) |
| americas | 500 | Table 10A.1 Latin America low productivity 500 (exact) |
| asia | 350 | Asia dairy 386, low productivity 355; non-dairy 376 / 305. The only published 350 is Indian subcontinent high-productivity dairy |
| oceania | 500 | Oceania dairy 488; non-dairy 416 / 467. No 500 anywhere |
| global | 400 | no global row exists in either table |

This object survived review round 7 for BW only, after the other benchmarks were withdrawn. Two of the six still do not resolve.

## 3. Correctly classified as non-IPCC

The 20 `suggested_uncertainty_pct` values are Penman (2000) and Monni (2007), disclosed as such in the user guide. The one exception is `Bo` at 15%, which is published in the footer of Table 10.16A and is now marked `CONFIRMED`.

`Tw` has no IPCC default and is correctly a project assumption. `GWP_VALUES` are correct against AR4 (25 / 298), AR5 (28 / 265) and AR6 (27 / 273, non-fossil methane), but the Assessment Reports are not in `reference/`, so those six are confirmed against the published figures rather than from a local source.

## 4. What this pass did not do

**Amended after the Ym decision below: finding 2.3 has since been resolved and applied.** Everything else in section 2 still stands open.

No other value was changed. Of the remaining `DEVIATION_OPEN` rows, several carry review provenance: `Milk` 3.5 and `Fat` 4.3 were adjudicated at round 8 page 7, and the regional benchmark at round 7 item #3. Resolving 2.1 or 2.4 would change reported emission means. Those are decisions to take deliberately, with the reviewer, not corrections to apply on the strength of a reading. Ym was different on exactly that point: no review round had ever adjudicated it.

The PERT mean-shift measurement (Part B) is still outstanding and is now larger than first estimated, because `deep_bedding` moved to 80 and `liquid_slurry` to 50 after that estimate was made.

---

# Ym: deep verification, 2026-09-11

Finding 2.3 above set this out in outline. This section is the full reading, because Ym is the one open finding that is wrong under **both** guideline editions and that inverts a qualitative conclusion, not just a number.

## What IPCC actually publishes

### 2019 Refinement, Table 10.12 (Updated), PDF page 10.46

| Livestock category | Description | Condition | Ym % |
|---|---|---|---|
| Dairy cows and Buffalo | High-producing (>8500 kg/head/yr) | DE >= 70, NDF <= 35 | 5.7 |
| Dairy cows and Buffalo | High-producing (>8500 kg/head/yr) | DE >= 70, NDF >= 35 | 6.0 |
| Dairy cows and Buffalo | Medium producing (5000-8500 kg/yr) | DE 63-70, NDF > 37 | 6.3 |
| Dairy cows and Buffalo | Low producing (<5000 kg/yr) | DE <= 62, NDF > 38 | **6.5** |
| Non dairy and multi-purpose | > 75% forage | DE <= 62 | **7.0** |
| Non dairy and multi-purpose | >75% high quality forage and/or mixed rations, 15-75% forage with grain/silage | DE 62-71 | 6.3 |
| Non dairy and multi-purpose | Feedlot, all other grains, 0-15% forage | DE >= 72 | **4.0** |
| Non dairy and multi-purpose | Feedlot, steam-flaked corn, 0-10% forage | DE >= 75 | **3.0** |

Two footnotes decide how this maps onto the tool.

**Footnote 4** is the one that matters most: *"Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected."*

So IPCC restricts 6.5 to **lactating** dairy cows, and sends dry-phase animals in low-productivity systems to **7.0**. The tool's `dairy_cows` label already reads "mature lactating females" and its `other_cows` label reads "mature non-dairy females, inc. dry". Both land exactly where footnote 4 puts them.

**Footnote 3**: *"Uncertainty values are +/- 20%."* The tool ships 20%. That is an IPCC-published figure, not the Penman/Monni default the first pass assumed, and the verdict on `Ym suggested_uncertainty_pct` has been corrected from `NOT_IPCC` to `CONFIRMED`. The internal change from 8 to 20 on 2026-06-15 cited "2019R Tier 2 guidance" without naming a table; this is the table.

### 2006 Guidelines, Table 10.12, PDF page 10.30

| Livestock category | Ym |
|---|---|
| Feedlot fed Cattle (90% or more concentrates) | **3.0% +/- 1.0** |
| Dairy Cows (Cattle and Buffalo) and their young | 6.5% +/- 1.0 |
| Other Cattle and Buffaloes primarily fed low quality crop residues and by-products | 6.5% +/- 1.0 |
| Other Cattle or Buffalo, grazing | 6.5% +/- 1.0 |

The 2006 table is much coarser: everything is 6.5 **except feedlot at 3.0**.

### Independent confirmation from Annex 10A.2

The annex was built by running the Tier 2 method over these same values, so its CH4-conversion column is a cross-check on the main table. It agrees exactly:

| Annex row | DE | Ym | Matches Table 10.12 row |
|---|---|---|---|
| Africa, every non-dairy row including Calves on forage | 58-59 | **7.0** | >75% forage, DE <= 62 |
| Latin America, Feedlot cattle | 74 | **4.0** | Feedlot all other grains, DE >= 72 |
| North America, Feedlot cattle | 75 | **3.0** | Feedlot steam-flaked corn, DE >= 75 |
| North America / Latin America, Calves on **milk** | 95 | **0.0** | none; pre-ruminant, EF is 0 |
| Asia, Calves on forage | 62 | 6.3 | mixed rations, DE 62-71 |

Every non-dairy row of the Africa block carries 7.0, in every category, including calves.

## What the tool does

`PARAM_CATALOGUE$Ym` is 6.5 and `resolve_subcat_default()` has no `Ym` case in its override switch, so all nine sub-categories receive 6.5. There is no `YM_BY_SUBCAT`. The resolver also accepts an `ipcc_version` argument and never reads it, so the 2006 and 2019R editions resolve identically.

Ym enters only one place, `calc_enteric_ch4()`:

    (ge * (Ym / 100) * 365) / 55.65

It is strictly linear and it does not appear in volatile solids or anywhere in the manure pathway, so the effect is confined to enteric CH4 and scales one for one.

## Measured effect

Run through the app's own engine at its own resolved defaults, per 100,000 head:

| Sub-category | Now (6.5) | IPCC | Change |
|---|---|---|---|
| dairy_cows | 6957.7 | 6957.7 | 0.0% (already correct) |
| other_cows | 6063.5 | 6529.9 | +7.7% |
| bulls | 5775.0 | 6219.2 | +7.7% |
| oxen | 4477.1 | 4821.5 | +7.7% |
| heifers | 5721.5 | 6161.7 | +7.7% |
| calves | 2010.8 | 2165.5 | +7.7% |

| Feedlot cattle | t CH4/yr | vs now |
|---|---|---|
| Now: Ym 6.5, DE 55 | 10213.5 | |
| 2019R: Ym 4.0, DE 74 | 3655.2 | **-64.2%** |
| 2006: Ym 3.0, DE 74 | 2741.4 | -73.2% |
| Ym alone: Ym 4.0, DE 55 | 6285.2 | -38.5% |

**The feedlot figure is qualitatively wrong, not just quantitatively.** At the tool's current defaults a feedlot animal is the *highest* per-head enteric emitter in the herd, above dairy cows. The whole point of IPCC's low feedlot Ym is that concentrate-fed animals emit *less* enteric methane per head. The tool currently reverses the direction of that comparison, which would invert any conclusion a user drew about intensification.

**Feedlot cannot be fixed by moving Ym alone.** The 4.0 row is conditional on DE >= 72 and the tool's DE default is 55. Moving Ym without DE ships an animal on a combination IPCC does not sanction, and lands 41.8% away from the correct answer. Annex 10A.2 gives feedlot DE 74 and CP 14.0 against the tool's 55 and 10.0, so the feedlot sub-category is carrying grazing-animal diet parameters throughout.

## Recommended values

Edition-aware, keyed on sub-category, on the tool's existing low-productivity African basis:

| Sub-category | 2019R | 2006 | Basis |
|---|---|---|---|
| dairy_cows | 6.5 | 6.5 | Table 10.12 low producing, lactating (footnote 4) |
| other_cows | 7.0 | 6.5 | non-dairy >75% forage; footnote 4 also sends dry dairy here |
| bulls | 7.0 | 6.5 | non-dairy >75% forage |
| oxen | 7.0 | 6.5 | non-dairy >75% forage |
| heifers | 7.0 | 6.5 | non-dairy >75% forage |
| growing_males | 7.0 | 6.5 | non-dairy >75% forage |
| calves_female | 7.0 | 6.5 | Annex 10A.2 Africa, Calves on forage |
| calves_male | 7.0 | 6.5 | Annex 10A.2 Africa, Calves on forage |
| feedlot_cattle | **4.0** | **3.0** | Feedlot, 0-15% forage, DE >= 72 |

With two dependencies that have to move at the same time:

1. **Feedlot DE must go to about 74** (Annex 10A.2 Latin America) or the Ym row's own precondition is violated. Feedlot CP should go to 14.0 on the same authority.
2. The 7.0 assignment is conditional on DE <= 62. The tool's DE default of 55 satisfies it, but a user who raises DE into 62-71 should be getting 6.3. A per-sub-category constant cannot express that; only a DE-conditional lookup can. The constant is the right approximation for the shipped defaults and should be documented as conditional rather than absolute.

Three further notes:

- **Milk-fed calves are Ym 0.0** in the annex, with an enteric EF of zero. The tool has no pre-weaning category, and its calves default to the forage-fed reading. A user with a milk-fed calf population would be badly overstated. Worth a note in the guidance rather than a tenth sub-category.
- `resolve_subcat_default()` already takes `ipcc_version` and ignores it. An edition-aware Ym is the first default that genuinely needs it, so this is also the change that makes that argument real.
- **No review round adjudicated the Ym default.** The review record carries only the uncertainty change (internal, 2026-06-15). Unlike `Milk` 3.5 and `Fat` 4.3, correcting Ym does not overturn a reviewer decision.

## Applied, 2026-09-11

The full edition-aware split was adopted and is in the code. What changed:

**New objects in the master:** `YM_BY_SUBCAT` (9 sub-categories x 2 editions), `DE_BY_SUBCAT` and `CP_BY_SUBCAT` (9 each). The master went from 537 to 573 rows. `YM_BY_SUBCAT` is the first object with a column per guideline edition; every other default is edition-neutral.

**`resolve_subcat_default()` now honours its `ipcc_version` argument.** It had accepted that argument and ignored it since it was written. Ym is the first default where the distinction is load-bearing, so the argument is now real rather than decorative.

**Resolved values:**

| sub-category | Ym 2019R | Ym 2006 | DE | CP |
|---|---|---|---|---|
| dairy_cows | 6.5 | 6.5 | 55 | 10 |
| other_cows | 7.0 | 6.5 | 55 | 10 |
| bulls | 7.0 | 6.5 | 55 | 10 |
| oxen | 7.0 | 6.5 | 55 | 10 |
| heifers | 7.0 | 6.5 | 55 | 10 |
| growing_males | 7.0 | 6.5 | 55 | 10 |
| calves_female | 7.0 | 6.5 | 55 | 10 |
| calves_male | 7.0 | 6.5 | 55 | 10 |
| feedlot_cattle | 4.0 | 3.0 | 74 | 14 |

**Measured effect on enteric CH4, per 100,000 head, under 2019R:**

| sub-category | before | after | change |
|---|---|---|---|
| dairy_cows | 6957.7 | 6957.7 | 0.0% |
| other_cows | 6063.5 | 6529.9 | +7.7% |
| bulls | 5775.0 | 6219.2 | +7.7% |
| oxen | 4477.1 | 4821.5 | +7.7% |
| heifers | 5721.5 | 6161.7 | +7.7% |
| growing_males | 4103.6 | 4419.3 | +7.7% |
| calves_female | 2010.8 | 2165.5 | +7.7% |
| calves_male | 1845.2 | 1987.2 | +7.7% |
| feedlot_cattle | 10213.5 | 3655.2 | -64.2% |

The qualitative inversion is gone: a feedlot animal now sits well below a dairy cow on per-head enteric methane, which is the direction IPCC's table implies.

**Surfaces updated.** The prompt's sub-category override table carries Ym for both editions plus DE and CP, so the translator is told the rule rather than left to infer it. The worked example now emits heifers at 7.0. The methodology and user guide parameter tables state the split instead of a single 6.5. `reference/DEFAULTS_MASTER.md` shows all four new columns.

**Coverage.** All 36 new cells are carried by at least one surface and read MATCH; the matrix went from 444 to 480 cells with zero divergences. Audit check **F35** asserts all nine sub-categories across both editions, plus that feedlot DE satisfies the `DE >= 72` precondition of its own Ym row and that no other sub-category's DE has drifted from the catalogue. A spot check would not have caught the original defect, because the one sub-category that was already right (dairy) is the one a spot check would most likely have picked.

**Two latent bugs surfaced by the change.** The kit generator was passing an undefined `ipcc_version` to `resolve_subcat_default()` and got away with it only because R evaluates arguments lazily and the callee never read it; the worked example now resolves under the edition it declares in its own metadata. And the matrix's own extractors had to learn the new objects, without which the prompt would have stated nine Ym values that no surface checked.

## Still open on Ym

- The 7.0 row is conditional on DE <= 62. A per-sub-category constant cannot express that, so a user who raises DE into 62-71 should be getting 6.3 and will not. Only a DE-conditional lookup would be fully faithful; the constant is correct for the shipped defaults and is documented as conditional.
- Milk-fed calves are Ym 0.0 in Annex 10A.2, with an enteric EF of zero. The tool has no pre-weaning category and its calves resolve to the forage-fed 7.0. An inventory with a large milk-fed calf population would be overstated. This belongs in the guidance rather than as a tenth sub-category.
- `DE_BY_SUBCAT` inherits the unresolved `DE` question from finding 2.1 for the eight non-feedlot rows: 55 still matches neither annex table. The new object did not create that problem and does not fix it.

---

# Bo: deep verification, 2026-09-11

Tier 1 item 1 of the variable-by-variable pass. Same protocol as Ym: find every table in both editions, read the footnotes, ask the shape question, cross-check the annex, confirm the conditioning variable reaches the resolver, measure, then record.

## What IPCC publishes

**2019R Vol.4 Ch.10 Table 10.16A (Updated), PDF page 10.67.** Keyed by region and, within "Other Regions", by productivity:

| Category | N. America | W. Europe | E. Europe | Oceania | Other, high productivity | Other, low productivity |
|---|---|---|---|---|---|---|
| Dairy cattle | 0.24 | 0.24 | 0.24 | 0.24 | 0.24 | **0.13** |
| Non dairy cattle | 0.19 | 0.18 | 0.17 | 0.17 | 0.18 | **0.13** |
| All Animals PRP | 0.19 across every region | | | | | |

Footnote 1: "For other regions, low productivity is considered the default value for Tier 1 if not using the Tier 1a." Table footer: "Uncertainty values are +/- 15 percent."

**2006 edition.** Table 10.16 in the 2006 Guidelines is a different table entirely: manure-management CH4 emission factors for deer, reindeer, rabbits and fur-bearing animals. The 2006 Bo values live in the Annex 10A.2 derivation tables. Table 10.16A's own source note says its values "are consistent with 2006 IPCC Guidelines values from Annex 10A.2 with the exception of PRP".

## The shape question

Bo is keyed by **region x productivity x dairy/non-dairy**, and the tool holds a single scalar of 0.13. That is the Ym pattern on its face, so it was worked through carefully. Three things decide it.

**For the stated audience the single value is right.** The tool is built for developing-country inventory compilers, which maps to "Other regions", and footnote 1 makes low productivity the Tier 1 default there. In that column dairy and non-dairy are **both 0.13**, so the dairy/non-dairy split that mattered so much for Ym collapses to a single number here.

**The app cannot express IPCC's regions anyway.** `COUNTRY_TO_REGION` maps 93 countries onto africa, americas, asia, europe and oceania. IPCC's columns are North America, Western Europe, Eastern Europe, Oceania and Other Regions. The app's `americas` conflates North America (0.24 dairy) with Latin America (Other Regions), and `europe` conflates Western with Eastern Europe. Keying Bo off the existing region vocabulary would therefore produce a value that is wrong for roughly half the countries in each of those two buckets. This is the opposite of the Ym case, where `sub_category` mapped onto IPCC's categories exactly.

**The consequence is real but bounded.** A Western European or North American dairy inventory that accepts the default gets 0.13 where IPCC gives 0.24, understating manure CH4 by 46%. Bo is a user-supplied parameter, so this bites only on gap-filled rows, and the auto-fill hint already names Table 10.16(a) and the 0.24 figure explicitly.

**Decision: keep 0.13, document the full table, keep warning.** Consistent with the decision taken for the Chapter 11 climate factors. Adding a region key would require replacing the app's region vocabulary with IPCC's, which is a larger change than the defect warrants and would silently reassign every existing inventory.

## PRP Bo 0.19 is the other half of a matched pair

Table 10.16A publishes a separate Bo of 0.19 for manure deposited on pasture, range and paddock, and `calc_manure_ch4()` applies one Bo to every management system including pasture. That looks like a straightforward omission and is not.

The 2019 Refinement pairs that 0.19 with a pasture MCF of 0.47%. The tool deliberately holds pasture MCF on the 2006 convention (1.0 / 1.5 / 2.0), a decision already on record in this register. Taking 0.19 without 0.47% would combine the 2019R numerator with the 2006 denominator and inflate pasture manure CH4 by 46% on top of an MCF that is already four times the 2019R figure. The two coherent options are the 2006 pair (MCF 2.0, Bo 0.13) or the 2019R pair (MCF 0.47, Bo 0.19); the tool holds the first, consistently. `DEVIATION_DOCUMENTED`, unchanged.

## Confirmed and corrected

- `Bo` 0.13: **CONFIRMED** against Table 10.16A, Other regions low productivity, for dairy and non-dairy alike.
- `Bo` uncertainty 15%: **CONFIRMED** from the table footer, as already recorded.
- Citation **corrected**: `ipcc_ref` and the parameter definition said "Table 10.16", which in both editions is the deer and reindeer emission-factor table. Now "Table 10.16A".

## What the Bo pass turned up elsewhere

Checking whether Bo's context hint was accurate surfaced that `CONTEXT_DEPENDENT_HINTS` in `R/utils_qaqc.R`, the text shown to a user whenever a parameter is auto-filled, carried **no verification coverage at all** and three of its eight strings had drifted from the values the tool ships:

| hint | said | tool ships |
|---|---|---|
| `EF4` | "DEFAULT IS THE 2019R AGGREGATED VALUE (0.010)" | 0.014, the wet-climate value |
| `EF3_PRP` | "DEFAULT IS THE 2019R AGGREGATED VALUE" (0.004) | 0.006, the wet-climate value |
| `Ym` | "6.5 ... low-productivity cattle on forage" | 6.5 is the low-producing DAIRY row; cattle on forage is 7.0 |

A user reading the EF4 hint was told the number 0.010 when the value they had actually been given was 0.014. All three are corrected, and `qaqc_hints` is now a checked surface in `scripts/verify_defaults.R`: the opening clause of each hint must state that parameter's shipped default.

The check needed two passes. The first version asserted only that the shipped value appeared somewhere in the hint, which every one of these strings satisfies because they all list the alternatives too; the negative test caught it passing against the deliberately broken text. Restricting the scan to the opening clause, with table citations and edition tokens stripped, makes it bite.

---

# Milk and Fat: deep verification, 2026-09-11

Both were adjudicated at review round 8 page 7, so the value question was approached as an escalation, not a correction. The pass confirmed one of them outright, left the other open on a basis question, and found a separate defect neither the reviewer nor any earlier pass had looked at.

## Fat 4.3: CONFIRMED, and robust

Table 10A.1 (New) gives three rows for Africa, and the fat content is the same in all of them:

| Africa row | Weight | Milk yield | **Fat** | Protein | Pregnant | DE | CP |
|---|---|---|---|---|---|---|---|
| Africa (aggregate) | 260 | **3.5** | **4.3** | 3.6 | 54 | 51 | 8.7 |
| High productivity systems | 250 | 5.8 | **4.3** | 3.6 | 57 | 50 | 7.8 |
| Low productivity systems | 270 | 1.2 | **4.3** | 3.6 | 52 | 51 | 9.6 |

Fat does not move with the productivity basis, so no choice of basis can change it. The round 8 comment, "IPCC 2019 gives 4.3 for africa", is exactly right and nothing further is owed on it.

The same table settles `MilkPR` a second way: protein content is **3.6** in all three rows, reinforcing that the shipped 3.3 is supported by no reading.

## Milk 3.5: correct for the row it comes from, open on which row

3.5 is the Africa **aggregate**, and footnote 4 says what that means: the regional rows "were estimated as weighted average by taking into account parameter values related to low production systems and high production systems and livestock population structure". For Africa the split is 49% high, 51% low.

The round 8 change from an unsourced 4.0 to 3.5 was therefore right. What is open is whether the aggregate is the row this tool should use, because the tool does not consistently sit on any single row:

| parameter | tool | Africa aggregate | Africa high | Africa low | non-dairy grazing (10A.2) |
|---|---|---|---|---|---|
| Milk | 3.5 | **3.5** | 5.8 | 1.2 | 1.2 |
| Fat | 4.3 | **4.3** | **4.3** | **4.3** | 4.1 |
| BW | 275 | 260 | 250 | 270 | **275** |
| DE | 55 | 51 | 50 | 51 | 58 |
| CP | 10.0 | 8.7 | 7.8 | 9.6 | **10.0** |
| pct_pregnant | 0.60 | 0.54 | 0.57 | 0.52 | 0.54 |

Two of the tool's other defaults point at the **low productivity** row specifically. `Bo` is 0.13 on the stated basis of "Other regions, low productivity", which Table 10.16A footnote 1 makes the Tier 1 default for those regions. `Ca` is 0.17, the Pasture/Range coefficient, and Pasture/Range is precisely how Table 10A.1 characterises the low-productivity feeding situation while the aggregate row is marked Stall Fed.

On a consistent low-productivity basis, Africa dairy milk yield is **1.2 kg/day**, not 3.5. Measured through the engine for dairy cows, per 100,000 head: enteric CH4 6957.7 t/yr at 3.5, **5929.6 t/yr at 1.2** (-14.8%), and 7985.8 t/yr at the high-productivity 5.8.

This is finding 2.1 again, not a new one: the tool mixes rows. Milk is the cell where the mixing is most visible because it is the only one of the six above where the aggregate and the low-productivity value differ by a factor of three.

## A unit convention that does not match the default

Table 10A.1 footnote 1: "The value represent milk yield in kg per day during the whole year." The published 3.5 is therefore an annual average per head, already diluted by the dry period.

The tool's `Milk` field is documented as "Daily milk yield per lactating cow (not sub-category-average, the tool multiplies by pct_pregnant internally)", and `calc_nel()` implements exactly that:

    NE_l = Milk x (1.47 + 0.40 x Fat) x pct_pregnant

IPCC Equation 10.8 carries no such factor. The convention is coherent for a user supplying a per-lactating-cow figure, but the IPCC default shipped into that field is already an annual average, so it is discounted a second time. For dairy cows at pct_pregnant 0.85, NE_l is 9.49 MJ/day where Equation 10.8 as written gives 11.16, a 15% reduction, and enteric CH4 runs 4.7% low.

Either the default should be grossed up to a per-lactating-cow basis, or the pct_pregnant factor should not apply when the value is the IPCC default. Recorded, not changed: it interacts with the basis question above and with `pct_pregnant` itself, which is separately open.

## The defect that was actually fixed

Checking who receives the Milk default turned up something neither the reviewer nor any earlier pass had examined. The biological-zero rule tested only `sex == "male"`, so **every non-male sub-category inherited the dairy-cow 3.5 kg/day**, including animals that have never calved:

| sub-category | label | got Milk |
|---|---|---|
| heifers | "young females 1-3yr, not yet calved" | 3.5 |
| calves_female | "Calves - Female (<1yr)" | 3.5 |
| feedlot_cattle | fattening animals, mixed sex | 3.5 |

That adds a net-energy-for-lactation term to animals that cannot produce milk. Measured per 100,000 head:

| sub-category | enteric CH4 before | after | change |
|---|---|---|---|
| heifers | 6161.7 | 5170.6 | **-16.1%** |
| feedlot_cattle | 3655.2 | 3214.3 | **-12.1%** |
| calves_female | 2165.5 | 2165.5 | 0.0% |

Heifers were running 19% high and feedlot cattle 14% high on enteric methane. Calves were unaffected in the numbers only because the separate pregnancy zero already forced their NE_l term to zero, but the filled template still displayed a milk yield of 3.5 kg/day for a calf, which is visibly wrong to a user and to the translator.

**Annex 10A.2 settles it for every region, not just Africa:** only the Mature Females rows carry a milk yield at all. Growing/Replacement, Calves on forage and Feedlot cattle are blank in that column.

Fixed by keying the zero on maturity rather than sex alone: `Milk`, `Fat` and `MilkPR` are non-zero only where the animal is female and `adult_>3yr`. Keyed on age rather than an explicit list so an unrecognised sub-category, which defaults to sex "mixed" and adult age, keeps the catalogue value instead of being silently zeroed. The translator prompt's biological-zero rules were updated to match.

## Two audit checks were passing vacuously

F36 was written for the rule above and **passed against the deliberately reverted code**. So did F35, the Ym check added earlier the same day.

Both built their failure list with `<<-` inside `tryCatch`. These checks run inside `section_F()`, and `tryCatch` evaluates its expression in the caller's frame, so `<<-` skips the local variable and writes to the global environment; the check then reads an empty local list and passes regardless. Both now return the failure list from the `tryCatch` block instead, and both have been demonstrated failing against their own defect before passing.

This is the third time in this audit that a check has had to be tested against the broken state before it could be trusted: F34 was masked by the audit's own globals, the first `qaqc_hints` extractor was satisfied by a number appearing anywhere in the prose, and now these two. A check that has never been seen to fail is not evidence.

---

# DECLARED BASIS: low productivity, adopted 2026-09-11

Until now the tool had no declared basis. Its defaults were drawn from whichever IPCC row had seemed right at the time each one was set, and finding 2.1 showed the result described no animal IPCC published: `Milk`, `Fat` and `Ym` from the Africa dairy aggregate, `BW` and `CP` from the Africa non-dairy grazing row, and `MilkPR`, `pct_pregnant` and `DE` from neither.

**The decision: where IPCC offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY.**

## Why that row

Three things already pointed at it before the decision was taken.

`Bo` is 0.13, which Table 10.16A labels "Other regions, low productivity systems" and which footnote 1 of that table makes the Tier 1 default for those regions. `Ca` is 0.17, the Pasture/Range activity coefficient, and Pasture/Range is exactly how Table 10A.1 characterises the low-productivity feeding situation, while the aggregate row is marked Stall Fed. `Ym` is 6.5, the low-producing dairy row of Table 10.12.

So the tool was already sitting on the low-productivity row for its three most consequential coefficients. The decision makes the animal-characteristic defaults agree with them rather than contradict them.

It also matches the user base. The tool is built for developing-country inventory compilers working with smallholder and pastoral systems, which is what the low-productivity row describes.

## What the basis resolves to

**Generic catalogue defaults, from Table 10A.1 (New), Africa, Low productivity systems (PDF p.10.104):**

| parameter | was | now | note |
|---|---|---|---|
| BW | 275 | **270** | was the Table 10A.2 non-dairy grazing weight |
| Milk | 3.5 | **1.2** | was the aggregate of high (5.8) and low (1.2) |
| Fat | 4.3 | 4.3 | identical in all three rows; unchanged |
| MilkPR | 3.3 | **3.6** | was a leftover of the pre-correction Fat of 3.5 |
| pct_pregnant | 0.60 | **0.52** | matched no row in either table |
| DE | 55 | **51** | sat between the two tables, matching neither |
| CP | 10.0 | **9.6** | was the Table 10A.2 non-dairy grazing figure |
| Ym | 6.5 | 6.5 | low-producing dairy row; unchanged |

**Per sub-category.** The dairy row follows Table 10A.1 low productivity; every non-dairy row follows its matching Table 10A.2 Africa grazing row, which is the same extensive-system reading:

| sub-category | DE | CP | pct_pregnant | IPCC row |
|---|---|---|---|---|
| dairy_cows | 51 | 9.6 | 0.52 | 10A.1 Africa low productivity |
| other_cows | 58 | 10.0 | 0.54 | 10A.2 Mature Females - grazing |
| bulls | 58 | 10.0 | zero | 10A.2 Bulls - Grazing |
| oxen | 58 | 10.0 | zero | 10A.2 Draft Bullocks |
| heifers | 59 | 10.4 | 0.50 | 10A.2 Growing/Replacement |
| growing_males | 59 | 10.4 | zero | 10A.2 Growing/Replacement |
| calves | 59 | 10.3 | zero | 10A.2 Calves on forage |
| feedlot_cattle | 74 | 14.0 | zero | 10A.2 Latin America Feedlot |

Two independent confirmations fell out of this. The dairy low-productivity milk yield (10A.1) and the non-dairy grazing milk yield (10A.2) are both **1.2 kg/day**, so both mature-female categories land on the same figure from different tables. And `heifers` pregnancy has no IPCC figure at all: Table 10A.2 leaves the Pregnant column blank for Growing/Replacement, so 0.50 is now marked `NO_IPCC_DEFAULT` rather than passed off as a default.

## Measured effect

Total CO2e per 100,000 head, AR5, pasture-only manure:

| sub-category | before | after | change |
|---|---|---|---|
| dairy_cows | 224,117 | 203,397 | -9.2% |
| other_cows | 208,025 | 150,027 | **-27.9%** |
| bulls | 200,706 | 183,947 | -8.4% |
| oxen | 155,598 | 142,606 | -8.4% |
| heifers | 165,456 | 144,731 | -12.5% |
| growing_males | 141,493 | 124,653 | -11.9% |
| calves_female | 68,194 | 59,200 | -13.2% |
| calves_male | 62,440 | 54,454 | -12.8% |
| feedlot_cattle | 113,414 | 113,414 | 0.0% |

`other_cows` moves most because three changes compound on it: milk yield from 3.5 to 1.2, pregnancy from the Eastern Europe 0.85 to the Africa 0.54, and digestibility from 55 to 58. Feedlot is unaffected because it was already resolved onto its own IPCC row.

These are reductions across the board. An inventory that accepts the defaults will now report materially lower emissions than the same inventory did in July. That is the point of the change and it is the single most important thing for a reviewer to see.

## This overturns a review decision

`Milk` 3.5 was agreed at review round 8 page 7, where the comment was "check this, I think it's closer to 3.5" against a previous unsourced 4.0. **That was right for the aggregate row.** What changed is the basis, not the reading of the table. The reviewer was correcting an unsourced number, not choosing between productivity systems, and the productivity question does not appear to have been put to them.

Flagged as `APPLIED_OVERTURNS_REVIEW` in `reference/VALUE_CHANGES_FOR_REVIEW.md` so it cannot pass unnoticed. If the reviewer prefers the aggregate row, the change to revert is a single cell in the master.

`Fat` 4.3, agreed in the same round, is untouched and unaffected: Table 10A.1 gives 4.3 in all three Africa rows.

## Three audit checks had to be updated, and one had a real gap

F30, F31 and F35 all failed on the change, which is what they are for. Their expectations were rewritten against the IPCC rows rather than against whatever the code now produces.

F35 had asserted that every sub-category carried the *catalogue* DE. That was true only while DE was a uniform 55 matching no IPCC row; it now asserts the full nine-row diet table. F31 turned out to be asserting `pick("other_cows", ...)` on a fixture that writes only dairy_cows, bulls and oxen, where an absent row returns NA and the assertion tests nothing; it now uses oxen. F31 also still asserted bulls EF3 without bulls MCF, the omission that let the dry_lot correction through once before, and that is now closed.

## Still open after this decision

The basis choice does not settle the `BW` and `WG` roundings of finding 2.7: `bulls` 350 against the table's 340, `oxen` 300 against 340, `heifers` 200 against 204, `calves` 60 against 82, `feedlot` 250 against 460. Those are separate from the productivity question and remain open.
