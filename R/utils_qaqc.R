# QA/QC checks for uploaded parameter specifications
# run_qaqc() returns a tidy data.frame: one row per (group x parameter x check)

# C1: IPCC-aligned names; legacy names auto-renamed by parse_uploaded_template.
# Andreas 2026-05-27: EF3_S / Frac_GASMS / Frac_LEACH_H removed from the
# Parameters sheet (now specified per-MMS in Manure_Management), so they are
# no longer Parameters-tab QA/QC targets. Kept as legacy aliases tolerated on
# upload but not benchmarked here.
## Andreas 28/5/26 #3 (asymmetric-bounds rule fix): EF4 and EF5 dropped.
## The IPCC 2019 R Vol.4 Ch.11 Table 11.3 published ranges for these two
## parameters are roughly symmetric (EF4 ratio = 1.0, EF5 ratio = 0.82),
## so the `ratio < 1.5 → warn` rule was firing against IPCC's own values.
## EF3_PRP / Frac_GASM_PRP / Frac_LEACH_PRP DO have right-skewed ranges in
## Table 11.3 and stay in the list.
ASYMMETRIC_PARAMS <- c("EF3_PRP",
                        "Frac_GASM_PRP", "Frac_LEACH_PRP")
FRACTION_PARAMS   <- c("pct_pregnant", "ASH", "UE",
                        "Frac_GASM_PRP", "Frac_LEACH_PRP")

## Andreas 28/5/26 #3: only parameters with a defensible direct IPCC table
## lookup get the benchmark_deviation check. BW is the only one we currently
## key off the continental Annex Tables 10A.1 (dairy cows) / 10A.2 (other
## cattle) / 10A.3 (buffalo). Milk / DE / Ym / Bo / MW previously fired
## warnings citing values that came from heuristic mid-points, not the
## published IPCC tables — see the block comment over IPCC_DEFAULTS_BY_REGION
## in utils_ipcc_defaults.R.
BENCHMARK_ELIGIBLE_PARAMS <- c("BW")

# ---------------------------------------------------------------------------
# BENCHMARK REFERENCE
#
# Review round 7 item 3 was "~20 spurious QA warnings", because "the
# explanation cited IPCC default values that I could not find in the IPCC
# guidelines". The fix then narrowed the check to BW. It did not fix BW.
#
# Every sub-category was still measured against ONE adult number, so the tool
# warned about values it had supplied itself (its own calf default of 60 kg
# came out 78% from the 275 benchmark), and warned a compiler who entered
# IPCC's own Annex 10A.2 Africa weights: Calves on forage 82 and Mature Males
# 540 both flagged. And the message for a dairy herd cited Table 10A.1 while
# comparing against 275, a number that appears nowhere in 10A.1. That is the
# round 7 complaint verbatim, still live on the one parameter that survived.
#
# So: a recognised sub-category is benchmarked against its OWN resolved
# default, which is Annex 10A.2 row by row and citable. Only an unrecognised
# one falls back to the continental benchmark, which now carries a real dairy
# value instead of branching the wording alone.
#
# The name matching below is FUZZY, and is confined to this file on purpose.
# A guessed animal class is acceptable for deciding whether to show a warning
# and is not acceptable for choosing a number that enters an emission
# estimate. resolve_subcat_default() takes exact keys and keeps it that way.
.BENCH_SUBCAT_SYNONYMS <- c(
  # legacy five-term vocabulary and common free text
  cow = "other_cows", cows = "other_cows",
  dairycow = "dairy_cows", dairycows = "dairy_cows", dairy = "dairy_cows",
  lactatingcows = "dairy_cows", milkingcows = "dairy_cows",
  othercow = "other_cows", othercows = "other_cows",
  drycows = "other_cows", suckler = "other_cows", sucklercows = "other_cows",
  heifer = "heifers", replacementheifers = "heifers",
  bull = "bulls", adultmales = "bulls", maturemales = "bulls",
  breedingbulls = "bulls",
  ox = "oxen", draught = "oxen", draft = "oxen", draftbullocks = "oxen",
  draughtcattle = "oxen", bullocks = "oxen",
  steer = "growing_males", steers = "growing_males",
  growingmales = "growing_males", growingreplacement = "growing_males",
  calf = "calves_female", calves = "calves_female",
  calvesonforage = "calves_female",
  feedlot = "feedlot_cattle", feedlotcattle = "feedlot_cattle")

