# Build "What the tool assumes" Word document at the project root.
suppressMessages({library(officer); library(flextable)})
out <- "What_the_tool_assumes_and_what_it_would_take_to_offer_every_option.docx"

doc <- read_docx()
H1 <- function(t) { doc <<- body_add_par(doc, t, style = "heading 1"); invisible() }
H2 <- function(t) { doc <<- body_add_par(doc, t, style = "heading 2"); invisible() }
P  <- function(t) { doc <<- body_add_par(doc, t, style = "Normal"); invisible() }
TB <- function(df, widths = NULL) {
  ft <- flextable(df)
  ft <- theme_box(ft)
  ft <- bg(ft, bg = "#E7E6E6", part = "header")
  ft <- bold(ft, part = "header")
  ft <- fontsize(ft, size = 9, part = "all")
  ft <- padding(ft, padding = 3, part = "all")
  if (!is.null(widths)) for (j in seq_along(widths)) ft <- width(ft, j = j, width = widths[j])
  doc <<- body_add_flextable(doc, ft)
  doc <<- body_add_par(doc, "", style = "Normal")
  invisible()
}
df <- function(...) data.frame(..., check.names = FALSE, stringsAsFactors = FALSE)

doc <- body_add_par(doc, "What the cattle uncertainty tool assumes, and what it would take to offer every option", style = "heading 1")
P("Cattle GHG Tier 2 uncertainty tool. Alliance Bioversity-CIAT, Global Methane Hub emissions uncertainty project. 21 September 2026.")

H1("1. Why this document exists")
P("The tool fills in an IPCC default for every value a country does not supply. Each default is one cell of a much larger IPCC table. To reach that cell the tool had to pick a region, a productivity level, a climate and, for manure, one version of each storage system. Those picks are the assumptions. They are listed here in plain words, with the numbers they produce, the other options the IPCC guidelines offer, and what it would take to let a user choose among all of them.")
P("Two things to keep in mind. First, a default is only used when the uploaded file has no value for that parameter. A country that supplies all its own numbers is not affected by any of this. Second, every run report (Word and Excel) now carries the same list of assumptions, with a column saying whether the run relied on each one.")

H1("2. How to read the tables")
P("For each assumption there are four parts. What we assume today. The default values it produces. What the IPCC guidelines also offer. What it would take to make every option available, with a rough effort. Effort is given in working days for one developer and does not include review by the science lead.")

# ---------------------------------------------------------------------------
H1("3. The eight declared assumptions")

H2("3.1 Region: Africa")
P("What we assume. When the file gives no body weight, milk yield, milk fat, pregnancy rate, feed digestibility, crude protein or working hours, the tool uses the Africa rows of the IPCC 2019 Refinement Annex tables 10A.1 (dairy cattle) and 10A.2 (other cattle).")
P("Default values it produces (typical rows).")
TB(df(Parameter = c("Body weight (kg)", "Mature weight (kg)", "Daily weight gain (kg/day)", "Milk yield (kg/head/day, annual average)", "Milk fat (%)", "Feed digestibility DE (%)", "Crude protein CP (%)", "Share of cows pregnant"),
      `Dairy cows` = c("270", "300", "0", "1.2", "4.3", "51", "9.6", "0.52"),
      `Other cows` = c("275", "300", "0", "1.2", "4.3", "58", "10", "0.54"),
      Heifers = c("200", "300", "0.25", "0", "0", "59", "10.4", "0.5"),
      Bulls = c("350", "400", "0", "0", "0", "58", "10", "0"),
      Calves = c("60", "300", "0.3", "0", "0", "59", "10.3", "0"),
      Feedlot = c("250", "400", "1.0", "0", "0", "74", "14", "0")),
   widths = c(2.0, 0.8, 0.8, 0.7, 0.7, 0.7, 0.7))
