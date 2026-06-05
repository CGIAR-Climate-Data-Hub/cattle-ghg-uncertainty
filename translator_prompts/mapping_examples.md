# Mapping examples — raw user data → template fields

Worked examples Claude can pattern-match against. The first three are based on the two synthetic example datasets bundled with the app (Country X = smallholder dairy, Country Y = pastoral non-dairy beef), the rest are common real-world patterns.

When a user's data resembles one of these patterns, you can move faster — but always still confirm the column meaning with the user before producing the final workbook.

---

## Example 1 — Country X (smallholder dairy), clean Excel

**User uploads:** a one-sheet Excel with these columns (typical of a Statistics Office output for a single dairy sub-category, single year):

```
country      year   sub_category   head_count   live_weight_kg   mature_wt_kg   adg_kg_d   milk_kg_d   milk_fat_pct   digest_pct   ym_pct   bo_m3
Country X    2022   dairy_cows     500000       275              300            0          4.0         4.0            55           6.5      0.13
```

**Mapping:**

| raw | → template (Parameters sheet) | notes |
|-----|------------------------------|-------|
| `country`, `year` | → Inventory_Metadata | not Parameters |
| `sub_category = dairy_cows` | → `sub_category` | matches ANIMAL_SUBCATEGORIES exactly |
| `head_count` | → `N` (param), `value = 500000` | |
| `live_weight_kg` | → `BW` | `live_weight` is in PARAM_ALIASES |
| `mature_wt_kg` | → `MW` | unit OK |
| `adg_kg_d` | → `WG` | "average daily gain" — adult dairy cow usually 0 |
| `milk_kg_d` | → `Milk` | confirm "per lactating cow" not "herd total" |
| `milk_fat_pct` | → `Fat` | |
| `digest_pct` | → `DE` | `DE_pct` is in PARAM_ALIASES |
| `ym_pct` | → `Ym` | `Ym_pct` is in PARAM_ALIASES |
| `bo_m3` | → `Bo` | unit m³/kg VS implied |

**Missing core parameters** (per catalogue, tier = core): `Fat` (yes, present), `pct_pregnant`, `CP`, `MilkPR` — fill with IPCC defaults: 0.60, 10.0, 3.3.

**Advanced parameters not in user file:** `Cfi`, `Ca`, `C`, `Cp`, `hours`, `ASH`, `UE`, `EF3_PRP`, `EF4`, `EF5`, `Frac_GASM_PRP`, `Frac_LEACH_PRP`, `Tw` — fill from catalogue defaults; mark `data_source = "IPCC default — to be reviewed"`. (The managed-storage manure-N₂O quantities — direct EF3, Frac_GasMS, Frac_LeachMS — are NOT Parameters rows; they go per-MMS in Manure_Management.)

**Manure_Management:** ask the user. Default-ish setup for smallholder dairy might be {pasture: 60%, solid_storage: 30%, daily_spread: 10%} — but **never default the allocation silently**; this is country-specific. Always confirm.

---

## Example 2 — Country Y (pastoral non-dairy beef), messier

**User uploads:** an Excel with sub-categories in rows and parameters in columns, with embedded units in headers:

```
group                       N            Live_BW (kg)   ADG (kg/day)   Milk (L/d)   DE %   Ym
breeding cows               2,400,000    230            0.05           1.5          50     7.0
growing males 1-3yr         400,000      180            0.20           0            48     7.2
```

**Mapping:**

| raw | → template | notes |
|-----|-----------|-------|
| `group = "breeding cows"` | → `sub_category = other_cows` | not `dairy_cows` because country is non-dairy beef — confirm with user |
| `group = "growing males 1-3yr"` | → `sub_category = growing_males` | direct match |
| `N` | → `N`, value cleaned of thousands separator | strip commas |
| `Live_BW (kg)` | → `BW` | "Live_BW" → BW alias |
| `ADG (kg/day)` | → `WG` | |
| `Milk (L/d)` | → `Milk` (kg/day) | **unit check: L vs kg** — milk density ≈ 1.03 kg/L; for accuracy multiply L by 1.03, but for cattle inventory 1:1 is acceptable. Ask user if precision matters; report the choice. |
| `DE %` | → `DE` | percent OK |
| `Ym` | → `Ym` | confirm units — if value > 1 assume %, if value < 0.2 assume fraction |

