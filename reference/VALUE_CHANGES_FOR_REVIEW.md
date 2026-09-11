# IPCC default values: what changed, and what we think is still wrong

Generated 2026-09-11 by `scripts/build_review_table.R`. Do not edit by hand.

## What this is

Every IPCC default the cattle uncertainty tool ships was read back against the IPCC source text, value by value, in September 2026. This is the result, laid out so it can be checked.

The **before** column is the value as it stood at commit `fbfa1bc` (2026-07-10), the last change before September and the last recorded deployment. That is still what the live app runs, so the before column is what a user would get today. It is extracted from git by `scripts/extract_baseline_defaults.R`, never retyped.

**What each status is asking of you:**

| status | count | meaning |
|---|---|---|
| `APPLIED` | 74 | Already changed. The IPCC basis was unambiguous and no review round had ruled on the value. Please endorse, or object. |
| `PROPOSED` | 3 | We think it is wrong, but a numbered review round adjudicated it, so it has **not** been changed. Your call. |
| `OPEN` | 6 | Differs from IPCC with no recorded reason and no review history. A judgement call we did not want to take alone. |
| `APPLIED_OVERTURNS_REVIEW` | 1 | **Changed, and it reverses a value a review round agreed.** Read these first. |

Nothing here has been pushed or deployed.

---

## 0. Applied, and it overturns an earlier review decision (1)

The one thing in this document that most needs a second opinion.

| object | key | field | was 2026-07-10 | now | review round | why |
|---|---|---|---|---|---|---|
| PARAM_CATALOGUE | Milk | ipcc_default | 3.5 | 1.2 | R8 p7 | Changed from 3.5 to 1.2 by the low-productivity basis decision of 2026-09-11. 3.5 was the Africa AGGREGATE row of Table 10A.1, a population-weighted average of the high (5.8) and low (1.2) productivity systems; 1.2 is the low-productivity row. Review round 8 page 7 agreed 3.5 against a previous unsourced 4.0, and that was right FOR THE AGGREGATE ROW. What changed is the basis, not the reading: the productivity question does not appear to have been put to the reviewer. Reverting is a single cell in the master. |

## 1. Already applied (74)

Changed since 2026-07-10. Each cites the IPCC table it was read from.

