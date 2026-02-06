# Sync-server-free collaborative checklist module

# Private environment to store master documents per doc_id
.master_checklists <- new.env(parent = emptyenv())

#' Get or create master checklist state
#' @noRd
get_checklist_state <- function(doc_id) {
  if (!exists(doc_id, envir = .master_checklists)) {
    doc <- automerge::am_create()
    automerge::am_put(doc, automerge::AM_ROOT, "items", automerge::am_list())
    automerge::am_commit(doc, "init")
    .master_checklists[[doc_id]] <- shiny::reactiveValues(
      doc = doc,
      version = 0L
    )
  }
  .master_checklists[[doc_id]]
}

#' Generate a short unique ID
#' @noRd
generate_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d%H%M%S"),
    sprintf("%04x", sample.int(65535L, 1L))
  )
}

#' Collaborative checklist UI
#'
#' Creates a checklist input that synchronizes across Shiny sessions using
#' Automerge CRDT, without requiring an external sync server.
#'
#' @param id Module ID.
#' @param width The width of the checklist container (e.g., `"100%"`, `"400px"`).
#'
#' @return A Shiny UI element.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(checklist_ui("tasks"))
#'   server <- function(input, output, session) checklist_server("tasks")
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family checklist
#' @export
checklist_ui <- function(id, width = "100%") {
  ns <- shiny::NS(id)
  shiny::div(
    style = sprintf("width: %s;", width),
    shiny::div(
      style = "display: flex; gap: 8px; align-items: center;",
      shiny::div(
        style = "flex: 1;",
        shiny::textInput(ns("new_item"), label = NULL, placeholder = "Add new item...")
      ),
      shiny::div(
        style = "margin-bottom: 15px;",
        shiny::actionButton(ns("add_btn"), "Add", class = "btn-primary btn-sm")
      )
    ),
    shiny::uiOutput(ns("items_list"))
  )
}

