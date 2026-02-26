# Collaborative textarea UI

Creates a textarea input that synchronizes across Shiny sessions using
Automerge CRDT, without requiring an external sync server.

## Usage

``` r
textarea_ui(
  id,
  label = NULL,
  width = "100%",
  height = "200px",
  placeholder = NULL
)
```

## Arguments

- id:

  Module ID.

- label:

  Label for the textarea, or `NULL` for no label.

- width:

  The width of the input (e.g., `"100%"`, `"400px"`).

- height:

  The height of the input (e.g., `"200px"`).

- placeholder:

  Placeholder text when empty.

## Value

A Shiny UI element.

## See also

Other textarea:
[`textarea_server()`](http://shikokuchuo.net/shinysync/reference/textarea_server.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(textarea_ui("editor"))
  server <- function(input, output, session) textarea_server("editor")
  shiny::shinyApp(ui, server)
}
```
