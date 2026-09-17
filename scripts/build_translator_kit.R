# =============================================================================
# Build the knowledge files for the in-app GMH Uncertainty Translator
# =============================================================================
# Reads PARAM_CATALOGUE, PARAM_ALIASES, MMS_DEFAULTS and controlled vocabularies
# from the live R source and emits Markdown knowledge files into
# translator_prompts/. These .md files are concatenated at runtime by
# R/openai_client.R::assemble_translator_system_prompt() into the system
# prompt sent to Anthropic Claude (see R/anthropic_client.R; the "GPT-4.1"
# in older comments here is stale).
#
# Usage (from project root):
#   Rscript scripts/build_translator_kit.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

# --- Regeneration is safe -----------------------------------------------------
#
# This script was frozen between 2026-09-10 and 2026-09-11 because it destroyed
# hand-added prompt content on every run. It no longer does. Every factual table
# in the generated files is now built from the R constants, and the prose that
# used to be hand-edited into the output lives in translator_prompts/partials/
# and is read back in. A missing partial is a hard error rather than a silently
# shorter prompt.
#
# Rule for maintainers: NEVER hand-edit translator_prompts/param_catalogue.md or
# template_schema.md. Change the R constants for numbers, or the partials for
# prose, then re-run this script.
# -----------------------------------------------------------------------------

suppressMessages({
  # load_defaults.R MUST come first: it reads reference/defaults_master.csv and
  # defines .master_wide()/.master_list(), which utils_template.R and
  # utils_ipcc_defaults.R call at source time to build their constants. The app
  # gets this free by sourcing R/ alphabetically; this script names its files,
  # so it has to name this one too. Omitting it broke the generator silently
  # when the master migration landed, and nothing caught it because the kit
  # build was not in the audit. Audit check F34 now is.
  source("R/load_defaults.R", local = FALSE)
  source("R/utils_template.R", local = FALSE)
  source("R/utils_validation.R", local = FALSE)
  source("R/utils_ipcc_defaults.R", local = FALSE)
})

out_dir <- "translator_prompts"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ---------------------------------------------------------------------------
# 1-2. The generated knowledge files.
#
# 2026-09-17: the generators moved to R/translator_prompt_build.R, and the
# app calls the SAME functions at runtime, so what the model reads in the app
# can no longer differ from what this script writes. This script now exists
# for the DIY kit, for review diffs of the generated files, and to write the
# manifest that audit check F46 and scripts/deploy.R compare against the
# defaults master. Prose still lives in translator_prompts/partials/.
# ---------------------------------------------------------------------------
source("R/translator_prompt_build.R", local = FALSE)
pc <- PARAM_CATALOGUE
NPAR <- nrow(pc)

lines <- build_param_catalogue_md(file.path(out_dir, "partials"))
writeLines(lines, file.path(out_dir, "param_catalogue.md"), useBytes = TRUE)
message("✓ wrote param_catalogue.md (", NPAR, " parameters)")

lines <- build_template_schema_md(file.path(out_dir, "partials"))
writeLines(lines, file.path(out_dir, "template_schema.md"), useBytes = TRUE)
message("✓ wrote template_schema.md")

we <- build_worked_example_md(file.path(out_dir, "partials"))
writeLines(we, file.path(out_dir, "worked_example.md"), useBytes = TRUE)
message("✓ wrote worked_example.md (", length(.WE_SUBCATS), " sub-cats x ", NPAR, " params)")

