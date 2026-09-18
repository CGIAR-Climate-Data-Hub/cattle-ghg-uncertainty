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

translator_consistency_checks <- function(param_specs, manure = NULL) {
  out <- list()
  add <- function(where, issue) {
    out[[length(out) + 1L]] <<- data.frame(where = where, issue = issue,
                                            stringsAsFactors = FALSE)
  }
  fmt <- function(x) format(signif(x, 4), trim = TRUE)

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
      m <- m[!is.na(m$m) & !is.na(m$f) & abs(m$m - m$f) > 1e-9 * pmax(1, abs(m$m)), , drop = FALSE]
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
  }

  if (!length(out))
    return(data.frame(where = character(), issue = character(), stringsAsFactors = FALSE))
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
