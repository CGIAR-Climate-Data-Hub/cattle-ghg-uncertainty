# =============================================================================
# annotate_ipcc_verdicts.R -- write the IPCC verification verdicts into the
# master
# =============================================================================
#
# Every numeric default in defaults/defaults_master.csv was read back against
# the IPCC source text, value by value, on 2026-09-11. This script records the
# outcome of that reading as two columns on the master itself, so the single
# authority also carries its own provenance and nobody has to hold a separate
# verification document alongside it.
#
# The verdicts are research results, not derivable from the data, so they are
# written here as an explicit table. Re-running is idempotent. A value that
# changes in the CSV does NOT invalidate its verdict automatically, which is
# why audit check F33 asserts that every numeric row still carries one and
# scripts/verify_defaults.R prints the verdict beside each cell.
#
# VERDICT VOCABULARY
#   CONFIRMED            read at the cited IPCC table or equation
#   INTERPRETED          a defensible reading of an IPCC category label rather
#                        than a quotation; recorded so the reading is visible
#   DEVIATION_DOCUMENTED differs from IPCC deliberately, reason on record
#   DEVIATION_OPEN       differs with no recorded reason; needs a decision
#   NOT_IPCC             non-IPCC source or project assumption; must never be
#                        presented to a user as an IPCC default
#   NO_IPCC_DEFAULT      IPCC publishes no default for this quantity at all
#   META                 not a value (bookkeeping fields)
#
# Usage (from project root):
#   Rscript scripts/annotate_ipcc_verdicts.R
# =============================================================================

if (basename(getwd()) == "scripts") setwd("..")

P <- "defaults/defaults_master.csv"
M <- utils::read.csv(P, stringsAsFactors = FALSE, na.strings = "<NA>",
                     colClasses = "character")

V <- list()
set <- function(object, key, field, verdict, source) {
  V[[length(V) + 1L]] <<- data.frame(
    object = object, key = key, field = field,
    ipcc_verdict = verdict, ipcc_source = source, stringsAsFactors = FALSE)
}
# key = "*" or field = "*" applies to every key / field of that object.

# --- Chapter 10 energy coefficients ----------------------------------------
T104 <- "2019R V4 Ch10 Table 10.4 (Updated), p.10.24"
T105 <- "2019R V4 Ch10 Table 10.5 (Updated), p.10.25"
T107 <- "2019R V4 Ch10 Table 10.7 (Updated), constants for Eq 10.13"
E106 <- "2019R V4 Ch10 Eq 10.6 note: C = 0.8 females, 1.0 castrates, 1.2 bulls (NRC 1996)"
T1012 <- "2019R V4 Ch10 Table 10.12 (Updated)"
T1016A <- "2019R V4 Ch10 Table 10.16A (Updated), Other regions low productivity"
T10A1 <- "2019R V4 Ch10 Table 10A.1 (New), Africa dairy row, p.10.104"
A1_LOW <- "2019R V4 Ch10 Table 10A.1 (New), Africa LOW PRODUCTIVITY SYSTEMS row, p.10.104"
BASIS_NOTE <- "Declared basis, adopted 2026-09-11: where Table 10A.1 offers an aggregate, a high-productivity and a low-productivity row, the tool takes LOW PRODUCTIVITY. That is the row whose Pasture/Range feeding situation matches Ca 0.17, and it is consistent with Bo 0.13, which Table 10.16A footnote 1 makes the Tier 1 default for other regions."
T10A2 <- "2019R V4 Ch10 Table 10A.2 (New), Africa Mature Females - grazing, Large Areas, p.10.108"
A2G <- "2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108"

