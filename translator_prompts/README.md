# translator_prompts — system-prompt knowledge base for the in-app AI Translator

The `.md` files in this folder are concatenated at runtime by `R/openai_client.R::assemble_translator_system_prompt()` into the ~18 k-token system prompt sent to GPT-4.1 on every translator call. The AI Translator on the Resources tab cannot function without them.

## Files

| File | Purpose | How produced |
|------|---------|--------------|
| `system_instructions.md` | Persona, workflow, and behaviour rules for the translator. | **Hand-written.** Edit to change the assistant's behaviour. |
| `param_catalogue.md` | The 27 IPCC-aligned parameters: codes, units, defaults, distributions, aliases. | **Auto-generated** by `scripts/build_translator_kit.R`. Re-run after any change to `PARAM_CATALOGUE` or `PARAM_ALIASES` in `R/utils_template.R`. |
| `template_schema.md` | Exact workbook layout: sheets, columns, validation rules, MMS list, distribution-choice guide. | **Auto-generated.** Re-run after any change to template structure, MMS list, or controlled vocabularies. |
| `mapping_examples.md` | ~10 worked examples for pattern matching (Country X, Country Y, lbs→kg, etc.). | **Hand-written.** |
| `worked_example.md` | A complete reference template-ready JSON the model can copy the shape of. | **Hand-written.** |
| `questionnaire.md` | Pre-flight questionnaire so the model knows what the user might paste. | **Hand-written.** |

## Re-build

When `PARAM_CATALOGUE`, `PARAM_ALIASES`, `MMS_DEFAULTS`, or the controlled vocabularies change in `R/`:

```bash
Rscript scripts/build_translator_kit.R
```

This regenerates `param_catalogue.md` and `template_schema.md` from the live R source. Then commit + deploy.

## Editing translator behaviour

To change how the AI responds (tone, output format, completeness rules, etc.), edit `system_instructions.md` directly. No re-build needed — the file is read at runtime on every translator call. Commit + deploy and the change is live.
