# =============================================================================
# verify_defaults.R -- exhaustive cross-surface check of every shipped default
# =============================================================================
#
# WHY THIS EXISTS
#
# The app's IPCC defaults are copied onto many surfaces: the Excel template
# (four separate sheets), the six translator prompt files, the www/ copies and
# the DIY kit zip, both published guides and their built PDFs/DOCX, the two
# built-in example inventories, and the audit's own literals. Until now those
# copies were checked by eye, one suspected problem at a time. That is how a
# wrong dry_lot MCF survived from the initial commit, and how the June 2026
# MMS corrections reached the code but never the translator prompt.
#
# This script replaces eye-checking with enumeration. ROWS are generated from
# the R constants, so a value cannot be missed by oversight. COLUMNS are the
# surfaces. Every cell is compared and given a verdict.
#
# Usage (from project root):
#   Rscript scripts/verify_defaults.R
#
# Writes DEFAULTS_MATRIX.md (human) and DEFAULTS_MATRIX.csv (machine).
# Exits non-zero if any cell is DIFFERS or ABSENT-UNEXPECTED outside the
# allow-list.
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

suppressMessages({
  for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))
    if (!grepl("^_", basename(f))) source(f)
})

TOL <- 1e-9
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---------------------------------------------------------------------------
# ALLOW-LIST -- deliberate divergences.
#
# Every entry needs a justification and a source anchor. This list is printed
# in the report so it can be re-read rather than forgotten. Anything NOT here
# and not MATCH is a defect until proven otherwise.
# ---------------------------------------------------------------------------
ALLOW <- data.frame(
  object = c("PARAM_CATALOGUE", "PARAM_CATALOGUE",
             "PARAM_CATALOGUE", "PARAM_CATALOGUE"),
  key    = c("Bo", "Cfi", "N", "WG"),
  field  = c("ipcc_default", "ipcc_default", "ipcc_default", "ipcc_default"),
  surface = c("engine_fallback", "engine_fallback",
              "xlsx_parameters", "xlsx_parameters"),
  why = c(
    "mc_simulation.R get_param_alt uses Bo=0.10; bites only when the row is absent entirely. Documented in knowledge/04-parameters.md",
    "mc_simulation.R get_param_alt uses Cfi=0.322; bites only when the row is absent entirely",
    "Example template shows an illustrative herd of 500,000 head; the catalogue default for N is deliberately NA (the user must supply it)",
    "Example template shows an illustrative 0.10 kg/day gain for a dairy cow; the catalogue default is 0 (adults do not grow)"),
  stringsAsFactors = FALSE)

# ---------------------------------------------------------------------------
# REVIEW PROVENANCE -- loaded before any comparison, so a DIFFERS on a value
# that a numbered review round adjudicated is ESCALATED, never quietly fixed.
# Local-only file (names and quotes a reviewer); absent in a clean clone.
# ---------------------------------------------------------------------------
RP_PATH <- "knowledge/review_provenance_index.csv"
REVIEW <- if (file.exists(RP_PATH)) {
  read.csv(RP_PATH, stringsAsFactors = FALSE)
} else {
  message("NOTE: ", RP_PATH, " absent (expected in a clean clone); ",
          "review-provenance column will be blank.")
  data.frame(object = character(), key = character(), field = character(),
             round = character(), authority = character(),
             stringsAsFactors = FALSE)
}
review_for <- function(obj, key, fld) {
  h <- REVIEW[REVIEW$object == obj &
              (REVIEW$key == key | REVIEW$key == "ALL") &
              (REVIEW$field == fld | REVIEW$field == "ALL"), ]
  if (nrow(h) == 0) return(c(round = "", authority = ""))
  c(round = h$round[1], authority = h$authority[1])
}

# ---------------------------------------------------------------------------
# 1. ROW UNIVERSE -- generated from the constants
# ---------------------------------------------------------------------------
rows <- list()
add <- function(object, key, field, value)
  rows[[length(rows) + 1L]] <<- data.frame(
    object = object, key = key, field = field,
    reference = as.character(value), stringsAsFactors = FALSE)

pc <- PARAM_CATALOGUE
for (i in seq_len(nrow(pc))) for (f in c(
  "ipcc_default", "suggested_uncertainty_pct", "suggested_lower_bound",
  "suggested_upper_bound", "suggested_distribution", "param_type",
  "param_tier", "unit", "ipcc_ref"))
  add("PARAM_CATALOGUE", pc$parameter[i], f, pc[[f]][i])

md <- MMS_DEFAULTS
for (i in seq_len(nrow(md))) for (f in c(
  "mcf_tropical", "mcf_tropical_dry", "mcf_temperate", "mcf_boreal",
  "ef3", "label", "versions"))
  add("MMS_DEFAULTS", md$id[i], f, md[[f]][i])

mf <- MMS_FRAC_DEFAULTS_2019
for (i in seq_len(nrow(mf))) for (f in c(
  "frac_gas", "frac_gas_low", "frac_gas_high",
  "frac_leach", "frac_leach_low", "frac_leach_high"))
  add("MMS_FRAC_DEFAULTS_2019", mf$mms_type[i], f, mf[[f]][i])