.bench_subcat <- function(sub_category, cattle_type = "") {
  if (is.null(sub_category) || is.na(sub_category)) return(NA_character_)
  k <- tolower(trimws(as.character(sub_category)))
  if (k %in% ANIMAL_SUBCATEGORIES) return(k)
  k2 <- gsub("[^a-z0-9]", "", k)
  if (k2 %in% gsub("[^a-z0-9]", "", ANIMAL_SUBCATEGORIES))
    return(ANIMAL_SUBCATEGORIES[gsub("[^a-z0-9]", "", ANIMAL_SUBCATEGORIES) == k2][1])
  # [[ ]] on a named character vector ERRORS for an absent name rather than
  # returning NULL, and an unrecognised sub-category is the common case.
  if (!k2 %in% names(.BENCH_SUBCAT_SYNONYMS)) return(NA_character_)
  hit <- unname(.BENCH_SUBCAT_SYNONYMS[[k2]])
  # "cows" alone is the one genuinely ambiguous term; cattle_type settles it.
  if (hit == "other_cows" && grepl("dairy", tolower(cattle_type))) hit <- "dairy_cows"
  hit
}

# Returns the value to benchmark against and a citation a reader can look up.
.bench_reference <- function(parameter, sub_category, cattle_type, region) {
  sc <- .bench_subcat(sub_category, cattle_type)
  if (!is.na(sc)) {
    v <- tryCatch(resolve_subcat_default(sc, parameter)$value,
                  error = function(e) NA_real_)
    if (!is.na(v))
      return(list(value = as.numeric(v), source = sprintf(
        "the tool's IPCC default for sub-category '%s' (Vol.4 Ch.10 Annex Table 10A.1/10A.2, Africa, low productivity)", sc)))
  }
  # See .is_dairy_type(): grepl("dairy", "non_dairy") is TRUE, so this
  # benchmark was comparing non-dairy herds against the dairy column.
  is_dairy <- .is_dairy_type(cattle_type)
  reg <- if (is.null(region) || is.na(region)) "global" else tolower(trimws(region))
  if (!reg %in% IPCC_DEFAULTS_BY_REGION$region) reg <- "global"
  row <- IPCC_DEFAULTS_BY_REGION[IPCC_DEFAULTS_BY_REGION$region == reg &
                                 IPCC_DEFAULTS_BY_REGION$parameter == parameter, ,
                                 drop = FALSE]
  if (!nrow(row)) return(list(value = NA_real_, source = ""))
  if (is_dairy && "default_val_dairy" %in% names(row) &&
      !is.na(row$default_val_dairy[1]))
    return(list(value = as.numeric(row$default_val_dairy[1]), source = sprintf(
      "IPCC Vol.4 Ch.10 Annex Table 10A.1 (dairy cattle) for region '%s'", reg)))
  list(value = as.numeric(row$default_val[1]), source = sprintf(
    "IPCC Vol.4 Ch.10 Annex Table 10A.2 (non-dairy cattle) for region '%s'", reg))
}

