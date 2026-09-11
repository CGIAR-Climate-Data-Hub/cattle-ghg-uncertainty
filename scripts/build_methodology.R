# Run from project root: Rscript scripts/build_methodology.R
# Self-correcting if invoked from inside scripts/.
if (basename(getwd()) == "scripts") setwd("..")

# The "what the defaults assume" block is generated from DEFAULT_BASIS
# and \input{} by both guides. Rebuild it first so a guide can never be
# rendered against a stale basis table.
source("scripts/build_basis_block.R")


if (!requireNamespace("rmarkdown", quietly = TRUE)) install.packages("rmarkdown")

# LaTeX engine: prefer whatever is already installed (MiKTeX / TeX Live / TinyTeX).
# R child-process PATH often omits MiKTeX even when the shell has it, so add the
# usual Windows install dir before probing. Only fall back to installing TinyTeX
# if NO engine is found at all. The previous is_tinytex() guard tried to install
# TinyTeX on a machine that already had MiKTeX and errored out, which is why this
# script could not be run. Same approach as build_user_guide.R.
tb <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs/MiKTeX/miktex/bin/x64")
if (dir.exists(tb)) Sys.setenv(PATH = paste(tb, Sys.getenv("PATH"), sep = .Platform$path.sep))
if (!nzchar(Sys.which("pdflatex")) && !nzchar(Sys.which("xelatex"))) {
  if (!requireNamespace("tinytex", quietly = TRUE)) install.packages("tinytex")
  if (!tinytex::is_tinytex()) tinytex::install_tinytex()
}

# knit_root_dir = getwd() so LaTeX \includegraphics paths like
# "www/alliance_logo.png" resolve from the project root, not from
# doc/ where the .Rmd lives.
# Build BOTH formats. www/methodology.docx is served alongside the PDF and was
# previously left to drift because this script only rendered the PDF.
for (fmt in c("word_document", "pdf_document")) {
  ext <- if (fmt == "word_document") "docx" else "pdf"
  rmarkdown::render(
    "doc/methodology.Rmd",
    output_format = fmt,
    output_file   = paste0("../www/methodology.", ext),
    knit_root_dir = getwd()
  )
}
cat("Done — www/methodology.pdf created.\n")
