# Consistency checks on a translator-produced template (2026-09-18).
#
# run_qaqc() judges each row on its own. The errors the AI actually made on
# the Zambia file were relational: a calf row split into male and female
# halves with different invented weights, a manure allocation that summed to
# 111 %, one production system given a pasture MCF four times the value the
# file gives every other system, and an uncertainty of 0.5 where the file
# said 50 %. None of these is visible from one row.
#
# These checks run server-side, on the workbook the writer produced, before
# the Download button and again from scripts/translator_eval.R. They are
# advisory: each finding is a sentence the compiler can check against the
# source file. They never change a value.
#
# Returns a data.frame(where, issue) with zero rows when nothing was found.

# ---------------------------------------------------------------------------
# Source reconciliation (2026-10-14)
#
# Everything above compares the template against itself. On the Colombian
# municipal file that was not enough twice in one evening:
#
#   Run 1 emitted 2,067,473 head where the file said 1,873,832, because one
#   group appeared under two aggregation levels. It passed 2,434 checks.
#   Run 2 replaced the Ym of seven groups with the IPCC default of 7.0 where
#   the file gives 5.85 to 6.00, and said so in data_source, unread.
#
# A translator's job is fidelity to a source, so the source has to be one of
# the things it is checked against. `source` carries a fingerprint of the
# uploaded workbook: every number in it, and the parameter families the
# server-side scan found. Both are already computed elsewhere.
#
# When `source` is NULL these checks are skipped and the behaviour is exactly
# as before.
# ---------------------------------------------------------------------------

# Numbers the translator may legitimately derive rather than copy: a unit
# conversion of a single cell. Sums and weighted averages are NOT here; those
# must be tagged user_chat, which exempts them from the verbatim check.
.TRANSLATOR_VALUE_TRANSFORMS <- c(1, 100, 1/100, 18.45, 1/18.45, 365, 1/1000)

# Every numeric reading of a column, including cells that store the number
# as TEXT. A Spanish or French workbook writes 10,78 for ten point seven
# eight, and as.numeric() returns NA for it, so the value is invisible to
# every check below. The Colombian municipal file has two such cells
# (DMI "10,78" and BW "300,00"): they produced a false "no matching number
# is in your file" report on DMI for two municipalities, and they are why
# the translator read 15 rows from a sheet that has 16.
#
# Both continental conventions are read, and the pattern decides which:
#   "10,78" or "1.234,56"  -> comma is the decimal mark
#   "1,234,567"            -> comma groups thousands
# A bare "1,234" is ambiguous, so both readings are kept. This set is only
# ever used for "is this number present in the source", where an extra
# candidate costs sensitivity, never a false alarm.
# [0-9] rather than a shorthand class throughout: R's default TRE
# engine reads a shorthand inside a bracket as literal characters.
.translator_cell_numbers <- function(col) {
  if (is.numeric(col)) return(col[is.finite(col)])
  x <- trimws(as.character(col))
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(numeric(0))
  out <- suppressWarnings(as.numeric(x))
  out <- out[is.finite(out)]
  dec <- grepl("^[-+]?[0-9]+,[0-9]+$", x) |
         grepl("^[-+]?[0-9]{1,3}([.][0-9]{3})+,[0-9]+$", x)
  if (any(dec)) {
    v <- suppressWarnings(as.numeric(gsub(",", ".", gsub("[.]", "", x[dec]))))
    out <- c(out, v[is.finite(v)])
  }
  thou <- grepl("^[-+]?[0-9]{1,3}(,[0-9]{3})+$", x)
  if (any(thou)) {
    v <- suppressWarnings(as.numeric(gsub(",", "", x[thou])))
    out <- c(out, v[is.finite(v)])
  }
  out
}

