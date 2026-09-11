# =============================================================================
# build_review_table.R -- the before/after table for external review
# =============================================================================
#
# WHY. Ten unpushed commits changed IPCC defaults that feed emission
# calculations, and the reviewer has seen none of them. This renders one
# document they can work through: what each value was before, what it is now,
# what we still think is wrong, and the exact IPCC table behind each call.
#
# THE BASELINE is fbfa1bc (2026-07-10), extracted mechanically by
# scripts/extract_baseline_defaults.R into reference/baseline_defaults.csv.
# It is the last commit before September and the last recorded deploy, so the
# "before" column is what the live app still runs. Never hand-transcribe it.
#
# STATUS is the reviewer's cue for what is being asked of them:
#   APPLIED   already changed; the IPCC basis is unambiguous and no review
#             round had ruled on it. Endorse or object.
#   PROPOSED  we believe it is wrong, but a numbered review round adjudicated
#             it, so it has NOT been changed. Decide.
#   OPEN      differs from IPCC with no recorded reason and no review history;
#             a judgement call we did not want to take alone. Decide.
#
# Usage (from project root):
#   Rscript scripts/build_review_table.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

BASE_PATH <- "reference/baseline_defaults.csv"
if (!file.exists(BASE_PATH))
  stop("run scripts/extract_baseline_defaults.R first: ", BASE_PATH,
       " is missing", call. = FALSE)

rd <- function(p) utils::read.csv(p, stringsAsFactors = FALSE,
                                  na.strings = "<NA>", colClasses = "character")
B <- rd(BASE_PATH)
M <- rd("reference/defaults_master.csv")
kk <- function(d) paste(d$object, d$key, d$field, sep = "\r")
B$k <- kk(B); M$k <- kk(M)

