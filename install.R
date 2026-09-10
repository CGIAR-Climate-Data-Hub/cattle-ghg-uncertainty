# Dependency installer (Binder, shinyapps.io, and CI).
#
# Keep this list in sync with the library() calls in app.R and every pkg::
# reference under R/. scripts/audit.R sources R/*.R directly, so a package
# missing here fails the CI regression gate.
install.packages(c(
  "shiny",
  "bslib",
  "shinyWidgets",
  "DT",
  "readxl",
  "writexl",
  "openxlsx",
  "plotly",
  "ggplot2",
  "MASS",
  "mc2d",
  "Matrix",
  "future",
  "promises",
  "httr2",
  "jsonlite",
  "openssl",     # HMAC-SHA256 for magic-link auth + chat-history digests
  "officer",     # Word run-summary report
  "flextable"    # Word report tables
), repos = "https://cloud.r-project.org")