# The values the source itself gives for each manure coefficient, read from
# the column whose HEADER names it. Matching on the header rather than on
# any cell keeps this precise: the question is "what does their EF3 column
# say", not "does this number appear anywhere in the workbook".
#
# Needed because testing a manure value against the whole number pool is
# far too weak. EF3 = 0.02 passed that test by matching 2/100, where 2 is
# some unrelated count, while the file's own EF3 column says 0.009.
.MANURE_FAMILY_HEADERS <- list(
  MCF          = c("^mcf", "methane conversion", "factor de conversi"),
  EF3          = c("^ef3", "^fe[ _]*n2o", "^factor de emisi.*n2o", "direct n2o"),
  Bo           = c("^bo$", "^b0$", "methane producing", "potencial.*metano"),
  Frac_GasMS   = c("frac_?gas", "volatilis", "volatiliz"),
  Frac_LeachMS = c("frac_?leach", "lixivia", "leaching")
)

.translator_family_column_values <- function(sheets) {
  out <- list()
  for (sh in sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d) || is.null(names(d))) next
    hdr <- tolower(trimws(names(d)))
    for (fam in names(.MANURE_FAMILY_HEADERS)) {
      for (pat in .MANURE_FAMILY_HEADERS[[fam]]) {
        k <- which(grepl(pat, hdr, perl = TRUE))
        if (!length(k)) next
        v <- unlist(lapply(k, function(j) .translator_cell_numbers(d[[j]])))
        v <- v[is.finite(v) & v != 0]
        if (length(v)) out[[fam]] <- unique(c(out[[fam]], round(v, 6)))
        break
      }
    }
  }
  out
}

translator_source_fingerprint <- function(parsed) {
  if (is.null(parsed) || !length(parsed$sheets)) return(NULL)
  nums <- numeric(0)
  for (sh in parsed$sheets) {
    d <- sh$preview
    if (is.null(d) || !NROW(d)) next
    for (col in d) nums <- c(nums, .translator_cell_numbers(col))
  }
  fam <- tryCatch(.translator_scan_param_labels(parsed$sheets),
                  error = function(e) character(0))
  list(numbers  = unique(round(nums, 6)),
       families = sub(" .*$", "", fam),      # "Ym (methane ...)" -> "Ym"
       family_values = tryCatch(.translator_family_column_values(parsed$sheets),
                                error = function(e) list()))
}

