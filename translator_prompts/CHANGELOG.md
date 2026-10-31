# Translator prompt changelog

What the AI translator is told, and why it changed. Hand-kept, newest first. The prompt the app sends is assembled from `system_instructions.md`, the generated `param_catalogue.md`, `template_schema.md` and `worked_example.md`, the hand-written `mapping_examples.md`, and the in-app presentation rules in `R/openai_client.R`. `Rscript scripts/translator_prompt_view.R` writes the assembled prompt to `reports/` with its hash; the same hash is stamped into every workbook's Inventory_Metadata notes.

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
