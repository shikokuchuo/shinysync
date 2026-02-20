# autoedit

Real-time collaborative editing for R and Shiny applications, built on
[Automerge](https://automerge.org/) CRDT.

[![Ask
DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shikokuchuo/autoedit)

## Installation

``` r
pak::pak("shikokuchuo/autoedit")
```

## Features

| Component                                                                   | Description                                              | Sync Server  |
|-----------------------------------------------------------------------------|----------------------------------------------------------|--------------|
| [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md)           | CodeMirror 6 code editor with cursor-preserving sync     | Required     |
| [`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md) | Synchronize any Shiny inputs across sessions with replay | Not required |
| [`kanban_ui()`](http://shikokuchuo.net/autoedit/reference/kanban_ui.md)     | Collaborative kanban board with movable items            | Not required |
| [`textarea_ui()`](http://shikokuchuo.net/autoedit/reference/textarea_ui.md) | Basic synchronized textarea                              | Not required |

The **editor** provides the best experience for collaborative text
editing, with proper cursor preservation when remote changes arrive.

**sync_inputs** makes an entire Shiny app collaborative with a single
function call. All scalar inputs (sliders, dropdowns, checkboxes, text
inputs) are synchronized automatically. Pair with
[`replay_ui()`](http://shikokuchuo.net/autoedit/reference/replay_ui.md)
/
[`replay_server()`](http://shikokuchuo.net/autoedit/reference/replay_server.md)
to step through the full history of input changes.

The **kanban** module works well without a sync server because its
actions (add, toggle, delete, move) are discrete - there’s no cursor
position to preserve.

The **textarea** syncs correctly but has UX limitations (cursor jumps on
remote edits), making it suitable only for simple use cases.

## Quick Start

### Kanban Board (serverless)

``` r
library(shiny)
library(autoedit)

ui <- fluidPage(kanban_ui("board"))

server <- function(input, output, session) {
  kanban_server("board", initial_items = list(
    todo = c("Design feature", "Write tests"),
    in_progress = c("Code review"),
    done = c("Deploy v1.0")
  ))
}

shinyApp(ui, server)
```

### Collaborative Shiny App (serverless)

``` r
library(shiny)
library(autoedit)

ui <- fluidPage(
  selectInput("dist", "Distribution", c("Normal", "Uniform", "Exponential")),
  sliderInput("n", "Observations", 10, 500, 100),
  plotOutput("plot"),
  replay_ui("timeline")
)

server <- function(input, output, session) {
  replaying <- sync_inputs()
  replay_server("timeline", replaying = replaying)

  output$plot <- renderPlot({
    data <- switch(input$dist,
      Normal = rnorm(input$n),
      Uniform = runif(input$n),
      Exponential = rexp(input$n)
    )
    hist(data, main = input$dist, col = "steelblue", border = "white")
  })
}

shinyApp(ui, server)
```

### Editor (with sync server)

``` r
library(shiny)
library(autoedit)
library(autosync)
library(automerge)

sync_server <- amsync_server()
sync_server$start()

doc_id <- create_document(sync_server)
doc <- get_document(sync_server, doc_id)
am_put(doc, AM_ROOT, "text", am_text("Start typing..."))
am_commit(doc, "init")

ui <- fluidPage(editor_output("editor"))

server <- function(input, output, session) {
  output$editor <- editor_render(editor(sync_server$url, doc_id))
}

onStop(function() sync_server$close())
shinyApp(ui, server)
```

Open either app in multiple browser windows for real-time collaboration.

## Vignettes

- **Collaborative Shiny Apps** - Using
  [`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
  with replay
- **Collaborative Meeting Notes App** - Using the CodeMirror editor with
  a sync server
- **Collaborative Kanban Board** - Serverless task management

## Development

To rebuild the bundled JavaScript widget:

``` bash
cd inst/build
npm install
npm run build
```

## Related Packages

- [automerge](https://github.com/posit-dev/automerge-r) - R bindings for
  Automerge CRDT
- [autosync](https://github.com/shikokuchuo/autosync) - R sync server
  for Automerge documents
