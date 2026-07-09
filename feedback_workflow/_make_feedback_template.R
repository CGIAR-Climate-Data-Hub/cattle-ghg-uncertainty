library(openxlsx)

wb <- createWorkbook()

# ---- Instructions sheet ----
addWorksheet(wb, "Instructions")
writeData(wb, "Instructions", data.frame(
  ` ` = c(
    "IPCC Tier 2 Livestock GHG Uncertainty Calculator — Beta Testing Feedback Form",
    "",
    "HOW TO USE THIS TEMPLATE",
    "1. Fill in one row per comment in the 'Feedback' sheet.",
    "2. Use the Type dropdown to classify your comment:",
    "   Bug          — the tool crashes, produces wrong numbers, or behaves unexpectedly",
    "   Correction   — something is factually incorrect (method, equation, reference) or not IPCC-compliant",
    "   Enhancement  — a feature that would make the tool more useful",
    "   General      — a general comment or question, or feedback from user experience such as a challenge that you were later able to overcome",
    "3. Use Severity to indicate urgency (Critical = must fix before release).",
    "4. In 'Suggested fix', note the expected behaviour or your proposed solution.",
    "5. Save your completed file and email it to m.lolita@cgiar.org.",
    "6. Multiple reviewers: combine sheets by appending rows — the Reviewer name column keeps them distinct.",
    "",
    "COLUMN DEFINITIONS",
    "Reviewer name   — Your full name",
    "Date            — Date of the observation (YYYY-MM-DD)",
    "Tab             — Which app tab (Home, Definitions, Resources, Data Input, QA/QC, Uncertainty, Correlations, Simulate, Sensitivity, IPCC Report, Contact)",
    "Screen element  — The specific button, table, chart, or text that the comment relates to",
    "Type            — Bug / Correction / Enhancement / General",
    "Severity        — Critical / High / Medium / Low",
    "Description     — What you observed or what the problem is",
    "Suggested fix   — What the correct behaviour should be, or your proposed solution",
    "Status          — Leave blank; will be filled by the development team"
  )
), colNames = FALSE)

setColWidths(wb, "Instructions", cols = 1, widths = 100)
addStyle(wb, "Instructions", style = createStyle(wrapText = TRUE, valign = "top"), rows = 1:30, cols = 1)
addStyle(wb, "Instructions", style = createStyle(fontSize = 14, textDecoration = "bold"), rows = 1, cols = 1)

# ---- Feedback sheet ----
addWorksheet(wb, "Feedback")

headers <- c("Reviewer name", "Date", "Tab", "Screen element / feature",
             "Type", "Severity", "Description", "Suggested fix / comment", "Status")
writeData(wb, "Feedback", as.data.frame(matrix(nrow = 0, ncol = length(headers),
                                                dimnames = list(NULL, headers))))

# Header style
header_style <- createStyle(
  fontColour = "#FFFFFF", fgFill = "#2D6A4F", fontName = "Calibri",
  fontSize = 11, textDecoration = "bold", halign = "left",
  border = "Bottom", borderColour = "#1B4332"
)
addStyle(wb, "Feedback", header_style, rows = 1, cols = seq_along(headers), gridExpand = TRUE)

# Add 50 blank rows with alternating background
even_style <- createStyle(fgFill = "#F7F5F0")
for (r in seq(2, 51, by = 2))
  addStyle(wb, "Feedback", even_style, rows = r, cols = 1:9, gridExpand = TRUE)

# Data validation — Type column (E)
dataValidation(wb, "Feedback", col = 5, rows = 2:200, type = "list",
               value = '"Bug,Correction,Enhancement,General"')
# Data validation — Severity column (F)
dataValidation(wb, "Feedback", col = 6, rows = 2:200, type = "list",
               value = '"Critical,High,Medium,Low"')
# Data validation — Tab column (C)
dataValidation(wb, "Feedback", col = 3, rows = 2:200, type = "list",
               value = '"Home,Definitions,Resources,Data Input,QA/QC,Uncertainty,Correlations,Simulate,Sensitivity,IPCC Report,Contact,General (whole app)"')

# Column widths
setColWidths(wb, "Feedback", cols = 1:9,
             widths = c(18, 12, 14, 28, 14, 12, 50, 50, 10))

# Freeze top row
freezePane(wb, "Feedback", firstRow = TRUE)

# ---- Reference sheet (Type + Severity definitions) ----
# Andreas review: column order is Type | Type_def | Severity | Sev_def
# so the first two columns are the category (Type + its definition) and
# the last two are the severity (Severity + its definition), instead of
# interleaving them.
addWorksheet(wb, "Type_definitions")
writeData(wb, "Type_definitions", data.frame(
  Type      = c("Bug", "Correction", "Enhancement", "General"),
  Type_def  = c(
    "The tool crashes, produces wrong output, or behaves unexpectedly",
    "Something is factually incorrect — wrong equation, wrong IPCC reference, wrong number",
    "A feature that would make the tool more useful or easier to use",
    "A general observation, question, or comment"
  ),
  Severity  = c("Critical", "High", "Medium", "Low"),
  Sev_def   = c(
    "Must fix before any external release — calculation error or crash",
    "Should fix before external release — significant usability or accuracy issue",
    "Can fix in next iteration — minor issue that does not block use",
    "Nice to have — cosmetic or very minor improvement"
  ),
  check.names = FALSE
))
setColWidths(wb, "Type_definitions", cols = 1:4, widths = c(16, 55, 14, 55))
addStyle(wb, "Type_definitions", createStyle(wrapText = TRUE), rows = 1:5, cols = 1:4, gridExpand = TRUE)
addStyle(wb, "Type_definitions", createStyle(textDecoration = "bold", fgFill = "#D8F3DC"),
         rows = 1, cols = 1:4, gridExpand = TRUE)

# NOTE: run from the repo root — `Rscript feedback_workflow/_make_feedback_template.R`
saveWorkbook(wb, "feedback_workflow/beta_feedback_template.xlsx", overwrite = TRUE)
cat("Saved: feedback_workflow/beta_feedback_template.xlsx\n")