for (nm in c("CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT", "LW_BY_SUBCAT",
             "MW_BY_SUBCAT", "WG_BY_SUBCAT", "PCT_PREGNANT_BY_SUBCAT",
             "FEEDING_SITUATION_CA")) {
  o <- get(nm)
  for (k in names(o)) add(nm, k, "value", o[[k]])
}
for (i in seq_len(nrow(IPCC_DEFAULTS_BY_REGION)))
  add("IPCC_DEFAULTS_BY_REGION", IPCC_DEFAULTS_BY_REGION$region[i],
      "default_val", IPCC_DEFAULTS_BY_REGION$default_val[i])
for (ar in names(GWP_VALUES)) for (g in names(GWP_VALUES[[ar]]))
  add("GWP_VALUES", paste0(ar, ".", g), "value", GWP_VALUES[[ar]][[g]])

M <- do.call(rbind, rows)
message("row universe: ", nrow(M), " cells from ",
        length(unique(M$object)), " objects")

# ---------------------------------------------------------------------------
# 2. SURFACE EXTRACTORS
#
# Each returns a named character vector keyed "object|key|field".
# Returning NA for a key means "this surface does not carry that value",
# which scores ABSENT-EXPECTED unless the surface policy says MUST.
# ---------------------------------------------------------------------------
norm <- function(x) {
  x <- trimws(gsub("[`*%]", "", as.character(x)))
  x[x %in% c("", "-", "—", "(none)", "NA", "n/a")] <- NA
  n <- suppressWarnings(as.numeric(x))
  ifelse(is.na(n), x, format(n, trim = TRUE, scientific = FALSE,
                             drop0trailing = TRUE))
}
same <- function(a, b) {
  if (is.na(a) && is.na(b)) return(TRUE)
  if (is.na(a) || is.na(b)) return(FALSE)
  na <- suppressWarnings(as.numeric(a)); nb <- suppressWarnings(as.numeric(b))
  if (!is.na(na) && !is.na(nb)) return(abs(na - nb) < TOL)
  identical(a, b)
}

# -- markdown pipe-table reader (base R; no deps) ---------------------------
md_tables <- function(path) {
  if (!file.exists(path)) return(list())
  ln <- readLines(file(path, encoding = "UTF-8"), warn = FALSE)
  out <- list(); i <- 1
  is_sep <- function(s) grepl("^[[:space:]]*\\|[-:| [:space:]]+$", s) &&
                        grepl("-", s)
  while (i < length(ln)) {
    if (grepl("^[[:space:]]*\\|", ln[i]) && is_sep(ln[i + 1])) {
      hdr <- strsplit(sub("\\|[[:space:]]*$", "",
                          sub("^[[:space:]]*\\|", "", ln[i])), "|",
                      fixed = TRUE)[[1]]
      hdr <- trimws(hdr); body <- list(); j <- i + 2
      while (j <= length(ln) && grepl("^[[:space:]]*\\|", ln[j])) {
        cells <- strsplit(sub("\\|[[:space:]]*$", "",
                              sub("^[[:space:]]*\\|", "", ln[j])), "|",
                          fixed = TRUE)[[1]]
        cells <- trimws(cells); length(cells) <- length(hdr)
        body[[length(body) + 1L]] <- cells; j <- j + 1
      }
      if (length(body)) {
        d <- as.data.frame(do.call(rbind, body), stringsAsFactors = FALSE)
        names(d) <- make.unique(hdr)
        out[[length(out) + 1L]] <- d
      }
      i <- j
    } else i <- i + 1
  }
  out
}
pick_table <- function(tabs, must_have) {
  for (t in tabs) if (all(must_have %in% names(t))) return(t)
  NULL
}

S <- list()   # surface name -> named vector
# NB: an extractor that finds nothing must still appear in the report as a
# column of zeros, otherwise a broken extractor looks like a passing surface.
.empty <- setNames(character(0), character(0))

# --- S1: translator param_catalogue.md -------------------------------------
S[["prompt_param_catalogue"]] <- local({
  v <- .empty
  t <- pick_table(md_tables("translator_prompts/param_catalogue.md"),
                  c("code", "IPCC default"))
  if (!is.null(t)) {
    code <- norm(t$code)
    map <- c(ipcc_default = "IPCC default",
             suggested_distribution = "distribution",
             param_type = "type", param_tier = "tier",
             unit = "unit", ipcc_ref = "IPCC ref")
    for (fld in names(map)) if (map[[fld]] %in% names(t))
      v[paste("PARAM_CATALOGUE", code, fld, sep = "|")] <- norm(t[[map[[fld]]]])
    if ("suggested ±%" %in% names(t)) {
      u <- norm(sub("%$", "", t[["suggested ±%"]]))
      u[grepl("asymmetric", u)] <- NA
      v[paste("PARAM_CATALOGUE", code, "suggested_uncertainty_pct",
              sep = "|")] <- u
    }
  }
  b <- pick_table(md_tables("translator_prompts/param_catalogue.md"),
                  c("code", "lower", "central", "upper"))
  if (!is.null(b)) {
    k <- norm(b$code)
    v[paste("PARAM_CATALOGUE", k, "suggested_lower_bound", sep = "|")] <- norm(b$lower)
    v[paste("PARAM_CATALOGUE", k, "suggested_upper_bound", sep = "|")] <- norm(b$upper)
  }
  # Ca line generated from FEEDING_SITUATION_CA:
  #   "Values: stall_fed = 0; pasture_flat = 0.17; pasture_hilly = 0.36."
  ca_ln <- grep("^Values: ",
                readLines(file("translator_prompts/param_catalogue.md",
                               encoding = "UTF-8"), warn = FALSE),
                value = TRUE)
  if (length(ca_ln)) for (piece in strsplit(sub("^Values: ", "", ca_ln[1]),
                                            ";", fixed = TRUE)[[1]]) {
    kv <- trimws(strsplit(sub("[.]$", "", piece), "=", fixed = TRUE)[[1]])
    if (length(kv) == 2 && kv[1] %in% names(FEEDING_SITUATION_CA))
      v[paste("FEEDING_SITUATION_CA", kv[1], "value", sep = "|")] <- norm(kv[2])
  }
  o <- pick_table(md_tables("translator_prompts/param_catalogue.md"),
                  c("sub-category", "Cfi (Table 10.4)"))
  if (!is.null(o)) {
    k <- norm(o[["sub-category"]])
    v[paste("CFI_BY_SUBCAT", k, "value", sep = "|")] <- norm(o[["Cfi (Table 10.4)"]])
    if ("C (Eq 10.6)" %in% names(o))
      v[paste("C_GROWTH_BY_SUBCAT", k, "value", sep = "|")] <- norm(o[["C (Eq 10.6)"]])
  }
  v
})

