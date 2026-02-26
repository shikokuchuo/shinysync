# Tests for replay module

# Helper: populate a master sync doc with a known history for testing.
# Returns the doc_id used. Caller must clean up .master_sync[[doc_id]].
setup_replay_doc <- function(doc_id, steps) {
  env <- shinysync:::.master_sync
  get_state <- shinysync:::get_sync_state

  shiny::isolate({
    state <- get_state(doc_id)
    inputs <- automerge::am_get(state$doc, automerge::AM_ROOT, "inputs")

    for (step in steps) {
      for (nm in names(step$values)) {
        automerge::am_put(state$doc, inputs, nm, step$values[[nm]])
      }
      automerge::am_commit(state$doc, step$msg, time = step$time)
    }
    state$version <- length(steps)
  })

  doc_id
}

cleanup_replay_doc <- function(doc_id) {
  env <- shinysync:::.master_sync
  excl <- shinysync:::.sync_excludes
  if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env)
  if (exists(doc_id, envir = excl)) rm(list = doc_id, envir = excl)
}

# -- replay_ui() ---------------------------------------------------------------

test_that("replay_ui() creates valid Shiny tags", {
  ui <- replay_ui("test")

  expect_s3_class(ui, "shiny.tag")
  html <- as.character(ui)

  # Timeline slider
  expect_match(html, "test-timeline")
  # Playback controls
  expect_match(html, "test-first")
  expect_match(html, "test-prev")
  expect_match(html, "test-play")
  expect_match(html, "test-next_btn")
  expect_match(html, "test-last")
  # Step label output
  expect_match(html, "test-step_label")
})

test_that("replay_ui() includes commit message output when show_messages = TRUE", {
  ui <- replay_ui("test", show_messages = TRUE)
  html <- as.character(ui)

  expect_match(html, "test-commit_msg")
})

test_that("replay_ui() omits commit message output when show_messages = FALSE", {
  ui <- replay_ui("test", show_messages = FALSE)
  html <- as.character(ui)

  expect_no_match(html, "test-commit_msg")
})

test_that("replay_ui() stores config data attributes", {
  ui <- replay_ui("test", playback_ms = 500)
  html <- as.character(ui)

  expect_match(html, 'data-playback-ms="500"')
  expect_match(html, 'data-show-messages="true"')
})

test_that("replay_ui() stores show_messages=false in config", {
  ui <- replay_ui("test", show_messages = FALSE, playback_ms = 2000)
  html <- as.character(ui)

  expect_match(html, 'data-show-messages="false"')
  expect_match(html, 'data-playback-ms="2000"')
})

test_that("replay_ui() namespaces all element IDs", {
  ui <- replay_ui("mymod")
  html <- as.character(ui)

  # All IDs should be prefixed with "mymod-"
  expect_match(html, "mymod-timeline")
  expect_match(html, "mymod-config")
  expect_match(html, "mymod-first")
  expect_match(html, "mymod-play")
})

# -- replay snapshot reconstruction via am_fork() ------------------------------

test_that("am_fork() at historical hash reconstructs correct state", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")

  # Step 1: set x = "a"
  automerge::am_put(doc, inputs, "x", "a")
  automerge::am_commit(doc, "x: a", time = Sys.time())

  # Step 2: set x = "b"
  automerge::am_put(doc, inputs, "x", "b")
  automerge::am_commit(doc, "x: b", time = Sys.time())

  # Step 3: set x = "c"
  automerge::am_put(doc, inputs, "x", "c")
  automerge::am_commit(doc, "x: c", time = Sys.time())

  # Get all changes and filter to meaningful ones
  changes <- automerge::am_get_changes(doc)
  is_meaningful <- vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))

  meaningful <- changes[is_meaningful]
  hashes <- lapply(meaningful, automerge::am_change_hash)

  expect_length(hashes, 3L)

  # Fork at step 1 — should have x = "a"
  snap1 <- automerge::am_fork(doc, hashes[1])
  inputs1 <- automerge::am_get(snap1, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(snap1, inputs1, "x"), "a")

  # Fork at step 2 — should have x = "b"
  snap2 <- automerge::am_fork(doc, hashes[2])
  inputs2 <- automerge::am_get(snap2, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(snap2, inputs2, "x"), "b")

  # Fork at step 3 — should have x = "c"
  snap3 <- automerge::am_fork(doc, hashes[3])
  inputs3 <- automerge::am_get(snap3, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(snap3, inputs3, "x"), "c")
})

