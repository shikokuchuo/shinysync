# Collaborative Meeting Notes App

This vignette demonstrates how to build a collaborative meeting notes
application using autoedit. We start with the recommended approach using
[`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) with a
sync server, then show a simpler serverless alternative using
[`textarea_ui()`](http://shikokuchuo.net/autoedit/reference/textarea_ui.md)
for cases where the limitations are acceptable.

## Setup

To run these examples, you need the autoedit package installed:

``` r
# install.packages("pak")
pak::pak("shikokuchuo/autoedit")
```

Open multiple browser windows or tabs pointing to the same Shiny app URL
to see real-time collaboration in action.

## Collaborative editor with sync server

The [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md)
widget provides the best collaborative editing experience. It uses
CodeMirror 6 with the `automerge-codemirror` integration, which applies
Automerge operations directly to CodeMirror’s document model. This means
your cursor stays in place when others edit, you get full syntax
highlighting, and documents can be saved and restored across sessions.

### Editor example with autosync

The following example uses the
[autosync](https://github.com/shikokuchuo/autosync) package, which
provides an in-process Automerge sync server:

``` r
library(shiny)
library(autoedit)
library(autosync)
library(automerge)

# Available meeting rooms (names = display labels, values = IDs)
rooms <- c(
  "Daily Standup" = "standup",
  "Sprint Planning" = "planning",
  "Retrospective" = "retrospective",
  "Brainstorming" = "brainstorm"
)

room_labels <- setNames(names(rooms), rooms)

# Room-specific initial content templates
room_templates <- list(
  standup = "# Daily Standup\n\n## What I did yesterday\n- \n\n## What I'm doing today\n- \n\n## Blockers\n- \n",
  planning = "# Sprint Planning\n\n## Goals\n- \n\n## User Stories\n- \n\n## Capacity\n- \n",
  retrospective = "# Retrospective\n\n## What went well\n- \n\n## What could be improved\n- \n\n## Action items\n- \n",
  brainstorm = "# Brainstorming Session\n\n## Ideas\n- \n\n## Discussion Notes\n- \n"
)

# Create and start the sync server (once, at app startup)
sync_server <- amsync_server(port = 3030)
sync_server$start()

# Create a document for each room with initial content
doc_ids <- list()
for (room in rooms) {
  doc_ids[[room]] <- create_document(sync_server)
  doc <- get_document(sync_server, doc_ids[[room]])
  am_put(doc, AM_ROOT, "text", am_text(room_templates[[room]]))
  am_commit(doc, "init")
}

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      .notes-container {
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 0;
      }
      .room-header {
        background: #f8f9fa;
        padding: 10px 15px;
        border-bottom: 1px solid #ddd;
        border-radius: 4px 4px 0 0;
      }
      .sync-indicator {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #28a745;
        margin-right: 8px;
      }
    "))
  ),

  titlePanel("Collaborative Meeting Notes"),

  fluidRow(
    column(
      width = 3,
      wellPanel(
        h4("Select Room"),
        radioButtons(
          "room",
          label = NULL,
          choices = rooms,
          selected = "standup"
        ),
        hr(),
        p(
          class = "text-muted",
          tags$span(class = "sync-indicator"),
          "Sync active"
        ),
        p(
          class = "text-muted small",
          "Open multiple browser windows to collaborate in real-time."
        ),
        hr(),
        downloadButton("export", "Export as Quarto", class = "btn-sm")
      )
    ),

    column(
      width = 9,
      div(
        class = "notes-container",
        div(
          class = "room-header",
          h5(
            style = "margin: 0;",
            textOutput("room_title", inline = TRUE)
          )
        ),
        # Dynamically render the active editor
        uiOutput("active_editor")
      )
    )
  )
)

server <- function(input, output, session) {
  # Dynamically render only the active room's editor
  output$active_editor <- renderUI({
    editor_output("editor", height = "500px")
  })

  output$editor <- editor_render({
    editor(sync_server$url, doc_ids[[input$room]], height = "500px")
  })

  # Room title
  output$room_title <- renderText({
    room_labels[input$room]
  })

  # Get current room's text for export
  current_text <- reactive({
    input$editor_content
  })

  # Export handler
  output$export <- downloadHandler(
    filename = function() {
      paste0(input$room, "-notes-", Sys.Date(), ".qmd")
    },
    content = function(file) {
      front_matter <- sprintf(
        "---\ntitle: \"%s\"\ndate: \"%s\"\nformat: html\n---\n\n",
        room_labels[input$room],
        Sys.Date()
      )
      writeLines(paste0(front_matter, current_text()), file)
    }
  )
}

