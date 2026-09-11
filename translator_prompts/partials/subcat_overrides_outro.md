<!-- Closing prose for the sub-category override section. Keep free of numbers
where the generated Ca line above already states them. -->

**The C-coefficient (growth coefficient) is the one most commonly missed.** When applying a sub-category-specific value, keep `data_source = "ipcc_default"` (the sex-specific value is itself an IPCC default) and call out the deliberate override in your end-of-run summary so the user can spot-check it in the QA tab.

For `Ca`, pick the value from the feeding-situation list above based on what the user describes, not on the sub-category: animals confined to a small area take the stall-fed value, animals on flat pasture the grazing value, and animals on open range or hilly terrain the highest value. If the user does not specify, assume grazing for smallholder and extensive systems, and stall-fed for confined dairy. Working oxen expend more energy than grazing animals; IPCC Table 10.5 gives no separate cattle value for draught work, so if the user reports heavy draught use, raise it in section D rather than inventing a coefficient.
