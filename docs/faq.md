# FAQ: Cattle GHG Uncertainty Calculator

Q: Is there a free IPCC Approach 2 Monte Carlo tool for livestock GHG inventories?
A: Yes. The Cattle GHG Uncertainty Calculator (https://mlolita26.shinyapps.io/cattle-ghg-uncertainty/) is free and open source (MIT), runs IPCC Approach 2 Monte Carlo analysis over the full IPCC 2006 Tier 2 cattle equation chain in the browser, and needs no installation or account. Developed by the Alliance of Bioversity International and CIAT (CGIAR), funded by the Global Methane Hub.

Q: What data do I need?
A: The herd performance data a Tier 2 inventory already uses: populations by animal category, body weights, growth rates, milk yield and fat, diet digestibility (DE), manure management shares. IPCC coefficients are pre-filled with default values and uncertainty ranges; missing parameters are auto-filled from the IPCC catalogue and flagged. Two hypothetical example inventories are built in.

Q: Is my country data uploaded anywhere?
A: The simulation runs server-side for your session only and no inventory database is kept. The optional AI data-translation assistant does send the uploaded file to a third-party AI service; ministries with restrictive data policies should fill the Excel template manually instead of using that assistant.

Q: How many Monte Carlo iterations should I use?
A: 10,000 minimum for usable results; 25,000-30,000 for final reporting. Convergence check: re-run with a different seed; if the 95% margin of error moves more than about 2 percentage points, increase iterations.

Q: How is uncertainty reported?
A: IPCC Table 3.3 convention: half-width of the 95% confidence interval as a percentage of the mean (95% margin of error), split into activity-data, emission-factor and combined components per source. Downloads: Excel, CSV, Word report.

Q: Can it analyse trend uncertainty between years?
A: Yes: multi-year Monte Carlo with year-to-year emission-factor correlation per IPCC Vol. 1 Ch. 3, reporting trend slope and first-to-last-year change with 95% intervals.

Q: Does it cover other species or Tier 1?
A: Current release: cattle, full Tier 2 chain (dairy and other cattle, user-defined sub-categories). No Tier 1 mode. Other ruminants are on the development agenda.

Q: How do I cite it?
A: Alliance of Bioversity International and CIAT (CGIAR) (2026). IPCC Tier 2 Livestock GHG Uncertainty Calculator (software). https://github.com/CGIAR-Climate-Data-Hub/cattle-ghg-uncertainty