# PARAM_CATALOGUE ipcc_default
cat_default <- list(
  BW = c("CONFIRMED", paste0(A1_LOW, ": Weight 270 kg. ", BASIS_NOTE)),
  MW = c("NO_IPCC_DEFAULT", "Neither Table 10A.1 nor Table 10A.2 has a mature-weight column; the cited table does not contain this value. Reviewer R7 #3 listed 300 kg MW as unfindable in IPCC"),
  WG = c("CONFIRMED", paste0(T10A1, ": weight gain 0 for every dairy row")),
  Milk = c("CONFIRMED", paste0(A1_LOW, ": milk yield 1.2 kg/day. ", BASIS_NOTE, " The previous 3.5 was the Africa AGGREGATE row, a population-weighted average of the high (5.8) and low (1.2) productivity systems per footnote 4. Changing it overturns the value agreed at review round 8 page 7, which was right for the aggregate row; the basis, not the reading, is what changed.")),
  Fat = c("CONFIRMED", paste0(A1_LOW, ": fat content 4.3%. Identical in the aggregate, high and low productivity rows, so the basis choice cannot move it. Agreed at review round 8 page 7 and unaffected.")),
  pct_pregnant = c("CONFIRMED", paste0(A1_LOW, ": 52% pregnant. ", BASIS_NOTE, " The previous 0.60 matched no row in either table.")),
  DE = c("CONFIRMED", paste0(A1_LOW, ": digestibility of feed 51%. ", BASIS_NOTE, " The previous 55% sat between the two tables and matched neither.")),
  Cfi = c("CONFIRMED", paste0(T104, ": lactating cows 0.386")),
  Ca = c("CONFIRMED", paste0(T105, ": Pasture 0.17")),
  C = c("CONFIRMED", E106),
  Cp = c("CONFIRMED", paste0(T107, ": Cattle and Buffalo 0.10")),
  hours = c("CONFIRMED", paste0(T10A1, ": work 0 hrs/day for every dairy row")),
  CP = c("CONFIRMED", paste0(A1_LOW, ": CP in diet 9.6%. ", BASIS_NOTE, " The previous 10.0% was the Table 10A.2 non-dairy grazing figure, which now sits on the non-dairy sub-categories instead.")),
  Ym = c("CONFIRMED", paste0(T1012, ": Low producing cows (<5000 kg/yr), DE <= 62, NDF > 38, Ym 6.5%. Footnote 4 restricts the dairy rows to LACTATING cows, which is exactly the dairy_cows sub-category, so 6.5 is right as the dairy default and wrong as the generic one: the same table gives 7.0 for non-dairy >75% forage and 4.0 for feedlot. See the Ym section of the provenance register")),
  Bo = c("CONFIRMED", paste0(T1016A, ": dairy and non-dairy cattle both 0.13")),
  ASH = c("DEVIATION_DOCUMENTED", "2006 V4 Ch10 Eq 10.24 note: 0.08 for cattle. The 2019 Refinement rewrote the same note around swine (0.06 for sows), so it does not supersede the cattle figure"),
  UE = c("CONFIRMED", "2019R V4 Ch10 Eq 10.24 note: typically 0.04 GE for most ruminants"),
  EF3_PRP = c("CONFIRMED", "2019R V4 Ch11 Table 11.1 (Updated), EF3PRP CPP wet climates: 0.006"),
  EF4 = c("CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.014"),
  EF5 = c("CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated): 0.011"),
  Frac_GASM_PRP = c("CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), FracGASM: 0.21"),
  Frac_LEACH_PRP = c("CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H) wet climates: 0.24, confirmed in the body text at Ch11 s11.2.2"),
  MilkPR = c("CONFIRMED", paste0(A1_LOW, ": protein content of milk 3.6%. Identical in all three Africa rows of Table 10A.1 and in Table 10A.2, and the tool's own documented route %MilkPR = 1.9 + 0.4 x %Fat gives 3.62 at Fat 4.3. The previous 3.3 was what that formula returns for Fat 3.5, the value Fat held before review round 8 corrected it.")),
  Tw = c("NOT_IPCC", "Winter temperature is country-specific; IPCC publishes no default. Project assumption"))
for (k in names(cat_default))
  set("PARAM_CATALOGUE", k, "ipcc_default", cat_default[[k]][1], cat_default[[k]][2])

# PARAM_CATALOGUE uncertainty: Tier 1 literature, not IPCC, with one exception.
set("PARAM_CATALOGUE", "*", "suggested_uncertainty_pct", "NOT_IPCC",
    "Penman et al. (2000) IPCC Good Practice Guidance and Monni et al. (2007). Disclosed as a non-IPCC suggestion in the user guide")
set("PARAM_CATALOGUE", "Bo", "suggested_uncertainty_pct", "CONFIRMED",
    paste0(T1016A, " footer: uncertainty +/- 15%"))
# Ym's uncertainty IS published by IPCC, so the blanket Penman/Monni
# attribution above was wrong for this row. Table 10.12 footnote 3 gives it
# outright. The internal 2026-06-15 change from 8 to 20 cited "2019R Tier 2
# guidance" without a table; this is the table.
set("PARAM_CATALOGUE", "Ym", "suggested_uncertainty_pct", "CONFIRMED",
    paste0(T1012, " footnote 3: 'Uncertainty values are +/- 20% based on published standard deviations from Niu et al. (2018) and data compilations for non dairy cattle as described in Annex 10B.2'"))

# PARAM_CATALOGUE asymmetric bounds, all five Chapter 11 parameters.
bnd <- function(k, lo_v, lo_s, hi_v, hi_s) {
  set("PARAM_CATALOGUE", k, "suggested_lower_bound", lo_v, lo_s)
  set("PARAM_CATALOGUE", k, "suggested_upper_bound", hi_v, hi_s)
}
FLOOR <- "IPCC gives 0.000 as the lower bound. The tool uses a small positive floor because a zero lower bound is degenerate for the bounded distributions; documented deviation"
bnd("EF3_PRP", "DEVIATION_DOCUMENTED", FLOOR,
    "CONFIRMED", "2019R V4 Ch11 Table 11.1 (Updated): upper 0.027")
