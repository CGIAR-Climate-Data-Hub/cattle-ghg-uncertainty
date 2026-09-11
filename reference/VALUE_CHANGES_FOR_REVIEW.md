# IPCC default values: what changed, and what we think is still wrong

Generated 2026-09-11 by `scripts/build_review_table.R`. Do not edit by hand.

## What this is

Every IPCC default the cattle uncertainty tool ships was read back against the IPCC source text, value by value, in September 2026. This is the result, laid out so it can be checked.

The **before** column is the value as it stood at commit `fbfa1bc` (2026-07-10), the last change before September and the last recorded deployment. That is still what the live app runs, so the before column is what a user would get today. It is extracted from git by `scripts/extract_baseline_defaults.R`, never retyped.

**What each status is asking of you:**

| status | count | meaning |
|---|---|---|
| `APPLIED` | 47 | Already changed. The IPCC basis was unambiguous and no review round had ruled on the value. Please endorse, or object. |
| `PROPOSED` | 4 | We think it is wrong, but a numbered review round adjudicated it, so it has **not** been changed. Your call. |
| `OPEN` | 10 | Differs from IPCC with no recorded reason and no review history. A judgement call we did not want to take alone. |

Nothing here has been pushed or deployed.

---

## 1. Already applied (47)

Changed since 2026-07-10. Each cites the IPCC table it was read from.

| object | key | field | before | now | affects | IPCC source |
|---|---|---|---|---|---|---|
| CP_BY_SUBCAT | feedlot_cattle | value | 10 | 14 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Latin America and North America Feedlot cattle both give CP in diet 14.0% |
| DE_BY_SUBCAT | feedlot_cattle | value | 55 | 74 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Latin America Feedlot cattle: digestibility of feed 74%. Required by Table 10.12, whose feedlot Ym of 4.0 is conditional on DE >= 72; the catalogue default of 55 would violate that precondition |
| MMS_DEFAULTS | anaerobic_digester | mcf_boreal | 1 | 3.55 | manure CH4 | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 |
| MMS_DEFAULTS | anaerobic_digester | mcf_temperate | 1 | 4.38 | manure CH4 | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 |
| MMS_DEFAULTS | anaerobic_digester | mcf_tropical | 3.5 | 4.59 | manure CH4 | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 |
| MMS_DEFAULTS | anaerobic_digester | mcf_tropical_dry | 3.5 | 4.59 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_DEFAULTS | composting | ef3 | 0.006 | 0.01 | direct N2O, manure management | 2019R V4 Ch10 Table 10.21 (Updated), Composting - Static Pile (Forced aeration): 0.010 |
| MMS_DEFAULTS | deep_bedding | mcf_boreal | 3 | 17 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | deep_bedding | mcf_temperate | 17 | 39 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | deep_bedding | mcf_tropical | 30 | 80 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | deep_bedding | mcf_tropical_dry | 30 | 80 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_DEFAULTS | dry_lot | mcf_tropical | 5 | 2 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Dry lot: 1.0 / 1.5 / 2.0 |
| MMS_DEFAULTS | dry_lot | mcf_tropical_dry | 5 | 2 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_DEFAULTS | lagoon | mcf_temperate | 66 | 77 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Uncovered anaerobic lagoon: 66 / 77 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | liquid_slurry | mcf_temperate | 35 | 24 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Liquid/Slurry with natural crust cover: 10 / 24 / 50. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | liquid_slurry | mcf_tropical | 80 | 50 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Liquid/Slurry with natural crust cover: 10 / 24 / 50. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column |
| MMS_DEFAULTS | liquid_slurry | mcf_tropical_dry | 80 | 50 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_DEFAULTS | pasture | mcf_temperate | 1 | 1.5 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Pasture/Range/Paddock: 1.0 / 1.5 / 2.0 |
| MMS_DEFAULTS | pasture | mcf_tropical | 1.5 | 2 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Pasture/Range/Paddock: 1.0 / 1.5 / 2.0 |
| MMS_DEFAULTS | pasture | mcf_tropical_dry | 1.5 | 2 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_DEFAULTS | solid_storage | mcf_boreal | 3 | 2 | manure CH4 | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Solid storage: 2.0 / 4.0 / 5.0 |
| MMS_DEFAULTS | solid_storage_covered | mcf_boreal | 1 | 2 | manure CH4 | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 |
| MMS_DEFAULTS | solid_storage_covered | mcf_temperate | 2 | 4 | manure CH4 | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 |
| MMS_DEFAULTS | solid_storage_covered | mcf_tropical | 4 | 5 | manure CH4 | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 |
| MMS_DEFAULTS | solid_storage_covered | mcf_tropical_dry | 4 | 5 | manure CH4 | Mirrors mcf_tropical on every system. The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both |
| MMS_FRAC_DEFAULTS_2019 | composting | frac_gas_high | 0.98 | 0.7 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 |
| MMS_FRAC_DEFAULTS_2019 | composting | frac_gas_low | 0.33 | 0.14 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 |
| MMS_FRAC_DEFAULTS_2019 | daily_spread | frac_gas_high | 0.1 | 0.6 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 |
| MMS_FRAC_DEFAULTS_2019 | daily_spread | frac_gas_low | 0.04 | 0.05 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 |
| MMS_FRAC_DEFAULTS_2019 | dry_lot | frac_gas_high | 0.45 | 0.5 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 |
| MMS_FRAC_DEFAULTS_2019 | dry_lot | frac_gas_low | 0.15 | 0.2 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 |
| MMS_FRAC_DEFAULTS_2019 | liquid_slurry | frac_gas | 0.48 | 0.3 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 |
| MMS_FRAC_DEFAULTS_2019 | liquid_slurry | frac_gas_high | 0.72 | 0.36 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 |
| MMS_FRAC_DEFAULTS_2019 | liquid_slurry | frac_gas_low | 0.24 | 0.09 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 |
| MMS_FRAC_DEFAULTS_2019 | solid_storage | frac_gas_high | 0.68 | 0.65 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 |
| MMS_FRAC_DEFAULTS_2019 | solid_storage | frac_gas_low | 0.23 | 0.1 | indirect N2O (volatilisation) | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 |
| PARAM_CATALOGUE | Bo | ipcc_ref | Table 10.16 | Table 10.16A | manure CH4 | Corrected citation, not a value change. Table 10.16 is the deer, reindeer, rabbit and fur-bearing animal emission-factor table in both editions. The cattle Bo values are in Table 10.16A (Updated) of the 2019 Refinement. |
| PARAM_CATALOGUE | Bo | suggested_uncertainty_pct | 20 | 15 | manure CH4 | 2019R V4 Ch10 Table 10.16A (Updated), Other regions low productivity footer: uncertainty +/- 15% |
| YM_BY_SUBCAT | bulls | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | calves_female | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | calves_male | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | feedlot_cattle | ym_2006 | 6.5 | 3 | enteric CH4 | 2006 V4 Ch10 Table 10.12, p.10.30: 'Feedlot fed Cattle' 3.0%, footnote a 'when fed diets contain 90 percent or more concentrates' |
| YM_BY_SUBCAT | feedlot_cattle | ym_2019_refinement | 6.5 | 4 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Feedlot (all other grains, 0-15% forage), DE >= 72, Ym 4.0%. Annex 10A.2 Latin America Feedlot cattle confirms it at DE 74. North America feedlot sits at DE 75 with Ym 3.0, the steam-flaked corn row |
| YM_BY_SUBCAT | growing_males | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | heifers | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | other_cows | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | oxen | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |

