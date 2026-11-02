# OpenAI API client for the in-app AI translator.
# Thin httr2 wrapper around https://api.openai.com/v1/chat/completions.
#
# Vendor + model picked per the June 2026 review: OpenAI GPT-4.1, the
# OpenAI flagship that matches Claude Sonnet's quality on structured
# data-mapping tasks (Excel column headers -> IPCC parameter names).
# Vendor swap is one function in this file.
#
# Configuration is via environment variables; the key NEVER appears in
# source. See R/usage_log.R for the per-call spend ledger and the
# monthly cap that gates this client.

# Pricing for GPT-4.1 as of 2026-06. Update when OpenAI changes prices.
# (Cost per 1M tokens, USD.)
.OPENAI_PRICING <- list(
  "gpt-4.1"     = list(input = 2.00, output = 8.00),
  "gpt-4o"      = list(input = 2.50, output = 10.00),
  "gpt-4o-mini" = list(input = 0.15, output = 0.60)
)
.OPENAI_DEFAULT_MODEL <- "gpt-4.1"
.OPENAI_ENDPOINT      <- "https://api.openai.com/v1/chat/completions"

# Assemble the system prompt from the four translator-kit asset files.
# Reuses the same .md files already in translator_prompts/ that the
# user-facing translator kit ships, so the in-app translator and the
# downloadable kit share a single source of truth.
#
# Returns a single character string ready to be sent as the first message
# in the conversation (role = "system"). At repo root the assembled
# prompt is roughly 12-15K tokens.
#
# 2026-09-17: the three GENERATED sections (param_catalogue, template_schema,
# worked_example) are no longer read from disk. They are built at runtime
# from the live R objects by R/translator_prompt_build.R, so a change to the
# defaults master or the template layout reaches the model on the next app
# start with no rebuild step. The three hand-written files are still read
# from disk, then passed through translator_prompt_fill_placeholders() so
# the literal defaults they used to carry ({{default:pct_pregnant:heifers}}
# and friends) are always current. The assembled prompt is memoised per
# process and its hash is exposed by translator_system_prompt_hash() for the
# conversation and workbook stamps (plan B5/B6).
.TSP_MEMO <- new.env(parent = emptyenv())

