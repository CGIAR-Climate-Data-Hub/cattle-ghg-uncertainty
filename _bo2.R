suppressMessages({library(readxl)
  for (f in list.files("R", pattern="[.]R$", full.names=TRUE)) source(f)})
ps <- parse_uploaded_template("test_data/COL/Colombia_4municipalities_TEMPLATE.xlsx")$param_specs
b <- ps[ps$parameter == "Bo", ]
cat("Bo on the Parameters sheet of the reference:\n")
cat("  distinct means:", paste(unique(as.numeric(b$mean)), collapse=", "),
    "  on", nrow(b), "rows\n")
cat("  data_source   :", paste(unique(b$data_source), collapse=", "), "\n")
cat("\nThe slider measurement used default_mms_fallback() for MCF/EF3, and\n")
cat("took Bo from the Parameters sheet above.\n")
