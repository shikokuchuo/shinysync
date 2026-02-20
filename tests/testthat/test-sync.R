# Tests for sync_inputs() helpers and state management

# -- is_syncable() ------------------------------------------------------------

test_that("is_syncable() accepts scalar strings, numbers, and logicals", {
  is_syncable <- autoedit:::is_syncable

  expect_true(is_syncable("hello"))
  expect_true(is_syncable(42))
  expect_true(is_syncable(3.14))
  expect_true(is_syncable(TRUE))
  expect_true(is_syncable(FALSE))
})

test_that("is_syncable() accepts scalar integers", {
  is_syncable <- autoedit:::is_syncable

  expect_true(is_syncable(1L))
  expect_true(is_syncable(0L))
})

test_that("is_syncable() accepts edge-case scalar values", {
  is_syncable <- autoedit:::is_syncable

  expect_true(is_syncable(""))
  expect_true(is_syncable(0))
  expect_true(is_syncable(Inf))
  expect_true(is_syncable(-Inf))
  expect_true(is_syncable(NaN))
  expect_true(is_syncable(NA_character_))
  expect_true(is_syncable(NA_real_))
  expect_true(is_syncable(NA))
})

test_that("is_syncable() rejects NULL and non-scalar values", {
  is_syncable <- autoedit:::is_syncable

  expect_false(is_syncable(NULL))
  expect_false(is_syncable(c("a", "b")))
  expect_false(is_syncable(1:5))
  expect_false(is_syncable(list(1)))
  expect_false(is_syncable(data.frame(x = 1)))
})

test_that("is_syncable() rejects non-atomic types", {
  is_syncable <- autoedit:::is_syncable

  expect_false(is_syncable(list()))
  expect_false(is_syncable(mean))
  expect_false(is_syncable(as.raw(0)))
  expect_false(is_syncable(1i))
  expect_false(is_syncable(as.factor("a")))
})

test_that("is_syncable() rejects zero-length vectors", {
  is_syncable <- autoedit:::is_syncable

  expect_false(is_syncable(character()))
  expect_false(is_syncable(numeric()))
  expect_false(is_syncable(logical()))
})

# -- filter_input_ids() -------------------------------------------------------

test_that("filter_input_ids() excludes dotted names", {
  filter <- autoedit:::filter_input_ids

  result <- filter(c("dist", ".clientdata_url", "n", ".hidden"))
  expect_equal(result, c("dist", "n"))
})

test_that("filter_input_ids() applies include filter", {
  filter <- autoedit:::filter_input_ids

  result <- filter(c("dist", "n", "color"), include = c("dist", "n"))
  expect_equal(result, c("dist", "n"))
})

test_that("filter_input_ids() applies exclude filter", {
  filter <- autoedit:::filter_input_ids

  result <- filter(c("dist", "n", "color"), exclude = "color")
  expect_equal(result, c("dist", "n"))
})

test_that("filter_input_ids() applies include then exclude", {
  filter <- autoedit:::filter_input_ids

  result <- filter(
    c("a", "b", "c", "d"),
    include = c("a", "b", "c"),
    exclude = "b"
  )
  expect_equal(result, c("a", "c"))
})

test_that("filter_input_ids() returns empty for all-dotted input", {
  filter <- autoedit:::filter_input_ids

  result <- filter(c(".a", ".b"))
  expect_length(result, 0L)
})

test_that("filter_input_ids() handles empty input vector", {
  filter <- autoedit:::filter_input_ids

  result <- filter(character())
  expect_length(result, 0L)
})

test_that("filter_input_ids() excludes registered module prefixes", {
  env <- autoedit:::.sync_excludes
  register <- autoedit:::register_sync_exclude
  filter <- autoedit:::filter_input_ids

  doc_id <- "test-filter-prefix"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  register(doc_id, "timeline-")
  result <- filter(
    c("dist", "timeline-play", "timeline-timeline", "n"),
    doc_id = doc_id
  )

  expect_equal(result, c("dist", "n"))
})

