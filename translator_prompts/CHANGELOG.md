# Translator prompt changelog

What the AI translator is told, and why it changed. Hand-kept, newest first. The prompt the app sends is assembled from `system_instructions.md`, the generated `param_catalogue.md`, `template_schema.md` and `worked_example.md`, the hand-written `mapping_examples.md`, and the in-app presentation rules in `R/openai_client.R`. `Rscript scripts/translator_prompt_view.R` writes the assembled prompt to `reports/` with its hash; the same hash is stamped into every workbook's Inventory_Metadata notes.

## 2026-11-01, after the 16:18 run

The 16:18 run (2026.11.02.2): 496/496 values, every series cell equal to its file row, no duplicate rows, milk conversions verified. Left: a normal ±35 % where the file's milk row says triangular 3 to 7.5; Frac_GasMS of solid storage at 30 for four commercial dairy groups and 45 (the file) for the cows, downgraded to a note because both numbers are in the file; 44 "range not in file" warnings on the IPCC catalogue bounds of EF3_PRP and EF4.

- **Ranges and distributions from the table** (`translator_apply_table_ranges`, after the series rebuild): a Parameters row whose checked entry carries bounds or a distribution takes them (bounds times the row's conversion factor), recorded as "range taken from the file" / "distribution taken from the file" warnings.
- The "(in file)" note for a coefficient that differs within a system applies to MCF only; Frac_GasMS, Frac_LeachMS and EF3 keep the warning.
- The "range not in file" check skips bounds equal to the catalogue's own; the conversion verifier warns on a margin written for a converted value without the file's bounds.
- The inventory year and the country are required at upload (a tooltip explains the one-year choice and the trend tab); the guide gained "Preparing your file" and "How to answer the AI's questions".

## 2026-11-01, late: after the 15:09 run

- The series rebuild matches a row without its system label on the batch's requested level and merges duplicate (system, group, year) rows (the commercial dairy sheet had two rows per year).
- The "range not in file" check takes the conversion factor from the AI's JSON (the converted milk bounds were flagged).
- A clean source check shows nothing; once the answers are in and the table matches, the conversation ends on one bubble: "Everything is recorded and the AI's table of values matches your file. Click Produce template now." A mismatch still shows its line and the correction.

## 2026-11-01, night: the series from the file, the checks of Stage 5, the rest of Stage 4

Reason: the 13:31 run's feedlot BW series was invented and its MW series left out; the ±20 % milk bounds replaced the file's; ten questions on a file whose note answered eight.

- **Series copied by the server** (`translator_rebuild_series`, after the fix-up, before the write): for every group and parameter whose file row the source check confirmed (an entry read from a year column), the row's values in every year column replace the AI's series, converted with the row's factor; recorded as "series taken from the file" (info when the AI's cells agreed, warn with the years when they differed or were missing). The batch request says a series cell is a cell of the file, never extended, smoothed, interpolated or rounded.
- **Stage 5 checks**: the value match is relative, 1e-5, and a match through a unit transform is an info row ("derived by unit transform"); a converted row is tested on its `source_value`; the ranges of a `user_file` row are looked for in the file ("range not in file", warn); a Parameters value of a series parameter found only in another year's column is a failure ("value from another year"); one value per system for DE, CP, Fat, MilkPR, pct_pregnant and Ym ("same value within a system": warn under 2 % spread, info above).
- **Stage 4**: the blocking failures travel on the hidden `Translator_Checks` sheet to the app's QA/QC tab (`run_qaqc(translator_checks)`, "Translator check: ..." fail rows, ignorable); the writer's silent fills are listed (`.translator_writer_diff`: gaps filled from the catalogue, optional values blanked, cattle_type filled, duplicate rows); a batch cut at the output limit is asked again in two halves of its sub-categories and merged; closed sessions and day-old jobs are dropped from the job store.
- **Questions**: what the notes or the upload settings settle is recorded as a decision and not asked (rule 10; the notes block).
- Tests: scripts/test_translator_roundtrip.R (audit F81).

