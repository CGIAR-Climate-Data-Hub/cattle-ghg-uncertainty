# Generate the LaTeX "what the defaults assume" block for both guides, from
# DEFAULT_BASIS. Written to a file and spliced into the .Rmd between markers,
# so the guides stay in step with the master without being hand-edited.
suppressMessages({
  for (f in list.files("R", pattern = "[.]R$", full.names = TRUE))
    if (!grepl("^_", basename(f))) source(f)
})

esc <- function(x) {
  x <- gsub("\\", "\\textbackslash{}", x, fixed = TRUE)
  for (ch in c("&", "%", "$", "#", "_", "{", "}"))
    x <- gsub(ch, paste0("\\", ch), x, fixed = TRUE)
  gsub("<=", "$\\leq$", gsub(">=", "$\\geq$", x, fixed = TRUE), fixed = TRUE)
}

lines <- c(
"% BEGIN GENERATED: default basis (scripts/build_basis_block.R). Do not edit.",
"\\subsection{What the defaults assume}",
"",
"Every IPCC default this tool ships is one cell of a much larger table. Reaching it means choosing a region, a productivity class, a climate and, for manure, a specific system variant. Those choices are listed below. \\textbf{Where a choice does not describe the herd being reported, the parameters it governs must be replaced with country-specific values.}",
"",
"\\renewcommand{\\arraystretch}{1.25}",
"\\begin{small}",
"\\begin{longtable}{p{2.4cm} p{3.4cm} p{3.6cm} p{5.6cm}}",
"\\toprule",
"\\textbf{Choice} & \\textbf{This tool uses} & \\textbf{IPCC also publishes} & \\textbf{Affects, and what to do otherwise} \\\\",
"\\midrule",
"\\endhead")

for (i in seq_len(nrow(DEFAULT_BASIS))) {
  lb <- DEFAULT_BASIS_LABELS[[DEFAULT_BASIS$dimension[i]]]
  if (is.null(lb)) lb <- DEFAULT_BASIS$dimension[i]
  gov <- gsub(" ", ", ", DEFAULT_BASIS$governs[i], fixed = TRUE)
  lines <- c(lines, sprintf(
    "\\textbf{%s} & %s & %s & \\texttt{%s}. %s \\\\ \\addlinespace[2pt]",
    esc(lb), esc(DEFAULT_BASIS$chosen[i]), esc(DEFAULT_BASIS$alternatives[i]),
    esc(gov), esc(DEFAULT_BASIS$why[i])))
}

lines <- c(lines,
"\\bottomrule",
"\\end{longtable}",
"\\end{small}",
"",
"\\texttt{MCF}, \\texttt{EF3} and \\texttt{FRAC} above are the per-manure-system coefficient families rather than catalogue parameters.",
"",
"\\subsubsection{Which IPCC variant each manure system models}",
"",
"IPCC splits several manure systems into variants whose coefficients differ substantially. Liquid slurry with a natural crust emits less methane and volatilises less nitrogen than the same slurry without one, and composting in a static pile is not the same system as composting in a vessel. This tool carries \\textbf{one row per manure system}, and every coefficient on that row (the methane conversion factor, the direct N\\textsubscript{2}O emission factor, and the volatilisation and leaching fractions) is read from the single IPCC variant named below, so the row describes a real system rather than a blend. \\textbf{A herd running a different variant must override the coefficients on that row.}",
"",
"\\begin{small}",
"\\begin{longtable}{p{4.2cm} p{10.5cm}}",
"\\toprule",
"\\textbf{Manure system} & \\textbf{IPCC variant modelled} \\\\",
"\\midrule",
"\\endhead")

for (i in seq_len(nrow(MMS_DEFAULTS))) {
  lines <- c(lines, sprintf("\\texttt{%s} & %s \\\\ \\addlinespace[2pt]",
                            esc(MMS_DEFAULTS$id[i]),
                            esc(MMS_DEFAULTS$ipcc_variant[i])))
}

lines <- c(lines,
"\\bottomrule",
"\\end{longtable}",
"\\end{small}",
"",
"% END GENERATED: default basis")

writeLines(lines, "doc/_basis_block.tex", useBytes = TRUE)
cat("wrote doc/_basis_block.tex (", length(lines), " lines,",
    nrow(DEFAULT_BASIS), "choices )\n")
