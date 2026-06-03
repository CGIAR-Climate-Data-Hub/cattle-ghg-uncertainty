# Generate a deliberately-messy dummy cattle dataset for stress-testing
# the in-app AI translator. The file mimics the kind of file a real
# inventory compiler might send: multiple sheets, French/English mix,
# typos in category names, wide-format years, unit-suffix-in-cell,
# decimal-comma vs decimal-point, missing values as "n/a" and "—",
# total rows mixed in with category rows, and a footnote inline.
#
# A good translator should be able to map this into the strict template
# after 3-5 clarifying questions.
#
# Run with:
#   Rscript _make_stress_test_data.R
# Output:
#   stress_test_cattle_data_burkina.xlsx  (repo root)

suppressMessages(library(writexl))

# Each value is a CHARACTER string so we can mix units, footnote markers,
# decimal commas, percentage suffixes, etc. — i.e. simulate the kind of
# raw data the translator actually receives.

cover <- data.frame(
  Field = c("Country / region",
            "Compiled by",
            "Reference year",
            "Espèce inventoriée",
            "IPCC version",
            "Climate zone",
            "Notes"),
  Value = c("Burkinafaso",                                       # typo, no space
            "Min. Env. & Climate; June 2024",
            "2024",
            "bovins",                                            # French
            "2019R",                                             # not "2019_refinement"
            "tropic",                                            # typo: tropical
            "Données population: enquête nationale 2020, projetée à 2024."),
  stringsAsFactors = FALSE
)

# Wide-format population table. Years as columns, sub-categories as
# rows. Mixed French/English names. A TOTAL row mixed in. A "Tx
# croissance" row that's NOT a population count but a growth rate, sat
# in the middle to confuse things. A footnote row at the bottom.