num <- function(v) suppressWarnings(as.numeric(v))
fmt <- function(v) {
  n <- num(v)
  ifelse(is.na(n), ifelse(is.na(v), "", v),
         format(n, scientific = FALSE, trim = TRUE, drop0trailing = TRUE))
}
same <- function(a, b) {
  na <- num(a); nb <- num(b)
  both_num <- !is.na(na) & !is.na(nb)
  out <- ifelse(both_num, abs(na - nb) < 1e-12,
                (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
  out[is.na(out)] <- FALSE
  out
}

# --- which emission pathway each value feeds -------------------------------
# The reviewer's first question on any row is "what does this move?".
PATHWAY <- function(object, key, field) {
  if (object == "MMS_FRAC_DEFAULTS_2019")
    return(if (grepl("^frac_gas", field)) "indirect N2O (volatilisation)"
           else "indirect N2O (leaching)")
  if (object == "MMS_DEFAULTS")
    return(if (grepl("^mcf", field)) "manure CH4"
           else if (field == "ef3") "direct N2O, manure management" else "")
  if (object == "YM_BY_SUBCAT") return("enteric CH4")
  if (object %in% c("CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT", "LW_BY_SUBCAT",
                    "MW_BY_SUBCAT", "WG_BY_SUBCAT", "FEEDING_SITUATION_CA"))
    return("gross energy, so enteric CH4 + manure CH4 + N excretion")
  if (object %in% c("DE_BY_SUBCAT", "CP_BY_SUBCAT", "PCT_PREGNANT_BY_SUBCAT"))
    return("gross energy and N excretion")
  if (object == "GWP_VALUES") return("CO2e aggregation only")
  if (object == "IPCC_DEFAULTS_BY_REGION") return("QA benchmark only, not a calculation input")
  p <- c(Ym = "enteric CH4", Bo = "manure CH4", DE = "gross energy",
         CP = "N excretion", ASH = "volatile solids, so manure CH4",
         UE = "volatile solids, so manure CH4",
         EF3_PRP = "direct N2O, pasture", EF4 = "indirect N2O (deposition)",
         EF5 = "indirect N2O (leaching)",
         Frac_GASM_PRP = "indirect N2O (volatilisation), pasture",
         Frac_LEACH_PRP = "indirect N2O (leaching), pasture")
  if (object == "PARAM_CATALOGUE" && key %in% names(p)) return(unname(p[key]))
  if (object == "PARAM_CATALOGUE") return("gross energy, so enteric CH4 + manure CH4")
  ""
}

# --- values we believe are still wrong -------------------------------------
# Research results, not derivable from the data, so written out explicitly.
# A row here is NOT changed in the code; it is put to the reviewer.
PROPOSALS <- rbind(
  data.frame(object = "PARAM_CATALOGUE", key = "Milk", field = "ipcc_default",
    proposed = "", status = "APPLIED_OVERTURNS_REVIEW",
    why = "Changed from 3.5 to 1.2 by the low-productivity basis decision of 2026-09-11. 3.5 was the Africa AGGREGATE row of Table 10A.1, a population-weighted average of the high (5.8) and low (1.2) productivity systems; 1.2 is the low-productivity row. Review round 8 page 7 agreed 3.5 against a previous unsourced 4.0, and that was right FOR THE AGGREGATE ROW. What changed is the basis, not the reading: the productivity question does not appear to have been put to the reviewer. Reverting is a single cell in the master."),
  # The four composting MCF proposals were WITHDRAWN. They rested on
  # comparing 0.5 against the 2019 Refinement, but the tool's declared MCF
  # basis is the 2006 table, where Composting - Static pile IS 0.5, and ten
  # of the twelve systems read their MCF from it. The value is correct.
  #
  # The anaerobic digester and MW proposals were APPLIED, so they now appear
  # automatically as changes rather than as proposals.
  data.frame(object = "PARAM_CATALOGUE", key = "Milk", field = "ipcc_default",
    proposed = "", status = "APPLIED_OVERTURNS_REVIEW",
    why = "Changed from 3.5 to 1.2 by the low-productivity basis decision of 2026-09-11. 3.5 was the Africa AGGREGATE row of Table 10A.1, a population-weighted average of the high (5.8) and low (1.2) productivity systems; 1.2 is the low-productivity row. Review round 8 page 7 agreed 3.5 against a previous unsourced 4.0, and that was right FOR THE AGGREGATE ROW. What changed is the basis, not the reading: the productivity question does not appear to have been put to the reviewer. Reverting is a single cell in the master."),
  data.frame(object = "MMS_DEFAULTS", key = "composting", field = "mcf_tropical",
    proposed = "2.5", status = "OPEN",
    why = "The row declares the Static Pile variant and its EF3 (0.010) and Frac (0.65) both follow it, but 0.5 is the 2019R In-vessel figure. 2019R Table 10.17 gives Composting - Static pile (Forced aeration) 1.00 cool / 2.00 temperate / 2.50 warm. Correct as-is under 2006, where static pile is 0.5."),
  data.frame(object = "MMS_DEFAULTS", key = "composting", field = "mcf_temperate",
    proposed = "2.0", status = "OPEN",
    why = "See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant."),
  data.frame(object = "MMS_DEFAULTS", key = "composting", field = "mcf_boreal",
    proposed = "1.0", status = "OPEN",
    why = "See mcf_tropical: the MCF is the only coefficient on this row still reading the other edition's variant."),
  data.frame(object = "MMS_DEFAULTS", key = "composting", field = "mcf_tropical_dry",
    proposed = "2.5", status = "OPEN",
    why = "See mcf_tropical. This column mirrors mcf_tropical on every system, so it moves with it."),
  data.frame(object = "MMS_FRAC_DEFAULTS_2019", key = "anaerobic_digester", field = "frac_gas_high",
    proposed = "0.50", status = "OPEN",
    why = "Table 10.22 gives Anaerobic digester as a bare range 0.05 to 0.50 with no central. The tool takes 0.05 as the central and samples 0.02 to 0.08, so its whole range sits at or below IPCC's floor and its ceiling is six times too low."),
  data.frame(object = "PARAM_CATALOGUE", key = "MW", field = "ipcc_ref",
    proposed = "(none)", status = "OPEN",
    why = "Cites Table 10A.2, which has no mature-weight column; neither does Table 10A.1. IPCC publishes no default for mature weight. Review round 7 item 3 raised exactly this; the companion value (400 kg BW) was fixed and this citation was not."),
  data.frame(object = "PARAM_CATALOGUE", key = "Milk", field = "ipcc_default",
    proposed = "3.5 or 1.2", status = "PROPOSED",
    why = "3.5 is the Africa AGGREGATE row of Table 10A.1, which footnote 4 defines as a weighted average of high-productivity (5.8) and low-productivity (1.2) systems. The round 8 move from an unsourced 4.0 to 3.5 was right for that row. The open question is which row the tool should sit on: Bo is 0.13 on the stated basis of 'other regions, LOW productivity' and Ca is 0.17, the Pasture/Range coefficient that Table 10A.1 attaches to the low-productivity row, while the aggregate row is Stall Fed. On a consistent low-productivity basis Africa dairy milk is 1.2. Measured for dairy cows per 100,000 head: enteric CH4 6957.7 t/yr at 3.5 against 5929.6 t/yr at 1.2, a 14.8% difference. Separately, footnote 1 says the published figure is milk yield per day across the WHOLE YEAR, while the tool defines the field as per-lactating-cow and multiplies by pct_pregnant, discounting it a second time (NE_l 15% low)."),
  data.frame(object = "PARAM_CATALOGUE", key = "Fat", field = "ipcc_default",
    proposed = "no change", status = "PROPOSED",
    why = "UNCHANGED and confirmed. Table 10A.1 gives 4.3 for Africa in all three rows (aggregate, high productivity and low productivity), so the low-productivity basis decision cannot move it. The round 8 comment that IPCC 2019 gives 4.3 for Africa is exactly right. Listed only so the reviewer can see it was rechecked and survived the basis change that moved Milk."),
  data.frame(object = "IPCC_DEFAULTS_BY_REGION", key = "asia", field = "default_val",
    proposed = "(decide)", status = "PROPOSED",
    why = "Table 10A.1 Asia dairy is 386 (low productivity 355); Table 10A.2 Asia gives 376 and 305. The shipped 350 matches no Asia row. Review round 7 item 3 kept this object for BW only after the other benchmarks were withdrawn."),
  data.frame(object = "IPCC_DEFAULTS_BY_REGION", key = "oceania", field = "default_val",
    proposed = "(decide)", status = "PROPOSED",
    why = "Table 10A.1 Oceania dairy is 488; Table 10A.2 gives 416 and 467. The shipped 500 appears in no Oceania row. Same review provenance as asia."),
  stringsAsFactors = FALSE)
PROPOSALS$k <- kk(PROPOSALS)

# --- assemble ---------------------------------------------------------------
i <- match(M$k, B$k)

# EFFECTIVE before, not merely "was this row in the file".
#
# YM/DE/CP_BY_SUBCAT are new OBJECTS, so every one of their 36 rows looks new.
# Most are not behaviour changes: before the split, a bull's CP resolved to the
# PARAM_CATALOGUE default of 10 and it still does. Only the rows that actually
# moved are changes, and a reviewer asked to check 36 rows of which 4 matter
# will skim all 36. So a row from a new per-sub-category object is compared
# against what the baseline app would have resolved for that parameter, which
# is the baseline catalogue default.
SUBCAT_OF <- c(YM_BY_SUBCAT = "Ym", DE_BY_SUBCAT = "DE", CP_BY_SUBCAT = "CP",
               CFI_BY_SUBCAT = "Cfi", C_GROWTH_BY_SUBCAT = "C",
               LW_BY_SUBCAT = "BW", MW_BY_SUBCAT = "MW", WG_BY_SUBCAT = "WG",
               PCT_PREGNANT_BY_SUBCAT = "pct_pregnant")
base_cat <- function(param) {
  h <- B$value[B$object == "PARAM_CATALOGUE" & B$key == param &
               B$field == "ipcc_default"]
  if (length(h)) h[1] else NA_character_
}
before_raw <- B$value[i]
for (r in which(is.na(i) & M$object %in% names(SUBCAT_OF)))
  before_raw[r] <- base_cat(SUBCAT_OF[[M$object[r]]])

R <- data.frame(
  object = M$object, key = M$key, field = M$field,
  before = fmt(before_raw),
  now    = fmt(M$value),
  verdict = ifelse(is.na(M$ipcc_verdict), "", M$ipcc_verdict),
  source  = ifelse(is.na(M$ipcc_source), "", M$ipcc_source),
  round   = ifelse(is.na(M$review_round), "", M$review_round),
  is_new  = is.na(i),
  stringsAsFactors = FALSE)
R$pathway <- mapply(PATHWAY, R$object, R$key, R$field)
# A citation row's ipcc_source is the generic META note, which tells the
# reviewer nothing. Say what the citation was and why it moved.
CITE_WHY <- c(
  Bo = "Corrected citation, not a value change. Table 10.16 is the deer, reindeer, rabbit and fur-bearing animal emission-factor table in both editions. The cattle Bo values are in Table 10.16A (Updated) of the 2019 Refinement.")
is_cite <- R$field == "ipcc_ref"
R$source[is_cite] <- ifelse(R$key[is_cite] %in% names(CITE_WHY),
                            CITE_WHY[R$key[is_cite]],
                            "Citation change only, no value moved.")
# A row counts as changed when the value the app RESOLVES moved, whether or
# not the row existed before. A new row holding the value the catalogue
# already supplied changed nothing and must not appear.
R$changed <- !same(before_raw, M$value)

j <- match(kk(R), PROPOSALS$k)
R$proposed <- ifelse(is.na(j), "", PROPOSALS$proposed[j])
R$why      <- ifelse(is.na(j), "", PROPOSALS$why[j])
R$status   <- ifelse(!is.na(j), PROPOSALS$status[j],
               ifelse(R$changed, "APPLIED", ""))

# META fields (labels, units, the versions string) are not shipped numbers and
# would only pad the table, EXCEPT where we are putting one to the reviewer:
# MW's ipcc_ref cites a table that does not contain the value, which is a
# citation defect worth as much as a wrong number.
# META fields (labels, units, the versions string) are not shipped numbers and
# would only pad the table, with two exceptions. A changed ipcc_ref is a
# verifiable claim about where a value came from and belongs in front of the
# reviewer: Bo cited "Table 10.16", which in both editions is the deer and
# reindeer emission-factor table. And MW's citation is itself a proposal.
keep <- R$status != "" &
        (R$verdict != "META" | !is.na(j) | R$field == "ipcc_ref")
R <- R[keep, ]
R <- R[order(factor(R$status, levels = c("APPLIED_OVERTURNS_REVIEW", "APPLIED", "PROPOSED", "OPEN")),
             R$object, R$key, R$field), ]

esc <- function(x) gsub("\\|", "\\\\|", ifelse(is.na(x), "", x))
sect <- function(d, cols, hdr) c(
  paste0("| ", paste(hdr, collapse = " | "), " |"),
  paste0("|", paste(rep("---", length(hdr)), collapse = "|"), "|"),
  vapply(seq_len(nrow(d)), function(r)
    paste0("| ", paste(vapply(cols, function(cn) esc(d[[cn]][r]), character(1)),
                       collapse = " | "), " |"), character(1)))

n_app <- sum(R$status == "APPLIED"); n_pro <- sum(R$status == "PROPOSED")
n_opn <- sum(R$status == "OPEN")
n_ovr <- sum(R$status == "APPLIED_OVERTURNS_REVIEW")

out <- c(
"# IPCC default values: what changed, and what we think is still wrong",
"",
sprintf("Generated %s by `scripts/build_review_table.R`. Do not edit by hand.", Sys.Date()),
"",
"## What this is",
"",
"Every IPCC default the cattle uncertainty tool ships was read back against the IPCC source text, value by value, in September 2026. This is the result, laid out so it can be checked.",
"",
sprintf("The **before** column is the value as it stood at commit `fbfa1bc` (2026-07-10), the last change before September and the last recorded deployment. That is still what the live app runs, so the before column is what a user would get today. It is extracted from git by `scripts/extract_baseline_defaults.R`, never retyped."),
"",
"**What each status is asking of you:**",
"",
"| status | count | meaning |",
"|---|---|---|",
sprintf("| `APPLIED` | %d | Already changed. The IPCC basis was unambiguous and no review round had ruled on the value. Please endorse, or object. |", n_app),
sprintf("| `PROPOSED` | %d | We think it is wrong, but a numbered review round adjudicated it, so it has **not** been changed. Your call. |", n_pro),
sprintf("| `OPEN` | %d | Differs from IPCC with no recorded reason and no review history. A judgement call we did not want to take alone. |", n_opn),
sprintf("| `APPLIED_OVERTURNS_REVIEW` | %d | **Changed, and it reverses a value a review round agreed.** Read these first. |", n_ovr),
"",
"Nothing here has been pushed or deployed.",
"",
"---",
"",
sprintf("## 0. Applied, and it overturns an earlier review decision (%d)", n_ovr),
"",
"The one thing in this document that most needs a second opinion.",
"")
out <- c(out, sect(R[R$status == "APPLIED_OVERTURNS_REVIEW", ],
  c("object", "key", "field", "before", "now", "round", "why"),
  c("object", "key", "field", "was 2026-07-10", "now", "review round", "why")))
out <- c(out, "",
sprintf("## 1. Already applied (%d)", n_app),
"",
"Changed since 2026-07-10. Each cites the IPCC table it was read from.",
"")
out <- c(out, sect(R[R$status == "APPLIED", ],
  c("object", "key", "field", "before", "now", "pathway", "source"),
  c("object", "key", "field", "before", "now", "affects", "IPCC source")))

out <- c(out, "", sprintf("## 2. Proposed, not changed: a review round ruled on these (%d)", n_pro), "",
  "Left alone deliberately. The earlier decision may rest on context the code does not record.", "")
out <- c(out, sect(R[R$status == "PROPOSED", ],
  c("object", "key", "field", "before", "now", "proposed", "round", "why"),
  c("object", "key", "field", "was 2026-07-10", "current", "proposed",
    "review round", "why")))

out <- c(out, "", sprintf("## 3. Open questions (%d)", n_opn), "",
  "Differs from IPCC with no recorded reason. These would move a reported number. Where the `was` and `current` columns differ, the value was already changed in September and we now think it should move again.", "")
out <- c(out, sect(R[R$status == "OPEN", ],
  c("object", "key", "field", "before", "now", "proposed", "pathway", "why"),
  c("object", "key", "field", "was 2026-07-10", "current", "proposed",
    "affects", "why")))

out <- c(out, "",
"---", "",
"## One change with no row in the tables above",
"",
"The biological-zero rule tested only for males, so every non-male sub-category inherited the dairy-cow milk yield of 3.5 kg/day, including heifers (which by the tool's own label have not calved), female calves and feedlot cattle. That added a net-energy-for-lactation term to animals that cannot produce milk. Annex 10A.2 gives a milk yield only to its Mature Females rows, in every region; Growing/Replacement, Calves and Feedlot cattle are blank.",
"",
"Corrected so that Milk, Fat and MilkPR are non-zero only for mature females. Measured per 100,000 head: heifers enteric CH4 6161.7 to 5170.6 t/yr (-16.1%), feedlot cattle 3655.2 to 3214.3 (-12.1%). Calves were unaffected numerically because the separate pregnancy zero already suppressed the term, but the filled template had been showing a milk yield for a calf.",
"",
"It does not appear in the tables above because it is a rule in the resolver, not a value in the defaults file.",
"",
"## How to read the manure rows",
"",
"`MMS_DEFAULTS` rows are per manure management system. IPCC splits several systems into variants with different coefficients (liquid slurry with and without a crust, composting in-vessel versus static pile), and every coefficient on one of our rows must come from the variant that row declares. The `ipcc_variant` column in `reference/DEFAULTS_MASTER.md` records which one.",
"",
"`mcf_tropical_dry` mirrors `mcf_tropical` on every system: the 2019 Refinement resolves ten climate zones and the tool resolves four.",
"",
"## Climate basis",
"",
"Three Chapter 11 factors have separate wet and dry climate values in IPCC, and the tool ships the wet-climate figure for everyone:",
"",
"| factor | wet (shipped) | dry | aggregated |",
"|---|---|---|---|",
"| EF3_PRP | 0.006 | 0.002 | 0.004 |",
"| EF4 | 0.014 | 0.005 | 0.010 |",
"| Frac_LEACH_PRP | 0.24 | 0 | not published |",
"",
"A dry-climate inventory that accepts the defaults therefore overstates pasture N2O and, for leaching, reports a pathway IPCC treats as absent. The decision taken was to keep the wet-climate defaults, document the alternatives, and warn rather than add a required climate input. Flagged here because it affects any dry-climate country using the tool.",
"",
"## Where these values live",
"",
"`reference/defaults_master.csv` is the single authority. Every other surface (the Excel template, the AI translator prompts, the methodology and user guide, the worked examples) is generated from it, and `scripts/verify_defaults.R` checks all 14 surfaces against it on every build. A value accepted here is changed in that one file and propagates everywhere.",
"")

writeLines(out, "reference/VALUE_CHANGES_FOR_REVIEW.md", useBytes = TRUE)
utils::write.csv(
  R[, c("status", "object", "key", "field", "before", "now", "proposed",
        "pathway", "verdict", "round", "source", "why")],
  "reference/VALUE_CHANGES_FOR_REVIEW.csv", row.names = FALSE)

cat(sprintf("wrote reference/VALUE_CHANGES_FOR_REVIEW.md (%d rows: %d applied, %d proposed, %d open)\n",
            nrow(R), n_app, n_pro, n_opn))