## 2026-11-01, evening: conversions verified (Stage 6), series regardless of the table, no AI review

Reason: the 11:25 Zambia run. Nine series were missing (emergent dairy DE and CP for the non-cow groups, the feedlot MW, the commercial dairy heifers' MW): the table now lists the inventory year only and the emission rule said "a mechanical translation of the table", so the AI left series out. The emergent dairy milk series again started from the 2024 converted value, and the commercial beef cows' milk bounds were left per lactating day. The AI review of the 100 flagged items hit its output limit and applied nothing; the user chose to drop it.

- **Conversions declared and recomputed** (tool schema; the Copied-or-computed rule; the batch request; the checklist; examples 2, 6 and the milk row; the worked example intro): a converted row carries `source_value`, `source_unit`, `conversion` (`milk_lactating_to_head` with `lactation_days`, `lb_to_kg`, `l_to_kg`, `pct_to_fraction`, `fraction_to_pct`, `per_year_to_per_day`, `custom` with `conversion_factor`) and `source_lower`/`source_upper` for converted bounds. The server recomputes the mean and the bounds (`.translator_verify_conversions`, fail above 0.2 %, info when verified, warn when the factor or the file's bounds are missing) and every time-series cell of the parameter against its own year's file value (`.translator_ts_conversion_issues`: "not converted" or "converted from another year's value").
- **Series regardless of the table** (Step 9 item 1, the batch request): the table lists the inventory year; the series are read from the file's year columns for every group whose value changes, the groups sharing one series with the cows and the feedlot weights named.
- **No AI review after assembly** (`.TRANSLATOR_AI_REVIEW = FALSE`): the checks are listed for the compiler, the files come right after them.
- **Series values in no year column** (the 13:31 run: the feedlot BW series climbed one kilogram a year where the file is uneven and then flat, five values the file has nowhere, twenty more from other years): the year check now reports, per series, the years whose value is in no column of the file ("time-series value not in file", fail); converted parameters are left to the conversion check (the factor from the AI's JSON, or, without it, a Parameters value itself absent from the file).
- **The source check runs when a table arrives**, not at the click: its result is a line in the chat ("all N found" / "N did not match; the AI will correct them after your answers"), the correction is sent as soon as no question is open, the year check runs first, and the click only starts production (a notice covers the rare case of an unchecked table). Rule 10: the reply that closes the questions ends with "Click Produce template now when you are ready; the server first checks my table of values against your file", never "ready for emission".

## 2026-11-01, afternoon: the year before the table, and a less strict source check

Reason: the second Zambia run of the day. The AI built its table on the 2022 column during the exploration and the inventory year (2024) was decided in the questions afterwards; the check passed the table because every entry matched its 2022 cell. The check also flagged 61 entries whose labels were right: population rows under no heading, "All production systems" and "all categories except calves" rows, "Heifers" against the file's "Heifer", "Oxen (>3 years)" against "Oxen (> 3 years)". And the re-emitted table listed every year (1,038 rows).

- **Inventory year and country at upload** (optional fields next to the file): stated in the upload message under SETTINGS GIVEN BY THE USER AT UPLOAD, recorded in the register before the exploration (topics `inventory_year`, `country`), so the table is built on that column and the question is not asked.
- **Year check** (`.translator_year_fix_message`): when the year decided in the chat differs from the column most of the table's entries read, the server asks once for the whole block re-read on that column (a YEAR CHECK message, stage `source_fix`).
- **The table lists the inventory year only**: one row per parameter and group; the other years of a series are not listed and are checked after production (rule 13, Step 2, the upload block).
- **Source check**: a row under no heading accepts any section; a label or system is accepted when every content word of it is found near the row as a word stem ("heifer", "oxen 3 years" after folding punctuation), or when the row itself or its heading covers several groups ("all production systems", "all categories ...") and names no exception matching the entry ("except calves" refuses a calves entry).

## 2026-11-01, the source_values block in compact form

Reason: the first Zambia run of Stage 3 wrote the block as one object per value with fifteen named fields; the explore reply reached the 40,000-token output limit inside the block (run 1's prose table had taken 25,500 tokens), the server's pattern wanted a closing fence and extracted nothing, and the continuation's 77 entries replaced the lost block. The streamed reply also dropped the browser connection.

- **One object per sub-category and system**, with `system`, `label`, `sub_category`, `aggregation_level` and `values`: positional rows `[parameter, sheet, row, col, section, mean, lower, upper, unit, distribution]` plus `bounds_sheet`, `bounds_row` when the bounds come from another sheet (rule 13; Step 2 and Step 9 of system_instructions.md; the upload block). About 35 tokens per value instead of 90; `year_col` is gone, `col` is the header the mean was read from. The server still reads the older flat form.
- A block cut at the output limit is read without its closing fence, trimmed to its last complete row; the continuation's block is appended, a row written twice is kept once; the continuation request says to restart the cut group with its header.
- The live bubble is refreshed at most four times a second while a reply streams.

## 2026-10-31, Stage 3 of the review plan: the verified exploration table

Reason: the batches copied from a prose table (section B) that had no production-system column and no block-heading column and that the server could not check; the Zambia misreadings (a mature-weight range on a body-weight row, a per-system DE fix on the wrong system) came from it.

- **Section B is a `source_values` block** (rule 13 in the in-app rules; Step 2 and Step 9 of system_instructions.md; the upload block): a JSON array, one object per value the model will emit, with the system label, the sub-category label, the row's `_section`, sheet, row, column, mean, lower, upper, unit, distribution, year column, parameter and template codes. Sections A and C are lists.
- **The server checks every entry** against the sheets as the model saw them (`R/translator_source.R`): sheet, row, column, value, heading, labels, bounds. On the first mismatch the entries go back once (a SOURCE CHECK message, the model re-emits the whole block); on a second mismatch the list is shown with a "Produce anyway" button. Production does not start before.
- **Every batch request names its system's rows** ("SOURCE ROWS FOR THIS BATCH": the file's label for the system, the row ranges per sheet, the expected sub-categories) before the checklist and the decisions; a batch whose sub-categories differ from the expected set is re-requested once.
- Chat output limit 40,000 tokens (the block is larger than the table); a cut block is continued in a new block.

## 2026-10-31, Stage 2 of the review plan: one rule per subject

Reason: the technical review of 31 October found the same rule stated in several places with different wording, and three contradictions that explain errors seen on the Zambia runs.

- **Row count is the required parameters** (`{{n_params_required}}`, 25): the Only-user-subcategories rule, check 15 and the batch nudge used `{{n_params}}` (27, with GE and DMI), so the model wrote GE = 0 and DMI = 0 for every group to meet the count. New **Measured-intake rule** (Step 4): a GE or DMI row exists only when the file measured it.
- **One time-series rule** (Step 9, the batch nudge): one row per group and year for every year column of the file, each year from its own column; a constant parameter may be left blank; one year only gives `[]`. The nudge used to say "single-year snapshot: emit one row per sub_category" and "leave a column blank wherever its value is the same", which made a dropped series look like a constant one. The server now removes rows with a year and no value and reports them.
- **Section B carries the production system and the block heading** (`_section`, which the upload JSON now supplies on every data row): two look-alike rows (Weight and Mature weight, the same sub-category in five systems) are told apart by these two columns. The explore reply's sample in the in-app rules has the four sections and synthetic values; the old sample had no sections, proposed an answer and used Zambia's numbers.
- **Decisions scoped to a system** (`topic@level`, rule 11): a per-system decision carries its system; the binding block of a batch lists only the decisions of that system; a `file`-basis entry is listed as a reading to verify, not as binding. Check 1 allows a file value with a blank range (the Defaulted-uncertainty rule); the asymmetric-bounds rule keeps the file's distribution (pert only when it names none); no row carries both a percentage and a bound pair (the server keeps the bounds and reports).
- **Conversions stated, not silent**: the Copied-or-computed rule, the unit normalisation paragraph, examples 2, 3 and 6 and the worked example intro say the file's number, the factor and the result are stated in the reply and the server recomputes them (Stage 6 adds the fields). Example 2 gives one answer for L to kg (× 1.03); the Ym unit is asked, not assumed. Example 9 (images) removed; example 11 uses synthetic values, `mean`, `lower`, `upper` and `user_file`.
- **Emission checklist**: about 250 tokens restating the seven rules behind the errors, appended to every batch request and the full-mode request before the binding decisions.
- **Tool schema**: `aggregation_level` required on parameter, manure and time-series rows; enums for `distribution`, `mms_type`, `cattle_type`, `species` and `ipcc_version`.
- Clarification replies keep the 3-to-5-question cap; the explore reply's section D lists every ambiguity (the cap used to contradict it). An unanswered question keeps the file's value. The discovery request lists its three items in order. Steps renumbered 1 to 10.

## 2026-10-30, review of the checks and the Zambia errors

- **Review mode.** After the workbook is written and checked, the flagged items go back to the AI once (`mode = "review"`, `not_errors`); it returns corrected rows or explains, quoting the file, why an item is not an error. The server applies the rows, rewrites, re-checks and lists every correction and explanation in the checks file (R/translator_review.R). Reason: the checks found three of the seven errors of the 30 October Zambia run but only reported them.
- **All-rows rule (Step 4b).** A line labelled "all ..." applies to every row it names. Reason: the MCF spread line ("all ... all manure management") was dropped on all 164 rows; calves C = 1.0 ("All production systems") was missed in one system.
- **Relative spread on the manure sheet** is written as a percentage in `fraction_unc_pct`, `mcf_unc_pct`, `ef3_unc_pct`, `frac_gas_unc_pct`, `frac_leach_unc_pct`; the server computes each row's bounds. Reason: the model wrote 0 to 50, then 0 to twice the share, for "beta 0.5".
- **Time-series coverage (Step 8) and year columns (check 13).** Every group whose value changes over the years gets a series, including groups that share one series in the file; each year takes that year's column. Reason: DE and CP were written for the cows only in three systems, the feedlot weights not at all, and one 2023 value was the 2024 one.
- **Distributions in every system (check 12).** Reason: Ym was PERT in one system where the file says normal in all five.

## 2026-10-30, default uncertainty ranges

- **Defaulted-uncertainty rule, C2, check 14, case (a), no-uncertainty-anywhere rule.** A blank range is filled from the catalogue only for Ym, Bo (IPCC 2019), Cfi, Ca, C, Cp (Monni et al. 2007) and, as bounds belonging to the IPCC default value, EF3_PRP, EF4, EF5, Frac_GASM_PRP and Frac_LEACH_PRP. Every other range is left blank and reported to the user under "ranges you need to add"; the app lists it as Missing and does not run. Reason: no source gives a range for a country's own animal or diet data that applies to another country; the catalogue values used before (BW 15 %, Milk 20 %, ...) had no source.
- **Catalogue table** says "none: leave blank unless the file gives one" for those inputs instead of "(asymmetric: use bounds)".
- **Mapping examples 6 and 7** rewritten accordingly; the Ym definition cites IPCC 2019 Table 10.12 footnote 3 instead of Penman (2000).
- **In-app rule 6 (manure) and the Per-MMS uncertainty rule**: blank bounds take the IPCC range for EF3 and the Table 10.22 fractions only at the IPCC default value; a blank MCF range is Missing (the rule used to say a blank pair is treated as exactly known).

## 2026-10-22, after the Nairobi review workshop

- **Rule 11, decisions block.** Every clarify reply ends with a fenced `decisions` JSON array (topic, decision, basis, confidence, quote). The app keeps it as the register, shows it, and appends it as BINDING DECISIONS to every emission request. Reason: answers given in the chat were resent as transcript only and were not reliably applied.
- **Rule 12, source categories block.** The explore reply ends with a fenced `source_categories` JSON array (label as in the file, system, mapped sub-category and level, merge_into, confidence). Reason: the app checks that every source category is a group in the template (check C6).
- **One-category rule (Step 4b).** One source category becomes one template category; calves are never split into male and female unless the file does; the pooled `calves` code exists for that. The "split calves 50/50" example was removed from the in-app rules. Reason: the AI split pooled calves on its own.
- **Corrected-template rule (Step 3).** A template produced by the tool, corrected by the user and uploaded back outranks the original file and the earlier answers for the values it carries.
- **Discovery request** also asks for `sub_categories_by_level`, used only for the time estimate.
- **Single path**: no longer forces `distribution = pert` over the file's named distribution.
- **Temperature** 0 on the chat turns (emission was already 0).

## 2026-10-13 to 2026-10-15

- Defaulted-uncertainty rule and no-uncertainty-anywhere rule (Step 4b); C1 (missing values) and C2 (missing ranges) in the exploration report.
- Runnable-size rule and the scale note (the Colombian municipal file).
- Copied-or-computed rule and one-head-count rule; non-English headers (FE = factor de emisión); decimal commas.

## 2026-09-30

- Relative-uncertainty rule, per-manure-system uncertainty rule, named-distribution rule, right-row-right-column rule (the Zambia review by Andreas).
- 2026-10-22, in-app rule 10 (R/openai_client.R): the questions are shown one at a time by the app, so the reply must not end with "Please answer the section D questions"; after the answers, a question already answered is not asked again, and when nothing is open the reply says so and asks nothing.
- 2026-10-23, in-app rule 10: every question in every reply is a numbered item, even a single one, and the numbered questions come last in the reply (a question written in prose, "Please also confirm: ...", was missed by the app and buried under the recorded line).
- 2026-10-23, later: anything the user must answer, confirm or check ("please confirm", "please check whether") is such a numbered item; no request in prose, no lead-in line such as "One more question:" (the Zambia reply had a "please check whether" in prose above a numbered question and asked it again a turn later).
- 2026-10-23, evening: in-app rule 10 reversed. Since June it said "Section D only, no section A/B/C" and the model ignored it (14,000 to 16,000 output tokens of sections A to D on every explore); the morning's additions to the rule made it comply, the explore reply fell to about 3,000 tokens, and the two runs without section B in the transcript emitted the wrong year's populations (20 of 27) and invented manure coefficients, while the runs with it were right. Rule 10 now asks for all four sections in full, the questions last; the app hides A to C from the user. The workflow sentence in system_instructions.md says the same and drops "worked out internally".
- The onboarding questionnaire and getting-started files were removed from the kit; questions are asked after the file is seen.

## 2026-09-17 and 2026-09-18

- One shared tool `emit_inventory_piece` with a `mode` (enumerate, batch, full), `tool_choice = auto` on every call; the prompt is built at runtime from the defaults master with `{{placeholders}}`; `partials/` hold the hand-written notes; the reply memo and the ready state.
- Self-checks 10 to 15, including the row-count assertion (sub-categories × parameters).

## 2026-07-06

- Back to the full-template contract: the model writes every parameter row. The sparse overlay of 16 June (emit only the user's values, the app fills the rest) was reverted after it produced templates missing rows.

## 2026-06-30, restore point `9110134`

- The June version regarded as known-good: dedicated enumerate and batch tools with forced tool choice, no tools on chat turns, batch parts cleared after every merge, the onboarding questions asked one by one.
