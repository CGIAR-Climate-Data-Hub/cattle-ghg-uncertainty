# =============================================================================
# load_defaults.R -- build every IPCC default object from the master CSV
# =============================================================================
#
# reference/defaults_master.csv is THE authority for every shipped default.
# This file turns it into the R objects the rest of the app already expects.
#
# WHY. The defaults used to live as literal vectors in two R files, and copies
# of them accumulated in the Excel template, three translator prompt files,
# both published guides, the audit's own literals and the example inventories.
# Corrections reached some copies and not others: the June 2026 MMS fixes
# never reached the translator prompt, the template's example column drifted
# three separate times, and a wrong dry_lot MCF survived from the initial
# commit. One authority removes the class of problem rather than the
# instances.
#
# CONTRACT. Object NAMES, COLUMN NAMES, COLUMN ORDER, ROW ORDER and TYPES are
# identical to the literals they replaced, so none of the ~140 call sites
# across R/ had to change. scripts/verify_defaults.R re-checks every value
# against every surface, and audit check F32 asserts the round trip.
#
# ROW ORDER IS LOAD-BEARING for PARAM_CATALOGUE: the translator writer emits
# one block of rows per sub-category in exactly catalogue order. The master
# carries an explicit row_order column for that reason; do not sort by name.
#
# Sourced early: app.R and every script source R/ alphabetically, and
# "load_defaults.R" sorts before "utils_*.R", so the objects exist before
# anything uses them.
# =============================================================================

.DEFAULTS_MASTER_PATH <- "reference/defaults_master.csv"

.defaults_master <- local({
  p <- .DEFAULTS_MASTER_PATH
  if (!file.exists(p)) {
    # Try one level up: scripts/ sometimes runs before setwd("..").
    alt <- file.path("..", p)
    if (file.exists(alt)) p <- alt else
      stop("defaults master not found at ", .DEFAULTS_MASTER_PATH,
           ". Every IPCC default in the app is read from that file; ",
           "the app cannot start without it.", call. = FALSE)
  }
  # na.strings is the sentinel, NOT "": an empty cell is a genuine empty
  # string (four parameters have no IPCC reference) and must stay one.
  m <- utils::read.csv(p, stringsAsFactors = FALSE, na.strings = "<NA>",
                       colClasses = "character", encoding = "UTF-8")
  need <- c("object", "key", "field", "value", "row_order")
  miss <- setdiff(need, names(m))
  if (length(miss))
    stop("defaults master is missing column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  m$row_order <- as.integer(m$row_order)
  m
})

# Pull one object out of the master as a wide data.frame, preserving the
# recorded row order and coercing any column that is wholly numeric.
.master_wide <- function(object, key_name) {
  d <- .defaults_master[.defaults_master$object == object, ]
  if (!nrow(d)) stop("defaults master has no rows for ", object, call. = FALSE)
  keys   <- unique(d$key[order(d$row_order)])
  fields <- unique(d$field)
  out <- data.frame(k = keys, stringsAsFactors = FALSE)
  names(out) <- key_name
  for (f in fields) {
    sub <- d[d$field == f, ]
    out[[f]] <- .master_coerce(sub$value[match(keys, sub$key)])
  }
  out
}

# Restore the original column type. A CSV has only text, so this must infer:
# logical first (user_reducible drives the tornado colouring and would break
# as the string "TRUE"), then numeric, then leave as character. Inference is
# all-or-nothing per column so a single stray value cannot silently retype it.
.master_coerce <- function(v) {
  nonmiss <- v[!is.na(v)]
  if (length(nonmiss) && all(nonmiss %in% c("TRUE", "FALSE")))
    return(as.logical(v))
  n <- suppressWarnings(as.numeric(v))
  if (all(is.na(n) == is.na(v))) n else v
}

# Pull a named vector (the *_BY_SUBCAT style lists) as a list, in order.
.master_list <- function(object) {
  d <- .defaults_master[.defaults_master$object == object &
                        .defaults_master$field == "value", ]
  if (!nrow(d)) stop("defaults master has no rows for ", object, call. = FALSE)
  d <- d[order(d$row_order), ]
  as.list(stats::setNames(.master_coerce(d$value), d$key))
}