test_that("am_fork() preserves multiple keys at historical point", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")

  # Step 1: set dist and n
  automerge::am_put(doc, inputs, "dist", "Normal")
  automerge::am_put(doc, inputs, "n", 100)
  automerge::am_commit(doc, "dist, n: 2 inputs", time = Sys.time())

  # Step 2: change only dist
  automerge::am_put(doc, inputs, "dist", "Uniform")
  automerge::am_commit(doc, "dist: Uniform", time = Sys.time())

  changes <- automerge::am_get_changes(doc)
  meaningful <- changes[vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))]

  hashes <- lapply(meaningful, automerge::am_change_hash)

  # At step 1: dist = "Normal", n = 100
  snap1 <- automerge::am_fork(doc, hashes[1])
  inp1 <- automerge::am_get(snap1, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(snap1, inp1, "dist"), "Normal")
  expect_equal(automerge::am_get(snap1, inp1, "n"), 100)

  # At step 2: dist = "Uniform", n still 100
  snap2 <- automerge::am_fork(doc, hashes[2])
  inp2 <- automerge::am_get(snap2, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(snap2, inp2, "dist"), "Uniform")
  expect_equal(automerge::am_get(snap2, inp2, "n"), 100)
})

test_that("am_fork() handles all syncable value types", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")

  automerge::am_put(doc, inputs, "str", "hello")
  automerge::am_put(doc, inputs, "num", 3.14)
  automerge::am_put(doc, inputs, "int", 42L)
  automerge::am_put(doc, inputs, "lgl", TRUE)
  automerge::am_commit(doc, "all types", time = Sys.time())

  changes <- automerge::am_get_changes(doc)
  meaningful <- changes[vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))]
  hash <- automerge::am_change_hash(meaningful[[1L]])

  snap <- automerge::am_fork(doc, list(hash))
  inp <- automerge::am_get(snap, automerge::AM_ROOT, "inputs")

  expect_equal(automerge::am_get(snap, inp, "str"), "hello")
  expect_equal(automerge::am_get(snap, inp, "num"), 3.14)
  expect_type(automerge::am_get(snap, inp, "lgl"), "logical")
  expect_true(automerge::am_get(snap, inp, "lgl"))
})

test_that("step_info filtering logic excludes init commits", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")

  # Simulate a second session joining (init commit)
  automerge::am_put(doc, inputs, "x", "hello")
  automerge::am_commit(doc, "init: x", time = Sys.time())

  # Real user change
  automerge::am_put(doc, inputs, "x", "world")
  automerge::am_commit(doc, "x: world", time = Sys.time())

  changes <- automerge::am_get_changes(doc)

  is_meaningful <- vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))

  meaningful <- changes[is_meaningful]
  expect_length(meaningful, 1L)
  expect_equal(automerge::am_change_message(meaningful[[1L]]), "x: world")
})

test_that("step_info filtering returns empty for init-only doc", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  changes <- automerge::am_get_changes(doc)
  is_meaningful <- vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))

  expect_false(any(is_meaningful))
})

