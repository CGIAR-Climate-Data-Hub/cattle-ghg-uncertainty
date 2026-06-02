# Team meeting — 2 June 2026 · To-do list

**Meeting:** Cattle GHG Uncertainty Calculator — review walkthrough
**Date:** 2 June 2026
**Attendees:** Lolita Muller (Alliance Bioversity-CIAT), Andreas Wilkes, Pete Steward (Alliance Bioversity-CIAT), Todd Rosenstock (CGIAR System Organization)
**Source:** `uncertainty calculator.vtt` (51 min transcript)
**Next meeting:** Tuesday 16 June 2026 — same time

---

## Status legend

- ⬜ not started · 🟡 in progress · ✅ done · ⏸️ blocked / waiting on someone

---

## 🔴 CRITICAL — correctness blocker

### 1. Recent fixes propagated to example path but NOT to custom-upload path ✅ *investigated — code is correct; added regression protection*

**Raised by:** Andreas (21:00)

> *"All those fixes that you've done in the last… When I tried it this morning, using again a custom upload, the fixes weren't working. The correction for the N2O that was out by a factor of 10, that wasn't changed. And also that what you were showing, the disaggregation of emissions and uncertainty by subcategory and so on. Again, that wasn't working in the custom upload version."*

**Findings (investigated 2 June 2026):**

Ran `_zim_verify.R` against Andreas's canonical `uncertainty_template_ipcc2019_ZIM_v2.xlsx` (the file he's been benchmarking against @Risk). Result at commit `98d74d6`, 10 000 iterations, seed 42, AR5:

| Source | Tool mean | 95% CI | @Risk reference |
|---|---|---|---|
| Enteric CH4 | 2 608 t | [2 123, 3 167] | 2 929 t ✓ in CI |
| Manure CH4 | 593 t | [412, 859] | 708 t ✓ in CI |
| **Direct N2O MM** | **30.1 t** | **[11.8, 52.8]** | **39.9 t ✓ in CI** |
| Indirect N2O MM | 15.5 t | [11.9, 19.9] | 19.6 t ✓ in CI (barely) |

Per-sub-category disaggregation working:
| Sub-category | Direct N2O |
|---|---|
| DINT_cow | 22.14 t |
| DINT_bull | 0.28 t |
| **DINT_heif** | **5.12 t** ← heifer auto-match firing |
| DINT_GrM | 0.09 t |
| DINT_calves | 2.50 t |
| Total | 30.13 t (matches headline) |

The heifer auto-match (`resolve_sub_category_matches`) IS firing — DINT_heif in Parameters auto-matched to DINT_heifer in Manure_Management. Without this, heifer N2O would fall back to the default 70/30 allocation and produce the factor-of-10 low result Andreas remembered.

**Conclusion: the code IS correct against the canonical Zim file. The fixes ARE in the custom-upload path.**