**Decision flagged to user:** "I treated `Milk (L/d)` as kg/day 1:1. If you'd prefer kg = L × 1.03, say so and I'll redo it."

---

## Example 3 — Wide-format with per-MMS data

**User uploads:** a manure-allocation table separate from the parameters table:

```
sub_category    pasture_pct   solid_storage_pct   liquid_slurry_pct   anaerobic_lagoon_pct
dairy_cows      40            35                  15                  10
other_cows      70            20                  5                   5
```

**Mapping to Manure_Management sheet:**

| dairy_cows row 1 | mms_type=pasture, fraction_pct=40 |
| dairy_cows row 2 | mms_type=solid_storage, fraction_pct=35 |
| dairy_cows row 3 | mms_type=liquid_slurry, fraction_pct=15 |
| dairy_cows row 4 | mms_type=lagoon, fraction_pct=10 |
| other_cows row 1 | mms_type=pasture, fraction_pct=70 |
| ... | ... |

Per row, also fill `MCF_pct` (look up the climate zone from Inventory_Metadata or ask user), `EF3` (from MMS_DEFAULTS in template_schema.md), `Frac_GasMS_pct`, `Frac_LeachMS_pct` from the per-MMS defaults table.

**Optional — MMS allocation uncertainty:** if the user expresses uncertainty about the allocation itself ("about 40 % on pasture, could be 30–55 %"), fill `lower_fraction` / `upper_fraction` / `distribution_fraction` on each row. Leave blank to keep `fraction_pct` deterministic. The app renormalises each Monte Carlo iteration so per-group rows sum to 100 % even with the sampler active. Filled values surface `fraction_<mms>` in the sensitivity tornado so MMS allocation can be identified as an influential driver.

**Sanity check:** dairy_cows: 40+35+15+10 = 100 ✓; other_cows: 70+20+5+5 = 100 ✓. Both groups pass.

---

## Example 4 — User has only a head count + says "use IPCC defaults for the rest"

This is common — small-inventory teams who know their animal numbers but nothing else.

**User says:** "Country X, 2022, IPCC 2019 Refinement, 500,000 dairy cows in one sub-category, 100% pasture, use IPCC defaults for everything else."

**You do:** Build a Parameters block with `N = 500000` (user-provided) and every other parameter set to its `ipcc_default` from `param_catalogue.md`, distribution = `suggested_distribution`, uncertainty = `suggested_uncertainty_pct`, `data_source = "IPCC default (Tier 2 fallback)"`. Build one Manure_Management row: `mms_type=pasture, fraction_pct=100`, plus the MCF/EF3/Frac defaults for pasture. Done in two minutes.

**Important caveat to tell the user:** "I used Africa-region IPCC defaults uniformly. The Cattle Uncertainty App's QA/QC tab will flag any of these as 'IPCC default' so you can replace them with country-specific values later. The simulation will run, but the resulting uncertainty bands will be wide because they reflect IPCC's Tier 1 ranges, not your country's actual measurement quality."

---

## Example 5 — Multi-year time series (correlations)

**User uploads:** an Excel with annual columns:

```
year    population    body_wt_kg    milk_kg_per_d    de_pct
2018    480000        265           3.6              54.0
2019    488000        268           3.8              54.5
2020    495000        272           4.0              55.0
2021    503000        276           4.2              55.5
2022    510000        280           4.4              56.0
```

**Mapping:** all goes into the optional `Parameter_TimeSeries` sheet:

| year | N | BW | Milk | DE |
|------|---|----|----|----|
| 2018 | 480000 | 265 | 3.6 | 54.0 |
| ... | ... | ... | ... | ... |

