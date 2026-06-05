# IPCC Tier 2 Livestock GHG Uncertainty Calculator

[![Launch App](https://img.shields.io/badge/Launch%20App-shinyapps.io-2D6A4F?style=for-the-badge&logo=r)](https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/)
[![Launch on Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty/HEAD?urlpath=shiny)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![R](https://img.shields.io/badge/R-%3E%3D4.3-276DC3?logo=r)](https://www.r-project.org/)

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

**Emission sources covered:** Enteric fermentation CH₄ · Manure management CH₄ · Direct N₂O from manure · Indirect N₂O (atmospheric deposition + leaching)

| Feature | Detail |
|---|---|
| Methodology | IPCC 2006 Guidelines Vol. 4 Ch. 10–11; 2019 Refinement supported |
| Simulation | 10 000 Monte Carlo iterations (configurable) |
| Correlations | Gaussian copula for activity-data time series; preset, manual, or structural-default emission-factor correlation; per-MMS allocation simplex sampling |
| Uncertainty decomposition | Activity data vs. emission factors, side-by-side |
| Sensitivity analysis | Standardised Regression Coefficients (SRC) and partial rank correlation (PRCC) |
| Trend uncertainty | Multi-year Monte Carlo with year-to-year temporal correlation of EFs (IPCC Vol.1 Ch.3 §3.2.2.4) |
| Reporting output | IPCC Table 3.3 formatted XLSX / CSV download; Word run summary |
| Input format | Excel template with dropdowns, formulas, IPCC defaults, and colour-coded guidance |
| **AI Translator** | Built-in chat panel converts raw country data (.xlsx / .csv, multi-sheet, mixed languages, messy units) into the strict template. Backed by OpenAI GPT-4.1, gated by magic-link email auth. |
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

**Workflow.** Open the **Resources** tab → the *AI Translator* card sits at the top. Sign in with your email (CGIAR addresses are auto-approved; other addresses require a one-time admin OK). Drop in your file. The AI reads every sheet, asks 2-5 clarifying questions, then — when you say *"go ahead"* — produces a downloadable .xlsx in the exact shape the **Data Input** tab expects.

---

## Repository structure

```
cattle-ghg-uncertainty/
├── app.R                        # Shiny entry point
├── install.R                    # Dependency installer (Binder + shinyapps.io)
├── runtime.txt                  # Binder R-version spec
├── README.md
│
├── R/                           # All application source
│   ├── app_ui.R, app_server.R   # Shiny UI + reactive server
│   ├── calc_*.R                 # IPCC Vol.4 Ch.10/11 emission equations
│   ├── mc_*.R                   # Monte Carlo sampling, simulation, uncertainty, sensitivity
│   ├── utils_*.R                # IPCC defaults, templates, distributions, QA/QC, exports
│   ├── auth_magic_link.R        # AI Translator magic-link email auth
│   ├── chat_ui.R                # AI Translator chat panel UI + server
│   ├── conversation_history.R   # Per-user persistent chat history
│   ├── openai_client.R          # OpenAI GPT-4.1 client (streaming + json_schema)
│   ├── usage_log.R              # Per-call token ledger + monthly budget gate
│   └── trend_tab.R              # Trend tab UI helpers
│
├── www/                         # Web assets — logos, built docs (PDF/DOCX),
│                                #   Find-out-more topic HTML, custom CSS
├── docs/                        # Find-out-more topic page sources (Rmd)
├── doc/                         # Methodology + user guide source documents
├── config/                      # Runtime config (approved_users.csv whitelist)
├── translator_prompts/          # AI Translator system-prompt knowledge files (md)
├── scripts/                     # Build, test, deploy tooling
│   ├── audit.R                  #   Regression test suite
│   ├── build_methodology.R      #   Render methodology.pdf
│   ├── build_user_guide.R       #   Render user_guide.pdf / .docx
│   ├── build_help_docs.R        #   Render in-app Find-out-more HTML pages
│   ├── build_translator_kit.R   #   Refresh AI Translator knowledge files
│   ├── deploy.R                 #   Deploy to shinyapps.io
│   ├── example_verify.R         #   End-to-end sanity check on built-in examples
│   └── make_stress_test_data.R  #   Generate stress-test dataset for the AI Translator
└── rsconnect/                   # shinyapps.io deploy state (auto-generated)
```

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
