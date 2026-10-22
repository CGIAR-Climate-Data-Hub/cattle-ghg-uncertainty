# Usage: Rscript scripts/translator_prompt_view.R   (developer side, no API call)
#
# Writes reports/translator_prompt_<hash8>.md: the system prompt exactly as
# the app sends it, its hash, the discovery request and a sample batch
# request with a sample decisions block, and what changed in
# translator_prompts/ since the June restore point (9110134). This is how a
# failing output is read against the instructions that produced it
# (2026-10-22, WP8). Not served by the app.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
if (!dir.exists("reports")) dir.create("reports")
prompt <- assemble_translator_system_prompt()
h <- translator_system_prompt_hash()
reg <- translator_register_set_user(list(), "inventory_year", "2022", quote = "year 2022")
reg <- translator_register_set_user(reg, "calves_handling", "pooled", quote = "keep calves together")
reg <- translator_register_merge(reg, list(list(topic = "mms_split_source", decision = "herd-wide, from the MMS sheet",
                                               basis = "file", confidence = "low", quote = "")), 5L)
git <- function(...) tryCatch(paste(system2("git", c(...), stdout = TRUE, stderr = TRUE), collapse = "\n"),
                              error = function(e) "(git not available)")
out <- c(
  sprintf("# Translator prompt %s", substr(h, 1, 8)),
  "",
  sprintf("Assembled %s. Model: %s. Prompt hash: %s. Master hash: %s.",
          format(Sys.time(), "%Y-%m-%d %H:%M"), .ANTHROPIC_DEFAULT_MODEL, h,
          tryCatch(translator_prompt_inputs_hash()$master_sha256, error = function(e) "unknown")),
  "",
  "## Changes to translator_prompts/ and the in-app rules since 9110134 (30 June 2026)",
  "",
  "```", git("diff", "--stat", "9110134", "HEAD", "--", "translator_prompts/", "R/openai_client.R"), "```",
  "",
  "```", git("log", "--date=short", "--format=%h|%ad|%s", "9110134..HEAD", "--", "translator_prompts/", "R/openai_client.R"), "```",
  "",
  "See translator_prompts/CHANGELOG.md for the reasons.",
  "",
  "## Discovery request (what the server appends for the enumerate call)",
  "",
  "```", .translator_discovery_request(reg), "```",
  "",
  "## Batch request (sample, system 1 of 3)",
  "",
  "```", .translator_batch_nudge(1L, 3L, "commercial_dairy", reg), "```",
  "",
  "## System prompt, as sent",
  "",
  prompt)
path <- file.path("reports", sprintf("translator_prompt_%s.md", substr(h, 1, 8)))
writeLines(out, path, useBytes = TRUE)
cat("written:", path, "(", nchar(prompt), "prompt characters )\n")
