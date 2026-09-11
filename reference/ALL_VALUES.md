# Every shipped value: July, now, source and reach

Generated 2026-09-11 by `scripts/build_full_value_table.R`. Do not edit by hand.

All 291 numeric values the tool ships. Unlike `VALUE_CHANGES_FOR_REVIEW.md`, which lists only what changed, this lists everything, because "we checked it and it did not move" is also a result.

| column | what it is |
|---|---|
| **July** | the value at commit `fbfa1bc`, 2026-07-10, the last change before September and the last recorded deployment. Extracted from git by script, never retyped. `(new)` means the row did not exist then. |
| **Now** | the value in `reference/defaults_master.csv`, the single authority every other surface is built from. |
| **Source** | the exact IPCC table, page and row the value was read from, or an explicit statement that IPCC publishes nothing for it. |
| **Reach** | how many of the 15 checked surfaces carry this value and whether they agree. `master only` is normal: most values appear on only a few surfaces. |

- 92 values moved since July, 199 did not
- verdicts: 216 CONFIRMED, 23 DEVIATION_DOCUMENTED, 14 DEVIATION_OPEN, 6 INTERPRETED, 13 NO_IPCC_DEFAULT, 19 NOT_IPCC
- propagation: 0 values disagree across surfaces

## The 25 parameters

`PARAM_CATALOGUE`, 54 values, 7 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| N | suggested_uncertainty_pct | 10 | 10 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| BW | ipcc_default | 275 | 270 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: Weight 270 kg. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. | 3 surfaces, all agree |
| BW | suggested_uncertainty_pct | 15 | 15 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| MW | ipcc_default | 300 | 300 |  | `NO_IPCC_DEFAULT` | Neither Table 10A.1 nor Table 10A.2 has a mature-weight column; the cited table does not contain this value. Reviewer R7 #3 listed 300 kg MW as unfindable in IPCC | 3 surfaces, all agree |
| MW | suggested_uncertainty_pct | 10 | 10 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| WG | ipcc_default | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa dairy row, p.10.104: weight gain 0 for every dairy row | 3 surfaces, all agree |
| WG | suggested_uncertainty_pct | 30 | 30 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Milk | ipcc_default | 3.5 | 1.2 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: milk yield 1.2 kg/day. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 3.5 was the Africa AGGREGATE row, a population-weighted average of the high (5.8) and low (1.2) productivity systems per footnote 4. Changing it overturns the value agreed at review round 8 page 7, which was right for the aggregate row; the basis, not the reading, is what changed. | 4 surfaces, all agree |
| Milk | suggested_uncertainty_pct | 20 | 20 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Fat | ipcc_default | 4.3 | 4.3 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: fat content 4.3%. Identical in the aggregate, high and low productivity rows, so the basis choice cannot move it. Agreed at review round 8 page 7 and unaffected. | 3 surfaces, all agree |
| Fat | suggested_uncertainty_pct | 10 | 10 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| pct_pregnant | ipcc_default | 0.6 | 0.52 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: 52% pregnant. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 0.60 matched no row in either table. | 2 surfaces, all agree |
| pct_pregnant | suggested_uncertainty_pct | 20 | 20 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| DE | ipcc_default | 55 | 51 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: digestibility of feed 51%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 55% sat between the two tables and matched neither. | 3 surfaces, all agree |
| DE | suggested_uncertainty_pct | 15 | 15 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Cfi | ipcc_default | 0.386 | 0.386 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: lactating cows 0.386 | 4 surfaces, all agree |
| Cfi | suggested_uncertainty_pct | 30 | 30 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Ca | ipcc_default | 0.17 | 0.17 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.5 (Updated), p.10.25: Pasture 0.17 | 6 surfaces, all agree |
| Ca | suggested_uncertainty_pct | 30 | 30 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |
| C | ipcc_default | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 4 surfaces, all agree |
| C | suggested_uncertainty_pct | 30 | 30 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Cp | ipcc_default | 0.1 | 0.1 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.7 (Updated), constants for Eq 10.13: Cattle and Buffalo 0.10 | 5 surfaces, all agree |
| Cp | suggested_uncertainty_pct | 10 | 10 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |
| hours | ipcc_default | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa dairy row, p.10.104: work 0 hrs/day for every dairy row | 4 surfaces, all agree |
| hours | suggested_uncertainty_pct | 20 | 20 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| CP | ipcc_default | 10 | 9.6 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: CP in diet 9.6%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 10.0% was the Table 10A.2 non-dairy grazing figure, which now sits on the non-dairy sub-categories instead. | 3 surfaces, all agree |
| CP | suggested_uncertainty_pct | 15 | 15 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 2 surfaces, all agree |
| Ym | ipcc_default | 6.5 | 6.5 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Low producing cows (<5000 kg/yr), DE <= 62, NDF > 38, Ym 6.5%. Footnote 4 restricts the dairy rows to LACTATING cows, which is exactly the dairy_cows sub-category, so 6.5 is right as the dairy default and wrong as the generic one: the same table gives 7.0 for non-dairy >75% forage and 4.0 for feedlot. See the Ym section of the provenance register | 4 surfaces, all agree |
| Ym | suggested_uncertainty_pct | 20 | 20 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated) footnote 3: 'Uncertainty values are +/- 20% based on published standard deviations from Niu et al. (2018) and data compilations for non dairy cattle as described in Annex 10B.2' | 2 surfaces, all agree |
| Bo | ipcc_default | 0.13 | 0.13 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.16A (Updated), Other regions low productivity: dairy and non-dairy cattle both 0.13 | 5 surfaces, all agree |
| Bo | suggested_uncertainty_pct | 20 | 15 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.16A (Updated), Other regions low productivity footer: uncertainty +/- 15% | 3 surfaces, all agree |
| ASH | ipcc_default | 0.08 | 0.08 |  | `DEVIATION_DOCUMENTED` | 2006 V4 Ch10 Eq 10.24 note: 0.08 for cattle. The 2019 Refinement rewrote the same note around swine (0.06 for sows), so it does not supersede the cattle figure | 5 surfaces, all agree |
| ASH | suggested_uncertainty_pct | 25 | 25 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |
| UE | ipcc_default | 0.04 | 0.04 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.24 note: typically 0.04 GE for most ruminants | 5 surfaces, all agree |
| UE | suggested_uncertainty_pct | 25 | 25 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |
| EF3_PRP | ipcc_default | 0.006 | 0.006 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.1 (Updated), EF3PRP CPP wet climates: 0.006 | 5 surfaces, all agree |
| EF3_PRP | suggested_lower_bound | 0.0005 | 0.0005 |  | `DEVIATION_DOCUMENTED` | IPCC gives 0.000 as the lower bound. The tool uses a small positive floor because a zero lower bound is degenerate for the bounded distributions; documented deviation | 1 surfaces, all agree |
| EF3_PRP | suggested_upper_bound | 0.027 | 0.027 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.1 (Updated): upper 0.027 | 1 surfaces, all agree |
| EF4 | ipcc_default | 0.014 | 0.014 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.014 | 5 surfaces, all agree |
| EF4 | suggested_lower_bound | 0.011 | 0.011 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.011 | 1 surfaces, all agree |
| EF4 | suggested_upper_bound | 0.017 | 0.017 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.017 | 1 surfaces, all agree |
| EF5 | ipcc_default | 0.011 | 0.011 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated): 0.011 | 4 surfaces, all agree |
| EF5 | suggested_lower_bound | 0.0005 | 0.0005 |  | `DEVIATION_DOCUMENTED` | IPCC gives 0.000 as the lower bound. The tool uses a small positive floor because a zero lower bound is degenerate for the bounded distributions; documented deviation | 1 surfaces, all agree |
| EF5 | suggested_upper_bound | 0.02 | 0.02 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated): upper 0.020 | 1 surfaces, all agree |
| Frac_GASM_PRP | ipcc_default | 0.21 | 0.21 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), FracGASM: 0.21 | 4 surfaces, all agree |
| Frac_GASM_PRP | suggested_lower_bound | 0.005 | 0.005 |  | `DEVIATION_DOCUMENTED` | IPCC gives 0.000 as the lower bound. The tool uses a small positive floor because a zero lower bound is degenerate for the bounded distributions; documented deviation | 1 surfaces, all agree |
| Frac_GASM_PRP | suggested_upper_bound | 0.31 | 0.31 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), FracGASM: upper 0.31 | 1 surfaces, all agree |
| Frac_LEACH_PRP | ipcc_default | 0.24 | 0.24 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H) wet climates: 0.24, confirmed in the body text at Ch11 s11.2.2 | 5 surfaces, all agree |
| Frac_LEACH_PRP | suggested_lower_bound | 0.01 | 0.01 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H): lower 0.01 | 1 surfaces, all agree |
| Frac_LEACH_PRP | suggested_upper_bound | 0.73 | 0.73 |  | `CONFIRMED` | 2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H): upper 0.73 | 1 surfaces, all agree |
| MilkPR | ipcc_default | 3.3 | 3.6 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: protein content of milk 3.6%. Identical in all three Africa rows of Table 10A.1 and in Table 10A.2, and the tool's own documented route %MilkPR = 1.9 + 0.4 x %Fat gives 3.62 at Fat 4.3. The previous 3.3 was what that formula returns for Fat 3.5, the value Fat held before review round 8 corrected it. | 4 surfaces, all agree |
| MilkPR | suggested_uncertainty_pct | 10 | 10 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |
| Tw | ipcc_default | 20 | 20 |  | `NOT_IPCC` | Winter temperature is country-specific; IPCC publishes no default. Project assumption | 5 surfaces, all agree |
| Tw | suggested_uncertainty_pct | 25 | 25 |  | `NOT_IPCC` | Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide | 3 surfaces, all agree |