# IPCC alignment audit (2026-05): for parameters whose IPCC default depends
# on a contextual choice the inventory compiler should make (climate zone,
# production system, animal class), the auto-fill notification appends an
# explicit hint so users know to review the value rather than accept it.
CONTEXT_DEPENDENT_HINTS <- list(
  EF3_PRP        = "DEFAULT IS THE 2019R WET-CLIMATE VALUE (0.006). Vol.4 Ch.11 Table 11.1 also gives 0.002 for dry climates and 0.004 aggregated across both. A dry-climate inventory that keeps 0.006 overstates direct pasture N2O threefold. Set the value that matches your country's climate.",
  EF4            = "DEFAULT IS THE 2019R WET-CLIMATE VALUE (0.014). Vol.4 Ch.11 Table 11.3 also gives 0.005 (dry) and 0.010 aggregated across both. A dry-climate inventory that keeps 0.014 overstates indirect N2O from deposition almost threefold. Set the value that matches your country's climate.",
  Frac_LEACH_PRP = "DEFAULT IS THE 2019R WET-CLIMATE VALUE (0.24). In dry climates the IPCC default is 0. Vol.4 Ch.11 Table 11.3.",
  Bo             = "DEFAULT IS THE 2019R 'OTHER REGIONS, LOW PRODUCTIVITY' CATTLE VALUE (0.13). For intensive dairy in North America / Western Europe, Vol.4 Ch.10 Table 10.16(a) gives 0.24; consult the table for your production system.",
  MCF            = "DEFAULT IS PER-MMS x CLIMATE ZONE. Pick the row that matches BOTH your manure-management system AND your climate zone (Vol.4 Ch.10 Table 10.17). Tropical lagoon MCF (80%) differs sharply from temperate solid storage (4%).",
  Ym             = "DEFAULT IS 6.5% (Vol.4 Ch.10 Table 10.12, LOW-PRODUCING DAIRY COWS; footnote 4 restricts the dairy rows to lactating animals). The template now fills this per sub-category: 7.0 for non-dairy and multi-purpose cattle on >75% forage, 4.0 for feedlot under the 2019 Refinement, and 6.5 / 3.0 respectively under 2006. Other rows: high-DE dairy = 5.7-6.0%. Pick the row that matches your diet quality and animal class.",
  Cfi            = "DEFAULT IS THE LACTATING-COW VALUE (0.386, Vol.4 Ch.10 Table 10.4). For non-lactating cattle/buffalo = 0.322; for bulls = 0.370. Pick the row that matches your sub-category.",
  Ca             = "DEFAULT IS THE PASTURE-FLAT VALUE (0.17, Vol.4 Ch.10 Table 10.5). For stall-fed = 0; for hilly grazing = 0.36. Pick the row that matches the feeding situation."
)

# Cross-sheet sub-category-key reconciliation. The Parameters sheet and
# Manure_Management sheet must share the same compound key (cattle_type ||
# aggregation_level || sub_category) for the simulation to find the per-MMS
# allocation for each animal sub-category. If they disagree by a typo (e.g.
# "DINT_heif" vs "DINT_heifer"), the prior behaviour was a silent fallback to
# a default 70/30 pasture/solid_storage split, producing materially wrong
# direct/indirect manure-N2O numbers (Andreas test-run 28/5/26).
#
# This helper attempts a single round of unambiguous fuzzy matching: within
# the same cattle_type + aggregation_level, look for a Manure_Management
# sub_category that is either case-insensitively equal or within
# Levenshtein distance 2 of the Parameters sub_category. If exactly ONE
# candidate matches, surface it as a `warn` (so the user can verify on the
# QAQC tab) and the simulation observer rewrites the lookup. If 0 or >1
# candidates match, surface it as `fail` so the run is blocked.
resolve_sub_category_matches <- function(param_specs, manure_data) {
  empty_issues <- data.frame(
    group = character(), parameter = character(), check = character(),
    status = character(), message = character(), stringsAsFactors = FALSE)

  need_cols <- c("cattle_type", "aggregation_level", "sub_category")
  if (is.null(param_specs) || nrow(param_specs) == 0 ||
      !all(need_cols %in% names(param_specs))) {
    return(list(matched = character(), issues = empty_issues))
  }

  mk_key <- function(df) {
    sub <- if ("sub_category" %in% names(df)) df$sub_category else rep("", nrow(df))
    paste(df$cattle_type, df$aggregation_level, sub, sep = "||")
  }
  p_keys <- unique(mk_key(param_specs))

  have_manure <- !is.null(manure_data) && nrow(manure_data) > 0 &&
                  all(need_cols %in% names(manure_data))
  m_keys <- if (have_manure) unique(mk_key(manure_data)) else character()

  matched <- setNames(p_keys, p_keys)
  issues  <- list()

  add_issue <- function(grp, chk, sta, msg) {
    issues[[length(issues) + 1L]] <<- data.frame(
      group = grp, parameter = "", check = chk, status = sta,
      message = msg, stringsAsFactors = FALSE)
  }

  exact      <- intersect(p_keys, m_keys)
  to_resolve <- setdiff(p_keys, exact)

  if (length(to_resolve) > 0 && !have_manure) {
    add_issue("(template)", "sub_category_no_mms_sheet", "info",
              t("qa_msg_no_mms"))
    return(list(matched = matched,
                issues  = do.call(rbind, issues) %||% empty_issues))
  }

  for (p_key in to_resolve) {
    parts <- strsplit(p_key, "||", fixed = TRUE)[[1]]
    if (length(parts) < 3) next
    p_cattle <- parts[1]; p_agg <- parts[2]; p_sub <- parts[3]
    grp_label <- sprintf("%s / %s / %s", p_cattle, p_agg, p_sub)

    same_group <- m_keys[vapply(strsplit(m_keys, "||", fixed = TRUE),
                                function(x) length(x) >= 3 &&
                                            x[1] == p_cattle &&
                                            x[2] == p_agg,
                                logical(1))]
    if (length(same_group) == 0) {
      add_issue(grp_label, "sub_category_no_match", "warn",
                qa_msg("sub_no_match", p_sub, p_cattle, p_agg))
      next
    }

    m_subs   <- vapply(strsplit(same_group, "||", fixed = TRUE),
                       function(x) x[3], character(1))
    ci_equal <- tolower(m_subs) == tolower(p_sub)
    dists    <- as.integer(adist(p_sub, m_subs))
    near     <- !is.na(dists) & dists <= 2L
    is_cand  <- ci_equal | near
    candidates <- same_group[is_cand]

    if (length(candidates) == 1L) {
      matched[p_key] <- candidates[1]
      cand_sub <- strsplit(candidates[1], "||", fixed = TRUE)[[1]][3]
      min_d <- min(dists[is_cand], na.rm = TRUE)
      add_issue(grp_label, "sub_category_auto_match", "warn",
                qa_msg("sub_auto_match", p_sub, cand_sub, min_d))
    } else if (length(candidates) > 1L) {
      cand_subs <- vapply(strsplit(candidates, "||", fixed = TRUE),
                          function(x) x[3], character(1))
      add_issue(grp_label, "sub_category_ambiguous", "fail",
                qa_msg("sub_ambiguous",
                       p_sub,
                       paste(sprintf("'%s'", cand_subs), collapse = ", ")))
    } else {
      add_issue(grp_label, "sub_category_no_match", "warn",
                qa_msg("sub_no_match_listed",
                       p_sub, p_cattle, p_agg,
                       paste(sprintf("'%s'", m_subs), collapse = ", ")))
    }
  }

  list(matched = matched,
       issues  = if (length(issues) > 0) do.call(rbind, issues) else empty_issues)
}

