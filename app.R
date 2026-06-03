# IPCC Tier 2 Livestock GHG Uncertainty Calculator
# Developed by CIAT/CGIAR Alliance | Funded by Global Methane Hub

# Source all R files
r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
for (f in sort(r_files)) source(f, local = TRUE)

# Required packages
library(shiny)
library(bslib)
library(shinyWidgets)
library(DT)
library(readxl)
library(writexl)
library(plotly)
library(ggplot2)
library(MASS)
library(mc2d)
library(Matrix)
library(future)
library(promises)
# Round 6b: Word run-summary export
library(officer)
library(flextable)
# Round 8 contact form posts client-side to Web3Forms (no server-side libs needed)
# 2026-06: in-app AI translator — OpenAI API client + magic-link auth
library(httr2)
library(jsonlite)

# Launch app
shinyApp(ui = app_ui(), server = app_server)
