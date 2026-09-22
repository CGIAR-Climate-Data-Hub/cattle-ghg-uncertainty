# =============================================================================
# sweep_param_values.R -- every number next to every parameter, in every file
# =============================================================================
#
# scripts/verify_defaults.R is MASTER-FIRST: it takes the 291 known values and
# asks each of 15 known surfaces for them. That makes it exhaustive over what
# it already knows about and blind to everything else. Every defect found by
# hand this month lived in the blind spot: a literal in the engine, a stale
# number in a guide table, a parameter whose name contains an underscore and
# so never matched an extractor's pattern.
#
# This script is DISCOVERY-FIRST and runs the other way round. It reads every
# tracked file, whatever its format, finds every mention of every parameter,
# collects the numbers sitting next to it, and asks whether the master's value
# is among them. It knows nothing about surfaces, so it cannot have a blind
# spot shaped like one.
#
# It trades precision for recall on purpose. A line can mention a parameter
# and carry numbers that have nothing to do with its value (a page reference,
# a line number, a range, a different parameter). So the output is a triage
# list, not a verdict, and it is sorted so the high-precision signal comes
# first:
#
#   STALE    the line mentions P and carries P's JULY value, which is no
#            longer P's value. Almost always a real defect.
#   MISSING  the line mentions P and carries numbers, none of which is P's
#            value. Usually prose; sometimes a defect.
#   OK       P's current value is among the numbers on the line.
#
# Usage:
#   Rscript scripts/sweep_param_values.R            # report
#   Rscript scripts/sweep_param_values.R --all      # include OK lines
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")
ARGS <- commandArgs(TRUE)
SHOW_ALL <- "--all" %in% ARGS

rd <- function(p) utils::read.csv(p, stringsAsFactors = FALSE,
                                  na.strings = "<NA>", colClasses = "character")
M <- rd("defaults/defaults_master.csv")
B <- if (file.exists("defaults/baseline_defaults.csv"))
       rd("defaults/baseline_defaults.csv") else M[0, ]
num <- function(v) suppressWarnings(as.numeric(v))
V <- M[!is.na(num(M$value)) & M$ipcc_verdict != "META", ]

k3 <- function(d) paste(d$object, d$key, d$field, sep = "\r")
B$k <- k3(B)
V$k <- k3(V)
V$july <- num(B$value[match(V$k, B$k)])
V$now  <- num(V$value)

# --- which word in a file means "this value" --------------------------------
# For a catalogue parameter it is the parameter name. For a per-sub-category
# or per-system value it is the KEY (dairy_cows, solid_storage), because that
# is what distinguishes one of the nine from another.
PARAM_OF_OBJECT <- c(
  CFI_BY_SUBCAT = "Cfi", C_GROWTH_BY_SUBCAT = "C", LW_BY_SUBCAT = "BW",
  MW_BY_SUBCAT = "MW", WG_BY_SUBCAT = "WG", DE_BY_SUBCAT = "DE",
  CP_BY_SUBCAT = "CP", YM_BY_SUBCAT = "Ym",
  PCT_PREGNANT_BY_SUBCAT = "pct_pregnant")
ALIASES <- list(
  BW = c("live_weight", "W"), N = "cattle_pop", WG = "weight_gain",
  MW = "mature_weight", Milk = "milk_yield", Fat = "milk_fat",
  DE = "DE_pct", CP = "CP_pct", Ym = "Ym_pct", ASH = "ash",
  C = "C_growth", MilkPR = "protein_milk",
  pct_pregnant = c("pct_calving", "pct_lactating"),
  Frac_GASM_PRP = "Frac_GasPRP", Frac_LEACH_PRP = "Frac_LeachPRP")

tokens_for <- function(object, key) {
  if (object == "PARAM_CATALOGUE") return(unique(c(key, ALIASES[[key]])))
  if (object %in% names(PARAM_OF_OBJECT)) return(key)
  if (object == "GWP_VALUES") return(sub("[.].*$", "", key))
  key                                    # MMS ids, region names
}
V$tokens <- Map(tokens_for, V$object, V$key)

# --- read anything ----------------------------------------------------------
strip_xml <- function(x) {
  x <- gsub("<[^>]*>", " ", paste(x, collapse = " "))
  gsub("[[:space:]]+", " ", x)
}
unz_text <- function(path, members) {
  out <- character(0)
  for (m in members) {
    con <- try(unz(path, m, open = "rb"), silent = TRUE)
    if (inherits(con, "try-error")) next
    raw <- try(readLines(con, warn = FALSE, encoding = "UTF-8"), silent = TRUE)
    close(con)
    if (!inherits(raw, "try-error")) out <- c(out, strip_xml(raw))
  }
  out
}
zip_members <- function(path, pat) {
  l <- try(utils::unzip(path, list = TRUE), silent = TRUE)
  if (inherits(l, "try-error")) return(character(0))
  grep(pat, l$Name, value = TRUE)
}

