
# autoedit

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/shikokuchuo/autoedit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/shikokuchuo/autoedit/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Real-time collaborative text editing for R and Shiny applications, built on [Automerge](https://automerge.org/) CRDT.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shikokuchuo/autoedit)

## Installation

``` r
pak::pak("shikokuchuo/autoedit")
```

## Overview

autoedit provides two approaches to collaborative editing:

| | Textarea | Editor |
|---|----------|--------|
| **Interface** | Standard Shiny textarea | CodeMirror 6 code editor |
| **Sync** | In-process via Shiny | WebSocket to external server |
| **Use case** | Multi-session Shiny apps | Cross-application collaboration |
| **Dependencies** | automerge | automerge, autosync |

## Textarea

A Shiny module that syncs across browser sessions using Shiny's reactive system. No external server required - the Shiny process manages document state directly.

``` r
library(shiny)
library(autoedit)

ui <- fluidPage(
  textarea_ui("editor", label = "Collaborative notes")
)

server <- function(input, output, session) {
  text <- textarea_server("editor", initial_text = "Start typing...")
}

shinyApp(ui, server)
```

Open in multiple browser windows for real-time collaboration.

## Editor

A [CodeMirror 6](https://codemirror.net/) code editor widget that syncs via WebSocket to any automerge-repo compatible server. Suitable for collaboration across different applications or persistent documents.

``` r
library(autoedit)

# Connect to a sync server
editor("ws://localhost:3030", "document-id")

# Or use the public Automerge sync server
editor("wss://sync.automerge.org", "your-document-id")
```

### Shiny Example

``` r
library(shiny)
library(automerge)
library(autosync)
library(autoedit)

server <- amsync_server()
server$start()

doc_id <- create_document(server)
doc <- get_document(server, doc_id)
am_put(doc, AM_ROOT, "text", am_text(""))
am_commit(doc, "init")

ui <- fluidPage(editor_output("editor"))

shiny_server <- function(input, output, session) {
  output$editor <- editor_render(editor(server$url, doc_id))
}

onStop(function() server$close())
shinyApp(ui, shiny_server)
```

## Development

To rebuild the bundled JavaScript widget:

``` bash
cd inst/build
npm install
npm run build
```

## Related Packages

- [automerge](https://github.com/posit-dev/automerge-r) - R bindings for Automerge CRDT
- [autosync](https://github.com/shikokuchuo/autosync) - R sync server for Automerge documents