assemble_translator_system_prompt <- function(asset_dir = "translator_prompts") {
  if (!is.null(.TSP_MEMO[[asset_dir]])) return(.TSP_MEMO[[asset_dir]])
  generated <- c(param_catalogue = "param_catalogue",
                 template_schema = "template_schema",
                 worked_example  = "worked_example")
  # No prep sheet is shipped. The onboarding questions live in
  # system_instructions, and the model asks them itself, better placed after
  # it has seen the user's file. A separate form was removed on 2026-09-30.
  order <- c("system_instructions", "param_catalogue", "template_schema",
             "mapping_examples", "worked_example")
  parts <- lapply(order, function(nm) {
    body <- if (nm %in% names(generated)) {
      translator_generated_section(nm, partials_dir = file.path(asset_dir, "partials"))
    } else {
      p <- file.path(asset_dir, paste0(nm, ".md"))
      if (!file.exists(p)) {
        warning(sprintf("Translator-kit asset missing: %s, skipping.", p), call. = FALSE)
        return(NULL)
      }
      # HTML comments are maintainer notes; the model never sees them.
      translator_prompt_fill_placeholders(paste(
        .tp_strip_html_comments(readLines(p, warn = FALSE, encoding = "UTF-8")),
        collapse = "\n"))
    }
    paste0("# ", nm, "\n\n", body)
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0)
    stop("No translator-kit asset files found in ", asset_dir, call. = FALSE)

  # The output contract for the in-app tool call. Rewritten 2026-09-17: the
  # previous block listed BW, MW, WG, Milk, Fat, DE, CP, hours and
  # pct_pregnant as activity_data, contradicting the catalogue (N only), and
  # its manure example used `mcf: 0.015` (a fraction) where the sheet column
  # is MCF_pct in percent. Every field name and unit below now matches the
  # tool schema in R/anthropic_client.R and the template_schema section.
  n_par <- nrow(PARAM_CATALOGUE)
  marker_instruction <- paste(
    "",
    "",
    "## Output convention (in-app)",
    "",
    "You never write the template yourself in chat. When the user clicks",
    "the green Produce template now button, the server calls you with a",
    "tool named `emit_inventory_piece` and a `mode`; you answer by calling",
    "that tool once. The shape of its input is:",
    "",
    "```",
    "{",
    "  \"mode\": \"enumerate\" | \"batch\" | \"full\",",
    "  \"inventory_metadata\": {                       (enumerate and full)",
    "    \"country\": \"Zimbabwe\", \"region\": \"africa\", \"year\": 2024,",
    "    \"species\": \"cattle_non_dairy\", \"ipcc_version\": \"2019_refinement\",",
    "    \"prepared_by\": \"...\", \"notes\": \"...\"",
    "  },",
    "  \"aggregation_levels\": [\"commercial_dairy\", ...],   (enumerate only)",
    "  \"aggregation_level\": \"commercial_dairy\",           (batch only, echo the requested one)",
    "  \"parameters\": [                                  (batch and full)",
    "    {\"cattle_type\": \"dairy\", \"aggregation_level\": \"commercial_dairy\",",
    "     \"sub_category\": \"dairy_cows\", \"parameter\": \"N\", \"mean\": 250000,",
    "     \"uncertainty_pct\": 5, \"lower\": null, \"upper\": null,",
    "     \"distribution\": \"normal\", \"param_type\": \"activity_data\",",
    "     \"data_source\": \"user_file\"}",
    "  ],",
    "  \"manure_management\": [",
    "    {\"cattle_type\": \"dairy\", \"aggregation_level\": \"commercial_dairy\",",
    "     \"sub_category\": \"dairy_cows\", \"mms_type\": \"solid_storage\",",
    "     \"fraction_pct\": 60, \"MCF_pct\": 5, \"EF3\": 0.01,",
    "     \"Frac_GasMS_pct\": 45, \"Frac_LeachMS_pct\": 2}",
    "  ],",
    "  \"parameter_timeseries\": [",
    "    {\"cattle_type\": \"dairy\", \"aggregation_level\": \"commercial_dairy\",",
    "     \"sub_category\": \"dairy_cows\", \"year\": 2018, \"N\": 240000, \"Milk\": 9.1}",
    "  ]",
    "}",
    "```",
    "",
    "Rules:",
    "",
    sprintf("* `parameters[].parameter` MUST be one of the %d canonical codes in", n_par),
    "  param_catalogue.md. Nothing else: no `MCF`, no `C_growth` (use `C`).",
    "* `parameters[].param_type` is `activity_data` for `N` ONLY and",
    "  `coefficient` for every other parameter, however measurable it is.",
    "* `parameters[].distribution` is one of the codes listed in",
    "  param_catalogue.md.",
    "* Every parameters row carries `mean`, `distribution`, `param_type`,",
    "  `data_source`, and EITHER `uncertainty_pct` (symmetric, leave lower and",
    "  upper null) OR `lower` + `upper` (asymmetric or file-supplied bounds,",
    "  leave uncertainty_pct null). A `constant` row has lower = mean = upper.",
    "* `data_source` is one of `user_file`, `user_chat`, `ipcc_default`,",
    "  `biological_zero`, `placeholder`. Never omit it.",
    "* Manure units: `fraction_pct`, `MCF_pct`, `Frac_GasMS_pct` and",
    "  `Frac_LeachMS_pct` are PERCENTAGES (5 means 5 %); `EF3` is a fraction",
    "  (0.01). Every manure row carries all five.",
    "* `inventory_metadata.region` is always set from the country",
    "  (Zimbabwe -> africa, India -> asia, Brazil -> americas). Never leave",
    "  it for the server to guess.",
    "* `parameter_timeseries`: one row per (group, year) ONLY when the source",
    "  has multi-year activity data; fill only the columns that change across",
    "  years; `[]` otherwise. NEVER fabricate years that are not in the source.",
    "* Numbers are literals. Write 4.644, never 4.5*1.032. No placeholders",
    "  such as \"repeat for each sub-category\": every row is listed.",
    "",
    "In chat replies you respond in plain text only. While you are still",
    "gathering information, ask. When you have enough, end with one short",
    "sentence directing the user to click the green Produce template now",
    "button (in-app presentation rule 9): that is the ONLY way emission",
    "starts; typed phrases like 'go ahead' are not a trigger.",
    sep = "\n")

  # 2026-06: in-app UI presentation rules. These OVERRIDE any earlier
  # formatting guidance from the kit's system_instructions.md. The kit
  # was written for the claude.ai web workspace (wide screen, no rate
  # limits, users expecting a long-form analysis). The in-app chat panel
  # is narrow and users want focused answers fast. The rules below trim
  # the response style accordingly. Last-wins on conflicts, by OpenAI
  # convention (later instructions take precedence).
  ui_presentation_rules <- paste(
    "",
    "",
    "## In-app UI presentation rules (HIGHEST PRIORITY: override earlier rules)",
    "",
    "You are now deployed inside a small chat panel embedded in a Shiny",
    "web app, not in the claude.ai workspace. The UI is narrow and users",
    "want focused, fast answers. Apply these rules to every reply:",
    "",
    "1. **No preamble.** Do not introduce yourself, do not summarise what",
    "   you do, do not say 'Here is a brief summary' or 'Welcome!'. Start",
    "   directly with the most important substantive content.",
    "2. **Clarification replies: at most 3-5 questions each.** Save the",
    "   rest for the next round and pick the ones that block you most.",
    "   This cap does not apply to the explore reply's section D, which",
    "   lists every ambiguity (rule 10); the app paces those one at a",
    "   time itself.",
    "3. NO markdown formatting at all in chat replies. The chat panel",
    "   renders text as-is, so asterisks show up as literal asterisks,",
    "   which looks broken. Specifically:",
    "     - No **bold** or __bold__ markers: they appear as asterisks.",
    "     - No *italic* or _italic_ markers: same problem.",
    "     - No `inline code` backticks.",
    "     - No # or ## or ### headings.",
    "     - No markdown tables (| col | col |).",
    "   Use plain prose. If you need emphasis, restructure the sentence",
    "   so the important word comes first instead of bolding it. Short",
    "   bullet lists with a leading dash and a space (`- like this`) are",
    "   OK because they render visually as bullets even in plain text.",
    "4. **One step at a time.** Do not pre-announce 'Step 1 / Step 2 /",
    "   Step 3': just do the most important step and wait for the user.",
    "5. **Short paragraphs.** 2-4 sentences max. The chat panel is narrow.",
    "6. **Confirmations are terse.** 'OK: Cows in milk maps to dairy_cows'",
    "   is better than restating the reasoning.",
    "7. **No 'Next steps' / 'Summary' / 'Please answer above' meta-text.**",
    "   The user will reply when they're ready; trust them to drive the",
    "   conversation.",
    "8. **NEVER stall.** Forbidden phrases include 'Please wait while I",
    "   generate the output', 'I will now prepare the filled template',",
    "   'Generating now…', 'One moment…', 'Working on it…', or any",
    "   variant that implies you're about to do something IN A FOLLOW-UP",
    "   REPLY. This is a single-shot streaming chat: you have ONE",
    "   response to do the work and then stop talking.",
    "",
    "9. **NEVER emit the template yourself, EVER. The button is the only",
    "   way to start emission (updated 2026-06-12).** A complete filled",
    "   inventory is 200-1000+ JSON rows; it does not fit in the",
    "   streaming chat's token budget and gets truncated mid-array. The",
    "   in-app server runs the emission as a separate, batched,",
    "   tool_use-strict process that is ONLY triggered when the user",
    "   clicks the green Produce template now button below the chat.",
    "",
    "   Typed phrases like 'go ahead' / 'produce the template' /",
    "   'generate' / 'yes do it' are NO LONGER a trigger and never were",
    "   meant to be a deferral substitute. Treat them as a request to",
    "   confirm readiness, not a request to start emission. The correct",
    "   reply to any such phrase is one short sentence directing the",
    "   user to the button, e.g.: 'Great, everything's confirmed. To",
    "   start emission, click the green Produce template now button",
    "   below the chat. The server runs ~5 minutes of batched calls",
    "   and shows the Download button when done.'",
    "",
    "   When you finish a clarification round and have enough",
    "   information, ALWAYS end the reply with this same one-line",
    "   instruction: never inline JSON, never start emission yourself,",
    "   never promise to 'generate the template now'. The ONE exception",
    "   has been removed: even for tiny single-sub-category inventories,",
    "   the user clicks the button.",
    "",
    "10. **Explore reply: all four sections, written in full. The app",
    "    shows the user only the orientation lines and the questions.**",
    "    (From 2026-06-12 to 2026-10-23 this rule said 'Section D only,",
    "    no section A / B / C', after a run printed 16,000 tokens of",
    "    tables to the user. The app now keeps sections A to C out of",
    "    the user's view itself, and emission needs section B in the",
    "    transcript: the two runs of 2026-10-23 whose explore reply",
    "    skipped it emitted the wrong year's populations and invented",
    "    manure coefficients, while the runs that carried it were right.)",
    "",
    "    For the FIRST reply after a file upload (the EXPLORE step in",
    "    the system prompt's workflow), write, in this order:",
    "      - one short orientation line: \"I read your file: N sheets,",
    "        M production systems with K sub-categories total, parameters",
    "        found: <param list>. Inventory year inferred as YYYY.\"",
    "      - any gaps in one line: \"Missing from file (will use IPCC",
    "        defaults): <param list>.\"",
    "      - sections A, B and C in full, with the exact headers of the",
    "        system prompt's workflow (### A. File shape, ### B. Inventory",
    "        of values found, ### C. Inventory of GAPS). Section B is",
    "        your working inventory for emission: every value you will",
    "        emit, with its sheet, row and column, read from the",
    "        inventory year's column. The user does not see it unless",
    "        they ask.",
    "      - section D (### D. Ambiguities to ask the user): the",
    "        numbered questions, in full, last. End there and wait.",
    "",
    "    The app shows your numbered questions to the user ONE AT A TIME",
    "    and sends the answers back in one message, so never end with",
    "    \"Please answer the section D questions\" or any other",
    "    instruction to answer (added 2026-10-22). When the answers",
    "    arrive, do not ask again a question that was answered: say in",
    "    one line what you recorded, ask only what is still open, and if",
    "    nothing is open say so in one line and ask nothing; end that",
    "    reply with exactly: \"Click Produce template now when you are",
    "    ready; the server first checks my table of values against your",
    "    file.\" (never \"the inventory is ready for emission\": the",
    "    server's check comes after your reply). What the user's notes",
    "    or the settings given at upload already settle is not a",
    "    question: record it as a decision with basis user and do not",
    "    ask it (2026-11-01: ten questions were asked on a file whose",
    "    note answered eight of them).",
    "    Every question you ask, in every reply, is a numbered item",
    "    (1., 2., ...), even when there is only one, and the numbered",
    "    questions come LAST in the reply, after everything else",
    "    (added 2026-10-23): the app turns each numbered item into its",
    "    own bubble, and a question hidden in prose is missed. Anything",
    "    the user must answer, confirm or check (\"please confirm\",",
    "    \"please check whether\") is such a numbered item: never leave a",
    "    request in prose, and never write a lead-in line such as \"One",
    "    more question:\".",
    "",
    "    If the user asks 'show me what you found' or 'list the BWs you",
    "    have', answer with the relevant slice of B as a 5-15-row",
    "    excerpt, not the whole table again.",
    "",
    "11. **Decisions block (added 2026-10-22).** End EVERY reply in which",
    "    the user has answered something, or in which you have read or",
    "    assumed something that affects the template, with exactly one",
    "    fenced block labelled decisions, containing a JSON array. One",
    "    element per decision made or confirmed so far (cumulative: restate",
    "    earlier ones), with the fields topic, decision, basis, confidence,",
    "    quote. basis is user (the user said it), file (read from the file),",
    "    default (an IPCC default), or assumed. confidence is high, medium",
    "    or low; use low whenever you are not sure, so the app asks the",
    "    user. quote is the user's own words, verbatim, or the file cell.",
    "    Use these topic names where they fit: species, ipcc_edition,",
    "    inventory_year, aggregation_level, mms_split_source,",
    "    calves_handling, uncertainty_source, and pct_vs_fraction:<column>",
    "    or category:<label> for specific columns and categories, and",
    "    value:<parameter>:<sub_category> for one number; otherwise a",
    "    short snake_case name. A decision that applies to ONE production",
    "    system carries the system's snake_case level after an @ sign in",
    "    the topic (value:DE:other_cows@emergent_beef, or",
    "    de_range@emergent_beef); without @ it applies to every system,",
    "    so never leave the @ off a per-system decision (added",
    "    2026-10-31: a DE fix for one system was applied to another).",
    "    The block is not shown to the user; put it last, after your",
    "    questions. Example:",
    "",
    "    ```decisions",
    "    [{\"topic\": \"inventory_year\", \"decision\": \"2022\",",
    "      \"basis\": \"user\", \"confidence\": \"high\",",
    "      \"quote\": \"year 2022\"},",
    "     {\"topic\": \"calves_handling\", \"decision\": \"pooled: one",
    "      calves category per system, as in the file\", \"basis\":",
    "      \"file\", \"confidence\": \"high\", \"quote\": \"Calves\"},",
    "     {\"topic\": \"value:DE:other_cows@system_b\", \"decision\":",
    "      \"triangular 53.82 to 56.22 around the file's 55.02\",",
    "      \"basis\": \"user\", \"confidence\": \"high\",",
    "      \"quote\": \"centre the 2.4-point width on the value\"}]",
    "    ```",
    "",
    "    A decision the user has made is binding: never replace it with a",
    "    file reading or a default, and apply it in every emission call.",
    "    A decision with basis file is a reading of the file, not an",
    "    order: when the file says otherwise on re-reading, the file",
    "    wins and the reading is corrected. Never split a category",
    "    (calves or any other) into male and female unless the file",
    "    does; one source category becomes one template category.",
    "",
    "12. **Source categories block (added 2026-10-22).** The FIRST reply",
    "    after a file upload (the explore reply) also ends with exactly one",
    "    fenced block labelled source_categories: a JSON array with one",
    "    element per distinct animal category in the file, per production",
    "    system or region where the file has them, with the fields label",
    "    (exactly as written in the file), system (the file's own name for",
    "    the system or region), sub_category (the template code you map it",
    "    to), aggregation_level (the snake_case level you will emit),",
    "    merge_into (only when two source categories must become one",
    "    template group, naming the other label, with the reason in the",
    "    label), confidence (high | medium | low; low makes the app ask the",
    "    user). The server checks the finished template against this list:",
    "    every entry must come out as a group unless the user confirmed a",
    "    merge. The block is not shown to the user; put it after the",
    "    decisions block.",
    "",
    "13. **Source values block (added 2026-10-31, compact form",
    "    2026-11-01).** Section B of the explore reply is not a prose",
    "    table. It is one fenced block labelled source_values: a JSON",
    "    array with one object per sub-category and production system.",
    "    Each object has system (the production-system label exactly as",
    "    written in the file), label (the sub-category label exactly as",
    "    written on its rows), sub_category and aggregation_level",
    "    (template codes) and values: an array with one row per value you",
    "    will emit from the file for the inventory year (one row per",
    "    parameter and group; the other years of a time series are not",
    "    listed, the server checks them after production), one row per",
    "    line, in this fixed order:",
    "    [parameter, sheet, row, col, section, mean, lower, upper, unit,",
    "    distribution]. parameter is the catalogue code; sheet the sheet",
    "    name; row the JSON row key (an integer); col the header the mean",
    "    was read from (the year header, a header name from headers, or",
    "    the Excel letter); section the row's _section string copied",
    "    verbatim; mean, lower, upper numbers or null; unit a string or",
    "    null; distribution as in the file or null. A lower or upper read",
    "    from another sheet (a margin-of-error sheet) adds two more",
    "    elements: bounds_sheet, bounds_row. Under ### B. write one line,",
    "    \"source_values: N entries\" (N counts the value rows), then the",
    "    block. Sections A and C are lists, not tables.",
    "",
    "    The server checks every value row against the file cell by cell",
    "    (sheet, row, column, value, _section, labels) and sends back any",
    "    that does not match, once, as a SOURCE CHECK message: reply with",
    "    the whole block corrected and nothing else. In emission, every",
    "    row takes its mean, lower, upper and distribution from the value",
    "    row of the group with the same system and label and the same",
    "    parameter; the batch request names the file rows of its system.",
    "",
    "Shape of the two reply kinds, for reference (synthetic values; the",
    "numbers are not from any real file):",
    "",
    "  EXPLORE REPLY:",
    "    I read your file: 3 sheets, 2 production systems (System A,",
    "    System B) with 8 sub-categories, parameters found: N, BW, MW,",
    "    WG, Milk, DE, CP, Ym. Inventory year inferred as 2020.",
    "    Missing from file (will use IPCC defaults): Fat, pct_pregnant,",
    "    hours, Cfi, Ca, C, Cp, MilkPR, Bo, ASH, UE, Tw, EF3_PRP, EF4,",
    "    EF5, Frac_GASM_PRP, Frac_LEACH_PRP.",
    "    ### A. File shape",
    "    <one line per sheet>",
    "    ### B. Inventory of values found",
    "    source_values: 212 entries",
    "    ```source_values",
    "    [{\"system\": \"System A\", \"label\": \"Adult cows\", \"sub_category\": \"other_cows\", \"aggregation_level\": \"system_a\", \"values\": [",
    "    [\"N\", \"Data\", 2, \"2020\", \"Animal numbers\", 12500, 11250, 13750, \"head\", \"normal\", \"Margins\", 2],",
    "    [\"BW\", \"Data\", 5, \"2020\", \"Weight (kg)\", 410, null, null, \"kg\", null],",
    "    [\"MW\", \"Data\", 9, \"2020\", \"Mature weight (kg)\", 450, 430, 470, \"kg\", \"normal\"]",
    "    ]},",
    "    {\"system\": \"System A\", \"label\": \"Bulls\", \"sub_category\": \"bulls\", \"aggregation_level\": \"system_a\", \"values\": [",
    "    ...",
    "    ]}]",
    "    ```",
    "    ### C. Inventory of GAPS",
    "    <C1 missing values; C2 values without a range>",
    "    ### D. Ambiguities to ask the user",
    "    1. The year columns run 2015 to 2020: is 2020 the inventory",
    "       year?",
    "    2. The manure shares are given once for each system: do they",
    "       apply to every sub-category of that system?",
    "    3. The margin column holds values like 0.3: is that a fraction",
    "       (plus or minus 30 percent) or a percentage?",
    "    4. In System B the range given for adult cows' DE (58 to 60)",
    "       does not contain the value (57.4): which one should be",
    "       corrected?",
    "    ```decisions ... ```",
    "    ```source_categories ... ```",
    "",
    "  CLARIFICATION REPLY (after the user answers):",
    "    Recorded: 2020 is the inventory year; the manure split applies",
    "    to every sub-category; the margins are fractions.",
    "    1. <the next open question, if any>",
    "    ```decisions ... ```",
    "",
    "Stop after the questions. Wait for the user.",
    sep = "\n")

  out <- paste(c(parts, marker_instruction, ui_presentation_rules),
               collapse = "\n\n---\n\n")
  .TSP_MEMO[[asset_dir]] <- out
  out
}

# The emission checklist (2026-10-31): the rules behind the test-inventory errors,
# restated in about 250 tokens at the end of every emission request (the
# uncached tail, where the model weighs text most). The system prompt
# carries each of them in full; here they are the last thing read before
# the tool call.
translator_emission_checklist <- function() {
  req <- PARAM_CATALOGUE$parameter[!PARAM_CATALOGUE$param_tier %in% "optional"]
  opt <- PARAM_CATALOGUE$parameter[PARAM_CATALOGUE$param_tier %in% "optional"]
  paste(
    "EMISSION CHECKLIST (read once more before calling the tool):",
    "- Converted value: source_value, source_unit, conversion (with",
    "  lactation_days or conversion_factor), and source_lower and",
    "  source_upper when the bounds were converted too; every year of",
    "  its time series converted from that year's own value. The server",
    "  recomputes every one of them.",
    "- Right row: every value comes from the row whose block heading",
    "  (_section) names the parameter and whose system and sub-category",
    "  labels are the ones asked for; the Weight, Mature weight and",
    "  Weight gain blocks hold the same labels and are told apart only",
    "  by their heading.",
    sprintf("- All rows: %d parameters per group (%s), every group of this",
            length(req), paste(req, collapse = ", ")),
    sprintf("  system; no %s row unless the file measured it for that group.",
            paste(opt, collapse = " or ")),
    "- The file's distribution on every row that names one. A percentage",
    "  margin is uncertainty_pct with null bounds; a bound pair is lower",
    "  and upper with null uncertainty_pct; never both on one row.",
    "- This system only: no row of another production system, whatever",
    "  its label says.",
    "- One year column for the Parameters sheet (the inventory year). The",
    "  time series takes each year from its own column, for every group",
    "  and every year column of the file; [] when the file has one year.",
    "- Every line of the file labelled 'all ...' applies to every row it",
    "  names, in every system.",
    "- A value you converted (milk per lactating day, lb, L) keeps",
    "  user_file; the file's number and the factor are stated in your",
    "  reply and the server recomputes them.",
    sep = "\n")
}

# sha256 of the assembled prompt. Saved with every conversation (a resumed
# conversation whose hash differs from the live prompt cannot produce a
# template until the file is re-uploaded) and written into every translator
# workbook's Notes cell, so a downloaded file can be traced to the defaults
# it was built with.
translator_system_prompt_hash <- function(asset_dir = "translator_prompts") {
  key <- paste0(asset_dir, "#hash")
  if (!is.null(.TSP_MEMO[[key]])) return(.TSP_MEMO[[key]])
  h <- .tp_sha256(assemble_translator_system_prompt(asset_dir))
  .TSP_MEMO[[key]] <- h
  h
}
translator_system_prompt_reset <- function() {
  rm(list = ls(.TSP_MEMO), envir = .TSP_MEMO)
  if (exists("translator_prompt_reset")) translator_prompt_reset()
}

# Internal helper: estimate token count (approximate). OpenAI uses BPE
# tokenisation; a rule-of-thumb for English text is ~4 chars/token. We
# use this only for budget projection BEFORE a call is made; the actual
# token count comes back from the API in the `usage` block.
.estimate_tokens <- function(text) {
  if (is.null(text) || !nzchar(text)) return(0L)
  as.integer(ceiling(nchar(text) / 4))
}

# Cost in USD for a usage tuple, with GPT-4.1's implicit prompt-cache
# discount applied. Cached tokens cost 50% of the normal input price
# (OpenAI's "Automatic Prompt Caching" feature, applied when a system
# prompt of ≥1024 tokens has been seen within the past ~5-10 minutes).
# Verify the discount factor against
# <https://platform.openai.com/docs/pricing> if pricing changes.
openai_cost_usd <- function(prompt_tokens, completion_tokens,
                             model = .OPENAI_DEFAULT_MODEL,
                             cached_tokens = 0L) {
  p <- .OPENAI_PRICING[[model]]
  if (is.null(p)) {
    warning(sprintf("Unknown model '%s'; cost reported as NA.", model),
            call. = FALSE)
    return(NA_real_)
  }
  cached_tokens <- min(cached_tokens %||% 0L, prompt_tokens %||% 0L)
  non_cached    <- max((prompt_tokens %||% 0L) - cached_tokens, 0L)
  (non_cached      / 1e6) * p$input        +
  (cached_tokens   / 1e6) * p$input * 0.5  +
  (completion_tokens / 1e6) * p$output
}

# Main entry point.
#
# `messages` is a list of lists, each shaped like
#   list(role = "system"|"user"|"assistant", content = "<text>").
# The function adds the OpenAI auth header from the env var, posts the
# request, and returns a list with three named slots:
#
#   $reply              character: the assistant's reply text
#   $usage              list     : prompt_tokens, completion_tokens, total_tokens
#   $model              character: the model name OpenAI confirmed
#   $cost_usd           numeric  : estimated USD cost of this call
#
# On any non-2xx response, returns a list with $error set to a
# user-friendly message and $reply = NULL. The caller (the Shiny chat
# observer) is responsible for surfacing the error to the user.
openai_chat <- function(messages,
                         model = .OPENAI_DEFAULT_MODEL,
                         max_tokens = 16000,
                         temperature = 0.2,
                         timeout_sec = 90) {
  api_key <- Sys.getenv("OPENAI_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the OPENAI_API_KEY). Please contact the administrator."))
  }

  body <- list(
    model       = model,
    messages    = messages,
    max_tokens  = max_tokens,
    temperature = temperature
  )

  req <- httr2::request(.OPENAI_ENDPOINT) |>
    httr2::req_headers(
      `Authorization` = paste("Bearer", api_key),
      `Content-Type`  = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)  # we'll inspect ourselves

  resp <- tryCatch(httr2::req_perform(req),
                    error = function(e) e)

  if (inherits(resp, "error")) {
    return(list(reply = NULL,
                error = paste0("Could not reach OpenAI (", conditionMessage(resp),
                               "). Try again in a minute.")))
  }

  status <- httr2::resp_status(resp)
  if (status >= 200 && status < 300) {
    parsed <- httr2::resp_body_json(resp)
    reply <- tryCatch(parsed$choices[[1]]$message$content,
                       error = function(e) NULL)
    if (is.null(reply) || !nzchar(reply)) {
      return(list(reply = NULL,
                  error = "OpenAI returned an empty reply. Try again."))
    }
    usage <- parsed$usage %||% list(prompt_tokens = 0L,
                                     completion_tokens = 0L,
                                     total_tokens = 0L)
    cached_tokens <- usage$prompt_tokens_details$cached_tokens %||% 0L
    list(
      reply    = reply,
      usage    = list(prompt_tokens     = usage$prompt_tokens     %||% 0L,
                       completion_tokens = usage$completion_tokens %||% 0L,
                       cached_tokens     = cached_tokens,
                       total_tokens      = usage$total_tokens     %||%
                                            ((usage$prompt_tokens %||% 0L) +
                                             (usage$completion_tokens %||% 0L))),
      model    = parsed$model %||% model,
      cost_usd = openai_cost_usd(usage$prompt_tokens     %||% 0L,
                                  usage$completion_tokens %||% 0L,
                                  parsed$model %||% model,
                                  cached_tokens = cached_tokens),
      error    = NULL
    )
  } else {
    # Map common error statuses to user-friendly messages.
    user_msg <- switch(as.character(status),
      "401" = "AI translator authentication failed. The server's OPENAI_API_KEY is missing or invalid: please contact the administrator.",
      "403" = "AI translator is blocked by OpenAI. The administrator may need to add billing or remove a usage cap.",
      "429" = "OpenAI is rate-limiting requests. Try again in a minute.",
      "500" = "OpenAI is having trouble. Try again later.",
      "502" = "OpenAI is having trouble. Try again later.",
      "503" = "OpenAI is having trouble. Try again later.",
      "504" = "OpenAI is having trouble. Try again later.",
      sprintf("OpenAI returned an unexpected error (HTTP %d). Try again later.", status)
    )
    # Try to surface the API's own error_message for diagnostics: but
    # don't show it to the user (could leak request internals); log via
    # message() so it lands in the Shiny server log.
    tryCatch({
      body <- httr2::resp_body_json(resp)
      msg  <- body$error$message %||% ""
      if (nzchar(msg)) message("OpenAI error body: ", msg)
    }, error = function(e) NULL)
    list(reply = NULL, error = user_msg)
  }
}

