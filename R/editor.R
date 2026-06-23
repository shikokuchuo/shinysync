# Collaborative text editor widget

#' Collaborative text editor widget
#'
#' Creates a real-time collaborative text editor using CodeMirror 6 and
#' Automerge CRDT, synchronized via WebSocket to an automerge-repo compatible
#' sync server.
#'
#' @param server_url WebSocket URL (ws:// or wss://) of the sync server.
#' @param doc_id Document ID (base58check encoded).
#' @param timeout Connection timeout in milliseconds. Default 10000.
#' @param width,height Widget dimensions.
#'
#' @return An htmlwidget object.
#'
#' @details
#' The widget connects to the specified sync server and synchronizes
#' a CodeMirror 6 editor with an Automerge document. Multiple users can
#' edit the same document simultaneously with automatic conflict resolution.
#'
#' The Automerge document must have a "text" field of type Automerge text
#' (created with `automerge::am_text()`).
#'
#' In Shiny applications, the current editor content is available as an
#' input value at `input$<outputId>_content`.
#'
#' @examples
#' \dontrun{
#' # Connect to the public Automerge sync server
#' editor("wss://sync.automerge.org", "your-document-id")
#'
#' # Or use with an autosync server
#' server <- autosync::sync_server(port = 3030)
#' server$start()
#'
#' doc_id <- autosync::create_document(server)
#' doc <- autosync::get_document(server, doc_id)
#' automerge::am_put(doc, automerge::AM_ROOT, "text", automerge::am_text(""))
#' automerge::am_commit(doc, "init")
#'
#' editor(server$url, doc_id)
#' }
#'
#' @export
editor <- function(server_url, doc_id, timeout = 10000,
                   width = "100%", height = "400px") {
  htmlwidgets::createWidget(
    name = "shinysyncEditor",
    x = list(serverUrl = server_url, docId = doc_id, timeout = timeout),
    width = width,
    height = height,
    package = "shinysync"
  )
}

#' Shiny bindings for editor
#'
#' Output and render functions for using editor within Shiny
#' applications and interactive R Markdown documents.
#'
#' @param outputId Output variable to read from.
#' @param width,height Widget dimensions (must be valid CSS unit or a number
#'   which will be coerced to a string and have "px" appended).
#' @param expr An expression that generates an editor widget.
#' @param env The environment in which to evaluate `expr`.
#' @param quoted Logical, whether `expr` is a quoted expression.
#'
#' @return `editor_output()` returns a Shiny output element.
#'   `editor_render()` returns a Shiny render function.
#'
#' @name editor-shiny
#'
#' @export
editor_output <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(outputId, "shinysyncEditor", width, height,
                                  package = "shinysync")
}

#' @rdname editor-shiny
#' @export
editor_render <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(expr, editor_output, env, quoted = TRUE)
}