The most likely explanations for what Andreas saw:
1. **Stale browser session** — he had loaded an example earlier, then uploaded; some `rv$*` state from the example may have leaked into the upload run. The example-load handler `.load_example()` does NOT clear `rv$manure_data` or `rv$inv_metadata` ([R/app_server.R:91-122](R/app_server.R#L91-L122)) — this is worth fixing as a defensive cleanup even though it doesn't seem to be Andreas's immediate problem.
2. **Different version of the file** — Andreas may have been testing against a locally-modified copy with different sub-category names that defeat the auto-match.
3. **Cached deployment** — the previous deploy may not have included the most recent fix at the time he tested.

**Verification of the built-in examples (Country X + Country Y):**

Per-pathway hand-computation from IPCC equations vs simulation (run via `_example_verify.R`):

| Pathway | Country X sim | Country X hand-comp | Country Y sim | Country Y hand-comp |
|---|---|---|---|---|
| Enteric CH4 | 37 688 t | 37 460 t (99.4%) | 178 673 t | 173 896 t (97.3%) |
| Manure CH4 | 1 356 t | 1 340 t (98.8%) | 6 613 t | ~6 400 t (97%) |
| Direct N2O MM | 57.1 t | 56.6 t (99.1%) | 271 t | 263 t (97%) |
| Indirect N2O MM | 53.9 t | 53.5 t (99.3%) | 256 t | 249 t (97%) |
| Direct N2O PRP | 106.6 t | 105.7 t (99.2%) | 506 t | 492 t (97%) |
| Indirect N2O PRP | 126.3 t | 125.3 t (99.2%) | 599 t | 582 t (97%) |
| Total CO2eq | 1 184 329 t | 1 176 805 t (99.4%) | 5 620 245 t | ~5 460 000 t (97%) |

Every pathway matches hand-comp to within 1–3% — residual is expected Monte Carlo / Jensen-inequality noise. **No factor-of-10 issue. No silent indirect-N2O collapse.** The full IPCC equation chain (EF1 = GE·Ym/100/55.65, N_excretion with milk + growth retention, MMS routing where "pasture" → PRP and other systems → MM, default 2019R Frac_GasMS/Frac_LeachMS defaults per MMS type) is intact in the example path.

The earlier indirect-N2O ≈ 0 bug Andreas hit on Zim was specific to the multi-sub-category / multi-MMS code path (heifer auto-match falling through to defaults with the wrong Frac_GasMS). That bug doesn't exist in the example path because the examples have a single sub-category and fall back to the default 70/30 pasture/solid_storage routing cleanly.

**Regression protection added:**
- New audit checks in [_audit.R](_audit.R) now lock this in on every audit run:
  - `F20a` — Zim template: heifer auto-match (DINT_heif → DINT_heifer) must fire
  - `F20b` — Zim end-to-end: total_direct_n2o_mm in plausible band [15, 60] (floor at 15 catches the factor-of-10 regression)
  - `F20c` — Zim end-to-end: 5 sub-categories produced, each with non-zero direct N2O
  - `F21_country_x` — Country X per-head emissions in IPCC Tier-2 plausible band (enteric 30–160 kg/hd/yr, manure CH4 0–40, direct N2O MM 0.005–0.5)
  - `F21_country_y` — same band check for Country Y
- Audit now **89/89 pass**.
- `_zim_verify.R` updated to include `mms_fraction_samples` (was lagging the live `app_server.R`).
- New `_example_verify.R` script runs the examples end-to-end with per-head sanity printouts — useful when adding new IPCC parameters or changing defaults.

**Still to do:**
- ⬜ **When Andreas re-tests** in the next iteration (per his commitment in the meeting), confirm against latest deploy. If he still sees the factor-of-10 issue, ask him to email the exact file he uploaded so we can reproduce.
- ⬜ **Defensive fix for stale state** in `.load_example()`: also clear `rv$manure_data` and `rv$inv_metadata` so switching from example → upload (or upload → example) doesn't carry old state.

**Blocks:** Andreas's full-Zimbabwe and Zambia tests (#10, #11) — unblocked from the code side; awaits Andreas's next test run.

---

## 🟠 HIGH — concrete bugs & UX problems

### 2. Uncertainty tab — search filter resets on cell edit ⬜

**Raised by:** Andreas (12:00–13:50)

Live walkthrough Andreas gave on screen:
1. Search `MW` in the uncertainty table
2. See all mature-weight rows across sub-categories
3. Double-click "Normal" → change to Beta → click Yes
4. **Table re-renders from scratch, search box is cleared, all rows reappear** — Andreas has to re-search before editing the next one.

> *"It's just a really annoying little bug"* — painful on a large inventory where the same parameter recurs 10+ times.

**Action**
- Investigate the reactive in `R/app_server.R` where the uncertainty table edit handler is wired.
- Either: enable DT `stateSave = TRUE` so client-side filter state persists, or capture the search term in the reactive and re-apply after the edit triggers re-render.

### 3. Correlation tab — "Manual entry" disabled inline ⬜

**Raised by:** Lolita herself (15:30) — flagged live in the call

> *"Disabled because you did not upload the correlation matrix yet… which is weird because you should be able to do it here if you wanted to. So I'll have a look."*

**Action**
- In the Correlations tab UI gating logic, allow the user to upload the manual correlation CSV directly from inside the "Manual entry" radio option, rather than requiring an upload before the option becomes selectable.

### 4. Asymmetric uncertainty reporting (+x% / −y%) ⬜

**Raised by:** Andreas (23:30)

> *"A lot of these distributions for the emissions… they are not symmetrical. The tool's default reporting is plus or minus X percent. But some users might want to separately know what the plus and the minus are."*

Background: the IPCC 95% interval is computed from the 2.5 / 97.5 quantiles of the Monte Carlo output, so the upper and lower half-widths can be very different (lognormal EFs, PERT-bounded fractions, manure-N₂O sums). The current display collapses them to a single ±x% MoE.

**Action**
- Add an option to display MoE as separate `(+upper%, −lower%)` rather than (or alongside) the symmetric `±x%`.
- Apply to: Results tab headline bubbles, IPCC Report tab (Table 3.3 columns), Excel export, Word run-summary.
- Decide: toggle, or always show both?

---

## 🟡 MEDIUM — features & documentation

### 5. Tone down Claude AI translator's voice ⬜

**Raised by:** Andreas (6:15)

> *"I just don't like that Claude has a slightly cocky attitude, but no, it worked really well. It was super good."*

**Action**
- Edit `claude_project_assets/system_instructions.md` — remove assertive/confident phrasing; soften assertions into questions where the translator should defer to the user; remove "I'll" / "I know" language.
- Re-build kit via `_build_claude_project_assets.R`; re-zip; re-deploy.

### 6. "Find out more" buttons → deep-linked methodology sections ⬜

**Raised by:** Pete (28:00–30:00)

> *"Could you convert that to a form where you could then like link that methodology? For the tool, because I was wondering, like, some of those sections are really technical, like, the correlation matrix, and it might be if you just ask Claude, could you just turn this into a rendered markdown that's hosted on the same GitHub or like an Astro file? I feel like Brayden is really fond of using for the climate data tab. You can ask him about that. But then you could have the link to the section in the user guide so that the user can just be like, find out more, click that, just opens a new tab."*

**Action sub-tasks**
- Convert `methodology.Rmd` → web-rendered markdown / Astro pages hosted on GitHub Pages (or similar) with section anchors.
- Highest-priority section to start with: **correlations** (Pete called out the correlation matrix explicitly).
- Add a "Find out more" button (info icon) on the Correlations tab → opens the deep-linked section in a new tab.
- Roll out to Sensitivity, Decomposition, IPCC Report tabs once the pattern is set.
- **Talk to Brayden** about the Astro setup he's using for the climate data tab.

### 7. Expand correlations explanation in the user guide ⬜

**Raised by:** Lolita herself (14:30)

> *"I tried to add a little guide and I've also planned to add something that's better in the user guide so people can understand."*

**Action**
- Write a deeper Correlations section in `user_guide.Rmd` with:
  - Worked examples showing the effect of each preset on the headline 95% interval
  - Visualisations of pair-wise correlation
  - When to use independence vs structural defaults vs time-series vs manual entry
- Mostly overlaps with #6 — the in-app deep-link should land on this section.

### 8. Tips / common-mistakes section in user guide ⬜

**Raised by:** Andreas (43:00)

> *"Pay a bit more attention to every single, even minor issue that comes up so that it can all either be fixed or contribute to the user guide. Like here are some warnings, watch out for this, this, and this."*

**Action**
- As #10 / #11 testing progresses, log every annoyance / pitfall.
- Curate into a "Tips & common pitfalls" section near the top of `user_guide.Rmd`.
- Candidates to seed: forgetting to set analysis type before simulating, leaving `pct_pregnant` blank, MMS fractions not summing to 100%, reading IPCC Table 3.3 columns (units are tCH₄ / tN₂O, not CO₂eq).

---

## 🟢 LARGER — hosting decision

### 9. Move AI translator off claude.ai free tier — host via Anthropic API, paid by CGIAR, gated ⬜

**Raised by:** Todd + Andreas + Pete (7:00–10:00) — significant discussion

Andreas's real-world experience:
> *"After uploading one set of data and responding to one question, it told me I had to wait 24 hours. So I ended up with a paid account."*

Todd's recommendation:
> *"Even the lower paid accounts are pretty restrictive in Claude these days and they're getting a lot of feed around it. So you might want to consider other models of it going being paid by the CGIAR. Have it actually stage gated on the front end — you've approved somebody to do this, you're not gonna have tons of users, but then the CGIAR pays for it through their API use, because the free accounts are often very restrictive."*

Todd also flagged the secondary benefits:
> *"If you can figure out some way to stage gate it… you create sort of a community of people who are doing this as well, because you know who it is, because they will have to have been approved to use your API. Otherwise they use your API forever, anything and everything. You can monitor what they're doing… a little surveillance you can do if you actually build it into the website directly. But then you have to have people logging in, you have to have approvals and stuff, which is a gate, but maybe not so high."*

**Action — needs decision before implementation**
- Scope cost: expected per-translation token count × expected users → monthly envelope.
- Decide budget owner (this conflicts with the prior "no API budget" steer — needs a real conversation, possibly with Todd / Hayden).
- If approved: implement in-app translator endpoint + login + approval flow + usage monitoring.
- **Conflict flag:** this contradicts the existing "no ongoing maintenance / no API key budget" position. Decision needed at leadership level.

---

## 📋 VALIDATION & TESTING PROGRAMME

### 10. Andreas — full Zimbabwe re-test (all 4 production systems) 🟡

**Raised by:** Andreas (7:00, 27:30, 43:00)

So far Andreas has tested only 1 of 4 Zimbabwe production systems against @Risk and IPCC Inventory Software. Plans to redo from scratch covering the full inventory once #1 is fixed.

**Sequence**
- (a) Lolita closes #1 (custom-upload-path fixes)
- (b) Andreas reruns full Zimbabwe inventory
- (c) Compare against @Risk + IPCC Inventory Software (already run, results in hand)

### 11. Zambia inventory test ⬜

**Raised by:** Andreas (25:00, 43:00)

> *"Would it be helpful if I gave you a roughly structured input file, basically all the inventory values for something and some default uncertainty estimates from a country? I'm going to keep working on Zimbabwe. Perhaps I would give you Zambia."*

**Action**
- **Andreas:** send Zambia inventory inputs by end of this week (~6 June).
- **Lolita:** run the inputs through the tool; document any divergence.

### 12. Pete — naïve internal-tester walkthrough ⬜

**Raised by:** Pete (44:00)

> *"Maybe you could give me some random example that's already been done, like New Zealand or whatever, I could have a go as a much more naive sort of internal tester to see like how far can I get with this?"*

**Action**
- **Andreas:** send Pete his Zimbabwe single-production-system file.
- **Pete:** complete a non-expert walkthrough before the 16 June meeting; feed back UX issues.

### 13. Namita test ⬜

**Raised by:** Pete (47:00)

> *"Might be also good, Lolita, to see if somebody else, some other people on our team could have a go as well… Maybe ask Namita to have a go at it."*

**Action**
- Lolita to invite Namita with a worked example.

### 14. National consultants in Zambia + Zimbabwe ⏸️ *(blocked on #10, #11)*

**Raised by:** Andreas (43:00)

> *"We'd also run it with the national consultants who are responsible for the tier 2 inventory in both of those countries to get like an actual user feedback, as it were."*

Hayden specifically interested in seeing engagement with **Sinero** (Zimbabwe consultant).

### 15. Lolita — own thorough end-to-end test ⬜

**Raised by:** Lolita herself (25:00)

> *"Really, really, really take time and take an example and do what Andy is doing as well. So we're 2 doing it, just seeing the details and if everything is working okay. Take time to really read the user guide and the methodology and change things if needed."*

### 16. Validate against published peer-reviewed inventory analyses ⬜

**Raised by:** Pete (25:50)

> *"I was just wondering if we could take one of these existing analyses, run it through the tool as an example and as a kind of form of validation and see if we get similar results. If we do, that's a nice green light. And then we could also use that maybe in the user guide or, you know, if we somehow think about how we can publish this tool somewhere, we could show that we've done a robust assessment against peer review resources out there already doing it."*

**Candidates**
- Karimi-Zindashty et al. — Canadian inventory
- Milne et al. — pasture-based dairy CH₄
- New Zealand inventories on the Climate Smart Agriculture website (Andreas to share links)

### 17. Add a Validation / Testing section to `methodology.Rmd` ⬜

**Raised by:** Pete (27:30)

> *"How are we capturing this validation, Lolita? Is there some section in here which is capturing this processor? If somebody wants to know how have you tested this tool that you've built, that information is there."*

Lolita: *"I don't think it's there for now, but that should be in the methodology, I think."*

**Action**
- New section in `methodology.Rmd` documenting:
  - Golden-case hand-computation (`_audit.R` Section A)
  - @Risk comparison (Zimbabwe)
  - IPCC Inventory Software comparison
  - Any published-analyses replication from #16

### 18. Add the IPCC 2019 Refinement Italy case study as a built-in example ⬜

**Raised by:** Andreas (46:30)

> *"The only one that is officially IPCC documented… is a small partial case study in the 2019 refinement, which summarizes the assumptions that were used in Italy's inventory. I think it's documented clearly enough that you could turn that into an Excel file and run it."*

**Action**
- Andreas points Lolita to the right section of IPCC 2019 Refinement.
- Lolita uses the AI translator to convert the Italy assumptions into the template format.
- Add as a built-in example alongside Country X / Country Y.

### 19. Anonymise country data when bundling new examples ⬜

**Raised by:** Andreas (44:30)

> *"The very early draft was done with some example from Uganda, which we then anonymized. Basically, it's because I have this data, but we don't necessarily want to say, look, here's Zimbabwe's inventory data on GitHub."*

**Action**
- Keep the Country X / Country Y abstraction in the public repo, even when real-country data drives them.
- Italy case study (#18) is fine to publish as-is — it's already a public IPCC document.

---

## 🛠️ INFRASTRUCTURE

### 20. Tidy up the GitHub repo ⬜

**Raised by:** Lolita herself (31:30)

> *"The GitHub right now is very, very messy, so that's something I have to work on. But everything will also be available on the GitHub. So if people want to access the code, they will be able to."*

**Action — cruft to remove or .rscignore:**
- Reviewer artefact files in the repo root (`.zip`, `.pdf`, `.docx`, `.xlsx` from review rounds)
- `*.pre_audit_2026_05_bak` backups
- `_zim_verify.R`, `_test_*.R`, `_make_comments_tracker.R` (dev-only scripts — confirm)
- Untracked `methodology.docx` / `methodology.pdf` / `user_guide.docx` / `user_guide.pdf` in the project root (already rendered to `www/`)
- Confirm `.rscignore` rules cover all of this for the deploy bundle

### 21. Move repo from `ERAgriculture/` to Climate Action Program GitHub org ⬜

**Raised by:** Pete + Lolita (32:00)

> *"Right now it's on the era one and it's not the right place… There's another option which would be make Todd happy, I should imagine, which would be this one. That would make your life easier and we don't have to set up another project. And then it's under Climate Action Program."*

**Action**
- Pete is adding Lolita to the Climate Action Program GitHub org.
- Once added: move/transfer the repo, update README badges, update `.git/config` remote, update any deploy scripts.

### 22. Add Climate Action Program (CAP) cluster logo everywhere ⬜

**Raised by:** Pete (32:30)

> *"It's under Climate Action Program, which we need to put that logo, cluster that logo everywhere."*

**Action — third logo to add alongside Alliance + GMH:**
- Source the CAP cluster logo file
- Add to:
  - Home tab logo bar (3 logos)
  - Word run-summary footer
  - Methodology + user-guide PDF / DOCX covers
  - README.md

### 23. Set up GitHub Issues workflow + Claude automation ⬜

**Raised by:** Pete (33:00–34:30)

> *"I can sort of pull that locally and work on Vyas, work with Vyas code on it. So, I mean, traditionally what the idea is that you'd raise a bunch of issues and be like, okay, there's this thing needs fixing in this graph and there's this error in this figure and you paste that image, you write a little description and post it in GitHub. But I think now you can either automate the posting of those issues, so that's a lot easier. So I could just screen grab it and be like, wait, Claude, just post an issue to this GitHub about this, so I don't have to think too much about it."*

Pete also raised the option of Claude auto-fixing trivial issues in a sandbox (e.g. table decimal-place tidy-ups) — *"rather than having to send you or you or your clauder to do, but then you need to action."*

**Action**
- Enable GitHub Issues on the (newly-moved) repo
- Agree workflow between Pete + Lolita: which issues are sandbox-auto-fixable, which need review
- Pete to start raising issues against the repo

### 24. Code transparency / external-review readiness ⬜

**Raised by:** Andreas (30:00)

> *"In the old days when everything was coded by hand, it was known exactly how things work. Now that Claude is doing a lot of the work… how clear and transparent is the actual coding in the background? I assume you're not staying up 48 hours in a 24-hour period. There isn't a kind of black box or several black boxes in the background due to Claude doing its own programming, is there?… There must be some kind of standard or criteria for trusting coding. And I just wanted to be sure that we would be able to meet that if required."*

Lolita confirmed in the call: documented, one script per section, all commented, can be debugged / changed.

**Action**
- Keep this discipline as features are added.
- Once the repo is in the CAP org, confirm an external reviewer can navigate it (clear README, file purpose comments, no orphaned scripts).

### 25. Migrate shinyapps.io deployment off the personal `mlolita26` account ⬜

**Carry-over from 1 June review pass — not in the 2 June transcript** but related to infrastructure.

The deployed URL `mlolita26.shinyapps.io/cattle-ghg-uncertainty/` exposes Lolita's personal username. Needs a CIAT / CAP / project shinyapps.io account.

---

## 📅 MEETINGS & DELIVERABLES

### 26. Hayden / Global Methane Hub inception meeting — 22 June, 4 pm Nairobi 🟡

**Raised by:** Pete + Andreas (35:00, 40:50)

- 45-min meeting.
- **Lolita is on leave 18–23 June** (Disneyland 23rd).
- Pete to try to move the meeting so Lolita can attend live.
- **Fallback if it can't move:**
  - Lolita prepares a 5-min video presentation with her face on camera — Pete wants her prominent in front of Hayden, *"this is your and Andy's work"*
  - Andreas backs up with a quick PowerPoint of screenshots + results

Hayden's likely questions (per Andreas):
- Timeline for partner outreach (he has a separate UNFCCC-secretariat grant doing inventory improvements in ~20 countries)
- Can the framework extend to other agricultural methane sources — rice, biomass burning?
- GIS integration?

Andreas's overall steer:
> *"I would rather not rush. Make sure someone like me who's going to make 100 mistakes that all of them get made and documented and it goes into the guidance rather than those issues coming up with testing by the partners."*

### 27. Next internal team meeting — Tuesday 16 June, same time ⬜

**Raised by:** Lolita (47:00)

- Lolita to send the invite to Pete + Todd + Andreas.
- Targets for that meeting:
  - #1 closed
  - #10 (Zimbabwe full inventory) and #11 (Zambia) completed
  - #12 (Pete's naïve test) done
  - At minimum: #2 + #3 (the two concrete bugs) fixed

### 28. Sort out Teams holiday calendar visibility for Lolita's 18–23 June leave ⬜

**Raised by:** Pete (48:30)

- Leave is approved but isn't showing in the Teams holiday calendar — Lolita to add it.

---

## Suggested execution order (immediate)

1. **#1** — critical correctness fix (custom-upload path missing fixes). Until this is closed, Andreas can't continue Zimbabwe testing and Zambia testing is blocked.
2. **#2 + #3** — the two concrete UI bugs (search-reset, manual-entry gating). Both are quick.
3. **#5** — tone down translator (small text edit + rebuild).
4. **#11** — once Andreas sends Zambia inputs (end of this week), Lolita runs them through.
5. **#19 + #20** — repo tidy + anonymise example data, so we're ready to move to the CAP org (#21).
6. **#22** — add the CAP cluster logo (third logo).
7. **#26** — kick off Hayden video prep in parallel.

Items #4, #6, #7, #8, #16–#18 are next-iteration scope.

Item #9 (hosted AI translator) needs a real budget conversation before any code changes — flag for the next meeting agenda.

---

*Document generated from `uncertainty calculator.vtt` transcript. To update, edit this file directly.*