translator_consistency_checks <- function(param_specs, manure = NULL,
                                          source = NULL) {
  out <- list()
  # 2026-10-22: every issue carries a severity (fail, warn, info) so the
  # checks workbook and the data workbook can colour it.
  add <- function(where, issue, severity = "warn") {
    out[[length(out) + 1L]] <<- data.frame(where = where, issue = issue,
                                            severity = severity,
                                            stringsAsFactors = FALSE)
  }
  fmt <- function(x) format(signif(x, 7), trim = TRUE)

  ps <- param_specs
  if (!is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("sub_category", "parameter", "mean") %in% names(ps))) {
    lvl <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level)
           else rep("", nrow(ps))
    lvl[is.na(lvl)] <- ""
    sc <- as.character(ps$sub_category)
    mu <- suppressWarnings(as.numeric(ps$mean))

    # 1. Calf halves. A source file almost always carries one calves row;
    #    the template splits it into calves_male and calves_female, and both
    #    halves should then carry the same numbers.
    for (L in unique(lvl)) {
      a <- which(lvl == L & sc == "calves_male")
      b <- which(lvl == L & sc == "calves_female")
      if (!length(a) || !length(b)) next
      m <- merge(data.frame(parameter = ps$parameter[a], m = mu[a], stringsAsFactors = FALSE),
                 data.frame(parameter = ps$parameter[b], f = mu[b], stringsAsFactors = FALSE),
                 by = "parameter")
      # Head counts are allowed to differ by one animal: an odd pooled
      # population splits into halves that differ by 0.5 or 1.
      tol <- ifelse(m$parameter == "N", 1, 1e-9 * pmax(1, abs(m$m)))
      m <- m[!is.na(m$m) & !is.na(m$f) & abs(m$m - m$f) > tol, , drop = FALSE]
      if (nrow(m)) {
        add(sprintf("%s%scalves", L, if (nzchar(L)) " / " else ""),
            sprintf(paste0("Male and female calves carry different values for %s. ",
                           "If the source file has a single calves row, both halves ",
                           "should be identical to it."),
                    paste(sprintf("%s (%s vs %s)", m$parameter, fmt(m$m), fmt(m$f)),
                          collapse = ", ")))
      }
    }

    # 2. Uncertainty far below the rest of the file for the same parameter:
    #    a fraction copied where a percentage was expected (0.5 for 50 %).
    if ("uncertainty_pct" %in% names(ps)) {
      u_all <- suppressWarnings(as.numeric(ps$uncertainty_pct))
      for (p in unique(ps$parameter)) {
        idx <- which(ps$parameter == p & !is.na(u_all) & u_all > 0)
        if (length(idx) < 3) next
        med <- stats::median(u_all[idx])
        if (med < 5) next
        for (i in idx[u_all[idx] < 1]) {
          add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], p),
              sprintf(paste0("Uncertainty %s%% is far below the %s%% typical for %s in this ",
                             "file. A fraction may have been copied instead of a percentage."),
                      fmt(u_all[i]), fmt(med), p))
        }
      }
    }

    # 3. A distribution that cannot represent the value it was given. The
    #    app's QA/QC also fails this row; naming it here lets the compiler
    #    fix it in the source before upload.
    if ("distribution" %in% names(ps)) {
      d <- tolower(as.character(ps$distribution))
      bad_beta <- which(d == "beta" & !is.na(mu) & (mu <= 0 | mu >= 1))
      for (i in bad_beta)
        add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], ps$parameter[i]),
            sprintf("A beta distribution was assigned to a value of %s. Beta only fits values between 0 and 1; the source most likely meant a normal or triangular distribution.", fmt(mu[i])))
      if (all(c("lower", "upper") %in% names(ps))) {
        lo <- suppressWarnings(as.numeric(ps$lower)); hi <- suppressWarnings(as.numeric(ps$upper))
        bad_b <- which(!is.na(mu) & !is.na(lo) & !is.na(hi) & d != "constant" & (lo > mu | mu > hi))
        for (i in bad_b)
          add(sprintf("%s%s%s / %s", lvl[i], if (nzchar(lvl[i])) " / " else "", sc[i], ps$parameter[i]),
              sprintf("The bounds %s to %s do not bracket the mean %s. Either the mean or the bounds came from a different year or group of the source file.", fmt(lo[i]), fmt(hi[i]), fmt(mu[i])))
      }
    }
  }

  mm <- manure
  if (!is.null(mm) && is.data.frame(mm) && nrow(mm) > 0 &&
      all(c("sub_category", "mms_type", "fraction_pct") %in% names(mm))) {
    mlvl <- if ("aggregation_level" %in% names(mm)) as.character(mm$aggregation_level)
            else rep("", nrow(mm))
    mlvl[is.na(mlvl)] <- ""
    key <- paste0(mlvl, ifelse(nzchar(mlvl), " / ", ""), as.character(mm$sub_category))
    fr <- suppressWarnings(as.numeric(mm$fraction_pct))

    # 4. Shares of manure systems must sum to 100 % for each animal group.
    for (k in unique(key)) {
      if (all(is.na(fr[key == k]))) next   # placeholder or empty rows
      s <- sum(fr[key == k], na.rm = TRUE)
      if (abs(s - 100) > 1)
        add(k, sprintf("Manure system shares sum to %s%%, not 100%%. A system may have been added or a share copied from another group.", fmt(s)))
    }

    # 5. One manure system, one set of coefficients. MCF depends on climate
    #    and system, not on which herd uses it, so different values for the
    #    same system across the file point at a copy error.
    coef_cols <- intersect(c("MCF_pct", "EF3", "Frac_GasMS_pct", "Frac_LeachMS_pct"), names(mm))
    for (col in coef_cols) {
      v <- suppressWarnings(as.numeric(mm[[col]]))
      for (mt in unique(as.character(mm$mms_type))) {
        sel <- which(as.character(mm$mms_type) == mt & !is.na(v))
        vals <- unique(round(v[sel], 6))
        if (length(vals) < 2) next
        by_val <- vapply(vals, function(x) {
          grp <- unique(key[sel][round(v[sel], 6) == x])
          sprintf("%s in %s", fmt(x), paste(utils::head(grp, 3), collapse = ", "))
        }, character(1))
        add(mt, sprintf("%s takes %d different values for the same manure system: %s. Check which one the source file gives.",
                        col, length(vals), paste(by_val, collapse = "; ")))
      }
    }

    # 6. One bound pair reused across every manure row (Andreas, 2026-09-30).
    #    On the Zambia file the source gave a RELATIVE MoE of +/-50 % per
    #    share; the translator wrote lower = 0, upper = 50 on every row
    #    instead, so a 40 % dry-lot share and a 1.25 % digester share were
    #    given the same bounds. Every existing check passed it: the bounds
    #    bracket each mean and the centrals still sum to 100. The tell is
    #    that one bound pair repeats across rows whose centrals differ.
    if (all(c("lower_fraction", "upper_fraction") %in% names(mm))) {
      lo <- suppressWarnings(as.numeric(mm$lower_fraction))
      hi <- suppressWarnings(as.numeric(mm$upper_fraction))
      ok <- !is.na(lo) & !is.na(hi) & !is.na(fr)
      if (sum(ok) >= 3L) {
        pair <- paste(round(lo[ok], 6), round(hi[ok], 6), sep = "|")
        # EVERY repeated pair is examined, not just the commonest one. A
        # partly-corrected file can carry the error on a minority of rows
        # while some larger, entirely legitimate group sits above it: on the
        # Zambia file, once the 102 worst rows were fixed, the largest group
        # became 32 rows that correctly share both a bound pair AND a share,
        # which hid 21 rows that were still wrong.
        for (pv in names(table(pair))) {
          sel  <- which(pair == pv)
          n_sh <- length(sel)
          # Only a finding when the shares those rows carry actually differ:
          # several systems genuinely sitting at the same share may
          # legitimately share bounds, and that is not a mistake.
          if (n_sh < 3L) next
          cen <- unique(round(fr[ok][sel], 6))
          if (length(cen) < 2L) next
          b  <- as.numeric(strsplit(pv, "|", fixed = TRUE)[[1]])
          bg <- max(fr[ok][sel])
          add("Manure_Management",
              sprintf(paste0("%d of %d manure rows carry the same bounds (%s to %s) on shares that differ (%s). ",
                             "If the source gives a relative uncertainty, say +/-50%%, the bounds should be a ",
                             "percentage OF EACH SHARE, so a %s%% share becomes %s to %s, not %s to %s."),
                      n_sh, sum(ok), fmt(b[1]), fmt(b[2]),
                      paste(fmt(utils::head(sort(cen), 3)), collapse = ", "),
                      fmt(bg), fmt(bg * 0.5), fmt(bg * 1.5), fmt(b[1]), fmt(b[2])))
        }
      }
    }

    # 7. A per-MMS coefficient given a central value but no bounds anywhere
    #    (Andreas, 2026-09-30). The engine treats a blank bound pair as
    #    EXACTLY KNOWN: sample_per_mms_param() returns a zero-variance column,
    #    so the source's stated uncertainty is dropped rather than replaced by
    #    a default. On the Zambia file MCF came through correctly but its
    #    +/-25 % did not, and nothing said so.
    for (col in coef_cols) {
      lo_col <- switch(col, MCF_pct = "lower_mcf", EF3 = "lower_ef3",
                       Frac_GasMS_pct = "lower_frac_gas",
                       Frac_LeachMS_pct = "lower_frac_leach", NULL)
      hi_col <- switch(col, MCF_pct = "upper_mcf", EF3 = "upper_ef3",
                       Frac_GasMS_pct = "upper_frac_gas",
                       Frac_LeachMS_pct = "upper_frac_leach", NULL)
      if (is.null(lo_col)) next
      v <- suppressWarnings(as.numeric(mm[[col]]))
      n_val <- sum(!is.na(v))
      if (n_val == 0L) next
      lo <- if (lo_col %in% names(mm)) suppressWarnings(as.numeric(mm[[lo_col]])) else rep(NA_real_, nrow(mm))
      hi <- if (hi_col %in% names(mm)) suppressWarnings(as.numeric(mm[[hi_col]])) else rep(NA_real_, nrow(mm))
      if (all(is.na(lo)) && all(is.na(hi)))
        add("Manure_Management",
            sprintf(paste0("%s has a value on %d row(s) but no lower or upper bound on any of them, so the tool will ",
                           "treat it as exactly known and its uncertainty will not reach the result. If the source ",
                           "gives a range for it, add %s and %s."),
                    col, n_val, lo_col, hi_col))
    }
  }

  # ---- source reconciliation ------------------------------------------
  if (!is.null(source) && is.data.frame(ps) && nrow(ps) > 0 &&
      "data_source" %in% names(ps)) {
    dsrc <- tolower(as.character(ps$data_source))
    dsrc[is.na(dsrc)] <- ""
    val  <- suppressWarnings(as.numeric(ps$mean))
    lvl2 <- if ("aggregation_level" %in% names(ps)) as.character(ps$aggregation_level)
            else rep("", nrow(ps))
    lvl2[is.na(lvl2)] <- ""

    # C3. A row tagged user_file claims the number appears in the file as
    # written. Anything else is either a transcription error or invented.
    # Derived values are tagged user_chat and are exempt by design.
    if (length(source$numbers)) {
      verbatim <- dsrc == "user_file" & is.finite(val) & val != 0
      if (any(verbatim)) {
        cand <- unique(as.vector(outer(source$numbers,
                                       .TRANSLATOR_VALUE_TRANSFORMS, "*")))
        seen <- vapply(val[verbatim], function(v)
          any(abs(cand - v) <= 5e-4 * max(1, abs(v))), logical(1))
        if (any(!seen)) {
          miss <- which(verbatim)[!seen]
          shown <- utils::head(unique(sprintf("%s%s%s = %s",
            lvl2[miss], ifelse(nzchar(lvl2[miss]), " / ", ""),
            ps$parameter[miss], fmt(val[miss]))), 6)
          add("source reconciliation", sprintf(paste0(
            "%d value(s) are marked as taken from your file but no matching ",
            "number is in it: %s. Either the value was altered, or it was ",
            "computed and should be marked user_chat rather than user_file."),
            length(miss), paste(shown, collapse = "; ")))
        }
      }
    }

    # C1. A population read from the file belongs to one group. The same
    # number under two groups is the signature of a double count, which is
    # how one run came to report ten per cent more animals than the file.
    isN <- ps$parameter %in% c("N", "cattle_pop") & dsrc == "user_file" &
           is.finite(val) & val > 0
    if (sum(isN) > 1) {
      key <- paste(lvl2[isN], ps$sub_category[isN])
      dup <- val[isN][duplicated(round(val[isN], 4))]
      if (length(dup)) {
        for (d in unique(dup)) {
          w <- key[round(val[isN], 4) == round(d, 4)]
          add("source reconciliation", sprintf(paste0(
            "The population %s appears on %d groups (%s). A head count read ",
            "from the file belongs to one group, so this is usually the same ",
            "animals counted twice."), fmt(d), length(w),
            paste(utils::head(w, 4), collapse = ", ")))
        }
      }
    }

    # C4. The template says a parameter was gap-filled, while the scan found
    # that parameter in the uploaded file. One of the two is wrong, and the
    # user should be the one to decide which.
    if (length(source$families)) {
      filled <- grepl("ipcc|default|auto", dsrc) & ps$parameter %in% source$families
      if (any(filled)) {
        by_p <- split(which(filled), ps$parameter[filled])
        for (pn in names(by_p)) {
          i <- by_p[[pn]]
          add("source reconciliation", sprintf(paste0(
            "%s was filled from the IPCC default on %d row(s) (%s), but %s is ",
            "present in your file. Check whether the file's value should have ",
            "been used."), pn, length(i),
            paste(utils::head(unique(lvl2[i]), 4), collapse = ", "), pn))
        }
      }
    }
  }

  # C5. The same question as C4, asked of the Manure_Management sheet.
  # C4 only sees param_specs, so a coefficient that lives on the manure
  # sheet escaped it entirely: the Colombian file gives a direct N2O
  # emission factor as "FE N2O" = 0.009 and a Bo of 0.19, and the template
  # was written with the IPCC 0.02 and 0.13, with nothing to notice.
  #
  # The comparison is against the source's OWN column for that coefficient,
  # not the workbook's number pool: 0.02 passes a pool test by matching an
  # unrelated 2 divided by 100. Percent against fraction is tolerated,
  # since the sheets differ on that and it is not an error.
  if (!is.null(source) && !is.null(manure) && is.data.frame(manure) &&
      nrow(manure) > 0 && length(source$family_values %||% list())) {
    fv <- source$family_values
    col_fam <- c(MCF_pct = "MCF", EF3 = "EF3", Bo = "Bo",
                 Frac_GasMS_pct = "Frac_GasMS", Frac_LeachMS_pct = "Frac_LeachMS")
    for (cn in names(col_fam)) {
      fam <- col_fam[[cn]]
      if (!cn %in% names(manure) || is.null(fv[[fam]]) || !length(fv[[fam]])) next
      v <- suppressWarnings(as.numeric(manure[[cn]]))
      v <- unique(v[is.finite(v) & v != 0])
      if (!length(v)) next
      ref <- unique(c(fv[[fam]], fv[[fam]] * 100, fv[[fam]] / 100))
      seen <- vapply(v, function(z)
        any(abs(ref - z) <= 1e-3 * max(1, abs(z))), logical(1))
      if (!all(seen)) {
        add("source reconciliation", sprintf(paste0(
          "Manure_Management: %s is set to %s, but your file's own %s column ",
          "gives %s. An IPCC default appears to have replaced a value your ",
          "file supplies. Check which should be used."),
          cn, paste(fmt(v[!seen]), collapse = ", "), fam,
          paste(fmt(utils::head(sort(fv[[fam]]), 4)), collapse = ", ")))
      }
    }
  }

  # C6 (2026-10-22, WP2): every category the AI listed in the source must
  # be a group in the template, unless the user confirmed a merge. One
  # source category becomes one template category; a missing one is a
  # failure, because the template then simply has fewer animals.
  if (!is.null(source) && length(source$source_categories) &&
      !is.null(ps) && is.data.frame(ps) && nrow(ps) > 0 &&
      all(c("sub_category", "aggregation_level") %in% names(ps))) {
    norm <- function(x) gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x))))
    have <- unique(paste(norm(ps$aggregation_level), norm(ps$sub_category), sep = "||"))
    have_sc <- unique(norm(ps$sub_category))
    reg <- source$register %||% list()
    merge_confirmed <- function(label) {
      e <- reg[[paste0("category:", label)]]
      !is.null(e) && identical(e$basis, "user") && grepl("merge|fusion|combine", tolower(e$decision %||% ""))
    }
    missing <- character(0)
    for (sc in source$source_categories) {
      if (nzchar(sc$merge_into %||% "") && merge_confirmed(sc$label)) next
      code <- norm(sc$sub_category %||% "")
      lvl  <- norm(sc$aggregation_level %||% "")
      found <- if (nzchar(code) && nzchar(lvl)) paste(lvl, code, sep = "||") %in% have
               else if (nzchar(code)) code %in% have_sc
               else TRUE
      if (!found) missing <- c(missing, sprintf("%s (%s / %s)", sc$label, sc$aggregation_level %||% "", sc$sub_category %||% ""))
    }
    n_src <- length(source$source_categories)
    n_tpl <- length(have)
    if (length(missing)) {
      add("category coverage", sprintf(paste0(
        "The source file lists %d categories and the template has %d groups; ",
        "%d source categor%s not in the template: %s. Every source category must ",
        "appear unless you confirmed a merge in the conversation."),
        n_src, n_tpl, length(missing), if (length(missing) == 1L) "y is" else "ies are",
        paste(utils::head(missing, 8), collapse = "; ")), severity = "fail")
    } else {
      add("category coverage", sprintf("Source categories: %d; template groups: %d; every source category is in the template.", n_src, n_tpl),
          severity = "info")
    }
  }

  if (!length(out))
    return(data.frame(where = character(), issue = character(), severity = character(),
                      stringsAsFactors = FALSE))
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
