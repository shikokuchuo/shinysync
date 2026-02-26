# Collaborative kanban board server

Server logic for a collaborative kanban board that synchronizes across
Shiny sessions using Automerge CRDT.

## Usage

``` r
kanban_server(
  id,
  doc_id = "default",
  columns = c(todo = "To Do", in_progress = "In Progress", done = "Done"),
  initial_items = NULL
)
```

## Arguments

- id:

  Module ID (must match the ID used in
  [`kanban_ui()`](http://shikokuchuo.net/shinysync/reference/kanban_ui.md)).

- doc_id:

  Document identifier. All kanban boards with the same `doc_id`
  synchronize together. Default is `"default"`.

- columns:

  Named character vector defining the columns (must match UI).

- initial_items:

  Optional named list of initial items per column. Names should be
  column IDs, values are character vectors of item texts.

## Value

A reactive expression returning a data frame with columns `id`, `text`,
`done`, and `column`.

## Details

Items can be moved between columns using the arrow buttons. The kanban
board uses a single Automerge document where each item has a `column`
field indicating which column it belongs to.

## See also

Other kanban:
[`kanban_ui()`](http://shikokuchuo.net/shinysync/reference/kanban_ui.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(kanban_ui("board"))
  server <- function(input, output, session) {
    kanban_server("board", initial_items = list(
      todo = c("Design feature", "Write tests"),
      in_progress = c("Code review"),
      done = c("Deploy v1.0")
    ))
  }
  shiny::shinyApp(ui, server)
}
```