## Cfi by sub-category

`CFI_BY_SUBCAT`, 9 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 0.386 | 0.386 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves | 2 surfaces, all agree |
| other_cows | value | 0.322 | 0.322 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves | 1 surfaces, all agree |
| bulls | value | 0.37 | 0.37 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves | 2 surfaces, all agree |
| oxen | value | 0.322 | 0.322 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves. 2019R V4 Ch10 Table 10A.2 footnote 8: 'Draft bullocks were all assumed to be castrates and CFi values were adjusted accordingly'. Castrates are steers, so 0.322 | 2 surfaces, all agree |
| heifers | value | 0.322 | 0.322 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves | 2 surfaces, all agree |
| growing_males | value | 0.322 | 0.322 |  | `INTERPRETED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves. IPCC's 0.370 row is labelled 'bulls', glossed 'intact males'. The tool reads 'bulls' as mature breeding males and assigns the steers/heifers/calves value to growing and immature males. Defensible, but a reading rather than a quotation | 2 surfaces, all agree |
| calves_female | value | 0.322 | 0.322 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves | 1 surfaces, all agree |
| calves_male | value | 0.322 | 0.322 |  | `INTERPRETED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves. IPCC's 0.370 row is labelled 'bulls', glossed 'intact males'. The tool reads 'bulls' as mature breeding males and assigns the steers/heifers/calves value to growing and immature males. Defensible, but a reading rather than a quotation | 1 surfaces, all agree |
| feedlot_cattle | value | 0.322 | 0.322 |  | `INTERPRETED` | 2019R V4 Ch10 Table 10.4 (Updated), p.10.24: 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves. IPCC's 0.370 row is labelled 'bulls', glossed 'intact males'. The tool reads 'bulls' as mature breeding males and assigns the steers/heifers/calves value to growing and immature males. Defensible, but a reading rather than a quotation | 1 surfaces, all agree |