bnd("EF4", "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.011",
    "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), wet climate: 0.017")
bnd("EF5", "DEVIATION_DOCUMENTED", FLOOR,
    "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated): upper 0.020")
bnd("Frac_GASM_PRP", "DEVIATION_DOCUMENTED", FLOOR,
    "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), FracGASM: upper 0.31")
bnd("Frac_LEACH_PRP", "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H): lower 0.01",
    "CONFIRMED", "2019R V4 Ch11 Table 11.3 (Updated), FracLEACH-(H): upper 0.73")

# --- MMS_DEFAULTS ----------------------------------------------------------
# MCF. The 2006 table is per-degree-C; the tool's three bands read the SAME
# three columns of it for every temperature-dependent system: boreal = the
# "<= 10" column, temperate = the "19" column, tropical = the ">= 28" column.
# That convention was undocumented until this pass; it is consistent across
# liquid_slurry, deep_bedding and lagoon, which is what makes it a convention
# rather than three coincidences.
T1017_06 <- "2006 V4 Ch10 Table 10.17, MCF by average annual temperature"
T1017_19 <- "2019R V4 Ch10 Table 10.17 (Updated)"
BANDS <- "boreal = the '<= 10 C' column, temperate = the '19 C' column, tropical = the '>= 28 C' column"

mcf <- list(
  pasture = c("CONFIRMED", paste0(T1017_06, ", Pasture/Range/Paddock: 1.0 / 1.5 / 2.0")),
  daily_spread = c("CONFIRMED", paste0(T1017_06, ", Daily spread: 0.1 / 0.5 / 1.0")),
  solid_storage = c("CONFIRMED", paste0(T1017_06, " and ", T1017_19, ", Solid storage: 2.0 / 4.0 / 5.0")),
  solid_storage_covered = c("CONFIRMED", paste0(T1017_19, ", Solid storage - Covered/compacted: 2.00 / 4.00 / 5.00")),
  dry_lot = c("CONFIRMED", paste0(T1017_06, " and ", T1017_19, ", Dry lot: 1.0 / 1.5 / 2.0")),
  deep_bedding = c("CONFIRMED", paste0(T1017_06, ", Cattle and Swine deep bedding > 1 month: 17 / 39 / 80. ", BANDS)),
  liquid_slurry = c("CONFIRMED", paste0(T1017_06, ", Liquid/Slurry with natural crust cover: 10 / 24 / 50. ", BANDS)),
  lagoon = c("CONFIRMED", paste0(T1017_06, ", Uncovered anaerobic lagoon: 66 / 77 / 80. ", BANDS)),
  composting = c("CONFIRMED", paste0(T1017_06, ", Composting - Static pile: 0.5 / 0.5 / 0.5, marked 'Not temperature dependant'. This was briefly recorded as a DEVIATION_OPEN on the grounds that 2019R gives Static pile (Forced aeration) 1.00 / 2.00 / 2.50 and 0.5 is the 2019R In-vessel figure. That reading was WRONG: the tool's declared MCF basis is the 2006 table, where static pile IS 0.5, and 10 of the 12 systems read their MCF from it. The variant is consistent across all three coefficient families; only the edition differs between families, which is the documented tool-wide convention. A 2019R user does get 0.5 rather than 1.00 to 2.50, and that is part of the same documented MCF basis, alongside pasture")),
  anaerobic_digester = c("CONFIRMED", "2019R V4 Ch10 Table 10A.11, high quality biogas digester with open storage: 3.55 cold / 4.38 temperate / 4.59 warm. The 2006 table gives only a 0 to 100% range requiring Formula 1"),
  aerobic_treatment = c("CONFIRMED", paste0(T1017_06, ", Aerobic treatment: 0 / 0 / 0")),
  burned_for_fuel = c("CONFIRMED", paste0(T1017_06, ", Burned for fuel: 10 / 10 / 10")))
for (k in names(mcf)) for (f in c("mcf_tropical", "mcf_temperate", "mcf_boreal"))
  set("MMS_DEFAULTS", k, f, mcf[[k]][1], mcf[[k]][2])
# The dry-tropical column mirrors the tropical one on every row.
set("MMS_DEFAULTS", "*", "mcf_tropical_dry", "DEVIATION_DOCUMENTED",
    paste0("Mirrors mcf_tropical on every system, so it carries the same value read from ", T1017_06, " (or, for the two systems that table does not cover, their stated source). The 2019 Refinement splits ten climate zones including Tropical Dry, which the tool's four-band model does not resolve; the tropical value is used for both"))

