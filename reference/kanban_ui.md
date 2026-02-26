# Collaborative kanban board UI

Creates a kanban board that synchronizes across Shiny sessions using
Automerge CRDT, without requiring an external sync server.

## Usage

``` r
kanban_ui(
  id,
  columns = c(todo = "To Do", in_progress = "In Progress", done = "Done"),
  column_colors = c(todo = "#64748b", in_progress = "#3b82f6", done = "#22c55e")
)
```

## Arguments

- id:

  Module ID.

- columns:

  Named character vector defining the columns. Names are internal IDs,
  values are display labels. Default is

  `c(todo = "To Do", in_progress = "In Progress", done = "Done")`.

- column_colors:

  Named character vector of CSS colors for column headers. Names should
  match column IDs. Default provides red/yellow/green styling.

## Value

A Shiny UI element.

## See also

Other kanban:
[`kanban_server()`](http://shikokuchuo.net/shinysync/reference/kanban_server.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(kanban_ui("board"))
  server <- function(input, output, session) kanban_server("board")
  shiny::shinyApp(ui, server)
}
```