## C by sub-category

`C_GROWTH_BY_SUBCAT`, 9 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 2 surfaces, all agree |
| other_cows | value | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 1 surfaces, all agree |
| bulls | value | 1.2 | 1.2 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 2 surfaces, all agree |
| oxen | value | 1 | 1 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 2 surfaces, all agree |
| heifers | value | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 2 surfaces, all agree |
| growing_males | value | 1 | 1 |  | `INTERPRETED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996). The tool assigns the castrate value 1.0 to growing and feedlot males, the same reading it applies to Cfi | 2 surfaces, all agree |
| calves_female | value | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996) | 1 surfaces, all agree |
| calves_male | value | 1 | 1 |  | `INTERPRETED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996). The tool assigns the castrate value 1.0 to growing and feedlot males, the same reading it applies to Cfi | 1 surfaces, all agree |
| feedlot_cattle | value | 1 | 1 |  | `INTERPRETED` | 2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996). The tool assigns the castrate value 1.0 to growing and feedlot males, the same reading it applies to Cfi | 1 surfaces, all agree |

## Ym by sub-category and edition

`YM_BY_SUBCAT`, 18 values, 18 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| dairy_cows | ym_2019_refinement | (new) | 6.5 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Low producing cows (<5000 kg/yr), DE <= 62, NDF > 38, Ym 6.5%. The dairy_cows sub-category is mature LACTATING females, which is exactly the population footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' restricts these rows to | 2 surfaces, all agree |
| other_cows | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| other_cows | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| bulls | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| bulls | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| oxen | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| oxen | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| heifers | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| heifers | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 2 surfaces, all agree |
| growing_males | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| growing_males | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| calves_female | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| calves_female | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| calves_male | ym_2006 | (new) | 6.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot | 1 surfaces, all agree |
| calves_male | ym_2019_refinement | (new) | 7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included. For other_cows, which includes dry dairy cows, footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected' sends them to the same 7.0 | 1 surfaces, all agree |
| feedlot_cattle | ym_2006 | (new) | 3 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.12, p.10.30: 'Feedlot fed Cattle' 3.0%, footnote a 'when fed diets contain 90 percent or more concentrates' | 1 surfaces, all agree |
| feedlot_cattle | ym_2019_refinement | (new) | 4 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.12 (Updated): Feedlot (all other grains, 0-15% forage), DE >= 72, Ym 4.0%. Annex 10A.2 Latin America Feedlot cattle confirms it at DE 74. North America feedlot sits at DE 75 with Ym 3.0, the steam-flaked corn row | 1 surfaces, all agree |

## Body weight by sub-category

`LW_BY_SUBCAT`, 9 values, 1 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 275 | 270 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: Weight 270 kg. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. Previously 275, the Table 10A.2 non-dairy grazing weight, so the dairy sub-category had been carrying a non-dairy figure. | 1 surfaces, all agree |
| other_cows | value | 275 | 275 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Mature Females - grazing, Large Areas 275 kg | 1 surfaces, all agree |
| bulls | value | 350 | 350 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Mature Males 540 kg, Bulls - Grazing 340 kg. The 350 used here matches neither | 1 surfaces, all agree |
| oxen | value | 300 | 300 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Draft Bullocks 340 kg. The 300 used here is 12% lower | 1 surfaces, all agree |
| heifers | value | 200 | 200 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Growing/Replacement 204 kg. The 200 used here is a rounding of it, not a transcription | 1 surfaces, all agree |
| growing_males | value | 200 | 200 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Growing/Replacement 204 kg. The 200 used here is a rounding of it, not a transcription | 1 surfaces, all agree |
| calves_female | value | 60 | 60 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Calves on forage 82 kg. The 60 used here is 27% lower than any IPCC calf row | 1 surfaces, all agree |
| calves_male | value | 60 | 60 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Calves on forage 82 kg. The 60 used here is 27% lower than any IPCC calf row | 1 surfaces, all agree |
| feedlot_cattle | value | 250 | 250 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108 has no Africa feedlot row. The two published feedlot weights are North America 500 kg and Latin America 460 kg. The 250 used here is half the lower of them | 1 surfaces, all agree |

## Mature weight by sub-category

`MW_BY_SUBCAT`, 9 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 300 | 300 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| other_cows | value | 300 | 300 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| bulls | value | 400 | 400 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| oxen | value | 350 | 350 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| heifers | value | 300 | 300 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| growing_males | value | 350 | 350 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| calves_female | value | 300 | 300 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| calves_male | value | 350 | 350 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |
| feedlot_cattle | value | 400 | 400 |  | `NO_IPCC_DEFAULT` | Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults | 1 surfaces, all agree |

## Weight gain by sub-category

`WG_BY_SUBCAT`, 9 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1: weight gain 0 for every dairy row | 2 surfaces, all agree |
| other_cows | value | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: mature female rows carry no weight gain | 1 surfaces, all agree |
| bulls | value | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: mature male rows carry no weight gain | 1 surfaces, all agree |
| oxen | value | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Draft Bullocks carry no weight gain | 1 surfaces, all agree |
| heifers | value | 0.25 | 0.25 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Growing/Replacement 0.24 kg/day. The 0.25 used here is a rounding of it | 2 surfaces, all agree |
| growing_males | value | 0.2 | 0.2 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Growing/Replacement 0.24 kg/day. The 0.20 used here is 17% lower and matches no Africa row | 1 surfaces, all agree |
| calves_female | value | 0.3 | 0.3 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Calves on forage 0.33 kg/day. The 0.30 used here is a rounding of it | 1 surfaces, all agree |
| calves_male | value | 0.3 | 0.3 |  | `DEVIATION_OPEN` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Calves on forage 0.33 kg/day. The 0.30 used here is a rounding of it | 1 surfaces, all agree |
| feedlot_cattle | value | 1 | 1 |  | `DEVIATION_OPEN` | Table 10A.2 has no Africa feedlot row. Published feedlot gains are North America 1.4 and Latin America 0.90 kg/day. The 1.0 used here falls between them | 1 surfaces, all agree |

