# Render the beta-test feedback guide to PDF + DOCX, in place, from its source.
# Run from the repo root:  Rscript feedback_workflow/_build_feedback_guide.R
# (The feedback guide is NOT part of the AI-translator kit, so it is built here
#  rather than by scripts/build_translator_kit.R.)
suppressWarnings(suppressMessages(library(rmarkdown)))

# Put a LaTeX engine on PATH for pdflatex (R's child PATH often omits MiKTeX/TinyTeX).
h <- Sys.which("pdflatex"); if (!nzchar(h)) h <- Sys.which("xelatex")
tb <- if (nzchar(h)) dirname(h) else file.path(Sys.getenv("LOCALAPPDATA"),
                                                "Programs/MiKTeX/miktex/bin/x64")
if (dir.exists(tb)) Sys.setenv(PATH = paste(tb, Sys.getenv("PATH"), sep = .Platform$path.sep))

src <- "feedback_workflow/feedback_guide.Rmd"
if (!file.exists(src)) stop("Not found: ", src, " — run from the repo root.")
for (fmt in c("word_document", "pdf_document")) {
  out <- tryCatch(rmarkdown::render(src, output_format = fmt, quiet = TRUE, envir = new.env()),
                  error = function(e) { message("FAILED ", fmt, ": ", conditionMessage(e)); NULL })
  if (!is.null(out) && file.exists(out))
    cat("Built:", basename(out), "(", file.info(out)$size, "bytes )\n")
}
