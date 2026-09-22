# =============================================================================
# build_knowledge_provenance.R -- knowledge/14-ipcc-provenance.md
# =============================================================================
#
# The knowledge base is MAP/GAP: pointers and reasoning, not values, so that
# it cannot drift. This file is the deliberate exception, and it is safe for
# the same reason the rule exists: it is GENERATED from
# defaults/defaults_master.csv, so it cannot say anything the authority does
# not say. Regenerate it rather than editing it.
#
# It answers a different question from reports/ALL_VALUES.md. That file is
# organised by tool object: "what is BW and where did it come from". This one
# is organised by SOURCE DOCUMENT: "open Table 10A.1, which of our values are
# supposed to be on that page". That is the direction you read in when you are
# checking the tool against the guidelines rather than the other way round.
#
# Copyright note: knowledge/README.md forbids verbatim IPCC chapter text in
# this folder. The master's ipcc_source field sometimes quotes a footnote in
# full. Those quotations are STRIPPED here and replaced with a pointer to the
# master, which is gitignored-adjacent but tracked, and which is where the
# full wording belongs.
#
# Usage (from project root):
#   Rscript scripts/build_knowledge_provenance.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")
OUT <- "knowledge/14-ipcc-provenance.md"
if (!dir.exists("knowledge")) {
  cat("knowledge/ is not present (it is local-only and gitignored). Nothing to do.\n")
  quit(save = "no")
}

M <- utils::read.csv("defaults/defaults_master.csv", stringsAsFactors = FALSE,
                     na.strings = "<NA>", colClasses = "character")
num <- function(v) suppressWarnings(as.numeric(v))
V <- M[!is.na(num(M$value)) & M$ipcc_verdict != "META", ]
V$row_order <- num(V$row_order)

