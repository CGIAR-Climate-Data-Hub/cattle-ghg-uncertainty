<!-- Per-sub-category caveats appended to the generated override table.
Keyed by sub-category code from ANIMAL_SUBCATEGORIES. -->

## growing_males

NOTE: the controlled-vocab code `growing_males` is genuinely ambiguous — different countries use the term for both castrate steers (C=1.0) and intact pre-castration bulls (C=1.2). If a source file's "growing males" entry has C=1.2 in its Coefficients sheet, that means the inventory team treats them as intact — honor the file value with `data_source = user_file`. If the file is silent on C, default to 1.0 (castrate-steer assumption) and surface this in section D as a clarifying question.

## calves_female

= pooled-calves IPCC default; only drop to 0.8 if the file genuinely sex-disaggregates post-weaning female-calf growth as heifer-track

## calves_male

= pooled-calves IPCC default; rises to 1.2 only on the intact-bull development path post-puberty, and DROPS to 1.0 / steer if castrated — castration LOWERS C, it does not raise it