# Streaming variant of openai_chat().
#
# Uses OpenAI's `stream: true` mode (Server-Sent Events) so the response
# tokens arrive incrementally as the model generates them. The supplied
# `on_chunk(text)` callback is fired once per token delta: typically
# the Shiny chat UI uses this to push the new text to the browser via
# `session$sendCustomMessage()` so the bubble appears to type out live.
#
# Returns the same shape as openai_chat() when the stream finishes:
#   $reply / $usage / $model / $cost_usd / $error
# but the assembled $reply is the concatenation of every delta, which
# matches what a non-streaming call would have returned. Usage info is
# in the FINAL chunk when `stream_options.include_usage = TRUE`.
openai_chat_stream <- function(messages,
                                on_chunk = function(text) {},
                                model = .OPENAI_DEFAULT_MODEL,
                                max_tokens = 16000,
                                temperature = 0.2,
                                timeout_sec = 180,
                                max_retries = 2,
                                response_format = NULL) {
  api_key <- Sys.getenv("OPENAI_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    return(list(reply = NULL,
                error = "AI translator is not configured (server is missing the OPENAI_API_KEY). Please contact the administrator."))
  }

  body <- list(
    model          = model,
    messages       = messages,
    max_tokens     = max_tokens,
    temperature    = temperature,
    stream         = TRUE,
    stream_options = list(include_usage = TRUE)
  )
  # Optional response_format (e.g. json_schema strict mode). Streaming
  # supports it: chunks arrive with delta.content fragments of the
  # JSON, accumulated they form the complete validated payload. Lets
  # the force-template path share this streaming machinery and avoid
  # the 180s timeout that hit the old non-streaming call.
  if (!is.null(response_format)) body$response_format <- response_format

  # Retry loop. Only retries while NO chunks have been emitted to the
  # browser yet: once the user has seen partial output we can't safely
  # restart without duplicating tokens.
  attempt   <- 0
  last_err  <- NULL
  last_msg  <- NULL
  final_resp <- NULL

  repeat {
    attempt <- attempt + 1

    # Reset per-attempt state.
    accumulated <- ""
    final_usage <- NULL
    sse_buffer  <- ""

    on_data <- function(data) {
      chunk_text <- rawToChar(data)
      sse_buffer <<- paste0(sse_buffer, chunk_text)
      while (grepl("\n\n", sse_buffer, fixed = TRUE)) {
        split <- regmatches(sse_buffer,
                            regexpr("\n\n", sse_buffer, fixed = TRUE),
                            invert = TRUE)[[1]]
        event       <- split[1]
        sse_buffer <<- if (length(split) >= 2) split[2] else ""
        for (line in strsplit(event, "\n", fixed = TRUE)[[1]]) {
          if (!startsWith(line, "data: ")) next
          payload <- substring(line, 7)
          if (payload == "[DONE]") next
          parsed <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = FALSE),
                              error = function(e) NULL)
          if (is.null(parsed)) next
          if (!is.null(parsed$usage)) final_usage <<- parsed$usage
          if (length(parsed$choices) >= 1) {
            delta <- parsed$choices[[1]]$delta$content
            if (!is.null(delta) && nzchar(delta)) {
              accumulated <<- paste0(accumulated, delta)
              tryCatch(on_chunk(delta), error = function(e) {
                message("translator stream on_chunk error: ", conditionMessage(e))
              })
            }
          }
        }
      }
      TRUE
    }

    req <- httr2::request(.OPENAI_ENDPOINT) |>
      httr2::req_headers(
        `Authorization` = paste("Bearer", api_key),
        `Content-Type`  = "application/json",
        `Accept`        = "text/event-stream"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(timeout_sec) |>
      # Stall detector: if the stream sends < 1 byte/sec for 45 seconds,
      # treat the call as dead and abort. This is the right knob for a
      # streaming API: wall-clock timeouts kill calls that are still
      # legitimately progressing (e.g. a 6MB response that legitimately
      # takes 4 minutes to fully stream). curl options are exposed via
      # req_options() and map directly to CURLOPT_LOW_SPEED_*.
      httr2::req_options(low_speed_time = 45L, low_speed_limit = 1L) |>
      httr2::req_error(is_error = function(resp) FALSE)

    resp <- tryCatch(httr2::req_perform_stream(req, on_data, buffer_kb = 16),
                      error = function(e) e)

    # Decide outcome of this attempt.
    if (inherits(resp, "error")) {
      last_err <- conditionMessage(resp)
      status   <- NA_integer_
    } else {
      last_err <- NULL
      status   <- httr2::resp_status(resp)
    }

    success_status <- !is.na(status) && status >= 200 && status < 300
    transient_status <- !is.na(status) && (status == 429 || status >= 500)
    network_error    <- inherits(resp, "error")

    if (success_status) {
      final_resp <- resp
      break
    }

    # Don't retry if user already saw some text: would duplicate output.
    if (nzchar(accumulated)) {
      final_resp <- resp
      break
    }

    # Don't retry on non-transient client errors (401, 403, 404, ...).
    if (!network_error && !transient_status) {
      final_resp <- resp
      break
    }

    if (attempt > max_retries) {
      final_resp <- resp
      break
    }

    delay <- c(1, 3)[min(attempt, 2)]
    message(sprintf("openai_chat_stream: retrying after %ds (attempt %d/%d, status=%s)",
                     delay, attempt, max_retries + 1L,
                     if (is.na(status)) last_err else as.character(status)))
    Sys.sleep(delay)
  }

  # Handle final outcome.
  resp <- final_resp
  if (inherits(resp, "error")) {
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = paste0("Streaming failed (", last_err,
                               "). Try again in a minute.")))
  }

  status <- httr2::resp_status(resp)
  if (status >= 300) {
    tryCatch({
      body <- httr2::resp_body_json(resp)
      msg  <- body$error$message %||% ""
      if (nzchar(msg)) message("OpenAI stream error: ", msg)
    }, error = function(e) NULL)
    user_msg <- switch(as.character(status),
      "401" = "AI translator authentication failed. Please contact the administrator.",
      "403" = "AI translator is blocked by OpenAI. The administrator may need to add billing.",
      "429" = "OpenAI is rate-limiting requests. Try again in a minute.",
      sprintf("OpenAI returned HTTP %d. Try again later.", status))
    return(list(reply = if (nzchar(accumulated)) accumulated else NULL,
                error = user_msg))
  }

  prompt_tokens     <- final_usage$prompt_tokens     %||% 0L
  completion_tokens <- final_usage$completion_tokens %||% 0L
  # GPT-4.1 implicit prompt caching surfaces in usage.prompt_tokens_details.
  cached_tokens     <- final_usage$prompt_tokens_details$cached_tokens %||% 0L
  list(
    reply    = accumulated,
    usage    = list(prompt_tokens     = prompt_tokens,
                     completion_tokens = completion_tokens,
                     cached_tokens     = cached_tokens,
                     total_tokens      = prompt_tokens + completion_tokens),
    model    = model,
    cost_usd = openai_cost_usd(prompt_tokens, completion_tokens, model,
                                cached_tokens = cached_tokens),
    error    = NULL
  )
}

