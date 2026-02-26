# Synchronize Shiny inputs across sessions

Makes Shiny inputs collaborative by synchronizing their values across
all connected sessions using Automerge CRDT, without requiring an
external sync server.

## Usage

``` r
sync_inputs(
  session = shiny::getDefaultReactiveDomain(),
  doc_id = "default",
  include = NULL,
  exclude = NULL,
  path = NULL
)
```

## Arguments

- session:

  The Shiny session object. Default uses
  [`shiny::getDefaultReactiveDomain()`](https://rdrr.io/pkg/shiny/man/domains.html).

- doc_id:

  Document identifier string. All sessions using the same `doc_id` share
  synchronized input state. Default is `"default"`.

- include:

  Optional character vector of input IDs to synchronize. If `NULL`
  (default), all eligible inputs are synchronized.

- exclude:

  Optional character vector of input IDs to exclude from
  synchronization. Applied after `include`.

- path:

  Optional file path for persistent state. When provided, the Automerge
  document is saved to this file after every change and reloaded
  automatically when the app restarts. Set to `NULL` (default) for
  in-memory only.

## Value

A `reactiveVal` (logical). `FALSE` during normal operation, `TRUE`
during replay. Can be ignored if replay is not used. Called primarily
for side effects.

## Details

Call this function once in your Shiny server logic to enable
collaborative input synchronization. Scalar string, numeric, and logical
input values are synchronized automatically. Complex inputs (file
uploads, action buttons, data table selections, etc.) are excluded by
default.

When a user changes an input, the new value is propagated to all other
connected sessions. The entire app state is stored in a single Automerge
document, providing automatic conflict resolution via CRDT.

Inputs with names starting with `"."` (Shiny internal inputs) are always
excluded.

### Persistence

When `path` is provided, the shared document is saved to disk (via
[`automerge::am_save()`](https://posit-dev.github.io/automerge-r/reference/am_save.html))
after every change. On the next app startup, the document is loaded from
disk and all sessions resume from the saved state. This makes the shared
input state survive R process restarts.

## Note

This function synchronizes sessions within a single R process. For
multi-process deployments, use an external sync server with the
[`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md)
widget instead.

## See also

Other sync:
[`replay_server()`](http://shikokuchuo.net/shinysync/reference/replay_server.md),
[`replay_ui()`](http://shikokuchuo.net/shinysync/reference/replay_ui.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(
    shiny::selectInput("dist", "Distribution",
      c("Normal", "Uniform", "Exponential")),
    shiny::sliderInput("n", "Observations", 10, 500, 100),
    shiny::plotOutput("plot")
  )
  server <- function(input, output, session) {
    sync_inputs()
    output$plot <- shiny::renderPlot(
      hist(switch(input$dist,
        Normal = rnorm(input$n),
        Uniform = runif(input$n),
        Exponential = rexp(input$n)
      ))
    )
  }
  shiny::shinyApp(ui, server)
}
```
