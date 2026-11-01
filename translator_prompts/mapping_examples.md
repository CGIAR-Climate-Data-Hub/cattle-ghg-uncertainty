# Mapping examples: raw user data → template fields

Worked examples Claude can pattern-match against. The first three are based on the two synthetic example datasets bundled with the app (Country X = smallholder dairy, Country Y = pastoral non-dairy beef), the rest are common real-world patterns.

When a user's data resembles one of these patterns, you can move faster: but always still confirm the column meaning with the user before producing the final workbook.

---

## Example 1: Country X (smallholder dairy), clean Excel

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
| `adg_kg_d` | → `WG` | "average daily gain": adult dairy cow usually 0 |
| `milk_kg_d` | → `Milk` | confirm "per lactating cow" not "herd total". A per-lactating-cow value needs converting, because `Milk` is the annual average per head: value × lactation length ÷ 365. The row carries `source_value`, `source_unit = "kg/lactating day"`, `conversion = "milk_lactating_to_head"`, `lactation_days`, and `source_lower`/`source_upper` when the file gives bounds (converted with the same factor); every year of the series is converted from its own year's value. The server recomputes all of it |
| `milk_fat_pct` | → `Fat` | |
| `digest_pct` | → `DE` | `DE_pct` is in PARAM_ALIASES |
| `ym_pct` | → `Ym` | `Ym_pct` is in PARAM_ALIASES |
| `bo_m3` | → `Bo` | unit m³/kg VS implied |

