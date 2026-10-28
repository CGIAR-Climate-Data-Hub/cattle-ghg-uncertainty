# Usage: Rscript scripts/test_translator_retry.R   (no API call, about 30 s)
# The background API call retries a rate limit (429), an overload (529), an
# "error" event inside a 200 stream and a refused connection, while nothing
# has reached the user; it does not retry a 400; Stop during the wait ends
# it. Against a local stub that counts the attempts per path.
suppressMessages({library(shiny); for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)})
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) stop(msg) }
Sys.setenv(ANTHROPIC_API_KEY = "sk-stub", APP_RUNTIME_DIR = tempfile("rt"))
.ANTHROPIC_ASYNC_RETRY_DELAYS <- c(0.5, 0.5, 0.5, 0.5)
stub <- tempfile(fileext = ".R")
writeLines(c(
  'library(httpuv); port <- as.integer(commandArgs(TRUE)[1]); hits <- new.env()',
  'sse <- function(type, data) paste0("event: ", type, "\ndata: ", jsonlite::toJSON(data, auto_unbox = TRUE), "\n\n")',
  'ok_body <- paste0(sse("message_start", list(type = "message_start", message = list(usage = list(input_tokens = 5, output_tokens = 0)))),',
  '  sse("content_block_start", list(type = "content_block_start", index = 0, content_block = list(type = "text", text = ""))),',
  '  sse("content_block_delta", list(type = "content_block_delta", index = 0, delta = list(type = "text_delta", text = "hello"))),',
  '  sse("message_delta", list(type = "message_delta", delta = list(stop_reason = "end_turn"), usage = list(output_tokens = 1))),',
  '  sse("message_stop", list(type = "message_stop")))',
  'app <- list(call = function(req) { p <- req$PATH_INFO; n <- (hits[[p]] %||% 0) + 1; assign(p, n, envir = hits)',
  '  if (p == "/count") return(list(status = 200L, headers = list(`Content-Type` = "application/json"), body = jsonlite::toJSON(as.list(hits), auto_unbox = TRUE)))',
  '  ok <- list(status = 200L, headers = list(`Content-Type` = "text/event-stream"), body = ok_body)',
  '  if (p == "/s529" && n <= 2) return(list(status = 529L, headers = list(`Content-Type` = "application/json"), body = "{\\"error\\":{\\"type\\":\\"overloaded_error\\",\\"message\\":\\"Overloaded\\"}}"))',
  '  if (p == "/s429" && n <= 1) return(list(status = 429L, headers = list(`Content-Type` = "application/json", `retry-after` = "1"), body = "{\\"error\\":{\\"message\\":\\"rate\\"}}"))',
  '  if (p == "/serr" && n <= 1) return(list(status = 200L, headers = list(`Content-Type` = "text/event-stream"), body = sse("error", list(type = "error", error = list(type = "overloaded_error", message = "Overloaded")))))',
  '  if (p == "/s400") return(list(status = 400L, headers = list(`Content-Type` = "application/json"), body = "{\\"error\\":{\\"message\\":\\"bad request\\"}}"))',
  '  if (p == "/salways") return(list(status = 529L, headers = list(`Content-Type` = "application/json"), body = "{}"))',
  '  ok })',
  '`%||%` <- function(a, b) if (is.null(a)) b else a',
  's <- startServer("127.0.0.1", port, app); while (TRUE) service(50)'), stub)
port <- 18790L; port_late <- 18791L
srv <- processx::process$new(file.path(R.home("bin"), "Rscript"), c(stub, port), stdout = "|", stderr = "|")
Sys.sleep(3)
call <- function(path, p = port, should_stop = function() FALSE) {
  assign(".ANTHROPIC_ENDPOINT", sprintf("http://127.0.0.1:%d%s", p, path), envir = globalenv())
  res <- NULL; retries <- 0L
  anthropic_chat_stream_async(list(list(role = "user", content = "hi")), model = "claude-sonnet-4-6",
    should_stop = should_stop, on_result = function(r) res <<- r,
    on_retry = function(a, d, why) retries <<- retries + 1L)
  t0 <- Sys.time(); while (is.null(res) && difftime(Sys.time(), t0, units = "secs") < 30) later::run_now(0.05)
  list(res = res, retries = retries)
}
r <- call("/s529"); ok(is.null(r$res$error) && identical(r$res$reply, "hello") && r$retries == 2L, "529 overloaded twice: two retries, then the reply")
r <- call("/s429"); ok(is.null(r$res$error) && identical(r$res$reply, "hello") && r$retries == 1L, "429 with Retry-After: one retry, then the reply")
r <- call("/serr"); ok(is.null(r$res$error) && identical(r$res$reply, "hello") && r$retries == 1L, "overloaded_error event inside a 200 stream: one retry, then the reply")
r <- call("/s400"); ok(!is.null(r$res$error) && r$retries == 0L, "400: no retry, the error is reported")
r <- call("/salways"); ok(!is.null(r$res$error) && grepl("overloaded", r$res$error, ignore.case = TRUE) && r$retries == 4L, "529 every time: four retries, then the overload message")
late <- NULL
later::later(function() late <<- processx::process$new(file.path(R.home("bin"), "Rscript"), c(stub, port_late), stdout = "|", stderr = "|"), 3)
assign(".ANTHROPIC_ASYNC_RETRY_DELAYS", c(4, 4, 4, 4), envir = globalenv())
r <- call("/ok", p = port_late); ok(is.null(r$res$error) && identical(r$res$reply, "hello") && r$retries >= 1L, "connection refused until the server is up: retried, then the reply")
assign(".ANTHROPIC_ASYNC_RETRY_DELAYS", c(2, 2, 2, 2), envir = globalenv())
stop_now <- FALSE; later::later(function() stop_now <<- TRUE, 1)
r <- call("/salways", should_stop = function() stop_now); ok(isTRUE(r$res$stopped) && r$retries == 1L, "Stop during the wait: no further attempt, the run ends as stopped")
srv$kill(); if (!is.null(late)) late$kill()
cat("RETRY TEST PASSED\n")
