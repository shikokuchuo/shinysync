# Collaborative Meeting Notes App

This vignette demonstrates how to build a collaborative meeting notes
application using the
[`textarea_ui()`](http://shikokuchuo.net/autoedit/reference/textarea_ui.md)
and
[`textarea_server()`](http://shikokuchuo.net/autoedit/reference/textarea_server.md)
functions from autoedit. These functions provide real-time multi-user
text synchronization without requiring an external sync server. \## How
it works

The textarea module uses Automerge CRDT (Conflict-free Replicated Data
Type) to synchronize text across multiple browser sessions. Key
features: - **No external server required**: Synchronization happens
in-process via Shiny’s reactive system - **Automatic conflict
resolution**: Concurrent edits from multiple users are merged
automatically - **Room-based organization**: Use different `doc_id`
values to create separate collaborative spaces

## Running the app

To run this example, you need the autoedit package installed:

``` r
# install.packages("pak")
pak::pak("shikokuchuo/autoedit")
```

Then run the app below. Open multiple browser windows or tabs pointing
to the same Shiny app URL to see real-time collaboration in action.

## Complete application code

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
       downloadButton("export", "Export as Markdown", class = "btn-sm")
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
       div(
         id = "standup-panel",
         textarea_ui(
           "notes_standup",
           label = NULL,
           width = "100%",
           height = "500px",
           placeholder = "Start typing your standup notes..."
         )
       ),
       div(
         id = "planning-panel",
         style = "display: none;",
         textarea_ui(
           "notes_planning",
           label = NULL,
           width = "100%",
           height = "500px",
           placeholder = "Start typing your planning notes..."
         )
       ),
       div(
         id = "retrospective-panel",
         style = "display: none;",
         textarea_ui(
           "notes_retrospective",
           label = NULL,
           width = "100%",
           height = "500px",
           placeholder = "Start typing your retrospective notes..."
         )
       ),
       div(
         id = "brainstorm-panel",
         style = "display: none;",
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

 # Toggle panel visibility based on selected room
 observeEvent(input$room, {
   all_rooms <- c("standup", "planning", "retrospective", "brainstorm")
   for (room in all_rooms) {
     panel_id <- paste0(room, "-panel")
     if (room == input$room) {
       shinyjs_show <- sprintf(
         "$('#%s').show();",
         panel_id
       )
     } else {
       shinyjs_show <- sprintf(
         "$('#%s').hide();",
         panel_id
       )
     }
     session$sendCustomMessage("toggle_panel", list(
       id = panel_id,
       show = room == input$room
     ))
   }
 })

 # Add custom message handler for panel toggling
 session$onFlushed(function() {
   session$sendCustomMessage(
     type = "register_toggle",
     message = list()
   )
 }, once = TRUE)

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
     paste0(input$room, "-notes-", Sys.Date(), ".md")
   },
   content = function(file) {
     writeLines(current_text(), file)
   }
 )
}

# UI must include the JavaScript for panel toggling
ui <- tagList(
 tags$head(
   tags$script(HTML("
     Shiny.addCustomMessageHandler('toggle_panel', function(msg) {
       if (msg.show) {
         $('#' + msg.id).show();
       } else {
         $('#' + msg.id).hide();
       }
     });
   "))
 ),
 ui
)

shinyApp(ui, server)
```

## Key concepts

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

## Limitations

The serverless textarea module has some limitations compared to the
WebSocket-based editor:

1.  **Single process only**: Synchronization only works within a single
    R process. If you run multiple Shiny processes (e.g., behind a load
    balancer), sessions on different processes won’t sync.

2.  **No persistence**: Documents are stored in memory and lost when the
    R process restarts. For persistent collaboration, use the
    [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md)
    widget with an external sync server.

3.  **No syntax highlighting**: The textarea is a plain text input. For
    code editing with syntax highlighting, use
    [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md).

For production deployments requiring persistence or multi-process
scaling, see the CodeMirror editor vignette.
