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