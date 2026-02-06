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
library(bslib)
library(autoedit)
library(autosync)
library(automerge)

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
for (room in names(room_templates)) {
  doc_ids[[room]] <- create_document(sync_server)
  doc <- get_document(sync_server, doc_ids[[room]])
  am_put(doc, AM_ROOT, "text", am_text(room_templates[[room]]))
  am_commit(doc, "init")
}

ui <- page_fillable(
  padding = "1rem",
  div(class = "d-flex justify-content-between align-items-center mb-3",
    h2("Collaborative Meeting Notes", class = "mb-0"),
    downloadButton("export", "Export as Quarto", class = "btn-sm")
  ),
  navset_card_pill(
    id = "room",
    nav_panel("Daily Standup", value = "standup", uiOutput("editor_standup")),
    nav_panel("Sprint Planning", value = "planning", uiOutput("editor_planning")),
    nav_panel("Retrospective", value = "retrospective", uiOutput("editor_retrospective")),
    nav_panel("Brainstorming", value = "brainstorm", uiOutput("editor_brainstorm"))
  )
)

server <- function(input, output, session) {
  output$editor_standup <- renderUI(editor_output("ed_standup", height = "500px"))
  output$editor_planning <- renderUI(editor_output("ed_planning", height = "500px"))
  output$editor_retrospective <- renderUI(editor_output("ed_retrospective", height = "500px"))
  output$editor_brainstorm <- renderUI(editor_output("ed_brainstorm", height = "500px"))

  output$ed_standup <- editor_render(editor(sync_server$url, doc_ids[["standup"]], height = "500px"))
  output$ed_planning <- editor_render(editor(sync_server$url, doc_ids[["planning"]], height = "500px"))
  output$ed_retrospective <- editor_render(editor(sync_server$url, doc_ids[["retrospective"]], height = "500px"))
  output$ed_brainstorm <- editor_render(editor(sync_server$url, doc_ids[["brainstorm"]], height = "500px"))

  current_content <- reactive({
    switch(input$room,
      "standup" = input$ed_standup_content,
      "planning" = input$ed_planning_content,
      "retrospective" = input$ed_retrospective_content,
      "brainstorm" = input$ed_brainstorm_content
    )
  })

  output$export <- downloadHandler(
    filename = function() paste0(input$room, "-notes-", Sys.Date(), ".qmd"),
    content = function(file) {
      titles <- c(standup = "Daily Standup", planning = "Sprint Planning",
                  retrospective = "Retrospective", brainstorm = "Brainstorming")
      front_matter <- sprintf("---\ntitle: \"%s\"\ndate: \"%s\"\nformat: html\n---\n\n",
                              titles[input$room], Sys.Date())
      writeLines(paste0(front_matter, current_content()), file)
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
library(bslib)
library(autoedit)

# Room-specific initial content templates
room_templates <- list(
  standup = "# Daily Standup\n\n## What I did yesterday\n- \n\n## What I'm doing today\n- \n\n## Blockers\n- \n",
  planning = "# Sprint Planning\n\n## Goals\n- \n\n## User Stories\n- \n\n## Capacity\n- \n",
  retrospective = "# Retrospective\n\n## What went well\n- \n\n## What could be improved\n- \n\n## Action items\n- \n",
  brainstorm = "# Brainstorming Session\n\n## Ideas\n- \n\n## Discussion Notes\n- \n"
)

ui <- page_fillable(
  padding = "1rem",
  div(class = "d-flex justify-content-between align-items-center mb-3",
    h2("Collaborative Meeting Notes", class = "mb-0"),
    downloadButton("export", "Export as Quarto", class = "btn-sm")
  ),
  card(
    card_header(
      navset_pill(
        id = "room",
        nav_panel("Daily Standup", value = "standup"),
        nav_panel("Sprint Planning", value = "planning"),
        nav_panel("Retrospective", value = "retrospective"),
        nav_panel("Brainstorming", value = "brainstorm")
      )
    ),
    card_body(
      conditionalPanel("input.room === 'standup'",
        textarea_ui("notes_standup", label = NULL, width = "100%", height = "500px",
                    placeholder = "Start typing your standup notes...")),
      conditionalPanel("input.room === 'planning'",
        textarea_ui("notes_planning", label = NULL, width = "100%", height = "500px",
                    placeholder = "Start typing your planning notes...")),
      conditionalPanel("input.room === 'retrospective'",
        textarea_ui("notes_retrospective", label = NULL, width = "100%", height = "500px",
                    placeholder = "Start typing your retrospective notes...")),
      conditionalPanel("input.room === 'brainstorm'",
        textarea_ui("notes_brainstorm", label = NULL, width = "100%", height = "500px",
                    placeholder = "Start typing your ideas..."))
    )
  )
)

server <- function(input, output, session) {
  text_standup <- textarea_server("notes_standup", doc_id = "standup",
                                  initial_text = room_templates$standup)
  text_planning <- textarea_server("notes_planning", doc_id = "planning",
                                   initial_text = room_templates$planning)
  text_retrospective <- textarea_server("notes_retrospective", doc_id = "retrospective",
                                        initial_text = room_templates$retrospective)
  text_brainstorm <- textarea_server("notes_brainstorm", doc_id = "brainstorm",
                                     initial_text = room_templates$brainstorm)

  current_text <- reactive({
    switch(input$room,
      "standup" = text_standup(),
      "planning" = text_planning(),
      "retrospective" = text_retrospective(),
      "brainstorm" = text_brainstorm()
    )
  })

  output$export <- downloadHandler(
    filename = function() paste0(input$room, "-notes-", Sys.Date(), ".qmd"),
    content = function(file) {
      titles <- c(standup = "Daily Standup", planning = "Sprint Planning",
                  retrospective = "Retrospective", brainstorm = "Brainstorming")
      front_matter <- sprintf("---\ntitle: \"%s\"\ndate: \"%s\"\nformat: html\n---\n\n",
                              titles[input$room], Sys.Date())
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
