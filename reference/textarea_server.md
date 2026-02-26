# Collaborative textarea server

Server logic for a collaborative textarea that synchronizes across Shiny
sessions using Automerge CRDT.

## Usage

``` r
textarea_server(id, doc_id = "default", initial_text = "", debounce_ms = 150)
```

## Arguments

- id:

  Module ID (must match the ID used in
  [`textarea_ui()`](http://shikokuchuo.net/shinysync/reference/textarea_ui.md)).

- doc_id:

  Document identifier. All textareas with the same `doc_id` synchronize
  together. Default is `"default"`.

- initial_text:

  Initial text content. Only used when creating a new document; ignored
  if the document already exists.

- debounce_ms:

  Debounce delay in milliseconds for text input changes. Default is
  150ms.

## Value

A reactive expression returning the current synchronized text.

## Details

This module uses Shiny's reactive system to synchronize text across
multiple browser sessions without requiring an external sync server.
Each session maintains a local Automerge document that syncs with a
shared master document using Automerge's sync protocol.

Concurrent edits are automatically merged using Automerge's CRDT
algorithm, ensuring eventual consistency across all sessions.

## See also

Other textarea:
[`textarea_ui()`](http://shikokuchuo.net/shinysync/reference/textarea_ui.md)

## Examples

``` r
if (interactive()) {
  ui <- shiny::fluidPage(textarea_ui("editor"))
  server <- function(input, output, session) textarea_server("editor")
  shiny::shinyApp(ui, server)
}
```