# The hand-written files carry {{placeholders}} that the app fills at
# runtime. The DIY-kit copies must be filled here, so a kit user pastes real
# numbers into their Claude Project. Written to www/ only; the canonical
# translator_prompts/ copies keep their placeholders.
fill_for_kit <- function(f) {
  # Same treatment the app gives the file: maintainer HTML comments out,
  # placeholders filled from the live objects.
  txt <- paste(.tp_strip_html_comments(
    readLines(file.path(out_dir, f), warn = FALSE, encoding = "UTF-8")), collapse = "
")
  translator_prompt_fill_placeholders(txt)
}

# Manifest (plan B3): hashes of the master, the template layout and each
# generated file. F46 fails when the master or layout hash no longer matches
# what the live objects produce, i.e. when this script needs re-running.
manifest <- translator_prompt_manifest(out_dir)
manifest$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
jsonlite::write_json(manifest, file.path(out_dir, ".manifest.json"),
                     auto_unbox = TRUE, pretty = TRUE)
message("✓ wrote .manifest.json (master ", substr(manifest$master_sha256, 1, 8),
        ", layout ", substr(manifest$layout_sha256, 1, 8), ")")

# ---------------------------------------------------------------------------
# 3. Stage user-facing assets into www/ so the Shiny app can serve them.
# Only the files end-users need to download go to www/ — system_instructions.md
# and the README stay in translator_prompts/ for the maintainer.
# ---------------------------------------------------------------------------
www_dir <- "www"
if (!dir.exists(www_dir)) dir.create(www_dir, recursive = TRUE)
# system_instructions.md is staged too — users paste it into the "Instructions"
# field of their own Claude Project (DIY-kit flow). The other four .md files
# are the project knowledge.
# worked_example.md is 5th in the live system prompt (openai_client.R:32-34) but
# was historically absent from both www/ and the kit, so DIY-kit users ran a
# materially different translator from the in-app one. Ship it.
user_facing <- c("system_instructions.md",
                 "questionnaire.md", "getting_started.md",
                 "param_catalogue.md", "template_schema.md",
                 "mapping_examples.md", "worked_example.md")
hand_written <- c("system_instructions.md", "mapping_examples.md", "questionnaire.md",
                  "getting_started.md")
for (f in user_facing) {
  src <- file.path(out_dir, f)
  dst <- file.path(www_dir, f)
  if (!file.exists(src)) next
  if (f %in% hand_written) writeLines(fill_for_kit(f), dst, useBytes = TRUE)
  else file.copy(src, dst, overwrite = TRUE)
}
message("✓ staged ", length(user_facing), " files into ", www_dir, "/")

# ---------------------------------------------------------------------------
# 3b. Render the user-facing .Rmd files (getting_started.Rmd, questionnaire.Rmd)
# to PDF + DOCX via rmarkdown::render(). The .Rmd files carry the same polished
# CGIAR-green LaTeX styling as user_guide.Rmd and methodology.Rmd. Outputs are
# staged in translator_prompts/ (canonical) and copied to www/ (served by
# Shiny). Needs: `rmarkdown` package + a LaTeX install (MiKTeX/TinyTeX) for
# pdflatex.
# ---------------------------------------------------------------------------
# Locate a LaTeX engine. R's child-process PATH doesn't always include
# MiKTeX/TinyTeX even when the shell does, so we also check the usual Windows
# install dirs.
find_xelatex <- function() {
  hit <- Sys.which("xelatex")
  if (nzchar(hit) && file.exists(hit)) return(unname(hit))
  candidates <- c(
    file.path(Sys.getenv("LOCALAPPDATA"),
              "Programs/MiKTeX/miktex/bin/x64/xelatex.exe"),
    file.path(Sys.getenv("APPDATA"),
              "TinyTeX/bin/windows/xelatex.exe"),
    "C:/Program Files/MiKTeX/miktex/bin/x64/xelatex.exe",
    "C:/texlive/2024/bin/windows/xelatex.exe",
    "/usr/bin/xelatex", "/usr/local/bin/xelatex"
  )
  for (p in candidates) if (file.exists(p)) return(p)
  ""
}

xelatex_bin <- find_xelatex()
if (nzchar(xelatex_bin)) {
  Sys.setenv(PATH = paste(dirname(xelatex_bin), Sys.getenv("PATH"),
                           sep = .Platform$path.sep))
  message("  (LaTeX engine at ", xelatex_bin, ")")
}

if (requireNamespace("rmarkdown", quietly = TRUE)) {
  to_render <- c("getting_started.Rmd", "questionnaire.Rmd")
  for (rmd in to_render) {
    src <- file.path(out_dir, rmd)
    if (!file.exists(src)) next
    for (fmt in c("pdf_document", "word_document")) {
      out <- tryCatch(
        rmarkdown::render(src, output_format = fmt,
                          quiet = TRUE, envir = new.env()),
        error = function(e) {
          message("✗ ", rmd, " → ", fmt,
                  " failed: ", conditionMessage(e))
          NULL
        })
      if (!is.null(out) && file.exists(out)) {
        file.copy(out, file.path(www_dir, basename(out)), overwrite = TRUE)
        message("✓ ", basename(out), "  (",
                file.info(out)$size, " bytes)")
      }
    }
  }
} else {
  message("(rmarkdown package not installed — ",
          "install.packages('rmarkdown') to enable styled PDF/DOCX.)")
}

# ---------------------------------------------------------------------------
# 3c. Build translator_kit.zip — the bundle users download to set up their
# OWN Claude Project (DIY-kit flow). Public sharing of Claude Projects is
# limited on personal accounts, so instead of pointing users at a shared
# project URL we ship them everything they need to recreate it on their
# own claude.ai account in ~2 minutes.
#
# Zip contents:
#   README.txt              — one-page quick-start (created here, inline)
#   getting_started.pdf     — the polished step-by-step with screenshots
#   system_instructions.md  — paste into the Project's "Instructions" field
#   param_catalogue.md      ┐
#   template_schema.md      │ upload as Project "Files" (knowledge base)
#   mapping_examples.md     │
#   questionnaire.md        ┘
#   questionnaire.docx      — the fillable form the user pastes per chat
# ---------------------------------------------------------------------------
kit_files <- c("system_instructions.md", "param_catalogue.md",
               "template_schema.md", "mapping_examples.md",
               "worked_example.md",
               "questionnaire.md", "questionnaire.docx",
               "getting_started.pdf")
kit_files_present <- kit_files[file.exists(file.path(out_dir, kit_files))]

# Inline README.txt — gives the user the 5-step recipe at a glance.
readme_lines <- c(
  "GMH UNCERTAINTY TRANSLATOR — DIY KIT",
  "=====================================",
  "",
  "WHAT THIS IS",
  "------------",
  "A free AI helper that turns your raw cattle inventory data (Excel/CSV)",
  "into the input template expected by the Cattle Uncertainty App. The",
  "kit lets you set up your OWN Translator on claude.ai in about 2",
  "minutes — no payment, no installation.",
  "",
  "QUICK-START (5 STEPS)",
  "---------------------",
  "1. Sign up for a free account at https://claude.ai (Google / email / Apple).",
  "",
  "2. In the left sidebar, click 'Projects' then 'Create project'.",
  "   Name it 'GMH Uncertainty Translator' (or anything you like).",
  "",
  "3. Open the project and find the 'Instructions' field (top right).",
  "   Open `system_instructions.md` from this kit in any text editor,",
  "   select all, copy, and paste the contents into that field. Save.",
  "",
  "4. Below the Instructions field is a 'Files' panel. Drag-and-drop",
  "   these four files into it:",
  "      - param_catalogue.md",
  "      - template_schema.md",
  "      - mapping_examples.md",
  "      - questionnaire.md",
  "",
  "5. Open `questionnaire.docx`, fill it in (country, year, sub-categories,",
  "   manure systems, etc. — about 2 minutes). Then start a new chat in",
  "   your Project, paste the filled questionnaire as the first message,",
  "   and follow the conversation. Claude will ask you to upload your",
  "   data file(s) next.",
  "",
  "For the full walkthrough with screenshots, open getting_started.pdf",
  "in this kit.",
  "",
  ""
)
writeLines(readme_lines, file.path(out_dir, "README.txt"), useBytes = TRUE)
kit_files_present <- c("README.txt", kit_files_present)

zip_path <- normalizePath(file.path(www_dir, "translator_kit.zip"),
                           winslash = "/", mustWork = FALSE)
if (file.exists(zip_path)) file.remove(zip_path)

# Build the zip with paths flattened (no translator_prompts/ prefix inside
# the archive). Switch into out_dir so the file names in the archive match the
# short names the README references.
# Filled copies of the hand-written files live in www/; stage them into a
# temporary kit folder together with the generated files so the archive
# carries no unfilled placeholder.
kit_dir <- tempfile("translator_kit_"); dir.create(kit_dir)
for (f in kit_files_present) {
  from <- if (f %in% hand_written && file.exists(file.path(www_dir, f))) file.path(www_dir, f)
          else file.path(out_dir, f)
  file.copy(from, file.path(kit_dir, f), overwrite = TRUE)
}
old_wd <- getwd()
setwd(kit_dir)
zip_ok <- tryCatch({
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(zipfile = zip_path, files = kit_files_present,
             mode = "cherry-pick")
  } else {
    utils::zip(zipfile = zip_path, files = kit_files_present,
               flags = "-q9X")
  }
  TRUE
}, error = function(e) {
  message("  zip build failed: ", conditionMessage(e))
  FALSE
})
setwd(old_wd)
zip_ok <- zip_ok && file.exists(zip_path)

if (zip_ok) {
  message("✓ translator_kit.zip  (",
          file.info(zip_path)$size, " bytes, ",
          length(kit_files_present), " files)")
} else {
  message("✗ translator_kit.zip — neither zip::zip nor utils::zip worked. ",
          "install.packages('zip') and try again.")
}

# ---------------------------------------------------------------------------
# 4. Quick smoke-check
# ---------------------------------------------------------------------------
message("\nFiles in ", out_dir, "/:")
for (f in list.files(out_dir, full.names = TRUE))
  message("  ", basename(f), "  (", file.info(f)$size, " bytes)")

invisible(NULL)
