# Tests for editor widget functions

test_that("editor() creates a valid htmlwidget", {
  widget <- editor("wss://sync.example.com", "test-doc-id")

  expect_s3_class(widget, "htmlwidget")
  expect_s3_class(widget, "shinysyncEditor")
})

test_that("editor() passes parameters correctly", {
  widget <- editor(
    server_url = "wss://sync.example.com",
    doc_id = "my-document-123",
    timeout = 5000
  )

  expect_equal(widget$x$serverUrl, "wss://sync.example.com")
  expect_equal(widget$x$docId, "my-document-123")
  expect_equal(widget$x$timeout, 5000)
})

test_that("editor() uses default values", {
  widget <- editor("wss://sync.example.com", "test-doc-id")

  expect_equal(widget$x$timeout, 10000)
  expect_equal(widget$width, "100%")
  expect_equal(widget$height, "400px")
})

test_that("editor() accepts custom dimensions", {
  widget <- editor(
    "wss://sync.example.com", "test-doc-id",
    width = "800px", height = "600px"
  )

  expect_equal(widget$width, "800px")
  expect_equal(widget$height, "600px")
})

test_that("editor() accepts numeric dimensions", {
  widget <- editor(
    "wss://sync.example.com", "test-doc-id",
    width = 500, height = 300
  )

  expect_equal(widget$width, 500)

  expect_equal(widget$height, 300)
})

test_that("editor_output() creates Shiny output binding", {
  skip_if_not_installed("shiny")

  output <- editor_output("myEditor")

  expect_s3_class(output, "shiny.tag.list")
  html <- as.character(output)
  expect_match(html, "myEditor")
  expect_match(html, "shinysyncEditor")
})

test_that("editor_output() uses default dimensions", {
  skip_if_not_installed("shiny")

  output <- editor_output("myEditor")
  html <- as.character(output)

  expect_match(html, "100%")
  expect_match(html, "400px")
})

test_that("editor_output() accepts custom dimensions", {
  skip_if_not_installed("shiny")

  output <- editor_output("myEditor", width = "800px", height = "600px")
  html <- as.character(output)

  expect_match(html, "800px")
  expect_match(html, "600px")
})

test_that("editor_render() returns a render function", {
  skip_if_not_installed("shiny")

  render_fn <- editor_render({
    editor("wss://sync.example.com", "test-doc-id")
  })

  expect_type(render_fn, "closure")
})

test_that("editor_render() handles quoted expressions", {
  skip_if_not_installed("shiny")

  expr <- quote(editor("wss://sync.example.com", "test-doc-id"))
  render_fn <- editor_render(expr, quoted = TRUE)

  expect_type(render_fn, "closure")
})