read_any <- function(f) {
  ext <- tolower(tools::file_ext(f))
  if (ext %in% c("png", "webp", "rds", "jpg", "jpeg", "gif", "ico")) return(NULL)
  if (ext == "docx") return(unz_text(f, zip_members(f, "^word/document[.]xml$")))
  if (ext == "xlsx") return(unz_text(f, zip_members(f, "^xl/(sharedStrings[.]xml|worksheets/.*[.]xml)$")))
  if (ext == "zip") {
    mem <- zip_members(f, "[.](md|txt|Rmd|csv)$")
    return(unz_text(f, mem))
  }
  if (ext == "pdf") {
    if (nzchar(Sys.which("pdftotext"))) {
      tmp <- tempfile(fileext = ".txt")
      on.exit(unlink(tmp), add = TRUE)
      ok <- suppressWarnings(system2("pdftotext", c("-q", shQuote(f), shQuote(tmp))))
      if (identical(ok, 0L) && file.exists(tmp))
        return(readLines(tmp, warn = FALSE))
    }
    return(NULL)
  }
  r <- try(readLines(f, warn = FALSE), silent = TRUE)
  if (inherits(r, "try-error")) return(NULL)
  # LaTeX writes an underscore as "\_", so "pct_pregnant" never matches
  # "pct\_pregnant" and every parameter with an underscore in its name is
  # invisible in .Rmd and .tex. Unwrap \texttt{} and drop the backslashes.
  if (ext %in% c("rmd", "tex"))
    r <- gsub("\\\\", "", gsub("\\\\texttt\\{([^}]*)\\}", "\\1", r))
  r
}

# --- the sweep --------------------------------------------------------------
FILES <- system2("git", c("ls-files"), stdout = TRUE)
FILES <- FILES[file.exists(FILES)]
# Generated artefacts a user actually receives, even when not tracked.
FILES <- unique(c(FILES, Sys.glob("*.csv"), Sys.glob("*.md")))
# The master and its own generated reports are the authority, not a surface;
# checking them against themselves proves nothing and buries the real signal.
SELF <- c("defaults/defaults_master.csv", "defaults/baseline_defaults.csv",
          "reports/ALL_VALUES.md", "reports/ALL_VALUES.csv",
          "reports/VALUE_CHANGES_FOR_REVIEW.md",
          "reports/VALUE_CHANGES_FOR_REVIEW.csv",
          "defaults/DEFAULTS_MASTER.md", "defaults/provenance_register.md",
          "reports/DEFAULTS_MATRIX.csv", "reports/DEFAULTS_MATRIX.md", "reports/AUDIT_REPORT.md")
FILES <- setdiff(FILES, SELF)

NUMPAT <- "[0-9]+(?:[.][0-9]+)?"
rows <- list()
cache <- new.env(parent = emptyenv())

for (f in FILES) {
  txt <- tryCatch(read_any(f), error = function(e) NULL)
  if (is.null(txt) || !length(txt)) next
  for (i in seq_len(nrow(V))) {
    toks <- V$tokens[[i]]
    pat <- paste0("(?<![A-Za-z0-9_])(", paste(gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", toks),
                                              collapse = "|"), ")(?![A-Za-z0-9_])")
    hit <- grep(pat, txt, perl = TRUE)
    if (!length(hit)) next
    for (h in hit) {
      line <- txt[h]
      ns <- num(unlist(regmatches(line, gregexpr(NUMPAT, line, perl = TRUE))))
      ns <- ns[!is.na(ns)]
      if (!length(ns)) next
      has_now  <- any(abs(ns - V$now[i]) < 1e-9)
      has_july <- !is.na(V$july[i]) && abs(V$july[i] - V$now[i]) > 1e-9 &&
                  any(abs(ns - V$july[i]) < 1e-9)
      status <- if (has_july && !has_now) "STALE" else
                if (has_now) "OK" else "MISSING"
      if (status == "OK" && !SHOW_ALL) next
      rows[[length(rows) + 1]] <- data.frame(
        status = status, file = f, line_no = h,
        object = V$object[i], key = V$key[i], field = V$field[i],
        now = V$now[i], july = V$july[i],
        found = paste(unique(ns), collapse = " "),
        text = substr(gsub("[[:space:]]+", " ", line), 1, 200),
        stringsAsFactors = FALSE)
    }
  }
}

R <- if (length(rows)) do.call(rbind, rows) else
       data.frame(status = character(0))
if (!nrow(R)) { cat("no parameter mentions found -- check the file list\n"); quit(save = "no") }

ord <- c(STALE = 1, MISSING = 2, OK = 3)
R <- R[order(ord[R$status], R$file, R$object, R$key), ]
utils::write.csv(R, "reports/PARAM_SWEEP.csv", row.names = FALSE)

cat(sprintf("swept %d files against %d values\n", length(FILES), nrow(V)))
cat(sprintf("  STALE   %4d  (line names the parameter and carries its OLD value)\n",
            sum(R$status == "STALE")))
cat(sprintf("  MISSING %4d  (line names the parameter, has numbers, none is the current value)\n",
            sum(R$status == "MISSING")))
if (SHOW_ALL) cat(sprintf("  OK      %4d\n", sum(R$status == "OK")))
cat("wrote reports/PARAM_SWEEP.csv\n\n")

if (any(R$status == "STALE")) {
  cat("=== STALE ===\n")
  s <- R[R$status == "STALE", ]
  for (j in seq_len(nrow(s)))
    cat(sprintf("%s:%d  %s/%s  now=%s july=%s\n    %s\n",
                s$file[j], s$line_no[j], s$object[j], s$key[j],
                format(s$now[j]), format(s$july[j]), s$text[j]))
}
