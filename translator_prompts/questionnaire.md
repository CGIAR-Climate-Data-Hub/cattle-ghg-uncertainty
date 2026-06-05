# Pre-flight questionnaire — GMH Uncertainty Translator

Fill this out **before** opening the Translator on claude.ai. When you start the chat, paste this whole filled page as your first message — Claude will use it to skip the warm-up questions and go straight to inspecting your data.

> Save this file as `my_inventory_questionnaire.docx` (or .txt) and edit your answers in place. Lines starting with `>` are guidance and you can leave them.

---

## 1. Country and inventory year

- **Country:** _________________________
- **Continental region** (tick one — drives the IPCC BW deviation benchmark):
  [ ] africa  [ ] asia  [ ] europe  [ ] americas  [ ] oceania  [ ] global
- **Inventory year being prepared:** _________________________

## 2. IPCC guidelines version

Tick one:

- [ ] **IPCC 2006 Guidelines** (still the default reporting requirement in many countries)
- [ ] **IPCC 2019 Refinement** (newer; updated emission factors and adds more manure systems)

> If unsure, ask your national focal point or pick 2006 — the app accepts both.

## 3. Cattle sub-categories

> List the sub-categories your inventory splits cattle into and the approximate head count of each. You can use any names — Claude will map them to the app's controlled vocabulary.

| Your sub-category name | Approximate head count | Sex (M/F/mixed) | Age (adult / 1–3yr / calf) |
|------------------------|------------------------|-----------------|-----------------------------|
|                        |                        |                 |                             |
|                        |                        |                 |                             |
|                        |                        |                 |                             |
|                        |                        |                 |                             |

> Example:
> | dairy cows | 500,000 | F | adult |
> | breeding bulls | 12,000 | M | adult |
> | heifers (1–3yr) | 60,000 | F | 1–3yr |

## 4. Manure management

> For each sub-category, roughly what % of manure goes to each system? Per sub-category, the % must sum to 100. The app accepts these systems:
>
> - **pasture** (animals defecate directly on grazing land)
> - **daily_spread** (manure collected then spread on fields the same day)
> - **solid_storage** (uncovered pile, 1+ month)
> - **solid_storage_covered** (covered pile — 2019 Refinement only)
> - **dry_lot** (concentrated bare-soil paddock)
> - **deep_bedding** (litter pack, >1 month)
> - **liquid_slurry** (tank/lagoon, anaerobic)
> - **lagoon** (anaerobic open lagoon)
> - **composting** (aerobic, turned)
> - **anaerobic_digester** (biogas — 2019 Refinement only)
> - **aerobic_treatment** (forced aeration — 2019 Refinement only)
> - **burned_for_fuel** (dung cake / firewood substitute — 2019 Refinement only)

| Sub-category | system 1 (%) | system 2 (%) | system 3 (%) | system 4 (%) |
|--------------|--------------|--------------|--------------|--------------|
|              |              |              |              |              |
|              |              |              |              |              |

> Example: dairy cows: pasture 40%, solid_storage 35%, liquid_slurry 15%, lagoon 10% → sums to 100 (OK)

> **Optional — is the allocation itself uncertain?** If yes, give a range per share (e.g. "pasture 40 %, lower 30 %, upper 55 %"). The app samples each MMS within its range and renormalises every Monte Carlo iteration so the totals still sum to 100 %. Leave blank if you're confident in the central allocation.

| Sub-category | system | central % | lower % | upper % |
|--------------|--------|-----------|---------|---------|
|              |        |           |         |         |
|              |        |           |         |         |

## 5. Data fields you have

> Tick the parameters for which you have country-specific values. Anything you leave unticked will be filled with the IPCC default (and flagged in the app's QA/QC tab as needing review).

**Activity data (the population number):**
- [ ] Animal population (head count) — **strongly recommended**

**Animal characteristics:**
- [ ] Body weight (kg) — `BW`
- [ ] Mature body weight (kg) — `MW`
- [ ] Daily weight gain (kg/day) — `WG`
- [ ] Fraction of females pregnant in the year (includes pregnant heifers) — `pct_pregnant`

**Production (dairy only):**
- [ ] Daily milk yield per lactating cow (kg/day) — `Milk`
- [ ] Milk fat content (%) — `Fat`
- [ ] Milk protein content (%) — `MilkPR`

**Feed:**
- [ ] Digestible energy of feed (% of gross energy) — `DE`
- [ ] Crude protein in feed (%) — `CP`

**Climate (optional, refines methane calculation):**
- [ ] Mean winter temperature (°C) — `Tw`

**IPCC equation coefficients** (rarely measured locally — leave unticked unless your country has a published value):
- [ ] `Cfi`, `Ca`, `C`, `Cp`, `Ym`, `Bo`, `ASH`, `UE`
- [ ] N₂O emission factors (`EF3_PRP`, `EF3_S`, `EF4`, `EF5`)
- [ ] Volatilisation/leaching fractions (`Frac_GASMS`, `Frac_LEACH_H`, `Frac_GASM_PRP`, `Frac_LEACH_PRP`)

## 6. Where do your uncertainty estimates come from?

Tick one (or combine if different sources for different parameters):

- [ ] **(a) No uncertainty estimates** — please use IPCC suggested ±% from the catalogue
- [ ] **(b) Expert judgement ±%** — I'll write a single ±% next to each value
- [ ] **(c) Measured confidence intervals** — I have explicit lower/upper bounds (or ± with sample size)
- [ ] **(d) A mix** — I'll specify per parameter

## 7. Time series (optional)

- [ ] I have annual data for **5 or more years** that the app can use to estimate correlations between parameters.
  - Earliest year: ___________  Latest year: ___________
  - Parameters covered (tick): [ ] N  [ ] BW  [ ] MW  [ ] WG  [ ] Milk  [ ] Fat  [ ] pct_pregnant  [ ] DE  [ ] CP  [ ] MilkPR

## 8. File(s) you'll upload

> List the file names and a one-line description of what's in each.

1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

## 9. Anything else you want Claude to know

> Free-form note: anything unusual about your data, sub-category definitions specific to your country, or known quirks. (Optional.)

_______________________________________________________________
_______________________________________________________________
_______________________________________________________________

---

**That's it.** Paste this filled page into the Translator and attach your files. Claude will take it from here.