cattle_counts <- data.frame(
  Categorie = c("Vaches laitières (en lactation)",   # = dairy_cows
                "Vaches taries",                      # = other_cows (dry)
                "Génisses gestantes < 2 ans",         # = heifers (pregnant)
                "Autres génisses",                    # = heifers (other)
                "Taureaux de trait",                  # = oxen (castrated working bulls!)
                "Taureaux reproducteurs",             # = bulls (breeding)
                "Bouvillons en croissance",           # = growing steers (beef)
                "Veaux < 12 mois mâles",              # = calves_male
                "Veaux < 12 mois femelles",           # = calves_female
                "TOTAL CHEPTEL BOVIN",                # <-- total row, exclude
                "Tx croissance pop. annuel %",        # <-- growth rate, NOT count!
                "* Population projetée depuis 2020"), # <-- footnote
  `1990` = c("180 000","60 000","45 000","60 000","18 000","6 500","52 000","75 000","78 000","574 500","n/a",""),
  `2000` = c("210 000","68 000","51 000","66 000","20 000","7 200","61 000","84 000","87 000","654 200","1,4",""),
  `2010` = c("245 000","75 000","58 000","72 000","22 500","8 100","73 000","98 000","101 000","752 600","1,5",""),
  `2020` = c("280 000","82 000","65 500","79 000","24 800","8 800","85 000","110 000","114 000","849 100","1,2",""),
  `2024` = c("295 000","85 500","68 000","82 000","25 600","9 100","90 000","115 000","119 000","889 200","1,3 *",""),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# Weights + growth rates. UNITS ARE MIXED ON PURPOSE:
#  - BW for the dairy cows is in kg
#  - BW for the bulls is in lbs (translation challenge!)
#  - WG is in "kg/an" (kg per year) NOT kg/day — a common confusion
#  - MW has some entries as "—" and some as "n/a"

weights <- data.frame(
  subcat   = c("Vaches laitières",
               "Vaches taries",
               "Génisses gestantes",
               "Autres génisses",
               "Taureaux de trait",
               "Taureaux reproducteurs",
               "Bouvillons en croissance",
               "Veaux <12 m. mâles",
               "Veaux <12 m. femelles"),
  `BW (kg)` = c("385", "350", "295", "260", "770 lbs",   # lbs!!
                "510", "240", "95", "92"),
  MW        = c("440", "440", "440", "440", "550",
                "550", "—", "n/a", "n/a"),
  `WG (kg/an)` = c("12",   "0",    "65",   "75",   "0",
                   "0",    "180",  "55",   "50"),
  Notes = c("perte de poids saison sèche -10%", "", "", "", "",
            "", "BW estimé d'après marché", "", ""),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# Milk and feed. UNIT TRAPS:
#  - Milk is "L/jour" (litres per day), not kg/day — needs conversion
#    via density (~1.03)
#  - DE pct column uses decimal-COMMA ("60,5") instead of decimal-point
#  - Crude protein has a unit suffix in the cell ("12 %")
#  - Methane factor (Ym) is in absolute % ("6,5") for some, fraction
#    ("0.065") for others — inconsistent!

milk_feed <- data.frame(
  Cat = c("Vaches laitières",
          "Vaches taries",
          "Génisses gestantes",
          "Autres génisses",
          "Taureaux de trait",
          "Taureaux reproducteurs",
          "Bouvillons en croissance",
          "Veaux"),
  `Lait l/jour` = c("4,5", "0", "0", "0", "0", "0", "0", "0"),
  `Fat %`       = c("4,2", "—", "—", "—", "—", "—", "—", "—"),
  `DE pct`      = c("62,0", "55,0", "58,0", "57,5", "54,0", "55,0", "60,5", "63,5"),
  `Crude protein` = c("13 %", "9 %", "11 %", "10 %", "8 %", "9 %", "11 %", "14 %"),
  `Méthane factor` = c("6,5", "7,0", "6,8", "6,8", "7,2", "7,1", "0.065", "0.065"),  # inconsistent units
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# Manure allocation. A separate "Total" row that should be excluded.
# % signs in column header AND in cell values.

manure <- data.frame(
  `Systeme de gestion` = c("Pâturage / paddock",                   # = pasture
                            "Stockage solide (tas)",                # = solid storage
                            "Lagune",                               # = liquid/lagoon
                            "Épandage quotidien",                   # = daily spread
                            "Brûlage de combustible",               # = burnt for fuel
                            "TOTAL"),
  `% du total (annuel)` = c("65%", "20%", "5%", "8%", "2%", "100%"),
  `Climat`              = c("tropical sec", "tropical sec",
                              "tropical sec", "tropical sec",
                              "tropical sec", ""),
  Notes = c("dominant en saison de pluies",
            "période de soudure",
            "rares fermes intensives uniquement",
            "village péri-urbain",
            "rare, hors statistiques",
            "vérifier somme"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# Some completely unrelated noise sheet — the kind that ends up in real
# files. Should be IGNORED by the translator.

extras <- data.frame(
  Note = c("Pour le calcul de la consommation alimentaire utiliser DE pct = MJ ÉnDig / MJ ÉnBrute",
           "Source pour Ym: Niu 2018 (méta-analyse Afrique sub-saharienne)",
           "Bo = 0,10 m3 CH4/kg VS (valeur Afrique faible productivité 2006)",
           "Conversion lait L -> kg : * 1,032",
           "Conversion poids lbs -> kg : / 2,2046"),
  stringsAsFactors = FALSE
)

sheets <- list(
  `Inventory cover`   = cover,
  `Animal numbers`    = cattle_counts,
  `Weights & growth`  = weights,
  `Milk and feed`     = milk_feed,
  `Manure handling`   = manure,
  `Notes (à ignorer)` = extras
)

out_path <- "stress_test_cattle_data_burkina.xlsx"
write_xlsx(sheets, out_path)

cat(sprintf("Wrote %s  (%d KB, %d sheets)\n",
            out_path,
            round(file.info(out_path)$size / 1024),
            length(sheets)))
cat("Sheet names:\n")
for (s in names(sheets)) cat("  ", s, "\n")
