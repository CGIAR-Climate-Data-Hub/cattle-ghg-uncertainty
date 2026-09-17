# translator_prompts — knowledge base for the in-app AI Translator

The system prompt sent to Claude on every translator call is assembled by `R/openai_client.R::assemble_translator_system_prompt()` from six sections. Since 2026-09-17 the three GENERATED sections are built at runtime from the app's own R objects (`R/translator_prompt_build.R`), so a change to the defaults master or the workbook layout reaches the model on the next app start with no rebuild. The `.md` copies in this folder exist for the DIY kit and for review diffs.

## Files

| File | Purpose | How produced |
|------|---------|--------------|
| `system_instructions.md` | Persona, workflow, behaviour rules. | **Hand-written.** Numbers appear only as `{{placeholders}}` (see below), never as literals. HTML comments are stripped before the model sees it. |
| `param_catalogue.md` | The parameters: codes, units, defaults, distributions, aliases, the declared basis, the sub-category override table. | **Generated** at runtime AND written here by `scripts/build_translator_kit.R`. Never hand-edit. |
| `template_schema.md` | Workbook layout: sheets, columns (from `TEMPLATE_P_COLS` / `TEMPLATE_MM_COLS` / `TEMPLATE_META_FIELDS` in `R/utils_template.R`), units, validation rules, MMS tables. | **Generated.** Never hand-edit. |
| `mapping_examples.md` | Worked "raw column → template field" examples. | **Hand-written**, with `{{placeholders}}` for defaults. |
| `worked_example.md` | One complete reference output whose shape the model copies. | **Generated** from `resolve_subcat_default()` and the MMS tables. |
| `questionnaire.md` | The pre-flight form a user may paste. | **Hand-written.** |
| `partials/*.md` | Prose the generated files embed (definitions, notes). | **Hand-written.** |
| `.manifest.json` | sha256 of the defaults master, the template layout and each generated file at the last build. Audit check F46 and `scripts/deploy.R` compare it against the live objects. | Written by the build script. |

## Placeholders in the hand-written files

`{{default:PARAM}}` (catalogue default), `{{default:PARAM:SUBCAT}}` (the resolver's value for a sub-category), `{{unc:PARAM}}` (suggested uncertainty %), `{{n_params}}`, `{{params}}`, `{{subcats}}`, `{{subcats_non_dairy}}`. They are filled by `translator_prompt_fill_placeholders()` when the prompt is assembled in the app, and when the build script stages the kit copies into `www/`. An unknown placeholder is a hard error, and audit F46 fails if any placeholder is left unfilled.

## Re-build

After any change to `reference/defaults_master.csv`, to the template layout vectors, or to a partial:

```bash
Rscript scripts/build_translator_kit.R
```

The app itself does not need this (it regenerates at start), but the committed copies, the DIY kit zip and the manifest do, and audit F46 fails until it is done. The deploy gate runs the audit, so a forgotten rebuild cannot ship.

## Editing translator behaviour

Edit `system_instructions.md` (or `mapping_examples.md`). Restart the app to pick it up locally; commit and deploy for production. Use a placeholder rather than typing a number. The inline output-convention and UI-presentation blocks live in `R/openai_client.R` and are swept by audit F44 for superseded values like the `.md` files.