# Clean up when app stops
onStop(function() sync_server$close())

shinyApp(ui, server)
```

------------------------------------------------------------------------

## Serverless alternative with textarea

For simpler use cases, autoedit provides
[`textarea_ui()`](http://shikokuchuo.net/autoedit/reference/textarea_ui.md)
and
[`textarea_server()`](http://shikokuchuo.net/autoedit/reference/textarea_server.md)
functions that synchronize text without requiring an external sync
server.

### How it works

The textarea module uses Automerge CRDT (Conflict-free Replicated Data
Type) to synchronize text across multiple browser sessions. No external
server is required - synchronization happens in-process via Shiny’s
reactive system. Concurrent edits from multiple users are merged
automatically, and you can use different `doc_id` values to create
separate collaborative spaces.

### Complete application code

``` r
library(shiny)
library(autoedit)

# Available meeting rooms (names = display labels, values = IDs)
rooms <- c(
  "Daily Standup" = "standup",
  "Sprint Planning" = "planning",
  "Retrospective" = "retrospective",
  "Brainstorming" = "brainstorm"
)

room_labels <- setNames(names(rooms), rooms)

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      .notes-container {
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 0;
      }
      .notes-container textarea {
        font-family: 'SF Mono', Consolas, 'Liberation Mono', Menlo, monospace;
        font-size: 14px;
        line-height: 1.5;
        border: none;
        resize: none;
      }
      .room-header {
        background: #f8f9fa;
        padding: 10px 15px;
        border-bottom: 1px solid #ddd;
        border-radius: 4px 4px 0 0;
      }
      .sync-indicator {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #28a745;
        margin-right: 8px;
      }
    "))
  ),

  titlePanel("Collaborative Meeting Notes"),

  fluidRow(
    column(
      width = 3,
      wellPanel(
        h4("Select Room"),
        radioButtons(
          "room",
          label = NULL,
          choices = rooms,
          selected = "standup"
        ),
        hr(),
        p(
          class = "text-muted",
          tags$span(class = "sync-indicator"),
          "Sync active"
        ),
        p(
          class = "text-muted small",
          "Open multiple browser windows to collaborate in real-time."
        ),
        hr(),
        downloadButton("export", "Export as Quarto", class = "btn-sm")
      )
    ),

    column(
      width = 9,
      div(
        class = "notes-container",
        div(
          class = "room-header",
          h5(
            style = "margin: 0;",
            textOutput("room_title", inline = TRUE)
          )
        ),
        # Create a textarea for each room (only active one is visible)
        conditionalPanel(
          condition = "input.room == 'standup'",
          textarea_ui(
            "notes_standup",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your standup notes..."
          )
        ),
        conditionalPanel(
          condition = "input.room == 'planning'",
          textarea_ui(
            "notes_planning",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your planning notes..."
          )
        ),
        conditionalPanel(
          condition = "input.room == 'retrospective'",
          textarea_ui(
            "notes_retrospective",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your retrospective notes..."
          )
        ),
        conditionalPanel(
          condition = "input.room == 'brainstorm'",
          textarea_ui(
            "notes_brainstorm",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your ideas..."
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Initialize textarea servers for each room
  # Each room has its own doc_id for independent collaboration
  text_standup <- textarea_server(
    "notes_standup",
    doc_id = "standup",
    initial_text = "# Daily Standup\n\n## What I did yesterday\n- \n\n## What I'm doing today\n- \n\n## Blockers\n- \n"
  )

  text_planning <- textarea_server(
    "notes_planning",
    doc_id = "planning",
    initial_text = "# Sprint Planning\n\n## Goals\n- \n\n## User Stories\n- \n\n## Capacity\n- \n"
  )

  text_retrospective <- textarea_server(
    "notes_retrospective",
    doc_id = "retrospective",
    initial_text = "# Retrospective\n\n## What went well\n- \n\n## What could be improved\n- \n\n## Action items\n- \n"
  )

  text_brainstorm <- textarea_server(
    "notes_brainstorm",
    doc_id = "brainstorm",
    initial_text = "# Brainstorming Session\n\n## Ideas\n- \n\n## Discussion Notes\n- \n"
  )

  # Room title
  output$room_title <- renderText({
    room_labels[input$room]
  })

  # Get current room's text for export
  current_text <- reactive({
    switch(
      input$room,
      "standup" = text_standup(),
      "planning" = text_planning(),
      "retrospective" = text_retrospective(),
      "brainstorm" = text_brainstorm(),
      ""
    )
  })

  # Export handler
  output$export <- downloadHandler(
    filename = function() {
      paste0(input$room, "-notes-", Sys.Date(), ".qmd")
    },
    content = function(file) {
      front_matter <- sprintf(
        "---\ntitle: \"%s\"\ndate: \"%s\"\nformat: html\n---\n\n",
        room_labels[input$room],
        Sys.Date()
      )
      writeLines(paste0(front_matter, current_text()), file)
    }
  )
}

shinyApp(ui, server)
```

### Document IDs

Each
[`textarea_server()`](http://shikokuchuo.net/autoedit/reference/textarea_server.md)
call takes a `doc_id` parameter that identifies the collaborative
document. All sessions using the same `doc_id` will synchronize
together:

``` r
# These will sync together (same doc_id)
textarea_server("editor1", doc_id = "shared-doc")
textarea_server("editor2", doc_id = "shared-doc")

# This is independent (different doc_id)
textarea_server("editor3", doc_id = "private-doc")
```

### Initial text

The `initial_text` parameter sets the starting content for a new
document. If the document already exists (another session created it),
this parameter is ignored:

``` r
textarea_server(
 "notes",
 doc_id = "meeting",
 initial_text = "# Meeting Notes\n\nAttendees:\n- "
)
```

### Debouncing

To avoid excessive synchronization, text changes are debounced. The
default is 150ms, but you can adjust it:

``` r
# Faster sync (more responsive, more overhead)
textarea_server("fast", doc_id = "doc", debounce_ms = 50)

# Slower sync (less responsive, less overhead)
textarea_server("slow", doc_id = "doc", debounce_ms = 500)
```

## Limitations of the serverless approach

The serverless textarea module has limitations compared to the sync
server-based editor:

| Feature                  | [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) | [`textarea_ui()`](http://shikokuchuo.net/autoedit/reference/textarea_ui.md) |
|--------------------------|-------------------------------------------------------------------|-----------------------------------------------------------------------------|
| Cursor preserved on sync | Yes                                                               | No                                                                          |
| Syntax highlighting      | Yes                                                               | No                                                                          |
| Multi-process scaling    | Yes                                                               | No                                                                          |
| Document persistence     | Yes                                                               | No                                                                          |
| External server required | Yes                                                               | No                                                                          |
| Setup complexity         | Moderate                                                          | Minimal                                                                     |

### Why the cursor jumps

The textarea module uses Automerge efficiently at the CRDT layer - only
deltas (individual character insertions and deletions) are synchronized
between documents. However, HTML `<textarea>` elements have no API for
granular text updates. The only way to update a textarea
programmatically is to replace its entire `.value` property.

This means that when another user’s changes arrive:

1.  Automerge efficiently merges just the changed operations
2.  The merged text is extracted as a full string
3.  The textarea value is replaced entirely
4.  The cursor position is lost

For truly smooth concurrent editing with cursor preservation, you need
an editor with a proper document model that can apply operations
incrementally - which is exactly what
[`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) with
CodeMirror provides.

### Single process limitation

Synchronization only works within a single R process. If you run
multiple Shiny processes (e.g., behind a load balancer), sessions on
different processes won’t sync. For multi-process deployments, use
[`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) with a
sync server.

### No persistence

Documents are stored in memory and lost when the R process restarts. For
persistent collaboration, use
[`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) with a
sync server that supports document storage.

## When to use each approach

### Use `editor()` with a sync server when:

- Multiple users will type simultaneously
- You need syntax highlighting
- You need document persistence
- You’re deploying across multiple processes
- Smooth cursor behavior is important

### Use `textarea_ui()` / `textarea_server()` when:

- You want zero external dependencies
- Collaboration is light (turn-taking rather than simultaneous typing)
- The occasional cursor jump is acceptable
- You’re building a quick prototype