**Missing core parameters** (per catalogue, tier = core): `Fat` (yes, present), `pct_pregnant`, `CP`, `MilkPR`, fill with the IPCC defaults **from the catalogue table in `param_catalogue`**, which for these three are {{default:pct_pregnant}}, {{default:CP}} and {{default:MilkPR}} (these numbers are filled in from the app's live tables when this prompt is assembled, so they cannot go stale).

**Advanced parameters not in user file:** `Cfi`, `Ca`, `C`, `Cp`, `hours`, `ASH`, `UE`, `EF3_PRP`, `EF4`, `EF5`, `Frac_GASM_PRP`, `Frac_LEACH_PRP`, `Tw`, fill from catalogue defaults; mark `data_source = "ipcc_default"`. (The managed-storage manure-N₂O quantities, direct EF3, Frac_GasMS, Frac_LeachMS, are NOT Parameters rows; they go per-MMS in Manure_Management.)

**Manure_Management:** ask the user. Default-ish setup for smallholder dairy might be {pasture: 60%, solid_storage: 30%, daily_spread: 10%}, but **never default the allocation silently**; this is country-specific. Always confirm.

---

## Example 2: Country Y (pastoral non-dairy beef), messier

**User uploads:** an Excel with sub-categories in rows and parameters in columns, with embedded units in headers:

```
group                       N            Live_BW (kg)   ADG (kg/day)   Milk (L/d)   DE %   Ym
breeding cows               2,400,000    230            0.05           1.5          50     7.0
growing males 1-3yr         400,000      180            0.20           0            48     7.2
```

**Mapping:**

| raw | → template | notes |
|-----|-----------|-------|
| `group = "breeding cows"` | → `sub_category = other_cows` | not `dairy_cows` because country is non-dairy beef: confirm with user |
| `group = "growing males 1-3yr"` | → `sub_category = growing_males` | direct match |
| `N` | → `N`, value cleaned of thousands separator | strip commas |
| `Live_BW (kg)` | → `BW` | "Live_BW" → BW alias |
| `ADG (kg/day)` | → `WG` | |
| `Milk (L/d)` | → `Milk` (kg/day) | **unit check: L vs kg**, milk density 1.03 kg/L: kg = L × 1.03. One conversion, declared on the row (`source_value`, `source_unit = "L/day"`, `conversion = "l_to_kg"`); the server recomputes it |
| `DE %` | → `DE` | percent OK |
| `Ym` | → `Ym` | confirm units: a value above 1 is most likely a percentage and a value below 0.2 a fraction, but ask in section D; don't assume |

**Conversion stated to the user:** "Milk (L/d) 1.5 was converted to kg/day: 1.5 × 1.03 = 1.545."

---

## Example 3: Wide-format with per-MMS data

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

**Optional: MMS allocation uncertainty:** if the user expresses uncertainty about the allocation itself ("about 40 % on pasture, could be 30–55 %"), fill `lower_fraction` / `upper_fraction` / `distribution_fraction` on each row. Leave blank to keep `fraction_pct` deterministic. The app renormalises each Monte Carlo iteration so per-group rows sum to 100 % even with the sampler active. Filled values surface `fraction_<mms>` in the sensitivity tornado so MMS allocation can be identified as an influential driver.

**Sanity check:** dairy_cows: 40+35+15+10 = 100 ✓; other_cows: 70+20+5+5 = 100 ✓. Both groups pass.

---

## Example 4: User has only a head count + says "use IPCC defaults for the rest"

This is common: small-inventory teams who know their animal numbers but nothing else.

**User says:** "Country X, 2022, IPCC 2019 Refinement, 500,000 dairy cows in one sub-category, 100% pasture, use IPCC defaults for everything else."

**You do:** Build a Parameters block with `N = 500000` (`data_source = "user_file"`) and every other parameter set to its `ipcc_default` from `param_catalogue.md`, distribution = `suggested_distribution`, `data_source = "ipcc_default"`. Give a range only where the catalogue has a default range (Ym, Bo, Cfi, Ca, C, Cp, and the bounds of the pasture N2O factors); leave every other range blank, including the range of N. Build one Manure_Management row: `mms_type=pasture, fraction_pct=100`, plus the MCF/EF3/Frac defaults for pasture. Done in two minutes.

**Important caveat to tell the user:** "I used IPCC default values. Default uncertainty ranges exist only for Ym, Bo, Cfi, Ca, C, Cp and the pasture N2O factors. Every other range, starting with your animal numbers, should come from your own data: until you add them, the app uses placeholder ranges with no published source, warns about each one and lists them in the report."

---

## Example 5: Multi-year time series (correlations)

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

Columns omitted (e.g. `Fat`, `pct_pregnant`, `CP`, `MilkPR`, `WG`) are simply left blank: the app's correlation routine drops columns with < 5 non-missing observations or zero variance.

**The user still needs the Parameters sheet for the 2022 (or whichever is the inventory year) point estimates.** The time series is optional, supplements correlations only.

---

## Example 6: User has units in lbs

**User uploads:** US-source data with weights in pounds:

```
sub_category    n         live_weight_lb   adg_lb_d
dairy_cows      120000    1320             0
```

**Conversions:**

- `live_weight_lb = 1320` → `BW = 1320 × 0.4536 = 598.8` kg
- `adg_lb_d = 0` → `WG = 0` (zero is unit-agnostic)

**Sanity check:** 1320 lb ≈ 599 kg, plausible for a US Holstein. The row stays `user_file` and declares the conversion: `source_value = 1320`, `source_unit = "lb"`, `conversion = "lb_to_kg"` (the server recomputes 1320 × 0.45359 = 598.74 and flags a difference above 0.2 %).

---

## Example 7: Distribution unknown, only mean given

**User says:** "Our crude protein in feed is 11%, that's the only number I have."

**You do:** `parameter = CP, value = 11, distribution = normal`, `data_source = "user_chat"`, with `uncertainty_pct`, `lower` and `upper` left blank. CP has no default range: neither IPCC nor the literature gives one that applies to another country's diet data.

**Tell the user:** "CP = 11% is in the template. There is no published default uncertainty range for CP, so the app will use a placeholder range, warn about it and list it in the report, until you enter your own. If you know how the 11% was obtained (for example from feed tables or a survey), I can help you work out a range: tell me the spread, or the lowest and highest plausible values."

---

## Example 8: Ambiguous sub-category names

**User uploads:** sub-categories labelled `lactating`, `dry`, `bulls`, `young stock`.

**Mapping:**

- `lactating` → `dairy_cows` (if dairy system) or `other_cows` (if non-dairy with seasonal lactation)
- `dry` → `other_cows` (mature non-lactating females)
- `bulls` → `bulls`
- `young stock` → ambiguous: could be `heifers`, `growing_males`, or both. **Ask the user**: "Is your 'young stock' all-female (heifers), all-male (growing males), or mixed? If mixed, I can either pool them as one group with sex = mixed, or split them, say which."

---

## Example 10: Aliases the catalogue knows about

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

Note: a raw column for managed-storage volatilisation / leaching (e.g. `Frac_GasMS`, `Frac_LeachMS`) or a managed-storage direct EF (`EF3_S`) is **not** a Parameters row, map it to the per-MMS `Frac_GasMS_pct` / `Frac_LeachMS_pct` / `EF3` columns in the Manure_Management sheet instead.

---

## Example 11: Pre-aggregated columns + parallel breakdown blocks

This pattern bites repeatedly with real survey data, so call it out explicitly. Typical layout (synthetic values in the shape of a national livestock survey):

```
| Param | Sub-cat | sex | Local breed % | mean | s.d. | n | DEFF | Cross breed % | mean | s.d. | n | DEFF | ... | Sub-category | mean | MoEcomb | Lower CI | Upper CI |
| LW    | Cows    |     | 0.60          | 290  | 60   | 250 | 4.9  | 0.40          | 330  | 64   | 120 | 3.1 | ... | Cows         | 306.0  | 0.21    | 241.7    | 370.3    |
| LW    | Bulls   |     | 0.65          | 310  | 110  | 90  | 4.6  | 0.35          | 430  | 130  | 45  | 2.2 | ... | Bulls        | 352.0  | 0.32    | 239.4    | 464.6    |
```

The file has **two parallel breakdown blocks** (Local breed / Cross breed, each with mean / s.d. / n / DEFF) AND a final block with the **already-computed weighted aggregate** (mean / lower CI / upper CI, indexed by a second `Sub-category` label).

**Rule: PREFER THE PRE-AGGREGATED COLUMNS.** They sit after the breakdown blocks, usually next to a label that repeats the sub-category name. They:

- already apply the file author's weighting scheme (which may use sample-design effects you can't reproduce),
- carry the asymmetric CI bounds you want for `lower_bound` / `upper_bound`,
- are the values the file author would put in a table if asked.

For the example above, the correct mapping for `BW` is:

| sub_category | mean | lower | upper | distribution | data_source |
|---|---|---|---|---|---|
| other_cows | 306.0 | 241.7 | 370.3 | pert | user_file |
| bulls | 352.0 | 239.4 | 464.6 | pert | user_file |

(`pert` here because the file names no distribution; a file that names one keeps it.)

**DO NOT** pick just the Local-breed mean (290) or the Cross-breed mean (330): that ignores 30%+ of the data and the file author's aggregation work.

**Signals that an aggregated column is present:** a repeated sub-category label sitting further right in the file; column names like `W-av`, `weighted_mean`, `combined`, `consolidated`, `pooled`, `mean (all)`, `aggregate`, or just `mean` sitting next to a `Sub-category` label after several breakdown blocks; a column named `MoEcomb` or `combined CI` nearby; presence of `Lower CI` / `Upper CI` columns *only on the aggregate side*, not on the breakdowns.

**If you can't tell which is the aggregate column, ASK the user before guessing.** Don't pick a breakdown column and pretend it's the answer.