| object | key | field | before | now | affects | IPCC source |
|---|---|---|---|---|---|---|
| CP_BY_SUBCAT | calves_female | value | 10 | 10.3 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: CP in diet 10.3% |
| CP_BY_SUBCAT | calves_male | value | 10 | 10.3 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: CP in diet 10.3% |
| CP_BY_SUBCAT | dairy_cows | value | 10 | 9.6 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: CP in diet 9.6%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. |
| CP_BY_SUBCAT | feedlot_cattle | value | 10 | 14 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Latin America and North America Feedlot cattle both give CP in diet 14.0% |
| CP_BY_SUBCAT | growing_males | value | 10 | 10.4 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: CP in diet 10.4% |
| CP_BY_SUBCAT | heifers | value | 10 | 10.4 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: CP in diet 10.4% |
| DE_BY_SUBCAT | bulls | value | 55 | 58 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Bulls - Grazing: digestibility of feed 58% |
| DE_BY_SUBCAT | calves_female | value | 55 | 59 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: digestibility of feed 59% |
| DE_BY_SUBCAT | calves_male | value | 55 | 59 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: digestibility of feed 59% |
| DE_BY_SUBCAT | dairy_cows | value | 55 | 51 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: digestibility of feed 51%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. |
| DE_BY_SUBCAT | feedlot_cattle | value | 55 | 74 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Latin America Feedlot cattle: digestibility of feed 74%. Required by Table 10.12, whose feedlot Ym of 4.0 is conditional on DE >= 72 |
| DE_BY_SUBCAT | growing_males | value | 55 | 59 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: digestibility of feed 59% |
| DE_BY_SUBCAT | heifers | value | 55 | 59 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: digestibility of feed 59% |
| DE_BY_SUBCAT | other_cows | value | 55 | 58 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Mature Females - grazing, Large Areas: digestibility of feed 58% |
| DE_BY_SUBCAT | oxen | value | 55 | 58 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Draft Bullocks: digestibility of feed 58% |
| IPCC_DEFAULTS_BY_REGION | africa | default_val_dairy |  | 270 | QA benchmark only, not a calculation input | 2019R V4 Ch10 Table 10A.1 (New), Africa Low productivity systems: 270 kg (aggregate 260, high productivity 250) |
| IPCC_DEFAULTS_BY_REGION | americas | default_val_dairy |  | 500 | QA benchmark only, not a calculation input | 2019R V4 Ch10 Table 10A.1 (New), Latin America Low productivity systems: 500 kg (aggregate 508, high 520). North America is 650 |
| IPCC_DEFAULTS_BY_REGION | asia | default_val_dairy |  | 355 | QA benchmark only, not a calculation input | 2019R V4 Ch10 Table 10A.1 (New), Asia Low productivity systems: 355 kg (aggregate 386, high productivity 485) |
| IPCC_DEFAULTS_BY_REGION | europe | default_val_dairy |  | 600 | QA benchmark only, not a calculation input | 2019R V4 Ch10 Table 10A.1 (New), Western Europe: 600 kg. Eastern Europe is 550; no productivity split is published for either |
| IPCC_DEFAULTS_BY_REGION | global | default_val_dairy |  | 400 | QA benchmark only, not a calculation input | Table 10A.1 has no global row. 400 kg is a project benchmark carried over from the non-dairy column |
| IPCC_DEFAULTS_BY_REGION | oceania | default_val_dairy |  | 488 | QA benchmark only, not a calculation input | 2019R V4 Ch10 Table 10A.1 (New), Oceania: 488 kg; no productivity split published |
| LW_BY_SUBCAT | dairy_cows | value | 275 | 270 | gross energy, so enteric CH4 + manure CH4 + N excretion | Table 10A.1 gives Africa DAIRY weight 260 kg. The 275 used here is the Table 10A.2 non-dairy grazing weight, so the dairy sub-category carries a non-dairy figure |
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
| PARAM_CATALOGUE | BW | ipcc_default | 275 | 270 | gross energy, so enteric CH4 + manure CH4 | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: Weight 270 kg. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. |
| PARAM_CATALOGUE | CP | ipcc_default | 10 | 9.6 | N excretion | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: CP in diet 9.6%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 10.0% was the Table 10A.2 non-dairy grazing figure, which now sits on the non-dairy sub-categories instead. |
| PARAM_CATALOGUE | DE | ipcc_default | 55 | 51 | gross energy | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: digestibility of feed 51%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 55% sat between the two tables and matched neither. |
| PARAM_CATALOGUE | MilkPR | ipcc_default | 3.3 | 3.6 | gross energy, so enteric CH4 + manure CH4 | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: protein content of milk 3.6%. Identical in all three Africa rows of Table 10A.1 and in Table 10A.2, and the tool's own documented route %MilkPR = 1.9 + 0.4 x %Fat gives 3.62 at Fat 4.3. The previous 3.3 was what that formula returns for Fat 3.5, the value Fat held before review round 8 corrected it. |
| PARAM_CATALOGUE | pct_pregnant | ipcc_default | 0.6 | 0.52 | gross energy, so enteric CH4 + manure CH4 | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: 52% pregnant. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 0.60 matched no row in either table. |
| PCT_PREGNANT_BY_SUBCAT | dairy_cows | value | 0.85 | 0.52 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: 52% pregnant. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 0.85 was the Eastern Europe dairy rate, which sat on a different continent from every other default in the tool. |
| PCT_PREGNANT_BY_SUBCAT | other_cows | value | 0.85 | 0.54 | gross energy and N excretion | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Mature Females - grazing, Large Areas: 54% pregnant. The previous 0.85 was the Eastern Europe dairy rate. |
| YM_BY_SUBCAT | bulls | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | calves_female | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | calves_male | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | feedlot_cattle | ym_2006 | 6.5 | 3 | enteric CH4 | 2006 V4 Ch10 Table 10.12, p.10.30: 'Feedlot fed Cattle' 3.0%, footnote a 'when fed diets contain 90 percent or more concentrates' |
| YM_BY_SUBCAT | feedlot_cattle | ym_2019_refinement | 6.5 | 4 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Feedlot (all other grains, 0-15% forage), DE >= 72, Ym 4.0%. Annex 10A.2 Latin America Feedlot cattle confirms it at DE 74. North America feedlot sits at DE 75 with Ym 3.0, the steam-flaked corn row |
| YM_BY_SUBCAT | growing_males | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | heifers | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | other_cows | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |
| YM_BY_SUBCAT | oxen | ym_2019_refinement | 6.5 | 7 | enteric CH4 | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 |