# --- S2: translator template_schema.md -------------------------------------
S[["prompt_template_schema"]] <- local({
  v <- .empty
  tabs <- md_tables("translator_prompts/template_schema.md")
  t <- pick_table(tabs, c("id", "EF3"))
  if (!is.null(t)) {
    k <- norm(t$id)
    v[paste("MMS_DEFAULTS", k, "ef3", sep = "|")] <- norm(t$EF3)
    for (pair in list(c("MCF trop.moist", "mcf_tropical"),
                      c("MCF trop.dry", "mcf_tropical_dry"),
                      c("MCF temperate", "mcf_temperate"),
                      c("MCF boreal", "mcf_boreal")))
      if (pair[1] %in% names(t))
        v[paste("MMS_DEFAULTS", k, pair[2], sep = "|")] <- norm(t[[pair[1]]])
    if ("label" %in% names(t))
      v[paste("MMS_DEFAULTS", k, "label", sep = "|")] <- norm(t$label)
    # `versions` is rendered as two tick columns, not the raw "2006,2019"
    # string. Reconstruct it so the cell can be compared rather than skipped.
    if (all(c("2006?", "2019R?") %in% names(t))) {
      tick <- function(x) grepl("✓", x)
      ver <- ifelse(tick(t[["2006?"]]) & tick(t[["2019R?"]]), "2006,2019",
             ifelse(tick(t[["2019R?"]]), "2019",
             ifelse(tick(t[["2006?"]]), "2006", NA_character_)))
      v[paste("MMS_DEFAULTS", k, "versions", sep = "|")] <- ver
    }
  }
  fr <- pick_table(tabs, c("mms_type", "Frac_Gas (mean / low / high)"))
  if (!is.null(fr)) {
    k <- norm(fr$mms_type)
    sp <- function(col, idx) vapply(strsplit(fr[[col]], "/", fixed = TRUE),
      function(p) if (length(p) >= idx) norm(p[idx]) else NA_character_,
      character(1))
    g <- "Frac_Gas (mean / low / high)"; l <- "Frac_Leach (mean / low / high)"
    v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_gas", sep = "|")]       <- sp(g, 1)
    v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_gas_low", sep = "|")]   <- sp(g, 2)
    v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_gas_high", sep = "|")]  <- sp(g, 3)
    if (l %in% names(fr)) {
      v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_leach", sep = "|")]      <- sp(l, 1)
      v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_leach_low", sep = "|")]  <- sp(l, 2)
      v[paste("MMS_FRAC_DEFAULTS_2019", k, "frac_leach_high", sep = "|")] <- sp(l, 3)
    }
  }
  v
})

# --- S3-S6: the generated Excel template -----------------------------------
tmpl <- file.path(tempdir(), "verify_template.xlsx")
ok_tmpl <- tryCatch({
  generate_template_openxlsx(tmpl, include_example = TRUE); TRUE
}, error = function(e) { message("template generation FAILED: ",
                                 conditionMessage(e)); FALSE })

S[["xlsx_parameters"]] <- local({
  v <- .empty; if (!ok_tmpl) return(v)
  p <- as.data.frame(readxl::read_excel(tmpl, sheet = "Parameters", skip = 2))
  nm <- names(p)
  pcol <- nm[which(tolower(nm) == "parameter")][1]
  if (is.na(pcol)) return(v)
  k <- norm(p[[pcol]]); keep <- !is.na(k) & k %in% pc$parameter
  for (pair in list(c("value", "ipcc_default"),
                    c("uncertainty_pct", "suggested_uncertainty_pct"),
                    c("distribution", "suggested_distribution")))
    if (pair[1] %in% nm)
      v[paste("PARAM_CATALOGUE", k[keep], pair[2], sep = "|")] <-
        norm(p[[pair[1]]][keep])
  v
})

S[["xlsx_lists"]] <- local({
  v <- c(); if (!ok_tmpl) return(v)
  l <- as.data.frame(readxl::read_excel(tmpl, sheet = "_Lists"))
  if (!"id" %in% names(l)) return(v)
  k <- norm(l$id); keep <- !is.na(k) & k %in% md$id
  for (f in c("mcf_tropical", "mcf_tropical_dry", "mcf_temperate",
              "mcf_boreal", "ef3", "label", "versions"))
    if (f %in% names(l))
      v[paste("MMS_DEFAULTS", k[keep], f, sep = "|")] <- norm(l[[f]][keep])
  v
})

