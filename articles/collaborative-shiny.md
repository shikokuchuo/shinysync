# Collaborative Shiny Apps

This vignette demonstrates how to make an entire Shiny app collaborative
using
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md).
Every connected user shares the same input state and sees the same
output — no sync server required.

## The idea

A standard Shiny app gives each user an independent session. User A’s
dropdown has no connection to User B’s dropdown.
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)
changes this by storing every input value in a shared Automerge
document. When one user changes a control, the new value is propagated
to all other sessions automatically.

This works well for any app where the inputs are standard Shiny widgets
(sliders, dropdowns, numeric inputs, checkboxes, radio buttons, text
inputs) and the goal is a shared view of the same output.

## Example

The following app performs k-means clustering on the `iris` dataset.
Adding
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)
to the server makes it collaborative. The `path` argument enables
persistence across restarts, and the
[`replay_ui()`](http://shikokuchuo.net/shinysync/reference/replay_ui.md)
/
[`replay_server()`](http://shikokuchuo.net/shinysync/reference/replay_server.md)
module adds a timeline for stepping through the history of changes —
both are optional.

``` r
library(shiny)
library(shinysync)

vars <- names(iris)[1:4]

ui <- fluidPage(
  titlePanel("Collaborative Data Explorer"),
  sidebarLayout(
    sidebarPanel(
      selectInput("xcol", "X Variable", vars),
      selectInput("ycol", "Y Variable", vars, selected = vars[2]),
      numericInput("clusters", "Clusters", 3, min = 1, max = 9)
    ),
    mainPanel(
      plotOutput("plot"),
      replay_ui("timeline")
    )
  )
)

server <- function(input, output, session) {
  replaying <- sync_inputs(path = "explorer.automerge")
  replay_server("timeline", replaying = replaying)

  output$plot <- renderPlot({
    d <- iris[, c(input$xcol, input$ycol)]
    cl <- kmeans(d, input$clusters)
    plot(d, col = cl$cluster, pch = 19,
      main = paste(input$clusters, "clusters"))
    points(cl$centers, pch = 4, cex = 3, lwd = 3)
  })
}

shinyApp(ui, server)
```

Open two browser tabs pointing to the app. Change the X variable in one
tab — the other tab’s dropdown updates and the plot redraws. Every
control is synchronized: switch to petal dimensions, increase the
cluster count, and all sessions follow.

## How it works

[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)
sets up three things in the current session:

1.  **A shared Automerge document** — The entire input state is stored
    as a flat map:
    `{"xcol": "Sepal.Length", "ycol": "Sepal.Width", "clusters": 3}`. A
    master copy lives in a package-level environment shared by all
    sessions in the same R process. Each session maintains a local copy
    that syncs incrementally with the master using Automerge’s sync
    protocol.

2.  **An observer for local changes** — Watches
    `reactiveValuesToList(input)` for changes. When a user changes a
    dropdown, the new value is written to the local Automerge document
    and synced to the master. A reactive version counter notifies other
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
# Only sync the variable selectors, not the cluster count
sync_inputs(include = c("xcol", "ycol"))
```

Use `exclude` to sync everything except certain inputs:

``` r
# Sync all inputs except the action button
sync_inputs(exclude = "reset_btn")
```

Action buttons (whose values are integer click counters) are not
scalar-typed in the way
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)
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

This lets a single app deployment serve multiple groups simultaneously,
each with its own synchronized state.

## Persistence

By default, the shared state lives in memory and is lost when R
restarts. The `path` argument (shown in the example as
`sync_inputs(path = "explorer.automerge")`) saves the Automerge document
to disk after every change and reloads it on the next startup. Users
reconnect and pick up exactly where they left off.

The Automerge document is self-contained — it holds every input value in
a single binary blob via
[`am_save()`](https://posit-dev.github.io/automerge-r/reference/am_save.html)
/
[`am_load()`](https://posit-dev.github.io/automerge-r/reference/am_load.html).

## Replay

Every input change is recorded as an Automerge commit with a descriptive
message and timestamp. The replay module (shown in the example as
`replay_ui("timeline")` / `replay_server("timeline", ...)`) lets you
step through this history, reconstructing the exact app state at each
point.

The timeline slider shows one position per meaningful change (init
commits from new sessions are filtered out). Dragging the slider
reconstructs the document at that step and pushes the values to all
widgets — the plot redraws to match. Commit messages narrate the
exploration: `"xcol: Petal.Length"`, `"clusters: 5"`. While the slider
is not at the latest step, live syncing is paused — moving to the end
resumes normal operation.

The step buttons (first, previous, next, last) navigate one commit at a
time. The play button animates through the history automatically.
Pressing play on a session where the team explored sepal dimensions with
3 clusters, then switched to petal dimensions and increased to 5
clusters, replays the entire analytical path as a narrated sequence.

### Customisation

[`replay_ui()`](http://shikokuchuo.net/shinysync/reference/replay_ui.md)
accepts two styling parameters:

- `show_messages` — Display the commit message for each step (default
  `TRUE`). Messages describe what changed, e.g. `"xcol: Petal.Length"`
  or `"clusters: 5"`.
- `playback_ms` — Milliseconds between steps during animated playback
  (default `1000`).

Pass matching values to
[`replay_server()`](http://shikokuchuo.net/shinysync/reference/replay_server.md):

``` r
replay_ui("timeline", show_messages = FALSE, playback_ms = 500)
replay_server("timeline", replaying = replaying,
              show_messages = FALSE, playback_ms = 500)
```

## Use cases

### Shared dashboard driving

The primary use case. A team opens the same app during a meeting, and
anyone can drive the controls. Everyone sees the same plot update in
real time — useful for group analysis sessions, classroom
demonstrations, and pair exploration.

### Persistent analysis state

With `path`, a solo analyst can close and reopen the app without losing
their variable selections and parameter settings.

### Audit trail and provenance

Every input change is a timestamped commit in the Automerge document
history. For reproducible research or regulated environments, this
provides a complete record of how the analysis was configured at every
point. Combined with the replay module, the full sequence of analyst
decisions is browsable after the fact.

### Training and onboarding

An instructor configures a dashboard, stepping through a series of
analytical choices. Later, a student uses the replay timeline to walk
through the instructor’s exploration step by step. The commit messages
narrate each decision, and the outputs update to match.

### Multiple independent rooms

Using `doc_id`, a single app deployment can serve multiple groups
simultaneously — each with its own synchronized state, similar to how
collaborative documents use share links.

## When to use sync_inputs() vs other approaches

| Scenario                                  | Recommendation                                                                                                                                              |
|:------------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Shared controls for a visualization       | [`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)                                                                                |
| Collaborative text editing                | [`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md) with sync server                                                                         |
| Collaborative task tracking               | [`kanban_ui()`](http://shikokuchuo.net/shinysync/reference/kanban_ui.md) / [`kanban_server()`](http://shikokuchuo.net/shinysync/reference/kanban_server.md) |
| Mix of shared controls and free-form text | [`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md) + [`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md)           |

[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)
is designed for the common case where a group of people want to look at
the same dashboard and have anyone be able to drive the controls. It
treats each input as an atomic value with last-write-wins semantics,
which is appropriate for controls like dropdowns and numeric inputs
where “merging” two values is not meaningful.

## Limitations

- **Single R process only** — The shared state lives in memory and we do
  not use an external sync server.

- **Scalar values only** — Complex inputs like file uploads, data table
  selections, and plot brush events are not synchronized. Only length-1
  character, numeric, and logical values are synced.