## 2. Proposed, not changed: a review round ruled on these (3)

Left alone deliberately. The earlier decision may rest on context the code does not record.

| object | key | field | was 2026-07-10 | current | proposed | review round | why |
|---|---|---|---|---|---|---|---|
| IPCC_DEFAULTS_BY_REGION | asia | default_val | 350 | 350 | (decide) | R7 #3 | Table 10A.1 Asia dairy is 386 (low productivity 355); Table 10A.2 Asia gives 376 and 305. The shipped 350 matches no Asia row. Review round 7 item 3 kept this object for BW only after the other benchmarks were withdrawn. |
| IPCC_DEFAULTS_BY_REGION | oceania | default_val | 500 | 500 | (decide) | R7 #3 | Table 10A.1 Oceania dairy is 488; Table 10A.2 gives 416 and 467. The shipped 500 appears in no Oceania row. Same review provenance as asia. |
| PARAM_CATALOGUE | Fat | ipcc_default | 4.3 | 4.3 | no change | R8 p7 | UNCHANGED and confirmed. Table 10A.1 gives 4.3 for Africa in all three rows (aggregate, high productivity and low productivity), so the low-productivity basis decision cannot move it. The round 8 comment that IPCC 2019 gives 4.3 for Africa is exactly right. Listed only so the reviewer can see it was rechecked and survived the basis change that moved Milk. |

## 3. Open questions (6)

Differs from IPCC with no recorded reason. These would move a reported number. Where the `was` and `current` columns differ, the value was already changed in September and we now think it should move again.

| object | key | field | was 2026-07-10 | current | proposed | affects | why |
|---|---|---|---|---|---|---|---|
| MMS_DEFAULTS | composting | mcf_boreal | 0.5 | 0.5 | 1.0 | manure CH4 | See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant. |
| MMS_DEFAULTS | composting | mcf_temperate | 1 | 0.5 | 2.0 | manure CH4 | See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant. |
| MMS_DEFAULTS | composting | mcf_tropical | 1.5 | 0.5 | 2.5 | manure CH4 | The row declares the Static Pile variant and its EF3 (0.010) and Frac (0.65) both follow it, but 0.5 is the 2019R In-vessel figure. 2019R Table 10.17 gives Composting - Static pile (Forced aeration) 1.00 cool / 2.00 temperate / 2.50 warm. Correct as-is under 2006, where static pile is 0.5. |
| MMS_DEFAULTS | composting | mcf_tropical_dry | 1.5 | 0.5 | 2.5 | manure CH4 | See mcf_tropical. This column mirrors mcf_tropical on every system, so it moves with it. |
| MMS_FRAC_DEFAULTS_2019 | anaerobic_digester | frac_gas_high | 0.08 | 0.08 | 0.50 | indirect N2O (volatilisation) | Table 10.22 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central. The tool takes 0.05 as the central and samples 0.02 to 0.08, so its whole range sits at or below IPCC's floor and its ceiling is six times too low. |
| PARAM_CATALOGUE | MW | ipcc_ref | Table 10A.2 | Table 10A.2 | (none) | gross energy, so enteric CH4 + manure CH4 | Cites Table 10A.2, which has no mature-weight column; neither does Table 10A.1. IPCC publishes no default for mature weight. Review round 7 item 3 raised exactly this; the companion value (400 kg BW) was fixed and this citation was not. |

---

## One change with no row in the tables above

The biological-zero rule tested only for males, so every non-male sub-category inherited the dairy-cow milk yield of 3.5 kg/day, including heifers (which by the tool's own label have not calved), female calves and feedlot cattle. That added a net-energy-for-lactation term to animals that cannot produce milk. Annex 10A.2 gives a milk yield only to its Mature Females rows, in every region; Growing/Replacement, Calves and Feedlot cattle are blank.

Corrected so that Milk, Fat and MilkPR are non-zero only for mature females. Measured per 100,000 head: heifers enteric CH4 6161.7 to 5170.6 t/yr (-16.1%), feedlot cattle 3655.2 to 3214.3 (-12.1%). Calves were unaffected numerically because the separate pregnancy zero already suppressed the term, but the filled template had been showing a milk yield for a calf.

It does not appear in the tables above because it is a rule in the resolver, not a value in the defaults file.

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

