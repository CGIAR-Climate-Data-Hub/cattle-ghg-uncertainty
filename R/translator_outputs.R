# Outputs of a translation (2026-10-22, WP4 of
# knowledge/24-translator-plan-2026-10-22.md): the data workbook annotated
# with the checks (filters, coloured cells, a Check and a Why column), the
# checks workbook the user reviews, the raw conversation document, and the
# names of the three files.

.TRANSLATOR_SEV_FILL <- c(fail = "#FECACA", warn = "#FED7AA", info = "#DBEAFE")
.TRANSLATOR_SEV_FONT <- c(fail = "#7F1D1D", warn = "#9A3412", info = "#1E3A8A")
.TRANSLATOR_SEV_RANK <- c(fail = 3L, warn = 2L, info = 1L)

.translator_safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9]+", "_", trimws(as.character(x %||% "")))
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) "inventory" else x
}

# <Country>_<year>_<what>_<stamp>.<ext>, for example
# Zambia_2022_cattle_uncertainty_template_2026-10-22_1530.xlsx
translator_output_filename <- function(piece, kind = c("template", "checks", "conversation"),
                                       stamp = Sys.time()) {
  kind <- match.arg(kind)
  md <- if (is.list(piece)) piece$inventory_metadata %||% list() else list()
  country <- .translator_safe_name(.translator_scalar(md$country %||% "inventory"))
  year <- .translator_scalar(md$year %||% NA)
  year <- if (!is.na(year) && nzchar(as.character(year))) paste0(gsub("[^0-9]", "", as.character(year)), "_") else ""
  what <- switch(kind, template = "cattle_uncertainty_template",
                 checks = "translation_checks", conversation = "translation_conversation")
  ext <- if (kind == "conversation") "docx" else "xlsx"
  sprintf("%s_%s%s_%s.%s", country, year, what, format(stamp, "%Y-%m-%d_%H%M"), ext)
}

# ---------------------------------------------------------------------------
# Flags: one table of (sheet, group, parameter, severity, text) out of the
# consistency issues and the QA/QC rows
# ---------------------------------------------------------------------------