test_that("filter_input_ids() excludes multiple module prefixes", {
  env <- autoedit:::.sync_excludes
  register <- autoedit:::register_sync_exclude
  filter <- autoedit:::filter_input_ids

  doc_id <- "test-filter-multi-prefix"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  register(doc_id, "mod1-")
  register(doc_id, "mod2-")
  result <- filter(
    c("x", "mod1-a", "mod2-b", "y"),
    doc_id = doc_id
  )

  expect_equal(result, c("x", "y"))
})

test_that("filter_input_ids() works with no doc_id exclusions", {
  filter <- autoedit:::filter_input_ids

  result <- filter(c("a", "b"), doc_id = "nonexistent-doc-id")
  expect_equal(result, c("a", "b"))
})

# -- register_sync_exclude() ---------------------------------------------------

test_that("register_sync_exclude() accumulates unique prefixes", {
  env <- autoedit:::.sync_excludes
  register <- autoedit:::register_sync_exclude

  doc_id <- "test-exclude-accum"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  register(doc_id, "mod1-")
  register(doc_id, "mod2-")
  register(doc_id, "mod1-")

  expect_equal(env[[doc_id]], c("mod1-", "mod2-"))
})

test_that("register_sync_exclude() creates entry for new doc_id", {
  env <- autoedit:::.sync_excludes
  register <- autoedit:::register_sync_exclude

  doc_id <- "test-exclude-new"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  expect_false(exists(doc_id, envir = env))
  register(doc_id, "ns-")
  expect_true(exists(doc_id, envir = env))
  expect_equal(env[[doc_id]], "ns-")
})

# -- get_sync_state() ----------------------------------------------------------

test_that("get_sync_state() creates and reuses master document", {
  env <- autoedit:::.master_sync
  get_state <- autoedit:::get_sync_state

  doc_id <- "test-sync-state"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  shiny::isolate({
    state1 <- get_state(doc_id)
    state2 <- get_state(doc_id)

    expect_s3_class(state1, "reactivevalues")
    expect_identical(state1, state2)

    inputs <- automerge::am_get(state1$doc, automerge::AM_ROOT, "inputs")
    expect_s3_class(inputs, "am_map")
  })
})

test_that("get_sync_state() initialises with an init commit", {
  env <- autoedit:::.master_sync
  get_state <- autoedit:::get_sync_state

  doc_id <- "test-sync-init-commit"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  shiny::isolate({
    state <- get_state(doc_id)
    changes <- automerge::am_get_changes(state$doc)
    expect_true(length(changes) >= 1L)
    expect_equal(automerge::am_change_message(changes[[1L]]), "init")
  })
})

test_that("get_sync_state() initialises version to 0", {
  env <- autoedit:::.master_sync
  get_state <- autoedit:::get_sync_state

  doc_id <- "test-sync-version-init"
  on.exit(if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env))

  shiny::isolate({
    state <- get_state(doc_id)
    expect_equal(state$version, 0L)
  })
})

test_that("get_sync_state() persists and restores from disk", {
  env <- autoedit:::.master_sync
  paths_env <- autoedit:::.master_sync_paths
  get_state <- autoedit:::get_sync_state

  tmp <- tempfile(fileext = ".automerge")
  doc_id <- "test-sync-persist"
  on.exit({
    if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env)
    if (exists(doc_id, envir = paths_env)) rm(list = doc_id, envir = paths_env)
    unlink(tmp)
  })

  shiny::isolate({
    # Create state and write a value
    state <- get_state(doc_id, path = tmp)
    inputs <- automerge::am_get(state$doc, automerge::AM_ROOT, "inputs")
    automerge::am_put(state$doc, inputs, "x", "hello")
    automerge::am_commit(state$doc, "set x")
    writeBin(automerge::am_save(state$doc), tmp)

    # Remove from memory
    rm(list = doc_id, envir = env)
    rm(list = doc_id, envir = paths_env)

    # Re-create — should load from disk
    state2 <- get_state(doc_id, path = tmp)
    inputs2 <- automerge::am_get(state2$doc, automerge::AM_ROOT, "inputs")
    expect_equal(automerge::am_get(state2$doc, inputs2, "x"), "hello")
  })
})

