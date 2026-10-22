<!-- Per-sub-category caveats appended to the generated override table.
Keyed by sub-category code from ANIMAL_SUBCATEGORIES. Each note explains WHY
the generated value is what it is, or where a source file may legitimately
disagree. Do not restate the value itself: the table cell already has it. -->

## growing_males

Genuinely ambiguous across countries: the term is used for both castrate steers and intact pre-castration bulls, which take different IPCC Eq 10.6 coefficients. The app assumes castrate. If the source file's Coefficients sheet gives the intact-bull value instead, that means the inventory team treats them as intact, so honour the file value with `data_source = user_file` and note it. If the file is silent, keep the generated value and surface the assumption in section D.

## calves_female

Takes the female Eq 10.6 coefficient, on the heifer-replacement track. Use this code only when the source file reports female calves separately from male calves; a single calves row in the file takes the pooled `calves` code below, never a split you make yourself.

## calves

The pooled code for a file that reports calves as one group, which most inventories do. Growth coefficient C = 0.9, the midpoint of the female (0.8) and castrate (1.0) values, is a project assumption, not an IPCC value; Cfi 0.322 follows Table 10.4, which gives one value for calves of either sex. If the file carries its own calf coefficients, honour them with `data_source = user_file`.

## calves_male

Takes the castrate Eq 10.6 coefficient. It rises to the intact-bull value only on the breeding-bull development path after puberty. Note the direction: castration LOWERS the growth coefficient, it does not raise it, so a file showing a higher value for castrated males than for intact ones has the two swapped.
