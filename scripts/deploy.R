# Run from project root: Rscript scripts/deploy.R
if (basename(getwd()) == "scripts") setwd("..")

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