S[["xlsx_vocab"]] <- local({
  v <- c(); if (!ok_tmpl) return(v)
  w <- as.data.frame(readxl::read_excel(tmpl, sheet = "Vocab",
                                        col_names = FALSE))
  hdr <- which(apply(w, 1, function(r)
    isTRUE(any(grepl("^mms_type$", trimws(as.character(r)))))))
  for (h in hdr) {
    cols <- trimws(as.character(w[h, ])); j <- 1
    while (h + j <= nrow(w) && !is.na(w[h + j, 1]) &&
           norm(w[h + j, 1]) %in% md$id) {
      id <- norm(w[h + j, 1])
      for (pair in list(c("tropical_moist_%", "mcf_tropical"),
                        c("tropical_dry_%", "mcf_tropical_dry"),
                        c("temperate_%", "mcf_temperate"),
                        c("boreal_%", "mcf_boreal"),
                        c("EF3 (kg N2O-N/kg N)", "ef3"),
                        c("label", "label"))) {
        ci <- which(cols == pair[1])
        if (length(ci))
          v[paste("MMS_DEFAULTS", id, pair[2], sep = "|")] <-
            norm(w[h + j, ci[1]])
      }
      j <- j + 1
    }
  }
  # Second Vocab block: keyed on `term`, carries label + EF3 + two MCF cols.
  hdr2 <- which(apply(w, 1, function(r)
    isTRUE(any(grepl("^term$", trimws(as.character(r)))))))
  for (h in hdr2) {
    cols <- trimws(as.character(w[h, ])); j <- 1
    while (h + j <= nrow(w) && !is.na(w[h + j, 1]) &&
           norm(w[h + j, 1]) %in% md$id) {
      id <- norm(w[h + j, 1])
      for (pair in list(c("label", "label"),
                        c("EF3 (kg N2O-N/kg N)", "ef3"),
                        c("MCF tropical%", "mcf_tropical"),
                        c("MCF temperate%", "mcf_temperate"))) {
        ci <- which(cols == pair[1])
        if (length(ci))
          v[paste("MMS_DEFAULTS", id, pair[2], sep = "|")] <-
            norm(w[h + j, ci[1]])
      }
      j <- j + 1
    }
  }
  v
})

S[["xlsx_manure_example"]] <- local({
  v <- .empty; if (!ok_tmpl) return(v)
  # Sheet layout: banner row 1, headers row 2, hints row 3, data row 4.
  # skip = 2 made the HINTS row the header, so nothing ever matched and this
  # surface silently reported zero coverage. skip = 1 is correct.
  m <- as.data.frame(readxl::read_excel(tmpl, sheet = "Manure_Management",
                                        skip = 1))
  if (!"mms_type" %in% names(m)) return(v)
  k <- norm(m$mms_type); keep <- !is.na(k) & k %in% mf$mms_type
  if (!any(keep)) return(v)
  sc <- function(col, fld) if (col %in% names(m))
    v[paste("MMS_FRAC_DEFAULTS_2019", k[keep], fld, sep = "|")] <<-
      norm(as.numeric(m[[col]][keep]) / 100)
  sc("Frac_GasMS_pct", "frac_gas"); sc("lower_frac_gas", "frac_gas_low")
  sc("upper_frac_gas", "frac_gas_high")
  sc("Frac_LeachMS_pct", "frac_leach"); sc("lower_frac_leach", "frac_leach_low")
  sc("upper_frac_leach", "frac_leach_high")
  v
})

# --- S7: audit.R literals ---------------------------------------------------
S[["audit_literals"]] <- local({
  v <- .empty; f <- "scripts/audit.R"
  if (!file.exists(f)) return(v)
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  grab <- function(pat) {
    m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
    if (!length(m)) return(NA_character_)
    norm(sub(pat, "\\1", m, perl = TRUE))
  }
  for (id in md$id) {
    x <- grab(sprintf('mms_ef3\\("%s"\\), ([0-9.]+)', id))
    if (!is.na(x)) v[paste("MMS_DEFAULTS", id, "ef3", sep = "|")] <- x
    x <- grab(sprintf('fr\\("%s"\\)\\$frac_gas, ([0-9.]+)', id))
    if (!is.na(x)) v[paste("MMS_FRAC_DEFAULTS_2019", id, "frac_gas", sep = "|")] <- x
    x <- grab(sprintf('fr\\("%s"\\)\\$frac_leach, ([0-9.]+)', id))
    if (!is.na(x)) v[paste("MMS_FRAC_DEFAULTS_2019", id, "frac_leach", sep = "|")] <- x
  }
  v
})

