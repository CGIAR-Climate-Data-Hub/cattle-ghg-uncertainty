# Contributing

Thanks for your interest in the IPCC Tier 2 Livestock GHG Uncertainty Calculator.
This document covers how to report problems, how to propose changes, and the one
rule that matters more than any other in this repository.

## Ways to contribute

| You want to | Do this |
|---|---|
| Report a wrong number, a crash, or an IPCC non-compliance | Open a GitHub issue with the **Bug** label |
| Suggest a feature or a usability improvement | Open a GitHub issue with the **Enhancement** label |
| Ask how something works | Open a GitHub issue with the **Question** label, or email the address below |
| Send structured review feedback as an inventory compiler | Use the beta-test package in `documentation/beta_test/` (guide, sample inventory, feedback form) |
| Propose a code change | Fork, branch, and open a pull request (see below) |

If you are a national inventory compiler rather than a developer, the
`documentation/beta_test/` package is the best route. It is a 20-30 minute structured
walkthrough that needs no login, no R and no installation, and it produces
feedback in a form we can act on directly.

## Reporting a bug

A good report includes:

- What you did, what you expected, and what happened instead
- Which tab you were on
- Whether you used a built-in example (Country X / Country Y) or your own upload
- The IPCC version selected (2006 or 2019 Refinement) and the GWP set
- If it is a calculation issue, the numbers you expected and the numbers you got

**Do not attach real national inventory data to a public issue** unless your
country has already published it. If reproducing the problem needs your data,
say so in the issue and we will arrange a private channel.

## Development setup

Requires R >= 4.3.

```bash
git clone https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty.git
cd cattle-ghg-uncertainty
Rscript install.R          # installs all dependencies
R -e "shiny::runApp('.')"  # launches the app locally
```

The AI Translator additionally needs an Anthropic API key in a local
`.Renviron`. Everything else, including the whole Monte Carlo engine, runs
without any key or account.

## The regression gate

**`scripts/audit.R` is the contract. Every pull request must leave it green.**

```bash
Rscript scripts/audit.R    # writes reports/AUDIT_REPORT.md; exits non-zero on failure
```

It builds a synthetic hand-computed "golden case" and checks every IPCC
Vol.4 Ch.10/Ch.11 equation, the Monte Carlo sampler, the validators and the
exporters against it. It runs automatically on every push and pull request via
`.github/workflows/audit.yml`.

Some checks depend on fixtures in `test_data/`, which is deliberately untracked
because it holds real national inventory data. Those checks report as SKIP in a
clean clone and in CI. That is expected.

## Things that will get a pull request sent back

1. **The scalar and vectorised emission paths must stay bit-for-bit identical.**
   `ghg_emissions()` is the audit reference; `ghg_emissions_vec()` is what
   actually runs. Change one, change both, and re-run the audit.

2. **Never read a reactive value at server top level.** `rv$x` at the top of the
   server function crashes the session on load, and `testServer` does not catch
   it. Use `isolate()` or a plain value.

3. **In R regular expressions, `\s` and `\d` inside `[...]` need `perl = TRUE`.**
   The default TRE engine treats them as literal characters. This once shipped a
   bug where the email validator rejected any address containing the letter "s".

4. **Changing an IPCC default requires a citation.** `R/utils_ipcc_defaults.R`
   carries inline provenance comments pointing at chapter and table. Keep that
   up. If the value is not from the IPCC guidelines, say where it is from and do
   not label it as an IPCC default.

5. **Every user-facing string goes through `R/i18n.R`** in both English and
   French. `Rscript scripts/check_i18n.R` verifies that every key resolves.

6. **No personal names, developer dates or reviewer attribution in user-facing
   surfaces.** That belongs in git history, not in the app or the built docs.

## Pull request process

1. Branch from `main`.
2. Make the change, and add or extend an audit check if you are changing engine
   behaviour.
3. Run `Rscript scripts/audit.R` and confirm it passes.
4. Open the pull request describing what changed and why, and note any audit
   check you added.
5. CI must be green before merge.

## Scope

This tool covers cattle. Extending it to other species, adding emission sources
beyond the six currently modelled, or adding mitigation scenarios are all
recognised as valuable but are substantial pieces of work. Please open an issue
to discuss before starting.

Please also note that the project has no funded maintenance budget. Issues and
pull requests are reviewed on a best-effort basis, and features that would
require ongoing hosted services or metered API keys are unlikely to be accepted.
Self-serve, one-time deliverables are strongly preferred.

## Licence

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.

## Contact

M.Lolita@cgiar.org
