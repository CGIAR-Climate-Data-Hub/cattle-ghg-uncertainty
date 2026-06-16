# Master Server Function
app_server <- function(input, output, session) {

  # Reactive values
  rv <- reactiveValues(
    param_specs = NULL,
    inv_metadata = NULL,
    manure_data = NULL,
    population = NULL,
    corr_matrix = NULL,
    ef_corr_matrix = NULL,
    mc_results = NULL,
    uncertainty = NULL,
    decomposition = NULL,
    sensitivity = NULL,
    ipcc_table = NULL,
    sim_log = "",
    sim_running = FALSE,
    sim_error = NULL,
    comparison_result = NULL,
    comparison_sensitivity = NULL,
    diagnostics      = NULL,
    show_diagnostics = FALSE,
    upload_status = NULL,   # NULL | list(type = "success"|"error", message = "...")
    has_custom_upload = FALSE,
    # 2026-06 Andreas review: gate the corr_mode radio so users can't pick a
    # mode whose underlying matrix is empty. ts_available is TRUE when the
    # current dataset (example or upload) has a populated Parameter_TimeSeries
    # sheet that compute_corr_from_population() could turn into a matrix.
    # manual_uploaded is TRUE once the user has uploaded a CSV correlation
    # matrix via corr_matrix_upload (reset to FALSE on any new template load).
    ts_available     = FALSE,
    manual_uploaded  = FALSE,
    sim_view = "settings"   # R1.5: "settings" or "results" — drives Tab 5 panel toggle
  )

  # B4: Home page Resources link — switch to the Resources tab AND scroll to
  # the Tool-specific resources card (id="downloads-card" in app_ui.R) so the
  # methodology/user-guide download buttons are in view immediately. The JS
  # handler in app_ui.R wraps scrollIntoView in setTimeout(150ms) to give the
  # newly-activated tab a tick to render before we try to scroll to it.
  observeEvent(input$goto_resources, {
    bslib::nav_select(id = "nav", selected = "Resources", session = session)
    session$sendCustomMessage("scrollTo", "downloads-card")
  })

  # --- DATA INPUT ---

  # T1.1 fix: when the user has a custom upload loaded and re-touches the country
  # dropdown, ask before overwriting. Otherwise load the example silently.
  observeEvent(input$country, {
    if (!input$country %in% c("country_x", "country_y")) return()  # "custom" is a no-op
    if (isTRUE(rv$has_custom_upload)) {
      showModal(modalDialog(
        title = "Discard custom upload?",
        paste0("Loading the ",
               if (input$country == "country_x") "Country X" else "Country Y",
               " example will overwrite your uploaded data. Proceed?"),
        footer = tagList(
          modalButton("Keep my upload"),
          actionButton("confirm_load_example", "Load example",
                       class = "btn-warning")
        ),
        easyClose = TRUE
      ))
      return()
    }
    .load_example(input$country)
  })

  # Helper: load an example dataset
  # Helper: run ensure_completeness() immediately after loading any dataset so
  # the imputed-parameter flags are set before the user reaches Tab 2 or Tab 5.
  .apply_completeness <- function(region = NULL) {
    comp <- ensure_completeness(rv$param_specs, region = region)
    if (isTRUE(comp$valid) && length(comp$auto_filled) > 0) {
      rv$param_specs <- comp$param_specs
      .bump_unc_token()
    }
  }

  # Bump rv$param_specs_bulk_token to force a full re-render of the
  # uncertainty table (Tab 3). Call this AFTER every BULK replacement of
  # rv$param_specs (file load, example load, quickset apply/undo, etc.).
  # Do NOT call from cell-edit observers — those go through the
  # proxy_unc / replaceData path which preserves the user's search filter
  # and paging across edits.
  .bump_unc_token <- function() {
    rv$param_specs_bulk_token <-
      (isolate(rv$param_specs_bulk_token) %||% 0L) + 1L
  }

  # 2026-06: hardcode first-difference detrending. The user-facing "Treatment
  # of trends" selectInput was retired — the alternative options ("linear",
  # "none") were rarely the right call and not a choice an Excel-fluent
  # inventory compiler should be asked to make. compute_corr_from_population()
  # still accepts the parameter; we just don't surface it as a UI choice.
  .compute_corr_now <- function(pop) {
    if (is.null(pop)) return(NULL)
    compute_corr_from_population(pop, detrend = "first_diff")
  }

  .load_example <- function(name) {
    # T0.3 + B1: distinct example datasets per country selection.
    # Names "country_x" / "country_y" are abstract hypothetical countries
    # used only to illustrate the two contrasting production systems (dairy
    # smallholder vs pastoral non-dairy). No real-country attribution.
    if (name == "country_x") {
      rv$param_specs <- fill_bounds(generate_country_x_example())
      .bump_unc_token()
      # R2.2: built-in example now ships with synthetic 5-year time-series so
      # that Tab 4's "From template (auto)" correlation mode works without
      # requiring a separate Excel upload.
      rv$population  <- generate_country_x_timeseries()
      rv$corr_matrix <- .compute_corr_now(rv$population)
      # Manure-management allocation with 4 MMS types + per-MMS uncertainty so
      # the IPCC Table 3.3 EF column varies across N2O pathways (otherwise
      # every N2O row collapses to the same Nex-dominated MoE — looks like a
      # bug but is actually structural for single-MMS inventories).
      rv$manure_data <- generate_country_x_manure()
      rv$sim_log <- "Country X (hypothetical dairy smallholder) example data loaded — 12 parameters, dairy / cows; 4 MMS types (pasture / solid_storage / liquid_slurry / anaerobic_digester); 5-year synthetic time-series populated for correlation auto-mode.\n"
    } else if (name == "country_y") {
      rv$param_specs <- fill_bounds(generate_country_y_example())
      .bump_unc_token()
      rv$population  <- generate_country_y_timeseries()
      rv$corr_matrix <- .compute_corr_now(rv$population)
      rv$manure_data <- generate_country_y_manure()
      rv$sim_log <- "Country Y (hypothetical pastoral non-dairy) example data loaded — 11 parameters, non_dairy / breeding_cows; 2 MMS types (pasture / solid_storage); 5-year synthetic time-series populated for correlation auto-mode.\n"
    }
    # Flag any missing core parameters immediately so the Tab 1 notice appears
    # without needing to run the simulation first.
    .apply_completeness()
    rv$has_custom_upload <- FALSE
    # Built-in examples ship with synthetic time-series → ts_available = TRUE.
    # Any prior manual-matrix upload is implicitly discarded by the new dataset.
    rv$ts_available    <- !is.null(rv$corr_matrix)
    rv$manual_uploaded <- FALSE
    rv$upload_status     <- list(type = "success",
                                 message = sprintf("%s example loaded — %d parameters (with example time-series)",
                                   if (name == "country_x") "Country X" else "Country Y",
                                   nrow(rv$param_specs)))
  }

  observeEvent(input$confirm_load_example, {
    removeModal()
    .load_example(input$country)
  })

  # T1.1 fix: surface upload errors and successes visibly on Tab 1.
  # Previously errors only landed in rv$sim_log (Tab 5) — invisible to a user on Tab 1,
  # who would see the Country X example data still there and assume the upload silently failed.
  observeEvent(input$data_upload, {
    req(input$data_upload)
    fname <- input$data_upload$name
    tryCatch({
      parsed <- parse_uploaded_template(input$data_upload$datapath)

      if (is.null(parsed$param_specs) || nrow(parsed$param_specs) == 0)
        stop("No recognised parameters found in the Parameters sheet. ",
             "Check that parameter names match the expected list ",
             "(see the Vocab sheet of the template).")

      rv$param_specs    <- parsed$param_specs
      .bump_unc_token()
      rv$inv_metadata   <- parsed$metadata
      rv$manure_data    <- parsed$manure
      rv$population     <- parsed$population
      # 2026-06: only adopt the uploaded TS matrix when it's actually populated;
      # otherwise wipe rv$corr_matrix so a stale matrix from a previous upload
      # doesn't pretend the new dataset has TS data.
      rv$corr_matrix    <- parsed$corr_matrix   # may be NULL if TS sheet empty
      rv$ts_available   <- !is.null(parsed$corr_matrix)
      rv$manual_uploaded <- FALSE                # new template wipes prior manual matrix
      rv$has_custom_upload <- TRUE

      msg <- sprintf("%d parameters loaded from %s", nrow(parsed$param_specs), fname)
      if (!is.null(parsed$metadata) && nzchar(parsed$metadata$country %||% ""))
        msg <- paste0(msg, " (country: ", parsed$metadata$country, ")")
      if (!is.null(parsed$corr_matrix))
        msg <- paste0(msg, " — correlation matrix loaded from Parameter_TimeSeries (",
                      nrow(parsed$corr_matrix), " parameters)")

      # Flag missing core parameters immediately so Tab 1 shows the notice.
      region_upload <- if (!is.null(parsed$metadata) &&
                           nzchar(parsed$metadata$region %||% ""))
        parsed$metadata$region else NULL
      .apply_completeness(region = region_upload)

      rv$upload_status <- list(type = "success", message = msg)
      rv$sim_log <- paste0(rv$sim_log, "Custom data uploaded: ", msg, "\n")

      showNotification(msg, type = "message", duration = 6)

      if (length(parsed$warnings) > 0) {
        showNotification(paste("Upload warnings:",
                               paste(parsed$warnings, collapse = "; ")),
                         type = "warning", duration = 8)
      }
    }, error = function(e) {
      rv$upload_status <- list(type = "error",
                               message = paste0("Upload failed (", fname, "): ",
                                                e$message))
      rv$sim_log <- paste0(rv$sim_log, "Upload error: ", e$message, "\n")
      showNotification(paste0("Upload failed: ", e$message),
                       type = "error", duration = 10)
    })
  })

  # Parameter data table — R1.3: imputed rows rendered in red bold
  # Round 6b #4: add hover tooltip on imputed rows showing default + IPCC ref
  output$param_table <- DT::renderDT({
    req(rv$param_specs)
    ps <- rv$param_specs
    has_imputed <- "imputed" %in% names(ps) && any(isTRUE(ps$imputed) | ps$imputed == TRUE, na.rm = TRUE)

    options_list <- list(
      pageLength = 20,
      scrollX = TRUE,
      columnDefs = list(list(
        targets = which(names(ps) == "imputed") - 1,
        visible = FALSE))
    )

    if (has_imputed) {
      imputed_col <- which(names(ps) == "imputed") - 1L  # 0-based for JS
      options_list$rowCallback <- DT::JS(sprintf(
        "function(row, data) {
           if (data[%d] === true || data[%d] === 'TRUE' || data[%d] === 'true') {
             $(row).attr('title',
               'Auto-filled from IPCC default. Override in template if local data is available.');
           }
         }",
        imputed_col, imputed_col, imputed_col))
    }

    dt <- DT::datatable(ps,
                        options = options_list,
                        editable = TRUE, rownames = FALSE)
    if (has_imputed) {
      # Highlight imputed rows in red bold
      dt <- DT::formatStyle(dt, "imputed",
                            target = "row",
                            backgroundColor = DT::styleEqual(c(TRUE), c("#FECACA")),
                            color = DT::styleEqual(c(TRUE), c("#7F1D1D")),
                            fontWeight = DT::styleEqual(c(TRUE), c("bold")))
    }
    dt
  })

  # T3.2 / Round 6a #2: quick-set buttons toggle on / undo on second click.
  # On first click, snapshot current rows then apply the preset.
  # On second click, restore the snapshot and clear it. The button label flips
  # between the apply/undo wording in `quickset_normal_label` /
  # `quickset_pert_label` so the user can see which state it is in.
  observeEvent(input$set_all_normal, {
    req(rv$param_specs)
    if (!is.null(rv$quickset_normal_snapshot)) {
      rv$param_specs <- rv$quickset_normal_snapshot
      rv$quickset_normal_snapshot <- NULL
      showNotification("Reverted activity-data preset (restored previous values).",
                       type = "message", duration = 4)
    } else {
      rv$quickset_normal_snapshot <- rv$param_specs
      ad <- rv$param_specs$param_type == "activity_data"
      rv$param_specs$distribution[ad]    <- "normal"
      rv$param_specs$uncertainty_pct[ad] <- 15
      rv$param_specs <- fill_bounds(.recompute_bounds(rv$param_specs, which(ad)))
      showNotification("Set all activity-data parameters to Normal ±15% (click again to undo).",
                       type = "message", duration = 4)
    }
    .bump_unc_token()
  })
  observeEvent(input$set_all_pert, {
    req(rv$param_specs)
    if (!is.null(rv$quickset_pert_snapshot)) {
      rv$param_specs <- rv$quickset_pert_snapshot
      rv$quickset_pert_snapshot <- NULL
      showNotification("Reverted coefficient PERT preset (restored previous values).",
                       type = "message", duration = 4)
    } else {
      rv$quickset_pert_snapshot <- rv$param_specs
      ef <- rv$param_specs$param_type == "coefficient"
      rv$param_specs$distribution[ef] <- "pert"
      showNotification("Set all coefficients to PERT (click again to undo).",
                       type = "message", duration = 4)
    }
    .bump_unc_token()
  })

  # If the user edits the parameter table directly after applying a preset,
  # clear the snapshot so the next click is a fresh apply rather than an
  # accidental revert that would discard their edits.
  observeEvent(input$param_table_cell_edit, {
    rv$quickset_normal_snapshot <- NULL
    rv$quickset_pert_snapshot   <- NULL
  })
  observeEvent(input$uncertainty_table_cell_edit, {
    rv$quickset_normal_snapshot <- NULL
    rv$quickset_pert_snapshot   <- NULL
  })

  # Dynamic button labels (apply / undo) for the quick-set actions.
  output$quickset_normal_label <- renderText({
    if (!is.null(rv$quickset_normal_snapshot))
      "Undo: restore previous activity-data settings"
    else
      "Set all activity-data params to Normal ±15%"
  })
  outputOptions(output, "quickset_normal_label", suspendWhenHidden = FALSE)
  output$quickset_pert_label <- renderText({
    if (!is.null(rv$quickset_pert_snapshot))
      "Undo: restore previous coefficient settings"
    else
      "Set all coefficients to PERT"
  })
  outputOptions(output, "quickset_pert_label", suspendWhenHidden = FALSE)
  # Helper: recompute lower/upper from mean and uncertainty_pct for given rows
  .recompute_bounds <- function(ps, rows) {
    for (i in rows) {
      m   <- suppressWarnings(as.numeric(ps$mean[i]))
      pct <- suppressWarnings(as.numeric(ps$uncertainty_pct[i]))
      if (!is.na(m) && !is.na(pct)) {
        ps$lower[i] <- m * (1 - pct / 100)
        ps$upper[i] <- m * (1 + pct / 100)
      }
    }
    ps
  }

  # Edit parameter table in place — with bidirectional cascade (T1.8, T1.11a)
  # Edits to uncertainty_pct  -> recompute lower/upper from mean
  # Edits to lower or upper   -> recompute uncertainty_pct from the symmetric half-width
  # Edits to mean             -> recompute lower/upper from existing uncertainty_pct
  # Edits to distribution=constant -> zero uncertainty_pct, set lower=upper=mean
  observeEvent(input$param_table_cell_edit, {
    info     <- input$param_table_cell_edit
    cols     <- names(rv$param_specs)
    edit_col <- cols[info$col + 1]
    row      <- info$row

    # Apply the edit
    rv$param_specs[row, edit_col] <- DT::coerceValue(
      info$value, rv$param_specs[row, edit_col])

    ps   <- rv$param_specs
    mean <- suppressWarnings(as.numeric(ps$mean[row]))

    # Cascade rules
    if (edit_col == "distribution" && identical(ps$distribution[row], "constant")) {
      if ("uncertainty_pct" %in% cols) ps$uncertainty_pct[row] <- 0
      if ("lower" %in% cols)            ps$lower[row]            <- mean
      if ("upper" %in% cols)            ps$upper[row]            <- mean
    } else if (edit_col %in% c("uncertainty_pct", "mean") &&
               "uncertainty_pct" %in% cols && !is.na(mean)) {
      pct <- suppressWarnings(as.numeric(ps$uncertainty_pct[row]))
      if (!is.na(pct)) {
        if ("lower" %in% cols) ps$lower[row] <- mean * (1 - pct / 100)
        if ("upper" %in% cols) ps$upper[row] <- mean * (1 + pct / 100)
      }
    } else if (edit_col %in% c("lower", "upper") && !is.na(mean) && mean != 0 &&
               "uncertainty_pct" %in% cols) {
      lo <- suppressWarnings(as.numeric(ps$lower[row]))
      up <- suppressWarnings(as.numeric(ps$upper[row]))
      if (!is.na(lo) && !is.na(up)) {
        # Use symmetric half-width as the implied uncertainty_pct
        half <- ((up - lo) / 2) / mean * 100
        ps$uncertainty_pct[row] <- round(half, 2)
      }
    }

    rv$param_specs <- ps

    # Cross-tab sync: a Tab 1 edit should be reflected on Tab 3 the next
    # time the user looks at it, but WITHOUT discarding Tab 3's filter
    # state. Push the update via the Tab 3 proxy. (proxy_unc is defined
    # below where the Tab 3 renderDT lives — Shiny is fine with the
    # late binding because this observer fires after the session has
    # finished initialising.)
    if (exists("proxy_unc", inherits = TRUE)) {
      tryCatch(
        DT::replaceData(proxy_unc,
                         rv$param_specs[, .unc_visible_cols],
                         resetPaging = FALSE,
                         rownames    = FALSE),
        error = function(e) NULL)
    }
  })

  # Validation — surfaces upload status (success/failure) AND data validation errors
  output$validation_status <- renderUI({
    blocks <- list()
    # Show upload status banner if present (T1.1: makes upload errors visible)
    if (!is.null(rv$upload_status)) {
      cls <- if (rv$upload_status$type == "success") "validation-ok" else "validation-error"
      ic  <- if (rv$upload_status$type == "success") "check-circle" else "exclamation-triangle"
      blocks <- c(blocks, list(
        tags$div(class = cls, icon(ic), rv$upload_status$message)
      ))
    }
    if (is.null(rv$param_specs)) {
      blocks <- c(blocks, list(
        tags$div(class = "validation-error", icon("info-circle"),
                 "No data loaded. Select an example or upload a template.")
      ))
    } else {
      v <- validate_param_specs(rv$param_specs)
      if (v$valid) {
        blocks <- c(blocks, list(
          tags$div(class = "validation-ok", icon("check-circle"),
                   paste("Valid:", nrow(rv$param_specs), "parameters loaded"))
        ))
      } else {
        blocks <- c(blocks, list(
          tags$div(class = "validation-error", icon("exclamation-triangle"),
                   paste("Errors:", paste(v$errors, collapse = "; ")))
        ))
      }
    }
    do.call(tagList, blocks)
  })

  # --- QA/QC ---

  qaqc_result <- reactive({
    req(rv$param_specs)
    # G2: pass region from metadata for region-aware benchmark check
    region <- if (!is.null(rv$inv_metadata) && "region" %in% names(rv$inv_metadata) &&
                  nzchar(rv$inv_metadata$region %||% "")) {
      rv$inv_metadata$region
    } else "global"
    # Pass the Manure_Management sheet so cross-sheet sub-category-key
    # reconciliation (auto-match / ambiguous / no-match) surfaces in the same
    # QAQC table as the per-parameter checks (Andreas 28/5/26 follow-up).
    run_qaqc(rv$param_specs, region = region,
             manure_data = rv$manure_data)
  })

  # --- Auto-filled parameters card (Round 6b #4) ---
  imputed_rows <- reactive({
    ps <- rv$param_specs
    if (is.null(ps) || !"imputed" %in% names(ps)) return(NULL)
    flag <- ps$imputed
    flag[is.na(flag)] <- FALSE
    out <- ps[as.logical(flag), , drop = FALSE]
    if (nrow(out) == 0) return(NULL)
    out
  })

  output$has_imputed_params <- reactive({
    !is.null(imputed_rows())
  })
  outputOptions(output, "has_imputed_params", suspendWhenHidden = FALSE)

  output$imputed_params_card <- renderUI({
    rows <- imputed_rows()
    if (is.null(rows)) return(NULL)
    n <- nrow(rows)
    body_tmpl <- if (n == 1L) t("imputed_card_body_single") else t("imputed_card_body_plural")
    tagList(
      tags$p(sprintf(body_tmpl, n),
             style = "margin-bottom:8px; color:#92400E;"),
      DT::DTOutput("imputed_params_dt")
    )
  })

  output$imputed_params_dt <- DT::renderDT({
    rows <- imputed_rows()
    req(rows)

    cat_lookup <- PARAM_CATALOGUE[, c("parameter", "unit", "ipcc_ref")]
    names(cat_lookup)[2:3] <- c("unit_cat", "ipcc_ref_cat")
    rows <- merge(rows, cat_lookup, by = "parameter", all.x = TRUE, sort = FALSE)

    pick <- function(primary, fallback) {
      out <- primary
      missing <- is.na(out) | !nzchar(as.character(out))
      out[missing] <- fallback[missing]
      as.character(out)
    }
    unit_user <- if ("unit" %in% names(rows)) rows$unit else rep(NA_character_, nrow(rows))
    ref_user  <- if ("ipcc_ref" %in% names(rows)) rows$ipcc_ref else rep(NA_character_, nrow(rows))
    unit_disp <- pick(unit_user, rows$unit_cat)
    ref_disp  <- pick(ref_user,  rows$ipcc_ref_cat)
    src_disp  <- if ("data_source" %in% names(rows)) rows$data_source else rep(t("imputed_default_source"), nrow(rows))

    display <- data.frame(
      param = rows$parameter,
      default = formatC(rows$mean, digits = 4, format = "g"),
      unit = unit_disp,
      ref = ref_disp,
      source = src_disp,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    names(display) <- c(t("imputed_dt_col_param"),
                         t("imputed_dt_col_default"),
                         t("imputed_dt_col_unit"),
                         t("imputed_dt_col_ref"),
                         t("imputed_dt_col_source"))

    DT::datatable(
      display,
      rownames = FALSE,
      options  = list(dom = "t", paging = FALSE, ordering = FALSE),
      class    = "compact stripe"
    )
  })

  # Tab 1 (Data Input) inline notice — shown immediately when data is loaded.
  # A simpler amber card than the Tab 2 DT: lists imputed parameter names and
  # the IPCC default value used. No DT needed — the full details are on Tab 2.
  output$imputed_params_notice_tab1 <- renderUI({
    rows <- imputed_rows()
    if (is.null(rows) || nrow(rows) == 0) return(NULL)
    n <- nrow(rows)
    param_list <- paste(rows$parameter, collapse = ", ")
    title_tmpl <- if (n == 1L) t("imputed_notice_title_single") else t("imputed_notice_title_plural")
    tags$div(
      style = "background:#FEF3C7; border-left:4px solid #F59E0B; border-radius:8px; padding:14px 16px; margin-bottom:14px;",
      tags$p(style = "margin:0 0 6px; font-weight:600; color:#92400E;",
             icon("triangle-exclamation"),
             sprintf(title_tmpl, n)),
      tags$p(style = "margin:0 0 8px; font-size:0.88rem; color:#92400E;",
             tags$strong(paste0(t("imputed_notice_params_label"), " ")), param_list),
      tags$table(
        style = "width:100%; border-collapse:collapse; font-size:0.82rem;",
        tags$thead(
          tags$tr(style = "background:rgba(245,158,11,0.15);",
            tags$th(style = "padding:4px 8px; text-align:left;", t("imputed_th_param")),
            tags$th(style = "padding:4px 8px; text-align:left;", t("imputed_th_default")),
            tags$th(style = "padding:4px 8px; text-align:left;", t("imputed_th_ref"))
          )
        ),
        tags$tbody(
          lapply(seq_len(n), function(i) {
            ref_val <- if ("ipcc_ref" %in% names(rows) && nzchar(rows$ipcc_ref[i] %||% ""))
              rows$ipcc_ref[i] else {
                cat_row <- PARAM_CATALOGUE[PARAM_CATALOGUE$parameter == rows$parameter[i], ]
                if (nrow(cat_row) > 0) cat_row$ipcc_ref[1] else "—"
              }
            tags$tr(style = if (i %% 2 == 0) "background:rgba(245,158,11,0.08);" else "",
              tags$td(style = "padding:4px 8px; font-weight:600;", rows$parameter[i]),
              tags$td(style = "padding:4px 8px;",
                      formatC(as.numeric(rows$mean[i]), digits = 4, format = "g")),
              tags$td(style = "padding:4px 8px; color:#666;", ref_val)
            )
          })
        )
      ),
      tags$p(style = "margin:8px 0 0; font-size:0.8rem; color:#92400E;",
             icon("info-circle"),
             t("imputed_notice_tail_pre"),
             tags$strong(t("imputed_notice_tail_qaqc")),
             t("imputed_notice_tail_post"))
    )
  })
  outputOptions(output, "imputed_params_notice_tab1", suspendWhenHidden = FALSE)

  output$qaqc_summary_ui <- renderUI({
    df <- qaqc_result()
    s  <- qaqc_summary(df)
    if (nrow(df) == 0)
      return(tags$p(t("imputed_load_data_first"), style = "color:#888;"))
    tags$div(
      style = "display:flex; gap:8px; flex-wrap:wrap;",
      if ((s$n_missing %||% 0) > 0)
        tags$span(
          style = "font-size:1rem; padding:6px 14px; background-color:#FEF3C7; color:#92400E; border-radius:4px; font-weight:600;",
          paste(s$n_missing, t("qa_badge_autofilled"))),
      tags$span(class = "badge bg-success",
                style = "font-size:1rem; padding:6px 14px;",
                paste(s$n_pass, t("qa_badge_pass"))),
      if ((s$n_info %||% 0) > 0)
        tags$span(class = "badge",
                  style = "font-size:1rem; padding:6px 14px; background-color:#1565C0; color:#fff;",
                  paste(s$n_info, t("qa_badge_info"))),
      tags$span(class = "badge bg-warning text-dark",
                style = "font-size:1rem; padding:6px 14px;",
                paste(s$n_warn, t("qa_badge_warn"))),
      tags$span(class = "badge bg-danger",
                style = "font-size:1rem; padding:6px 14px;",
                paste(s$n_fail, t("qa_badge_fail")))
    )
  })

  output$qaqc_table <- DT::renderDT({
    df <- qaqc_result()
    if (nrow(df) == 0) {
      empty <- data.frame(message = t("qa_no_data"))
      names(empty) <- t("qa_col_message")
      return(DT::datatable(empty, rownames = FALSE, options = list(dom = "t")))
    }
    df$status_icon <- sapply(df$status, qaqc_icon)
    display <- df[, c("group", "parameter", "check", "status_icon", "message")]
    DT::datatable(
      display,
      escape    = FALSE,
      rownames  = FALSE,
      colnames  = c(t("qa_col_group"), t("qa_col_parameter"),
                     t("qa_col_check"), t("qa_col_status"), t("qa_col_message")),
      options   = list(
        pageLength = 50,
        dom        = "ftp",
        columnDefs = list(
          list(targets = 3, orderData = 0),  # sort by status_icon uses its text
          list(width = "90px", targets = 2),
          list(width = "80px", targets = 3)
        )
      )
    )
  })

  # Uncertainty table.
  # Andreas 2026-06-02 review (round 1): when a user searched the table for
  # a parameter (e.g. "MW") and edited a cell, the whole DT re-rendered from
  # scratch and the search filter was cleared — forcing a fresh search for
  # every edit on large inventories. stateSave = TRUE alone wasn't enough
  # because Shiny's reactivity tears down the DataTable instance on every
  # rv$param_specs change, and the saved-state restore races with the
  # re-init.
  #
  # 2026-06-08 follow-up (Lolita): users still seeing the filter reset.
  # Switched to a dataTableProxy: the initial render only fires on bulk
  # data changes (file load, example load, quickset apply, reset). Cell
  # edits go through DT::replaceData(proxy, ...) which mutates the live
  # DataTable instance in-place — search filter, paging, and ordering
  # are preserved natively. rv$unc_render_token is bumped at every
  # bulk-replacement of rv$param_specs to force the initial render path.
  .unc_visible_cols <- c("parameter", "mean", "uncertainty_pct",
                          "distribution", "lower", "upper", "param_type")

  output$uncertainty_table <- DT::renderDT({
    # Take a reactive dependency ONLY on the render token, not on the
    # per-cell contents of rv$param_specs. Cell edits use the proxy.
    rv$unc_render_token
    isolate({
      req(rv$param_specs)
      DT::datatable(
        rv$param_specs[, .unc_visible_cols],
        options = list(
          pageLength    = 20,
          stateSave     = TRUE,
          stateDuration = -1
        ),
        editable = TRUE, rownames = FALSE
      )
    })
  })

  proxy_unc <- DT::dataTableProxy("uncertainty_table")

  # Initialise the render token, and bump it whenever rv$param_specs is
  # BULK-replaced (file upload, example load, quickset apply / undo,
  # post-import update). Single-cell edits do NOT bump the token; they
  # update via the proxy. Triggered by `rv$param_specs_bulk_token`
  # which the bulk-replacement code paths bump explicitly.
  if (is.null(isolate(rv$unc_render_token))) rv$unc_render_token <- 0L
  observeEvent(rv$param_specs_bulk_token, {
    rv$unc_render_token <- isolate(rv$unc_render_token) + 1L
  }, ignoreInit = FALSE, ignoreNULL = TRUE)

  # Round 7 R1.16: persist Tab 3 cell edits (including param_type override)
  # back into rv$param_specs and cascade bounds the same way the Tab 1 DT does.
  # Validates that param_type is one of activity_data/coefficient.
  observeEvent(input$uncertainty_table_cell_edit, {
    info <- input$uncertainty_table_cell_edit
    visible_cols <- c("parameter", "mean", "uncertainty_pct", "distribution",
                      "lower", "upper", "param_type")
    edit_col <- visible_cols[info$col + 1]
    row      <- info$row
    if (is.na(edit_col)) return()

    new_value <- info$value
    if (edit_col == "param_type") {
      vt <- tolower(trimws(as.character(new_value)))
      if (vt == "emission_factor") vt <- "coefficient"  # legacy alias
      if (!vt %in% c("activity_data", "coefficient")) {
        showNotification(
          sprintf("param_type must be 'activity_data' or 'coefficient' — got '%s'. Edit ignored.",
                  new_value),
          type = "error", duration = 6)
        return()
      }
      new_value <- vt
    }

    rv$param_specs[row, edit_col] <- DT::coerceValue(
      new_value, rv$param_specs[row, edit_col])

    ps   <- rv$param_specs
    mean <- suppressWarnings(as.numeric(ps$mean[row]))
    cols <- names(ps)

    # Same cascade rules as the Tab 1 DT (param_table)
    if (edit_col == "distribution" && identical(ps$distribution[row], "constant")) {
      if ("uncertainty_pct" %in% cols) ps$uncertainty_pct[row] <- 0
      if ("lower" %in% cols)            ps$lower[row]            <- mean
      if ("upper" %in% cols)            ps$upper[row]            <- mean
    } else if (edit_col %in% c("uncertainty_pct", "mean") &&
               "uncertainty_pct" %in% cols && !is.na(mean)) {
      pct <- suppressWarnings(as.numeric(ps$uncertainty_pct[row]))
      if (!is.na(pct)) {
        if ("lower" %in% cols) ps$lower[row] <- mean * (1 - pct / 100)
        if ("upper" %in% cols) ps$upper[row] <- mean * (1 + pct / 100)
      }
    } else if (edit_col %in% c("lower", "upper") && !is.na(mean) && mean != 0 &&
               "uncertainty_pct" %in% cols) {
      lo <- suppressWarnings(as.numeric(ps$lower[row]))
      up <- suppressWarnings(as.numeric(ps$upper[row]))
      if (!is.na(lo) && !is.na(up)) {
        half <- ((up - lo) / 2) / mean * 100
        ps$uncertainty_pct[row] <- round(half, 2)
      }
    }

    rv$param_specs <- ps

    # Push the updated data to the live DT instance via the proxy. This
    # preserves the user's search filter, page, and ordering — they don't
    # get bounced back to the top of the table after every edit. The
    # output$uncertainty_table render path is gated on rv$unc_render_token
    # which we deliberately do NOT bump here.
    DT::replaceData(proxy_unc,
                    rv$param_specs[, .unc_visible_cols],
                    resetPaging = FALSE,
                    rownames    = FALSE)
  })

  # Template downloads. Round 7.1: filename and MMS dropdown reflect the
  # IPCC version picked via input$template_version. Andreas 2026-05 follow-up:
  # no default — user must pick a version explicitly. If they click a Download
  # button without choosing, surface a Shiny notification and abort the
  # download.
  .selected_ipcc_version <- function() input$template_version
  .version_suffix <- function(v) {
    if (identical(v, "2019_refinement")) "ipcc2019" else "ipcc2006"
  }
  .require_ipcc_version <- function() {
    v <- .selected_ipcc_version()
    if (is.null(v) || !nzchar(v)) {
      showNotification(
        "Please select an IPCC Guidelines version (IPCC 2006 or IPCC 2019 Refinement) before downloading a template.",
        type = "error", duration = 6)
      shiny::validate(shiny::need(FALSE, "IPCC version not selected"))
    }
    v
  }
  output$download_template <- downloadHandler(
    filename = function() {
      v <- .require_ipcc_version()
      paste0("uncertainty_template_", .version_suffix(v), ".xlsx")
    },
    content = function(file) {
      v <- .require_ipcc_version()
      generate_template(file, include_example = FALSE, ipcc_version = v)
    }
  )
  output$download_template_example <- downloadHandler(
    filename = function() {
      v <- .require_ipcc_version()
      paste0("uncertainty_template_example_", .version_suffix(v), ".xlsx")
    },
    content = function(file) {
      v <- .require_ipcc_version()
      generate_template(file, include_example = TRUE, ipcc_version = v)
    }
  )

  # Lolita 2026-06-02 review: downloadable correlation-matrix templates for
  # the "Advanced — manual entry" mode. Two flavours — blank (identity) and
  # pre-filled with the structural-defaults pairs — so users have a concrete
  # starting CSV with the canonical PARAM_CATALOGUE names already in place.
  # Prevents typos in row/column headers that would otherwise be silently
  # dropped by expand_corr_matrix().
  output$download_corr_template <- downloadHandler(
    filename = function() "correlation_matrix_template_blank.csv",
    content  = function(file) generate_corr_matrix_template(file, include_example = FALSE)
  )
  output$download_corr_template_example <- downloadHandler(
    filename = function() "correlation_matrix_template_example.csv",
    content  = function(file) generate_corr_matrix_template(file, include_example = TRUE)
  )

  # --- CORRELATIONS ---

  # T4.1 / Round 7 R1.15: structural-defaults preset — sparse matrix with documented
  # structural pairs only. Renamed 2026-05 from "IPCC-guidance preset" after the
  # statistical audit: the IPCC publishes no numerical correlation values; this
  # preset is expert-elicited from biological / statistical relationships in the
  # IPCC equations and the livestock literature. After Round 7 the preset operates
  # on the **unified** set of all parameter names (AD + coefficients) so within-
  # coefficient pairs like BW <-> MW (now both coefficients post-R1.6) flow
  # correctly. The previous cross-block N <-> BW pair was dropped in the 2026-05
  # audit (no defensible cross-country source).
  observeEvent(input$corr_mode, {
    if (input$corr_mode == "preset") {
      all_names <- if (!is.null(rv$param_specs))
        rv$param_specs$parameter
      else
        PARAM_CATALOGUE$parameter
      preset <- build_ipcc_preset_corr(all_names)
      if (is.null(preset)) {
        showNotification(
          "Preset has no applicable pairs for the current parameter set.",
          type = "warning", duration = 5)
        return()
      }
      rv$corr_matrix <- preset
      showNotification(
        sprintf("Loaded structural-defaults preset (%d parameters). Includes Milk↔BW and Milk↔DE (+0.30 each), BW↔MW at 0.50, and DE↔Ym at -0.50; Milk↔pct_pregnant and Cfi↔Ca are intentionally excluded.",
                nrow(preset)),
        type = "message", duration = 6)
    } else if (input$corr_mode == "timeseries") {
      # 2026-06: when the user switches *into* timeseries (e.g. from preset),
      # recompute from the current population data so the heatmap and the MC
      # both reflect the time-series, not whatever matrix the previous mode
      # left behind. If no time-series is available, leave rv$corr_matrix NULL
      # — the gated radio will keep this option disabled, but if a stale state
      # reaches here we explicitly clear rather than carrying a wrong matrix.
      if (!is.null(rv$population)) {
        rv$corr_matrix <- .compute_corr_now(rv$population)
      } else {
        rv$corr_matrix <- NULL
      }
    } else if (input$corr_mode == "manual") {
      # 2026-06: clear rv$corr_matrix if no manual matrix has been uploaded in
      # this session, so the heatmap doesn't show a stale preset. If the user
      # already uploaded one earlier, keep it.
      if (!isTRUE(rv$manual_uploaded)) rv$corr_matrix <- NULL
    } else if (input$corr_mode == "none") {
      # Don't wipe an uploaded matrix — just don't apply it (sim observer reads input$corr_mode)
    }
  }, ignoreInit = TRUE)

  # 2026-06: the observeEvent(input$corr_ts_detrend, ...) observer was removed
  # along with the UI selectInput it watched. First-difference detrending is
  # now hardcoded in .compute_corr_now().

  # T4.1: manual matrix upload (CSV)
  observeEvent(input$corr_matrix_upload, {
    req(input$corr_matrix_upload)
    tryCatch({
      df <- read.csv(input$corr_matrix_upload$datapath, row.names = 1,
                     check.names = FALSE)
      m  <- as.matrix(df)
      if (nrow(m) != ncol(m) || any(is.na(m)))
        stop("Matrix must be square with no missing values.")
      if (any(diag(m) != 1))
        stop("Diagonal entries must be 1.")
      m <- as.matrix(Matrix::nearPD(m, corr = TRUE)$mat)
      rv$corr_matrix    <- m
      rv$manual_uploaded <- TRUE
      showNotification(sprintf("Loaded manual correlation matrix (%d parameters).",
                               nrow(m)), type = "message", duration = 5)
    }, error = function(e) {
      showNotification(paste("Matrix upload failed:", e$message),
                       type = "error", duration = 8)
    })
  })

  # Round 6a #5: render the "Compare with/without correlations" checkbox
  # disabled when no correlations are selected on Tab 4 — the comparison
  # run would otherwise be identical to the main run and waste compute time.
  output$run_comparison_ui <- renderUI({
    no_ad_corr <- is.null(input$corr_mode) || input$corr_mode == "none"
    no_ef_corr <- is.null(input$ef_corr_mode) || input$ef_corr_mode == "none"
    if (no_ad_corr && no_ef_corr) {
      tagList(
        tags$div(
          style = "opacity:0.55; pointer-events:none;",
          checkboxInput("run_comparison", t("cmp_run_label"), value = FALSE)
        ),
        tags$div(
          style = "font-size:0.78rem; color:#92400E; background:#FEF3C7; padding:6px 10px; border-radius:4px; margin-top:-6px; margin-bottom:8px;",
          icon("info-circle"),
          tags$em(t("cmp_disabled_long"))
        )
      )
    } else {
      checkboxInput("run_comparison", t("cmp_run_label"), value = FALSE)
    }
  })

  # 2026-06 Andreas review: the per-scope ("population only" / "intake only")
  # filter was retired. The "shared data source" framing didn't survive the
  # statistical review (national animal-count statistics rarely include BW /
  # MW / WG, so the implied common provenance was thin), and
  # R/_test_correlation_effect.R confirmed the filter had no observable effect
  # on the headline for typical livestock inputs. The reactive is kept as a
  # thin wrapper around rv$corr_matrix so downstream callers don't change.
  effective_corr_matrix <- reactive({ rv$corr_matrix })

  # 2026-06 Andreas review: the corr_mode radio is rendered server-side so we
  # can disable choices whose prerequisites are missing (empty TS sheet, no
  # manual CSV uploaded, no template loaded). Uses Shiny's standard
  # radioButtons() (so the input binding works) with HTML choiceNames carrying
  # per-choice help text, plus a JS post-step that sets `disabled` on the
  # underlying <input> for greyed options. Prevents the silent no-op Andreas
  # hit on his ZIM run.
  output$corr_mode_ui <- renderUI({
    has_template <- !is.null(rv$param_specs)
    ts_ok        <- isTRUE(rv$ts_available)
    manual_ok    <- isTRUE(rv$manual_uploaded)
    current_mode <- input$corr_mode %||% "none"

    # Snap the selection back to "none" if the currently-active mode just
    # became unavailable (e.g. user uploaded a new template whose TS sheet
    # is empty while previously on timeseries). Deferred via session.
    # NOTE on manual: this mode is now ALWAYS selectable (the file picker
    # lives inside the manual conditionalPanel, so users need to enter the
    # mode to reach the upload). The simulation observer blocks the run if
    # the user selected manual without actually uploading a matrix — that's
    # where the safety check lives now, not here.
    if ((current_mode == "timeseries" && !ts_ok) ||
        (current_mode == "preset"     && !has_template)) {
      isolate({
        updateRadioButtons(session, "corr_mode", selected = "none")
        current_mode <- "none"
      })
    }

    label_for <- function(value, title, enabled, help_enabled, help_disabled) {
      help <- if (enabled) help_enabled
              else tagList(tags$strong(t("corr_disabled_prefix")), help_disabled)
      help_style <- "font-size:0.78rem; color:#52525B; line-height:1.4; margin-top:-2px; margin-bottom:6px;"
      wrap_style <- if (!enabled) "opacity:0.45; cursor:not-allowed;" else ""
      tags$span(
        style = wrap_style,
        tags$strong(title),
        tags$div(style = help_style, help)
      )
    }

    radio <- radioButtons("corr_mode",
      label = tagList(
        paste0(t("corr_mode_label"), " "),
        bslib::tooltip(
          tags$span(icon("circle-question"),
                    style = "color:#2D6A4F; cursor:help; vertical-align:middle;"),
          t("tip_corr_mode"),
          placement = "right"
        )
      ),
      choiceValues = c("none", "timeseries", "preset", "manual"),
      choiceNames = list(
        label_for("none", t("corr_mode_none"),
          enabled       = TRUE,
          help_enabled  = t("corr_help_none")),
        label_for("timeseries", t("corr_mode_ts"),
          enabled       = ts_ok,
          help_enabled  = tagList(t("corr_help_ts_pre"),
                                   tags$code(t("corr_ts_param_ts")),
                                   t("corr_help_ts_post"),
                                   tags$em(t("corr_help_ts_em"))),
          help_disabled = tagList(t("corr_help_ts_disabled_pre"),
                                   tags$code(t("corr_ts_param_ts")),
                                   t("corr_help_ts_disabled_post"))),
        label_for("preset", t("corr_mode_preset"),
          enabled       = has_template,
          help_enabled  = tagList(t("corr_help_preset"),
                                   tags$em(t("corr_help_preset_em"))),
          help_disabled = t("corr_help_preset_disabled")),
        label_for("manual", t("corr_mode_advanced_manual_short"),
          enabled       = TRUE,
          help_enabled  = if (manual_ok) t("corr_help_manual_loaded")
                            else t("corr_help_manual_pick"))
      ),
      selected = current_mode)

    # Disable individual <input type="radio"> elements via JS. Has to be
    # deferred to fire after the radio is mounted in the DOM; using
    # session$onFlushed would also work but a one-shot setTimeout(0) is enough
    # because renderUI inserts the script after the radio markup.
    disabled_values <- c()
    if (!ts_ok)        disabled_values <- c(disabled_values, "timeseries")
    if (!has_template) disabled_values <- c(disabled_values, "preset")
    # "manual" intentionally NOT in disabled_values — see comment above the
    # radioButtons() call. The simulation observer blocks the run if manual
    # is selected without an uploaded matrix.
    js_disable <- if (length(disabled_values) > 0) {
      tags$script(HTML(sprintf(
        "setTimeout(function(){var vals=%s; vals.forEach(function(v){var el=document.querySelector('input[name=\"corr_mode\"][value=\"'+v+'\"]'); if(el){el.disabled=true;}});}, 0);",
        jsonlite::toJSON(disabled_values)
      )))
    } else {
      tags$script(HTML(
        "setTimeout(function(){document.querySelectorAll('input[name=\"corr_mode\"]').forEach(function(el){el.disabled=false;});}, 0);"
      ))
    }

    tagList(radio, js_disable)
  })

  output$corr_heatmap <- plotly::renderPlotly({
    mtx <- effective_corr_matrix()
    if (is.null(mtx)) {
      plotly::plot_ly() %>%
        plotly::layout(title = t("corr_heatmap_no_matrix"),
                       xaxis = list(visible = FALSE), yaxis = list(visible = FALSE))
    } else {
      # 2026-05 audit follow-up: when the structural-defaults preset is active,
      # attach the per-pair source citation as the hover text so users can trace
      # where each non-zero correlation comes from.
      hover <- matrix("", nrow = nrow(mtx), ncol = ncol(mtx))
      if (isTRUE(input$corr_mode == "preset") && exists("PRESET_PAIRS")) {
        rn <- rownames(mtx); cn <- colnames(mtx)
        for (p in PRESET_PAIRS) {
          ia <- which(rn == p$a); ib <- which(cn == p$b)
          ja <- which(rn == p$b); jb <- which(cn == p$a)
          src <- if (!is.null(p$source)) p$source else ""
          tip <- sprintf("%s &harr; %s: %.2f<br><i>%s</i>", p$a, p$b, p$rho, src)
          if (length(ia) && length(ib)) hover[ia, ib] <- tip
          if (length(ja) && length(jb)) hover[ja, jb] <- tip
        }
      }
      plotly::plot_ly(z = mtx, type = "heatmap",
                      x = colnames(mtx), y = rownames(mtx),
                      text = hover, hoverinfo = "x+y+z+text",
                      colorscale = list(c(0, "#C1121F"), c(0.5, "#FFFFFF"), c(1, "#2D6A4F")),
                      zmin = -1, zmax = 1) %>%
        plotly::layout(title = t("corr_heatmap_title_ad"))
    }
  })

  output$corr_ts_status <- renderUI({
    if (is.null(rv$corr_matrix)) {
      div(style = "font-size:0.85rem; color:#92400E; background:#FEF3C7; padding:8px 10px; border-radius:6px;",
          icon("exclamation-triangle"),
          t("corr_ts_no_data"),
          tags$strong(t("corr_ts_param_ts")),
          t("corr_ts_no_data_tail"))
    } else {
      n <- nrow(rv$corr_matrix)
      nms <- paste(rownames(rv$corr_matrix), collapse = ", ")
      div(style = "font-size:0.85rem; color:#1B4332; background:#D8F3DC; padding:8px 10px; border-radius:6px;",
          icon("check-circle"), sprintf(t("corr_ts_loaded"), n, nms))
    }
  })

  # EF correlation matrix — built from UI inputs whenever they change.
  # 2026-05 audit follow-up: only two modes survive — "none" (IPCC default)
  # and "block" (within-literature correlations, cross-block zero). The
  # legacy "uniform" single-ρ option was removed because applying one ρ to
  # 13 coefficients drawn from three unrelated measurement literatures
  # (rumen fermentation / BMP-lagoon / NH₃ volatilisation) is statistically
  # indefensible. make_uniform_corr() in mc_sampling.R is kept as an
  # exported helper in case it is needed programmatically, but the UI no
  # longer offers it.
  ef_corr_reactive <- reactive({
    req(rv$param_specs)
    if (!isTRUE(input$ef_corr_mode == "block")) return(NULL)
    ef_params <- rv$param_specs[rv$param_specs$param_type == "coefficient", ]
    if (nrow(ef_params) < 2) return(NULL)
    rho_by_block <- list(
      energy   = input$ef_rho_energy   %||% 0,
      manureCH = input$ef_rho_manureCH %||% 0,
      manureN  = input$ef_rho_manureN  %||% 0
    )
    if (all(unlist(rho_by_block) == 0)) return(NULL)  # nothing to apply
    make_block_corr(ef_params$parameter, rho_by_block)
  })

  observe({
    rv$ef_corr_matrix <- ef_corr_reactive()
  })

  # 2026-05 UX overhaul: live "Currently:" captions under each block-rho slider.
  # Translates the numeric rho into a plain-language band so non-statisticians
  # can read the slider state without consulting docs.
  .rho_band <- function(rho) {
    if (is.null(rho) || !is.finite(rho)) return("")
    if (rho == 0)         return("Currently: 0.00 — independent within the block (no shared bias assumed).")
    if (rho <= 0.15)      return(sprintf("Currently: %.2f — weak shared bias.", rho))
    if (rho <= 0.35)      return(sprintf("Currently: %.2f — moderate shared bias (typical when one literature dominates).", rho))
                          sprintf("Currently: %.2f — strong shared bias (requires documented justification).", rho)
  }
  output$ef_rho_energy_interp   <- renderText(.rho_band(input$ef_rho_energy))
  output$ef_rho_manureCH_interp <- renderText(.rho_band(input$ef_rho_manureCH))
  output$ef_rho_manureN_interp  <- renderText(.rho_band(input$ef_rho_manureN))

  # 2026-06: warn when block-mode is selected but all three sliders are at 0.
  # Without this the user gets a silent no-op identical to the AD-side empty-TS
  # case Andreas hit.
  output$ef_rho_all_zero_warning <- renderUI({
    rhos <- c(input$ef_rho_energy   %||% 0,
              input$ef_rho_manureCH %||% 0,
              input$ef_rho_manureN  %||% 0)
    if (all(rhos == 0)) {
      tags$div(
        style = "font-size:0.82rem; color:#92400E; background:#FEF3C7; padding:8px 10px; border-radius:6px; margin-top:8px;",
        icon("exclamation-triangle"),
        " ", t("corr_ef_zero_warning")
      )
    }
  })

  output$ef_corr_heatmap <- plotly::renderPlotly({
    mat <- ef_corr_reactive()
    if (is.null(mat)) {
      plotly::plot_ly() %>%
        plotly::layout(title = t("corr_ef_no_corr"),
                       xaxis = list(visible = FALSE), yaxis = list(visible = FALSE))
    } else {
      title_str <- sprintf("%s — energy=%.2f, manureCH=%.2f, manureN=%.2f",
                           t("corr_heatmap_title_ef"),
                           input$ef_rho_energy   %||% 0,
                           input$ef_rho_manureCH %||% 0,
                           input$ef_rho_manureN  %||% 0)
      plotly::plot_ly(z = mat, type = "heatmap",
                      x = colnames(mat), y = rownames(mat),
                      colorscale = list(c(0, "#FFFFFF"), c(1, "#2D6A4F")),
                      zmin = 0, zmax = 1) %>%
        plotly::layout(title = title_str)
    }
  })

  # --- SIMULATION ---

  observeEvent(input$run_sim, {
    req(rv$param_specs)

    # Block run if no analysis mode selected — navigate to Data Input (where the toggle lives).
    if (is.null(input$analysis_mode) || !nzchar(input$analysis_mode)) {
      showNotification(
        "Please choose an analysis mode (Single year or Trend) at the top of the Data Input tab before running.",
        type = "error", duration = 10)
      rv$sim_log <- paste0(rv$sim_log,
        "Run blocked: no analysis mode selected.\n")
      bslib::nav_select(id = "nav", selected = "1. Data Input", session = session)
      return()
    }

    # Round 9: defensive no-op. Trend mode shows a different Run button
    # ('run_trend') via conditionalPanel, so clicking the single-year button
    # in trend mode shouldn't be possible — but if it is, we bail with a
    # message rather than running a single-year sim against trend settings.
    if (input$analysis_mode == "trend") {
      showNotification(
        "Trend mode is selected on the Home page. Click 'Run Trend Analysis' on this tab instead — the single-year Run is only used for analysis_mode = 'single'.",
        type = "warning", duration = 8)
      return()
    }

    # Block run if no emission sources selected; scroll to the checkboxes
    if (is.null(input$emission_sources) || length(input$emission_sources) == 0) {
      showNotification(
        "Please tick at least one emission source on the left before running the simulation.",
        type = "error", duration = 8)
      rv$sim_log <- paste0(rv$sim_log,
        "Run blocked: no emission sources selected.\n")
      session$sendCustomMessage("scrollTo", "emission_sources")
      return()
    }

    # 2026-06 Andreas review: belt-and-suspenders check that the selected
    # correlation mode actually has a matrix. The corr_mode_ui radio greys
    # out unavailable options, but a stale state (or a future code path
    # that bypasses the gated UI) could still reach here with a "lying"
    # mode setting. Block the run with an explicit error rather than a
    # silent no-op.
    if (isTRUE(input$corr_mode == "timeseries") && !isTRUE(rv$ts_available)) {
      showNotification(
        "Correlation mode is 'From template (auto, time-series)' but no Parameter_TimeSeries data is loaded. Either upload a template with a populated TS sheet, or switch the mode to 'Structural defaults' / 'No correlations' on Tab 4 before running.",
        type = "error", duration = 12)
      rv$sim_log <- paste0(rv$sim_log,
        "Run blocked: corr_mode='timeseries' selected but TS sheet is empty.\n")
      return()
    }
    if (isTRUE(input$corr_mode == "manual") && !isTRUE(rv$manual_uploaded)) {
      showNotification(
        "Correlation mode is 'Advanced — manual entry' but no CSV matrix has been uploaded. Either upload a manual matrix, or switch the mode on Tab 4 before running.",
        type = "error", duration = 12)
      rv$sim_log <- paste0(rv$sim_log,
        "Run blocked: corr_mode='manual' selected but no matrix uploaded.\n")
      return()
    }

    # T1.2 / T2.2 / A1: auto-fill missing core params from IPCC defaults
    # rather than blocking the simulation.
    # Round 7 T2.1: pass region so regional IPCC defaults are preferred over
    # the global table for the 5 parameters covered by IPCC_DEFAULTS_BY_REGION.
    region_for_completeness <- if (!is.null(rv$inv_metadata) &&
                                    "region" %in% names(rv$inv_metadata) &&
                                    nzchar(rv$inv_metadata$region %||% "")) {
      rv$inv_metadata$region
    } else NULL
    comp <- ensure_completeness(rv$param_specs, region = region_for_completeness)
    if (!isTRUE(comp$valid)) {
      showNotification(paste0("Cannot run simulation. ", comp$message),
                       type = "error", duration = 12)
      rv$sim_log <- paste0(rv$sim_log,
                           "Completeness check failed: ", comp$message, "\n")
      return()
    }
    if (length(comp$auto_filled) > 0) {
      rv$param_specs <- comp$param_specs
      .bump_unc_token()
      showNotification(comp$message, type = "warning", duration = 6)
      rv$sim_log <- paste0(rv$sim_log,
                           "Auto-fill: ", comp$message, "\n")
    }

    # Andreas 2026-05-26 follow-up: block the run when the user has left a
    # required `mean` cell blank (NA after parsing). ensure_completeness()
    # above auto-fills entirely-missing parameter rows from IPCC defaults but
    # cannot help here — the parameter row exists, the user just hasn't typed
    # a number into it. Without this guard the NA flows into rnorm() at
    # sampling time, produces NA draws, and trips `if (milk_yield > 0)` /
    # `if (weight_gain > 0)` inside calc_n_excretion / calc_neg with the
    # cryptic "missing value where TRUE/FALSE needed".
    #
    # Andreas 2026-05-27 follow-up: make the gate SOURCE-AWARE. Only require a
    # parameter to be non-blank if at least one *selected* emission source
    # actually consumes it (per SOURCE_PARAM_DEPS in utils_ipcc_defaults.R).
    # A CH4-only run must not be blocked by blank manure-N2O parameters
    # (EF3_S / Frac_GASMS / Frac_LEACH_H), which (a) aren't used by CH4 and
    # (b) are sourced per-MMS from the Manure_Management tab anyway.
    needed_params <- params_needed_for_sources(input$emission_sources)
    na_mean_rows <- which(is.na(rv$param_specs$mean) &
                          rv$param_specs$parameter %in% needed_params)
    if (length(na_mean_rows) > 0) {
      preview_cols <- intersect(c("cattle_type", "aggregation_level",
                                    "sub_category", "parameter"),
                                 names(rv$param_specs))
      preview <- rv$param_specs[na_mean_rows, preview_cols, drop = FALSE]
      preview_txt <- paste(apply(preview, 1, function(r)
        paste(trimws(r), collapse = " / ")), collapse = "; ")
      msg <- sprintf(
        paste0("Cannot run simulation: %d Parameters row(s) have a blank ",
               "`value` cell. Open the Parameters sheet, fill the yellow ",
               "cells, then re-upload. Missing: %s"),
        length(na_mean_rows),
        if (nchar(preview_txt) > 400) paste0(substr(preview_txt, 1, 400), " ...")
        else preview_txt)
      showNotification(msg, type = "error", duration = 15)
      rv$sim_log <- paste0(rv$sim_log, msg, "\n")
      return()
    }

    # 2026-06-08 (Lolita): block the run when ANY row has bounds that
    # don't bracket the mean (lower > mean OR mean > upper). Without this,
    # mc2d::rpert / rtriang / etc. emit NaN, NaN flows into total_co2e,
    # and the simulation crashes at quantile() with the unhelpful
    # 'missing values and NaN's not allowed' error after 20 000+ iterations.
    # The QA/QC tab catches the same issue but users sometimes skip QA
    # and go straight to Run — so duplicate the check here, source-aware
    # (only flag rows for parameters used by the selected emission sources).
    ps_check <- rv$param_specs
    has_b <- !is.na(ps_check$mean) & !is.na(ps_check$lower) & !is.na(ps_check$upper)
    not_constant <- ps_check$distribution != "constant" |
                      is.na(ps_check$distribution)
    in_scope <- ps_check$parameter %in% needed_params
    bad_idx <- which(has_b & not_constant & in_scope &
                       (ps_check$lower > ps_check$mean |
                          ps_check$mean  > ps_check$upper))
    if (length(bad_idx) > 0) {
      preview_cols <- intersect(c("sub_category", "parameter", "mean",
                                    "lower", "upper"),
                                 names(ps_check))
      preview <- ps_check[bad_idx[seq_len(min(6, length(bad_idx)))],
                          preview_cols, drop = FALSE]
      preview_txt <- paste(apply(preview, 1, function(r)
        paste(trimws(as.character(r)), collapse = " / ")),
        collapse = "; ")
      msg <- sprintf(
        paste0("Cannot run simulation: %d Parameters row(s) have bounds ",
               "that don't bracket the mean (lower > mean OR mean > upper). ",
               "These would produce NaN samples and crash the run. Fix on ",
               "Tab 1 or Tab 3 — also check the QA/QC tab for the full list. ",
               "Rows: %s"),
        length(bad_idx),
        if (nchar(preview_txt) > 400) paste0(substr(preview_txt, 1, 400), " ...")
        else preview_txt)
      showNotification(msg, type = "error", duration = 15)
      rv$sim_log <- paste0(rv$sim_log, msg, "\n")
      return()
    }

    rv$sim_running <- TRUE
    rv$sim_error   <- NULL
    # selectInput returns a character string; coerce once here so all downstream
    # code receives an integer without needing individual as.integer() calls.
    n_iter_val <- as.integer(input$n_iter)
    n_iter_fmt <- format(n_iter_val, big.mark = ",")

    rv$sim_log <- paste0(rv$sim_log, "\n--- Starting simulation ---\n")
    rv$sim_log <- paste0(rv$sim_log, "Iterations: ", n_iter_val, "\n")
    rv$sim_log <- paste0(rv$sim_log, "GWP: ", input$gwp_version, "\n")
    if (!is.null(rv$ef_corr_matrix)) {
      rv$sim_log <- paste0(rv$sim_log,
        sprintf("EF correlation: block-structured (energy=%.2f, manureCH=%.2f, manureN=%.2f)\n",
                input$ef_rho_energy   %||% 0,
                input$ef_rho_manureCH %||% 0,
                input$ef_rho_manureN  %||% 0))
    } else {
      rv$sim_log <- paste0(rv$sim_log, "EF correlation: none (independent)\n")
    }

    withProgress(
      message = sprintf("Monte Carlo simulation (%s iterations)", n_iter_fmt),
      value   = 0,
      {
        # Capture-by-reference holder for the stack at point-of-error. The
        # tryCatch error handler runs AFTER the stack has unwound, so
        # sys.calls() there only shows Shiny scaffolding (useless for
        # debugging if(NA) errors). withCallingHandlers runs BEFORE unwinding
        # — we snap sys.calls() there and stash it for the tryCatch logger.
        captured_stack <- character(0)
        tryCatch(withCallingHandlers({

          # ---- Stage 1: build system data ----
          setProgress(0.03, detail = "Preparing system data...")

          specs  <- rv$param_specs
          manure <- rv$manure_data

          make_group_key <- function(df) {
            if (all(c("cattle_type", "aggregation_level") %in% names(df))) {
              sub <- if ("sub_category" %in% names(df)) df$sub_category else rep("", nrow(df))
              paste(df$cattle_type, df$aggregation_level, sub, sep = "||")
            } else if (all(c("system", "subsystem") %in% names(df))) {
              paste(df$system, df$subsystem, sep = "||")
            } else {
              rep("group1", nrow(df))
            }
          }

          group_key  <- make_group_key(specs)
          sys_groups <- unique(group_key)

          # Andreas 28/5/26 follow-up: a sub-category-key typo across the two
          # sheets (e.g. Parameters "DINT_heif" vs Manure_Management
          # "DINT_heifer") used to silently fall back to a default 70/30
          # pasture/solid_storage allocation, materially under-counting MM
          # N2O. resolve_sub_category_matches() now performs a single round
          # of unambiguous fuzzy matching (same cattle_type + aggregation_level,
          # case-insensitive equal OR adist <= 2). Exactly-one match is auto-
          # substituted and shown to the user as a Shiny warning + QAQC row;
          # ambiguous matches (more than one candidate) block the run.
          sg_resolve <- resolve_sub_category_matches(specs, manure)
          sg_to_mm   <- sg_resolve$matched
          sg_issues  <- sg_resolve$issues

          ambig_rows <- sg_issues[sg_issues$status == "fail" &
                                    sg_issues$check == "sub_category_ambiguous", ,
                                  drop = FALSE]
          if (nrow(ambig_rows) > 0) {
            msg <- paste0(
              "ERROR: ", nrow(ambig_rows), " Parameters sub_category key(s) ",
              "are ambiguously close to multiple Manure_Management rows and ",
              "cannot be auto-matched. Fix the spelling in the template so ",
              "each Parameters key resolves to exactly one MM key, then ",
              "re-upload.\n", paste("  -", ambig_rows$message,
                                     collapse = "\n"), "\n")
            rv$sim_log <- paste0(rv$sim_log, msg)
            showNotification(
              "Sub-category key ambiguous between Parameters and Manure_Management. See simulation log for details.",
              type = "error", duration = NULL)
            stop("Ambiguous sub-category key — run blocked.", call. = FALSE)
          }

          auto_rows <- sg_issues[sg_issues$status == "warn" &
                                   sg_issues$check == "sub_category_auto_match", ,
                                 drop = FALSE]
          if (nrow(auto_rows) > 0) {
            for (ri in seq_len(nrow(auto_rows))) {
              rv$sim_log <- paste0(rv$sim_log,
                "INFO (auto-match): ", auto_rows$message[ri], "\n")
            }
            showNotification(
              paste0(nrow(auto_rows),
                     " sub-category key(s) auto-matched between Parameters and ",
                     "Manure_Management (likely typos). Verify on Tab 2 QAQC. ",
                     "Examples: ",
                     paste(head(sub("\\..*$", ".", auto_rows$message), 2),
                           collapse = " ")),
              type = "warning", duration = 12)
          }

          nomatch_rows <- sg_issues[sg_issues$status == "warn" &
                                      sg_issues$check == "sub_category_no_match", ,
                                    drop = FALSE]
          if (nrow(nomatch_rows) > 0) {
            for (ri in seq_len(nrow(nomatch_rows))) {
              rv$sim_log <- paste0(rv$sim_log,
                "WARNING (no MM match): ", nomatch_rows$message[ri], "\n")
            }
          }

          systems_data <- list()

          default_mms_fracs <- c(pasture = 0.70, solid_storage = 0.30)
          default_mcf_vals  <- c(pasture = 0.015, solid_storage = 0.050)
          default_ef3_vals  <- c(pasture = 0.020, solid_storage = 0.005)

          for (sg in sys_groups) {
            sys_specs <- specs[group_key == sg, ]

            # Round 7 R1.13: also extract per-MMS Frac_GasMS / Frac_LeachMS
            # from the manure sheet if the columns are present. NA -> fall back
            # to mms_frac_defaults_2019() inside calc_indirect_n2o_mm().
            frac_gas_vals   <- NULL
            frac_leach_vals <- NULL
            # Andreas 2026-05 follow-up (C4 / C6): per-MMS uncertainty matrices
            # populated below if the manure sheet has lower/upper/dist cols.
            # Andreas 28/5/26 #4: fraction_samples is the new per-MMS sampled
            # allocation matrix (n_iter × n_mms, rows renormalised to sum to 1).
            mcf_samples <- ef3_samples <- fg_samples <- fl_samples <-
              fraction_samples <- NULL

            if (!is.null(manure) && nrow(manure) > 0 &&
                all(c("mms_type", "fraction_pct", "MCF_pct", "EF3") %in% names(manure))) {
              manure_key <- make_group_key(manure)
              # Use the auto-matched MM key from resolve_sub_category_matches
              # (falls through to the literal sg when no remap was needed).
              sg_lookup  <- if (sg %in% names(sg_to_mm)) sg_to_mm[[sg]] else sg
              mms_rows   <- manure[manure_key == sg_lookup, ]
              if (nrow(mms_rows) > 0) {
                # Defensive coercion in case Excel stored these as text
                fp_num   <- suppressWarnings(as.numeric(mms_rows$fraction_pct))
                mcf_num  <- suppressWarnings(as.numeric(mms_rows$MCF_pct))
                ef3_num  <- suppressWarnings(as.numeric(mms_rows$EF3))
                mms_fracs <- setNames(fp_num / 100,  mms_rows$mms_type)
                mcf_vals  <- setNames(mcf_num / 100, mms_rows$mms_type)
                ef3_vals  <- setNames(ef3_num,       mms_rows$mms_type)
                # Drop any rows that didn't coerce (NA fraction → useless)
                mms_fracs <- mms_fracs[!is.na(mms_fracs)]
                mcf_vals  <- mcf_vals[names(mms_fracs)]
                ef3_vals  <- ef3_vals[names(mms_fracs)]
                # Replace any leftover NAs in MCF/EF3 with defaults rather than
                # crashing the simulation
                mcf_vals[is.na(mcf_vals)] <- 0.015
                ef3_vals[is.na(ef3_vals)] <- 0.005

                # Round 7 R1.13: per-MMS Frac_GasMS / Frac_LeachMS columns.
                if ("Frac_GasMS_pct" %in% names(mms_rows)) {
                  fg_num <- suppressWarnings(as.numeric(mms_rows$Frac_GasMS_pct)) / 100
                  frac_gas_vals <- setNames(fg_num, mms_rows$mms_type)
                  frac_gas_vals <- frac_gas_vals[names(mms_fracs)]
                }
                if ("Frac_LeachMS_pct" %in% names(mms_rows)) {
                  fl_num <- suppressWarnings(as.numeric(mms_rows$Frac_LeachMS_pct)) / 100
                  frac_leach_vals <- setNames(fl_num, mms_rows$mms_type)
                  frac_leach_vals <- frac_leach_vals[names(mms_fracs)]
                }

                # Andreas 2026-05 follow-up (C4 / C6): sample per-MMS MCF /
                # EF3 / Frac_GasMS / Frac_LeachMS uncertainty from the
                # lower / upper / distribution columns on the manure sheet.
                # Was previously dropped — only central values were used as
                # deterministic per-iteration constants, so MCF never showed
                # up in the MM-CH4 tornado despite huge bounds in real data.
                mc_n_iter <- n_iter_val
                # Pre-scale percentage cols to fractions so the sampler works
                # in the same units the downstream calc expects.
                mr_mcf_scaled <- mms_rows
                for (col in c("MCF_pct", "lower_mcf", "upper_mcf")) {
                  if (col %in% names(mr_mcf_scaled))
                    mr_mcf_scaled[[col]] <- suppressWarnings(
                      as.numeric(mr_mcf_scaled[[col]])) / 100
                }
                mr_fg_scaled <- mms_rows
                for (col in c("Frac_GasMS_pct", "lower_frac_gas", "upper_frac_gas")) {
                  if (col %in% names(mr_fg_scaled))
                    mr_fg_scaled[[col]] <- suppressWarnings(
                      as.numeric(mr_fg_scaled[[col]])) / 100
                }
                mr_fl_scaled <- mms_rows
                for (col in c("Frac_LeachMS_pct", "lower_frac_leach", "upper_frac_leach")) {
                  if (col %in% names(mr_fl_scaled))
                    mr_fl_scaled[[col]] <- suppressWarnings(
                      as.numeric(mr_fl_scaled[[col]])) / 100
                }
                mcf_samples <- sample_per_mms_param(
                  mr_mcf_scaled, "MCF_pct", "lower_mcf", "upper_mcf",
                  "distribution_mcf", mc_n_iter, default_dist = "pert")
                ef3_samples <- sample_per_mms_param(
                  mms_rows, "EF3", "lower_ef3", "upper_ef3",
                  "distribution_ef3", mc_n_iter, default_dist = "pert")
                fg_samples <- sample_per_mms_param(
                  mr_fg_scaled, "Frac_GasMS_pct", "lower_frac_gas",
                  "upper_frac_gas", "distribution_frac_gas",
                  mc_n_iter, default_dist = "pert")
                fl_samples <- sample_per_mms_param(
                  mr_fl_scaled, "Frac_LeachMS_pct", "lower_frac_leach",
                  "upper_frac_leach", "distribution_frac_leach",
                  mc_n_iter, default_dist = "pert")

                # Andreas 28/5/26 #4: sample fraction_pct per-MMS so MMS
                # allocation can show up in the tornado / rank-correlation.
                # If lower_fraction / upper_fraction are absent or equal to
                # the central value, the sampler degenerates to a constant
                # row (matching the prior deterministic behaviour). Each
                # iteration row is then divided by 100 and renormalised so
                # it sums to 1 — keeps the values on the simplex (Option A
                # from the design Q: independent sample + renormalise).
                if (any(c("lower_fraction", "upper_fraction",
                           "distribution_fraction") %in% names(mms_rows))) {
                  fraction_samples <- sample_per_mms_param(
                    mms_rows, "fraction_pct", "lower_fraction",
                    "upper_fraction", "distribution_fraction",
                    mc_n_iter, default_dist = "pert")
                  if (!is.null(fraction_samples)) {
                    # `pmax(0, x)` strips the matrix dim attribute; clamp
                    # in place to keep `fraction_samples` a matrix.
                    fraction_samples[fraction_samples < 0] <- 0
                    fraction_samples <- fraction_samples / 100
                    rs <- rowSums(fraction_samples)
                    rs[rs <= 0] <- 1  # safeguard against degenerate rows
                    fraction_samples <- fraction_samples / rs
                  }
                }

                # Reorder columns to match mms_fracs ordering.
                ord_names <- names(mms_fracs)
                if (!is.null(mcf_samples)) mcf_samples <- mcf_samples[, ord_names, drop = FALSE]
                if (!is.null(ef3_samples)) ef3_samples <- ef3_samples[, ord_names, drop = FALSE]
                if (!is.null(fg_samples))  fg_samples  <- fg_samples[, ord_names, drop = FALSE]
                if (!is.null(fl_samples))  fl_samples  <- fl_samples[, ord_names, drop = FALSE]
                if (!is.null(fraction_samples))
                  fraction_samples <- fraction_samples[, ord_names, drop = FALSE]
                # Final guard: if all MMS rows were unparsable, use defaults
                if (length(mms_fracs) == 0) {
                  mms_fracs <- default_mms_fracs
                  mcf_vals  <- default_mcf_vals
                  ef3_vals  <- default_ef3_vals
                }
              } else {
                mms_fracs <- default_mms_fracs
                mcf_vals  <- default_mcf_vals
                ef3_vals  <- default_ef3_vals
              }
            } else {
              mms_fracs <- default_mms_fracs
              mcf_vals  <- default_mcf_vals
              ef3_vals  <- default_ef3_vals
            }

            # R1.1 / Round 7 T4.3: build a UNIFIED correlation matrix over both
            # AD and coefficient parameters. The preset matrix and the time-series
            # matrix can both span both blocks (post-Round-7), so we expand the
            # user's matrix to the full (AD + coefficient) parameter list. This
            # supersedes the prior two-pass `corr_matrix` / `ef_corr_matrix` split,
            # though both inputs are still passed downstream for back-compat.
            ad_names   <- sys_specs$parameter[sys_specs$param_type == "activity_data"]
            coef_names <- sys_specs$parameter[sys_specs$param_type == "coefficient"]
            all_names  <- c(ad_names, coef_names)

            corr_mtx_active <- effective_corr_matrix()

            # isTRUE() wrap protects against input$corr_mode being NA mid-render
            # (the radioButtons("corr_mode", ...) is built inside a renderUI, so
            # input$corr_mode can transiently be NA right after Country X / Y
            # load when corr_mtx_active is already populated from the example's
            # synthetic time-series). Without isTRUE, `NA != "none"` returns NA,
            # `NA && TRUE` returns NA, and `if (NA)` throws "missing value where
            # TRUE/FALSE needed" — the exact error users reported on Country X.
            unified_corr <- if (isTRUE(input$corr_mode != "none") && !is.null(corr_mtx_active)) {
              expand_corr_matrix(corr_mtx_active, all_names)
            } else NULL

            ts_coef_corr <- if (isTRUE(input$corr_mode != "none") && !is.null(corr_mtx_active)) {
              expand_corr_matrix(corr_mtx_active, coef_names)
            } else NULL

            # AD block has only cattle_pop — within-block correlation is meaningless.
            corr <- NULL

            # If time-series matrix is available, prefer it over uniform-rho.
            ef_corr <- if (!is.null(ts_coef_corr)) {
              ts_coef_corr
            } else if (!is.null(rv$ef_corr_matrix)) {
              ef_n <- sum(sys_specs$param_type == "coefficient")
              if (nrow(rv$ef_corr_matrix) == ef_n) rv$ef_corr_matrix else NULL
            } else NULL

            # Andreas 2026-05 follow-up: Dirichlet MMS-allocation sampling
            # removed (not in IPCC guidance; MMS% is now deterministic).
            # Per-MMS uncertainty matrices (C4 / C6 fix) attached below.
            systems_data[[sg]] <- list(
              param_specs = sys_specs, corr_matrix = corr, ef_corr_matrix = ef_corr,
              unified_corr_matrix = unified_corr,
              mms_fractions = mms_fracs, mcf_values = mcf_vals, ef3_values = ef3_vals,
              frac_gas_values = frac_gas_vals, frac_leach_values = frac_leach_vals,
              mcf_samples = mcf_samples, ef3_samples = ef3_samples,
              frac_gas_samples = fg_samples, frac_leach_samples = fl_samples,
              # Andreas 28/5/26 #4: per-iteration MMS allocation samples
              mms_fraction_samples = fraction_samples
            )
          }

          # ---- Stage 2: Monte Carlo sampling ----
          n_sys <- length(sys_groups)

          # Duration heads-up for large runs. A big inventory (many sub-
          # categories) at high iteration counts — especially with the 3x
          # decomposition — can take several minutes. Tell the user to be
          # patient and keep the tab open, so a slow-but-working run isn't
          # mistaken for a hang. Framed around patience only — NO mention of
          # iteration counts to reduce or of hosting/server limits.
          decomp_mult <- if (isTRUE(input$run_decomposition)) 3L else 1L
          run_cost <- as.numeric(n_iter_val) * n_sys * decomp_mult
          if (run_cost >= 1.5e6) {
            showNotification(
              paste0("Large run in progress — this may take a few minutes. ",
                     "Please keep this browser tab open; the progress bar ",
                     "will keep updating until it finishes."),
              type = "message", duration = 12)
          }

          setProgress(0.08,
            detail = sprintf("Sampling %s iterations across %d system(s)...",
                             n_iter_fmt, n_sys))

          # Keep-alive: report progress once per system so the websocket keeps
          # receiving traffic during a long run on a large inventory (prevents
          # the shinyapps idle-disconnect Andy saw). The Combined run spans the
          # 0.48–0.88 progress band.
          keepalive_cb <- function(span_lo, span_hi, label = "Simulating") {
            force(span_lo); force(span_hi); force(label)
            function(done, total) {
              frac <- if (total > 0) done / total else 1
              setProgress(span_lo + (span_hi - span_lo) * frac,
                          detail = sprintf("%s — sub-category %d of %d…",
                                           label, done, total))
            }
          }
          sim_result <- run_inventory_simulation(
            systems_data, n_iter = n_iter_val,
            gwp = input$gwp_version, seed = input$seed,
            # Andreas 2026-05 follow-up: Tw is now sourced exclusively from
            # the Parameters template (per sub-category) — the UI input was
            # removed. pct_pregnant is still read here as a single global
            # value (Cp pro-rate applies inventory-wide).
            pct_pregnant = if (!is.null(input$pct_pregnant)) input$pct_pregnant else 1,
            # All correlated paths use the rank-correlation-preserving
            # restricted-pairing procedure (IPCC Vol.1 Ch.3 §3.2.3.2).
            sampler = "iman_conover",
            progress_cb = keepalive_cb(0.48, 0.88, "Main run"),
            # Cap retained input draws (memory): the full-n_iter results behind
            # every reported figure are unaffected — only the samples used for
            # the sensitivity ranking / density plots are thinned.
            keep_sample_rows = 4000L
          )

          # T1.12: zero out per-source contributions the user has unchecked.
          # The per-source columns are kept (for sensitivity / per-system tables);
          # only the headline totals (total_ch4, total_n2o, total_co2e) are
          # recomputed to reflect the selection.
          srcs <- input$emission_sources %||% character()
          gwp_vals <- GWP_VALUES[[input$gwp_version]]
          # Andreas 2026-05-21 bug: the per-system results frame names the
          # per-source columns `enteric_ch4_total`, `manure_ch4_total`,
          # `direct_n2o_mm_total`, ..., while the aggregated `inventory` frame
          # built in run_inventory_simulation() uses `total_enteric_ch4`,
          # `total_manure_ch4`, `total_direct_n2o_mm`, ..., a different
          # convention. The single-year run filters BOTH frames through
          # .apply_source_selection() below — so the function has to accept
          # either naming. Previously it knew only the per-system names, so
          # when applied to the inventory frame every column lookup returned
          # NULL, the arithmetic collapsed to length 0, and downstream code
          # surfaced the cryptic "replacement has 0 rows" / "missing value
          # where TRUE/FALSE required" error. The helper below resolves a
          # column by either name, with a numeric-0 fallback when the column
          # genuinely does not exist (so per-system frames that legitimately
          # lack PRP columns still work).
          .col_or_zero <- function(df, suffix_name, prefix_name) {
            if (!is.null(df[[suffix_name]])) df[[suffix_name]]
            else if (!is.null(df[[prefix_name]])) df[[prefix_name]]
            else 0
          }
          .apply_source_selection <- function(df) {
            ch4 <- (if ("enteric_ch4" %in% srcs)
                      .col_or_zero(df, "enteric_ch4_total", "total_enteric_ch4")
                    else 0) +
                   (if ("manure_ch4"  %in% srcs)
                      .col_or_zero(df, "manure_ch4_total",  "total_manure_ch4")
                    else 0)
            # Andreas 2026-05 #27: pasture direct and indirect are separate IPCC
            # reporting categories — splitting the single legacy `pasture_n2o`
            # checkbox into two. Old `pasture_n2o` kept as a back-compat alias
            # for any saved bookmarks / URLs.
            legacy_pasture <- "pasture_n2o" %in% srcs
            n2o <- (if ("manure_n2o_direct"   %in% srcs)
                      .col_or_zero(df, "direct_n2o_mm_total",   "total_direct_n2o_mm")
                    else 0) +
                   (if ("manure_n2o_indirect" %in% srcs)
                      .col_or_zero(df, "indirect_n2o_mm_total", "total_indirect_n2o_mm")
                    else 0) +
                   (if (legacy_pasture || "pasture_n2o_direct"   %in% srcs)
                      .col_or_zero(df, "direct_n2o_prp_total",   "total_direct_n2o_prp")
                    else 0) +
                   (if (legacy_pasture || "pasture_n2o_indirect" %in% srcs)
                      .col_or_zero(df, "indirect_n2o_prp_total", "total_indirect_n2o_prp")
                    else 0)
            df$total_ch4  <- ch4
            df$total_n2o  <- n2o
            df$co2e_ch4   <- ch4 * gwp_vals$CH4
            df$co2e_n2o   <- n2o * gwp_vals$N2O
            df$total_co2e <- df$co2e_ch4 + df$co2e_n2o
            df
          }
          # 6 sources now (pasture direct & indirect split). Skip
          # re-aggregation when the user has all 6 ticked.
          if (length(srcs) > 0 && length(srcs) < 6) {
            sim_result$inventory <- .apply_source_selection(sim_result$inventory)
            for (sn in names(sim_result$by_system)) {
              sim_result$by_system[[sn]]$results <- .apply_source_selection(
                sim_result$by_system[[sn]]$results)
            }
            rv$sim_log <- paste0(rv$sim_log, "Source selection: ",
                                 paste(srcs, collapse = ", "), "\n")
          }
          rv$mc_results        <- sim_result
          rv$show_diagnostics  <- FALSE

          local({
            co2e <- sim_result$inventory$total_co2e
            n    <- length(co2e)
            n2   <- floor(n / 2L)
            h1   <- co2e[seq_len(n2)]
            h2   <- co2e[seq(n2 + 1L, n)]
            om   <- mean(co2e)
            oci  <- quantile(co2e, c(0.025, 0.975), names = FALSE)
            ci1  <- quantile(h1,   c(0.025, 0.975), names = FALSE)
            ci2  <- quantile(h2,   c(0.025, 0.975), names = FALSE)
            rv$diagnostics <- list(
              n            = n,
              mcse_pct     = (sd(co2e) / om) / sqrt(n) * 100,
              drift_pct    = abs(mean(h1) - mean(h2)) / om * 100,
              ci_drift_pct = mean(abs(ci1 - ci2) / pmax(abs(oci), .Machine$double.eps)) * 100,
              skew_val     = mean(((co2e - om) / sd(co2e))^3),
              trace        = compute_diag_trace(co2e)
            )
          })

          # ---- Stage 3: uncertainty metrics ----
          setProgress(0.40, detail = "Computing uncertainty metrics...")
          rv$uncertainty <- calc_all_uncertainty(sim_result$inventory)
          rv$sim_log <- paste0(rv$sim_log, "Simulation complete.\n")

          # ---- Stage 4: decomposition (AD-only + EF-only, multi-group safe) ----
          # Run two additional full-inventory simulations with parameters locked:
          #   AD-only  — all emission-factor/coefficient params fixed at their means
          #   EF-only  — all activity-data params fixed at their means
          # Works for any number of cattle groups because it uses the same
          # run_inventory_simulation() pipeline as the main run.
          if (isTRUE(input$run_decomposition)) {
            setProgress(0.48, detail = sprintf("Running AD-only simulation (%d group(s))...",
                                               length(systems_data)))

            fix_params <- function(sd, fix_type) {
              ps <- sd$param_specs
              ps$param_type[is.na(ps$param_type)] <- "coefficient"
              rows <- ps$param_type == fix_type
              ps$distribution[rows] <- "constant"
              ps$lower[rows] <- ps$mean[rows]
              ps$upper[rows] <- ps$mean[rows]
              sd$param_specs <- ps
              if (fix_type == "coefficient") {
                sd$ef_corr_matrix <- NULL
                # Andreas 28/5/26 #9: per-MMS sample matrices (mcf_samples,
                # ef3_samples, frac_gas_samples, frac_leach_samples) and the
                # MMS-allocation sample matrix (mms_fraction_samples) all
                # carry coefficient-side variance — they were leaking
                # iteration-to-iteration MCF / EF3 / Frac variation into the
                # AD-only run, so AD-only CV differed across emission sources
                # even though N was the only AD parameter. Null them here so
                # the AD-only run sees deterministic per-MMS values
                # (mcf_values / ef3_values / frac_gas_values / frac_leach_values
                # / mms_fractions are still respected — they are the central
                # values used when the matrices are NULL).
                sd$mcf_samples           <- NULL
                sd$ef3_samples           <- NULL
                sd$frac_gas_samples      <- NULL
                sd$frac_leach_samples    <- NULL
                sd$mms_fraction_samples  <- NULL
              }
              if (fix_type == "activity_data") {
                sd$corr_matrix         <- NULL
                sd$unified_corr_matrix <- NULL
                # Per-MMS sample matrices STAY active in the EF-only run —
                # they are coefficient-side variance and are exactly what
                # the EF-only run is meant to expose.
              }
              sd
            }

            systems_ad <- lapply(systems_data, fix_params, fix_type = "coefficient")
            ad_result  <- run_inventory_simulation(
              systems_ad, n_iter = n_iter_val,
              gwp = input$gwp_version, seed = input$seed,
              pct_pregnant = if (!is.null(input$pct_pregnant)) input$pct_pregnant else 1,
              progress_cb = keepalive_cb(0.48, 0.68, "AD-only run"),
              # Cap retained samples to lower the transient peak; this run's
              # samples are never read (decomposition uses only its inventory).
              keep_sample_rows = 4000L
            )
            # Keep only the summary metrics; free the AD-only sample/result
            # matrices before the EF-only pass so the three full simulations
            # don't sit in memory simultaneously (free tier is ~1 GB RAM —
            # holding all three risks an out-of-memory abort on a large run).
            ad_unc <- calc_all_uncertainty(ad_result$inventory)
            rm(systems_ad, ad_result); invisible(gc(FALSE))

            setProgress(0.70, detail = sprintf("Running EF-only simulation (%d group(s))...",
                                               length(systems_data)))
            systems_ef <- lapply(systems_data, fix_params, fix_type = "activity_data")
            ef_result  <- run_inventory_simulation(
              systems_ef, n_iter = n_iter_val,
              gwp = input$gwp_version, seed = input$seed,
              pct_pregnant = if (!is.null(input$pct_pregnant)) input$pct_pregnant else 1,
              progress_cb = keepalive_cb(0.70, 0.88, "EF-only run"),
              # Cap retained samples to lower the transient peak; this run's
              # samples are never read (decomposition uses only its inventory).
              keep_sample_rows = 4000L
            )
            ef_unc <- calc_all_uncertainty(ef_result$inventory)
            rm(systems_ef, ef_result); invisible(gc(FALSE))

            rv$decomposition <- list(
              combined = rv$uncertainty,
              ad_only  = ad_unc,
              ef_only  = ef_unc
            )
            rv$ipcc_table <- format_ipcc_table(rv$decomposition)
            rv$sim_log <- paste0(rv$sim_log,
              sprintf("Uncertainty decomposition complete (%d group(s)).\n", length(systems_data)))
            setProgress(0.90, detail = "Decomposition complete.")
          } else {
            rv$sim_log  <- paste0(rv$sim_log,
              "Uncertainty decomposition skipped (checkbox unchecked).\n")
            rv$ipcc_table <- NULL
            setProgress(0.90, detail = "Decomposition skipped.")
          }

          # ---- Stage 5: sensitivity analysis ----
          # For multi-group inventories, combine each group's parameter samples
          # and regress against the TOTAL inventory CO2eq. Aggregate sensitivity
          # rankings — not rankings for the first group only.
          # Andreas 28/5/26 #8: column labels now read "param (sub_category)"
          # so the tornado clearly identifies which animal sub-category each
          # influential parameter belongs to (e.g. "Ym (DINT_cow)" vs
          # "Ym (DINT_heif)"). Inventory teams can then target research at the
          # specific sub-category that drives uncertainty rather than the
          # ambiguous "Ym" label. The helper is also exposed at server scope
          # so the per-source sensitivity dropdown (active_sensitivity below)
          # can aggregate across systems instead of falling back to the first
          # system only.

          setProgress(0.92, detail = "Running sensitivity analysis...")
          # Sensitivity is a SECONDARY analysis — isolate it so a failure here
          # leaves the main results (Tab 5) and the IPCC report (Tab 7) intact.
          # Before this guard, an error inside aggregate_sensitivity (e.g. the
          # "undefined columns selected" crash from a NaN/degenerate sample
          # column) propagated to the top-level handler and flagged the whole
          # run as failed even though the emissions had computed fine.
          if (length(sim_result$by_system) > 0) {
            rv$sensitivity <- tryCatch(
              aggregate_sensitivity(
                sim_result$by_system, sim_result$inventory$total_co2e),
              error = function(e) {
                rv$sim_log <- paste0(rv$sim_log,
                  "WARNING: sensitivity analysis could not be computed: ",
                  conditionMessage(e),
                  "\n  (Main results and the IPCC report are unaffected.)\n")
                out <- list()
                attr(out, "message") <- paste0(
                  "Sensitivity analysis is unavailable for this run (",
                  conditionMessage(e),
                  "). The emission results and uncertainty figures on the ",
                  "other tabs are unaffected.")
                out
              })
            if (length(rv$sensitivity) > 0)
              rv$sim_log <- paste0(rv$sim_log,
                sprintf("Sensitivity analysis complete (%d group(s)).\n",
                        length(sim_result$by_system)))
            # Release the transient regression memory before any comparison
            # run / sensitivity below (keeps peak RAM down on large runs).
            invisible(gc(FALSE))
          }

          # ---- Stage 6: comparison run (no correlations) ----
          rv$comparison_result      <- NULL
          rv$comparison_sensitivity <- NULL
          if (isTRUE(input$run_comparison)) {
            setProgress(0.94, detail = "Running comparison (no correlations)...")
            # 2026-06: must also null unified_corr_matrix here. Since the
            # Round 7 unified-matrix refactor, the preset / time-series /
            # manual matrices all flow through unified_corr_matrix (not the
            # legacy corr_matrix / ef_corr_matrix slots, which the new code
            # path leaves NULL on the main run). Nulling only the legacy two
            # meant the comparison run quietly kept applying the unified
            # matrix and produced bars identical to the main run.
            systems_nocorr <- lapply(systems_data, function(s) {
              s$corr_matrix         <- NULL
              s$ef_corr_matrix      <- NULL
              s$unified_corr_matrix <- NULL
              s
            })
            nocorr_result <- run_inventory_simulation(
              systems_nocorr, n_iter = n_iter_val,
              gwp = input$gwp_version, seed = input$seed,
              # Keep-alive: this 4th full simulation was the one stage with no
              # progress ticks, so the connection went silent during it and was
              # dropped ("Disconnected from the server" during "Running
              # comparison"). Wire the heartbeat here too.
              progress_cb = keepalive_cb(0.94, 0.99, "Comparison (no correlations)"),
              # Cap retained input draws: this second full result set persists in
              # rv$comparison_result for the session. Its inventory (full n_iter)
              # still drives the with/without-correlation CV comparison; only the
              # samples feeding the "without correlations" tornado are thinned.
              keep_sample_rows = 4000L
            )
            rv$comparison_result <- nocorr_result
            if (length(nocorr_result$by_system) > 0) {
              rv$comparison_sensitivity <- tryCatch(
                aggregate_sensitivity(
                  nocorr_result$by_system, nocorr_result$inventory$total_co2e),
                error = function(e) {
                  rv$sim_log <- paste0(rv$sim_log,
                    "WARNING: comparison sensitivity could not be computed: ",
                    conditionMessage(e), "\n")
                  NULL
                })
            }
            rv$sim_log <- paste0(rv$sim_log, "Comparison (no correlations) complete.\n")
            invisible(gc(FALSE))
            setProgress(0.99, detail = "Comparison complete.")
          }

          setProgress(1.00, detail = "Done.")
          rv$sim_running <- FALSE

          # Round 6a #6: flip directly to the results panel on every successful
          # run (not just the first one) and surface a short toast that doesn't
          # mention scrolling — the page already swaps to the results view.
          rv$sim_view <- "results"
          showNotification("Simulation complete — results displayed.",
                           type = "message", duration = 4)

        },
        error = function(e) {
          # withCallingHandlers: this runs BEFORE the stack unwinds. Snap the
          # call chain here so the outer tryCatch (which sees an already-
          # unwound stack) can log the real culprit. Capped at 40 frames.
          sc <- tryCatch(sys.calls(), error = function(.e) NULL)
          if (!is.null(sc))
            captured_stack <<- tail(vapply(sc, function(call)
              substr(paste(deparse(call), collapse = " "), 1, 240),
              character(1)), 40)
        }),
        error = function(e) {
          rv$sim_log <- paste0(rv$sim_log,
            "ERROR: ", e$message, "\n",
            if (length(captured_stack) > 0)
              paste0("call stack (innermost last):\n  ",
                     paste(captured_stack, collapse = "\n  "), "\n")
            else "")
          rv$sim_error <- e$message
          rv$sim_running <- FALSE
          # Make the failure visible — previously the error only landed in the
          # Tab 5 sim log, so users could click Simulate and see nothing happen.
          showNotification(
            paste0("Simulation failed: ", e$message,
                   " — see the Run log on Tab 5 for the full call trace."),
            type = "error", duration = NULL)
        })
      }
    )
  })

  output$sim_log <- renderText(rv$sim_log)

  # B2: drives the inline results section visibility on the merged Tab 5
  output$sim_complete <- reactive({
    !is.null(rv$mc_results) && !is.null(rv$uncertainty)
  })
  outputOptions(output, "sim_complete", suspendWhenHidden = FALSE)

  # R1.5 / Round 6a #6: switch to results view when the simulation completes.
  # The flip is forced directly in the run handler, so this observer is now
  # only a fallback for the first-run case.
  observe({
    if (!is.null(rv$mc_results) && !is.null(rv$uncertainty)) {
      isolate({
        rv$sim_view <- "results"
      })
    }
  })

  # Back button: return to settings
  observeEvent(input$show_settings_btn, {
    rv$sim_view <- "settings"
  })

  # Select all / Deselect all toggle for emission sources
  .all_source_vals <- c("enteric_ch4", "manure_ch4", "manure_n2o_direct",
                        "manure_n2o_indirect", "pasture_n2o_direct", "pasture_n2o_indirect")

  output$select_all_btn <- renderUI({
    all_selected <- setequal(input$emission_sources %||% character(0), .all_source_vals)
    actionButton("toggle_all_sources",
      label = if (all_selected) "Deselect all" else "Select all sources",
      class = "btn-outline-secondary btn-sm w-100 mb-1",
      icon  = if (all_selected) icon("square") else icon("check-square"))
  })
  outputOptions(output, "select_all_btn", suspendWhenHidden = FALSE)

  observeEvent(input$toggle_all_sources, {
    if (setequal(input$emission_sources %||% character(0), .all_source_vals)) {
      updateCheckboxGroupInput(session, "emission_sources", selected = character(0))
    } else {
      updateCheckboxGroupInput(session, "emission_sources", selected = .all_source_vals)
    }
  })

  output$sim_view <- reactive(rv$sim_view)
  outputOptions(output, "sim_view", suspendWhenHidden = FALSE)

  output$sim_status <- renderUI({
    if (!is.null(rv$sim_error)) {
      tags$div(
        style = "color:#C1121F; font-weight:600; margin-top:8px;",
        icon("exclamation-triangle"), " Error: ", rv$sim_error
      )
    } else if (!is.null(rv$mc_results)) {
      n_sys <- if (!is.null(rv$mc_results$by_system)) length(rv$mc_results$by_system) else 1
      tags$div(
        style = "color:#2D6A4F; font-weight:600; margin-top:8px;",
        icon("check-circle"),
        sprintf(" Complete — %d system(s) simulated.", n_sys)
      )
    } else {
      tags$div(style = "color:#6B6B6B; margin-top:8px;", "Ready to run.")
    }
  })

  # --- RESULTS ---

  output$vb_ch4 <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_ch4", ]
    if (nrow(row) > 0) paste0(round(row$mean, 1), " t") else "---"
  })

  output$vb_n2o <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_n2o", ]
    if (nrow(row) > 0) paste0(round(row$mean, 3), " t") else "---"
  })

  # Andreas 2026-05 C1: per-IPCC-source value boxes — mirrors the IPCC
  # reporting categories (enteric CH₄, manure CH₄, MM N₂O total, PRP N₂O total).
  # Column names refer to inventory aggregator output (mc_simulation.R
  # run_inventory_simulation), not per-system results.
  #
  # Andreas 28/5/26 #6: per-source value boxes now include a 95 % MoE
  # suffix (e.g. "1,234 t · ±12 %") so the headline uncertainty is visible
  # without drilling into the by-system table. IPCC uses MoE % (the half-
  # width of the 95 % CI as a fraction of the mean), not CV — confirmed by
  # IPCC 2006 Vol.1 Ch.3 Table 3.3.
  .moe_suffix <- function(row) {
    if (nrow(row) == 0 || is.na(row$moe_pct)) return("")
    paste0(" · ±", round(row$moe_pct, 1), "%")
  }
  .vb_mean <- function(var) {
    row <- rv$uncertainty[rv$uncertainty$variable == var, ]
    if (nrow(row) == 0) return("---")
    paste0(round(row$mean, if (row$mean < 10) 3 else 1), " t",
           .moe_suffix(row))
  }
  .vb_sum_means <- function(vars) {
    rows <- rv$uncertainty[rv$uncertainty$variable %in% vars, ]
    if (nrow(rows) == 0) return("---")
    s <- sum(rows$mean, na.rm = TRUE)
    # MoE on a sum of (positively correlated) per-iteration vectors is not
    # the sum of MoEs — compute it from the per-iteration combined series
    # in the inventory frame when available; otherwise fall back to the
    # max of the contributing MoEs as a conservative estimate.
    moe_str <- ""
    if (!is.null(rv$mc_results$inventory)) {
      inv <- rv$mc_results$inventory
      cols <- intersect(vars, names(inv))
      if (length(cols) > 0) {
        x <- rowSums(inv[, cols, drop = FALSE])
        if (length(x) > 1 && mean(x) > 0) {
          lo <- stats::quantile(x, 0.025, names = FALSE)
          hi <- stats::quantile(x, 0.975, names = FALSE)
          moe <- ((hi - lo) / 2) / mean(x) * 100
          moe_str <- paste0(" · ±", round(moe, 1), "%")
        }
      }
    }
    paste0(round(s, if (s < 10) 3 else 1), " t", moe_str)
  }
  output$vb_enteric_ch4 <- renderText({ req(rv$uncertainty); .vb_mean("total_enteric_ch4") })
  output$vb_manure_ch4  <- renderText({ req(rv$uncertainty); .vb_mean("total_manure_ch4") })
  output$vb_manure_n2o  <- renderText({
    req(rv$uncertainty)
    .vb_sum_means(c("total_direct_n2o_mm", "total_indirect_n2o_mm"))
  })
  output$vb_pasture_n2o <- renderText({
    req(rv$uncertainty)
    .vb_sum_means(c("total_direct_n2o_prp", "total_indirect_n2o_prp"))
  })

  output$vb_co2e <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_co2e", ]
    if (nrow(row) > 0) paste0(round(row$mean, 1), " t CO2eq") else "---"
  })

  # T6.3: secondary inline display of CO2eq (kept for sensitivity)
  output$vb_co2e_inline <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_co2e", ]
    if (nrow(row) > 0) paste0(round(row$mean, 1), " t (95% CI ",
                              round(row$ci_lower, 1), "–",
                              round(row$ci_upper, 1), ")") else "---"
  })

  # Andreas 28/5/26 #6: the value box previously titled "Total CV (%)" now
  # shows the inventory-total 95 % MoE — IPCC's reporting convention. CV is
  # still available alongside MoE in the by-system / by-category tables for
  # users who want both.
  output$vb_moe_total <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_co2e", ]
    if (nrow(row) > 0) paste0("±", round(row$moe_pct, 1), "%") else "---"
  })

  # T6.1 / T8.1: IPCC 95% margin of error
  output$vb_moe <- renderText({
    req(rv$uncertainty)
    row <- rv$uncertainty[rv$uncertainty$variable == "total_co2e", ]
    if (nrow(row) > 0) paste0("±", round(row$moe_pct, 1), "%") else "---"
  })

  output$results_histogram <- plotly::renderPlotly({
    req(rv$mc_results)
    co2e <- rv$mc_results$inventory$total_co2e
    co2e <- co2e[is.finite(co2e)]
    ci <- quantile(co2e, c(0.025, 0.975))

    # Robust display window. A few extreme draws from heavy-tailed emission
    # factors (e.g. lognormal EF4 / EF5) can otherwise stretch the x-axis and
    # collapse the whole distribution into a single bar at the left. Bin and
    # display over the 0.5-99.5 percentile window so the bulk of the
    # distribution is legible; note how many iterations fall outside the view.
    # (The DE-domain clamp in generate_mc_samples() removes the impossible
    # blow-ups at source; this is a display safeguard for any residual tail.)
    disp     <- as.numeric(quantile(co2e, c(0.005, 0.995)))
    bin_size <- (disp[2] - disp[1]) / 50
    n_out    <- sum(co2e < disp[1] | co2e > disp[2])

    xbins <- if (is.finite(bin_size) && bin_size > 0)
      list(start = disp[1], end = disp[2], size = bin_size) else NULL
    xaxis <- list(title = t("res_hist_xaxis"))
    if (!is.null(xbins)) xaxis$range <- c(disp[1], disp[2])

    p <- plotly::plot_ly(x = co2e, type = "histogram", nbinsx = 50, xbins = xbins,
                    marker = list(color = "#2D6A4F", line = list(color = "#1B4332", width = 1))) %>%
      plotly::layout(
        title = t("res_hist_chart_title"),
        xaxis = xaxis,
        yaxis = list(title = t("res_hist_yaxis")),
        shapes = list(
          list(type = "line", x0 = ci[1], x1 = ci[1], y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#C1121F", dash = "dash")),
          list(type = "line", x0 = ci[2], x1 = ci[2], y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#C1121F", dash = "dash"))
        )
      )
    if (n_out > 0) {
      p <- p %>% plotly::layout(annotations = list(list(
        x = 1, y = 1, xref = "paper", yref = "paper",
        xanchor = "right", yanchor = "bottom", showarrow = FALSE,
        font = list(size = 10, color = "#777777"),
        text = sprintf(t("res_hist_outlier_note"), n_out, length(co2e)))))
    }
    p
  })

  # Andreas 28/5/26 #6: the AD / EF / Combined decomposition chart now
  # uses 95 % MoE on the y-axis (IPCC Vol.1 Ch.3 Table 3.3 convention),
  # not CV. The underlying decomposition data frame still carries both
  # cv_pct and moe_pct, so consumers that want CV can pull it from
  # rv$decomposition directly.
  output$decomposition_plot <- plotly::renderPlotly({
    req(rv$decomposition)
    cat_keys <- c("AD Only", "EF Only", "Combined")
    moe_vals <- sapply(cat_keys, function(k) {
      df <- switch(k,
        "AD Only"  = rv$decomposition$ad_only,
        "EF Only"  = rv$decomposition$ef_only,
        "Combined" = rv$decomposition$combined
      )
      row <- df[df$variable == "total_co2e", ]
      if (nrow(row) > 0) row$moe_pct else NA
    })
    cat_labels <- c(t("res_decomp_ad_label"),
                     t("res_decomp_ef_label"),
                     t("res_decomp_combined_label"))

    plotly::plot_ly(x = cat_labels, y = moe_vals, type = "bar",
                    marker = list(color = c("#40916C", "#4361EE", "#2D6A4F"))) %>%
      plotly::layout(title = t("res_decomp_chart_title"),
                     yaxis = list(title = t("res_decomp_yaxis")))
  })

  # ---- Simulation diagnostics ----

  observeEvent(input$toggle_diagnostics, {
    rv$show_diagnostics <- !rv$show_diagnostics
  })

  output$has_diagnostics <- reactive({ !is.null(rv$diagnostics) })
  outputOptions(output, "has_diagnostics", suspendWhenHidden = FALSE)

  output$show_diagnostics <- reactive({ isTRUE(rv$show_diagnostics) })
  outputOptions(output, "show_diagnostics", suspendWhenHidden = FALSE)

  output$diag_badges <- renderUI({
    req(rv$diagnostics)
    d <- rv$diagnostics

    mcse_s  <- if (d$mcse_pct     <  0.5) "pass" else if (d$mcse_pct     < 1)  "warn" else "fail"
    drift_s <- if (d$drift_pct    <  2.0) "pass" else if (d$drift_pct    < 5)  "warn" else "fail"
    ci_s    <- if (d$ci_drift_pct <  5.0) "pass" else if (d$ci_drift_pct < 10) "warn" else "fail"

    skew_label <- if (abs(d$skew_val) < 0.5) "symmetric"
                  else if (d$skew_val  > 0)   "right-skewed (expected)"
                  else                          "left-skewed"
    skew_note  <- if (abs(d$skew_val) > 3) " — extreme, check draws" else ""

    iter_warning <- if (d$n < 10000) {
      div(style = paste0("background:#FEF3C7; border-left:4px solid #F59E0B;",
                         "padding:10px 14px; border-radius:4px; margin-bottom:12px;",
                         "font-size:0.88rem; color:#92400E;"),
          icon("triangle-exclamation"),
          tags$strong(sprintf(" %s iterations used.", format(d$n, big.mark = ","))),
          " Tail percentile estimates (2.5th / 97.5th) can still be noisy at this sample size.",
          " For submission-quality results, consider re-running with at least 10,000 iterations."
      )
    } else NULL

    tagList(
      iter_warning,
      bslib::layout_columns(
      col_widths = NULL,
      make_diag_badge(
        "Precision (MCSE)",
        paste0("Monte Carlo Standard Error: measures how much the reported mean would shift if ",
               "you re-ran with a different random seed. Aim for < 0.5% of the mean (green). ",
               "At 10,000 iterations a typical livestock-inventory MCSE is ~0.2% — comfortably inside the green band. ",
               "At 1,000 iterations it would be ~0.6%, which is borderline; raise the iteration count if you see this."),
        sprintf("%.2f%% of mean", d$mcse_pct),
        mcse_s
      ),
      make_diag_badge(
        "Mean Stability",
        paste0("Compares the average emission from the first half of iterations to the second half. ",
               "If they agree closely, the sample is large enough. Aim for < 2% difference (green). ",
               "A difference > 5% means your results depend on which random draws happened early vs late."),
        sprintf("%.1f%% drift (1st vs 2nd half)", d$drift_pct),
        drift_s
      ),
      make_diag_badge(
        "95% CI Stability",
        paste0("Compares the 95% confidence interval bounds from the first half vs the second half of iterations. ",
               "Percentile estimates are noisier than means and need more iterations to stabilise. ",
               "Aim for < 5% drift (green). If this fails, increase iterations significantly (try 30,000+)."),
        sprintf("%.1f%% drift (1st vs 2nd half)", d$ci_drift_pct),
        ci_s
      ),
      make_diag_badge(
        "Distribution Skew",
        paste0("Measures the asymmetry of the simulated emission distribution. ",
               "Positive (right-skewed) is normal and expected when emission factors follow lognormal distributions — this is not a problem. ",
               "Values beyond ±3 may indicate extreme outlier draws; if so, review your input uncertainty bounds."),
        sprintf("%.2f (%s%s)", d$skew_val, skew_label, skew_note),
        "info"
      )
    )
    )  # tagList
  })

  output$convergence_plot <- plotly::renderPlotly({
    req(rv$diagnostics)
    tr <- rv$diagnostics$trace
    plotly::plot_ly() |>
      plotly::add_ribbons(
        x = tr$iter, ymin = tr$running_lo, ymax = tr$running_hi,
        fillcolor = "rgba(59,130,246,0.12)",
        line = list(color = "transparent"),
        showlegend = FALSE, hoverinfo = "skip"
      ) |>
      plotly::add_lines(
        x = tr$iter, y = tr$running_mean,
        line = list(color = "#2D6A4F", width = 2.5),
        name = "Running mean"
      ) |>
      plotly::add_lines(
        x = tr$iter, y = tr$running_lo,
        line = list(color = "#3B82F6", width = 1.5, dash = "dash"),
        name = "Running 2.5th pct"
      ) |>
      plotly::add_lines(
        x = tr$iter, y = tr$running_hi,
        line = list(color = "#3B82F6", width = 1.5, dash = "dash"),
        name = "Running 97.5th pct"
      ) |>
      plotly::layout(
        xaxis  = list(title = "Iteration number"),
        yaxis  = list(title = "Total CO₂eq (t)"),
        shapes = list(
          list(type = "line", x0 = min(tr$iter), x1 = max(tr$iter),
               y0 = tr$final_mean, y1 = tr$final_mean,
               line = list(color = "#1B4332", dash = "dash", width = 1.5)),
          list(type = "line", x0 = min(tr$iter), x1 = max(tr$iter),
               y0 = tr$final_lo, y1 = tr$final_lo,
               line = list(color = "#3B82F6", dash = "dot", width = 1)),
          list(type = "line", x0 = min(tr$iter), x1 = max(tr$iter),
               y0 = tr$final_hi, y1 = tr$final_hi,
               line = list(color = "#3B82F6", dash = "dot", width = 1))
        ),
        legend = list(x = 0.75, y = 0.98, xanchor = "left", yanchor = "top",
                      bgcolor = "rgba(255,255,255,0.85)",
                      bordercolor = "#E0DDD5", borderwidth = 1),
        margin = list(t = 10, b = 10)
      )
  })
  outputOptions(output, "convergence_plot", suspendWhenHidden = FALSE)

  # Andreas 2026-05 #32, C2: aggregate by_system results by user-chosen level
  # (cattle_type / aggregation_level / sub_category). sys_name encodes
  # `cattle_type||aggregation_level||sub_category` (see make_group_key in the
  # simulation block above). Returns a named list of per-group iteration data
  # frames where each emission column is the sum of contributing sub-categories.
  .agg_results_by_level <- function(level = "cattle_type") {
    by_sys <- rv$mc_results$by_system
    sys_names <- names(by_sys)
    if (length(sys_names) == 0) return(list())
    parts <- strsplit(sys_names, "\\|\\|", fixed = FALSE)
    idx <- switch(level, "cattle_type" = 1, "aggregation_level" = 2, "sub_category" = 3, 1)
    group_keys <- sapply(parts, function(p) {
      if (length(p) >= idx && nzchar(p[idx])) p[idx] else paste(p, collapse = " / ")
    })
    out <- list()
    for (g in unique(group_keys)) {
      members <- sys_names[group_keys == g]
      frames <- lapply(members, function(sn) by_sys[[sn]]$results)
      # Sum the iteration-aligned frames cell-wise across members.
      combined <- frames[[1]]
      if (length(frames) > 1) {
        for (k in 2:length(frames)) {
          for (col in names(combined)) {
            combined[[col]] <- combined[[col]] + frames[[k]][[col]]
          }
        }
      }
      out[[g]] <- combined
    }
    out
  }

  # Andreas 28/5/26 #7.1: tell the UI whether the inventory has more than
  # one cattle_type so the headline-split card can show/hide automatically.
  output$has_multi_cattle_type <- reactive({
    by_sys <- rv$mc_results$by_system
    if (is.null(by_sys) || length(by_sys) == 0) return(FALSE)
    parts <- strsplit(names(by_sys), "\\|\\|", fixed = FALSE)
    ct <- unique(sapply(parts, function(p) if (length(p) >= 1) p[1] else ""))
    length(ct) > 1
  })
  outputOptions(output, "has_multi_cattle_type", suspendWhenHidden = FALSE)

  # Andreas 28/5/26 #7.1: compact summary table directly under the headline
  # value boxes. One row per cattle_type, columns = the four headline
  # emission sources + total CO₂eq. Mean and 95 % MoE % per cell. Uses the
  # existing .agg_results_by_level("cattle_type") helper.
  output$results_headline_by_cattle_type <- DT::renderDT({
    req(rv$mc_results)
    agg <- .agg_results_by_level("cattle_type")
    if (length(agg) == 0) return(DT::datatable(data.frame()))
    fmt <- function(x) {
      m  <- mean(x); if (!is.finite(m) || m == 0) return("0")
      lo <- quantile(x, 0.025, names = FALSE)
      hi <- quantile(x, 0.975, names = FALSE)
      moe <- ((hi - lo) / 2) / m * 100
      sprintf("%.3g ± %.1f%%", m, moe)
    }
    rows <- lapply(names(agg), function(gn) {
      r <- agg[[gn]]
      manure_n2o  <- r$direct_n2o_mm_total  + r$indirect_n2o_mm_total
      pasture_n2o <- r$direct_n2o_prp_total + r$indirect_n2o_prp_total
      data.frame(
        cattle = gn,
        enteric = fmt(r$enteric_ch4_total),
        m_ch4 = fmt(r$manure_ch4_total),
        m_n2o = fmt(manure_n2o),
        p_n2o = fmt(pasture_n2o),
        co2e  = fmt(r$total_co2e),
        check.names = FALSE)
    })
    df <- do.call(rbind, rows)
    names(df) <- c(t("res_col_cattle_type"),
                    t("res_col_enteric_ch4_t"),
                    t("res_col_manure_ch4_t"),
                    t("res_col_manure_n2o_t"),
                    t("res_col_pasture_n2o_t"),
                    t("res_col_total_co2e_t"))
    DT::datatable(df, rownames = FALSE,
                  options = list(dom = "t", paging = FALSE, ordering = FALSE,
                                 scrollX = TRUE))
  })

  output$results_by_system <- DT::renderDT({
    req(rv$mc_results)
    level <- input$results_aggregation_level %||% "cattle_type"
    agg <- .agg_results_by_level(level)
    if (length(agg) == 0) return(DT::datatable(data.frame()))
    summary_rows <- lapply(names(agg), function(gn) {
      res <- agg[[gn]]
      m   <- mean(res$total_co2e)
      lo  <- quantile(res$total_co2e, 0.025, names = FALSE)
      hi  <- quantile(res$total_co2e, 0.975, names = FALSE)
      data.frame(
        g    = gn,
        ch4  = round(mean(res$total_ch4), 2),
        n2o  = round(mean(res$total_n2o), 4),
        co2e = round(m, 2),
        moe  = round(((hi - lo) / 2) / m * 100, 1),
        lo   = round(lo, 2),
        hi   = round(hi, 2),
        check.names = FALSE
      )
    })
    df <- do.call(rbind, summary_rows)
    names(df) <- c(t("res_col_group"), t("res_col_mean_ch4_t"),
                    t("res_col_mean_n2o_t"), t("res_col_mean_co2e_t"),
                    t("res_col_moe_pct"),
                    t("res_col_ci_lower_t"), t("res_col_ci_upper_t"))
    DT::datatable(df, rownames = FALSE,
                  options = list(pageLength = 20, scrollX = TRUE))
  })

  # T6.2: per-reporting-category breakdown grouped by the aggregation level
  # chosen on the Results tab (#32, C2).
  # Andreas 28/5/26 #7.2 + #7.3: always show cattle_type as a column (even
  # when the user selects aggregation_level / sub_category as the secondary
  # grouping) AND show raw t CH₄ / t N₂O alongside t CO₂eq so inventory teams
  # have the gas-specific numbers they actually report.
  output$results_by_category <- DT::renderDT({
    req(rv$mc_results)
    level <- input$results_aggregation_level %||% "cattle_type"
    agg <- .agg_results_by_level(level)

    # Always also compute a cattle_type lookup. If the level IS cattle_type,
    # group names ARE the cattle_types. Otherwise build a mapping by
    # re-parsing sys_names — a sub_category / aggregation_level group could
    # technically span multiple cattle_types, but in practice one group key
    # maps cleanly to one cattle_type. Fall back to "—" if ambiguous.
    cattle_type_of <- if (level == "cattle_type") {
      setNames(names(agg), names(agg))
    } else {
      by_sys_names <- names(rv$mc_results$by_system)
      parts <- strsplit(by_sys_names, "\\|\\|", fixed = FALSE)
      idx <- switch(level, "aggregation_level" = 2, "sub_category" = 3, 1)
      kk <- sapply(parts, function(p)
        if (length(p) >= max(idx, 1) && nzchar(p[idx])) p[idx] else
          paste(p, collapse = " / "))
      ct <- sapply(parts, function(p) if (length(p) >= 1) p[1] else "—")
      uniq_ct_per_group <- tapply(ct, kk, function(x) {
        u <- unique(x); if (length(u) == 1) u else paste(u, collapse = " / ")
      })
      uniq_ct_per_group[names(agg)]
    }

    gwp_vals <- GWP_VALUES[[input$gwp_version]]
    g_ch4 <- gwp_vals$CH4
    g_n2o <- gwp_vals$N2O

    sources <- list(
      list(label = t("src_enteric_ch4"),   gas = "CH4", col = "enteric_ch4_total"),
      list(label = t("src_manure_ch4"),    gas = "CH4", col = "manure_ch4_total"),
      list(label = t("src_manure_n2o_d"),  gas = "N2O", col = "direct_n2o_mm_total"),
      list(label = t("src_manure_n2o_i"),  gas = "N2O", col = "indirect_n2o_mm_total"),
      list(label = t("src_pasture_n2o_d"), gas = "N2O", col = "direct_n2o_prp_total"),
      list(label = t("src_pasture_n2o_i"), gas = "N2O", col = "indirect_n2o_prp_total")
    )

    rows <- list()
    for (gn in names(agg)) {
      res <- agg[[gn]]
      ct <- cattle_type_of[gn]
      if (is.na(ct) || !nzchar(ct)) ct <- "—"
      for (s in sources) {
        raw <- res[[s$col]]
        if (is.null(raw) || all(raw == 0)) next
        co2e <- raw * (if (s$gas == "CH4") g_ch4 else g_n2o)
        m_raw  <- mean(raw)
        m_co2e <- mean(co2e)
        lo <- quantile(co2e, 0.025, names = FALSE)
        hi <- quantile(co2e, 0.975, names = FALSE)
        rows[[length(rows) + 1]] <- data.frame(
          cattle  = ct,
          group   = gn,
          source  = s$label,
          m_ch4   = if (s$gas == "CH4") round(m_raw, 3)  else NA_real_,
          m_n2o   = if (s$gas == "N2O") round(m_raw, 4)  else NA_real_,
          m_co2e  = round(m_co2e, 2),
          moe     = if (m_co2e > 0) round(((hi - lo) / 2) / m_co2e * 100, 1) else NA_real_,
          ci_lo   = round(lo, 2),
          ci_hi   = round(hi, 2),
          check.names = FALSE
        )
      }
    }
    if (length(rows) == 0) return(DT::datatable(data.frame()))
    df <- do.call(rbind, rows)
    if (level == "cattle_type") df$group <- NULL
    new_names <- c(t("res_col_cattle_type"))
    if (level != "cattle_type") new_names <- c(new_names, t("res_col_group"))
    new_names <- c(new_names, t("res_col_source"),
                    t("res_col_mean_t_ch4"), t("res_col_mean_t_n2o"),
                    t("res_col_mean_t_co2e"),
                    t("res_col_moe_pct"),
                    t("res_col_ci_lower_t"), t("res_col_ci_upper_t"))
    names(df) <- new_names
    DT::datatable(df, rownames = FALSE,
                  options = list(pageLength = 30, scrollX = TRUE))
  })

  # Comparison card in Results tab — only rendered when comparison data exists
  output$comparison_card <- renderUI({
    if (is.null(rv$comparison_result)) return(NULL)
    bslib::card(
      bslib::card_header(t("res_comparison_h")),
      bslib::card_body(plotly::plotlyOutput("comparison_plot", height = "320px"))
    )
  })

  output$comparison_plot <- plotly::renderPlotly({
    req(rv$mc_results, rv$comparison_result)

    vars   <- c("total_co2e", "total_ch4", "total_n2o")
    labels <- c(t("res_cmp_total_co2e"), t("res_cmp_total_ch4"), t("res_cmp_total_n2o"))

    unc_with    <- calc_all_uncertainty(rv$mc_results$inventory)
    unc_without <- calc_all_uncertainty(rv$comparison_result$inventory)

    get_moe <- function(unc, v) {
      row <- unc[unc$variable == v, ]
      if (nrow(row) > 0) round(row$moe_pct, 1) else NA_real_
    }

    moe_with    <- sapply(vars, get_moe, unc = unc_with)
    moe_without <- sapply(vars, get_moe, unc = unc_without)

    plotly::plot_ly() %>%
      plotly::add_bars(x = labels, y = moe_with,
                       name = t("res_comparison_with_label"),
                       marker = list(color = "#2D6A4F")) %>%
      plotly::add_bars(x = labels, y = moe_without,
                       name = t("res_comparison_without_label"),
                       marker = list(color = "#90A4AE")) %>%
      plotly::layout(
        barmode = "group",
        title   = t("res_cmp_chart_title"),
        yaxis   = list(title = t("res_decomp_yaxis")),
        xaxis   = list(title = ""),
        legend  = list(orientation = "h", y = -0.25)
      )
  })

  # --- SENSITIVITY ---

  # Toggle appears only when comparison data exists
  output$sens_view_toggle <- renderUI({
    if (is.null(rv$comparison_result)) return(NULL)
    div(
      style = "margin: 0 16px 12px 16px;",
      radioButtons("sens_view", t("sens_view_label"),
                   choices = setNames(c("with", "without"),
                                        c(t("res_comparison_with_label"),
                                          t("res_comparison_without_label"))),
                   selected = "with", inline = TRUE)
    )
  })

  # Helper: pick the right sensitivity dataset.
  # Andreas 28/5/26 #8: sensitivity parameter names now end with the sub-
  # category in parentheses (e.g. "Ym (DINT_cow)"). Delegate to the shared
  # `sens_group_of()` helper defined in R/mc_sensitivity.R so the audit can
  # exercise it directly.
  .sens_group <- sens_group_of

  # Render a group-filter dropdown once a simulation result is available.
  output$sens_group_filter_ui <- renderUI({
    sens <- rv$sensitivity
    if (is.null(sens)) return(NULL)
    df <- if (!is.null(sens$src) && is.data.frame(sens$src) && nrow(sens$src) > 0)
      sens$src else sens$prcc
    if (is.null(df) || !"variable" %in% names(df)) return(NULL)

    groups <- unique(sapply(df$variable, .sens_group))
    if (length(groups) <= 1) return(NULL)   # single group — no filter needed

    div(style = "min-width: 280px;",
      tags$label("Animal groups shown", class = "control-label"),
      div(style = "display: flex; gap: 6px; align-items: center;",
        selectizeInput("sens_groups",
          label   = NULL,
          choices = groups,
          selected = groups,
          multiple = TRUE,
          options  = list(placeholder = "Select groups…",
                          plugins     = list("remove_button"))
        ),
        div(style = "white-space: nowrap;",
          actionLink("sens_groups_all",  "All",  style = "font-size:0.8rem;"),
          tags$span(" | ", style = "font-size:0.8rem; color:#888;"),
          actionLink("sens_groups_none", "None", style = "font-size:0.8rem;")
        )
      )
    )
  })

  observeEvent(input$sens_groups_all, {
    sens <- rv$sensitivity
    if (is.null(sens)) return()
    df <- if (!is.null(sens$src) && is.data.frame(sens$src)) sens$src else sens$prcc
    if (is.null(df)) return()
    groups <- unique(sapply(df$variable, .sens_group))
    updateSelectizeInput(session, "sens_groups", selected = groups)
  })
  observeEvent(input$sens_groups_none, {
    updateSelectizeInput(session, "sens_groups", selected = character(0))
  })

  # T7.2: now also recomputes per-source sensitivity on demand (against the
  # selected output column) using the cached samples.
  active_sensitivity <- reactive({
    view <- if (!is.null(input$sens_view)) input$sens_view else "with"
    src  <- if (!is.null(input$sens_source)) input$sens_source else "total_co2e"

    base <- if (view == "without" && !is.null(rv$comparison_result)) {
      rv$comparison_result
    } else {
      rv$mc_results
    }
    if (is.null(base) || length(base$by_system) == 0) return(NULL)
    first_sys <- base$by_system[[1]]

    if (src == "total_co2e") {
      raw <- if (view == "without" && !is.null(rv$comparison_sensitivity))
        rv$comparison_sensitivity else rv$sensitivity
    } else if (!src %in% names(first_sys$results)) {
      raw <- rv$sensitivity
    } else {
      # Andreas 28/5/26 #8: per-source sensitivity now aggregates across ALL
      # systems and emits sub-category-suffixed labels via
      # aggregate_sensitivity(), instead of regressing only the first system's
      # samples against its own per-source result (which produced unlabelled
      # bare parameter names and missed every other sub-category's contribution).
      per_source_total <- if (length(base$by_system) == 1) {
        first_sys$results[[src]]
      } else {
        rowSums(sapply(base$by_system, function(s) s$results[[src]]))
      }
      raw <- aggregate_sensitivity(base$by_system, per_source_total,
                                    method = "both")
    }

    # Group filter — only apply when the dropdown is rendered (multi-group runs).
    sel_groups <- input$sens_groups
    if (is.null(raw) || is.null(sel_groups)) return(raw)

    filter_sens_df <- function(df) {
      if (is.null(df) || !is.data.frame(df) || !"variable" %in% names(df)) return(df)
      keep <- sapply(df$variable, .sens_group) %in% sel_groups
      df[keep, , drop = FALSE]
    }
    structure(
      list(src  = filter_sens_df(raw$src),
           prcc = filter_sens_df(raw$prcc)),
      message = attr(raw, "message")
    )
  })

  output$tornado_chart <- plotly::renderPlotly({
    sens_data <- active_sensitivity()
    req(sens_data)
    # Surface the zero-variance message from sensitivity_analysis() when the
    # selected output is structurally constant (e.g. PRP N2O with no pasture).
    msg <- attr(sens_data, "message")
    if (length(sens_data) == 0 && !is.null(msg)) {
      return(plotly::plot_ly() |> plotly::layout(
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
        annotations = list(list(
          text = msg, showarrow = FALSE,
          x = 0.5, y = 0.5, xref = "paper", yref = "paper",
          font = list(size = 13, color = "#555")))))
    }
    # When PRCC was skipped (too many parameters — multi-group inventory),
    # fall back to SRC and surface the reason as a chart annotation.
    prcc_note <- attr(sens_data, "prcc_note")
    sens <- if (input$sens_method == "prcc" && is.null(sens_data$prcc) &&
                !is.null(sens_data$src)) {
      sens_data$src   # fallback: show SRC with note below
    } else if (input$sens_method == "src" && !is.null(sens_data$src)) {
      sens_data$src
    } else if (!is.null(sens_data$prcc)) {
      sens_data$prcc
    } else return(plotly::plot_ly())

    top10 <- head(sens, 10)
    val_col <- if ("src" %in% names(top10)) "src" else "prcc"
    top10 <- top10[order(top10[[val_col]]), ]

    # Colour by user_reducible: green = user can improve with better data; grey = IPCC coefficient
    # Andreas 28/5/26 follow-up: tornado labels now include the
    # sub-category in parentheses (e.g. "Ym (DINT_cow)"). Strip that
    # suffix before the catalogue lookup, otherwise every row falls back
    # to NA → TRUE and every bar shows as user-reducible.
    reducible_lut <- setNames(PARAM_CATALOGUE$user_reducible, PARAM_CATALOGUE$parameter)
    bare_name <- sub(" \\([^()]+\\)\\s*$", "", top10$parameter)
    top10$reducible <- reducible_lut[bare_name]
    top10$reducible[is.na(top10$reducible)] <- TRUE
    bar_colours <- ifelse(top10[[val_col]] > 0,
      ifelse(top10$reducible, "#2D6A4F", "#78909C"),
      ifelse(top10$reducible, "#C1121F", "#90A4AE")
    )

    view_label <- if (!is.null(input$sens_view) && input$sens_view == "without")
      " (without correlations)" else ""

    plotly::plot_ly(y = factor(top10$parameter, levels = top10$parameter),
                    x = top10[[val_col]], type = "bar", orientation = "h",
                    marker = list(color = bar_colours),
                    text = ifelse(top10$reducible, "User-reducible", "IPCC coefficient"),
                    hoverinfo = "x+y+text") %>%
      plotly::layout(
        title = paste0("Top Parameters — ", toupper(val_col), view_label),
        xaxis = list(title = val_col), yaxis = list(title = ""),
        annotations = c(
          list(list(
            x = 0.99, y = 0.01, xref = "paper", yref = "paper", showarrow = FALSE, align = "right",
            text = "<span style='color:#2D6A4F'>■</span> User-reducible &nbsp; <span style='color:#78909C'>■</span> IPCC coefficient",
            font = list(size = 10)
          )),
          if (!is.null(prcc_note)) list(list(
            x = 0.5, y = 1.08, xref = "paper", yref = "paper", showarrow = FALSE, align = "center",
            text = paste0("<i>", prcc_note, "</i>"),
            font = list(size = 10, color = "#92400E")
          )) else list()
        )
      )
  })

  output$sensitivity_table <- DT::renderDT({
    sens_data <- active_sensitivity()
    req(sens_data)
    sens <- if (input$sens_method == "prcc" && !is.null(sens_data$prcc)) {
      sens_data$prcc
    } else if (!is.null(sens_data$src)) {
      sens_data$src
    } else req(FALSE)
    DT::datatable(sens, rownames = FALSE, options = list(pageLength = 20))
  })

  # --- IPCC REPORT ---

  output$ipcc_table_notice <- renderUI({
    if (!is.null(rv$mc_results) && is.null(rv$ipcc_table)) {
      div(class = "alert alert-warning", role = "alert",
          style = "margin-bottom:12px;",
          icon("triangle-exclamation"), " ",
          tags$strong("IPCC Table 3.3 not available for this run. "),
          "Enable 'Run uncertainty decomposition (AD/EF/Combined)' on Tab 5 and re-run the simulation. ",
          "Check the Simulation Log on Tab 5 for details.")
    }
  })

  output$ipcc_table <- DT::renderDT({
    req(rv$ipcc_table)
    DT::datatable(rv$ipcc_table, rownames = FALSE,
                  options = list(pageLength = 10, dom = 't'))
  })

  # T1.4 + R1.7: parameter glossary — variable names are now IPCC-aligned, so the
  # separate ipcc_software_name column is dropped (redundant). "Our column"
  # renamed to "Variable name".
  output$definitions_table <- DT::renderDT({
    cat <- PARAM_CATALOGUE
    is_fr <- identical(get0(".LANG_CURRENT", envir = .GlobalEnv,
                             ifnotfound = "en"), "fr")
    # Swap French definitions / units when the user picked French. IPCC codes
    # (Ym, Bo, EF3_PRP, …) and table refs stay verbatim — see R/i18n.R.
    if (is_fr) {
      fr_def <- .PARAM_DEFINITIONS_FR[cat$parameter]
      fr_unit <- .PARAM_UNITS_FR[cat$parameter]
      cat$definition <- ifelse(is.na(fr_def), cat$definition, fr_def)
      cat$unit       <- ifelse(is.na(fr_unit), cat$unit, fr_unit)
      cat$param_tier <- ifelse(cat$param_tier == "core",
                                t("def_tier_core"),
                                t("def_tier_advanced"))
    }
    cat$ipcc_framing <- ifelse(cat$parameter %in% c("cattle_pop", "N"),
                               t("def_framing_ad"),
                               t("def_framing_coef"))
    DT::datatable(
      cat[, c("parameter", "definition", "unit",
              "ipcc_default", "suggested_distribution",
              "param_tier", "ipcc_framing", "ipcc_ref")],
      rownames = FALSE,
      colnames = setNames(
        c("parameter", "definition", "unit", "ipcc_default",
          "suggested_distribution", "param_tier",
          "ipcc_framing", "ipcc_ref"),
        c(t("def_col_variable"), t("def_col_definition"), t("def_col_unit"),
          t("def_col_ipcc_default"), t("def_col_dist"), t("def_col_level"),
          t("def_col_ipcc_framing"), t("def_col_ipcc_ref"))),
      options = list(pageLength = -1, dom = "t", scrollX = TRUE),
      class = "compact stripe"
    )
  })
  # Render eagerly at startup so the table is cached in the browser and
  # visible even when the server is busy running a simulation.
  outputOptions(output, "definitions_table", suspendWhenHidden = FALSE)

  # Perf (2026-06): pre-bin histograms server-side and send only the bar
  # heights, instead of shipping every Monte Carlo draw to the browser as a
  # plotly `type="histogram"` (which bins client-side). On the IPCC Report tab
  # this turned ~150k-200k raw points per render into a few hundred bars, so the
  # tab opens near-instantly even on a 32-sub-category x 30k run. Bars are drawn
  # contiguous (width = bin width, bargap = 0) so they look like a histogram.
  .hist_bar <- function(x, nbins, color, density = FALSE, title = "") {
    x <- x[is.finite(x)]
    if (length(x) == 0) return(plotly::plot_ly())
    rng <- range(x)
    if (diff(rng) <= .Machine$double.eps) {
      # Degenerate (constant) input — a single spike, as a raw histogram drew it.
      p <- plotly::plot_ly(x = rng[1], y = if (density) 1 else length(x),
                           type = "bar", marker = list(color = color),
                           showlegend = FALSE)
    } else {
      h  <- hist(x, breaks = nbins, plot = FALSE)
      yv <- if (density) h$density else h$counts
      p  <- plotly::plot_ly(x = h$mids, y = yv, type = "bar",
                            width = h$breaks[2] - h$breaks[1],
                            marker = list(color = color, line = list(width = 0)),
                            showlegend = FALSE,
                            hovertemplate = "%{x:.3g}: %{y:.3g}<extra></extra>")
    }
    p |> plotly::layout(xaxis = list(title = title), yaxis = list(title = ""),
                        bargap = 0)
  }

  # T8.4 / Round 6a #8: per-source histograms embedded in IPCC Report.
  # Bug fix: previous version referenced `inv$enteric_ch4_total` etc., but the
  # top-level inventory data.frame only carries cross-system aggregates
  # (`total_enteric_ch4`, `total_manure_ch4`, `total_direct_n2o`,
  # `total_indirect_n2o`). Indirect N2O is the sum of MM-indirect and PRP-
  # indirect across systems, so we now rebuild per-source vectors by summing
  # the per-system samples directly. Sources with zero variance (because the
  # source was not ticked, or because all systems sum to zero for that source)
  # are skipped with a placeholder annotation rather than rendered as a flat
  # bar at zero.
  output$report_source_histograms <- plotly::renderPlotly({
    req(rv$mc_results)
    by_sys <- rv$mc_results$by_system
    if (length(by_sys) == 0)
      return(plotly::plot_ly() |>
               plotly::layout(title = "No simulation data available."))

    .sum_across <- function(field) {
      vals <- lapply(by_sys, function(s) s$results[[field]])
      vals <- Filter(function(v) !is.null(v) && length(v) > 0, vals)
      if (length(vals) == 0) return(NULL)
      Reduce(`+`, vals)
    }
    enteric_ch4 <- .sum_across("enteric_ch4_total")
    manure_ch4  <- .sum_across("manure_ch4_total")
    mm_n2o_dir  <- .sum_across("direct_n2o_mm_total")
    mm_n2o_ind  <- .sum_across("indirect_n2o_mm_total")
    prp_dir     <- .sum_across("direct_n2o_prp_total")
    prp_ind     <- .sum_across("indirect_n2o_prp_total")
    pasture_n2o <- if (!is.null(prp_dir) && !is.null(prp_ind)) prp_dir + prp_ind
                   else if (!is.null(prp_dir)) prp_dir
                   else prp_ind

    sources <- list(
      "Enteric CH4 (t)"         = enteric_ch4,
      "Manure CH4 (t)"          = manure_ch4,
      "Manure N2O direct (t)"   = mm_n2o_dir,
      "Manure N2O indirect (t)" = mm_n2o_ind,
      "Pasture N2O (t)"         = pasture_n2o
    )

    has_variance <- function(v) !is.null(v) && length(v) > 1 &&
      sd(v, na.rm = TRUE) > .Machine$double.eps
    keep <- vapply(sources, has_variance, logical(1))
    if (!any(keep)) {
      return(plotly::plot_ly() |>
               plotly::layout(
                 title = "No source has variance to display.",
                 annotations = list(list(
                   text = paste("None of the ticked emission sources produced",
                                "variable output. Ensure at least one source",
                                "is selected on Tab 5 and that the relevant",
                                "parameters have non-zero uncertainty."),
                   showarrow = FALSE, x = 0.5, y = 0.5,
                   xref = "paper", yref = "paper"))))
    }
    sources <- sources[keep]

    plots <- lapply(seq_along(sources), function(i) {
      .hist_bar(sources[[i]], nbins = 40, color = "#2D6A4F",
                title = names(sources)[i])
    })
    plotly::subplot(plots,
                    nrows  = max(1, ceiling(length(plots) / 3)),
                    margin = 0.06,
                    titleX = TRUE, titleY = FALSE)
  })

  # T8.4 / Round 6a #8: tornado chart embedded in IPCC Report (vs total_co2e).
  # Bug fix: when sensitivity_analysis() returns an empty list (no input
  # parameters had variance), or when SRC's lm() coefficients column is named
  # `Estimate` rather than `src`, the previous code crashed on
  # `top10[[val_col]]`. We now defend against an empty sensitivity object,
  # missing column, or zero rows with friendly placeholder annotations.
  output$report_tornado <- plotly::renderPlotly({
    placeholder <- function(msg) {
      plotly::plot_ly() |>
        plotly::layout(
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(list(
            text = msg, showarrow = FALSE,
            x = 0.5, y = 0.5, xref = "paper", yref = "paper",
            font = list(size = 14, color = "#555"))))
    }
    if (is.null(rv$sensitivity) || length(rv$sensitivity) == 0)
      return(placeholder("Sensitivity analysis not yet run. Run a simulation on Tab 5 first."))

    # Hotfix: custom %||% is unsafe on data.frames (it does is.na(a[1])
    # which on a frame returns a vector, breaking the `||` chain). Use
    # explicit checks instead so the tornado renderer doesn't throw.
    sens <- if (!is.null(rv$sensitivity$src) &&
                is.data.frame(rv$sensitivity$src) && nrow(rv$sensitivity$src) > 0) {
      rv$sensitivity$src
    } else if (!is.null(rv$sensitivity$prcc) &&
               is.data.frame(rv$sensitivity$prcc) && nrow(rv$sensitivity$prcc) > 0) {
      rv$sensitivity$prcc
    } else NULL
    if (is.null(sens) || nrow(sens) == 0)
      return(placeholder("No input parameters had variance — tornado chart cannot be built."))

    val_col <- if ("src" %in% names(sens)) "src"
               else if ("prcc" %in% names(sens)) "prcc"
               else NULL
    if (is.null(val_col) || !"parameter" %in% names(sens))
      return(placeholder("Sensitivity result is missing the expected columns."))

    top10 <- utils::head(sens, 10)
    top10 <- top10[order(top10[[val_col]]), , drop = FALSE]
    plotly::plot_ly(y = factor(top10$parameter, levels = top10$parameter),
                    x = top10[[val_col]], type = "bar", orientation = "h",
                    marker = list(color = ifelse(top10[[val_col]] > 0,
                                                 "#2D6A4F", "#C1121F"))) |>
      plotly::layout(title = paste0("Top 10 — ", toupper(val_col)),
                     xaxis = list(title = val_col),
                     yaxis = list(title = ""))
  })

  # Tx.1: input distribution density plots for QA review
  output$report_input_densities <- plotly::renderPlotly({
    req(rv$mc_results)
    if (length(rv$mc_results$by_system) == 0) return(plotly::plot_ly())
    samples <- rv$mc_results$by_system[[1]]$samples
    if (is.null(samples) || ncol(samples) == 0) return(plotly::plot_ly())

    # Take up to 12 parameters to keep the panel readable
    keep <- head(colnames(samples), 12)
    plots <- lapply(keep, function(p) {
      .hist_bar(samples[[p]], nbins = 30, color = "#40916C",
                density = TRUE, title = p)
    })
    plotly::subplot(plots, nrows = 4, margin = 0.04,
                    titleX = TRUE, titleY = FALSE)
  })

  # T8.3: input documentation table for IPCC inventory submission / QA
  output$inputs_doc_table <- DT::renderDT({
    req(rv$param_specs)
    ps <- rv$param_specs
    keep <- intersect(c("cattle_type", "aggregation_level", "sub_category",
                        "parameter", "param_type", "mean", "uncertainty_pct",
                        "lower", "upper", "distribution", "data_source",
                        "ipcc_ref"),
                      names(ps))
    DT::datatable(ps[, keep, drop = FALSE], rownames = FALSE,
                  options = list(pageLength = 25, scrollX = TRUE),
                  class = "compact stripe")
  })

  output$download_xlsx <- downloadHandler(
    filename = function() paste0("uncertainty_report_", Sys.Date(), ".xlsx"),
    content = function(file) {
      req(rv$mc_results, rv$uncertainty)
      export_results_xlsx(
        rv$mc_results$inventory, rv$uncertainty,
        rv$sensitivity, rv$ipcc_table, file,
        settings = list(
          n_iter           = as.integer(input$n_iter),
          corr_mode        = input$corr_mode,
          ef_corr_mode     = input$ef_corr_mode,
          run_comparison   = input$run_comparison,
          gwp_version      = input$gwp_version,
          seed             = input$seed,
          analysis_mode    = input$analysis_mode,
          emission_sources = input$emission_sources
        )
      )
    }
  )

  # Andreas 2026-05 #36, C10: CSV layout — emission category in column A,
  # pasture direct + indirect kept as separate rows (not collapsed into
  # total N₂O), and the variable->category mapping made explicit.
  output$download_csv <- downloadHandler(
    filename = function() paste0("uncertainty_results_", Sys.Date(), ".csv"),
    content = function(file) {
      req(rv$uncertainty)
      cat_map <- c(
        enteric_ch4_total       = "3.A.1 Enteric fermentation - CH4",
        manure_ch4_total        = "3.A.2 Manure management - CH4",
        direct_n2o_mm_total     = "3.A.2 Manure management - N2O direct",
        indirect_n2o_mm_total   = "3.A.2 Manure management - N2O indirect",
        direct_n2o_prp_total    = "3.C.4 Pasture deposition - N2O direct",
        indirect_n2o_prp_total  = "3.C.5 Pasture deposition - N2O indirect",
        total_enteric_ch4       = "3.A.1 Enteric fermentation - CH4 (inventory total)",
        total_manure_ch4        = "3.A.2 Manure management - CH4 (inventory total)",
        total_direct_n2o_mm     = "3.A.2 Manure management - N2O direct (inventory total)",
        total_indirect_n2o_mm   = "3.A.2 Manure management - N2O indirect (inventory total)",
        total_direct_n2o_prp    = "3.C.4 Pasture deposition - N2O direct (inventory total)",
        total_indirect_n2o_prp  = "3.C.5 Pasture deposition - N2O indirect (inventory total)",
        total_ch4               = "Aggregate - Total CH4",
        total_n2o               = "Aggregate - Total N2O",
        total_direct_n2o        = "Aggregate - Total N2O direct (MM + PRP)",
        total_indirect_n2o      = "Aggregate - Total N2O indirect (MM + PRP)",
        total_co2e              = "Aggregate - Total CO2eq"
      )
      unit_map <- c(
        enteric_ch4_total = "t CH4", manure_ch4_total = "t CH4",
        direct_n2o_mm_total = "t N2O", indirect_n2o_mm_total = "t N2O",
        direct_n2o_prp_total = "t N2O", indirect_n2o_prp_total = "t N2O",
        total_enteric_ch4 = "t CH4", total_manure_ch4 = "t CH4",
        total_direct_n2o_mm = "t N2O", total_indirect_n2o_mm = "t N2O",
        total_direct_n2o_prp = "t N2O", total_indirect_n2o_prp = "t N2O",
        total_ch4 = "t CH4", total_n2o = "t N2O",
        total_direct_n2o = "t N2O", total_indirect_n2o = "t N2O",
        total_co2e = "t CO2eq"
      )
      df <- rv$uncertainty
      out <- data.frame(
        cattle_type       = "TOTAL",
        emission_category = ifelse(df$variable %in% names(cat_map),
                                    cat_map[df$variable], df$variable),
        unit              = ifelse(df$variable %in% names(unit_map),
                                    unit_map[df$variable], ""),
        variable          = df$variable,
        mean              = df$mean,
        ci_lower          = df$ci_lower,
        ci_upper          = df$ci_upper,
        moe_pct           = df$moe_pct,
        cv_pct            = df$cv_pct,
        stringsAsFactors  = FALSE
      )

      # Andreas 28/5/26 #7.1 + #7.2: append per-cattle_type rows so inventory
      # compilers can see dairy / non-dairy / other contributions to each
      # IPCC reporting category, not only the inventory total.
      agg_ct <- .agg_results_by_level("cattle_type")
      per_source_vars <- c("enteric_ch4_total", "manure_ch4_total",
                            "direct_n2o_mm_total", "indirect_n2o_mm_total",
                            "direct_n2o_prp_total", "indirect_n2o_prp_total")
      ct_rows <- list()
      for (ct in names(agg_ct)) {
        res <- agg_ct[[ct]]
        for (v in per_source_vars) {
          if (!v %in% names(res)) next
          x <- res[[v]]
          if (all(x == 0)) next
          m  <- mean(x)
          lo <- stats::quantile(x, 0.025, names = FALSE)
          hi <- stats::quantile(x, 0.975, names = FALSE)
          ct_rows[[length(ct_rows) + 1L]] <- data.frame(
            cattle_type       = ct,
            emission_category = cat_map[[v]],
            unit              = unit_map[[v]],
            variable          = v,
            mean              = m,
            ci_lower          = lo,
            ci_upper          = hi,
            moe_pct           = if (m > 0) ((hi - lo) / 2) / m * 100 else NA_real_,
            cv_pct            = if (m > 0) stats::sd(x) / m * 100 else NA_real_,
            stringsAsFactors  = FALSE
          )
        }
      }
      if (length(ct_rows) > 0) out <- rbind(out, do.call(rbind, ct_rows))

      write.csv(out, file, row.names = FALSE)
    }
  )

  # Round 6b #9: Word run-summary download
  output$download_docx <- downloadHandler(
    filename = function() paste0("uncertainty_summary_", Sys.Date(), ".docx"),
    content = function(file) {
      # IMPORTANT: must be shiny::validate, NOT the bare `validate`. jsonlite
      # is loaded after shiny in this app and masks shiny's validate() with
      # its own single-argument JSON-validator. A bare `validate(need(...),
      # need(...))` resolves to jsonlite::validate(), which rejects the
      # second need() as an "unused argument" — producing a 500 on the
      # download handler. Same applies to the three trend downloads below.
      shiny::validate(
        shiny::need(!is.null(rv$mc_results),  "Run a Monte Carlo simulation on Tab 5 before downloading the Word summary."),
        shiny::need(!is.null(rv$uncertainty), "Uncertainty metrics not yet computed.")
      )
      settings <- list(
        n_iter            = as.integer(input$n_iter),
        corr_mode         = input$corr_mode,
        ef_corr_mode      = input$ef_corr_mode,
        run_comparison    = isTRUE(input$run_comparison),
        gwp_version       = input$gwp_version,
        seed              = input$seed,
        analysis_mode     = input$analysis_mode,
        emission_sources  = input$emission_sources
      )
      # Round 9b: pass through the decomposition, comparison run (uncertainty
      # frame), diagnostics, and a samples frame for the density plot so the
      # Word report can mirror everything the IPCC Report / Sensitivity /
      # Results tabs show.
      comp_unc <- if (!is.null(rv$comparison_result))
        calc_all_uncertainty(rv$comparison_result$inventory) else NULL
      density_samples <- if (!is.null(rv$mc_results$by_system) &&
                              length(rv$mc_results$by_system) > 0)
        rv$mc_results$by_system[[1]]$samples else NULL
      build_run_summary_docx(
        path                  = file,
        settings              = settings,
        param_specs           = rv$param_specs,
        mc_results            = rv$mc_results,
        uncertainty           = rv$uncertainty,
        sensitivity           = rv$sensitivity,
        ipcc_table            = rv$ipcc_table,
        ipcc_meta             = rv$inv_metadata,
        decomposition         = rv$decomposition,
        comparison_uncertainty = comp_unc,
        diagnostics           = rv$diagnostics,
        samples_for_density   = density_samples
      )
    }
  )

  # ====================================================================
  # F / T4.22 / TT.6: Trend tab — multi-year inventory uncertainty
  # ====================================================================
  # Round 8: rv_trend now caches per-year MC samples + delta + slope so the
  # trend tab can compute sensitivity and produce Excel/CSV/Word reports.
  rv_trend <- reactiveValues(results = NULL, samples_by_year = NULL,
                              co2e_by_year = NULL, slope = NULL,
                              delta_total = NULL, year_corr = NULL,
                              years = NULL, message = NULL)

  observeEvent(input$run_trend, {
    req(rv$param_specs)
    n_iter <- as.integer(input$n_iter %||% 10000)
    n_iter_fmt <- format(n_iter, big.mark = ",")
    # Round 9 follow-up: withProgress bar mirrors the single-year handler so
    # the user gets feedback during the per-year MC loop (which can take ~1
    # minute at 10k iter × 5 years on shinyapps.io).
    withProgress(
      message = sprintf("Trend Monte Carlo (%s iter / year)", n_iter_fmt),
      value = 0,
      {
        tryCatch({
          setProgress(0.03, detail = "Preparing trend data...")
          # Trend data is read exclusively from the Parameter_TimeSeries sheet
          # of the main upload (rv$population). The previous "optional separate
          # CSV override" file input was removed in the May 2026 UX overhaul --
          # one source of trend data is clearer for users.
          df <- if (!is.null(rv$population) && ncol(rv$population) >= 2) {
            trend_df_from_population(rv$population, rv$param_specs)
          } else {
            stop("No time-series data available. Load a template that includes ",
                 "a Parameter_TimeSeries sheet, or pick one of the built-in ",
                 "Country X / Country Y examples on Tab 1.")
          }
          # Round 9: trend uses the same n_iter slider as single-year. Source
          # selection from Tab 5 also applies — trend now honours
          # input$emission_sources just like the single-year flow.
          yc <- if (!is.null(input$year_corr) && nzchar(input$year_corr)) input$year_corr else "full"
          gv <- if (!is.null(input$gwp_version) && nzchar(input$gwp_version)) input$gwp_version else "AR5"
          sd_ <- if (!is.null(input$seed)) input$seed else 42

          # Per-year progress callback: fan out the [0.05, 0.95] band across
          # the years so the bar advances as each per-year sim completes.
          prog_fn <- function(yi, n_years, year_label) {
            frac <- 0.05 + 0.90 * (yi / max(n_years, 1L))
            setProgress(frac, detail = sprintf("Year %s (%d / %d)",
                                                year_label, yi, n_years))
          }
          setProgress(0.05, detail = "Starting per-year simulations...")

          res <- run_trend_analysis(df, base_specs = rv$param_specs, n_iter = n_iter,
                                     gwp = gv, seed = sd_, year_corr = yc,
                                     emission_sources = input$emission_sources,
                                     progress_fn = prog_fn)

          setProgress(0.97, detail = "Computing slope and Δ...")
          # Round 8: res is now a list, not a data frame
          rv_trend$results         <- res$table
          rv_trend$samples_by_year <- res$samples_by_year
          rv_trend$co2e_by_year    <- res$co2e_by_year
          rv_trend$slope           <- res$slope
          rv_trend$delta_total     <- res$delta_total
          rv_trend$year_corr       <- res$year_corr
          rv_trend$years           <- res$years
          rv_trend$message <- list(type = "success",
            text = sprintf("Trend computed for %d years (%d–%d). Δ vs base: %.1f%% [95%% CI %.1f%%, %.1f%%]; slope: %.0f t CO₂eq/yr.",
                           nrow(res$table), min(res$table$Year), max(res$table$Year),
                           res$delta_total$pct_mean,
                           res$delta_total$pct_ci[1], res$delta_total$pct_ci[2],
                           res$slope$mean))
          # Round 9: flip Tab 5 to results-view so trend chart/table/sensitivity
          # show in place (mirrors the single-year Run handler's sim_view flip).
          rv$sim_view <- "results"
          setProgress(1.00, detail = "Done.")
          showNotification(rv_trend$message$text, type = "message", duration = 7)
        }, error = function(e) {
          rv_trend$message <- list(type = "error",
            text = paste("Trend run failed:", e$message))
          showNotification(rv_trend$message$text, type = "error", duration = 10)
        })
      }
    )
  })

  output$trend_status <- renderUI({
    if (is.null(rv_trend$message)) {
      # R2.3: report whether the trend run will use template TS or a CSV override
      if (!is.null(rv$population) && ncol(rv$population) >= 2) {
        n_yrs <- length(unique(rv$population$year))
        n_par <- ncol(rv$population) - 1
        div(style = "font-size:0.85rem; color:#1B4332; background:#D8F3DC; padding:8px 10px; border-radius:6px;",
            icon("check-circle"),
            sprintf(" Using time-series from loaded template — %d years × %d parameters. ",
                    n_yrs, n_par),
            "Click Run to compute the trend, or upload a CSV above to override.")
      } else {
        div(style = "font-size:0.85rem; color:#555;",
            icon("info-circle"),
            " No time-series in the loaded template. Upload a long-format CSV and click Run, ",
            "or load Country X / Country Y from Tab 1 to use the example time-series.")
      }
    } else {
      bg <- if (rv_trend$message$type == "success") "#D8F3DC" else "#FECACA"
      fg <- if (rv_trend$message$type == "success") "#1B4332" else "#7F1D1D"
      div(style = sprintf("font-size:0.85rem; background:%s; color:%s; padding:8px 10px; border-radius:6px;",
                          bg, fg),
          rv_trend$message$text)
    }
  })

  # Round 9 follow-up: trend headline value boxes + Δ histogram + YoY bar
  # chart. These mirror the single-year value-box layout (vb_ch4 / vb_n2o /
  # vb_moe / vb_cv) but answer trend-specific questions: how much did
  # emissions change, how fast per year, what's the latest level, how
  # bumpy is the trajectory.

  # Helper: format a signed percent with sign (+1.2% / -1.2%)
  .fmt_signed_pct <- function(x, digits = 1) {
    if (is.null(x) || length(x) == 0 || is.na(x)) return("—")
    s <- formatC(x, digits = digits, format = "f")
    if (x > 0) paste0("+", s, "%") else paste0(s, "%")
  }

  output$vb_trend_delta <- renderText({
    req(rv_trend$delta_total)
    .fmt_signed_pct(rv_trend$delta_total$pct_mean, 1)
  })
  output$vb_trend_delta_sub <- renderText({
    req(rv_trend$delta_total)
    sprintf("95%% CI %s to %s",
            .fmt_signed_pct(rv_trend$delta_total$pct_ci[1], 1),
            .fmt_signed_pct(rv_trend$delta_total$pct_ci[2], 1))
  })

  output$vb_trend_slope <- renderText({
    req(rv_trend$slope)
    s <- rv_trend$slope$mean
    if (is.null(s) || is.na(s)) return("—")
    sign_str <- if (s > 0) "+" else ""
    paste0(sign_str, format(round(s, 0), big.mark = ","), " t/yr")
  })
  output$vb_trend_slope_sub <- renderText({
    req(rv_trend$slope)
    sprintf("95%% CI %s to %s t CO₂eq/yr",
            format(round(rv_trend$slope$ci[1], 0), big.mark = ","),
            format(round(rv_trend$slope$ci[2], 0), big.mark = ","))
  })

  output$vb_trend_latest <- renderText({
    req(rv_trend$results)
    df <- rv_trend$results
    last <- df[nrow(df), ]
    paste0(format(round(last$Mean_t_CO2eq, 0), big.mark = ","), " t")
  })
  output$vb_trend_latest_sub <- renderText({
    req(rv_trend$results)
    df <- rv_trend$results
    last <- df[nrow(df), ]
    # 2026-06: switched from CV% to 95% MoE to match the IPCC Vol.1 Ch.3
    # Table 3.3 reporting convention used by every other uncertainty display
    # in the app. CV_pct still in the trend results frame for re-derivation.
    sprintf("Year %d  ·  ±%.1f%% (95%% MoE)", last$Year, last$MoE_95_pct)
  })

  output$vb_trend_yoy <- renderText({
    req(rv_trend$results)
    yoy <- rv_trend$results$YoY_pct[!is.na(rv_trend$results$YoY_pct)]
    if (length(yoy) == 0) return("—")
    biggest <- yoy[which.max(abs(yoy))]
    .fmt_signed_pct(biggest, 1)
  })
  output$vb_trend_yoy_sub <- renderText({
    req(rv_trend$results)
    df <- rv_trend$results
    yoy <- df$YoY_pct[!is.na(df$YoY_pct)]
    if (length(yoy) == 0) return("—")
    idx <- which.max(abs(yoy))
    yr  <- df$Year[!is.na(df$YoY_pct)][idx]
    sprintf("Largest year-over-year change (%d)", yr)
  })

  # Inline summary line below the value boxes — mirrors the single-year
  # output$vb_co2e_inline pattern.
  output$vb_trend_inline <- renderText({
    req(rv_trend$results, rv_trend$year_corr)
    df <- rv_trend$results
    yc_label <- switch(rv_trend$year_corr,
                        full    = "fully correlated coefficients (IPCC 2019 default)",
                        partial = "partial year-correlation (AR(1), ρ=0.7)",
                        none    = "independent years")
    sprintf("Year range: %d – %d  ·  %d years analysed  ·  %s",
            min(df$Year), max(df$Year), nrow(df), yc_label)
  })

  # Δ Y_N − Y_1 distribution histogram — visualises the uncertainty on the
  # trend itself (the per-iteration distribution of the absolute change).
  # Mirrors the single-year output$results_histogram.
  output$trend_delta_histogram <- plotly::renderPlotly({
    req(rv_trend$delta_total)
    x <- rv_trend$delta_total$per_iter
    if (is.null(x) || length(x) == 0) return(plotly::plot_ly())
    ci <- stats::quantile(x, c(0.025, 0.975), names = FALSE, na.rm = TRUE)
    fill_above <- if (mean(x, na.rm = TRUE) > 0) "#2D6A4F" else "#C1121F"
    plotly::plot_ly(x = x, type = "histogram", nbinsx = 50,
                    marker = list(color = fill_above,
                                   line = list(color = "#1B4332", width = 1))) %>%
      plotly::layout(
        title = list(text = "Distribution of Δ Y_N − Y_1 (t CO₂eq) — uncertainty on the trend itself",
                     font = list(size = 12)),
        xaxis = list(title = "ΔCO₂eq (t)"),
        yaxis = list(title = "Frequency"),
        shapes = list(
          list(type = "line", x0 = ci[1], x1 = ci[1], y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#C1121F", dash = "dash", width = 1.5)),
          list(type = "line", x0 = ci[2], x1 = ci[2], y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#C1121F", dash = "dash", width = 1.5)),
          list(type = "line", x0 = 0, x1 = 0, y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#555", dash = "dot", width = 1))
        )
      )
  })

  # Year-over-year % change bar chart — quick visual of the per-year
  # bumpiness; complements the trend chart which shows levels.
  output$trend_yoy_chart <- plotly::renderPlotly({
    req(rv_trend$results)
    df <- rv_trend$results
    yrs <- df$Year[-1]
    yoy <- df$YoY_pct[-1]
    bar_col <- ifelse(yoy >= 0, "#2D6A4F", "#C1121F")
    plotly::plot_ly(x = yrs, y = yoy, type = "bar",
                    marker = list(color = bar_col)) %>%
      plotly::layout(
        title = list(text = "Year-over-year % change",
                     font = list(size = 12)),
        xaxis = list(title = "Year", dtick = 1),
        yaxis = list(title = "Δ vs prior year (%)", zeroline = TRUE,
                     zerolinecolor = "#555", zerolinewidth = 1.5)
      )
  })

  output$trend_table <- DT::renderDT({
    req(rv_trend$results)
    # 2026-06: drop the CV_pct column so the trend table aligns with the
    # single-year results tables (every user-facing uncertainty display in
    # the app reports as 95% MoE only). CV_pct is still in rv_trend$results
    # for internal/audit access.
    df <- rv_trend$results[, setdiff(names(rv_trend$results), "CV_pct"),
                            drop = FALSE]
    DT::datatable(df, rownames = FALSE,
                  options = list(pageLength = 25, dom = "t"))
  })

  output$trend_plot <- plotly::renderPlotly({
    req(rv_trend$results)
    df <- rv_trend$results
    sub <- if (!is.null(rv_trend$slope) && !is.null(rv_trend$delta_total)) {
      sprintf("Δ vs base: %.1f%% (95%% CI %.1f%%, %.1f%%)  •  Slope: %.0f t CO₂eq/yr (95%% CI %.0f, %.0f)",
              rv_trend$delta_total$pct_mean,
              rv_trend$delta_total$pct_ci[1], rv_trend$delta_total$pct_ci[2],
              rv_trend$slope$mean,
              rv_trend$slope$ci[1], rv_trend$slope$ci[2])
    } else NULL
    plotly::plot_ly() |>
      plotly::add_ribbons(x = df$Year, ymin = df$CI_Lower_t, ymax = df$CI_Upper_t,
                          name = t("res_vb_ci_label"),
                          line = list(color = "transparent"),
                          fillcolor = "rgba(45,106,79,0.25)") |>
      plotly::add_trace(x = df$Year, y = df$Mean_t_CO2eq,
                        type = "scatter", mode = "lines+markers",
                        name = t("res_vb_mean_label"),
                        line = list(color = "#1B4332", width = 3),
                        marker = list(size = 8, color = "#1B4332")) |>
      plotly::layout(
        title = list(text = paste0(t("res_trend_plot_title"),
                                    if (!is.null(sub)) paste0("<br><sub>", sub, "</sub>") else "")),
        xaxis = list(title = t("res_trend_xaxis_year")),
        yaxis = list(title = t("res_hist_xaxis")),
        hovermode = "x unified"
      )
  })

  # Round 8 — Trend sensitivity (per-year + delta)

  trend_sens_per_year <- reactive({
    req(rv_trend$samples_by_year, rv_trend$co2e_by_year)
    yrs <- names(rv_trend$samples_by_year)
    last <- yrs[length(yrs)]
    sensitivity_analysis(
      rv_trend$samples_by_year[[last]],
      rv_trend$co2e_by_year[[last]],
      method = "both"
    )
  })

  trend_sens_delta <- reactive({
    req(rv_trend$samples_by_year, rv_trend$delta_total)
    yrs <- names(rv_trend$samples_by_year)
    if (length(yrs) < 2) return(NULL)
    s_y1 <- as.data.frame(rv_trend$samples_by_year[[1]])
    s_yN <- as.data.frame(rv_trend$samples_by_year[[length(yrs)]])
    names(s_y1) <- paste0(names(s_y1), "_y1")
    names(s_yN) <- paste0(names(s_yN), "_yN")
    combined <- cbind(s_y1, s_yN)
    sensitivity_analysis(
      combined, rv_trend$delta_total$per_iter, method = "both"
    )
  })

  # Round 9 follow-up: trend tornado now matches the single-year tornado
  # (output$tornado_chart) — coloured by user_reducible × sign, with a hover
  # text and a bottom-right legend annotation explaining the colour scheme.
  # The bare-parameter strip in the trend-driver case (e.g. "W_y1" / "W_yN")
  # is split on the suffix so reducibility lookup hits PARAM_CATALOGUE.
  .trend_tornado_plot <- function(sens, title_text) {
    placeholder <- function(msg) {
      plotly::plot_ly() |>
        plotly::layout(
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(list(
            text = msg, showarrow = FALSE, x = 0.5, y = 0.5,
            xref = "paper", yref = "paper",
            font = list(size = 13, color = "#555"))))
    }
    if (is.null(sens) || length(sens) == 0)
      return(placeholder("Run a trend simulation first."))
    base <- if (!is.null(sens$src) && is.data.frame(sens$src) && nrow(sens$src) > 0) {
      sens$src
    } else if (!is.null(sens$prcc) && is.data.frame(sens$prcc) && nrow(sens$prcc) > 0) {
      sens$prcc
    } else NULL
    if (is.null(base) || nrow(base) == 0)
      return(placeholder("No input parameters had variance."))
    val_col <- if ("src" %in% names(base)) "src"
               else if ("prcc" %in% names(base)) "prcc"
               else NULL
    if (is.null(val_col) || !"parameter" %in% names(base))
      return(placeholder("Sensitivity result missing expected columns."))
    top10 <- utils::head(base[order(-abs(base[[val_col]])), , drop = FALSE], 10)
    top10 <- top10[order(top10[[val_col]]), , drop = FALSE]

    # Map parameter -> user_reducible. For trend-driver names like "W_y1" or
    # "Cfi_yN" strip the year suffix; for multi-system labels with the
    # sub-category in parentheses (e.g. "Ym (DINT_cow)") strip the
    # parenthesised suffix too — both must be stripped before the
    # catalogue lookup.
    bare_name <- sub(" \\([^()]+\\)\\s*$", "", top10$parameter)
    bare_name <- gsub("_(y1|yN)$", "", bare_name)
    reducible_lut <- setNames(PARAM_CATALOGUE$user_reducible,
                                PARAM_CATALOGUE$parameter)
    top10$reducible <- reducible_lut[bare_name]
    top10$reducible[is.na(top10$reducible)] <- TRUE

    bar_colours <- ifelse(top10[[val_col]] > 0,
      ifelse(top10$reducible, "#2D6A4F", "#78909C"),
      ifelse(top10$reducible, "#C1121F", "#90A4AE")
    )
    hover_txt <- ifelse(top10$reducible, "User-reducible", "IPCC coefficient")

    plotly::plot_ly(y = factor(top10$parameter, levels = top10$parameter),
                    x = top10[[val_col]], type = "bar", orientation = "h",
                    marker = list(color = bar_colours),
                    text = hover_txt, hoverinfo = "x+y+text") |>
      plotly::layout(
        title = list(text = title_text, font = list(size = 12)),
        xaxis = list(title = toupper(val_col)),
        yaxis = list(title = ""),
        margin = list(l = 130, b = 40),
        annotations = list(list(
          x = 0.99, y = -0.18, xref = "paper", yref = "paper",
          showarrow = FALSE, align = "right",
          text = "<span style='color:#2D6A4F'>■</span> User-reducible &nbsp; <span style='color:#78909C'>■</span> IPCC coefficient",
          font = list(size = 10)
        ))
      )
  }

  # Round 9 follow-up: trend rankings table (per-year + Δ). Mirrors the
  # single-year output$sensitivity_table but shows both SRC and PRCC columns
  # (and the user_reducible flag as a coloured Class column) so the user
  # doesn't have to flip a method toggle. Used by Tab 6 (Sensitivity) under
  # the trend mode conditional.
  .trend_sens_table <- function(sens) {
    if (is.null(sens) || length(sens) == 0) {
      return(DT::datatable(data.frame(Note = "Run a trend simulation first."),
                            rownames = FALSE, options = list(dom = "t")))
    }
    src  <- sens$src
    prcc <- sens$prcc
    base <- if (!is.null(src) && nrow(src) > 0) src
            else if (!is.null(prcc) && nrow(prcc) > 0) prcc
            else NULL
    if (is.null(base) || nrow(base) == 0) {
      return(DT::datatable(
        data.frame(Note = "No input parameters had variance."),
        rownames = FALSE, options = list(dom = "t")))
    }
    val_col <- if ("src" %in% names(base)) "src"
               else if ("prcc" %in% names(base)) "prcc"
               else names(base)[2]
    base <- base[order(-abs(base[[val_col]])), , drop = FALSE]
    base <- utils::head(base, 15)

    bare_name <- sub(" \\([^()]+\\)\\s*$", "", base$parameter)
    bare_name <- gsub("_(y1|yN)$", "", bare_name)
    reducible_lut <- setNames(PARAM_CATALOGUE$user_reducible,
                                PARAM_CATALOGUE$parameter)
    reducible <- reducible_lut[bare_name]
    reducible[is.na(reducible)] <- TRUE

    src_disp  <- if ("src" %in% names(base))
                   formatC(base$src,  digits = 3, format = "f") else NA_character_
    prcc_disp <- if (!is.null(prcc) && "prcc" %in% names(prcc))
                   formatC(prcc$prcc[match(base$parameter, prcc$parameter)],
                           digits = 3, format = "f") else NA_character_

    df <- data.frame(
      Parameter = base$parameter,
      Class     = ifelse(reducible, "User-reducible", "IPCC coefficient"),
      SRC       = src_disp,
      PRCC      = prcc_disp,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (all(is.na(df$PRCC))) df$PRCC <- NULL
    if (all(is.na(df$SRC)))  df$SRC  <- NULL

    dt <- DT::datatable(df, rownames = FALSE,
                         options = list(pageLength = 15, dom = "t"))
    DT::formatStyle(dt, "Class",
      backgroundColor = DT::styleEqual(
        c("User-reducible", "IPCC coefficient"),
        c("#D8F3DC", "#ECEFF1")),
      color = DT::styleEqual(
        c("User-reducible", "IPCC coefficient"),
        c("#1B4332", "#37474F")),
      fontWeight = "600")
  }

  output$trend_tornado_per_year <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_per_year(),
                         "Top 10 drivers — latest year")
  })

  output$trend_tornado_delta <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_delta(),
                         "Top 10 drivers — Δ Y_N − Y_1")
  })

  # Round 9: mirror outputs for the IPCC Report tab. Shiny requires unique
  # output IDs per UI element, so the same chart shown in two places needs two
  # render calls. Both delegate to the same reactive sources.
  output$trend_table_report <- DT::renderDT({
    req(rv_trend$results)
    DT::datatable(rv_trend$results, rownames = FALSE,
                  options = list(pageLength = 25, dom = "t"))
  })
  output$trend_plot_report <- plotly::renderPlotly({
    req(rv_trend$results)
    df <- rv_trend$results
    sub <- if (!is.null(rv_trend$slope) && !is.null(rv_trend$delta_total)) {
      sprintf("Δ vs base: %.1f%% (95%% CI %.1f%%, %.1f%%)  •  Slope: %.0f t CO₂eq/yr (95%% CI %.0f, %.0f)",
              rv_trend$delta_total$pct_mean,
              rv_trend$delta_total$pct_ci[1], rv_trend$delta_total$pct_ci[2],
              rv_trend$slope$mean,
              rv_trend$slope$ci[1], rv_trend$slope$ci[2])
    } else NULL
    plotly::plot_ly() |>
      plotly::add_ribbons(x = df$Year, ymin = df$CI_Lower_t, ymax = df$CI_Upper_t,
                          name = t("res_vb_ci_label"),
                          line = list(color = "transparent"),
                          fillcolor = "rgba(45,106,79,0.25)") |>
      plotly::add_trace(x = df$Year, y = df$Mean_t_CO2eq,
                        type = "scatter", mode = "lines+markers",
                        name = t("res_vb_mean_label"),
                        line = list(color = "#1B4332", width = 3),
                        marker = list(size = 8, color = "#1B4332")) |>
      plotly::layout(
        title = list(text = paste0(t("res_trend_plot_title"),
                                    if (!is.null(sub)) paste0("<br><sub>", sub, "</sub>") else "")),
        xaxis = list(title = t("res_trend_xaxis_year")),
        yaxis = list(title = t("res_hist_xaxis")),
        hovermode = "x unified"
      )
  })
  output$trend_tornado_per_year_report <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_per_year(),
                         "Top 10 drivers — latest year")
  })
  output$trend_tornado_delta_report <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_delta(),
                         "Top 10 drivers — Δ Y_N − Y_1")
  })
  # Round 9 follow-up: third copy of the trend tornadoes for Tab 6 (Sensitivity)
  # since each Shiny output ID can render in only one UI element. All three
  # copies (Tab 5 results, Tab 6, Tab 7 report) read from the same reactives.
  output$trend_tornado_per_year_sens <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_per_year(),
                         "Top 10 drivers — latest year")
  })
  output$trend_tornado_delta_sens <- plotly::renderPlotly({
    .trend_tornado_plot(trend_sens_delta(),
                         "Top 10 drivers — Δ Y_N − Y_1")
  })
  # Round 9 follow-up: rankings tables (Top 15) for trend mode, mirroring
  # the single-year output$sensitivity_table. Both SRC and PRCC columns
  # surfaced together; Class column is colour-coded (green = user-reducible,
  # grey = IPCC coefficient) to match the tornado bar palette.
  output$trend_sens_per_year_table <- DT::renderDT({
    .trend_sens_table(trend_sens_per_year())
  })
  output$trend_sens_delta_table <- DT::renderDT({
    .trend_sens_table(trend_sens_delta())
  })

  # Round 8 — Trend downloads (Excel / CSV / Word)

  .trend_filename <- function(ext) {
    yc <- if (!is.null(rv_trend$year_corr)) rv_trend$year_corr else "trend"
    paste0("trend_", yc, "_", Sys.Date(), ".", ext)
  }

  output$download_trend_xlsx <- downloadHandler(
    filename = function() .trend_filename("xlsx"),
    content = function(file) {
      shiny::validate(shiny::need(!is.null(rv_trend$results),
                    "Run a trend simulation on Tab 7 before downloading."))
      n_iter_val <- as.integer(input$n_iter %||% 10000)
      export_trend_xlsx(
        results_table        = rv_trend$results,
        slope                = rv_trend$slope,
        delta_total          = rv_trend$delta_total,
        sensitivity_per_year = trend_sens_per_year(),
        sensitivity_delta    = trend_sens_delta(),
        year_corr            = rv_trend$year_corr,
        n_iter               = n_iter_val,
        filepath             = file
      )
    }
  )

  output$download_trend_csv <- downloadHandler(
    filename = function() .trend_filename("csv"),
    content = function(file) {
      shiny::validate(shiny::need(!is.null(rv_trend$results),
                    "Run a trend simulation on Tab 7 before downloading."))
      write.csv(rv_trend$results, file, row.names = FALSE)
    }
  )

  output$download_trend_docx <- downloadHandler(
    filename = function() .trend_filename("docx"),
    content = function(file) {
      shiny::validate(shiny::need(!is.null(rv_trend$results),
                    "Run a trend simulation on Tab 7 before downloading."))
      n_iter_val <- as.integer(input$n_iter %||% 10000)
      build_trend_summary_docx(
        path                 = file,
        trend_results        = rv_trend$results,
        slope                = rv_trend$slope,
        delta_total          = rv_trend$delta_total,
        sensitivity_per_year = trend_sens_per_year(),
        sensitivity_delta    = trend_sens_delta(),
        year_corr            = rv_trend$year_corr,
        years                = rv_trend$years,
        n_iter               = n_iter_val,
        ipcc_meta            = rv$inv_metadata,
        param_specs          = rv$param_specs
      )
    }
  )

  # Round 8 — Contact / Feedback. The form is rendered as raw HTML+JS in
  # R/utils_contact.R via contact_form_html(); submission happens browser-side
  # (Web3Forms free tier blocks server-side POSTs). No Shiny observer needed.

  # 2026-06: in-app AI translator. Login + chat are encapsulated in
  # R/chat_ui.R; this single call registers all of its observers and
  # outputs. The translator UI is inserted into the Resources tab via
  # translator_chat_ui() in R/app_ui.R.
  translator_chat_server(input, output, session)
}