# --- S8: published guides (.Rmd sources) ------------------------------------
S[["doc_rmd"]] <- local({
  v <- .empty
  for (f in c("doc/methodology.Rmd", "doc/user_guide.Rmd")) {
    if (!file.exists(f)) next
    ln <- readLines(file(f, encoding = "UTF-8"), warn = FALSE)
    for (p in pc$parameter) {
      hit <- grep(sprintf("texttt\\{%s\\}|^%s &", p, p), ln, value = TRUE)[1]
      if (is.na(hit)) next
      cells <- trimws(strsplit(hit, "&", fixed = TRUE)[[1]])
      nums <- suppressWarnings(as.numeric(norm(cells)))
      key <- paste("PARAM_CATALOGUE", p, "ipcc_default", sep = "|")
      ref <- suppressWarnings(as.numeric(
        pc$ipcc_default[pc$parameter == p]))
      if (!is.na(ref) && any(!is.na(nums) & abs(nums - ref) < TOL))
        v[key] <- format(ref, scientific = FALSE, drop0trailing = TRUE)
    }
    # GWP table (methodology.Rmd 4.11): "AR5 (100-yr) & 28 & 265 & ..."
    for (ar in names(GWP_VALUES)) {
      hit <- grep(paste0("^", ar, " \\(100-yr"), ln, value = TRUE)[1]
      if (is.na(hit)) next
      cells <- trimws(strsplit(hit, "&", fixed = TRUE)[[1]])
      nums <- suppressWarnings(as.numeric(norm(cells)))
      for (g in names(GWP_VALUES[[ar]])) {
        ref <- as.numeric(GWP_VALUES[[ar]][[g]])
        if (any(!is.na(nums) & abs(nums - ref) < TOL))
          v[paste("GWP_VALUES", paste0(ar, ".", g), "value", sep = "|")] <-
            format(ref, scientific = FALSE, drop0trailing = TRUE)
      }
    }
  }
  v
})

# --- S9: built PDFs ---------------------------------------------------------
# --- S9: the BUILT guides (.docx) ------------------------------------------
# Reads the .docx rather than the .pdf: a .docx is a zip of XML, so base R can
# extract the text with unz() and no external interpreter. The earlier .pdf
# version depended on invoking python from R, which silently failed under
# Windows quoting and reported zero coverage while looking like a pass.
# The .docx and .pdf are rendered from the same .Rmd in one pass, so checking
# the .docx still catches a stale build.
S[["built_docx"]] <- local({
  v <- .empty
  for (f in c("www/methodology.docx", "www/user_guide.docx")) {
    if (!file.exists(f)) next
    xml <- tryCatch({
      con <- unz(f, "word/document.xml", open = "rb")
      raw <- readBin(con, "raw", n = 8e6)
      close(con)
      iconv(rawToChar(raw), "UTF-8", "UTF-8", sub = " ")
    }, error = function(e) NULL)
    if (is.null(xml) || !nzchar(xml)) {
      message("NOTE: could not read text from ", f,
              " -- built_docx coverage is INCOMPLETE, not passing."); next
    }
    txt <- gsub("[[:space:]]+", " ", gsub("<[^>]*>", " ", xml))
    for (prm in pc$parameter) {
      ref <- suppressWarnings(as.numeric(pc$ipcc_default[pc$parameter == prm]))
      if (is.na(ref)) next
      lab <- format(ref, scientific = FALSE, drop0trailing = TRUE)
      if (grepl(lab, txt, fixed = TRUE))
        v[paste("PARAM_CATALOGUE", prm, "ipcc_default", sep = "|")] <- lab
    }
    for (ar in names(GWP_VALUES)) for (g in names(GWP_VALUES[[ar]])) {
      ref <- as.numeric(GWP_VALUES[[ar]][[g]])
      lab <- format(ref, scientific = FALSE, drop0trailing = TRUE)
      if (grepl(lab, txt, fixed = TRUE))
        v[paste("GWP_VALUES", paste0(ar, ".", g), "value", sep = "|")] <- lab
    }
  }
  v
})

