# Sync-server-free collaborative textarea module

# Private environment to store master documents per doc_id
.master_docs <- new.env(parent = emptyenv())

#' Get or create master document state
#' @noRd
get_master_state <- function(doc_id) {
  if (!exists(doc_id, envir = .master_docs)) {
    doc <- automerge::am_create()
    automerge::am_put(doc, automerge::AM_ROOT, "text", automerge::am_text(""))
    automerge::am_commit(doc, "init")
    .master_docs[[doc_id]] <- shiny::reactiveValues(
      doc = doc,
      version = 0L
    )
  }
  .master_docs[[doc_id]]
}

#' Collaborative textarea UI
#'
#' Creates a textarea input that synchronizes across Shiny sessions using
#' Automerge CRDT, without requiring an external sync server.
#'
#' @param id Module ID.
#' @param label Label for the textarea, or `NULL` for no label.
#' @param width The width of the input (e.g., `"100%"`, `"400px"`).
#' @param height The height of the input (e.g., `"200px"`).
#' @param placeholder Placeholder text when empty.
#'
#' @return A Shiny UI element.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(textarea_ui("editor"))
#'   server <- function(input, output, session) textarea_server("editor")
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family textarea
#' @export
textarea_ui <- function(
  id,
  label = NULL,
  width = "100%",
  height = "200px",
  placeholder = NULL
) {
  ns <- shiny::NS(id)
  shiny::textAreaInput(
    ns("text"),
    label = label,
    value = "",
    width = width,
    height = height,
    placeholder = placeholder
  )
}

#' Collaborative textarea server
#'
#' Server logic for a collaborative textarea that synchronizes across Shiny
#' sessions using Automerge CRDT.
#'
#' @param id Module ID (must match the ID used in [textarea_ui()]).
#' @param doc_id Document identifier. All textareas with the same `doc_id`
#'   synchronize together. Default is `"default"`.
#' @param initial_text Initial text content. Only used when creating a new
#'   document; ignored if the document already exists.
#' @param debounce_ms Debounce delay in milliseconds for text input changes.
#'   Default is 150ms.
#'
#' @return A reactive expression returning the current synchronized text.
#'
#' @details
#' This module uses Shiny's reactive system to synchronize text across
#' multiple browser sessions without requiring an external sync server.
#' Each session maintains a local Automerge document that syncs with a
#' shared master document using Automerge's sync protocol.
#'
#' Concurrent edits are automatically merged using Automerge's CRDT
#' algorithm, ensuring eventual consistency across all sessions.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(textarea_ui("editor"))
#'   server <- function(input, output, session) textarea_server("editor")
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family textarea
#' @export
textarea_server <- function(
  id,
  doc_id = "default",
  initial_text = "",
  debounce_ms = 150
) {
  shiny::moduleServer(id, function(input, output, session) {
    master_state <- get_master_state(doc_id)

    # Initialize master with initial_text if it's empty and initial_text provided
    shiny::isolate({
      if (nzchar(initial_text)) {
        current <- automerge::am_text_content(
          automerge::am_get(master_state$doc, automerge::AM_ROOT, "text")
        )
        if (!nzchar(current)) {
          text_obj <- automerge::am_get(
            master_state$doc,
            automerge::AM_ROOT,
            "text"
          )
          automerge::am_text_splice(text_obj, 0L, 0L, initial_text)
          automerge::am_commit(master_state$doc, "initial content")
          master_state$version <- master_state$version + 1L
        }
      }
    })

    # Per-session sync states
    sync_local <- automerge::am_sync_state()
    sync_master <- automerge::am_sync_state()

    # Create local document and sync with master
    local_doc <- shiny::isolate({
      doc <- automerge::am_create()
      automerge::am_put(doc, automerge::AM_ROOT, "text", automerge::am_text(""))
      automerge::am_commit(doc, "init")
      doc
    })

    # Incremental sync function
    incremental_sync <- function() {
      old_local_heads <- automerge::am_get_heads(local_doc)
      old_master_heads <- automerge::am_get_heads(master_state$doc)

      repeat {
        msg_to_master <- automerge::am_sync_encode(local_doc, sync_local)
        msg_to_local <- automerge::am_sync_encode(master_state$doc, sync_master)

        if (is.null(msg_to_master) && is.null(msg_to_local)) {
          break
        }

        if (!is.null(msg_to_master)) {
          automerge::am_sync_decode(
            master_state$doc,
            sync_master,
            msg_to_master
          )
        }
        if (!is.null(msg_to_local)) {
          automerge::am_sync_decode(local_doc, sync_local, msg_to_local)
        }
      }

      new_local_heads <- automerge::am_get_heads(local_doc)
      new_master_heads <- automerge::am_get_heads(master_state$doc)

      list(
        pulled = !identical(old_local_heads, new_local_heads),
        pushed = !identical(old_master_heads, new_master_heads)
      )
    }

    # Initial sync
    sync_result <- shiny::isolate(incremental_sync())
    initial_text_value <- shiny::isolate({
      automerge::am_text_content(
        automerge::am_get(local_doc, automerge::AM_ROOT, "text")
      )
    })

    # Local state
    local <- shiny::reactiveValues(
      last_text = initial_text_value
    )

    # Update textarea with initial content after flush
    session$onFlushed(
      function() {
        shiny::updateTextAreaInput(session, "text", value = initial_text_value)
      },
      once = TRUE
    )

    # Debounced text input
    text_debounced <- shiny::debounce(shiny::reactive(input$text), debounce_ms)

    # Sync with master and optionally bump version
    sync_with_master <- function() {
      shiny::isolate({
        result <- incremental_sync()

        if (result$pushed) {
          master_state$version <- master_state$version + 1L
        }

        result$pulled
      })
    }

    # Handle local text changes
    shiny::observeEvent(
      text_debounced(),
      {
        new_text <- text_debounced()

        if (is.null(new_text) || identical(new_text, local$last_text)) {
          return()
        }

        tryCatch(
          {
            # Commit changes to local doc using splice diff
            text_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "text")
            old_text <- automerge::am_text_content(text_obj)
            automerge::am_text_update(text_obj, old_text, new_text)
            automerge::am_commit(
              local_doc,
              paste("Edit at", format(Sys.time(), "%H:%M:%S"))
            )
            local$last_text <- new_text

            # Sync with master
            pulled <- sync_with_master()

            # If we pulled changes, update the textarea
            if (pulled) {
              synced_text <- automerge::am_text_content(
                automerge::am_get(local_doc, automerge::AM_ROOT, "text")
              )
              if (!identical(synced_text, new_text)) {
                shiny::updateTextAreaInput(session, "text", value = synced_text)
                local$last_text <- synced_text
              }
            }
          },
          error = function(e) {
            shiny::showNotification(
              paste("Sync error:", conditionMessage(e)),
              type = "error"
            )
          }
        )
      },
      ignoreInit = TRUE
    )

    # React to master version changes (from other sessions)
    shiny::observeEvent(
      master_state$version,
      {
        current_input <- shiny::isolate(input$text)
        has_pending <- !is.null(current_input) &&
          !identical(current_input, local$last_text)

        if (has_pending) {
          return()
        }

        pulled <- sync_with_master()
        if (pulled) {
          new_text <- automerge::am_text_content(
            automerge::am_get(local_doc, automerge::AM_ROOT, "text")
          )
          if (!identical(new_text, local$last_text)) {
            shiny::updateTextAreaInput(session, "text", value = new_text)
            local$last_text <- new_text
          }
        }
      },
      ignoreInit = TRUE
    )

    # Return reactive with current text
    shiny::reactive(local$last_text)
  })
}
