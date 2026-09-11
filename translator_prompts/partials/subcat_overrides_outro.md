<!-- Closing prose for the sub-category override section. -->

**The C-coefficient (growth coefficient) is the one most commonly missed.** When applying a sub-category-specific value (`bulls` → 1.2, `oxen`/`growing_males` → 1.0), keep `data_source = "ipcc_default"` (the sex-specific value is itself an IPCC default) and call out the deliberate override in your end-of-run summary so the user can spot-check it in the QA tab.

For `Ca` specifically: pick the row based on the feeding situation the user describes — stall-fed (intensive) sits around 0.0–0.17, grazing on flat pasture around 0.17, grazing on hilly pasture around 0.36, working oxen up to 0.50. If the user doesn't specify, use 0.17 (grazing) for smallholder/extensive systems and 0.36 (stall-fed) for confined dairy systems.