run_qaqc <- function(param_specs, catalogue = PARAM_CATALOGUE, region = "global",
                     manure_data = NULL) {
  ps <- param_specs

  # Build reference lookup from catalogue
  ref <- catalogue[, c("parameter", "ipcc_default", "suggested_lower_bound",
                        "suggested_upper_bound", "param_tier",
                        "unit", "ipcc_ref")]
  # Rename catalogue's unit/ipcc_ref to avoid clobbering values already on ps
  names(ref)[names(ref) == "unit"]     <- "unit_cat"
  names(ref)[names(ref) == "ipcc_ref"] <- "ipcc_ref_cat"
  ps <- merge(ps, ref, by = "parameter", all.x = TRUE, sort = FALSE)

  # G2: override ipcc_default with region-specific value where available.
  # Cattle-type aware for the same reason as .bench_reference() above: the
  # table has a dairy column and a non-dairy column, and handing every row the
  # non-dairy one made a dairy herd look wrong against its own benchmark.
  if (exists("get_regional_default")) {
    ct_col <- if ("cattle_type" %in% names(ps)) ps$cattle_type else NULL
    for (i in seq_len(nrow(ps))) {
      reg_val <- get_regional_default(ps$parameter[i], region,
                                      cattle_type = if (is.null(ct_col)) NULL else ct_col[i])
      if (!is.na(reg_val)) ps$ipcc_default[i] <- reg_val
    }
  }

  # Optional group label for multi-group uploads
  has_group_cols <- all(c("cattle_type", "sub_category") %in% names(ps))
  if (has_group_cols) {
    ps$group <- paste(ps$cattle_type, ps$sub_category, sep = " / ")
  } else {
    ps$group <- ps$parameter
  }

  rows <- vector("list", nrow(ps) * 6L)
  k <- 0L

  add <- function(grp, par, chk, sta, msg) {
    k <<- k + 1L
    rows[[k]] <<- list(group = grp, parameter = par, check = chk,
                       status = sta, message = msg)
  }

  for (i in seq_len(nrow(ps))) {
    p   <- ps$parameter[i]
    grp <- ps$group[i]
    mu  <- ps$mean[i]
    lo  <- ps$lower[i]
    hi  <- ps$upper[i]
    d   <- if ("distribution" %in% names(ps)) ps$distribution[i] else NA_character_
    ipcc_def <- ps$ipcc_default[i]

    # ------------------------------------------------------------------
    # Check 1: bounds order — lower < mean < upper
    # ------------------------------------------------------------------
    is_constant <- !is.na(d) && d %in% c("constant", "const")
    # Zero-mean parameters (hours=0 when no work, weight_gain=0 for adults, etc.)
    # are degenerate constants — pass silently rather than flagging as failure.
    is_zero_mean <- !is.na(mu) && mu == 0 && !is.na(lo) && lo == 0 &&
                    !is.na(hi) && hi == 0
    if (!is_constant && !is_zero_mean && !is.na(lo) && !is.na(hi) && !is.na(mu)) {
      if (lo > mu) {
        add(grp, p, "bounds_order", "fail",
            qa_msg("bounds_order_fail_lo", lo, mu))
      } else if (mu > hi) {
        add(grp, p, "bounds_order", "fail",
            qa_msg("bounds_order_fail_hi", mu, hi))
      } else {
        add(grp, p, "bounds_order", "pass", t("qa_msg_bounds_order_pass"))
      }
    } else if (is_zero_mean) {
      add(grp, p, "bounds_order", "pass", t("qa_msg_bounds_order_zero"))
    }

    # ------------------------------------------------------------------
    # Check 2: non-negative lower bound
    # ------------------------------------------------------------------
    if (!is.na(lo)) {
      if (lo < 0) {
        add(grp, p, "non_negative", "warn",
            qa_msg("nonneg_warn", lo))
      } else {
        add(grp, p, "non_negative", "pass", t("qa_msg_nonneg_pass"))
      }
    }

    # ------------------------------------------------------------------
    # Check 3: known range constraints
    # ------------------------------------------------------------------
    if (!is.na(mu)) {
      if (p == "DE_pct") {
        if (mu < 1 || mu > 100) {
          add(grp, p, "range_check", "fail",
              qa_msg("range_de_fail", mu))
        } else {
          add(grp, p, "range_check", "pass",
              qa_msg("range_de_pass", mu))
        }
      }
      if (p == "Ym_pct") {
        if (mu < 1 || mu > 15) {
          add(grp, p, "range_check", "warn",
              qa_msg("range_ym_warn", mu))
        } else {
          add(grp, p, "range_check", "pass",
              qa_msg("range_ym_pass", mu))
        }
      }
      if (p %in% FRACTION_PARAMS) {
        if (mu < 0 || mu > 1) {
          add(grp, p, "range_check", "fail",
              qa_msg("frac_fail", p, mu))
        } else {
          add(grp, p, "range_check", "pass",
              qa_msg("frac_pass", p, mu))
        }
      }
    }

    # ------------------------------------------------------------------
    # Check 4: distribution suitability
    # ------------------------------------------------------------------
    if (!is.na(d) && !is.na(mu)) {
      if (d == "beta") {
        if (mu <= 0 || mu >= 1) {
          add(grp, p, "dist_suitability", "fail",
              qa_msg("beta_mean_fail", mu))
        } else if (!is.na(lo) && !is.na(hi) && (lo < 0 || hi > 1)) {
          add(grp, p, "dist_suitability", "fail",
              qa_msg("beta_bounds_fail", lo, hi))
        } else {
          add(grp, p, "dist_suitability", "pass", t("qa_msg_beta_pass"))
        }
      } else if (d == "lognormal") {
        if (mu <= 0) {
          add(grp, p, "dist_suitability", "fail",
              qa_msg("lognorm_fail", mu))
        } else {
          add(grp, p, "dist_suitability", "pass", t("qa_msg_lognorm_pass"))
        }
      } else if (d == "tnorm_0_1") {
        if (!is.na(lo) && !is.na(hi) && (lo < 0 || hi > 1)) {
          add(grp, p, "dist_suitability", "warn",
              qa_msg("tnorm_warn", lo, hi))
        } else {
          add(grp, p, "dist_suitability", "pass", t("qa_msg_tnorm_pass"))
        }
      }
    }

    # ------------------------------------------------------------------
    # Check 5: benchmark deviation from IPCC default
    # Andreas 28/5/26 #3: gated on BENCHMARK_ELIGIBLE_PARAMS so the check
    # only runs for parameters with a defensible direct IPCC table lookup.
    # BW uses continental IPCC Annex Tables 10A.1 (dairy cows) / 10A.2
    # (other cattle) / 10A.3 (buffalo). Milk / DE / Ym / Bo / MW no longer
    # produce benchmark warnings because the previous heuristic mid-points
    # were not citable to a published IPCC table — Andreas's reviewer
    # finding was that the QA tab claimed "IPCC default" values he could
    # not locate in the guidelines. The catalogue's `ipcc_default` values
    # are still used for template auto-fill, just not for deviation
    # flagging here.
    # ------------------------------------------------------------------
    if (p %in% BENCHMARK_ELIGIBLE_PARAMS && !is.na(mu)) {
      # Benchmark against the animal class, not against one adult number.
      # See the .bench_reference() comment: the message used to name a table
      # it was not reading, and every sub-category was measured against the
      # same figure, so the tab warned about the tool's own calf default and
      # about IPCC's own published weights.
      ct <- if ("cattle_type" %in% names(ps))
              tolower(trimws(as.character(ps$cattle_type[i]))) else ""
      sc_i <- if ("sub_category" %in% names(ps))
                as.character(ps$sub_category[i]) else NA_character_
      bench <- .bench_reference(p, sc_i, ct, region)
      ipcc_def <- bench$value
      ref_str  <- bench$source
    }
    if (p %in% BENCHMARK_ELIGIBLE_PARAMS &&
        !is.na(ipcc_def) && ipcc_def != 0 && !is.na(mu)) {
      pct_dev <- abs(mu - ipcc_def) / abs(ipcc_def) * 100
      if (pct_dev > 200) {
        add(grp, p, "benchmark_deviation", "fail",
            qa_msg("bench_fail", mu, pct_dev, ref_str, ipcc_def))
      } else if (pct_dev > 50) {
        add(grp, p, "benchmark_deviation", "warn",
            qa_msg("bench_warn", mu, pct_dev, ref_str, ipcc_def))
      } else {
        add(grp, p, "benchmark_deviation", "pass",
            qa_msg("bench_pass", mu, ref_str, ipcc_def))
      }
    }

    # ------------------------------------------------------------------
    # Round 7 R1.16: defensive check on user-overridden param_type values.
    # ------------------------------------------------------------------
    if ("param_type" %in% names(ps) && !is.na(ps$param_type[i])) {
      ptype <- tolower(trimws(as.character(ps$param_type[i])))
      if (!ptype %in% c("activity_data", "coefficient", "emission_factor")) {
        add(grp, p, "param_type_invalid", "fail",
            qa_msg("paramtype_fail", ps$param_type[i]))
      }
    }

    # ------------------------------------------------------------------
    # Check 4b (R1.3 / Round 6b): missing parameter — auto-filled from IPCC default
    # Reported as a dedicated "missing" severity so reviewers see exactly which
    # parameters were not supplied and what default value+reference was used.
    # ------------------------------------------------------------------
    if ("imputed" %in% names(ps) && isTRUE(ps$imputed[i])) {
      unit_str <- if ("unit" %in% names(ps) && !is.na(ps$unit[i]) && nzchar(ps$unit[i])) {
        ps$unit[i]
      } else if (!is.na(ps$unit_cat[i])) {
        ps$unit_cat[i]
      } else ""
      ref_str <- if ("ipcc_ref" %in% names(ps) && !is.na(ps$ipcc_ref[i]) && nzchar(ps$ipcc_ref[i])) {
        ps$ipcc_ref[i]
      } else if (!is.na(ps$ipcc_ref_cat[i])) {
        ps$ipcc_ref_cat[i]
      } else "IPCC default"
      context_hint <- CONTEXT_DEPENDENT_HINTS[[p]]
      base_msg <- qa_msg("missing", p, mu, unit_str, ref_str)
      msg <- if (!is.null(context_hint)) paste0(base_msg, " ", context_hint) else base_msg
      add(grp, p, "missing_parameter", "missing", msg)
    }

    # ------------------------------------------------------------------
    # Check 5b (T2.3): fractional parameter with unbounded distribution
    # ------------------------------------------------------------------
    UNBOUNDED_DISTS <- c("normal", "lognormal", "posnorm")
    if (p %in% FRACTION_PARAMS && !is.na(d) && tolower(d) %in% UNBOUNDED_DISTS) {
      add(grp, p, "fraction_distribution", "warn",
          qa_msg("frac_dist_warn", p, d))
    } else if (p %in% FRACTION_PARAMS && !is.na(d)) {
      add(grp, p, "fraction_distribution", "pass",
          qa_msg("frac_dist_pass", p, d))
    }

    # ------------------------------------------------------------------
    # Check 6: asymmetric bound check for right-skewed IPCC parameters
    # ------------------------------------------------------------------
    if (p %in% ASYMMETRIC_PARAMS && !is.na(lo) && !is.na(hi) && !is.na(mu) && mu > 0) {
      lower_span <- mu - lo
      upper_span <- hi - mu
      if (lower_span > 0 && upper_span > 0) {
        ratio <- upper_span / lower_span
        if (ratio < 1.5) {
          add(grp, p, "asymmetric_bounds", "warn",
              qa_msg("asym_warn", p, ratio))
        } else {
          add(grp, p, "asymmetric_bounds", "pass",
              qa_msg("asym_pass", p, ratio))
        }
      }
    }
  }

  rows <- rows[seq_len(k)]
  result <- if (k == 0L) {
    data.frame(group = character(), parameter = character(),
               check = character(), status = character(),
               message = character(), stringsAsFactors = FALSE)
  } else {
    do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  }

  # Cross-sheet sub-category-key reconciliation rows (see
  # resolve_sub_category_matches above). Surfaces silent fallback / auto-match
  # / ambiguity as visible QAQC entries — the simulation observer separately
  # consumes the `matched` mapping to substitute the auto-matched MM key.
  if (!is.null(manure_data)) {
    sg <- resolve_sub_category_matches(param_specs, manure_data)
    if (nrow(sg$issues) > 0) result <- rbind(result, sg$issues)
  }

  if (nrow(result) == 0L) return(result)
  param_order <- unique(ps$parameter)
  # Sort: missing → fail → warn → info → pass, then by parameter and check name
  status_rank <- c(missing = 1L, fail = 2L, warn = 3L, info = 4L, pass = 5L)
  result <- result[order(
    status_rank[result$status],
    match(result$parameter, param_order),
    result$check
  ), ]
  rownames(result) <- NULL
  result
}

