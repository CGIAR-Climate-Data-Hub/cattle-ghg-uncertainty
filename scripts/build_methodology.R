# Run from project root: Rscript scripts/build_methodology.R
# Self-correcting if invoked from inside scripts/.
if (basename(getwd()) == "scripts") setwd("..")

if (!requireNamespace("rmarkdown", quietly = TRUE)) install.packages("rmarkdown")
if (!requireNamespace("tinytex",   quietly = TRUE)) install.packages("tinytex")
if (!tinytex::is_tinytex()) tinytex::install_tinytex()

# knit_root_dir = getwd() so LaTeX \includegraphics paths like
# "www/alliance_logo.png" resolve from the project root, not from
# doc/ where the .Rmd lives.
rmarkdown::render(
  "doc/methodology.Rmd",
  output_format = "pdf_document",
  output_file   = "../www/methodology.pdf",
  knit_root_dir = getwd()
)
cat("Done — www/methodology.pdf created.\n")