ef3 <- list(
  pasture = c("DEVIATION_DOCUMENTED", "0.02 is the Chapter 11 EF3PRP for cattle on pasture, not a Table 10.21 manure-management factor. Table 10.21 routes pasture N to Chapter 11 explicitly. Carried on this row so the pasture pathway resolves; documented"),
  daily_spread = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Daily spread: 0"),
  solid_storage = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Solid storage: 0.010"),
  solid_storage_covered = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Solid storage - Covered/compacted: 0.01"),
  dry_lot = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Dry lot: 0.02"),
  deep_bedding = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Cattle and swine deep bedding, No mixing: 0.01"),
  liquid_slurry = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Liquid/Slurry With natural crust cover: 0.005"),
  composting = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Composting - Static Pile (Forced aeration): 0.010"),
  lagoon = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Uncovered anaerobic lagoon: 0"),
  anaerobic_digester = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Anaerobic digester: 0.0006"),
  aerobic_treatment = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated), Aerobic treatment, forced aeration: 0.005"),
  burned_for_fuel = c("CONFIRMED", "2019R V4 Ch10 Table 10.21 (Updated): reported under Fuel Combustion, not as manure management"))
for (k in names(ef3)) set("MMS_DEFAULTS", k, "ef3", ef3[[k]][1], ef3[[k]][2])

set("MMS_DEFAULTS", "*", "label", "META", "Display string, not a value")
set("MMS_DEFAULTS", "*", "versions", "META", "Which guideline editions offer this system")
set("MMS_DEFAULTS", "*", "ipcc_variant", "META", "Records which IPCC sub-type the row models")

# --- MMS_FRAC_DEFAULTS_2019, 2019R Table 10.22 "Other Cattle" column --------
T1022 <- "2019R V4 Ch10 Table 10.22 (Updated), Other Cattle column, pp.10.97-98"
frac <- list(
  lagoon               = "Uncovered anaerobic lagoon: 0.35 (0.20-0.80), leach 0",
  liquid_slurry        = "Liquid/Slurry With natural crust cover: 0.30 (0.09-0.36), leach 0",
  solid_storage        = "Solid storage plain: 0.45 (0.10-0.65), leach 0.02",
  solid_storage_covered= "Solid storage Covered/compacted: 0.22 (0.03-0.26), leach 0",
  dry_lot              = "Dry lot: 0.30 (0.20-0.50), leach 0.035 (0-0.07) per footnote 4",
  deep_bedding         = "Cattle and swine deep bedding: 0.25 (0.10-0.30), leach 0.035",
  daily_spread         = "Daily spread: 0.07 (0.05-0.60), leach 0",
  composting           = "Composting Static Pile: 0.65 (0.14-0.70), leach 0.06",
  aerobic_treatment    = "Aerobic treatment Forced aeration: 0.85 (0.27-1), leach 0")
for (k in names(frac)) for (f in c("frac_gas", "frac_gas_low", "frac_gas_high"))
  set("MMS_FRAC_DEFAULTS_2019", k, f, "CONFIRMED", paste0(T1022, ". ", frac[[k]]))
for (k in names(frac)) set("MMS_FRAC_DEFAULTS_2019", k, "frac_leach", "CONFIRMED",
                           paste0(T1022, ". ", frac[[k]]))
# Systems whose leaching fraction IPCC gives as a flat 0: the 0/0 bounds are
# the only defensible pair, so they are confirmed rather than tool-assigned.
for (k in c("daily_spread", "solid_storage_covered", "liquid_slurry",
            "aerobic_treatment", "lagoon"))
  for (f in c("frac_leach_low", "frac_leach_high"))
    set("MMS_FRAC_DEFAULTS_2019", k, f, "CONFIRMED",
        paste0(T1022, " gives leaching 0 for this system, so the bounds are 0 as well. ", frac[[k]]))
# Leach BOUNDS: IPCC publishes a range only for dry lot.
for (k in c("dry_lot"))
  for (f in c("frac_leach_low", "frac_leach_high"))
    set("MMS_FRAC_DEFAULTS_2019", k, f, "CONFIRMED",
        paste0(T1022, " footnote 4: uncertainty range 0 to 0.07"))
set("MMS_FRAC_DEFAULTS_2019", "deep_bedding", "frac_leach_low", "DEVIATION_DOCUMENTED",
    "IPCC gives leach 0.035 as a point value for deep bedding with no range. The tool borrows the dry-lot range (footnote 4), which is the same central value")
