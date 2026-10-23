# Translator prompt changelog

What the AI translator is told, and why it changed. Hand-kept, newest first. The prompt the app sends is assembled from `system_instructions.md`, the generated `param_catalogue.md`, `template_schema.md` and `worked_example.md`, the hand-written `mapping_examples.md`, and the in-app presentation rules in `R/openai_client.R`. `Rscript scripts/translator_prompt_view.R` writes the assembled prompt to `reports/` with its hash; the same hash is stamped into every workbook's Inventory_Metadata notes.

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
