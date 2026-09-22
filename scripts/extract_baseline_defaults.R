# =============================================================================
# extract_baseline_defaults.R -- dump the shipped defaults as they stood at the
# pre-September baseline
# =============================================================================
#
# WHY. reports/VALUE_CHANGES_FOR_REVIEW.md needs a "before" column that an
# external reviewer can trust. Hand-transcribing those values is exactly the
# mechanism that produced the drift this whole audit exists to remove, so the
# baseline is extracted mechanically from git instead.
#
# THE BASELINE is fbfa1bc (2026-07-10): the last commit before September and
# the last recorded shinyapps deploy, so its values are what the live app runs
# today. The only later pre-correction commit, 8be4f0f, renamed a dead object
# and added comments without touching a live value, so the two are
# value-identical and either could serve. fbfa1bc is used because it is the
# state the reviewer last saw.
#
# HOW. The baseline predates defaults/defaults_master.csv, so the values live
# in R literals. A detached git worktree gives us that tree without disturbing
# the working copy; a separate R process sources the two value-bearing files
# there and prints every constant in the master's own long format.
#
# Usage (from project root):
#   Rscript scripts/extract_baseline_defaults.R
#
# Writes defaults/baseline_defaults.csv. Re-runnable; the worktree is always
# cleaned up, including after a failure.
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

BASELINE  <- "fbfa1bc"
OUT       <- "defaults/baseline_defaults.csv"
WORKTREE  <- file.path(tempdir(), paste0("baseline-", BASELINE))

git <- function(...) {
  args <- c(...)
  out <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0)
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(out, collapse = "\n"), call. = FALSE)
  invisible(out)
}

cleanup <- function() {
  if (dir.exists(WORKTREE)) {
    try(git("worktree", "remove", "--force", shQuote(WORKTREE)), silent = TRUE)
    # If git declined (a leftover file it does not know about, common on
    # Windows), delete the tree ourselves. The prune below then clears git's
    # admin entry. Without the explicit unlink, `git worktree list` keeps
    # showing a "prunable" entry until the next run.
    unlink(WORKTREE, recursive = TRUE, force = TRUE)
  }
  try(git("worktree", "prune"), silent = TRUE)
}
# NOT on.exit(): registered at the top level of a script it does not reliably
# fire under Rscript, and the worktree survived every run while appearing to
# be cleaned up. Cleanup therefore runs explicitly at both ends: here, which
# also clears anything a previous failed run left behind, and again at the
# bottom on success.
cleanup()
message("creating worktree at ", BASELINE, " ...")
git("worktree", "add", "--detach", shQuote(WORKTREE), BASELINE)