set("MMS_FRAC_DEFAULTS_2019", "deep_bedding", "frac_leach_high", "DEVIATION_DOCUMENTED",
    "IPCC gives leach 0.035 as a point value for deep bedding with no range. The tool borrows the dry-lot range (footnote 4), which is the same central value")
for (k in c("solid_storage", "composting"))
  for (f in c("frac_leach_low", "frac_leach_high"))
    set("MMS_FRAC_DEFAULTS_2019", k, f, "DEVIATION_DOCUMENTED",
        "IPCC publishes the leaching fraction for this system as a point value with no range. The tool applies a +/- 50% band so the parameter can be sampled")
# Anaerobic digester: IPCC gives a bare range, no central.
for (f in c("frac_gas", "frac_gas_low", "frac_gas_high"))
  set("MMS_FRAC_DEFAULTS_2019", "anaerobic_digester", f, "CONFIRMED",
      paste0(T1022, " gives Anaerobic digester as a bare range 0.05 to 0.50 with no central, and footnote 3 tells you which end applies: 'The lower range of 0.05 losses is valid for digestate with a high dry matter content AND A COVER', and 'It is advised to use the liquid slurry without cover for uncovered digestate'. This row declares OPEN STORAGE, and its MCF comes from the Table 10A.11 open-storage row, so the covered figure was the wrong end of the range. Following footnote 3, the value is the Liquid/Slurry without natural crust cover, Other Cattle figure: 0.48 (0.15-0.60). It was previously 0.05 (0.02-0.08), roughly ten times too low and with a sampled range sitting entirely below IPCC's floor"))
set("MMS_FRAC_DEFAULTS_2019", "anaerobic_digester", "frac_leach", "CONFIRMED",
    paste0(T1022, ", Anaerobic digester: leach 0"))
for (f in c("frac_leach_low", "frac_leach_high"))
  set("MMS_FRAC_DEFAULTS_2019", "anaerobic_digester", f, "CONFIRMED",
      paste0(T1022, ", Anaerobic digester: leach 0"))
for (k in c("pasture", "burned_for_fuel")) for (f in c("frac_gas", "frac_gas_low",
      "frac_gas_high", "frac_leach", "frac_leach_low", "frac_leach_high"))
  set("MMS_FRAC_DEFAULTS_2019", k, f, "CONFIRMED",
      if (k == "pasture")
        "Not in Table 10.22. Pasture volatilisation and leaching are the Chapter 11 Frac_*_PRP pathway, so zero here is correct and avoids double counting"
      else "2019R V4 Ch10 Table 10.22 (Updated): Burned for fuel or as waste is NA; the N is reported under Fuel Combustion")

# --- per-sub-category ------------------------------------------------------
CFI_SRC <- paste0(T104, ": 0.386 lactating cows, 0.370 bulls (intact males), 0.322 all non-lactating cows, steers, heifers and calves")
OXEN <- "2019R V4 Ch10 Table 10A.2 footnote 8: 'Draft bullocks were all assumed to be castrates and CFi values were adjusted accordingly'. Castrates are steers, so 0.322"
INTACT <- "IPCC's 0.370 row is labelled 'bulls', glossed 'intact males'. The tool reads 'bulls' as mature breeding males and assigns the steers/heifers/calves value to growing and immature males. Defensible, but a reading rather than a quotation"
for (k in c("dairy_cows", "other_cows", "heifers", "calves_female", "bulls"))
  set("CFI_BY_SUBCAT", k, "value", "CONFIRMED", CFI_SRC)
set("CFI_BY_SUBCAT", "oxen", "value", "CONFIRMED", paste0(CFI_SRC, ". ", OXEN))
for (k in c("growing_males", "calves_male", "feedlot_cattle"))
  set("CFI_BY_SUBCAT", k, "value", "INTERPRETED", paste0(CFI_SRC, ". ", INTACT))

for (k in c("dairy_cows", "other_cows", "heifers", "calves_female", "bulls", "oxen"))
  set("C_GROWTH_BY_SUBCAT", k, "value", "CONFIRMED", E106)
for (k in c("growing_males", "calves_male", "feedlot_cattle"))
  set("C_GROWTH_BY_SUBCAT", k, "value", "INTERPRETED",
      paste0(E106, ". The tool assigns the castrate value 1.0 to growing and feedlot males, the same reading it applies to Cfi"))