test_that("get_sync_state() falls back to fresh doc on corrupt file", {
  env <- autoedit:::.master_sync
  paths_env <- autoedit:::.master_sync_paths
  get_state <- autoedit:::get_sync_state

  tmp <- tempfile(fileext = ".automerge")
  doc_id <- "test-sync-corrupt"
  on.exit({
    if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env)
    if (exists(doc_id, envir = paths_env)) rm(list = doc_id, envir = paths_env)
    unlink(tmp)
  })

  # Write garbage to the file

  writeBin(charToRaw("not a valid automerge document"), tmp)

  shiny::isolate({
    state <- get_state(doc_id, path = tmp)
    # Should get a fresh doc with an inputs map, not an error
    inputs <- automerge::am_get(state$doc, automerge::AM_ROOT, "inputs")
    expect_s3_class(inputs, "am_map")
    changes <- automerge::am_get_changes(state$doc)
    expect_equal(automerge::am_change_message(changes[[1L]]), "init")
  })
})

test_that("get_sync_state() first caller with path wins", {
  env <- autoedit:::.master_sync
  paths_env <- autoedit:::.master_sync_paths
  get_state <- autoedit:::get_sync_state

  tmp1 <- tempfile(fileext = ".automerge")
  tmp2 <- tempfile(fileext = ".automerge")
  doc_id <- "test-sync-path-wins"
  on.exit({
    if (exists(doc_id, envir = env)) rm(list = doc_id, envir = env)
    if (exists(doc_id, envir = paths_env)) rm(list = doc_id, envir = paths_env)
    unlink(c(tmp1, tmp2))
  })

  shiny::isolate({
    get_state(doc_id, path = tmp1)
    get_state(doc_id, path = tmp2)
    # First path should be recorded
    expect_equal(paths_env[[doc_id]], tmp1)
  })
})

# -- commit message formatting (sync_inputs observer logic) --------------------

test_that("single-input commit message uses 'id: value' format", {
  # Test the commit message logic from the observer
  changed_ids <- "dist"
  all_inputs <- list(dist = "Exponential")

  msg <- if (length(changed_ids) == 1L) {
    sprintf("%s: %s", changed_ids, as.character(all_inputs[[changed_ids]]))
  } else {
    sprintf(
      "%s: %d inputs",
      paste(changed_ids, collapse = ", "),
      length(changed_ids)
    )
  }
  expect_equal(msg, "dist: Exponential")
})

test_that("multi-input commit message uses 'ids: N inputs' format", {
  changed_ids <- c("dist", "n")
  all_inputs <- list(dist = "Normal", n = 100)

  msg <- if (length(changed_ids) == 1L) {
    sprintf("%s: %s", changed_ids, as.character(all_inputs[[changed_ids]]))
  } else {
    sprintf(
      "%s: %d inputs",
      paste(changed_ids, collapse = ", "),
      length(changed_ids)
    )
  }
  expect_equal(msg, "dist, n: 2 inputs")
})

# -- incremental sync protocol -------------------------------------------------

