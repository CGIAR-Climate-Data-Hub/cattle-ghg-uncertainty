# Build www/user_guide.pdf + www/user_guide.docx from doc/user_guide.Rmd.
# Run from project root:
#   Rscript scripts/build_user_guide.R
#
# Self-correcting if invoked from inside scripts/.

if (basename(getwd()) == "scripts") setwd("..")

if (!requireNamespace("rmarkdown", quietly = TRUE)) install.packages("rmarkdown")
if (!requireNamespace("tinytex",   quietly = TRUE)) install.packages("tinytex")
if (!tinytex::is_tinytex()) tinytex::install_tinytex()

# knit_root_dir = getwd() so the .Rmd's relative paths to www/ logos
# resolve from the project root, not from doc/.
for (fmt in c("word_document", "pdf_document")) {
  ext <- if (fmt == "word_document") "docx" else "pdf"
  rmarkdown::render(
    "doc/user_guide.Rmd",
    output_format = fmt,
    output_file   = paste0("../www/user_guide.", ext),
    knit_root_dir = getwd(),
    quiet         = TRUE
  )
  cat("Done — www/user_guide.", ext, " created.\n", sep = "")
}