test_that("am_fork at step produces correct am_keys", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")

  # Step 1: only "a" exists
  automerge::am_put(doc, inputs, "a", 1)
  automerge::am_commit(doc, "a: 1", time = Sys.time())

  # Step 2: add "b"
  automerge::am_put(doc, inputs, "b", 2)
  automerge::am_commit(doc, "b: 2", time = Sys.time())

  changes <- automerge::am_get_changes(doc)
  meaningful <- changes[vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))]

  hashes <- lapply(meaningful, automerge::am_change_hash)

  # At step 1 only key "a" should exist
  snap1 <- automerge::am_fork(doc, hashes[1])
  inp1 <- automerge::am_get(snap1, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_keys(snap1, inp1), "a")

  # At step 2 both keys exist
  snap2 <- automerge::am_fork(doc, hashes[2])
  inp2 <- automerge::am_get(snap2, automerge::AM_ROOT, "inputs")
  expect_setequal(automerge::am_keys(snap2, inp2), c("a", "b"))
})

test_that("am_fork() does not mutate the source document", {
  doc <- automerge::am_create()
  automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(doc, "init")

  inputs <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")
  automerge::am_put(doc, inputs, "x", "a")
  automerge::am_commit(doc, "x: a", time = Sys.time())
  automerge::am_put(doc, inputs, "x", "b")
  automerge::am_commit(doc, "x: b", time = Sys.time())

  heads_before <- automerge::am_get_heads(doc)

  changes <- automerge::am_get_changes(doc)
  meaningful <- changes[vapply(changes, function(ch) {
    msg <- automerge::am_change_message(ch)
    !is.null(msg) && !startsWith(msg, "init")
  }, logical(1))]
  hash1 <- automerge::am_change_hash(meaningful[[1L]])

  # Fork at step 1
 automerge::am_fork(doc, list(hash1))

  # Source doc should be unchanged
  heads_after <- automerge::am_get_heads(doc)
  expect_identical(heads_before, heads_after)

  inputs2 <- automerge::am_get(doc, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(doc, inputs2, "x"), "b")
})

# -- replay_server() via testServer -------------------------------------------

test_that("replay_server step_info and outputs work with populated doc", {
  doc_id <- "test-rs-outputs"
  t1 <- as.POSIXct("2026-01-15 10:30:00", tz = "UTC")
  t2 <- as.POSIXct("2026-01-15 10:31:00", tz = "UTC")

  setup_replay_doc(doc_id, list(
    list(values = list(dist = "Normal"), msg = "dist: Normal", time = t1),
    list(values = list(dist = "Uniform"), msg = "dist: Uniform", time = t2)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      # n_steps should reflect 2 meaningful changes
      expect_equal(n_steps(), 2L)

      # step_info should have 2 hashes, messages, timestamps
      info <- step_info()
      expect_length(info$hashes, 2L)
      expect_equal(info$messages, c("dist: Normal", "dist: Uniform"))
      expect_length(info$timestamps, 2L)

      # Set timeline to step 1 and check outputs
      session$setInputs(timeline = 1L)
      expect_match(output$step_label, "Step 1 of 2")
      expect_equal(output$commit_msg, "dist: Normal")

      # Set timeline to step 2 (end) and check outputs
      session$setInputs(timeline = 2L)
      expect_match(output$step_label, "Step 2 of 2")
      expect_equal(output$commit_msg, "dist: Uniform")
    }
  )
})

test_that("replay_server sets replaying flag when not at end", {
  doc_id <- "test-rs-replaying-flag"
  now <- Sys.time()

  setup_replay_doc(doc_id, list(
    list(values = list(x = "a"), msg = "x: a", time = now),
    list(values = list(x = "b"), msg = "x: b", time = now + 1),
    list(values = list(x = "c"), msg = "x: c", time = now + 2)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      # Move to step 1 (not at end) — should enter replay
      session$setInputs(timeline = 1L)
      expect_true(replaying())

      # Move to step 2 (still not at end)
      session$setInputs(timeline = 2L)
      expect_true(replaying())

      # Move to step 3 (end) — should exit replay
      session$setInputs(timeline = 3L)
      expect_false(replaying())
    }
  )
})