test_that("incremental sync converges two documents", {
  # Master doc (like get_sync_state creates)
  master <- automerge::am_create()
  automerge::am_put(master, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(master, "init")

  # Local doc loads from master (shared history, like sync_inputs does)
  local <- automerge::am_load(automerge::am_save(master))

  sync_local <- automerge::am_sync_state()
  sync_master <- automerge::am_sync_state()

  # Write a value in local
  inputs_l <- automerge::am_get(local, automerge::AM_ROOT, "inputs")
  automerge::am_put(local, inputs_l, "x", "hello")
  automerge::am_commit(local, "x: hello")

  # Run sync loop (same protocol as sync_inputs)
  repeat {
    msg_up <- automerge::am_sync_encode(local, sync_local)
    msg_down <- automerge::am_sync_encode(master, sync_master)
    if (is.null(msg_up) && is.null(msg_down)) break
    if (!is.null(msg_up)) automerge::am_sync_decode(master, sync_master, msg_up)
    if (!is.null(msg_down)) automerge::am_sync_decode(local, sync_local, msg_down)
  }

  # Master should now have x = "hello"
  inputs_m <- automerge::am_get(master, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(master, inputs_m, "x"), "hello")
})

test_that("incremental sync transfers changes in both directions", {
  # Master doc
  master <- automerge::am_create()
  automerge::am_put(master, automerge::AM_ROOT, "inputs", automerge::am_map())
  automerge::am_commit(master, "init")

  # Two local docs that share history via master
  local_a <- automerge::am_load(automerge::am_save(master))
  local_b <- automerge::am_load(automerge::am_save(master))

  sync_a <- automerge::am_sync_state()
  sync_ma <- automerge::am_sync_state()
  sync_b <- automerge::am_sync_state()
  sync_mb <- automerge::am_sync_state()

  # Session A writes a key
  inp_a <- automerge::am_get(local_a, automerge::AM_ROOT, "inputs")
  automerge::am_put(local_a, inp_a, "from_a", "value_a")
  automerge::am_commit(local_a, "from_a: value_a")

  # Sync A -> master
  repeat {
    msg_up <- automerge::am_sync_encode(local_a, sync_a)
    msg_down <- automerge::am_sync_encode(master, sync_ma)
    if (is.null(msg_up) && is.null(msg_down)) break
    if (!is.null(msg_up)) automerge::am_sync_decode(master, sync_ma, msg_up)
    if (!is.null(msg_down)) automerge::am_sync_decode(local_a, sync_a, msg_down)
  }

  # Session B writes a different key
  inp_b <- automerge::am_get(local_b, automerge::AM_ROOT, "inputs")
  automerge::am_put(local_b, inp_b, "from_b", "value_b")
  automerge::am_commit(local_b, "from_b: value_b")

  # Sync B -> master
  repeat {
    msg_up <- automerge::am_sync_encode(local_b, sync_b)
    msg_down <- automerge::am_sync_encode(master, sync_mb)
    if (is.null(msg_up) && is.null(msg_down)) break
    if (!is.null(msg_up)) automerge::am_sync_decode(master, sync_mb, msg_up)
    if (!is.null(msg_down)) automerge::am_sync_decode(local_b, sync_b, msg_down)
  }

  # Sync A again to pick up B's changes
  repeat {
    msg_up <- automerge::am_sync_encode(local_a, sync_a)
    msg_down <- automerge::am_sync_encode(master, sync_ma)
    if (is.null(msg_up) && is.null(msg_down)) break
    if (!is.null(msg_up)) automerge::am_sync_decode(master, sync_ma, msg_up)
    if (!is.null(msg_down)) automerge::am_sync_decode(local_a, sync_a, msg_down)
  }

  # Master should have both keys
  inp_m <- automerge::am_get(master, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(master, inp_m, "from_a"), "value_a")
  expect_equal(automerge::am_get(master, inp_m, "from_b"), "value_b")

  # Local A should have both keys
  inp_a2 <- automerge::am_get(local_a, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(local_a, inp_a2, "from_a"), "value_a")
  expect_equal(automerge::am_get(local_a, inp_a2, "from_b"), "value_b")

  # Local B should have both keys
  inp_b2 <- automerge::am_get(local_b, automerge::AM_ROOT, "inputs")
  expect_equal(automerge::am_get(local_b, inp_b2, "from_a"), "value_a")
  expect_equal(automerge::am_get(local_b, inp_b2, "from_b"), "value_b")
})
