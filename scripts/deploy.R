# Run from project root: Rscript scripts/deploy.R
if (basename(getwd()) == "scripts") setwd("..")

# ---------------------------------------------------------------------------
# Deploy gate (2026-09-17, plan B7). Three things must hold before a bundle
# is uploaded; each has bitten once.
#
#  1. The audit passes. It includes F46, which fails when the translator's
#     generated prompt files no longer match the defaults master or the
#     template layout, i.e. when scripts/build_translator_kit.R was not
#     re-run after a change to either.
#  2. The working tree is clean. rsconnect bundles the WORKING TREE, not the
#     commit, so uncommitted edits would go live unrecorded.
#  3. Nothing in translator_prompts/ or www/ is modified or untracked: a
#     regenerated prompt that was not committed would ship without a trace.
#
# Set DEPLOY_SKIP_GATE=1 to bypass, and say why in the commit that follows.
# ---------------------------------------------------------------------------
if (!identical(Sys.getenv("DEPLOY_SKIP_GATE", ""), "1")) {
  rs <- file.path(R.home("bin"), "Rscript")
  audit <- suppressWarnings(system2(rs, "scripts/audit.R", stdout = TRUE, stderr = TRUE))
  fails <- grep("Fail: *[1-9]", audit, value = TRUE)
  if (length(fails) || !any(grepl("AUDIT COMPLETE", audit, fixed = TRUE))) {
    cat(tail(audit, 25), sep = "\n")
    stop("deploy gate: the audit did not pass. Fix it, or set DEPLOY_SKIP_GATE=1 and record why.",
         call. = FALSE)
  }
  status <- tryCatch(system2("git", c("status", "--porcelain"), stdout = TRUE, stderr = FALSE),
                     error = function(e) character(0))
  status <- status[nzchar(trimws(status))]
  # OneDrive re-stamps Office files with SharePoint metadata within a minute
  # of any checkout or build (the audit above takes longer than that), which
  # made the gate refuse three deploys on 2026-09-21 over www/user_guide.docx
  # whose document text had not changed. A modified .docx whose
  # word/document.xml equals the committed one is restored and not counted.
  docx_mod <- status[grepl("^ M .*[.]docx$", status)]
  for (line in docx_mod) {
    path <- trimws(sub("^ M ", "", line))
    same <- tryCatch({
      td <- tempfile(); dir.create(td)
      head_copy <- file.path(td, "head.docx")
      system2("git", c("show", shQuote(paste0("HEAD:", path))), stdout = head_copy, stderr = FALSE)
      a <- unzip(path, "word/document.xml", exdir = file.path(td, "a"))
      b <- unzip(head_copy, "word/document.xml", exdir = file.path(td, "b"))
      identical(readBin(a, "raw", file.size(a)), readBin(b, "raw", file.size(b)))
    }, error = function(e) FALSE)
    if (isTRUE(same)) {
      system2("git", c("checkout", "--", shQuote(path)), stdout = FALSE, stderr = FALSE)
      message("deploy gate: ", path, " differed only in OneDrive metadata; restored.")
      status <- setdiff(status, line)
    }
  }
  if (length(status)) {
    cat(status, sep = "\n")
    stop("deploy gate: the working tree is not clean; commit or stash first.", call. = FALSE)
  }
  message("deploy gate: audit clean, working tree clean.")
}

# Notify any newly-approved users (diff config/approved_users.csv against
# the local snapshot, send a SendGrid welcome to each new email). This
# runs BEFORE the deploy so the welcome arrives at the moment the user
# is approved, not after the deploy finishes. Best-effort — failures
# don't block the deploy.
tryCatch(source("scripts/notify_approved.R"),
         error = function(e) message("notify_approved skipped: ",
                                       conditionMessage(e)))

rsconnect::deployApp(
  appDir      = ".",
  appName     = "cattle-ghg-uncertainty",
  account     = "mlolita26",
  forceUpdate = TRUE,
  launch.browser = FALSE
  # 2026-06 note: shinyapps.io does NOT support the rsconnect `envVars`
  # argument (that's a Posit Connect feature). Instead, secrets are shipped
  # via a `.Renviron` file in the app root, which R reads on startup. The
  # file is gitignored (never enters git history) but is NOT in .rscignore
  # so it gets bundled into the deploy. Rotate keys by editing the local
  # .Renviron and re-deploying.
)