# Non-streaming variant that uses OpenAI's `response_format: json_schema`
# strict mode to force a guaranteed-valid filled-template JSON. Called
# only by the "Produce template now" button: the regular chat path
# stays text/streaming.
#
# The strict-mode schema mirrors `.translator_write_template_xlsx()`'s
# expectations. If the model produces anything that doesn't match the
# schema, OpenAI returns an error and the user sees a clear message.
openai_chat_template_force <- function(messages,
                                        on_chunk = function(text) {},
                                        model = .OPENAI_DEFAULT_MODEL,
                                        max_tokens = 32000,  # GPT-4.1 max output is 32768
                                        timeout_sec = 600) {  # 10-min wall-clock: actual progress check is the stall detector in openai_chat_stream
  # Build the json_schema response_format, then delegate to
  # openai_chat_stream so we get streaming (no 180s timeout) + the
  # built-in retry logic for free. The on_chunk callback lets the
  # caller observe progress as JSON streams in: useful for updating
  # the progress bubble on the client.
  schema_body <- list(
      type = "json_schema",
      json_schema = list(
        name   = "filled_inventory_template",
        strict = FALSE,
        schema = list(
          type = "object",
          properties = list(
            inventory_metadata = list(
              type = "object",
              properties = list(
                country      = list(type = "string"),
                year         = list(type = c("integer", "string")),
                species      = list(type = "string"),
                ipcc_version = list(type = "string"),
                prepared_by  = list(type = "string"),
                notes        = list(type = "string")
              )
            ),
            parameters = list(
              type  = "array",
              items = list(
                type = "object",
                properties = list(
                  cattle_type       = list(type = "string"),
                  aggregation_level = list(type = "string"),
                  sub_category      = list(type = "string"),
                  parameter         = list(type = "string"),
                  mean              = list(type = "number"),
                  uncertainty_pct   = list(type = c("number", "null")),
                  lower             = list(type = c("number", "null")),
                  upper             = list(type = c("number", "null")),
                  distribution      = list(type = "string"),
                  param_type        = list(type = "string")
                ),
                required = c("sub_category", "parameter", "mean",
                              "distribution", "param_type")
              )
            ),
            manure_management = list(
              type  = "array",
              items = list(
                type = "object",
                properties = list(
                  cattle_type       = list(type = "string"),
                  aggregation_level = list(type = "string"),
                  sub_category      = list(type = "string"),
                  mms_type          = list(type = "string"),
                  fraction_pct      = list(type = "number"),
                  # Optional bounds on the allocation fraction. The
                  # simulator samples these when present; an absent or
                  # equal-to-central value degenerates to deterministic.
                  lower_fraction    = list(type = c("number", "null")),
                  upper_fraction    = list(type = c("number", "null")),
                  distribution_fraction = list(type = c("string", "null")),
                  MCF_pct           = list(type = c("number", "null")),
                  # Optional bounds on the IPCC coefficients: populate
                  # from user-supplied data when available, otherwise
                  # leave null and the catalogue defaults are used.
                  lower_mcf         = list(type = c("number", "null")),
                  upper_mcf         = list(type = c("number", "null")),
                  distribution_mcf  = list(type = c("string", "null")),
                  EF3               = list(type = c("number", "null")),
                  lower_ef3         = list(type = c("number", "null")),
                  upper_ef3         = list(type = c("number", "null")),
                  distribution_ef3  = list(type = c("string", "null")),
                  Frac_GasMS_pct    = list(type = c("number", "null")),
                  lower_frac_gas    = list(type = c("number", "null")),
                  upper_frac_gas    = list(type = c("number", "null")),
                  distribution_frac_gas = list(type = c("string", "null")),
                  Frac_LeachMS_pct  = list(type = c("number", "null")),
                  lower_frac_leach  = list(type = c("number", "null")),
                  upper_frac_leach  = list(type = c("number", "null")),
                  distribution_frac_leach = list(type = c("string", "null"))
                ),
                required = c("sub_category", "mms_type", "fraction_pct",
                              "MCF_pct", "EF3",
                              "Frac_GasMS_pct", "Frac_LeachMS_pct")
              )
            )
          ),
          required = I(c("parameters"))  # I() preserves single-element vector as a JSON array; without it jsonlite auto-unboxes to "required":"parameters" which OpenAI rejects ("parameters is not of type 'array'")
        )  # closes schema
      )    # closes json_schema
    )      # closes schema_body
  # (one trailing close bracket removed: was a leftover from the old non-streaming wrapper)

  openai_chat_stream(
    messages        = messages,
    on_chunk        = on_chunk,
    model           = model,
    max_tokens      = max_tokens,
    temperature     = 0,
    timeout_sec     = timeout_sec,
    response_format = schema_body
  )
}

# Convenience: build the message list for the chat UI from
# (system_prompt, history, new_user_message).
openai_build_messages <- function(system_prompt, history = list(),
                                   new_user_message = NULL) {
  msgs <- list(list(role = "system", content = system_prompt))
  for (m in history) {
    if (!is.null(m$role) && !is.null(m$content) && nzchar(m$content))
      msgs[[length(msgs) + 1]] <- list(role = m$role, content = m$content)
  }
  if (!is.null(new_user_message) && nzchar(new_user_message))
    msgs[[length(msgs) + 1]] <- list(role = "user", content = new_user_message)
  msgs
}
