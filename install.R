# Dependency installer (Binder, shinyapps.io, and CI).
#
# Keep this list in sync with the library() calls in app.R and every pkg::
# reference under R/. scripts/audit.R sources R/*.R directly, so a package
# missing here fails the CI regression gate.

# Honour a repository the caller has already configured (CI points at the
# Posit public package manager for Linux BINARIES; without this the hardcoded
# CRAN URL below forced a full source build, and the newest sources of `fs`
# and `Deriv` need a newer R than the runner had, which cascaded into shiny,
# DT, plotly and mc2d all failing to install). Falls back to CRAN everywhere
# else, so Binder and shinyapps.io behave exactly as before.
.repo <- getOption("repos")[["CRAN"]]
if (is.null(.repo) || is.na(.repo) || !nzchar(.repo) || .repo == "@CRAN@")
  .repo <- "https://cloud.r-project.org"

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
), repos = .repo)
