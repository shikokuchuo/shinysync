# Replay timeline server

Server logic for the replay timeline module. Reads the change history
from the master Automerge document created by
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md),
reconstructs snapshots at each step, and pushes the values to widgets.

## Usage

``` r
replay_server(
  id,
  doc_id = "default",
  replaying,
  show_messages = TRUE,
  playback_ms = 1000
)
```

## Arguments

- id:

  Module ID (must match the ID used in
  [`replay_ui()`](http://shikokuchuo.net/shinysync/reference/replay_ui.md)).

- doc_id:

  Document identifier. Must match the `doc_id` used in
  [`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md).
  Default is `"default"`.

- replaying:

  The `reactiveVal` returned by
  [`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md).

- show_messages:

  Whether to display commit messages. Default is `TRUE`.

- playback_ms:

  Interval in milliseconds between steps during animated playback.
  Default is `1000`.

## Value

Called for side effects. Returns `NULL` invisibly.

## See also

Other sync:
[`replay_ui()`](http://shikokuchuo.net/shinysync/reference/replay_ui.md),
[`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(
    shiny::selectInput("dist", "Distribution",
      c("Normal", "Uniform", "Exponential")),
    shiny::sliderInput("n", "Observations", 10, 500, 100),
    shiny::plotOutput("plot"),
    replay_ui("timeline")
  )
  server <- function(input, output, session) {
    replaying <- sync_inputs()
    replay_server("timeline", replaying = replaying)
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