.translator_flag_table <- function(issues = NULL, qa = NULL) {
  empty <- data.frame(sheet = character(0), group = character(0), parameter = character(0),
                      severity = character(0), text = character(0), stringsAsFactors = FALSE)
  rows <- list()
  if (!is.null(issues) && is.data.frame(issues) && nrow(issues) && "sheet" %in% names(issues)) {
    grp <- as.character(issues$group)
    # a time-series total names a year, not a group: the year column is matched
    yr <- is.na(grp) & grepl("^year ", as.character(issues$where))
    grp[yr] <- as.character(issues$where)[yr]
    ok <- !is.na(issues$sheet) & nzchar(issues$sheet) & !is.na(grp)
    name <- if ("check" %in% names(issues)) ifelse(is.na(issues$check), issues$where, issues$check) else issues$where
    if (any(ok))
      rows[[length(rows) + 1L]] <- data.frame(
        sheet = issues$sheet[ok], group = grp[ok],
        parameter = if ("parameter" %in% names(issues)) issues$parameter[ok] else NA_character_,
        severity = issues$severity[ok] %||% "warn",
        text = paste0(name[ok], ": ", issues$issue[ok]), stringsAsFactors = FALSE)
  }
  if (!is.null(qa) && is.data.frame(qa) && nrow(qa) && all(c("group", "parameter", "status") %in% names(qa))) {
    keep <- qa$status %in% c("fail", "warn")
    if (any(keep))
      rows[[length(rows) + 1L]] <- data.frame(
        sheet = "Parameters", group = .translator_qa_group_key(qa)[keep],
        parameter = as.character(qa$parameter[keep]),
        severity = as.character(qa$status[keep]),
        text = paste0(if ("check" %in% names(qa)) paste0(qa$check[keep], ": ") else "", qa$message[keep]),
        stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

# The header row of a sheet: the first of the top rows holding "cattle_type".
# The QA/QC rows name a group "cattle_type / sub_category" and carry the
# production system in `level`; the workbook key is
# cattle_type||level||sub_category. Without a level, the sub-category alone
# (every system's row of it is matched).
.translator_qa_group_key <- function(qa) {
  g <- as.character(qa$group)
  lv <- if ("level" %in% names(qa)) as.character(qa$level) else rep(NA_character_, length(g))
  parts <- strsplit(g, " / ", fixed = TRUE)
  vapply(seq_along(g), function(i) {
    p <- parts[[i]]
    if (length(p) == 2L && !is.na(lv[i]) && nzchar(lv[i])) paste(p[1], lv[i], p[2], sep = "||")
    else if (length(p) == 2L) p[2] else g[i]
  }, character(1))
}

.translator_sheet_header_row <- function(wb, sheet) {
  top <- tryCatch(openxlsx::read.xlsx(wb, sheet = sheet, colNames = FALSE, rows = 1:8,
                                      skipEmptyRows = FALSE, skipEmptyCols = FALSE),
                  error = function(e) NULL)
  if (is.null(top)) return(NA_integer_)
  for (i in seq_len(nrow(top)))
    if (any(trimws(as.character(unlist(top[i, ]))) == "cattle_type", na.rm = TRUE)) return(i)
  NA_integer_
}

# Annotate the written data workbook in place: autofilter on every data
# sheet, conditional formatting extended to every written row, flagged
# cells filled with the severity colour, and two columns at the right,
# Check and Why. The layout the app reads is untouched (the two columns sit
# after the last one parse_uploaded_template() looks at).
.translator_annotate_workbook <- function(path, issues = NULL, qa = NULL) {
  if (is.null(path) || !file.exists(path)) return(invisible(FALSE))
  wb <- tryCatch(openxlsx::loadWorkbook(path), error = function(e) NULL)
  if (is.null(wb)) return(invisible(FALSE))
  flags <- .translator_flag_table(issues, qa)
  hdr_style <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#E5E7EB",
                                     border = "Bottom")
  sev_style <- lapply(names(.TRANSLATOR_SEV_FILL), function(s)
    openxlsx::createStyle(fgFill = .TRANSLATOR_SEV_FILL[[s]], fontColour = .TRANSLATOR_SEV_FONT[[s]]))
  names(sev_style) <- names(.TRANSLATOR_SEV_FILL)

  for (sh in intersect(c("Parameters", "Manure_Management", "Parameter_TimeSeries"), names(wb))) {
    hdr <- .translator_sheet_header_row(wb, sh)
    if (is.na(hdr)) next
    full <- tryCatch(openxlsx::read.xlsx(wb, sheet = sh, startRow = hdr, colNames = TRUE,
                                         skipEmptyRows = FALSE, skipEmptyCols = FALSE),
                     error = function(e) NULL)
    if (is.null(full) || !nrow(full)) next
    keycols <- intersect(c("cattle_type", "aggregation_level", "sub_category"), names(full))
    if (!length(keycols)) next
    has <- rowSums(!is.na(full[, keycols, drop = FALSE]) & full[, keycols, drop = FALSE] != "") > 0
    last_data <- if (any(has)) max(which(has)) else 0L
    if (!last_data) next
    # a workbook annotated before (a corrected template coming back, or a
    # second pass) keeps its two columns: they are cleared and written again
    check_col <- match("Check", names(full)); why_col <- match("Why", names(full))
    if (is.na(check_col) || is.na(why_col)) {
      last_col  <- ncol(full)
      check_col <- last_col + 1L
      why_col   <- last_col + 2L
    } else {
      openxlsx::deleteData(wb, sh, cols = c(check_col, why_col), rows = (hdr + 1L):(hdr + last_data), gridExpand = TRUE)
    }

    openxlsx::writeData(wb, sh, "Check", startRow = hdr, startCol = check_col, colNames = FALSE)
    openxlsx::writeData(wb, sh, "Why",   startRow = hdr, startCol = why_col,   colNames = FALSE)
    openxlsx::addStyle(wb, sh, hdr_style, rows = hdr, cols = c(check_col, why_col), gridExpand = TRUE)
    openxlsx::setColWidths(wb, sh, cols = c(check_col, why_col), widths = c(10, 80))
    openxlsx::addFilter(wb, sh, rows = hdr, cols = 1:why_col)

    # the template's own rules stop at row 204; extend them to every row
    if (identical(sh, "Parameters") && hdr + last_data > 204L &&
        all(c("value", "uncertainty_pct", "lower_bound", "upper_bound") %in% names(full))) {
      rows_x <- 205:(hdr + last_data)
      red    <- openxlsx::createStyle(fgFill = "#FECACA", fontColour = "#7F1D1D")
      orange <- openxlsx::createStyle(fgFill = "#FED7AA", fontColour = "#9A3412")
      ci <- function(nm) match(nm, names(full))
      L <- function(nm) openxlsx::int2col(ci(nm))
      openxlsx::conditionalFormatting(wb, sh, cols = ci("value"), rows = rows_x,
        rule = sprintf('AND(%s%d="",A%d<>"")', L("value"), rows_x[1], rows_x[1]), style = red, type = "expression")
      openxlsx::conditionalFormatting(wb, sh, cols = ci("uncertainty_pct"), rows = rows_x,
        rule = ">100", style = orange, type = "expression")
      for (nm in c("lower_bound", "upper_bound"))
        openxlsx::conditionalFormatting(wb, sh, cols = ci(nm), rows = rows_x,
          rule = sprintf('AND(%s%d<>"",%s%d<>"",%s%d>=%s%d)', L("lower_bound"), rows_x[1], L("upper_bound"), rows_x[1],
                         L("lower_bound"), rows_x[1], L("upper_bound"), rows_x[1]),
          style = red, type = "expression")
    }

    fs <- flags[flags$sheet == sh, , drop = FALSE]
    if (!nrow(fs)) next
    key <- do.call(paste, c(lapply(c("cattle_type", "aggregation_level", "sub_category"), function(k)
      if (k %in% names(full)) ifelse(is.na(full[[k]]), "", as.character(full[[k]])) else ""), sep = "||"))
    subc <- if ("sub_category" %in% names(full)) ifelse(is.na(full$sub_category), "", as.character(full$sub_category)) else key
    # per sheet row: the worst severity and the texts
    row_sev <- rep(NA_character_, nrow(full)); row_txt <- vector("list", nrow(full))
    cell_hits <- list()
    for (k in seq_len(nrow(fs))) {
      g <- fs$group[k]
      rows_hit <- if (identical(sh, "Parameter_TimeSeries") && grepl("^year ", g) && "year" %in% names(full))
        which(as.character(full$year) == sub("^year ", "", g))
      else which(key == g | subc == g | (nzchar(g) & grepl(g, key, fixed = TRUE)))
      if (!length(rows_hit)) next
      prm <- fs$parameter[k]
      col_hit <- NA_integer_
      if (identical(sh, "Parameters")) {
        if (!is.na(prm) && "parameter" %in% names(full)) rows_hit <- rows_hit[full$parameter[rows_hit] == prm]
        col_hit <- match("value", names(full))
      } else if (!is.na(prm) && prm %in% names(full)) {
        col_hit <- match(prm, names(full))
      }
      rows_hit <- rows_hit[!is.na(rows_hit) & rows_hit <= last_data]
      if (!length(rows_hit)) next
      sev <- fs$severity[k]; if (!sev %in% names(.TRANSLATOR_SEV_RANK)) sev <- "warn"
      for (r in rows_hit) {
        if (is.na(row_sev[r]) || .TRANSLATOR_SEV_RANK[[sev]] > .TRANSLATOR_SEV_RANK[[row_sev[r]]]) row_sev[r] <- sev
        row_txt[[r]] <- c(row_txt[[r]], fs$text[k])
        if (!is.na(col_hit)) cell_hits[[length(cell_hits) + 1L]] <- c(r, col_hit, sev)
      }
    }
    for (r in which(!is.na(row_sev))) {
      xr <- hdr + r
      openxlsx::writeData(wb, sh, row_sev[r], startRow = xr, startCol = check_col, colNames = FALSE)
      openxlsx::writeData(wb, sh, paste(unique(row_txt[[r]]), collapse = " | "),
                          startRow = xr, startCol = why_col, colNames = FALSE)
      openxlsx::addStyle(wb, sh, sev_style[[row_sev[r]]], rows = xr, cols = check_col, gridExpand = TRUE)
    }
    for (h in cell_hits)
      openxlsx::addStyle(wb, sh, sev_style[[h[3]]], rows = hdr + as.integer(h[1]),
                         cols = as.integer(h[2]), gridExpand = TRUE, stack = TRUE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# The checks workbook: every check row, the decisions, a summary
# ---------------------------------------------------------------------------

translator_checks_table <- function(pc) {
  cols <- c("Sheet", "Group", "Parameter", "Check", "Severity", "Explanation", "Your decision")
  rows <- list()
  iss <- pc$issues
  if (!is.null(iss) && is.data.frame(iss) && nrow(iss)) {
    name <- if ("check" %in% names(iss)) ifelse(is.na(iss$check), iss$where, iss$check) else iss$where
    grp <- if ("group" %in% names(iss)) ifelse(is.na(iss$group), "", gsub("||", " / ", iss$group, fixed = TRUE)) else rep("", nrow(iss))
    # a check with no group but a place in its label (a manure system, a year) shows the place
    place <- !nzchar(grp) & !is.na(iss$where) & iss$where != name & !iss$where %in% c("Manure_Management", "Parameters")
    grp[place] <- iss$where[place]
    rows[[length(rows) + 1L]] <- data.frame(
      Sheet = if ("sheet" %in% names(iss)) ifelse(is.na(iss$sheet), "", iss$sheet) else "",
      Group = grp,
      Parameter = if ("parameter" %in% names(iss)) ifelse(is.na(iss$parameter), "", iss$parameter) else "",
      Check = name, Severity = if ("severity" %in% names(iss)) iss$severity else "warn",
      Explanation = iss$issue, `Your decision` = "", check.names = FALSE, stringsAsFactors = FALSE)
  }
  qa <- pc$qa
  if (!is.null(qa) && is.data.frame(qa) && nrow(qa)) {
    keep <- qa$status %in% c("fail", "warn")
    if (any(keep))
      rows[[length(rows) + 1L]] <- data.frame(
        Sheet = "Parameters", Group = gsub("||", " / ", .translator_qa_group_key(qa)[keep], fixed = TRUE),
        Parameter = as.character(qa$parameter[keep]),
        Check = if ("check" %in% names(qa)) as.character(qa$check[keep]) else "QA/QC",
        Severity = as.character(qa$status[keep]), Explanation = as.character(qa$message[keep]),
        `Your decision` = "", check.names = FALSE, stringsAsFactors = FALSE)
  }
  if (!length(rows)) {
    out <- as.data.frame(setNames(replicate(length(cols), character(0), simplify = FALSE), cols),
                         check.names = FALSE, stringsAsFactors = FALSE)
    return(out)
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out[order(-.TRANSLATOR_SEV_RANK[ifelse(out$Severity %in% names(.TRANSLATOR_SEV_RANK), out$Severity, "info")],
            out$Sheet, out$Group), , drop = FALSE]
}

translator_write_checks_xlsx <- function(pc, register = NULL, path, extra = list()) {
  checks <- translator_checks_table(pc)
  dec <- translator_register_df(register)
  names(dec) <- c("Topic", "Decision", "Basis", "Confidence", "Status", "Applied", "Note")
  n_by <- function(s) sum(checks$Severity == s)
  summary <- data.frame(
    Item = c("Generated", "Parameter rows", "Manure rows", "Checks: fail", "Checks: warn", "Checks: info",
             "Model", "Prompt hash", "Decisions digest", "How to use this file"),
    Value = c(format(Sys.time(), "%Y-%m-%d %H:%M"), as.character(pc$n_params %||% ""),
              as.character(pc$n_manure %||% ""), n_by("fail"), n_by("warn"), n_by("info"),
              extra$model %||% "", extra$prompt_hash %||% "", extra$register_digest %||% "",
              "Go through the Checks sheet from the top (fail first). Fix the cell in the data workbook, or write what you decided in the last column, so the review is on record."),
    stringsAsFactors = FALSE)
  wb <- openxlsx::createWorkbook()
  hdr <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#E5E7EB", border = "Bottom", wrapText = TRUE)
  wrap <- openxlsx::createStyle(wrapText = TRUE, valign = "top")
  add_sheet <- function(name, df, widths = NULL) {
    openxlsx::addWorksheet(wb, name)
    openxlsx::writeData(wb, name, df, headerStyle = hdr)
    if (nrow(df)) openxlsx::addStyle(wb, name, wrap, rows = 2:(nrow(df) + 1L), cols = seq_len(ncol(df)), gridExpand = TRUE)
    if (!is.null(widths)) openxlsx::setColWidths(wb, name, cols = seq_along(widths), widths = widths)
    openxlsx::freezePane(wb, name, firstRow = TRUE)
    openxlsx::addFilter(wb, name, rows = 1, cols = seq_len(ncol(df)))
  }
  add_sheet("Checks", checks, widths = c(18, 36, 14, 26, 10, 90, 30))
  for (s in names(.TRANSLATOR_SEV_FILL)) {
    r <- which(checks$Severity == s)
    if (length(r))
      openxlsx::addStyle(wb, "Checks", openxlsx::createStyle(fgFill = .TRANSLATOR_SEV_FILL[[s]], fontColour = .TRANSLATOR_SEV_FONT[[s]]),
                         rows = r + 1L, cols = 5L, gridExpand = TRUE)
  }
  add_sheet("Decisions", dec, widths = c(26, 50, 12, 12, 12, 10, 40))
  add_sheet("Summary", summary, widths = c(24, 90))
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

# ---------------------------------------------------------------------------
# The conversation document: raw, size 10, questions in one colour and
# answers in another, the start time first, nothing else
# ---------------------------------------------------------------------------

.TRANSLATOR_DOC_Q_COLOUR <- "#1D4ED8"   # the AI's questions
.TRANSLATOR_DOC_A_COLOUR <- "#166534"   # the user's answers

translator_write_conversation_docx <- function(messages, path) {
  doc <- officer::read_docx()
  para <- function(doc, txt, colour = "#000000") {
    lines <- strsplit(txt %||% "", "\n", fixed = TRUE)[[1]]
    if (!length(lines)) lines <- ""
    for (ln in lines)
      doc <- officer::body_add_fpar(doc, officer::fpar(officer::ftext(
        ln, prop = officer::fp_text(font.size = 10, color = colour))))
    doc
  }
  ts <- vapply(messages, function(m) as.character(m$ts %||% ""), character(1))
  ts <- ts[nzchar(ts)]
  started <- if (length(ts)) sub("T", " ", sub("Z$", " UTC", sort(ts)[1])) else "time not recorded"
  doc <- para(doc, paste0("Conversation started ", started))
  doc <- para(doc, "")
  for (m in messages) {
    src <- m$source %||% ""
    if (src %in% c("server_notice", "answers_batch", "user_continue")) next
    if (identical(m$role, "user")) {
      txt <- if (identical(src, "server_upload")) paste0("[", m$display %||% "File uploaded", "]")
             else m$display %||% m$content %||% ""
      doc <- para(doc, txt, .TRANSLATOR_DOC_A_COLOUR)
    } else {
      txt <- m$display %||% m$content %||% ""
      txt <- .translator_strip_decisions(txt)
      txt <- .translator_strip_source_categories(txt)
      if (!nzchar(trimws(txt))) next
      doc <- para(doc, txt, .TRANSLATOR_DOC_Q_COLOUR)
    }
    doc <- para(doc, "")
  }
  print(doc, target = path)
  invisible(path)
}
