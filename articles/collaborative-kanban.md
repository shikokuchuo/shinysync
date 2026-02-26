# Collaborative Kanban Board

This vignette demonstrates how to build a collaborative kanban board
using shinysync’s
[`kanban_ui()`](http://shikokuchuo.net/shinysync/reference/kanban_ui.md)
and
[`kanban_server()`](http://shikokuchuo.net/shinysync/reference/kanban_server.md)
functions.

## Why kanban boards work well for collaboration

Collaborative text editing is challenging because users have a cursor
position that must be preserved when remote changes arrive. Standard
HTML textareas can’t do this, leading to a frustrating experience.

Kanban boards avoid this problem because each action is discrete:

- **Adding an item**: Click a button, type text, submit
- **Moving an item**: Click an arrow button
- **Toggling an item**: Click a checkbox
- **Deleting an item**: Click the delete button

When the UI re-renders after a remote change, you’re not in the middle
of anything that gets disrupted.

Automerge handles concurrent operations correctly:

- Two users add items simultaneously: Both items appear
- Two users move the same item: Last write wins
- One user deletes while another moves: Delete wins

## Basic example

``` r
library(shiny)
library(shinysync)

ui <- fluidPage(
  h3("Team Kanban"),
  kanban_ui("board")
)

server <- function(input, output, session) {
  kanban_server(
    "board",
    doc_id = "team-kanban",
    initial_items = list(
      todo = c("Design feature", "Write tests"),
      in_progress = c("Code review"),
      done = c("Deploy v1.0")
    )
  )
}

shinyApp(ui, server)
```

Open in two browser windows and try moving items between columns.

## Complete application

``` r
library(shiny)
library(bslib)
library(shinysync)

ui <- page_fillable(
  padding = "1rem",
  h2("Collaborative Kanban Board"),
  p(class = "text-muted", "Session: ", textOutput("session_id", inline = TRUE)),
  kanban_ui("board"),
  hr(),
  card(
    card_header("Progress Summary"),
    card_body(verbatimTextOutput("summary"))
  )
)

server <- function(input, output, session) {
  output$session_id <- renderText(substr(session$token, 1, 6))

  items <- kanban_server(
    "board",
    doc_id = "team-kanban",
    initial_items = list(
      todo = c("Design new feature", "Write tests", "Update docs"),
      in_progress = c("Code review PR #42"),
      done = c("Fix login bug", "Deploy v1.2")
    )
  )

  output$summary <- renderPrint({
    df <- items()
    for (col in c("todo", "in_progress", "done")) {
      col_items <- df[df$column == col, ]
      cat(sprintf("%-12s %d items (%d done)\n",
                  paste0(col, ":"),
                  nrow(col_items),
                  sum(col_items$done)))
    }
  })
}

shinyApp(ui, server)
```

## Custom columns

You can define your own columns:

``` r
kanban_ui(
  "board",
  columns = c(
    backlog = "Backlog",
    ready = "Ready",
    doing = "Doing",
    review = "Review",
    done = "Done"
  ),
  column_colors = c(
    backlog = "#64748b",
    ready = "#8b5cf6",
    doing = "#3b82f6",
    review = "#f59e0b",
    done = "#22c55e"
  )
)

kanban_server(
  "board",
  columns = c(
    backlog = "Backlog",
    ready = "Ready",
    doing = "Doing",
    review = "Review",
    done = "Done"
  ),
  initial_items = list(
    backlog = c("Future feature A", "Future feature B"),
    ready = c("Approved task"),
    doing = c("Current work"),
    review = c("PR #123"),
    done = c("Shipped!")
  )
)
```

## Document IDs

The `doc_id` parameter identifies the collaborative document. All
sessions using the same `doc_id` synchronize together:

``` r
# These sync together
kanban_server("board1", doc_id = "shared-board")
kanban_server("board2", doc_id = "shared-board")

# This is independent
kanban_server("board3", doc_id = "other-board")
```

## Return value

[`kanban_server()`](http://shikokuchuo.net/shinysync/reference/kanban_server.md)
returns a reactive data frame with columns `id`, `text`, `done`, and
`column`:

``` r
items <- kanban_server("board", doc_id = "my-board")

observe({
  df <- items()
  done_count <- sum(df$column == "done")
  total <- nrow(df)
  message(sprintf("%d/%d items done", done_count, total))
})
```

## Limitations

The kanban module:

- Only syncs within a single R process (no multi-process scaling)
- Stores documents in memory (no persistence across restarts)

For production deployments needing persistence and scaling, use
[`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md) with
a sync server.