A2 <- "2019R V4 Ch10 Table 10A.2 (New), Africa block, p.10.108"
lw <- list(
  dairy_cows     = c("CONFIRMED", paste0(A1_LOW, ": Weight 270 kg. ", BASIS_NOTE, " Previously 275, the Table 10A.2 non-dairy grazing weight, so the dairy sub-category had been carrying a non-dairy figure.")),
  other_cows     = c("CONFIRMED", paste0(A2, ": Mature Females - grazing, Large Areas 275 kg")),
  bulls          = c("DEVIATION_OPEN", paste0(A2, ": Mature Males 540 kg, Bulls - Grazing 340 kg. The 350 used here matches neither")),
  oxen           = c("DEVIATION_OPEN", paste0(A2, ": Draft Bullocks 340 kg. The 300 used here is 12% lower")),
  heifers        = c("DEVIATION_OPEN", paste0(A2, ": Growing/Replacement 204 kg. The 200 used here is a rounding of it, not a transcription")),
  growing_males  = c("DEVIATION_OPEN", paste0(A2, ": Growing/Replacement 204 kg. The 200 used here is a rounding of it, not a transcription")),
  calves_female  = c("DEVIATION_OPEN", paste0(A2, ": Calves on forage 82 kg. The 60 used here is 27% lower than any IPCC calf row")),
  calves_male    = c("DEVIATION_OPEN", paste0(A2, ": Calves on forage 82 kg. The 60 used here is 27% lower than any IPCC calf row")),
  feedlot_cattle = c("DEVIATION_OPEN", paste0(A2, " has no Africa feedlot row. The two published feedlot weights are North America 500 kg and Latin America 460 kg. The 250 used here is half the lower of them")))
for (k in names(lw)) set("LW_BY_SUBCAT", k, "value", lw[[k]][1], lw[[k]][2])

set("MW_BY_SUBCAT", "*", "value", "NO_IPCC_DEFAULT",
    "Mature weight appears in Eq 10.6 as an input but IPCC publishes no default for it: neither Table 10A.1 nor Table 10A.2 has a mature-weight column. Reviewer R7 #3 raised exactly this. These are project assumptions and must not be shown as IPCC defaults")

wg <- list(
  dairy_cows     = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1: weight gain 0 for every dairy row"),
  other_cows     = c("CONFIRMED", paste0(A2, ": mature female rows carry no weight gain")),
  bulls          = c("CONFIRMED", paste0(A2, ": mature male rows carry no weight gain")),
  oxen           = c("CONFIRMED", paste0(A2, ": Draft Bullocks carry no weight gain")),
  heifers        = c("DEVIATION_OPEN", paste0(A2, ": Growing/Replacement 0.24 kg/day. The 0.25 used here is a rounding of it")),
  growing_males  = c("DEVIATION_OPEN", paste0(A2, ": Growing/Replacement 0.24 kg/day. The 0.20 used here is 17% lower and matches no Africa row")),
  calves_female  = c("DEVIATION_OPEN", paste0(A2, ": Calves on forage 0.33 kg/day. The 0.30 used here is a rounding of it")),
  calves_male    = c("DEVIATION_OPEN", paste0(A2, ": Calves on forage 0.33 kg/day. The 0.30 used here is a rounding of it")),
  feedlot_cattle = c("DEVIATION_OPEN", "Table 10A.2 has no Africa feedlot row. Published feedlot gains are North America 1.4 and Latin America 0.90 kg/day. The 1.0 used here falls between them"))
for (k in names(wg)) set("WG_BY_SUBCAT", k, "value", wg[[k]][1], wg[[k]][2])

# --- Ym, and the two diet parameters that move with it ---------------------
FN4 <- "footnote 4: 'Ym cited for dairy cattle are for lactating dairy cows. For dairy cattle during their dry phase, in high and medium production systems, the non-dairy high quality forage value (6.3) should be selected and for low production systems with >75% low quality forage the value of (7.0) should be selected'"
T1012_06 <- "2006 V4 Ch10 Table 10.12, p.10.30"
A2_YM <- "Annex 10A.2 confirms it independently: every non-dairy row of the Africa block carries 7.0, calves on forage included"
set("YM_BY_SUBCAT", "dairy_cows", "ym_2019_refinement", "CONFIRMED",
    paste0(T1012, ": Low producing cows (<5000 kg/yr), DE <= 62, NDF > 38, Ym 6.5%. The dairy_cows sub-category is mature LACTATING females, which is exactly the population ", FN4, " restricts these rows to"))
for (k in c("other_cows", "bulls", "oxen", "heifers", "growing_males",
            "calves_female", "calves_male"))
  set("YM_BY_SUBCAT", k, "ym_2019_refinement", "CONFIRMED",
      paste0(T1012, ": Non dairy and multi-purpose, >75% forage, DE <= 62, Ym 7.0%. ", A2_YM,
             ". For other_cows, which includes dry dairy cows, ", FN4, " sends them to the same 7.0"))
