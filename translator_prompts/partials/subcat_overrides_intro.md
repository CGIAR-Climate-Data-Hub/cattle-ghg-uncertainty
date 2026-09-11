<!-- Intro prose for the '## Sex- and physiology-specific coefficient overrides'
section. The TABLE that follows is generated from CFI_BY_SUBCAT,
C_GROWTH_BY_SUBCAT, YM_BY_SUBCAT, DE_BY_SUBCAT and CP_BY_SUBCAT so it cannot
drift from the app. Keep this text free of numbers: state the rule, let the
generated table carry the values. -->

The `IPCC default` column in the catalogue above lists the **lactating-female** value, because that is the most common case. For every other sub-category you MUST take `Cfi`, `C` and `Ym` from the table below, which is generated directly from the app's own resolver. Do not reuse the lactating-cow `Cfi` for non-dairy animals, and do not use the female `C` for males.

`Ym` is the only parameter that also depends on the guideline edition, so the table gives a column for each. Read the one matching `inventory_metadata.ipcc_version`. The 2019 Refinement separates lactating dairy cows from non-dairy and multi-purpose cattle and from feedlot cattle (IPCC Table 10.12); the 2006 table draws no distinction below feedlot. Using the lactating-dairy value for grazing cattle understates enteric methane, and using it for feedlot cattle overstates it badly.

Feedlot cattle also carry their own `DE` and `CP`, because the IPCC feedlot `Ym` applies only to a high-digestibility concentrate ration. Those three move together: if the source file shows a feedlot herd on a low-digestibility diet, it is not an IPCC feedlot, so map it to the appropriate grazing sub-category instead and say so.

`Ca` is handled separately: it depends on the feeding situation, not on the sub-category.
