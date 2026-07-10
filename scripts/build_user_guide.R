# Build www/user_guide.pdf + www/user_guide.docx from doc/user_guide.Rmd.
# Run from project root:
#   Rscript scripts/build_user_guide.R
#
# Self-correcting if invoked from inside scripts/.

if (basename(getwd()) == "scripts") setwd("..")

if (!requireNamespace("rmarkdown", quietly = TRUE)) install.packages("rmarkdown")

# LaTeX engine: prefer whatever is already installed (MiKTeX / TeX Live / TinyTeX).
# R's child-process PATH often omits MiKTeX even when the shell has it, so add the
# usual Windows install dir before probing (same approach as build_translator_kit.R).
# Only fall back to installing TinyTeX if NO engine is found at all — otherwise
# tinytex::install_tinytex() errors out when a system LaTeX like MiKTeX exists.
tb <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs/MiKTeX/miktex/bin/x64")
if (dir.exists(tb)) Sys.setenv(PATH = paste(tb, Sys.getenv("PATH"), sep = .Platform$path.sep))
if (!nzchar(Sys.which("pdflatex")) && !nzchar(Sys.which("xelatex"))) {
  if (!requireNamespace("tinytex", quietly = TRUE)) install.packages("tinytex")
  if (!tinytex::is_tinytex()) tinytex::install_tinytex()
}

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