# --- the dumper, run INSIDE the worktree in its own R process ---------------
# It must not see anything from this session: the point is to read the old
# literals, and a stray object from the current tree would silently mask one.
dumper <- file.path(WORKTREE, ".dump_baseline.R")
writeLines(c(
  'options(stringsAsFactors = FALSE)',
  # system2() gives the child this session's working directory, not the
  # script's, so without this setwd() the dumper sources the CURRENT R/ files
  # and silently reports today's values as the baseline. It failed loudly here
  # only because the current tree needs .master_wide(); a subtler drift would
  # have produced a plausible and entirely wrong "before" column.
  sprintf('setwd(%s)', deparse(normalizePath(WORKTREE, winslash = "/"))),
  'suppressMessages({',
  '  source("R/utils_ipcc_defaults.R")',
  '  source("R/utils_template.R")',
  '})',
  'rows <- list()',
  'add <- function(object, key, field, value, order) {',
  '  rows[[length(rows) + 1L]] <<- data.frame(',
  '    object = object, key = as.character(key), field = field,',
  '    value = if (length(value) == 0 || is.na(value)) NA_character_',
  '            else as.character(value),',
  '    row_order = order, stringsAsFactors = FALSE)',
  '}',
  '# PARAM_CATALOGUE: every column, so a changed unit or ipcc_ref shows too.',
  'pc <- PARAM_CATALOGUE',
  'for (i in seq_len(nrow(pc))) for (f in setdiff(names(pc), "parameter"))',
  '  add("PARAM_CATALOGUE", pc$parameter[i], f, pc[[f]][i], i)',
  'md <- MMS_DEFAULTS',
  'for (i in seq_len(nrow(md))) for (f in setdiff(names(md), "id"))',
  '  add("MMS_DEFAULTS", md$id[i], f, md[[f]][i], i)',
  'if (exists("MMS_FRAC_DEFAULTS_2019")) {',
  '  mf <- MMS_FRAC_DEFAULTS_2019',
  '  for (i in seq_len(nrow(mf))) for (f in setdiff(names(mf), "mms_type"))',
  '    add("MMS_FRAC_DEFAULTS_2019", mf$mms_type[i], f, mf[[f]][i], i)',
  '}',
  'for (nm in c("CFI_BY_SUBCAT", "C_GROWTH_BY_SUBCAT", "LW_BY_SUBCAT",',
  '             "MW_BY_SUBCAT", "WG_BY_SUBCAT", "PCT_PREGNANT_BY_SUBCAT",',
  '             "DE_BY_SUBCAT", "CP_BY_SUBCAT", "FEEDING_SITUATION_CA")) {',
  '  if (!exists(nm)) next',
  '  o <- get(nm); k <- names(o)',
  '  for (i in seq_along(k)) add(nm, k[i], "value", o[[k[i]]], i)',
  '}',
  '# YM_BY_SUBCAT did not exist at the baseline; emit nothing if absent.',
  'if (exists("YM_BY_SUBCAT")) {',
  '  y <- YM_BY_SUBCAT',
  '  for (i in seq_len(nrow(y))) for (f in setdiff(names(y), "sub_category"))',
  '    add("YM_BY_SUBCAT", y$sub_category[i], f, y[[f]][i], i)',
  '}',
  'if (exists("IPCC_DEFAULTS_BY_REGION"))',
  '  for (i in seq_len(nrow(IPCC_DEFAULTS_BY_REGION))) {',
  '    r <- IPCC_DEFAULTS_BY_REGION[i, ]',
  '    add("IPCC_DEFAULTS_BY_REGION", r$region, "parameter", r$parameter, i)',
  '    add("IPCC_DEFAULTS_BY_REGION", r$region, "default_val", r$default_val, i)',
  '  }',
  'ord <- 0L',
  'for (ar in names(GWP_VALUES)) for (g in names(GWP_VALUES[[ar]])) {',
  '  ord <- ord + 1L',
  '  add("GWP_VALUES", paste0(ar, ".", g), "value", GWP_VALUES[[ar]][[g]], ord)',
  '}',
  'M <- do.call(rbind, rows)',
  'write.csv(M, ".baseline_out.csv", row.names = FALSE, na = "<NA>")',
  'cat("BASELINE_ROWS:", nrow(M), "\n")'),
  dumper)

message("sourcing the baseline constants in a clean R process ...")
res <- suppressWarnings(system2(
  file.path(R.home("bin"), "Rscript"),
  c("--vanilla", shQuote(dumper)),
  stdout = TRUE, stderr = TRUE))
if (!any(grepl("BASELINE_ROWS:", res)))
  stop("baseline dump failed:\n", paste(res, collapse = "\n"), call. = FALSE)

B <- utils::read.csv(file.path(WORKTREE, ".baseline_out.csv"),
                     stringsAsFactors = FALSE, na.strings = "<NA>",
                     colClasses = "character")
B$baseline_commit <- BASELINE
B$baseline_date   <- "2026-07-10"

dir.create("reference", showWarnings = FALSE)
utils::write.csv(B, OUT, row.names = FALSE, na = "<NA>")

cleanup()

cat(sprintf("wrote %s: %d rows, %d objects (from %s, %s)\n",
            OUT, nrow(B), length(unique(B$object)), BASELINE, "2026-07-10"))
for (o in unique(B$object))
  cat(sprintf("  %-26s %d\n", o, sum(B$object == o)))
