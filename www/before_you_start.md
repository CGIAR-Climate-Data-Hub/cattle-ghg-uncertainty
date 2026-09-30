# Before you start: four things the translator cannot read from your file

**This is optional.** Nothing has to be filled in before you begin. The translator asks for what it needs, one or two questions at a time, and it asks better questions once it has seen your file, because it can ask about your actual column names and sub-category labels rather than hypothetical ones. Uploading your data first and answering as the questions arrive is a perfectly good way to work.

This page exists for two situations: you would rather decide these things in advance than mid-conversation, or you are preparing for a workshop and want to know what to bring.

Four things will be asked that no data file can answer. Everything else, including your sub-category names, head counts, and which parameters you have, is read directly from the file you upload, so there is no need to write any of it out here.

---

## 1. Which IPCC edition does your inventory report under?

- 2006 IPCC Guidelines
- 2019 Refinement

This is a reporting decision rather than a property of your data. It determines which manure management systems are available and which default values apply. If you are not sure, ask your national focal point. The tool accepts either.

## 2. Where do your uncertainty estimates come from?

- **None.** Use the IPCC suggested ranges from the catalogue.
- **Expert judgement.** A single plus or minus percentage per value.
- **Measured.** Explicit lower and upper bounds, or a mean and standard deviation.
- **A mixture**, specified per parameter.

This decides whether the bounds in your finished template are your own numbers or the catalogue's. It is the single most consequential thing the translator cannot work out for itself.

## 3. How is manure split between management systems?

A percentage per sub-category, summing to 100. Manure management system usage is usually surveyed separately from the herd, so these shares are often missing from the file you upload and have to be given in the chat.

The accepted systems are: `pasture`, `daily_spread`, `solid_storage`, `dry_lot`, `deep_bedding`, `liquid_slurry`, `lagoon`, `composting`, `burned_for_fuel`, and, under the 2019 Refinement only, `solid_storage_covered`, `anaerobic_digester` and `aerobic_treatment`.

You can use your own names for these. The translator maps them.

## 4. Is that split itself uncertain?

If your shares are an estimate rather than a measurement, give a lower and an upper percentage for each one, for example "pasture 40%, could be as low as 30% or as high as 55%". The tool then samples within those ranges and renormalises every iteration so the shares still sum to 100.

Left unspecified, the split is treated as exact. This one is easy to miss, because nothing in your file will prompt you for it, and a manure allocation that is really an estimate will otherwise be reported as though it were known precisely.

---

## Also worth having to hand

Your country name and the inventory year, if they are not stated in the file.

If there is anything unusual about your data, such as sub-category definitions specific to your country, breeds recorded separately, or a column whose meaning is not obvious from its name, say so at the start. It saves a round of questions later.

---

## One inventory per conversation

A finished template describes one country and one inventory year, because the metadata sheet carries a single country field. If you are preparing two inventories, do them in two separate conversations rather than one. A conversation carries the vocabulary and unit conventions agreed for the inventory already in it, and those can be carried across to the next one without anyone noticing, because the resulting template still looks correct.