## Digestibility by sub-category

`DE_BY_SUBCAT`, 9 values, 9 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | (new) | 51 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: digestibility of feed 51%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. | 1 surfaces, all agree |
| other_cows | value | (new) | 58 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Mature Females - grazing, Large Areas: digestibility of feed 58% | 1 surfaces, all agree |
| bulls | value | (new) | 58 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Bulls - Grazing: digestibility of feed 58% | 1 surfaces, all agree |
| oxen | value | (new) | 58 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Draft Bullocks: digestibility of feed 58% | 1 surfaces, all agree |
| heifers | value | (new) | 59 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: digestibility of feed 59% | 1 surfaces, all agree |
| growing_males | value | (new) | 59 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: digestibility of feed 59% | 1 surfaces, all agree |
| calves_female | value | (new) | 59 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: digestibility of feed 59% | 1 surfaces, all agree |
| calves_male | value | (new) | 59 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: digestibility of feed 59% | 1 surfaces, all agree |
| feedlot_cattle | value | (new) | 74 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Latin America Feedlot cattle: digestibility of feed 74%. Required by Table 10.12, whose feedlot Ym of 4.0 is conditional on DE >= 72 | 1 surfaces, all agree |

## Crude protein by sub-category

`CP_BY_SUBCAT`, 9 values, 9 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | (new) | 9.6 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: CP in diet 9.6%. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. | 1 surfaces, all agree |
| other_cows | value | (new) | 10 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Mature Females - grazing, Large Areas: CP in diet 10.0% | 1 surfaces, all agree |
| bulls | value | (new) | 10 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Bulls - Grazing: CP in diet 10.0% | 1 surfaces, all agree |
| oxen | value | (new) | 10 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Draft Bullocks: CP in diet 10.0% | 1 surfaces, all agree |
| heifers | value | (new) | 10.4 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: CP in diet 10.4% | 1 surfaces, all agree |
| growing_males | value | (new) | 10.4 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Growing/Replacement: CP in diet 10.4% | 1 surfaces, all agree |
| calves_female | value | (new) | 10.3 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: CP in diet 10.3% | 1 surfaces, all agree |
| calves_male | value | (new) | 10.3 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Calves on forage: CP in diet 10.3% | 1 surfaces, all agree |
| feedlot_cattle | value | (new) | 14 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Latin America and North America Feedlot cattle both give CP in diet 14.0% | 1 surfaces, all agree |

## Pregnancy fraction by sub-category

`PCT_PREGNANT_BY_SUBCAT`, 3 values, 2 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| dairy_cows | value | 0.85 | 0.52 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104: 52% pregnant. Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions. The previous 0.85 was the Eastern Europe dairy rate, which sat on a different continent from every other default in the tool. | 2 surfaces, all agree |
| other_cows | value | 0.85 | 0.54 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108, Mature Females - grazing, Large Areas: 54% pregnant. The previous 0.85 was the Eastern Europe dairy rate. | 1 surfaces, all agree |
| heifers | value | 0.5 | 0.5 |  | `NO_IPCC_DEFAULT` | Table 10A.2 leaves the Pregnant column blank for Growing/Replacement, so IPCC publishes no figure for replacement heifers. 0.50 is a project assumption and must not be presented as an IPCC default. | 2 surfaces, all agree |

## Activity coefficient by feeding situation

`FEEDING_SITUATION_CA`, 3 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| stall_fed | value | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.5 (Updated), p.10.25: Stall 0 | 1 surfaces, all agree |
| pasture_flat | value | 0.17 | 0.17 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.5 (Updated), p.10.25: Pasture 0.17 | 1 surfaces, all agree |
| pasture_hilly | value | 0.36 | 0.36 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.5 (Updated), p.10.25: Grazing large areas 0.36 | 1 surfaces, all agree |

## Manure systems: methane conversion and direct N2O