qaqc_summary <- function(qaqc_df) {
  list(
    n_pass    = sum(qaqc_df$status == "pass", na.rm = TRUE),
    n_info    = sum(qaqc_df$status == "info", na.rm = TRUE),
    n_warn    = sum(qaqc_df$status == "warn", na.rm = TRUE),
    n_fail    = sum(qaqc_df$status == "fail", na.rm = TRUE),
    n_missing = sum(qaqc_df$status == "missing", na.rm = TRUE)
  )
}

qaqc_icon <- function(status) {
  label <- switch(status,
    pass    = t("qa_icon_pass"),
    info    = t("qa_icon_info"),
    warn    = t("qa_icon_warn"),
    fail    = t("qa_icon_fail"),
    missing = t("qa_icon_missing"),
    status
  )
  switch(status,
    pass    = sprintf('<span style="color:#2D6A4F;font-weight:bold;">&#10003; %s</span>', label),
    info    = sprintf('<span style="color:#1565C0;font-weight:bold;">&#9432; %s</span>', label),
    warn    = sprintf('<span style="color:#B45309;font-weight:bold;">&#9651; %s</span>', label),
    fail    = sprintf('<span style="color:#C1121F;font-weight:bold;">&#10007; %s</span>', label),
    missing = sprintf('<span style="color:#92400E;font-weight:bold;background-color:#FEF3C7;padding:1px 6px;border-radius:3px;">&#9888; %s</span>', label),
    label
  )
}
