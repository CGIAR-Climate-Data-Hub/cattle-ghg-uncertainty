# =============================================================================
# load_defaults.R -- build every IPCC default object from the master CSV
# =============================================================================
#
# defaults/defaults_master.csv is THE authority for every shipped default.
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

# The path is overridable ONLY so the derivation test can point a clean R
# process at a perturbed copy of the master. Nothing in the app sets it.
#
# That test exists because two objects, IPCC_DEFAULTS_BY_REGION and
# GWP_VALUES, were written to the master by the export and then kept as
# hand-written literals here, so the master's copy of them was decorative
# and the two could have drifted with nothing noticing.
# scripts/verify_defaults.R cannot catch that: it builds its row universe
# FROM the R objects, so a literal is compared against itself. Only
# changing the master and watching the object move distinguishes "reads the
# master" from "happens to agree with it". See audit check F39.
.DEFAULTS_MASTER_PATH <- Sys.getenv("GMH_DEFAULTS_MASTER",
                                    "defaults/defaults_master.csv")

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

# THE fallback value for a parameter, straight from the master.
#
# Every "what do we use when this is missing" default in the engine and the
# calc_* signatures reads this. They used to carry their own literals, and
# eight of them had drifted: the missing-row fallback gave Bo 0.10 where the
# master says 0.13 (a 2006 value superseded in June), Cfi 0.322 where the
# catalogue holds the lactating 0.386, EF4 0.010 where the catalogue holds
# the wet-climate 0.014, and BW/Milk/Fat/DE were left behind by the
# low-productivity change.
#
# Two of those sat on the verify_defaults allow-list, justified as "bites
# only when the row is absent entirely". That is exactly the gap-fill path,
# so the allow-list was excusing the case it should have flagged.
#
# NA in the catalogue means the user must supply it (only N), so 0 is
# returned: no animals rather than an invented herd.
.cat_default <- function(parameter) {
  v <- PARAM_CATALOGUE$ipcc_default[PARAM_CATALOGUE$parameter == parameter]
  # An unknown parameter used to return 0 here, silently. That turns a typo
  # or a quantity with no catalogue row (Frac_GASMS, Frac_LEACH_H) into a
  # zero emission factor rather than an error, which is the worst available
  # outcome. Fail instead; callers for those two pass explicit literals.
  if (!length(v))
    stop("no PARAM_CATALOGUE row for '", parameter,
         "'; pass an explicit default at the call site and say why",
         call. = FALSE)
  # N is the one catalogue parameter with no published default: IPCC has no
  # herd size to offer. 0 head is the safe reading.
  if (is.na(v[1])) 0 else as.numeric(v[1])
}

# Pull a named vector (the *_BY_SUBCAT style lists) as a list, in order.
.master_list <- function(object) {
  d <- .defaults_master[.defaults_master$object == object &
                        .defaults_master$field == "value", ]
  if (!nrow(d)) stop("defaults master has no rows for ", object, call. = FALSE)
  d <- d[order(d$row_order), ]
  as.list(stats::setNames(.master_coerce(d$value), d$key))
}