set("YM_BY_SUBCAT", "feedlot_cattle", "ym_2019_refinement", "CONFIRMED",
    paste0(T1012, ": Feedlot (all other grains, 0-15% forage), DE >= 72, Ym 4.0%. Annex 10A.2 Latin America Feedlot cattle confirms it at DE 74. North America feedlot sits at DE 75 with Ym 3.0, the steam-flaked corn row"))
for (k in c("dairy_cows", "other_cows", "bulls", "oxen", "heifers",
            "growing_males", "calves_female", "calves_male"))
  set("YM_BY_SUBCAT", k, "ym_2006", "CONFIRMED",
      paste0(T1012_06, ": the 2006 table gives 6.5% for Dairy Cows and their young, for Other Cattle fed low quality crop residues, and for Other Cattle grazing alike. It draws no distinction below feedlot"))
set("YM_BY_SUBCAT", "feedlot_cattle", "ym_2006", "CONFIRMED",
    paste0(T1012_06, ": 'Feedlot fed Cattle' 3.0%, footnote a 'when fed diets contain 90 percent or more concentrates'"))

# Diet now follows the declared low-productivity / grazing basis: the dairy
# row from Table 10A.1 Africa low productivity, every non-dairy row from the
# matching Table 10A.2 Africa grazing row. Previously all nine carried a
# uniform DE of 55 and CP of 10, neither of which matched any single row.
A2_DIET <- list(
  other_cows    = c("58", "10.0", "Mature Females - grazing, Large Areas"),
  bulls         = c("58", "10.0", "Bulls - Grazing"),
  oxen          = c("58", "10.0", "Draft Bullocks"),
  heifers       = c("59", "10.4", "Growing/Replacement"),
  growing_males = c("59", "10.4", "Growing/Replacement"),
  calves_female = c("59", "10.3", "Calves on forage"),
  calves_male   = c("59", "10.3", "Calves on forage"))
set("DE_BY_SUBCAT", "dairy_cows", "value", "CONFIRMED",
    paste0(A1_LOW, ": digestibility of feed 51%. ", BASIS_NOTE))
set("CP_BY_SUBCAT", "dairy_cows", "value", "CONFIRMED",
    paste0(A1_LOW, ": CP in diet 9.6%. ", BASIS_NOTE))
for (k in names(A2_DIET)) {
  d <- A2_DIET[[k]]
  set("DE_BY_SUBCAT", k, "value", "CONFIRMED",
      paste0(A2G, ", ", d[3], ": digestibility of feed ", d[1], "%"))
  set("CP_BY_SUBCAT", k, "value", "CONFIRMED",
      paste0(A2G, ", ", d[3], ": CP in diet ", d[2], "%"))
}
set("DE_BY_SUBCAT", "feedlot_cattle", "value", "CONFIRMED",
    "2019R V4 Ch10 Table 10A.2 (New), Latin America Feedlot cattle: digestibility of feed 74%. Required by Table 10.12, whose feedlot Ym of 4.0 is conditional on DE >= 72")
set("CP_BY_SUBCAT", "feedlot_cattle", "value", "CONFIRMED",
    "2019R V4 Ch10 Table 10A.2 (New), Latin America and North America Feedlot cattle both give CP in diet 14.0%")

set("PCT_PREGNANT_BY_SUBCAT", "dairy_cows", "value", "CONFIRMED",
    paste0(A1_LOW, ": 52% pregnant. ", BASIS_NOTE, " The previous 0.85 was the Eastern Europe dairy rate, which sat on a different continent from every other default in the tool."))
set("PCT_PREGNANT_BY_SUBCAT", "other_cows", "value", "CONFIRMED",
    paste0(A2G, ", Mature Females - grazing, Large Areas: 54% pregnant. The previous 0.85 was the Eastern Europe dairy rate."))
set("PCT_PREGNANT_BY_SUBCAT", "heifers", "value", "NO_IPCC_DEFAULT",
    "Table 10A.2 leaves the Pregnant column blank for Growing/Replacement, so IPCC publishes no figure for replacement heifers. 0.50 is a project assumption and must not be presented as an IPCC default.")

set("FEEDING_SITUATION_CA", "stall_fed", "value", "CONFIRMED", paste0(T105, ": Stall 0"))
set("FEEDING_SITUATION_CA", "pasture_flat", "value", "CONFIRMED", paste0(T105, ": Pasture 0.17"))
set("FEEDING_SITUATION_CA", "pasture_hilly", "value", "CONFIRMED", paste0(T105, ": Grazing large areas 0.36"))