test_that("replay_server handles empty document gracefully", {
  doc_id <- "test-rs-empty"
  # No steps — only the init commit from get_sync_state
  shinysync:::get_sync_state(doc_id)
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      expect_equal(n_steps(), 0L)

      info <- step_info()
      expect_length(info$hashes, 0L)
      expect_length(info$messages, 0L)
      expect_length(info$timestamps, 0L)

      # Outputs should return empty strings
      session$setInputs(timeline = 1L)
      expect_equal(output$step_label, "")
      expect_equal(output$commit_msg, "")
    }
  )
})

test_that("replay_server single step doc: at end means not replaying", {
  doc_id <- "test-rs-single"
  now <- Sys.time()

  setup_replay_doc(doc_id, list(
    list(values = list(x = "only"), msg = "x: only", time = now)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      expect_equal(n_steps(), 1L)

      # Step 1 is also the last step, so should not enter replay
      session$setInputs(timeline = 1L)
      expect_false(replaying())
    }
  )
})

test_that("replay_server play/pause toggles playing state", {
  doc_id <- "test-rs-play"
  now <- Sys.time()

  setup_replay_doc(doc_id, list(
    list(values = list(x = "a"), msg = "x: a", time = now),
    list(values = list(x = "b"), msg = "x: b", time = now + 1),
    list(values = list(x = "c"), msg = "x: c", time = now + 2)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      # Set timeline to a non-end position first so the animation observer
      # can read input$timeline without hitting NULL
      session$setInputs(timeline = 1L)

      expect_false(playing())

      session$setInputs(play = 1L)
      expect_true(playing())

      session$setInputs(play = 2L)
      expect_false(playing())
    }
  )
})

test_that("replay_server registers sync exclude for its namespace", {
  doc_id <- "test-rs-exclude"
  now <- Sys.time()

  setup_replay_doc(doc_id, list(
    list(values = list(x = "a"), msg = "x: a", time = now)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      # The module should have registered its namespace prefix
      excl_env <- shinysync:::.sync_excludes
      expect_true(exists(doc_id, envir = excl_env))
      prefixes <- excl_env[[doc_id]]
      # Should contain the module's namespace prefix (ends with "-")
      expect_true(any(nzchar(prefixes)))
    }
  )
})

test_that("replay_server step_info timestamps are numeric", {
  doc_id <- "test-rs-timestamps"
  t1 <- as.POSIXct("2026-06-01 12:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-06-01 12:05:00", tz = "UTC")

  setup_replay_doc(doc_id, list(
    list(values = list(n = 10), msg = "n: 10", time = t1),
    list(values = list(n = 20), msg = "n: 20", time = t2)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      info <- step_info()
      expect_type(info$timestamps, "double")
      expect_length(info$timestamps, 2L)
      # Timestamps should be positive epoch seconds
      expect_true(all(info$timestamps > 0))
      # Second timestamp should be after first
      expect_true(info$timestamps[2L] > info$timestamps[1L])
    }
  )
})

test_that("replay_server step label includes timestamp", {
  doc_id <- "test-rs-label-ts"
  t1 <- as.POSIXct("2026-03-10 14:25:30", tz = "UTC")

  setup_replay_doc(doc_id, list(
    list(values = list(x = "a"), msg = "x: a", time = t1),
    list(values = list(x = "b"), msg = "x: b", time = t1 + 60)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      session$setInputs(timeline = 1L)
      label <- output$step_label
      # Should contain "Step 1 of 2" and a time with the em-dash separator
      expect_match(label, "Step 1 of 2")
      expect_match(label, "\u2014")
    }
  )
})

test_that("replay_server step_info hashes are raw vectors", {
  doc_id <- "test-rs-hash-type"
  now <- Sys.time()

  setup_replay_doc(doc_id, list(
    list(values = list(a = 1), msg = "a: 1", time = now),
    list(values = list(b = 2), msg = "b: 2", time = now + 1)
  ))
  on.exit(cleanup_replay_doc(doc_id))

  replaying <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    replay_server,
    args = list(doc_id = doc_id, replaying = replaying),
    {
      info <- step_info()
      expect_type(info$hashes, "list")
      for (h in info$hashes) {
        expect_type(h, "raw")
      }
    }
  )
})
