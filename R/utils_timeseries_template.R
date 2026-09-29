# Time Series Template for Activity Data Correlations
# Generates an Excel workbook users can download, fill in, and re-upload
# to Tab 4 (Correlations) so the tool can estimate pairwise correlations
# between activity data parameters from historical data.

generate_timeseries_template <- function(filepath) {

  if (!requireNamespace("openxlsx", quietly = TRUE))
    stop("Package 'openxlsx' is required to generate the template.")

  wb <- openxlsx::createWorkbook()

  # ---------------------------------------------------------------------------
  # Styles
  # ---------------------------------------------------------------------------
  mk <- function(...) openxlsx::createStyle(...)

  s_title   <- mk(fontSize = 14, fontColour = "#1B4332", textDecoration = "bold",
                  fontName = "Calibri")
  s_h2      <- mk(fontSize = 11, fontColour = "#1B4332", textDecoration = "bold",
                  fontName = "Calibri")
  s_body    <- mk(fontSize = 10, fontName = "Calibri", wrapText = TRUE,
                  valign = "top")
  s_label   <- mk(fontSize = 10, fontName = "Calibri", textDecoration = "bold",
                  fontColour = "#2D6A4F")
  s_warn    <- mk(fontSize = 10, fontName = "Calibri", fontColour = "#92400E",
                  fgFill = "#FEF3C7")
  s_header  <- mk(fontSize = 10, fontName = "Calibri", textDecoration = "bold",
                  fontColour = "#FFFFFF", fgFill = "#2D6A4F",
                  border = "TopBottomLeftRight", borderColour = "#1B4332",
                  halign = "center", valign = "center", wrapText = TRUE)
  s_subhdr  <- mk(fontSize = 9, fontName = "Calibri", fontColour = "#555555",
                  fgFill = "#D8F3DC", border = "TopBottomLeftRight",
                  borderColour = "#B7DFC0", halign = "center", valign = "top",
                  wrapText = TRUE, textDecoration = "italic")
  s_year    <- mk(fontSize = 10, fontName = "Calibri", halign = "center",
                  fgFill = "#F0FDF4", border = "TopBottomLeftRight",
                  borderColour = "#D1FAE5")
  s_data    <- mk(fontSize = 10, fontName = "Calibri", halign = "right",
                  fgFill = "#F0FDF4", border = "TopBottomLeftRight",
                  borderColour = "#D1FAE5", numFmt = "0.000")
  s_data_int <- mk(fontSize = 10, fontName = "Calibri", halign = "right",
                   fgFill = "#F0FDF4", border = "TopBottomLeftRight",
                   borderColour = "#D1FAE5", numFmt = "#,##0")
  s_empty   <- mk(fontSize = 10, fontName = "Calibri", halign = "right",
                  fgFill = "#FFFFFF", border = "TopBottomLeftRight",
                  borderColour = "#E5E7EB")
  s_note    <- mk(fontSize = 9, fontName = "Calibri", fontColour = "#6B7280",
                  textDecoration = "italic", wrapText = TRUE)
  s_bullet  <- mk(fontSize = 10, fontName = "Calibri", wrapText = TRUE,
                  valign = "top", indent = 1L)

  apply_style <- function(sheet, style, rows, cols, ...) {
    openxlsx::addStyle(wb, sheet, style, rows = rows, cols = cols,
                        gridExpand = TRUE, ...)
  }

  # ---------------------------------------------------------------------------
  # Sheet 1: README
  # ---------------------------------------------------------------------------
  openxlsx::addWorksheet(wb, "README", tabColour = "#2D6A4F")
  openxlsx::setColWidths(wb, "README", cols = 1, widths = 3)
  openxlsx::setColWidths(wb, "README", cols = 2, widths = 22)
  openxlsx::setColWidths(wb, "README", cols = 3, widths = 70)

  wr <- function(row, col, val, style = s_body) {
    openxlsx::writeData(wb, "README", val, startRow = row, startCol = col)
    if (!is.null(style)) apply_style("README", style, rows = row, cols = col)
  }

  openxlsx::setRowHeights(wb, "README", rows = 1, heights = 30)
  wr(1, 2, "Activity Data Time Series Template: README", s_title)

  openxlsx::setRowHeights(wb, "README", rows = 3, heights = 20)
  wr(3, 2, "PURPOSE", s_h2)
  wr(3, 3,
     paste("This workbook is used to supply historical time series data so the tool can",
           "estimate correlations between activity data parameters.",
           "When you upload this file in Tab 4 (Correlations > Activity Data > Upload time series),",
           "the tool computes a Spearman rank correlation matrix from your data and",
           "preserves it through Monte Carlo sampling per IPCC Vol.1 Ch.3 §3.2.3.2.",
           "You do NOT need to fill in every column: include only the parameters you have",
           "historical data for. The tool will treat unspecified parameters as uncorrelated",
           "with everything else (correlation = 0)."))

  openxlsx::setRowHeights(wb, "README", rows = 6, heights = 20)
  wr(6, 2, "SHEET TO FILL IN", s_h2)
  wr(6, 3, "Go to the 'TimeSeries' sheet. Fill in your data there. Do not rename that sheet.")

  openxlsx::setRowHeights(wb, "README", rows = 9, heights = 20)
  wr(9, 2, "MINIMUM REQUIREMENTS", s_h2)
  rows_req <- c(
    "At least 2 numeric columns (parameters) with data.",
    "At least 5 rows of data (years/periods). More years = more reliable correlations.",
    "Column names must exactly match the parameter names shown in row 2 of the TimeSeries sheet.",
    "Do not include a 'year' column with letters (e.g. '2015' as text). Use numbers or leave year out.",
    "Missing values are allowed: the tool uses pairwise complete observations (use = 'complete.obs')."
  )
  for (i in seq_along(rows_req)) {
    r <- 9 + i
    openxlsx::setRowHeights(wb, "README", rows = r, heights = 16)
    wr(r, 2, paste0(i, "."), s_label)
    wr(r, 3, rows_req[i], s_bullet)
  }

  openxlsx::setRowHeights(wb, "README", rows = 16, heights = 20)
  wr(16, 2, "COLUMN GUIDE", s_h2)

  col_guide <- data.frame(
    # R1.6: IPCC-aligned names
    Parameter = c("year", "N", "BW", "MW",
                  "WG", "Milk", "Fat", "pct_pregnant",
                  "DE", "CP", "MilkPR",
                  "Cfi", "Ca", "C", "Cp", "hours"),
    Unit = c("(non-numeric)", "head", "kg", "kg",
             "kg/day", "kg/head/day", "%", "fraction 0-1",
             "%", "%", "%",
             "MJ/day/kg^0.75", "dimensionless", "dimensionless", "dimensionless", "hours/day"),
    Source = c(
      "Year label: not used in correlation",
      "National livestock census / survey",
      "Livestock survey / liveweight monitoring",
      "Livestock survey / breed records",
      "Growth trials / expert estimate: often constant",
      "Dairy records / milk production surveys",
      "Dairy records / laboratory analysis",
      "Dairy records / reproduction surveys",
      "Feed quality studies / IPCC default table: often constant",
      "Feed quality studies: often constant",
      "Dairy records / laboratory analysis",
      "IPCC Table 10.4: typically constant, rarely measured annually",
      "IPCC Table 10.5: typically constant (depends on feeding system)",
      "IPCC Eq 10.6: typically constant (depends on sex)",
      "IPCC Table 10.7: typically constant (0 or 0.10)",
      "Work hours records: typically constant or zero"
    ),
    stringsAsFactors = FALSE
  )
  openxlsx::writeDataTable(wb, "README", col_guide,
                            startRow = 17, startCol = 2,
                            tableStyle = "TableStyleLight9")

  openxlsx::setRowHeights(wb, "README", rows = 35, heights = 20)
  wr(35, 2, "WHICH COLUMNS TO INCLUDE", s_h2)
  wr(35, 3,
     paste("Most users will only have reliable time series for cattle_pop and possibly",
           "BW or milk_yield. That is perfectly fine: include those columns only.",
           "The tool will set the correlation to 0 for all other pairs.",
           "\n\nIf your param_specs has Cfi, Ca, C_growth, or Cp as activity_data parameters",
           "and you suspect these vary correlated with your population data",
           "(e.g., diet quality improves when herd size shrinks), you may add those columns.",
           "Otherwise, leave them out."))

  openxlsx::setRowHeights(wb, "README", rows = 42, heights = 20)
  wr(42, 2, "IMPORTANT", s_h2)
  msgs <- c(
    "Do not change column header names: they must match the parameter names exactly.",
    "Column order does not matter: the tool matches by name.",
    "You can delete columns you have no data for.",
    "You can add more rows (years) beyond the 20 provided.",
    "Save the file as .xlsx before uploading."
  )
  for (i in seq_along(msgs)) {
    r <- 42 + i
    openxlsx::setRowHeights(wb, "README", rows = r, heights = 16)
    wr(r, 2, paste0(i, "."), s_label)
    wr(r, 3, msgs[i], s_bullet)
  }
  openxlsx::setRowHeights(wb, "README", rows = 49, heights = 32)
  openxlsx::writeData(wb, "README",
    "Note: The tool uses Pearson correlation on the raw time series. If your data has strong trends, consider detrending before using this template (e.g., use percentage changes year-on-year rather than absolute values), correlations in trending data reflect the shared trend, not the true year-to-year co-movement.",
    startRow = 49, startCol = 3)
  apply_style("README", s_warn, rows = 49, cols = 3)

  # ---------------------------------------------------------------------------
  # Sheet 2: TimeSeries
  # ---------------------------------------------------------------------------
  openxlsx::addWorksheet(wb, "TimeSeries", tabColour = "#40916C",
                          gridLines = TRUE)

  # R1.6: IPCC-aligned names
  params <- c("N", "BW", "MW", "WG",
              "Milk", "Fat", "pct_pregnant", "DE",
              "CP", "MilkPR")

  units <- c("head", "kg", "kg", "kg/day",
             "kg/head/day", "%", "fraction (0-1)", "%",
             "%", "%")

  descriptions <- c(
    "No. of animals",
    "Avg. body weight (BW)",
    "Mature body weight",
    "Daily weight gain",
    "Daily milk yield per cow",
    "Milk fat content",
    "Fraction calving (calves/females/year)",
    "Digestible energy",
    "Crude protein in diet",
    "Milk protein content"
  )

  all_cols  <- c("year", params)
  all_units <- c("(label only)", units)
  all_desc  <- c("Calendar year", descriptions)
  n_cols    <- length(all_cols)

  # Column widths
  openxlsx::setColWidths(wb, "TimeSeries", cols = 1, widths = 7)
  openxlsx::setColWidths(wb, "TimeSeries", cols = 2:n_cols, widths = 14)

  # Row 1: Parameter names (used by the tool)
  openxlsx::writeData(wb, "TimeSeries",
                       as.data.frame(t(all_cols)), startRow = 1, startCol = 1,
                       colNames = FALSE)
  apply_style("TimeSeries", s_header, rows = 1, cols = 1:n_cols)
  openxlsx::setRowHeights(wb, "TimeSeries", rows = 1, heights = 22)

  # Row 2: Descriptions (informational)
  openxlsx::writeData(wb, "TimeSeries",
                       as.data.frame(t(all_desc)), startRow = 2, startCol = 1,
                       colNames = FALSE)
  apply_style("TimeSeries", s_subhdr, rows = 2, cols = 1:n_cols)
  openxlsx::setRowHeights(wb, "TimeSeries", rows = 2, heights = 28)

  # Row 3: Units
  openxlsx::writeData(wb, "TimeSeries",
                       as.data.frame(t(all_units)), startRow = 3, startCol = 1,
                       colNames = FALSE)
  apply_style("TimeSeries", s_subhdr, rows = 3, cols = 1:n_cols)
  openxlsx::setRowHeights(wb, "TimeSeries", rows = 3, heights = 18)

  DATA_START <- 4

  # Example data: 10 years of hypothetical Country X values with realistic year-to-year variation
  set.seed(42)
  years <- 2013:2022
  n_ex  <- length(years)

  ex <- data.frame(
    year         = years,
    N            = round(c(4320000, 4410000, 4480000, 4530000, 4490000,
                            4560000, 4620000, 4670000, 4720000, 4790000)),
    BW           = round(c(278, 275, 272, 270, 274, 271, 268, 273, 276, 274), 1),
    MW           = round(c(302, 300, 300, 299, 301, 300, 298, 301, 302, 300), 1),
    WG           = round(c(0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00), 2),
    Milk         = round(c(3.9, 4.1, 4.0, 3.8, 4.2, 4.0, 3.9, 4.1, 4.0, 4.3), 2),
    Fat          = round(c(3.9, 4.0, 4.1, 3.9, 4.0, 4.0, 4.1, 4.0, 3.9, 4.1), 2),
    pct_pregnant  = round(c(0.59, 0.61, 0.60, 0.58, 0.62, 0.60, 0.59, 0.61, 0.60, 0.62), 3),
    DE           = round(c(54.5, 55.0, 55.5, 54.0, 55.5, 55.0, 54.5, 56.0, 55.0, 55.5), 1),
    CP           = round(c(9.8, 10.0, 10.2, 9.6, 10.3, 10.0, 9.9, 10.4, 10.1, 10.2), 1),
    MilkPR       = round(c(3.2, 3.3, 3.3, 3.2, 3.4, 3.3, 3.2, 3.4, 3.3, 3.4), 2)
  )

  openxlsx::writeData(wb, "TimeSeries", ex,
                       startRow = DATA_START, startCol = 1, colNames = FALSE)
  apply_style("TimeSeries", s_year,     rows = DATA_START:(DATA_START + n_ex - 1), cols = 1)
  apply_style("TimeSeries", s_data_int, rows = DATA_START:(DATA_START + n_ex - 1), cols = 2)
  apply_style("TimeSeries", s_data,     rows = DATA_START:(DATA_START + n_ex - 1), cols = 3:n_cols)
  openxlsx::setRowHeights(wb, "TimeSeries",
                           rows = DATA_START:(DATA_START + n_ex - 1), heights = 16)

  # 20 blank rows for user data
  BLANK_START <- DATA_START + n_ex
  BLANK_END   <- BLANK_START + 19
  apply_style("TimeSeries", s_empty,
              rows = BLANK_START:BLANK_END, cols = 1:n_cols)
  openxlsx::setRowHeights(wb, "TimeSeries", rows = BLANK_START:BLANK_END, heights = 16)

  # Instruction row below blanks
  NOTE_ROW <- BLANK_END + 2
  openxlsx::writeData(wb, "TimeSeries",
    "Add more rows above this line if needed. Delete the example data (rows 4-13) and replace with your own.",
    startRow = NOTE_ROW, startCol = 1)
  apply_style("TimeSeries", s_note, rows = NOTE_ROW, cols = 1)
  openxlsx::mergeCells(wb, "TimeSeries",
                        cols = 1:n_cols, rows = NOTE_ROW)

  # Freeze top 3 rows
  openxlsx::freezePane(wb, "TimeSeries", firstActiveRow = DATA_START)

  # Tab order: README first
  openxlsx::worksheetOrder(wb) <- c(1, 2)

  openxlsx::saveWorkbook(wb, filepath, overwrite = TRUE)
}