P("What IPCC also offers. The same two tables have rows for North America, Western Europe, Eastern Europe, Oceania, Latin America, Asia, the Middle East and the Indian subcontinent, each split into productivity levels.")
P("What it would take to offer every option. The template already has a region field, but today it is only used to judge whether a body weight looks plausible. Making it drive the defaults means typing the full Annex 10A.1 and 10A.2 tables into the defaults master (nine regions, two or three productivity rows each, about ten parameters, dairy and other cattle) and making the default resolver read the region. About three days, most of it careful data entry and checking against the PDF.")

H2("3.2 Productivity level: low productivity")
P("What we assume. Within the Africa rows the tool uses the low productivity row. That is a small animal with a low milk yield kept on pasture. It also sets the methane producing potential of manure (Bo 0.13) and the enteric methane conversion factor (Ym 6.5 for dairy cows, 7.0 for other cattle).")
P("What IPCC also offers. A high productivity row (milk 5.8 kg/day, body weight 250 kg for dairy) and a regional aggregate row (milk 3.5, body weight 260). Bo has a high productivity value of 0.18 for dairy cows in some regions.")
P("What it would take. Once the full regional tables are in the master (3.1), a productivity field in the template with three choices, and the resolver picking the row. About one day on top of 3.1.")

H2("3.3 Feeding situation: grazing on flat pasture")
P("What we assume. The activity coefficient Ca is 0.17 for every animal. That is the IPCC value for animals grazing flat pasture.")
P("What IPCC also offers (Table 10.5). Stall-fed animals: 0. Grazing large areas or hilly terrain: 0.36.")
P("What it would take. A feeding situation dropdown per animal group in the template, or per production system, mapped to the three values. Half a day. A user can already do this by typing Ca into the Parameters sheet.")

H2("3.4 Manure nitrogen losses: the Other Cattle column, also for dairy cows")
P("What we assume. The share of manure nitrogen lost to the air or by leaching in each storage system comes from the Other Cattle column of IPCC Table 10.22, for every herd including dairy cows.")
P("Default values it produces (share of nitrogen lost).")
TB(df(`Storage system` = c("Solid storage", "Covered solid storage", "Dry lot", "Deep bedding", "Liquid slurry (with crust)", "Composting (static pile)", "Anaerobic digester", "Daily spread", "Pasture", "Burned for fuel"),
      `To air, this tool (other cattle)` = c("0.45", "0.22", "0.30", "0.25", "0.30", "0.65", "0.48", "0.07", "0 (pasture handled separately)", "0"),
      `To air, IPCC dairy cow column` = c("0.30", "0.14", "0.30", "0.25", "0.30", "0.50", "0.48", "0.07", "same", "0"),
      `By leaching, this tool` = c("0.02", "0", "0.035", "0.035", "0", "0.06", "0", "0", "0.24 (pasture parameter)", "0")),
   widths = c(1.8, 1.6, 1.6, 1.5))
P("What it would take. The dairy cow column is already in the IPCC table. Adding it to the master and choosing the column from the cattle type of each row is half a day. Effect: for a dairy herd using solid storage or composting, indirect nitrous oxide falls by about a third for those systems.")

H2("3.5 Climate for soil nitrogen: wet")
P("What we assume. The three factors that govern nitrous oxide from manure deposited on pasture use the wet climate values of IPCC 2019 Tables 11.1 and 11.3.")
TB(df(Factor = c("EF3_PRP, direct N2O from deposited manure", "EF4, indirect N2O from volatilised nitrogen", "Frac_LEACH_PRP, share of nitrogen leached"),
      `This tool (wet)` = c("0.006", "0.014", "0.24"),
      `IPCC dry climate` = c("0.002", "0.005", "0 (no leaching)"),
      `IPCC climate aggregated` = c("0.004", "0.010", "0.24")),
   widths = c(2.8, 1.1, 1.2, 1.4))
P("What it would take. A wet or dry choice in the template metadata, applied to the three factors. Half a day. This matters: keeping the wet values in a dry country overstates direct pasture nitrous oxide about three times.")