## 2. Proposed, not changed: a review round ruled on these (4)

Left alone deliberately. The earlier decision may rest on context the code does not record.

| object | key | field | was 2026-07-10 | current | proposed | review round | why |
|---|---|---|---|---|---|---|---|
| IPCC_DEFAULTS_BY_REGION | asia | default_val | 350 | 350 | (decide) | R7 #3 | Table 10A.1 Asia dairy is 386 (low productivity 355); Table 10A.2 Asia gives 376 and 305. The shipped 350 matches no Asia row. Review round 7 item 3 kept this object for BW only after the other benchmarks were withdrawn. |
| IPCC_DEFAULTS_BY_REGION | oceania | default_val | 500 | 500 | (decide) | R7 #3 | Table 10A.1 Oceania dairy is 488; Table 10A.2 gives 416 and 467. The shipped 500 appears in no Oceania row. Same review provenance as asia. |
| PARAM_CATALOGUE | Fat | ipcc_default | 4.3 | 4.3 | (confirm) | R8 p7 | As Milk: correct against Table 10A.1 Africa dairy, but part of the same mixing question. Adjudicated at review round 8 page 7, so unchanged. |
| PARAM_CATALOGUE | Milk | ipcc_default | 3.5 | 3.5 | (confirm) | R8 p7 | Correct against Table 10A.1 Africa dairy. Flagged only because it sits in the dairy/non-dairy mixing cluster: the catalogue draws Milk, Fat and Ym from the dairy row and BW and CP from the non-dairy grazing row, describing no animal IPCC published. Adjudicated at review round 8 page 7, so unchanged. |

## 3. Open questions (10)

Differs from IPCC with no recorded reason. These would move a reported number. Where the `was` and `current` columns differ, the value was already changed in September and we now think it should move again.

