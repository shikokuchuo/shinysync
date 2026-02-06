test_that("checklist_ui() creates valid Shiny tags", {
  skip_if_not_installed("shiny")

  ui <- checklist_ui("test")

  expect_s3_class(ui, "shiny.tag")
  html <- as.character(ui)
  expect_match(html, "test-new_item")
  expect_match(html, "test-add_btn")
  expect_match(html, "test-items_list")
})

test_that("checklist_ui() accepts custom width", {
  skip_if_not_installed("shiny")

  ui <- checklist_ui("test", width = "500px")
  html <- as.character(ui)

  expect_match(html, "500px")
})

test_that("generate_id() creates unique IDs", {
  generate_id <- autoedit:::generate_id
  ids <- replicate(100, generate_id())

  expect_length(unique(ids), 100)
  expect_true(all(nchar(ids) > 10))
})

test_that("get_checklist_state() creates and reuses master document", {
  skip_if_not_installed("shiny")

  env <- autoedit:::.master_checklists
  if (exists("test-state", envir = env)) rm("test-state", envir = env)

  get_state <- autoedit:::get_checklist_state

  shiny::isolate({
    state1 <- get_state("test-state")
    state2 <- get_state("test-state")

    expect_s3_class(state1, "reactivevalues")
    expect_identical(state1, state2)

    items <- automerge::am_get(state1$doc, automerge::AM_ROOT, "items")
    expect_s3_class(items, "am_list")
  })

  rm("test-state", envir = env)
})
