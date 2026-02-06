# Sync-server-free collaborative kanban board module

# Private environment to store master documents per doc_id
.master_kanbans <- new.env(parent = emptyenv())

#' Get or create master kanban state
#' @noRd
get_kanban_state <- function(doc_id) {
 if (!exists(doc_id, envir = .master_kanbans)) {

    doc <- automerge::am_create()
    automerge::am_put(doc, automerge::AM_ROOT, "items", automerge::am_list())
    automerge::am_commit(doc, "init")
    .master_kanbans[[doc_id]] <- shiny::reactiveValues(
      doc = doc,
      version = 0L
    )
  }
  .master_kanbans[[doc_id]]
}

#' Generate a short unique ID
#' @noRd
generate_kanban_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d%H%M%S"),
    sprintf("%04x", sample.int(65535L, 1L))
  )
}

#' Collaborative kanban board UI
#'
#' Creates a kanban board that synchronizes across Shiny sessions using
#' Automerge CRDT, without requiring an external sync server.
#'
#' @param id Module ID.
#' @param columns Named character vector defining the columns. Names are
#'   internal IDs, values are display labels. Default is
#'
#' `c(todo = "To Do", in_progress = "In Progress", done = "Done")`.
#' @param column_colors Named character vector of CSS colors for column headers.
#'   Names should match column IDs. Default provides red/yellow/green styling.
#'
#' @return A Shiny UI element.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(kanban_ui("board"))
#'   server <- function(input, output, session) kanban_server("board")
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family kanban
#' @export
kanban_ui <- function(
  id,
  columns = c(todo = "To Do", in_progress = "In Progress", done = "Done"),
  column_colors = c(
    todo = "#64748b",
    in_progress = "#3b82f6",
    done = "#22c55e"
  )
) {
  ns <- shiny::NS(id)

  # Build column UIs
  column_uis <- lapply(names(columns), function(col_id) {
    bg_color <- if (col_id %in% names(column_colors)) column_colors[[col_id]] else "#6c757d"

    shiny::div(
      style = "flex: 1; min-width: 250px; margin: 0 8px;",
      shiny::div(
        style = sprintf(
          "background-color: %s; color: white; padding: 10px 12px; font-weight: 600; border-radius: 6px 6px 0 0; font-size: 14px;",
          bg_color
        ),
        columns[[col_id]]
      ),
      shiny::div(
        style = "border: 1px solid #e2e8f0; border-top: none; min-height: 200px; background: #f8fafc; padding: 8px; border-radius: 0 0 6px 6px;",
        shiny::uiOutput(ns(paste0("col_", col_id)))
      )
    )
  })

  shiny::div(
    # Add new item input
    shiny::div(
      style = "display: flex; gap: 8px; margin-bottom: 16px; align-items: center;",
      shiny::div(
        style = "max-width: 300px;",
        shiny::textInput(ns("new_item"), label = NULL, placeholder = "Add new item...")
      ),
      shiny::div(
        style = "margin-bottom: 15px;",
        shiny::actionButton(ns("add_btn"), "Add", class = "btn-primary btn-sm")
      )
    ),
    # Columns container
    shiny::div(
      style = "display: flex; flex-wrap: wrap; margin: 0 -8px;",
      column_uis
    )
  )
}