reg <- list(
  africa   = c("CONFIRMED", paste0(A2, ": Mature Females - grazing, Large Areas 275 kg. Note Table 10A.1 gives Africa dairy 260 kg")),
  asia     = c("DEVIATION_OPEN", "Table 10A.1 Asia dairy 386 kg (low productivity 355); Table 10A.2 Asia Mature Females 376, grazing 305. The 350 used here matches no Asia row; the only published 350 is Indian subcontinent high-productivity dairy"),
  europe   = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1: Western Europe dairy 600 kg"),
  americas = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1: Latin America low productivity dairy 500 kg. North America dairy is 650 and Latin America aggregate 508, so this is the low-productivity reading used elsewhere in the tool"),
  oceania  = c("DEVIATION_OPEN", "Table 10A.1 Oceania dairy 488 kg; Table 10A.2 Oceania Mature Females 416, Mature Males 467. The 500 used here appears in no Oceania row"),
  global   = c("NO_IPCC_DEFAULT", "Neither annex table has a global row. The 400 used here is a project benchmark"))
for (k in names(reg)) {
  set("IPCC_DEFAULTS_BY_REGION", k, "default_val", reg[[k]][1], reg[[k]][2])
  set("IPCC_DEFAULTS_BY_REGION", k, "parameter", "META", "Names the parameter the benchmark applies to")
}

# The dairy column. Table 10A.1, low-productivity row where that table
# splits, matching the declared basis. It exists because the QA benchmark
# message branched on cattle_type while comparing every herd against the
# same non-dairy number, which is review round 7 item 3 unresolved: the tab
# cited a table it was not reading.
reg_dairy <- list(
  africa   = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1 (New), Africa Low productivity systems: 270 kg (aggregate 260, high productivity 250)"),
  asia     = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1 (New), Asia Low productivity systems: 355 kg (aggregate 386, high productivity 485)"),
  europe   = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1 (New), Western Europe: 600 kg. Eastern Europe is 550; no productivity split is published for either"),
  americas = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1 (New), Latin America Low productivity systems: 500 kg (aggregate 508, high 520). North America is 650"),
  oceania  = c("CONFIRMED", "2019R V4 Ch10 Table 10A.1 (New), Oceania: 488 kg; no productivity split published"),
  global   = c("NO_IPCC_DEFAULT", "Table 10A.1 has no global row. 400 kg is a project benchmark carried over from the non-dairy column"))
for (k in names(reg_dairy))
  set("IPCC_DEFAULTS_BY_REGION", k, "default_val_dairy",
      reg_dairy[[k]][1], reg_dairy[[k]][2])

gwp <- list(AR4.CH4 = "25", AR4.N2O = "298", AR5.CH4 = "28", AR5.N2O = "265",
            AR6.CH4 = "27 (non-fossil methane, 100-year)", AR6.N2O = "273")
for (k in names(gwp))
  set("GWP_VALUES", k, "value", "CONFIRMED",
      paste0("IPCC ", sub("[.].*", "", k), " WGI, 100-year GWP: ", gwp[[k]],
             ". Confirmed against the published Assessment Report value; the AR volumes are not in reference/, so this is not a local-source read"))

VT <- do.call(rbind, V)

# --- apply -----------------------------------------------------------------
M$ipcc_verdict <- NA_character_
M$ipcc_source  <- NA_character_
# Specific rows must win over wildcards, so apply wildcards first.
spec <- (VT$key != "*") + (VT$field != "*")
for (i in order(spec)) {
  r <- VT[i, ]
  hit <- M$object == r$object &
         (r$key   == "*" | M$key   == r$key) &
         (r$field == "*" | M$field == r$field)
  M$ipcc_verdict[hit] <- r$ipcc_verdict
  M$ipcc_source[hit]  <- r$ipcc_source
}

isnum <- !is.na(suppressWarnings(as.numeric(M$value)))
gap <- isnum & is.na(M$ipcc_verdict)
if (any(gap)) {
  cat("UNVERDICTED numeric rows:\n")
  print(M[gap, c("object", "key", "field", "value")])
  stop("every numeric row must carry a verdict", call. = FALSE)
}
M$ipcc_verdict[is.na(M$ipcc_verdict)] <- "META"
M$ipcc_source[is.na(M$ipcc_source)]   <- "Descriptive field, not a shipped numeric default"

# row_order back to integer before writing. Reading with colClasses="character"
# makes write.csv quote it, while export_defaults_master.R writes it unquoted,
# so the two scripts would otherwise flip the quoting of all 573 lines on
# alternate runs and every diff would look like a full-file rewrite.
M$row_order <- as.integer(M$row_order)
utils::write.csv(M, P, row.names = FALSE, na = "<NA>")

cat(sprintf("annotated %d rows in %s\n", nrow(M), P))
tab <- table(M$ipcc_verdict[isnum])
cat(sprintf("  %d numeric values carry a verdict:\n", sum(isnum)))
for (k in names(sort(tab, decreasing = TRUE)))
  cat(sprintf("    %-22s %d\n", k, tab[[k]]))
