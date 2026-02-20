# Collaborative Shiny Apps

This vignette demonstrates how to make an entire Shiny app collaborative
using
[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md).
Every connected user shares the same input state and sees the same
output — no sync server required.

## The idea

A standard Shiny app gives each user an independent session. User A’s
slider has no connection to User B’s slider.
[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
changes this by storing every input value in a shared Automerge
document. When one user changes a control, the new value is propagated
to all other sessions automatically.

This works well for any app where the inputs are standard Shiny widgets
(sliders, dropdowns, numeric inputs, checkboxes, radio buttons, text
inputs) and the goal is a shared view of the same output.

## Basic example

A single line in the server function makes the app collaborative:

``` r
library(shiny)
library(autoedit)

ui <- fluidPage(
  titlePanel("Collaborative Distribution Viewer"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dist", "Distribution",
        c("Normal", "Uniform", "Exponential")),
      sliderInput("n", "Observations", 10, 500, 100),
      checkboxInput("density", "Show density curve", FALSE)
    ),
    mainPanel(
      plotOutput("plot")
    )
  )
)

server <- function(input, output, session) {
  sync_inputs()

  output$plot <- renderPlot({
    data <- switch(input$dist,
      Normal = rnorm(input$n),
      Uniform = runif(input$n),
      Exponential = rexp(input$n)
    )
    hist(data, main = input$dist, col = "steelblue", border = "white",
         probability = input$density)
    if (input$density) lines(density(data), col = "red", lwd = 2)
  })
}

shinyApp(ui, server)
```

Open two browser tabs pointing to the app. Move the slider in one tab —
the other tab’s slider moves to match and both plots update together.

## How it works

[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
sets up three things in the current session:

1.  **A shared Automerge document** — The entire input state is stored
    as a flat map:
    `{"xcol": "Sepal.Length", "ycol": "Sepal.Width", "clusters": 3}`. A
    master copy lives in a package-level environment shared by all
    sessions in the same R process. Each session maintains a local copy
    that syncs incrementally with the master using Automerge’s sync
    protocol.

2.  **An observer for local changes** — Watches
    `reactiveValuesToList(input)` for changes. When a user moves a
    slider, the new value is written to the local Automerge document and
    synced to the master. A reactive version counter notifies other
    sessions.

3.  **A handler for remote changes** — When the master version bumps
    (another session changed something), the local document syncs, reads
    the new values, and pushes them to the browser. A JavaScript message
    handler calls Shiny’s input binding `receiveMessage()` method to
    update each widget — the same mechanism that
    [`updateSliderInput()`](https://rdrr.io/pkg/shiny/man/updateSliderInput.html)
    etc. use internally.

Feedback loops are suppressed by tracking known values: when a remote
update sets an input to a new value, the resulting echo from the browser
is recognised and skipped.

## Controlling which inputs sync

By default, all scalar inputs (string, numeric, logical) are
synchronized. Inputs starting with `.` (Shiny internals) are always
excluded.

Use `include` to sync only specific inputs:

``` r
# Only sync these two controls
sync_inputs(include = c("xcol", "ycol"))
```

Use `exclude` to sync everything except certain inputs:

``` r
# Sync all inputs except the action button
sync_inputs(exclude = "reset_btn")
```

Action buttons (whose values are integer click counters) are not
scalar-typed in the way
[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
checks, so they are generally excluded automatically. If you find an
input being synced that shouldn’t be, use `exclude`.

## Document IDs

The `doc_id` parameter identifies the shared state. All sessions using
the same `doc_id` see the same inputs:

``` r
# These sessions share state
sync_inputs(doc_id = "classroom-demo")

# This session is independent
sync_inputs(doc_id = "instructor-view")
```

## Persistence

By default, the shared state lives in memory and is lost when R
restarts. Pass a `path` to save the Automerge document to disk
automatically:

``` r
sync_inputs(path = "app-state.automerge")
```

The document is saved after every change (223 bytes for a typical
3-input app) and reloaded on the next startup. Users reconnect and pick
up exactly where they left off.

This works because the Automerge document is self-contained — it holds
every input value in a single binary blob via
[`am_save()`](https://posit-dev.github.io/automerge-r/reference/am_save.html)
/
[`am_load()`](https://posit-dev.github.io/automerge-r/reference/am_load.html).

## When to use sync_inputs() vs other approaches

| Scenario                                  | Recommendation                                                                                                                                            |
|:------------------------------------------|:----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Shared controls for a visualization       | [`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)                                                                               |
| Collaborative text editing                | [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md) with sync server                                                                        |
| Collaborative task tracking               | [`kanban_ui()`](http://shikokuchuo.net/autoedit/reference/kanban_ui.md) / [`kanban_server()`](http://shikokuchuo.net/autoedit/reference/kanban_server.md) |
| Mix of shared controls and free-form text | [`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md) + [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md)           |

[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
is designed for the common case where a group of people want to look at
the same dashboard and have anyone be able to drive the controls. It
treats each input as an atomic value with last-write-wins semantics,
which is appropriate for controls like sliders and dropdowns where
“merging” two values is not meaningful.

## Replay

[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)
records every input change as an Automerge commit with a descriptive
message and timestamp. The replay module lets you step through this
history, reconstructing the exact app state at each point.

Add
[`replay_ui()`](http://shikokuchuo.net/autoedit/reference/replay_ui.md)
to your UI and
[`replay_server()`](http://shikokuchuo.net/autoedit/reference/replay_server.md)
to your server:

``` r
library(shiny)
library(autoedit)

ui <- fluidPage(
  titlePanel("Collaborative Distribution Viewer"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dist", "Distribution",
        c("Normal", "Uniform", "Exponential")),
      sliderInput("n", "Observations", 10, 500, 100)
    ),
    mainPanel(
      plotOutput("plot"),
      replay_ui("timeline")
    )
  )
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

The timeline slider shows one position per meaningful change (init
commits from new sessions are filtered out). Dragging the slider
reconstructs the document at that step and pushes the values to all
widgets, so the plot updates to match. While the slider is not at the
latest step, live syncing is paused — moving the slider to the end
resumes normal operation.

The step buttons (first, previous, next, last) navigate one commit at a
time. The play button animates through the history automatically.

### Customisation

[`replay_ui()`](http://shikokuchuo.net/autoedit/reference/replay_ui.md)
accepts two styling parameters:

- `show_messages` — Display the commit message for each step (default
  `TRUE`). Messages describe what changed, e.g. `"dist: Exponential"` or
  `"n: 250"`.
- `playback_ms` — Milliseconds between steps during animated playback
  (default `1000`).

Pass matching values to
[`replay_server()`](http://shikokuchuo.net/autoedit/reference/replay_server.md):

``` r
replay_ui("timeline", show_messages = FALSE, playback_ms = 500)
replay_server("timeline", replaying = replaying,
              show_messages = FALSE, playback_ms = 500)
```

## Limitations

- **Single R process only** — The shared state lives in memory. For
  multi-process deployments (e.g., multiple Shiny Server workers), use
  an external sync server with
  [`editor()`](http://shikokuchuo.net/autoedit/reference/editor.md)
  instead.

- **Scalar values only** — Complex inputs like file uploads, data table
  selections, and plot brush events are not synchronized. Only length-1
  character, numeric, and logical values are synced.