| object | key | field | was 2026-07-10 | current | proposed | affects | why |
|---|---|---|---|---|---|---|---|
| MMS_DEFAULTS | composting | mcf_boreal | 0.5 | 0.5 | 1.0 | manure CH4 | See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant. |
| MMS_DEFAULTS | composting | mcf_temperate | 1 | 0.5 | 2.0 | manure CH4 | See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant. |
| MMS_DEFAULTS | composting | mcf_tropical | 1.5 | 0.5 | 2.5 | manure CH4 | The row declares the Static Pile variant and its EF3 (0.010) and Frac (0.65) both follow it, but 0.5 is the 2019R In-vessel figure. 2019R Table 10.17 gives Composting - Static pile (Forced aeration) 1.00 cool / 2.00 temperate / 2.50 warm. Correct as-is under 2006, where static pile is 0.5. |
| MMS_DEFAULTS | composting | mcf_tropical_dry | 1.5 | 0.5 | 2.5 | manure CH4 | See mcf_tropical. This column mirrors mcf_tropical on every system, so it moves with it. |
| MMS_FRAC_DEFAULTS_2019 | anaerobic_digester | frac_gas_high | 0.08 | 0.08 | 0.50 | indirect N2O (volatilisation) | Table 10.22 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central. The tool takes 0.05 as the central and samples 0.02 to 0.08, so its whole range sits at or below IPCC's floor and its ceiling is six times too low. |
| PARAM_CATALOGUE | MilkPR | ipcc_default | 3.3 | 3.3 | 3.6 | gross energy, so enteric CH4 + manure CH4 | Both candidate Africa rows give milk protein 3.6% (Table 10A.1 dairy and Table 10A.2 non-dairy grazing), and the tool's own documented route %MilkPR = 1.9 + 0.4 x %Fat gives 3.62 at Fat 4.3. The shipped 3.3 is what that formula returns for Fat 3.5, the value Fat held before review round 8 corrected it. No IPCC reading supports 3.3. |
| PARAM_CATALOGUE | MW | ipcc_ref | Table 10A.2 | Table 10A.2 | (none) | gross energy, so enteric CH4 + manure CH4 | Cites Table 10A.2, which has no mature-weight column; neither does Table 10A.1. IPCC publishes no default for mature weight. Review round 7 item 3 raised exactly this; the companion value (400 kg BW) was fixed and this citation was not. |
| PARAM_CATALOGUE | pct_pregnant | ipcc_default | 0.6 | 0.6 | 0.54 | gross energy, so enteric CH4 + manure CH4 | Table 10A.1 Africa dairy and Table 10A.2 Africa grazing both give 54% pregnant. The shipped 0.60 matches no row in either table. |
| PCT_PREGNANT_BY_SUBCAT | dairy_cows | value | 0.85 | 0.85 | 0.54 | gross energy and N excretion | 0.85 is the Eastern Europe dairy rate. Every other default in the tool is on an Africa basis, where both annex tables give 54%. |
| PCT_PREGNANT_BY_SUBCAT | other_cows | value | 0.85 | 0.85 | 0.54 | gross energy and N excretion | As dairy_cows: 0.85 is the Eastern Europe rate, Africa is 54% in both annex tables. |

---

## How to read the manure rows

`MMS_DEFAULTS` rows are per manure management system. IPCC splits several systems into variants with different coefficients (liquid slurry with and without a crust, composting in-vessel versus static pile), and every coefficient on one of our rows must come from the variant that row declares. The `ipcc_variant` column in `reference/DEFAULTS_MASTER.md` records which one.

`mcf_tropical_dry` mirrors `mcf_tropical` on every system: the 2019 Refinement resolves ten climate zones and the tool resolves four.

## Climate basis

Three Chapter 11 factors have separate wet and dry climate values in IPCC, and the tool ships the wet-climate figure for everyone:

| factor | wet (shipped) | dry | aggregated |
|---|---|---|---|
| EF3_PRP | 0.006 | 0.002 | 0.004 |
| EF4 | 0.014 | 0.005 | 0.010 |
| Frac_LEACH_PRP | 0.24 | 0 | not published |

A dry-climate inventory that accepts the defaults therefore overstates pasture N2O and, for leaching, reports a pathway IPCC treats as absent. The decision taken was to keep the wet-climate defaults, document the alternatives, and warn rather than add a required climate input. Flagged here because it affects any dry-climate country using the tool.

## Where these values live

`reference/defaults_master.csv` is the single authority. Every other surface (the Excel template, the AI translator prompts, the methodology and user guide, the worked examples) is generated from it, and `scripts/verify_defaults.R` checks all 14 surfaces against it on every build. A value accepted here is changed in that one file and propagates everywhere.