#' Collaborative kanban board server
#'
#' Server logic for a collaborative kanban board that synchronizes across Shiny
#' sessions using Automerge CRDT.
#'
#' @param id Module ID (must match the ID used in [kanban_ui()]).
#' @param doc_id Document identifier. All kanban boards with the same `doc_id`
#'   synchronize together. Default is `"default"`.
#' @param columns Named character vector defining the columns (must match UI).
#' @param initial_items Optional named list of initial items per column.
#'   Names should be column IDs, values are character vectors of item texts.
#'
#' @return A reactive expression returning a data frame with columns `id`,
#'   `text`, `done`, and `column`.
#'
#' @details
#' Items can be moved between columns using the arrow buttons. The kanban
#' board uses a single Automerge document where each item has a `column`
#' field indicating which column it belongs to.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(kanban_ui("board"))
#'   server <- function(input, output, session) {
#'     kanban_server("board", initial_items = list(
#'       todo = c("Design feature", "Write tests"),
#'       in_progress = c("Code review"),
#'       done = c("Deploy v1.0")
#'     ))
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family kanban
#' @export
kanban_server <- function(
  id,
  doc_id = "default",
  columns = c(todo = "To Do", in_progress = "In Progress", done = "Done"),
  initial_items = NULL
) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    col_ids <- names(columns)
    master_state <- get_kanban_state(doc_id)

    # Initialize master with initial_items if empty
    shiny::isolate({
      if (!is.null(initial_items)) {
        items_obj <- automerge::am_get(
          master_state$doc,
          automerge::AM_ROOT,
          "items"
        )
        if (automerge::am_length(master_state$doc, items_obj) == 0L) {
          pos <- 1L
          for (col_id in names(initial_items)) {
            for (text in initial_items[[col_id]]) {
              automerge::am_insert(
                master_state$doc,
                items_obj,
                pos,
                automerge::am_map()
              )
              item <- automerge::am_get(master_state$doc, items_obj, pos)
              automerge::am_put(master_state$doc, item, "id", generate_kanban_id())
              automerge::am_put(master_state$doc, item, "text", text)
              automerge::am_put(master_state$doc, item, "done", FALSE)
              automerge::am_put(master_state$doc, item, "column", col_id)
              pos <- pos + 1L
            }
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
          done = automerge::am_get(local_doc, item, "done"),
          column = automerge::am_get(local_doc, item, "column")
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

    # Add new item (to first column by default)
    shiny::observeEvent(input$add_btn, {
      text <- trimws(input$new_item)
      if (nzchar(text)) {
        items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
        n <- automerge::am_length(local_doc, items_obj)

        pos <- n + 1L
        automerge::am_insert(local_doc, items_obj, pos, automerge::am_map())
        item <- automerge::am_get(local_doc, items_obj, pos)
        automerge::am_put(local_doc, item, "id", generate_kanban_id())
        automerge::am_put(local_doc, item, "text", text)
        automerge::am_put(local_doc, item, "done", FALSE)
        automerge::am_put(local_doc, item, "column", col_ids[1L])
        automerge::am_commit(local_doc, paste("Add:", text))

        shiny::updateTextInput(session, "new_item", value = "")
        sync_with_master()
      }
    })

    # Move item to a different column
    shiny::observeEvent(input$move_item, {
      # Format: "item_id:new_column"
      parts <- strsplit(input$move_item, ":", fixed = TRUE)[[1L]]
      item_id <- parts[1L]
      new_column <- parts[2L]

      items_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "items")
      n <- automerge::am_length(local_doc, items_obj)

      for (i in seq_len(n)) {
        item <- automerge::am_get(local_doc, items_obj, i)
        if (identical(automerge::am_get(local_doc, item, "id"), item_id)) {
          automerge::am_put(local_doc, item, "column", new_column)
          automerge::am_commit(local_doc, paste("Move to:", new_column))
          sync_with_master()
          break
        }
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

    # Render each column
    lapply(seq_along(col_ids), function(col_idx) {
      col_id <- col_ids[col_idx]
      output_id <- paste0("col_", col_id)

      output[[output_id]] <- shiny::renderUI({
        items <- local_items()
        col_items <- Filter(function(x) identical(x$column, col_id), items)

        if (length(col_items) == 0L) {
          return(shiny::p(
            style = "color: #888; font-style: italic; text-align: center; padding: 20px;",
            "No items"
          ))
        }

        shiny::tagList(
          lapply(col_items, function(item) {
            # Determine which move buttons to show
            can_move_left <- col_idx > 1L
            can_move_right <- col_idx < length(col_ids)

            move_buttons <- shiny::div(
              style = "display: flex; gap: 4px;",
              if (can_move_left) {
                shiny::tags$button(
                  type = "button",
                  class = "btn btn-sm btn-outline-secondary",
                  title = paste("Move to", columns[col_idx - 1L]),
                  onclick = sprintf(
                    "Shiny.setInputValue('%s', '%s:%s', {priority: 'event'})",
                    ns("move_item"),
                    item$id,
                    col_ids[col_idx - 1L]
                  ),
                  "\u2190"
                )
              },
              if (can_move_right) {
                shiny::tags$button(
                  type = "button",
                  class = "btn btn-sm btn-outline-secondary",
                  title = paste("Move to", columns[col_idx + 1L]),
                  onclick = sprintf(
                    "Shiny.setInputValue('%s', '%s:%s', {priority: 'event'})",
                    ns("move_item"),
                    item$id,
                    col_ids[col_idx + 1L]
                  ),
                  "\u2192"
                )
              }
            )

            shiny::div(
              style = paste(
                "background: white; border: 1px solid #dee2e6; border-radius: 4px;",
                "padding: 8px; margin-bottom: 8px; box-shadow: 0 1px 2px rgba(0,0,0,0.05);"
              ),
              shiny::div(
                style = "display: flex; align-items: flex-start; gap: 8px;",
                shiny::tags$input(
                  type = "checkbox",
                  checked = if (item$done) "checked" else NULL,
                  onclick = sprintf(
                    "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                    ns("toggle_item"),
                    item$id
                  ),
                  style = "width: 16px; height: 16px; cursor: pointer; margin-top: 2px;"
                ),
                shiny::span(
                  style = if (item$done) {
                    "flex: 1; text-decoration: line-through; color: #888;"
                  } else {
                    "flex: 1;"
                  },
                  item$text
                )
              ),
              shiny::div(
                style = "display: flex; justify-content: space-between; margin-top: 8px;",
                move_buttons,
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
            )
          })
        )
      })
    })

    # Return reactive with current items as data frame
    shiny::reactive({
      items <- local_items()
      if (length(items) == 0L) {
        data.frame(
          id = character(),
          text = character(),
          done = logical(),
          column = character()
        )
      } else {
        data.frame(
          id = vapply(items, `[[`, character(1L), "id"),
          text = vapply(items, `[[`, character(1L), "text"),
          done = vapply(items, `[[`, logical(1L), "done"),
          column = vapply(items, `[[`, character(1L), "column")
        )
      }
    })
  })
}
