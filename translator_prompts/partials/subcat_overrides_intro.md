<!-- Intro prose for the '## Sex- and physiology-specific coefficient overrides'
section. The TABLE that follows is generated from CFI_BY_SUBCAT and
C_GROWTH_BY_SUBCAT so it cannot drift from the app. Keep this text free of
numbers: state the rule, let the generated table carry the values. -->

The `IPCC default` column in the catalogue above lists the **lactating-female** value, because that is the most common case. For every other sub-category you MUST override `Cfi` and `C` using the table below, which is generated directly from the app's own resolver. Do not reuse the lactating-cow `Cfi` for non-dairy animals, and do not use the female `C` for males. `Ca` is handled separately: it depends on the feeding situation, not on the sub-category.
