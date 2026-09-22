# IPCC Tier 2 Livestock GHG Uncertainty Calculator

[![Launch App](https://img.shields.io/badge/Launch%20App-shinyapps.io-2D6A4F?style=for-the-badge&logo=r)](https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/)
[![Launch on Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty/HEAD?urlpath=shiny)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![R](https://img.shields.io/badge/R-%3E%3D4.3-276DC3?logo=r)](https://www.r-project.org/)
[![audit](https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty/actions/workflows/audit.yml/badge.svg)](https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty/actions/workflows/audit.yml)

A web-based tool for national cattle GHG inventory teams to quantify and report uncertainty in their IPCC Tier 2 emission estimates. Upload your country data, run 10,000 Monte Carlo simulations, and download results formatted directly for IPCC Table 3.3 — no coding required. An in-app **AI Translator** turns raw country data files (in any shape, any language) into the strict input template before you analyse.

**Developed by** the CGIAR Alliance of Bioversity International and CIAT, under the **CGIAR Climate Action Programme**
**Funded by** Global Methane Hub (Grant R-2026-01051)

---

## Run the app — no installation needed

There are two ways to open the app in a browser without installing R or writing any code.

### Option A — shinyapps.io (recommended)

> Fast, persistent, no waiting time. The app is live and ready.

Click the green **Launch App** badge above, or go to:
**https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/**

### Option B — Binder (zero account, slower start)

> Free, no account needed. **First load takes 3–8 minutes** while the environment builds. Subsequent loads are faster.

Click the **launch binder** badge above. Once the environment is ready, the app opens automatically in your browser.

---

## What this tool does

When a country reports cattle greenhouse-gas emissions under the Paris Agreement, every input — animal populations, body weights, feed quality, emission factors — has uncertainty attached to it. This tool propagates that uncertainty through the full IPCC Tier 2 equation chain so you can report not just a single emission number, but a defensible confidence interval, complete with a sensitivity ranking of which parameters drive the spread.

**Emission sources covered:** Enteric fermentation CH₄ · Manure management CH₄ · Direct N₂O from managed manure · Indirect N₂O from managed manure (volatilisation + leaching) · Direct N₂O from pasture/range/paddock (PRP) · Indirect N₂O from PRP

| Feature | Detail |
|---|---|
| Methodology | IPCC 2006 Guidelines Vol. 4 Ch. 10–11; 2019 Refinement supported |
| Simulation | 10 000 Monte Carlo iterations (configurable) |
| Correlations | Iman-Conover restricted pairing on Spearman rank correlations (IPCC Vol.1 Ch.3 §3.2.3.2), which preserves each marginal distribution exactly; preset, manual, or structural-default emission-factor correlation; optional bounded per-MMS allocation sampling with per-iteration renormalisation |
| Uncertainty decomposition | Activity data vs. emission factors, side-by-side |
| Sensitivity analysis | Standardised Regression Coefficients (SRC) and partial rank correlation (PRCC) |
| Trend uncertainty | Multi-year Monte Carlo with year-to-year temporal correlation of EFs (IPCC Vol.1 Ch.3 §3.2.2.4) |
| Reporting output | IPCC Table 3.3 formatted XLSX / CSV download; Word run summary |
| Input format | Excel template with dropdowns, formulas, IPCC defaults, and colour-coded guidance |
| **AI Translator** | Built-in chat panel converts raw country data (.xlsx / .csv, multi-sheet, mixed languages, messy units) into the strict template. Backed by Anthropic Claude (default `claude-sonnet-4-6`, overridable via the `TRANSLATOR_MODEL` environment variable), gated by magic-link email auth. |
| Example data | Country X (hypothetical dairy) and Country Y (hypothetical pastoral) — pre-loaded, no upload needed to explore |

---

## Tabs in the app

| Tab | Purpose |
|---|---|
| **Home** | Overview, quick-start guide, funding logos |
| **Definitions** | Plain-language glossary of every IPCC parameter |
| **Resources** | Methodology PDF, user-guide PDF, **AI Translator chat panel**, and links to the IPCC chapters |
| **1. Data Input** | Pick an example or upload your filled Excel template; inline editing |
| **2. QA/QC** | Automated traffic-light checks (bounds, IPCC defaults, fractions, units) |
| **3. Uncertainty** | Review and adjust distributions, ±%, and bounds per parameter |
| **4. Correlations** | Upload a historical time series, pick a preset, or enter a manual correlation matrix |
| **5. Simulate & Results** | Choose iterations + GWP version, run Monte Carlo, see histogram + 95 % CI + decomposition + per-system table |
| **6. Sensitivity** | Tornado chart + ranking table (SRC and PRCC) |
| **7. IPCC Report** | IPCC Table 3.3 output ready to paste into UNFCCC reporting; XLSX / CSV / Word download |
| **Contact / Feedback** | Pre-filled email link + feedback form |

---

## AI Translator — turn raw country data into a ready-to-upload template

If your raw inventory data lives in your own Excel or CSV files with column names that don't match the template, the tool's in-app AI Translator does the column mapping, unit conversion (lbs/kg, L/kg, %/fraction, °F/°C, etc.), sub-category vocabulary resolution, and IPCC-default fill-in for any parameter you don't have country-specific data for.

**Workflow.** Open the **Resources** tab → the *AI Translator* card sits at the top. Sign in with your email (CGIAR addresses are auto-approved; other addresses require a one-time admin OK). Drop in your file. The AI reads every sheet and asks 2-5 clarifying questions. When you have answered them, click the green **Produce template now** button: that button is the only trigger for template emission (typing *"go ahead"* in the chat does not start it). The result is a downloadable .xlsx in the exact shape the **Data Input** tab expects.

---

## Repository structure

Folders the running app needs are at the top and unchanged. Everything else is grouped by the work it belongs to.

```
cattle-ghg-uncertainty/
├── app.R, install.R, runtime.txt    # Shiny entry point, dependency installer, Binder R version
├── R/                               # All application source: UI, server, emission engine
│                                    #   (calc_*), Monte Carlo (mc_*), utilities (utils_*),
│                                    #   AI translator (chat_ui, anthropic_client, auth, history, usage log)
├── www/                             # Everything the app serves: logos, CSS, built guides (PDF/DOCX),
│                                    #   Find-out-more HTML pages, translator kit files
├── config/                          # approved_users.csv, the translator sign-in whitelist
├── defaults/                        # THE numbers the tool ships: defaults_master.csv (single authority),
│                                    #   baseline_defaults.csv (July 2026 values), provenance_register.md,
│                                    #   DEFAULTS_MASTER.md (readable rendering)
├── translator_prompts/              # AI translator prompt sources (generated .md carry a manifest)
│
├── documentation/
│   ├── source/                      # R Markdown sources of the user guide, methodology,
│   │                                #   correlations and translator pages (built into www/)
│   ├── team/                        # Documents written for the project team (assumptions note)
│   └── beta_test/                   # Beta-test package: sample inventory, feedback form, guide
├── ipcc_reference/                  # IPCC chapters we verified against (pdf/, text extracts in text/);
│                                    #   not in git, copyrighted
├── scripts/                         # Build, check and deploy tooling; audit.R is the test contract
├── reports/                         # Generated by scripts: AUDIT_REPORT, DEFAULTS_MATRIX, ALL_VALUES,
│                                    #   VALUE_CHANGES_FOR_REVIEW, PARAM_SWEEP
├── test_data/                       # Country inventories used in testing; not in git
├── runtime/                         # Written by the running app: conversation history, usage log,
│                                    #   sign-in tokens; not in git
├── project_history/                 # Reviewer rounds, received documents, 2026 archive; not in git
├── knowledge/                       # Cold-start notes for maintainers and AI agents; not in git
└── rsconnect/                       # shinyapps.io deploy state
```

---

## Testing and verification

The calculation engine has a regression gate at [`scripts/audit.R`](scripts/audit.R). It builds a synthetic hand-computed "golden case" and asserts every IPCC Vol.4 Ch.10/Ch.11 equation, the Monte Carlo sampler, the validators and the exporters against it, then writes `reports/AUDIT_REPORT.md`.

```bash
Rscript scripts/audit.R    # exits non-zero if any check fails
```

It runs on every push and pull request (see the **audit** badge above). Checks that depend on fixtures in `test_data/` report as SKIP in a clean clone, because that directory holds real national inventory data and is deliberately untracked.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go in GitHub issues. If you are a national inventory compiler rather than a developer, the structured 20-30 minute review package in `documentation/beta_test/` is the most useful route, and it needs no login, no R and no installation.

---

## Funding and acknowledgements

This tool was developed as part of project **D614 — GMH Emissions Uncertainty** funded by the **Global Methane Hub** (Grant R-2026-01051), implemented by the CGIAR Alliance of Bioversity International and CIAT under the **CGIAR Climate Action Programme**.

<p align="center">
  <img src="www/alliance_logo_readme.webp" alt="Alliance of Bioversity International and CIAT" height="140">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="www/climate_action_logo.png" alt="CGIAR Climate Action Programme" height="80">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="www/gmh_logo.png" alt="Global Methane Hub" height="80">
</p>

---

## License

MIT © CGIAR Alliance of Bioversity International and CIAT, 2026
