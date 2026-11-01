# The content hash of the tracked working tree, documentation/ and reports/
# left out (2026-11-01). scripts/audit.R writes it to runtime/.audit_stamp
# when every check passes; scripts/deploy.R skips the audit when the stamp
# matches the tree it is about to bundle, so a deploy no longer repeats the
# 7 to 8 minutes of tests that were run on the same code minutes before.
#
# A temporary index is read from HEAD and refreshed from the working tree
# (tracked files only), then written as a tree object: the hash depends on
# the file contents, not on whether they are committed, so an audit run
# before the commit stamps the same tree that the commit and the deploy
# gate (clean tree) see afterwards. documentation/ and reports/ are left
# out because they change without touching the app (beta-test files, the
# audit report itself) and are not in the deploy bundle.
audit_tree_hash <- function() {
  idx <- tempfile("audit_idx_")
  old <- Sys.getenv("GIT_INDEX_FILE", unset = NA)
  on.exit({
    if (is.na(old)) Sys.unsetenv("GIT_INDEX_FILE") else Sys.setenv(GIT_INDEX_FILE = old)
    unlink(idx)
  }, add = TRUE)
  Sys.setenv(GIT_INDEX_FILE = idx)
  r <- tryCatch({
    system2("git", c("read-tree", "HEAD"), stdout = FALSE, stderr = FALSE)
    system2("git", c("add", "-A", "--", ".", shQuote(":(exclude)documentation"), shQuote(":(exclude)reports")),
            stdout = FALSE, stderr = FALSE)
    system2("git", "write-tree", stdout = TRUE, stderr = FALSE)
  }, error = function(e) character(0))
  if (length(r) == 1L && grepl("^[0-9a-f]{40}$", r)) r else NA_character_
}

.AUDIT_STAMP_PATH <- "runtime/.audit_stamp"

audit_stamp_write <- function() {
  h <- audit_tree_hash()
  if (is.na(h)) return(invisible(FALSE))
  dir.create(dirname(.AUDIT_STAMP_PATH), showWarnings = FALSE, recursive = TRUE)
  writeLines(c(h, format(Sys.time(), "%Y-%m-%d %H:%M:%S")), .AUDIT_STAMP_PATH)
  invisible(TRUE)
}

# The time of the passing audit on this exact tree, or NULL.
audit_stamp_matches <- function(max_age_hours = 24) {
  if (!file.exists(.AUDIT_STAMP_PATH)) return(NULL)
  st <- tryCatch(readLines(.AUDIT_STAMP_PATH, warn = FALSE), error = function(e) character(0))
  if (length(st) < 2L) return(NULL)
  h <- audit_tree_hash()
  if (is.na(h) || !identical(st[1], h)) return(NULL)
  at <- tryCatch(as.POSIXct(st[2], format = "%Y-%m-%d %H:%M:%S"), error = function(e) NA)
  if (is.na(at) || difftime(Sys.time(), at, units = "hours") > max_age_hours) return(NULL)
  st[2]
}
