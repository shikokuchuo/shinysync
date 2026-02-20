# Replay timeline UI

Creates a timeline control for replaying the history of synchronized
inputs recorded by
[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md).

## Usage

``` r
replay_ui(id, show_messages = TRUE, playback_ms = 1000)
```

## Arguments

- id:

  Module ID.

- show_messages:

  Whether to display commit messages below the timeline. Default is
  `TRUE`.

- playback_ms:

  Interval in milliseconds between steps during animated playback.
  Default is `1000`.

## Value

A Shiny UI element.

## See also

Other sync:
[`replay_server()`](http://shikokuchuo.net/autoedit/reference/replay_server.md),
[`sync_inputs()`](http://shikokuchuo.net/autoedit/reference/sync_inputs.md)

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