`MMS_DEFAULTS`, 60 values, 26 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| pasture | ef3 | 0.02 | 0.02 |  | `DEVIATION_DOCUMENTED` | 0.02 is the Chapter 11 EF3PRP for cattle on pasture, not a Table 10.21 manure-management factor. Table 10.21 routes pasture N to Chapter 11 explicitly. Carried on this row so the pasture pathway resolves; documented | 6 surfaces, all agree |
| pasture | mcf_boreal | 1 | 1 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Pasture/Range/Paddock: 1.0 / 1.5 / 2.0 | 3 surfaces, all agree |
| pasture | mcf_temperate | 1 | 1.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Pasture/Range/Paddock: 1.0 / 1.5 / 2.0 | 3 surfaces, all agree |
| pasture | mcf_tropical | 1.5 | 2 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Pasture/Range/Paddock: 1.0 / 1.5 / 2.0 | 6 surfaces, all agree |
| pasture | mcf_tropical_dry | 1.5 | 2 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| daily_spread | ef3 | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Daily spread: 0 | 4 surfaces, all agree |
| daily_spread | mcf_boreal | 0.1 | 0.1 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Daily spread: 0.1 / 0.5 / 1.0 | 3 surfaces, all agree |
| daily_spread | mcf_temperate | 0.5 | 0.5 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Daily spread: 0.1 / 0.5 / 1.0 | 3 surfaces, all agree |
| daily_spread | mcf_tropical | 1 | 1 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Daily spread: 0.1 / 0.5 / 1.0 | 4 surfaces, all agree |
| daily_spread | mcf_tropical_dry | 1 | 1 |  | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| solid_storage | ef3 | 0.01 | 0.01 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Solid storage: 0.010 | 7 surfaces, all agree |
| solid_storage | mcf_boreal | 3 | 2 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Solid storage: 2.0 / 4.0 / 5.0 | 3 surfaces, all agree |
| solid_storage | mcf_temperate | 4 | 4 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Solid storage: 2.0 / 4.0 / 5.0 | 3 surfaces, all agree |
| solid_storage | mcf_tropical | 5 | 5 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Solid storage: 2.0 / 4.0 / 5.0 | 6 surfaces, all agree |
| solid_storage | mcf_tropical_dry | 5 | 5 |  | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| solid_storage_covered | ef3 | 0.01 | 0.01 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Solid storage - Covered/compacted: 0.01 | 4 surfaces, all agree |
| solid_storage_covered | mcf_boreal | 1 | 2 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 | 3 surfaces, all agree |
| solid_storage_covered | mcf_temperate | 2 | 4 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 | 3 surfaces, all agree |
| solid_storage_covered | mcf_tropical | 4 | 5 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.17 (Updated), Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00 | 3 surfaces, all agree |
| solid_storage_covered | mcf_tropical_dry | 4 | 5 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| dry_lot | ef3 | 0.02 | 0.02 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Dry lot: 0.02 | 4 surfaces, all agree |
| dry_lot | mcf_boreal | 1 | 1 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Dry lot: 1.0 / 1.5 / 2.0 | 3 surfaces, all agree |
| dry_lot | mcf_temperate | 1.5 | 1.5 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Dry lot: 1.0 / 1.5 / 2.0 | 3 surfaces, all agree |
| dry_lot | mcf_tropical | 5 | 2 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature and 2019R V4 Ch10 Table 10.17 (Updated), Dry lot: 1.0 / 1.5 / 2.0 | 3 surfaces, all agree |
| dry_lot | mcf_tropical_dry | 5 | 2 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| deep_bedding | ef3 | 0.01 | 0.01 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Cattle and swine deep bedding, No mixing: 0.01 | 3 surfaces, all agree |
| deep_bedding | mcf_boreal | 3 | 17 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| deep_bedding | mcf_temperate | 17 | 39 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| deep_bedding | mcf_tropical | 30 | 80 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| deep_bedding | mcf_tropical_dry | 30 | 80 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| liquid_slurry | ef3 | 0.005 | 0.005 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Liquid/Slurry With natural crust cover: 0.005 | 6 surfaces, all agree |
| liquid_slurry | mcf_boreal | 10 | 10 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Liquid/Slurry with natural crust cover: 10 / 24 / 50. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| liquid_slurry | mcf_temperate | 35 | 24 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Liquid/Slurry with natural crust cover: 10 / 24 / 50. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| liquid_slurry | mcf_tropical | 80 | 50 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Liquid/Slurry with natural crust cover: 10 / 24 / 50. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 4 surfaces, all agree |
| liquid_slurry | mcf_tropical_dry | 80 | 50 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| composting | ef3 | 0.006 | 0.01 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Composting - Static Pile (Forced aeration): 0.010 | 4 surfaces, all agree |
| composting | mcf_boreal | 0.5 | 0.5 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Composting - Static pile: 0.5 / 0.5 / 0.5, marked 'Not temperature dependant'. This was briefly recorded as a DEVIATION_OPEN on the grounds that 2019R gives Static pile (Forced aeration) 1.00 / 2.00 / 2.50 and 0.5 is the 2019R In-vessel figure. That reading was WRONG: the tool's declared MCF basis is the 2006 table, where static pile IS 0.5, and 10 of the 12 systems read their MCF from it. The variant is consistent across all three coefficient families; only the edition differs between families, which is the documented tool-wide convention. A 2019R user does get 0.5 rather than 1.00 to 2.50, and that is part of the same documented MCF basis, alongside pasture | 3 surfaces, all agree |
| composting | mcf_temperate | 1 | 0.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Composting - Static pile: 0.5 / 0.5 / 0.5, marked 'Not temperature dependant'. This was briefly recorded as a DEVIATION_OPEN on the grounds that 2019R gives Static pile (Forced aeration) 1.00 / 2.00 / 2.50 and 0.5 is the 2019R In-vessel figure. That reading was WRONG: the tool's declared MCF basis is the 2006 table, where static pile IS 0.5, and 10 of the 12 systems read their MCF from it. The variant is consistent across all three coefficient families; only the edition differs between families, which is the documented tool-wide convention. A 2019R user does get 0.5 rather than 1.00 to 2.50, and that is part of the same documented MCF basis, alongside pasture | 3 surfaces, all agree |
| composting | mcf_tropical | 1.5 | 0.5 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Composting - Static pile: 0.5 / 0.5 / 0.5, marked 'Not temperature dependant'. This was briefly recorded as a DEVIATION_OPEN on the grounds that 2019R gives Static pile (Forced aeration) 1.00 / 2.00 / 2.50 and 0.5 is the 2019R In-vessel figure. That reading was WRONG: the tool's declared MCF basis is the 2006 table, where static pile IS 0.5, and 10 of the 12 systems read their MCF from it. The variant is consistent across all three coefficient families; only the edition differs between families, which is the documented tool-wide convention. A 2019R user does get 0.5 rather than 1.00 to 2.50, and that is part of the same documented MCF basis, alongside pasture | 3 surfaces, all agree |
| composting | mcf_tropical_dry | 1.5 | 0.5 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| lagoon | ef3 | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Uncovered anaerobic lagoon: 0 | 3 surfaces, all agree |
| lagoon | mcf_boreal | 66 | 66 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Uncovered anaerobic lagoon: 66 / 77 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| lagoon | mcf_temperate | 66 | 77 | **->** | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Uncovered anaerobic lagoon: 66 / 77 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| lagoon | mcf_tropical | 80 | 80 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Uncovered anaerobic lagoon: 66 / 77 / 80. boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column | 3 surfaces, all agree |
| lagoon | mcf_tropical_dry | 80 | 80 |  | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| anaerobic_digester | ef3 | 0.0006 | 0.0006 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Anaerobic digester: 0.0006 | 4 surfaces, all agree |
| anaerobic_digester | mcf_boreal | 1 | 3.55 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 | 3 surfaces, all agree |
| anaerobic_digester | mcf_temperate | 1 | 4.38 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 | 3 surfaces, all agree |
| anaerobic_digester | mcf_tropical | 3.5 | 4.59 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1 | 4 surfaces, all agree |
| anaerobic_digester | mcf_tropical_dry | 3.5 | 4.59 | **->** | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| aerobic_treatment | ef3 | 0.005 | 0.005 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated), Aerobic treatment, forced aeration: 0.005 | 3 surfaces, all agree |
| aerobic_treatment | mcf_boreal | 0 | 0 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Aerobic treatment: 0 / 0 / 0 | 3 surfaces, all agree |
| aerobic_treatment | mcf_temperate | 0 | 0 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Aerobic treatment: 0 / 0 / 0 | 3 surfaces, all agree |
| aerobic_treatment | mcf_tropical | 0 | 0 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Aerobic treatment: 0 / 0 / 0 | 3 surfaces, all agree |
| aerobic_treatment | mcf_tropical_dry | 0 | 0 |  | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |
| burned_for_fuel | ef3 | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.21 (Updated): reported under Fuel Combustion, not as manure management | 3 surfaces, all agree |
| burned_for_fuel | mcf_boreal | 10 | 10 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Burned for fuel: 10 / 10 / 10 | 3 surfaces, all agree |
| burned_for_fuel | mcf_temperate | 10 | 10 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Burned for fuel: 10 / 10 / 10 | 3 surfaces, all agree |
| burned_for_fuel | mcf_tropical | 10 | 10 |  | `CONFIRMED` | 2006 V4 Ch10 Table 10.17, MCF by average annual temperature, Burned for fuel: 10 / 10 / 10 | 3 surfaces, all agree |
| burned_for_fuel | mcf_tropical_dry | 10 | 10 |  | `DEVIATION_DOCUMENTED` | Mirrors mcf_tropical on every system, so it carries the same value read from 2006 V4 Ch10 Table 10.17, MCF by average annual temperature (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both | 3 surfaces, all agree |

## Manure systems: nitrogen loss fractions

`MMS_FRAC_DEFAULTS_2019`, 72 values, 14 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| pasture | frac_gas | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 3 surfaces, all agree |
| pasture | frac_gas_high | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 2 surfaces, all agree |
| pasture | frac_gas_low | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 2 surfaces, all agree |
| pasture | frac_leach | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 3 surfaces, all agree |
| pasture | frac_leach_high | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 2 surfaces, all agree |
| pasture | frac_leach_low | 0 | 0 |  | `CONFIRMED` | Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting | 2 surfaces, all agree |
| daily_spread | frac_gas | 0.07 | 0.07 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 | 2 surfaces, all agree |
| daily_spread | frac_gas_high | 0.1 | 0.6 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 | 1 surfaces, all agree |
| daily_spread | frac_gas_low | 0.04 | 0.05 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 | 1 surfaces, all agree |
| daily_spread | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Daily spread: 0.07 (0.05-0.60), leach 0 | 2 surfaces, all agree |
| daily_spread | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Daily spread: 0.07 (0.05-0.60), leach 0 | 1 surfaces, all agree |
| daily_spread | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Daily spread: 0.07 (0.05-0.60), leach 0 | 1 surfaces, all agree |
| solid_storage | frac_gas | 0.45 | 0.45 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 | 4 surfaces, all agree |
| solid_storage | frac_gas_high | 0.68 | 0.65 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 | 2 surfaces, all agree |
| solid_storage | frac_gas_low | 0.23 | 0.1 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 | 2 surfaces, all agree |
| solid_storage | frac_leach | 0.02 | 0.02 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage plain: 0.45 (0.10-0.65), leach 0.02 | 3 surfaces, all agree |
| solid_storage | frac_leach_high | 0.03 | 0.03 |  | `DEVIATION_DOCUMENTED` | IPCC publishes the leaching fraction for this system as a point value with no range. The tool applies a +/- 50% band so the parameter can be sampled | 2 surfaces, all agree |
| solid_storage | frac_leach_low | 0.01 | 0.01 |  | `DEVIATION_DOCUMENTED` | IPCC publishes the leaching fraction for this system as a point value with no range. The tool applies a +/- 50% band so the parameter can be sampled | 2 surfaces, all agree |
| solid_storage_covered | frac_gas | 0.22 | 0.22 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 2 surfaces, all agree |
| solid_storage_covered | frac_gas_high | 0.26 | 0.26 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 1 surfaces, all agree |
| solid_storage_covered | frac_gas_low | 0.03 | 0.03 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 1 surfaces, all agree |
| solid_storage_covered | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 2 surfaces, all agree |
| solid_storage_covered | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 1 surfaces, all agree |
| solid_storage_covered | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0 | 1 surfaces, all agree |
| dry_lot | frac_gas | 0.3 | 0.3 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 | 1 surfaces, all agree |
| dry_lot | frac_gas_high | 0.45 | 0.5 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 | 1 surfaces, all agree |
| dry_lot | frac_gas_low | 0.15 | 0.2 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 | 1 surfaces, all agree |
| dry_lot | frac_leach | 0.035 | 0.035 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4 | 2 surfaces, all agree |
| dry_lot | frac_leach_high | 0.07 | 0.07 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 footnote 4: uncertainty range 0 to 0.07 | 1 surfaces, all agree |
| dry_lot | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 footnote 4: uncertainty range 0 to 0.07 | 1 surfaces, all agree |
| deep_bedding | frac_gas | 0.25 | 0.25 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Cattle and swine deep bedding: 0.25 (0.10-0.30), leach 0.035 | 2 surfaces, all agree |
| deep_bedding | frac_gas_high | 0.3 | 0.3 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Cattle and swine deep bedding: 0.25 (0.10-0.30), leach 0.035 | 1 surfaces, all agree |
| deep_bedding | frac_gas_low | 0.1 | 0.1 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Cattle and swine deep bedding: 0.25 (0.10-0.30), leach 0.035 | 1 surfaces, all agree |
| deep_bedding | frac_leach | 0.035 | 0.035 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Cattle and swine deep bedding: 0.25 (0.10-0.30), leach 0.035 | 2 surfaces, all agree |
| deep_bedding | frac_leach_high | 0.07 | 0.07 |  | `DEVIATION_DOCUMENTED` | IPCC gives leach 0.035 as a point value for deep bedding with no range. The tool borrows the dry-lot range (footnote 4), which is the same central value | 1 surfaces, all agree |
| deep_bedding | frac_leach_low | 0 | 0 |  | `DEVIATION_DOCUMENTED` | IPCC gives leach 0.035 as a point value for deep bedding with no range. The tool borrows the dry-lot range (footnote 4), which is the same central value | 1 surfaces, all agree |
| liquid_slurry | frac_gas | 0.48 | 0.3 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 3 surfaces, all agree |
| liquid_slurry | frac_gas_high | 0.72 | 0.36 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 1 surfaces, all agree |
| liquid_slurry | frac_gas_low | 0.24 | 0.09 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 1 surfaces, all agree |
| liquid_slurry | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 2 surfaces, all agree |
| liquid_slurry | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 1 surfaces, all agree |
| liquid_slurry | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0 | 1 surfaces, all agree |
| anaerobic_digester | frac_gas | 0.05 | 0.48 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central, and footnote 3 tells you which end applies: 'The lower range of 0.05 losses is valid for digestate with a high dry matter content AND A COVER', and 'It is advised to use the liquid slurry without cover for uncovered digestate'. This row declares OPEN STORAGE, and its MCF comes from the Table 10A.11 open-storage row, so the covered figure was the wrong end of the range. Following footnote 3, the value is the Liquid/Slurry without natural crust cover, Other Cattle figure: 0.48 (0.15-0.60). It was previously 0.05 (0.02-0.08), roughly ten times too low and with a sampled range sitting entirely below IPCC's floor | 1 surfaces, all agree |
| anaerobic_digester | frac_gas_high | 0.08 | 0.6 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central, and footnote 3 tells you which end applies: 'The lower range of 0.05 losses is valid for digestate with a high dry matter content AND A COVER', and 'It is advised to use the liquid slurry without cover for uncovered digestate'. This row declares OPEN STORAGE, and its MCF comes from the Table 10A.11 open-storage row, so the covered figure was the wrong end of the range. Following footnote 3, the value is the Liquid/Slurry without natural crust cover, Other Cattle figure: 0.48 (0.15-0.60). It was previously 0.05 (0.02-0.08), roughly ten times too low and with a sampled range sitting entirely below IPCC's floor | 1 surfaces, all agree |
| anaerobic_digester | frac_gas_low | 0.02 | 0.15 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central, and footnote 3 tells you which end applies: 'The lower range of 0.05 losses is valid for digestate with a high dry matter content AND A COVER', and 'It is advised to use the liquid slurry without cover for uncovered digestate'. This row declares OPEN STORAGE, and its MCF comes from the Table 10A.11 open-storage row, so the covered figure was the wrong end of the range. Following footnote 3, the value is the Liquid/Slurry without natural crust cover, Other Cattle figure: 0.48 (0.15-0.60). It was previously 0.05 (0.02-0.08), roughly ten times too low and with a sampled range sitting entirely below IPCC's floor | 1 surfaces, all agree |
| anaerobic_digester | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98, Anaerobic digester: leach 0 | 1 surfaces, all agree |
| anaerobic_digester | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98, Anaerobic digester: leach 0 | 1 surfaces, all agree |
| anaerobic_digester | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98, Anaerobic digester: leach 0 | 1 surfaces, all agree |
| composting | frac_gas | 0.65 | 0.65 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 | 1 surfaces, all agree |
| composting | frac_gas_high | 0.98 | 0.7 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 | 1 surfaces, all agree |
| composting | frac_gas_low | 0.33 | 0.14 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 | 1 surfaces, all agree |
| composting | frac_leach | 0.06 | 0.06 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Composting Static Pile: 0.65 (0.14-0.70), leach 0.06 | 2 surfaces, all agree |
| composting | frac_leach_high | 0.09 | 0.09 |  | `DEVIATION_DOCUMENTED` | IPCC publishes the leaching fraction for this system as a point value with no range. The tool applies a +/- 50% band so the parameter can be sampled | 1 surfaces, all agree |
| composting | frac_leach_low | 0.03 | 0.03 |  | `DEVIATION_DOCUMENTED` | IPCC publishes the leaching fraction for this system as a point value with no range. The tool applies a +/- 50% band so the parameter can be sampled | 1 surfaces, all agree |
| aerobic_treatment | frac_gas | 0.85 | 0.85 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 2 surfaces, all agree |
| aerobic_treatment | frac_gas_high | 1 | 1 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 1 surfaces, all agree |
| aerobic_treatment | frac_gas_low | 0.27 | 0.27 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 1 surfaces, all agree |
| aerobic_treatment | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 1 surfaces, all agree |
| aerobic_treatment | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 1 surfaces, all agree |
| aerobic_treatment | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0 | 1 surfaces, all agree |
| lagoon | frac_gas | 0.35 | 0.35 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 2 surfaces, all agree |
| lagoon | frac_gas_high | 0.8 | 0.8 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 1 surfaces, all agree |
| lagoon | frac_gas_low | 0.2 | 0.2 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 1 surfaces, all agree |
| lagoon | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 1 surfaces, all agree |
| lagoon | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 1 surfaces, all agree |
| lagoon | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98 gives leaching 0 for this system, so the bounds are 0 as well. Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0 | 1 surfaces, all agree |
| burned_for_fuel | frac_gas | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |
| burned_for_fuel | frac_gas_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |
| burned_for_fuel | frac_gas_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |
| burned_for_fuel | frac_leach | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |
| burned_for_fuel | frac_leach_high | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |
| burned_for_fuel | frac_leach_low | 0 | 0 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion | 1 surfaces, all agree |

## Regional body-weight benchmark (QA only)

`IPCC_DEFAULTS_BY_REGION`, 12 values, 6 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| africa | default_val | 275 | 275 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108: Mature Females - grazing, Large Areas 275 kg. Note Table 10A.1 gives Africa dairy 260 kg | master only |
| africa | default_val_dairy | (new) | 270 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Africa Low productivity systems: 270 kg (aggregate 260, high productivity 250) | master only |
| asia | default_val | 350 | 350 |  | `DEVIATION_OPEN` | Table 10A.1 Asia dairy 386 kg (low productivity 355); Table 10A.2 Asia Mature Females 376, grazing 305. The 350 used here matches no Asia row; the only published 350 is Indian subcontinent high-productivity dairy | master only |
| asia | default_val_dairy | (new) | 355 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Asia Low productivity systems: 355 kg (aggregate 386, high productivity 485) | master only |
| europe | default_val | 600 | 600 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1: Western Europe dairy 600 kg | master only |
| europe | default_val_dairy | (new) | 600 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Western Europe: 600 kg. Eastern Europe is 550; no productivity split is published for either | master only |
| americas | default_val | 500 | 500 |  | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1: Latin America low productivity dairy 500 kg. North America dairy is 650 and Latin America aggregate 508, so this is the low-productivity reading used elsewhere in the tool | master only |
| americas | default_val_dairy | (new) | 500 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Latin America Low productivity systems: 500 kg (aggregate 508, high 520). North America is 650 | master only |
| oceania | default_val | 500 | 500 |  | `DEVIATION_OPEN` | Table 10A.1 Oceania dairy 488 kg; Table 10A.2 Oceania Mature Females 416, Mature Males 467. The 500 used here appears in no Oceania row | master only |
| oceania | default_val_dairy | (new) | 488 | **->** | `CONFIRMED` | 2019R V4 Ch10 Table 10A.1 (New), Oceania: 488 kg; no productivity split published | master only |
| global | default_val | 400 | 400 |  | `NO_IPCC_DEFAULT` | Neither annex table has a global row. The 400 used here is a project benchmark | master only |
| global | default_val_dairy | (new) | 400 | **->** | `NO_IPCC_DEFAULT` | Table 10A.1 has no global row. 400 kg is a project benchmark carried over from the non-dairy column | master only |

## Global warming potentials

`GWP_VALUES`, 6 values, 0 moved since July.

| key | field | July | Now | | verdict | source | reach |
|---|---|---|---|---|---|---|---|
| AR4.CH4 | value | 25 | 25 |  | `CONFIRMED` | IPCC AR4 WGI, 100-year GWP: 25. Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |
| AR4.N2O | value | 298 | 298 |  | `CONFIRMED` | IPCC AR4 WGI, 100-year GWP: 298. Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |
| AR5.CH4 | value | 28 | 28 |  | `CONFIRMED` | IPCC AR5 WGI, 100-year GWP: 28. Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |
| AR5.N2O | value | 265 | 265 |  | `CONFIRMED` | IPCC AR5 WGI, 100-year GWP: 265. Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |
| AR6.CH4 | value | 27 | 27 |  | `CONFIRMED` | IPCC AR6 WGI, 100-year GWP: 27 (non-fossil methane, 100-year). Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |
| AR6.N2O | value | 273 | 273 |  | `CONFIRMED` | IPCC AR6 WGI, 100-year GWP: 273. Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read | 2 surfaces, all agree |

## Verdict glossary

| verdict | meaning |
|---|---|
| `CONFIRMED` | read at the cited IPCC table |
| `INTERPRETED` | a reading of an IPCC category label, not a quotation |
| `DEVIATION_DOCUMENTED` | differs from IPCC deliberately, reason on record |
| `DEVIATION_OPEN` | differs from IPCC, no recorded reason |
| `NOT_IPCC` | not an IPCC value |
| `NO_IPCC_DEFAULT` | IPCC publishes no default for this |

## How the reach column is produced

`scripts/verify_defaults.R` extracts every default from 15 surfaces and compares each against the master: the Excel Parameters, Vocab, _Lists and Manure_Management sheets, the six AI-translator prompt files, both published guides in source and built form, the QA auto-fill hints, the audit's own literals, and the two built-in example inventories. A value shown as agreeing has been read back out of each of those surfaces and matched. The run is gated in CI, so a surface that drifts fails the build.

Two limits worth stating. The matrix proves the surfaces agree with the R constants; audit check F39 separately proves the R constants are built from the master, by perturbing it and requiring every object to move. And a value carried by no surface is not unchecked: it is verified against IPCC in the source column, it simply is not repeated anywhere else in the app.