H2("3.6 Climate for manure methane: tropical")
P("What we assume. Whenever the tool fills a methane conversion factor (MCF) for a storage system, it takes the tropical value. Values typed by the user are used as given. The tropical values come from the 2006 Guidelines table, read at 28 degrees and above.")
P("Default values it produces (MCF, percent of methane potential released).")
TB(df(`Storage system` = c("Pasture", "Daily spread", "Solid storage", "Dry lot", "Deep bedding", "Liquid slurry (with crust)", "Composting (static pile)", "Anaerobic lagoon", "Anaerobic digester", "Burned for fuel"),
      Tropical = c("2", "1", "5", "2", "80", "50", "0.5", "80", "4.59", "10"),
      Temperate = c("1.5", "0.5", "4", "1.5", "39", "24", "0.5", "77", "4.38", "10"),
      Boreal = c("1", "0.1", "2", "1", "17", "10", "0.5", "66", "3.55", "10")),
   widths = c(2.2, 1.0, 1.0, 1.0))
P("What IPCC also offers. The 2019 Refinement replaces the temperature table by ten climate zones (for example warm temperate moist, tropical montane, tropical dry). Its tropical dry column equals the tropical column above in this tool.")
P("What it would take. A climate zone field in the template, and the ten-zone 2019 table in the master for every storage system. One to two days. One complication: the 2019 pasture value (0.47 percent) must be used together with a pasture-specific Bo of 0.19, and the tool carries a single Bo per animal, so the engine would need a per-system Bo. That is one more day.")

H2("3.7 One IPCC variant per manure storage system")
P("What we assume. Each storage system in the manure sheet stands for one specific IPCC variant. All coefficients on that row come from that variant.")
TB(df(`System in the tool` = c("Liquid slurry", "Composting", "Solid storage", "Deep bedding", "Anaerobic digester", "Anaerobic lagoon"),
      `Variant used` = c("With natural crust cover", "Static pile, forced aeration", "Plain (covered or compacted is a separate system)", "More than one month accumulation", "Low leakage, open storage", "Uncovered"),
      `Other IPCC variants` = c("Without crust (higher methane and nitrogen loss)", "In vessel; intensive windrow; passive windrow", "With bulking agent; with additives", "Less than one month; with or without mixing", "Covered storage (nitrogen loss 0.05 instead of 0.48)", "Covered")),
   widths = c(1.4, 2.2, 2.9))
P("What it would take. A variant dropdown on each manure row, with a coefficient set per variant in the master. Two days. Today a user can achieve the same result by typing the coefficients for their variant into the row.")

H2("3.8 Species: cattle")
P("What we assume. Every default is for cattle. Buffalo, which the IPCC treats separately (Bo 0.10, different weights), are not covered.")
P("What it would take. A species switch in the metadata and a buffalo set of defaults. About two days, because the animal energy equations also need buffalo coefficients.")