Columns omitted (e.g. `Fat`, `pct_pregnant`, `CP`, `MilkPR`, `WG`) are simply left blank — the app's correlation routine drops columns with < 5 non-missing observations or zero variance.

**The user still needs the Parameters sheet for the 2022 (or whichever is the inventory year) point estimates.** The time series is optional, supplements correlations only.

---

## Example 6 — User has units in lbs

**User uploads:** US-source data with weights in pounds:

```
sub_category    n         live_weight_lb   adg_lb_d
dairy_cows      120000    1320             0
```

**Conversions:**

- `live_weight_lb = 1320` → `BW = 1320 × 0.4536 = 598.8` kg
- `adg_lb_d = 0` → `WG = 0` (zero is unit-agnostic)

**Sanity check:** 1320 lb ≈ 599 kg — plausible for a US Holstein. Report the conversion in the "Units I changed" list.

---

## Example 7 — Distribution unknown, only mean given

**User says:** "Our crude protein in feed is 11% — that's the only number I have."

**You do:** `parameter = CP, value = 11, distribution = normal, uncertainty_pct = 15` (from catalogue), `lower = 11 × 0.85 = 9.35`, `upper = 11 × 1.15 = 12.65`, `data_source = "Country measurement; uncertainty from IPCC suggested ±15%"`.

**Tell the user:** "I used a ±15% Normal distribution around 11% — IPCC's suggested uncertainty for CP. If you have a measured range or a different distribution shape in mind, let me know and I'll update it."

---

## Example 8 — Ambiguous sub-category names

**User uploads:** sub-categories labelled `lactating`, `dry`, `bulls`, `young stock`.

**Mapping:**

- `lactating` → `dairy_cows` (if dairy system) or `other_cows` (if non-dairy with seasonal lactation)
- `dry` → `other_cows` (mature non-lactating females)
- `bulls` → `bulls`
- `young stock` → ambiguous: could be `heifers`, `growing_males`, or both. **Ask the user**: "Is your 'young stock' all-female (heifers), all-male (growing males), or mixed? If mixed, I can either pool them as one group with sex = mixed, or split them — say which."

---

## Example 9 — User pastes a PDF table screenshot

You can read images and PDFs. Extract the table to a markdown table first, show it back to the user for confirmation, then proceed with mapping as above. **Always confirm the extracted numbers before mapping** — OCR errors are silent and dangerous.

---

## Example 10 — Aliases the catalogue knows about

These pairs are auto-recognised; don't ask the user, just convert and note:

| raw | → canonical |
|-----|-------------|
| `cattle_pop`, `population_head`, `Population (head)` | `N` |
| `live_weight`, `W`, `Live_BW`, `body_weight` | `BW` |
| `mature_weight`, `MW` | `MW` |
| `weight_gain`, `ADG`, `adg`, `daily_gain` | `WG` |
| `milk_yield`, `Milk (kg/d)` | `Milk` |
| `milk_fat`, `Fat (%)` | `Fat` |
| `protein_milk`, `Milk_PR`, `MilkPR%` | `MilkPR` |
| `pct_lactating`, `pct_pregnant`, `pct_calving` | `pct_pregnant` (canonical name; legacy `pct_calving` accepted as alias) |
| `DE_pct`, `digestibility` | `DE` |
| `CP_pct`, `crude_protein` | `CP` |
| `Ym_pct`, `methane_conv_factor` | `Ym` |
| `ash`, `ASH` | `ASH` |
| `C_growth` | `C` |
| `Frac_LeachPRP` | `Frac_LEACH_PRP` |
| `Frac_GasPRP` | `Frac_GASM_PRP` |

Note: a raw column for managed-storage volatilisation / leaching (e.g. `Frac_GasMS`, `Frac_LeachMS`) or a managed-storage direct EF (`EF3_S`) is **not** a Parameters row — map it to the per-MMS `Frac_GasMS_pct` / `Frac_LeachMS_pct` / `EF3` columns in the Manure_Management sheet instead.