# --- S10: worked_example.md (GENERATED, so it must reproduce) --------------
# The user-supplied country values are legitimately different; everything
# else in the example is an IPCC default and must match.
.WE_USER_KEYS <- c("N", "BW", "MW", "Milk", "Fat", "DE", "CP")
S[["prompt_worked_example"]] <- local({
  v <- .empty
  f <- "translator_prompts/worked_example.md"
  if (!file.exists(f)) return(v)
  ln <- readLines(file(f, encoding = "UTF-8"), warn = FALSE)
  a <- grep("^```template-ready", ln); b <- grep("^```$", ln)
  if (!length(a) || !length(b)) return(v)
  j <- tryCatch(jsonlite::fromJSON(paste(ln[(a[1]+1):(b[b > a[1]][1]-1)],
                                         collapse = "
")),
                error = function(e) NULL)
  if (is.null(j)) { message("NOTE: worked_example JSON did not parse"); return(v) }
  pr <- j$parameters
  if (!is.null(pr) && nrow(pr)) {
    # Parameters with a per-sub-category override must be compared against
    # that override, not the catalogue default: the example legitimately
    # shows heifers Cfi 0.322 where the catalogue holds the lactating 0.386.
    # Routing them to the *_BY_SUBCAT objects also gives those objects their
    # first surface coverage.
    BY_SUBCAT <- c(Cfi = "CFI_BY_SUBCAT", C = "C_GROWTH_BY_SUBCAT",
                   BW = "LW_BY_SUBCAT", MW = "MW_BY_SUBCAT",
                   WG = "WG_BY_SUBCAT", pct_pregnant = "PCT_PREGNANT_BY_SUBCAT")
    keep <- !(pr$parameter %in% .WE_USER_KEYS)
    for (i in which(keep)) {
      prm <- pr$parameter[i]; sc <- pr$sub_category[i]
      if (prm %in% names(BY_SUBCAT)) {
        v[paste(BY_SUBCAT[[prm]], sc, "value", sep = "|")] <- norm(pr$mean[i])
        next
      }
      k <- function(fld) paste("PARAM_CATALOGUE", prm, fld, sep = "|")
      v[k("ipcc_default")] <- norm(pr$mean[i])
      v[k("param_type")]   <- norm(pr$param_type[i])
      # A biological zero overrides the catalogue distribution to "constant";
      # that is the resolver working, not a mismatch.
      rs <- resolve_subcat_default(sc, prm, ipcc_version = "2019_refinement")
      cat_dist <- pc$suggested_distribution[pc$parameter == prm]
      if (!is.null(rs) && identical(rs$distribution, cat_dist)) {
        v[k("suggested_distribution")] <- norm(pr$distribution[i])
        if (!is.null(pr$uncertainty_pct) && !is.na(pr$uncertainty_pct[i]))
          v[k("suggested_uncertainty_pct")] <- norm(pr$uncertainty_pct[i])
      }
    }
  }
  mm <- j$manure_management
  if (!is.null(mm) && nrow(mm)) for (i in seq_len(nrow(mm))) {
    id <- mm$mms_type[i]
    v[paste("MMS_DEFAULTS", id, "mcf_tropical", sep = "|")] <- norm(mm$MCF_pct[i])
    v[paste("MMS_DEFAULTS", id, "ef3", sep = "|")]          <- norm(mm$EF3[i])
    v[paste("MMS_FRAC_DEFAULTS_2019", id, "frac_gas", sep = "|")] <-
      norm(as.numeric(mm$Frac_GasMS_pct[i]) / 100)
    v[paste("MMS_FRAC_DEFAULTS_2019", id, "frac_leach", sep = "|")] <-
      norm(as.numeric(mm$Frac_LeachMS_pct[i]) / 100)
  }
  v
})

# --- S11: system_instructions.md -------------------------------------------
# Hand-written and the largest prompt file. Self-check #9 asserts specific
# Cfi and C values, and Step 5b asserts pct_pregnant defaults. Those are the
# numbers that can drift from the resolver, so those are what we extract.
S[["prompt_system_instructions"]] <- local({
  v <- .empty
  f <- "translator_prompts/system_instructions.md"
  if (!file.exists(f)) return(v)
  txt <- paste(readLines(file(f, encoding = "UTF-8"), warn = FALSE),
               collapse = "
")
  grab <- function(pat) {
    m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
    if (!length(m)) return(NA_character_)
    norm(sub(pat, "\\1", m, perl = TRUE))
  }
  for (sc in ANIMAL_SUBCATEGORIES) {
    x <- grab(sprintf("`%s\\.C`[^0-9]{0,40}([0-9.]+)", sc))
    if (!is.na(x)) v[paste("C_GROWTH_BY_SUBCAT", sc, "value", sep = "|")] <- x
    x <- grab(sprintf("`%s\\.Cfi`[^0-9]{0,40}([0-9.]+)", sc))
    if (!is.na(x)) v[paste("CFI_BY_SUBCAT", sc, "value", sep = "|")] <- x
  }
  # pct_pregnant block: "- `dairy_cows`, `other_cows` -> 0.85"
  for (ln in strsplit(txt, "
")[[1]]) {
    if (!grepl("pct_pregnant", txt, fixed = TRUE)) break
    m <- regmatches(ln, regexpr("([0-9]*\\.?[0-9]+)\\s*$", ln))
    if (!length(m) || !grepl("`", ln) || !grepl("→|->", ln)) next
    for (sc in names(PCT_PREGNANT_BY_SUBCAT))
      if (grepl(paste0("`", sc, "`"), ln, fixed = TRUE))
        v[paste("PCT_PREGNANT_BY_SUBCAT", sc, "value", sep = "|")] <- norm(m)
  }
  v
})

# --- S12: mapping_examples.md / questionnaire.md (vocabulary presence) -----
# Hand-written illustrative content. Checked for MMS-id vocabulary only:
# a code offered to the user that no longer exists is the failure mode here
# (questionnaire.md offered three removed parameters until 2026-09-11).
S[["prompt_vocab_files"]] <- local({
  v <- .empty
  for (f in c("translator_prompts/questionnaire.md",
              "translator_prompts/mapping_examples.md")) {
    if (!file.exists(f)) next
    txt <- paste(readLines(file(f, encoding = "UTF-8"), warn = FALSE),
                 collapse = " ")
    for (id in MMS_DEFAULTS$id)
      if (grepl(paste0("\\b", id, "\\b"), txt))
        v[paste("MMS_DEFAULTS", id, "versions", sep = "|")] <-
          MMS_DEFAULTS$versions[MMS_DEFAULTS$id == id]
  }
  v
})

# --- S13/S14: the built-in example inventories -----------------------------
# Country data by design: differences are expected and INFORMATIONAL, never
# failures. Listed so a stale value (as solid_storage EF3 0.005 was) is at
# least visible rather than invisible.
.example_surface <- function(gen) {
  v <- .empty
  d <- tryCatch(gen(), error = function(e) NULL)
  if (is.null(d)) return(v)
  for (i in seq_len(nrow(d))) {
    id <- d$mms_type[i]
    if (!id %in% MMS_DEFAULTS$id) next
    v[paste("MMS_DEFAULTS", id, "mcf_tropical", sep = "|")] <- norm(d$MCF_pct[i])
    v[paste("MMS_DEFAULTS", id, "ef3", sep = "|")]          <- norm(d$EF3[i])
  }
  v
}
S[["example_country_x"]] <- .example_surface(generate_country_x_manure)
S[["example_country_y"]] <- .example_surface(generate_country_y_manure)

# --- surface policies and SCOPE ---------------------------------------------
#
# POLICY says how hard a mismatch is. SCOPE says which cells a surface is even
# supposed to carry, so that "absent" means "should be here and isn't" rather
# than "this surface was never going to hold a GWP value". Without SCOPE the
# report drowns in false absences and stops being readable, which defeats the
# point of enumerating every cell.
POLICY <- c(prompt_param_catalogue = "MUST", prompt_template_schema = "MUST",
            xlsx_parameters = "MUST", xlsx_lists = "MUST",
            xlsx_vocab = "MUST", xlsx_manure_example = "REVIEW",
            audit_literals = "REVIEW", doc_rmd = "REVIEW",
            built_docx = "REVIEW",
            prompt_worked_example = "MUST",
            prompt_system_instructions = "MUST",
            prompt_vocab_files = "REVIEW",
            example_country_x = "INFO", example_country_y = "INFO")

SCOPE <- list(
  prompt_param_catalogue = list(
    objects = c("PARAM_CATALOGUE", "CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT")),
  prompt_template_schema = list(
    objects = c("MMS_DEFAULTS", "MMS_FRAC_DEFAULTS_2019")),
  xlsx_parameters = list(
    objects = "PARAM_CATALOGUE",
    fields  = c("ipcc_default", "suggested_uncertainty_pct",
                "suggested_distribution")),
  xlsx_lists = list(objects = "MMS_DEFAULTS"),
  xlsx_vocab = list(objects = "MMS_DEFAULTS",
                    fields = c("mcf_tropical", "mcf_tropical_dry",
                               "mcf_temperate", "mcf_boreal", "ef3", "label")),
  # The blank template pre-fills only two example MMS rows.
  xlsx_manure_example = list(objects = "MMS_FRAC_DEFAULTS_2019",
                             keys = c("pasture", "solid_storage")),
  # Deliberate spot-check subset, not full coverage.
  audit_literals = list(objects = character(0)),
  doc_rmd   = list(objects = character(0)),
  built_docx = list(objects = character(0)),
  prompt_worked_example = list(objects = character(0)),
  prompt_system_instructions = list(objects = character(0)),
  prompt_vocab_files = list(objects = character(0)),
  example_country_x = list(objects = character(0)),
  example_country_y = list(objects = character(0)))

in_scope <- function(sn, obj, key, fld) {
  sc <- SCOPE[[sn]]
  if (is.null(sc) || !length(sc$objects)) return(FALSE)
  if (!obj %in% sc$objects) return(FALSE)
  if (!is.null(sc$fields) && !fld %in% sc$fields) return(FALSE)
  if (!is.null(sc$keys)   && !key %in% sc$keys)   return(FALSE)
  TRUE
}

# ---------------------------------------------------------------------------
# 3. COMPARE
# ---------------------------------------------------------------------------
M$reference_n <- norm(M$reference)
M$rv_round <- ""; M$rv_authority <- ""
for (i in seq_len(nrow(M))) {
  r <- review_for(M$object[i], M$key[i], M$field[i])
  M$rv_round[i] <- r[["round"]]; M$rv_authority[i] <- r[["authority"]]
}

for (sn in names(S)) {
  v <- S[[sn]]
  got <- unname(v[paste(M$object, M$key, M$field, sep = "|")])
  verdict <- vapply(seq_len(nrow(M)), function(i) {
    g <- got[i]
    if (is.na(g)) return(if (POLICY[[sn]] == "MUST" &&
                             !is.na(M$reference_n[i]) &&
                             in_scope(sn, M$object[i], M$key[i], M$field[i]))
                         "absent" else "n/a")
    if (same(g, M$reference_n[i])) "MATCH" else "DIFFERS"
  }, character(1))
  allowed <- paste(M$object, M$key, M$field, sn) %in%
             paste(ALLOW$object, ALLOW$key, ALLOW$field, ALLOW$surface)
  verdict[allowed & verdict == "DIFFERS"] <- "ALLOWED"
  # On an INFO surface (the built-in example inventories) a difference is
  # country-specific data by design, not a defect. Given its own verdict so a
  # stale example value stays visible: solid_storage EF3 sat at the superseded
  # 0.005 in both examples and nothing flagged it.
  if (identical(unname(POLICY[[sn]]), "INFO"))
    verdict[verdict == "DIFFERS"] <- "INFO-DIFF"
  M[[sn]] <- verdict
  M[[paste0(sn, "_val")]] <- got
}

surf <- names(S)
M$n_differs <- rowSums(M[, surf, drop = FALSE] == "DIFFERS")
M$n_info    <- rowSums(M[, surf, drop = FALSE] == "INFO-DIFF")
M$n_match   <- rowSums(M[, surf, drop = FALSE] == "MATCH")
M$n_absent  <- rowSums(M[, surf, drop = FALSE] == "absent")

# Honest coverage accounting. Three reasons a cell has no document surface:
#   NO-VALUE  the reference is NA, so there is nothing to carry anywhere
#             (the 20 symmetric params have no lower/upper bound).
#   INTERNAL  a single-consumer R constant that by design appears in no
#             document: the per-sub-category weights feed only
#             resolve_subcat_default(), and the regional BW table feeds only
#             the QA/QC benchmark. Guarded by audit F30 and F13a instead.
#   UNCOVERED a real gap: the value IS published somewhere and nothing checks it.
INTERNAL_OBJECTS <- c("LW_BY_SUBCAT", "MW_BY_SUBCAT", "WG_BY_SUBCAT",
                      "IPCC_DEFAULTS_BY_REGION")
M$coverage <- ifelse(
  is.na(M$reference_n), "NO-VALUE",
  ifelse(rowSums(M[, surf, drop = FALSE] == "MATCH") > 0, "CHECKED",
  ifelse(M$object %in% INTERNAL_OBJECTS, "INTERNAL", "UNCOVERED")))

bad <- M[M$n_differs > 0 | M$n_absent > 0, ]
bad <- bad[order(bad$object, bad$key, bad$field), ]

# ---------------------------------------------------------------------------
# 4. REPORT
# ---------------------------------------------------------------------------
out <- c("# Defaults cross-surface matrix", "",
  sprintf("Generated %s. Reference = the R constants.", Sys.Date()), "",
  sprintf("- **%d** value cells enumerated from %d objects",
          nrow(M), length(unique(M$object))),
  sprintf("- **%d** surfaces compared: %s", length(surf),
          paste(surf, collapse = ", ")),
  sprintf("- **%d** cells carry review provenance", sum(nzchar(M$rv_round))),
  sprintf("- **%d** rows need attention (DIFFERS or unexpectedly ABSENT)",
          nrow(bad)),
  "")

if (nrow(bad)) {
  out <- c(out, "## Rows needing attention", "",
    "Work these one at a time. A row with a `review` entry was adjudicated in a numbered round: **escalate, do not silently change it.**", "",
    "| object | key | field | reference | surface | found | verdict | review |",
    "|---|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(bad))) for (sn in surf) {
    st <- bad[[sn]][i]
    if (!st %in% c("DIFFERS", "absent")) next
    out <- c(out, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |",
      bad$object[i], bad$key[i], bad$field[i], bad$reference_n[i], sn,
      bad[[paste0(sn, "_val")]][i] %||% "", st,
      if (nzchar(bad$rv_round[i]))
        paste0(bad$rv_round[i], " (", bad$rv_authority[i], ")") else ""))
  }
  out <- c(out, "")
} else out <- c(out, "## No rows need attention", "",
                "Every cell on every MUST surface matches the R constant.", "")

if (sum(M$n_info) > 0) {
  out <- c(out, "## Informational: example inventories that differ", "",
    "Country data by design, not defects. Listed so a stale example value stays visible.", "",
    "| object | key | field | default | surface | example |", "|---|---|---|---|---|---|")
  ii <- M[M$n_info > 0, ]
  for (i in seq_len(nrow(ii))) for (sn in surf)
    if (identical(ii[[sn]][i], "INFO-DIFF"))
      out <- c(out, sprintf("| %s | %s | %s | %s | %s | %s |",
        ii$object[i], ii$key[i], ii$field[i], ii$reference_n[i], sn,
        ii[[paste0(sn, "_val")]][i]))
  out <- c(out, "")
}

out <- c(out, "## Allow-list", "",
  "| object | key | field | surface | justification |", "|---|---|---|---|---|")
for (i in seq_len(nrow(ALLOW)))
  out <- c(out, sprintf("| %s | %s | %s | %s | %s |", ALLOW$object[i],
                        ALLOW$key[i], ALLOW$field[i], ALLOW$surface[i],
                        ALLOW$why[i]))

out <- c(out, "", "## Cell coverage", "",
  "| class | cells | meaning |", "|---|---|---|",
  sprintf("| CHECKED | %d | matched on at least one surface |",
          sum(M$coverage == "CHECKED")),
  sprintf("| NO-VALUE | %d | reference is NA, nothing to carry |",
          sum(M$coverage == "NO-VALUE")),
  sprintf("| INTERNAL | %d | single-consumer constant, no document surface by design |",
          sum(M$coverage == "INTERNAL")),
  sprintf("| **UNCOVERED** | **%d** | published somewhere and checked nowhere |",
          sum(M$coverage == "UNCOVERED")),
  "",
  if (sum(M$coverage == "UNCOVERED") > 0)
    paste("Uncovered:", paste(unique(paste(M$object[M$coverage == "UNCOVERED"],
          M$field[M$coverage == "UNCOVERED"])), collapse = "; "))
  else "No uncovered cells.",
  "", "## Coverage per surface", "",
  "| surface | policy | MATCH | DIFFERS | INFO | absent | n/a |",
  "|---|---|---|---|---|---|---|")
for (sn in surf)
  out <- c(out, sprintf("| %s | %s | %d | %d | %d | %d | %d |", sn, POLICY[[sn]],
    sum(M[[sn]] == "MATCH"), sum(M[[sn]] == "DIFFERS"),
    sum(M[[sn]] == "INFO-DIFF"),
    sum(M[[sn]] == "absent"), sum(M[[sn]] == "n/a")))

writeLines(out, "DEFAULTS_MATRIX.md", useBytes = TRUE)
write.csv(M[, c("object", "key", "field", "reference_n", "rv_round",
                "rv_authority", surf)],
          "DEFAULTS_MATRIX.csv", row.names = FALSE)

cat(sprintf("\n=== DEFAULTS MATRIX ===\ncells %d | surfaces %d | rows needing attention %d\n",
            nrow(M), length(surf), nrow(bad)))
for (sn in surf)
  cat(sprintf("  %-24s MATCH %4d  DIFFERS %3d  absent %3d\n", sn,
      sum(M[[sn]] == "MATCH"), sum(M[[sn]] == "DIFFERS"),
      sum(M[[sn]] == "absent")))
cat("Report: DEFAULTS_MATRIX.md\n")

if (nrow(bad) > 0 && !interactive()) quit(save = "no", status = 1L)
