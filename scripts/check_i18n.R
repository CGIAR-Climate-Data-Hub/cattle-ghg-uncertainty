source("R/i18n.R")
ids <- names(.STRINGS)
files <- c("R/app_ui.R", "R/chat_ui.R", "R/auth_magic_link.R",
           "R/utils_contact.R", "R/app_server.R", "R/utils_qaqc.R")
used <- character(0)
for (f in files) {
  lines <- readLines(f, warn = FALSE)
  m <- regmatches(lines, gregexpr('\\bt\\("[a-zA-Z0-9_]+"\\)', lines, perl = TRUE))
  for (mm in m) if (length(mm)) {
    sub1 <- sub('t\\("', '', mm)
    sub2 <- sub('"\\)', '', sub1)
    used <- c(used, sub2)
  }
}
used <- unique(used)
missing <- setdiff(used, ids)
cat("Total unique t() IDs in UI:", length(used), "\n")
cat("Missing IDs:", length(missing), "\n")
if (length(missing)) cat(paste(missing, collapse = "\n"), "\n")
unused <- setdiff(ids, used)
cat("Defined-but-unused IDs:", length(unused), "\n")