# ---------------------------------------------------------------------------
H1("4. Assumptions not yet declared")
P("The tool makes further choices that are visible only in the code and in the technical notes. They are not yet rows of the defaults master, so they do not appear in the reports or guides. The ones a compiler would care about are listed below. Adding each as a declared row is about half a day of work, after which every report, guide and template picks it up automatically.")
TB(df(Assumption = c("Composting methane factor is the 2006 static pile value (0.5 percent in all climates) although the declared variant is the 2019 one, whose value depends on temperature and is higher.",
                     "Temperate manure methane factors read the 2006 table at 19 degrees; boreal at 10 degrees or less; tropical at 28 degrees or more.",
                     "Three lower bounds are lifted slightly above zero (EF3_PRP and EF5 to 0.0005, Frac_GASM_PRP to 0.005) because two of the sampling distributions cannot start at exactly zero.",
                     "Calves are the forage-fed class (Ym 7.0). Milk-fed calves before weaning, which emit almost no enteric methane, have no group of their own.",
                     "Oxen work zero hours a day unless the user enters hours. The IPCC Africa table gives draft animals 1.1 hours.",
                     "Replacement heifers are 50 percent pregnant. The IPCC table leaves that cell blank.",
                     "Mature weight is a project assumption. IPCC publishes no mature weight table; the tool reads it as the target weight of the growth stage.",
                     "Winter temperature is 20 degrees, so the cold stress adjustment does nothing unless the user sets it.",
                     "Feedlot values are borrowed from the Latin and North America rows because the Africa table has no feedlot row.",
                     "When a file has no manure sheet, the tool assumes 70 percent of manure on pasture and 30 percent in solid storage.",
                     "Uncertainty ranges for some leaching fractions are project inventions where IPCC gives only a single value.",
                     "The uncertainty percentages shipped with most defaults are not IPCC values. They come from Penman et al. (2000) and Monni et al. (2007). Only Ym and Bo have IPCC ranges."),
      `What it would take` = c("Declare it, or switch to the 2019 value with the climate zone field of 3.6.",
                               "Declare it. Replaced entirely by the climate zone field of 3.6.",
                               "Declare it. No user option needed.",
                               "Declare it. A milk-fed calf group is a science decision, then one day.",
                               "A decision by the science lead, then declare or change the default.",
                               "Declare it.",
                               "Declare it in the user guide, where it is not yet marked as non-IPCC.",
                               "Declare it. Adequate as it is.",
                               "Declare it. Adequate as it is.",
                               "Declare it, and make the trend analysis respect an uploaded manure sheet, which it does not today.",
                               "Declare it.",
                               "Already stated in the guides and shown as an information row in the QA tab.")),
   widths = c(4.3, 2.2))

# ---------------------------------------------------------------------------
H1("5. Summary")
TB(df(Assumption = c("Region: Africa", "Productivity: low", "Feeding: flat pasture", "Manure nitrogen: other cattle column", "Soil climate: wet", "Manure methane climate: tropical", "One variant per storage system", "Species: cattle", "Twelve undeclared choices"),
      `What a user can do today` = c("Enter own values in the Parameters sheet", "Enter own values", "Enter Ca", "Enter fractions in the manure sheet", "Enter the three factors", "Enter MCF per row", "Enter coefficients per row", "Nothing", "Nothing; read the technical notes"),
      `To offer every option` = c("Region field drives defaults; full Annex tables in the master", "Productivity field", "Feeding dropdown", "Use the dairy cow column for dairy herds", "Wet or dry field", "Climate zone field and ten-zone table; per-system Bo", "Variant dropdown per row", "Species switch and buffalo defaults", "Declare each as a master row"),
      `Effort (days)` = c("3", "1", "0.5", "0.5", "0.5", "2 to 3", "2", "2", "0.5 each, about 6 in total")),
   widths = c(1.8, 1.8, 2.0, 0.9))
P("Doing everything in this table is roughly three to four weeks of development plus review. The order that gives the most value first: soil climate (half a day, large effect in dry countries), manure nitrogen column for dairy (half a day), the climate zone field for manure methane (two to three days), then region and productivity together (four days).")

H1("6. Where the assumptions live")
P("All eight declared assumptions are rows of one file, reference/defaults_master.csv, in a block called DEFAULT_BASIS. Every place that shows them (the Definitions tab of the app, the user guide, the methodology document, the Excel template, the AI translator instructions, and since 21 September 2026 the Word and Excel run reports) is generated from that file. Changing an assumption means editing that one row and rebuilding; an automatic check fails if any generated copy is out of date.")

print(doc, target = out)
cat("written:", out, "\n")
x <- paste(readLines(unz(out, "word/document.xml"), warn = FALSE), collapse = "")
cat("em dashes in document:", lengths(regmatches(x, gregexpr("—", x))), "\n")
