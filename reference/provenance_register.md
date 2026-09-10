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
