suppressMessages({
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
})
i18n_set_lang("fr")
cat(sprintf("FR Bo definition: %s\n",
            substr(.PARAM_DEFINITIONS_FR[["Bo"]], 1, 60)))
cat(sprintf("FR unit for hours: %s\n", .PARAM_UNITS_FR[["hours"]]))
cat(sprintf("FR framing AD: %s\n", t("def_framing_ad")))
cat(sprintf("FR framing coef: %s\n", t("def_framing_coef")))
cat(sprintf("FR tier core: %s\n", t("def_tier_core")))
cat(sprintf("FR col Variable name: %s\n", t("def_col_variable")))
i18n_set_lang("en")
cat(sprintf("EN col Variable name: %s\n", t("def_col_variable")))
