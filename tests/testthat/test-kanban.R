test_that("kanban_ui() creates valid Shiny tags", {
  skip_if_not_installed("shiny")

  ui <- kanban_ui("test")

  expect_s3_class(ui, "shiny.tag")
  html <- as.character(ui)
  expect_match(html, "test-new_item")
  expect_match(html, "test-add_btn")
  expect_match(html, "test-col_todo")
  expect_match(html, "test-col_in_progress")
  expect_match(html, "test-col_done")
})

test_that("kanban_ui() renders custom columns", {
  skip_if_not_installed("shiny")

  ui <- kanban_ui(
    "test",
    columns = c(backlog = "Backlog", active = "Active", complete = "Complete")
  )
  html <- as.character(ui)

  expect_match(html, "test-col_backlog")
  expect_match(html, "test-col_active")
  expect_match(html, "test-col_complete")
  expect_match(html, "Backlog")
  expect_match(html, "Active")
  expect_match(html, "Complete")
})

test_that("kanban_ui() applies custom colors", {
  skip_if_not_installed("shiny")

  ui <- kanban_ui(
    "test",
    columns = c(a = "A", b = "B"),
    column_colors = c(a = "#ff0000", b = "#00ff00")
  )
  html <- as.character(ui)

  expect_match(html, "#ff0000")
  expect_match(html, "#00ff00")
})

test_that("get_kanban_state() creates and reuses master document", {
  skip_if_not_installed("shiny")

  env <- autoedit:::.master_kanbans
  if (exists("test-kanban", envir = env)) rm("test-kanban", envir = env)

  get_state <- autoedit:::get_kanban_state

  shiny::isolate({
    state1 <- get_state("test-kanban")
    state2 <- get_state("test-kanban")

    expect_s3_class(state1, "reactivevalues")
    expect_identical(state1, state2)

    items <- automerge::am_get(state1$doc, automerge::AM_ROOT, "items")
    expect_s3_class(items, "am_list")
  })

  rm("test-kanban", envir = env)
})
