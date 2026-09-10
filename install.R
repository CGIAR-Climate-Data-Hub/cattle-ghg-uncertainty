# Dependency installer (Binder, shinyapps.io, and CI).
#
# Keep this list in sync with the library() calls in app.R and every pkg::
# reference under R/. scripts/audit.R sources R/*.R directly, so a package
# missing here fails the CI regression gate.

# Pick a repository, preferring Linux BINARIES when the caller offers them.
#
# r-lib/actions/setup-r with `use-public-rspm: true` publishes the Posit
# public package manager URL as the RSPM *environment variable* -- not as
# options(repos) -- so that is what we read first. Getting this wrong is not
# cosmetic: falling through to source-only CRAN on Ubuntu noble made `fs` and
# `Deriv` fail to build, which cascaded into sass -> bslib -> shiny/DT/plotly
# and Deriv -> doBy -> pbkrtest -> car -> rstatix -> ggpubr -> mc2d, and the
# audit then ran with mc2d missing and aborted three whole sections.
#
# Falls back to any repo the caller configured, then to CRAN, so Binder and
# shinyapps.io behave exactly as before.
.repo <- Sys.getenv("RSPM")
if (!nzchar(.repo)) {
  .opt <- getOption("repos")[["CRAN"]]
  if (!is.null(.opt) && !is.na(.opt) && nzchar(.opt) && .opt != "@CRAN@")
    .repo <- .opt
}
if (!nzchar(.repo)) .repo <- "https://cloud.r-project.org"
message("install.R: using repository ", .repo)

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