#' Collaborative checklist server
#'
#' Server logic for a collaborative checklist that synchronizes across Shiny
#' sessions using Automerge CRDT.
#'
#' @param id Module ID (must match the ID used in [checklist_ui()]).
#' @param doc_id Document identifier. All checklists with the same `doc_id`
#'   synchronize together. Default is `"default"`.
#' @param initial_items Optional character vector of initial items. Only used
#'   when creating a new document; ignored if the document already exists.
#'
#' @return A reactive expression returning a data frame with columns `id`,
#'   `text`, and `done`.
#'
#' @details
#' This module uses Shiny's reactive system to synchronize a checklist across
#' multiple browser sessions without requiring an external sync server.
#' Each session maintains a local Automerge document that syncs with a
#' shared master document using Automerge's sync protocol.
#'
#' Concurrent operations (adding items, toggling checkboxes, deleting items)
#' are automatically merged using Automerge's CRDT algorithm, ensuring
#' eventual consistency across all sessions.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     shiny::h3("Shared Shopping List"),
#'     checklist_ui("shopping")
#'   )
#'   server <- function(input, output, session) {
#'     checklist_server("shopping", initial_items = c("Milk", "Bread", "Eggs"))
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family checklist
#' @export
checklist_server <- function(id, doc_id = "default", initial_items = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    master_state <- get_checklist_state(doc_id)

    # Initialize master with initial_items if empty
    shiny::isolate({
      if (!is.null(initial_items) && length(initial_items) > 0L) {
        items_obj <- automerge::am_get(
          master_state$doc,
          automerge::AM_ROOT,
          "items"
        )
        if (automerge::am_length(master_state$doc, items_obj) == 0L) {
          for (i in seq_along(initial_items)) {
            # Insert a new map at position i (1-indexed)
            automerge::am_insert(
              master_state$doc,
              items_obj,
              i,
              automerge::am_map()
            )
            # Get the newly inserted map and set its properties
            item <- automerge::am_get(master_state$doc, items_obj, i)
            automerge::am_put(master_state$doc, item, "id", generate_id())
            automerge::am_put(master_state$doc, item, "text", initial_items[i])
            automerge::am_put(master_state$doc, item, "done", FALSE)
          }
          automerge::am_commit(master_state$doc, "initial items")
          master_state$version <- master_state$version + 1L
        }
      }
    })

    # Per-session sync states
    sync_local <- automerge::am_sync_state_new()
    sync_master <- automerge::am_sync_state_new()

    # Create local document and sync with master
    local_doc <- shiny::isolate({
      doc <- automerge::am_create()
      automerge::am_put(doc, automerge::AM_ROOT, "items", automerge::am_list())
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

    # Get items from local doc as a list
    get_items <- function() {
      items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
      n <- automerge::am_length(local_doc, items_obj)
      if (n == 0L) {
        return(list())
      }
      lapply(seq_len(n), function(i) {
        item <- automerge::am_get(local_doc, items_obj, i)
        list(
          id = automerge::am_get(local_doc, item, "id"),
          text = automerge::am_get(local_doc, item, "text"),
          done = automerge::am_get(local_doc, item, "done")
        )
      })
    }

    # Local reactive for tracking current items (start empty)
    local_items <- shiny::reactiveVal(list())

    # Initial sync and populate local_items after flush
    shiny::isolate(incremental_sync())
    session$onFlushed(function() {
      local_items(get_items())
    }, once = TRUE)

    # Sync with master and optionally bump version
    sync_with_master <- function() {
      result <- incremental_sync()
      if (result$pushed) {
        master_state$version <- master_state$version + 1L
      }
      if (result$pulled || result$pushed) {
        local_items(get_items())
      }
      result$pulled
    }

    # Add new item
    shiny::observeEvent(input$add_btn, {
      text <- trimws(input$new_item)
      if (nzchar(text)) {
        items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
        n <- automerge::am_length(local_doc, items_obj)

        # Insert a new map at position n+1 (1-indexed, at end)
        pos <- n + 1L
        automerge::am_insert(local_doc, items_obj, pos, automerge::am_map())
        item <- automerge::am_get(local_doc, items_obj, pos)
        automerge::am_put(local_doc, item, "id", generate_id())
        automerge::am_put(local_doc, item, "text", text)
        automerge::am_put(local_doc, item, "done", FALSE)
        automerge::am_commit(local_doc, paste("Add:", text))

        shiny::updateTextInput(session, "new_item", value = "")
        sync_with_master()
      }
    })

    # Toggle item done status
    shiny::observeEvent(input$toggle_item, {
      item_id <- input$toggle_item
      items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
      n <- automerge::am_length(local_doc, items_obj)

      for (i in seq_len(n)) {
        item <- automerge::am_get(local_doc, items_obj, i)
        if (identical(automerge::am_get(local_doc, item, "id"), item_id)) {
          current <- automerge::am_get(local_doc, item, "done")
          automerge::am_put(local_doc, item, "done", !current)
          automerge::am_commit(local_doc, paste("Toggle:", item_id))
          sync_with_master()
          break
        }
      }
    })

    # Delete item
    shiny::observeEvent(input$delete_item, {
      item_id <- input$delete_item
      items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
      n <- automerge::am_length(local_doc, items_obj)

      for (i in seq_len(n)) {
        item <- automerge::am_get(local_doc, items_obj, i)
        if (identical(automerge::am_get(local_doc, item, "id"), item_id)) {
          automerge::am_delete(local_doc, items_obj, i)
          automerge::am_commit(local_doc, paste("Delete:", item_id))
          sync_with_master()
          break
        }
      }
    })

    # React to master version changes (from other sessions)
    shiny::observeEvent(master_state$version, {
      sync_with_master()
    }, ignoreInit = TRUE)

    # Render the items list
    output$items_list <- shiny::renderUI({
      items <- local_items()

      if (length(items) == 0L) {
        return(shiny::p(
          style = "color: #888; font-style: italic;",
          "No items yet. Add one above!"
        ))
      }

      shiny::tagList(
        lapply(items, function(item) {
          checkbox_id <- paste0("check_", item$id)
          shiny::div(
            style = paste(
              "display: flex; align-items: center; gap: 8px;",
              "padding: 8px; border-bottom: 1px solid #eee;"
            ),
            shiny::tags$input(
              type = "checkbox",
              checked = if (item$done) "checked" else NULL,
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                ns("toggle_item"),
                item$id
              ),
              style = "width: 18px; height: 18px; cursor: pointer;"
            ),
            shiny::span(
              style = if (item$done) {
                "flex: 1; text-decoration: line-through; color: #888;"
              } else {
                "flex: 1;"
              },
              item$text
            ),
            shiny::tags$button(
              type = "button",
              class = "btn btn-sm btn-outline-danger",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                ns("delete_item"),
                item$id
              ),
              "\u00d7"
            )
          )
        })
      )
    })

    # Return reactive with current items as data frame
    shiny::reactive({
      items <- local_items()
      if (length(items) == 0L) {
        data.frame(id = character(), text = character(), done = logical())
      } else {
        data.frame(
          id = vapply(items, `[[`, character(1L), "id"),
          text = vapply(items, `[[`, character(1L), "text"),
          done = vapply(items, `[[`, logical(1L), "done")
        )
      }
    })
  })
}