fmtv <- function(v) format(num(v), scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
esc  <- function(x) gsub("\\|", "\\\\|", ifelse(is.na(x), "", x))

# --- strip verbatim quotations, per the knowledge/ copyright rule -----------
strip_quotes <- function(s) {
  s <- gsub("'[^']{40,}'", "[quoted in the master]", s)
  gsub("“[^”]{40,}”", "[quoted in the master]", s)
}

# --- classify each value by the document it was read from -------------------
TABLE_PAT <- "(Table|Eq|Annex) ?[0-9]+[A-Z]?[.][0-9]+[A-Za-z]*"
# regmatches() returns ONLY the elements that matched, so it is shorter than
# the input whenever anything failed to match. Feeding it to ifelse() recycles
# it against the full-length condition and silently misaligns every row: the
# first version of this script filed a Ym value that cites Table 10.12 under
# Table 10.7. Build the full-length vector by assignment instead, and assert
# the result below.
tok <- function(s) {
  out <- rep(NA_character_, length(s))
  m <- regexpr(TABLE_PAT, s)
  out[m > 0] <- regmatches(s, m)
  out
}
V$tbl <- tok(V$ipcc_source)
stopifnot(all(is.na(V$tbl) |
              mapply(grepl, V$tbl, V$ipcc_source, MoreArgs = list(fixed = TRUE))))

# Edition: whichever token appears FIRST, because the convention is
# "2019R V4 Ch10 Table X ..." and a later mention is usually the comparison
# ("2006 publishes no per-system fractions"), not the source.
first_at <- function(s, p) { i <- regexpr(p, s, fixed = TRUE); ifelse(i > 0, i, Inf) }
p19 <- first_at(V$ipcc_source, "2019R")
p06 <- first_at(V$ipcc_source, "2006")
V$edition <- ifelse(is.infinite(p19) & is.infinite(p06), "",
                    ifelse(p19 <= p06, "2019R", "2006"))
# Chapter comes from the table NUMBER, not from the prose. Table 10.22's
# source mentions Chapter 11 in passing (the PRP pathway is a Ch11 exception)
# and a text match filed the whole 66-value group under Ch11.
V$chapter <- ifelse(grepl("^(Table|Eq|Annex) ?11[.]", ifelse(is.na(V$tbl), "", V$tbl)),
                    "Ch11", "Ch10")

# Where to go and read it. The extracted text is what makes a claim checkable
# without a PDF viewer.
DOCS <- data.frame(
  edition = c("2019R", "2019R", "2006", "2006"),
  chapter = c("Ch10", "Ch11", "Ch10", "Ch11"),
  pdf = c("ipcc_reference/pdf/19R_V4_Ch10_Livestock (2).pdf",
          "ipcc_reference/pdf/19R_V4_Ch11_Soils_N2O_CO2.pdf",
          "ipcc_reference/pdf/V4_10_Ch10_Livestock.pdf",
          "ipcc_reference/pdf/V4_11_Ch11_N2O&CO2.pdf"),
  txt = c("ipcc_reference/text/19R_V4_Ch10_Livestock.txt",
          "ipcc_reference/text/19R_V4_Ch11.txt",
          "ipcc_reference/text/V4_10_Ch10_Livestock.txt",
          "ipcc_reference/text/V4_11_Ch11.txt"),
  stringsAsFactors = FALSE)
docfile <- function(ed, ch) {
  i <- which(DOCS$edition == ed & DOCS$chapter == ch)
  if (!length(i)) "" else DOCS$txt[i[1]]
}

# --- assemble ---------------------------------------------------------------
o <- c(
"# 14 - Where every value comes from",
"",
"**Purpose:** for each shipped value, the IPCC document, table and page it was read from, so a claim can be checked against the guidelines without going through the code.",
sprintf("**Derived from:** `defaults/defaults_master.csv`, generated %s by `scripts/build_knowledge_provenance.R`.", Sys.Date()),
"**Kind:** GENERATED. Do not edit by hand; regenerate.",
"",
"---",
"",
"## Why this file holds values when the rest of the folder does not",
"",
"The MAP/GAP rule says knowledge files carry pointers, not values, so they cannot drift. This file carries values and still cannot drift, because it is generated from the master. If it disagrees with the master, it is stale: rerun the script.",
"",
"It is organised by **source document**, which is the opposite of `reports/ALL_VALUES.md`. That file asks \"what is BW and where did it come from\". This one asks \"I have Table 10A.1 open, which of our values are supposed to be on this page\". Use this one when checking the tool against the guidelines, and that one when checking a value against the tool.",
"",
"Verbatim IPCC wording is stripped here, per the no-chapter-text rule in `README.md`. Where a footnote is quoted in full, the master has it.",
"",
"## How to check a value yourself",
"",
"The chapter PDFs and a plain-text extraction of each are in `reference/` (both gitignored: the chapters are copyrighted).",
"",
"| edition | chapter | PDF | extracted text |",
"|---|---|---|---|")
for (i in seq_len(nrow(DOCS)))
  o <- c(o, sprintf("| %s | %s | `%s` | `%s` |", DOCS$edition[i], DOCS$chapter[i],
                    DOCS$pdf[i], DOCS$txt[i]))
o <- c(o, "",
"Grep the text, not the PDF. For example, to check the Africa low-productivity dairy row that supplies eight catalogue defaults at once:",
"",
"```bash",
"grep -n 'Low productivity systems 270' ipcc_reference/text/19R_V4_Ch10_Livestock.txt",
"```",
"",
"That row reads `270 / 0 / Pasture-Range / 1.2 / 4.3 / 3.6 / 0 / 52 / 51 / 9.6 / 6.5`, which is BW, WG, feeding situation, Milk, Fat, MilkPR, hours, pct_pregnant, DE, CP and Ym in one line.",
"",
"Two source sets are **not** in `reference/`, so they cannot be checked locally: the Assessment Reports behind the GWP values, and the two papers behind the suggested uncertainty percentages.",
"",
"---",
"",
"## Summary",
"")

vt <- table(V$ipcc_verdict)
o <- c(o, sprintf("%d shipped numeric values. Verdicts: %s.", nrow(V),
                  paste(sprintf("%d %s", vt, names(vt)), collapse = ", ")), "")

ntbl <- sum(!is.na(V$tbl))
o <- c(o, sprintf("%d are traced to a numbered IPCC table or equation; %d are not (Assessment Reports, the two uncertainty papers, project assumptions and documented deviations from a published range).",
                  ntbl, nrow(V) - ntbl), "", "---", "",
"## By IPCC table", "")

# order tables by how many values they supply
tt <- sort(table(V$tbl), decreasing = TRUE)
for (t in names(tt)) {
  d <- V[!is.na(V$tbl) & V$tbl == t, ]
  d <- d[order(d$object, d$row_order), ]
  eds <- sort(unique(d$edition[nzchar(d$edition)]))
  ch <- unique(d$chapter)[1]
  df <- docfile(if (length(eds)) eds[1] else "2019R", ch)
  o <- c(o, sprintf("### %s  (V4 %s, %s) - %d %s", t, ch,
                    if (length(eds) == 1) eds else
                      if (length(eds) > 1) "edition per row, see the column below" else
                        "edition not stated",
                    nrow(d), if (nrow(d) == 1) "value" else "values"),
         "",
         if (length(eds) > 1)
           sprintf("Rows here cite both editions. %s",
                   paste(sprintf("`%s`", DOCS$txt[DOCS$chapter == ch]), collapse = " and "))
         else if (nzchar(df)) sprintf("Read it in `%s`.", df) else "",
         "",
         "| object | key | field | value | ed. | verdict | row cited |",
         "|---|---|---|---|---|---|---|")
  for (j in seq_len(nrow(d))) {
    src <- strip_quotes(d$ipcc_source[j])
    src <- sub(sprintf("^.*?%s[^,:]*[,:] ?", t), "", src)   # drop the table token itself
    if (nchar(src) > 150) src <- paste0(substr(src, 1, 147), "...")
    o <- c(o, sprintf("| `%s` | %s | %s | **%s** | %s | `%s` | %s |",
                      d$object[j], esc(d$key[j]), esc(d$field[j]),
                      fmtv(d$value[j]), d$edition[j], d$ipcc_verdict[j], esc(src)))
  }
  o <- c(o, "")
}

# --- non-table sources ------------------------------------------------------
o <- c(o, "---", "", "## Sources that are not a numbered IPCC table", "")
N <- V[is.na(V$tbl), ]
groups <- list(
  list(name = "IPCC Assessment Reports (global warming potentials)",
       sel = grepl("AR[456] WGI", N$ipcc_source),
       note = "Not in `reference/`: the AR volumes were not obtained, so these were confirmed against the published values rather than read from a local source. The tool offers all three sets and the user chooses; UNFCCC reporting currently requires AR5."),
  list(name = "Penman et al. (2000) IPCC Good Practice Guidance, and Monni et al. (2007)",
       sel = grepl("Penman", N$ipcc_source),
       note = "These are the **suggested uncertainty percentages**, not the values. IPCC publishes no uncertainty for most Tier 2 inputs, so the tool suggests one and says in the user guide that it is not an IPCC figure. A compiler with country data should override them."),
  list(name = "Project assumptions and documented deviations",
       sel = !grepl("AR[456] WGI|Penman", N$ipcc_source),
       note = "Values with no IPCC source, or where the tool deliberately departs from a published one. Each carries its reason in the source column.")
)
for (g in groups) {
  d <- N[g$sel, ]
  if (!nrow(d)) next
  d <- d[order(d$object, d$row_order), ]
  o <- c(o, sprintf("### %s - %d %s", g$name, nrow(d), if (nrow(d) == 1) "value" else "values"), "", g$note, "",
         "| object | key | field | value | verdict | why |",
         "|---|---|---|---|---|---|")
  for (j in seq_len(nrow(d))) {
    src <- strip_quotes(d$ipcc_source[j])
    if (nchar(src) > 150) src <- paste0(substr(src, 1, 147), "...")
    o <- c(o, sprintf("| `%s` | %s | %s | **%s** | `%s` | %s |",
                      d$object[j], esc(d$key[j]), esc(d$field[j]),
                      fmtv(d$value[j]), d$ipcc_verdict[j], esc(src)))
  }
  o <- c(o, "")
}

# --- the two lists a reviewer asks for first --------------------------------
o <- c(o, "---", "", "## Values IPCC publishes no default for", "",
"These are not gaps in the verification. IPCC genuinely offers nothing, so the tool supplies a project figure and must not present it as an IPCC default.",
"", "| object | key | value | why |", "|---|---|---|---|")
nd <- V[V$ipcc_verdict == "NO_IPCC_DEFAULT", ]
nd <- nd[order(nd$object, nd$row_order), ]
for (j in seq_len(nrow(nd)))
  o <- c(o, sprintf("| `%s` | %s | **%s** | %s |", nd$object[j], esc(nd$key[j]),
                    fmtv(nd$value[j]),
                    esc(substr(strip_quotes(nd$ipcc_source[j]), 1, 150))))

o <- c(o, "", "## Open deviations: the tool differs and no reason is on record", "",
"`DEVIATION_OPEN` is the reviewer's worklist. Each is a value that does not match the cited table and has no recorded justification.",
"", "| object | key | value | what IPCC says |", "|---|---|---|---|")
od <- V[V$ipcc_verdict == "DEVIATION_OPEN", ]
od <- od[order(od$object, od$row_order), ]
for (j in seq_len(nrow(od)))
  o <- c(o, sprintf("| `%s` | %s | **%s** | %s |", od$object[j], esc(od$key[j]),
                    fmtv(od$value[j]),
                    esc(substr(strip_quotes(od$ipcc_source[j]), 1, 150))))

o <- c(o, "", "---", "",
"## What guarantees this is true of the running app", "",
"The file is generated from the master, but the master is only the authority if the code actually reads it. Three checks in `scripts/audit.R` close that loop:",
"",
"- **F39** perturbs the master and requires every derived object to move, so no R constant is a literal in disguise.",
"- **F40** and **F43** cover the gap-fill path: a missing input must be filled from the master, and no fallback literal may compete with it.",
"- **F42** requires each value to cite the table it is supposed to come from, so a number that exists somewhere in IPCC cannot pass as read from the right place.",
"",
"`scripts/verify_defaults.R` then proves the 15 user-facing surfaces carry the same numbers. Its report is `DEFAULTS_MATRIX.md`.",
"")

writeLines(o, OUT, useBytes = TRUE)
cat(sprintf("wrote %s: %d values, %d IPCC tables/equations, %d non-table sources\n",
            OUT, nrow(V), length(tt), nrow(N)))
