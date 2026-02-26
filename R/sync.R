# Sync-server-free collaborative Shiny input synchronization

# Private environments to store master sync documents and file paths per doc_id
.master_sync <- new.env(parent = emptyenv())
.master_sync_paths <- new.env(parent = emptyenv())
.sync_excludes <- new.env(parent = emptyenv())

#' Register a module namespace prefix to exclude from sync
#' @noRd
register_sync_exclude <- function(doc_id, prefix) {
  current <- if (exists(doc_id, envir = .sync_excludes)) {
    .sync_excludes[[doc_id]]
  } else {
    character()
  }
  .sync_excludes[[doc_id]] <- unique(c(current, prefix))
}

#' Get or create master sync state
#' @noRd
get_sync_state <- function(doc_id, path = NULL) {
  # Record persistence path (first caller with a path wins)
  if (!is.null(path) && !exists(doc_id, envir = .master_sync_paths)) {
    .master_sync_paths[[doc_id]] <- path
  }

  if (!exists(doc_id, envir = .master_sync)) {
    doc <- NULL
    p <- if (exists(doc_id, envir = .master_sync_paths)) {
      .master_sync_paths[[doc_id]]
    }

    # Try to load persisted document from disk
    if (!is.null(p) && file.exists(p)) {
      doc <- tryCatch(
        automerge::am_load(readBin(p, "raw", file.size(p))),
        error = function(e) NULL
      )
    }

    # Fall back to a fresh document
    if (is.null(doc)) {
      doc <- automerge::am_create()
      automerge::am_put(
        doc, automerge::AM_ROOT, "inputs", automerge::am_map()
      )
      automerge::am_commit(doc, "init")
    }

    .master_sync[[doc_id]] <- shiny::reactiveValues(
      doc = doc,
      version = 0L
    )
  }
  .master_sync[[doc_id]]
}

#' Check if a value is syncable (scalar string, number, or logical)
#' @noRd
is_syncable <- function(x) {
  !is.null(x) &&
    (is.character(x) || is.numeric(x) || is.logical(x)) &&
    length(x) == 1L
}

#' Filter input IDs for syncing
#' @noRd
filter_input_ids <- function(ids, include = NULL, exclude = NULL,
                             doc_id = NULL) {
  ids <- ids[!startsWith(ids, ".")]
  if (!is.null(doc_id) && exists(doc_id, envir = .sync_excludes)) {
    prefixes <- .sync_excludes[[doc_id]]
    for (p in prefixes) {
      ids <- ids[!startsWith(ids, p)]
    }
  }
  if (!is.null(include)) {
    ids <- intersect(ids, include)
  }
  if (!is.null(exclude)) {
    ids <- setdiff(ids, exclude)
  }
  ids
}

#' Synchronize Shiny inputs across sessions
#'
#' Makes Shiny inputs collaborative by synchronizing their values across
#' all connected sessions using Automerge CRDT, without requiring an
#' external sync server.
#'
#' @param session The Shiny session object. Default uses
#'   [shiny::getDefaultReactiveDomain()].
#' @param doc_id Document identifier string. All sessions using the same
#'   `doc_id` share synchronized input state. Default is `"default"`.
#' @param include Optional character vector of input IDs to synchronize. If
#'   `NULL` (default), all eligible inputs are synchronized.
#' @param exclude Optional character vector of input IDs to exclude from
#'   synchronization. Applied after `include`.
#' @param path Optional file path for persistent state. When provided, the
#'   Automerge document is saved to this file after every change and
#'   reloaded automatically when the app restarts. Set to `NULL` (default)
#'   for in-memory only.
#'
#' @details
#' Call this function once in your Shiny server logic to enable collaborative
#' input synchronization. Scalar string, numeric, and logical input values
#' are synchronized automatically. Complex inputs (file uploads, action
#' buttons, data table selections, etc.) are excluded by default.
#'
#' When a user changes an input, the new value is propagated to all other
#' connected sessions. The entire app state is stored in a single Automerge
#' document, providing automatic conflict resolution via CRDT.
#'
#' Inputs with names starting with `"."` (Shiny internal inputs) are always
#' excluded.
#'
#' ## Persistence
#'
#' When `path` is provided, the shared document is saved to disk (via
#' [automerge::am_save()]) after every change. On the next app startup,
#' the document is loaded from disk and all sessions resume from the
#' saved state. This makes the shared input state survive R process
#' restarts.
#'
#' @note This function synchronizes sessions within a single R process.
#'   For multi-process deployments, use an external sync server with the
#'   [editor()] widget instead.
#'
#' @return A \code{reactiveVal} (logical). \code{FALSE} during normal
#'   operation, \code{TRUE} during replay. Can be ignored if replay is not
#'   used. Called primarily for side effects.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     shiny::selectInput("dist", "Distribution",
#'       c("Normal", "Uniform", "Exponential")),
#'     shiny::sliderInput("n", "Observations", 10, 500, 100),
#'     shiny::plotOutput("plot")
#'   )
#'   server <- function(input, output, session) {
#'     sync_inputs()
#'     output$plot <- shiny::renderPlot(
#'       hist(switch(input$dist,
#'         Normal = rnorm(input$n),
#'         Uniform = runif(input$n),
#'         Exponential = rexp(input$n)
#'       ))
#'     )
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#'
#' @family sync
#' @export
sync_inputs <- function(
  session = shiny::getDefaultReactiveDomain(),
  doc_id = "default",
  include = NULL,
  exclude = NULL,
  path = NULL
) {
  master_state <- get_sync_state(doc_id, path)
  replaying <- shiny::reactiveVal(FALSE)

  # Per-session Automerge sync states
  sync_local <- automerge::am_sync_state()
  sync_master <- automerge::am_sync_state()

  # Create local document with empty inputs map
  local_doc <- shiny::isolate({
    doc <- automerge::am_create()
    automerge::am_put(doc, automerge::AM_ROOT, "inputs", automerge::am_map())
    automerge::am_commit(doc, "init")
    doc
  })

  # Incremental sync function (same protocol as kanban/textarea modules)
  incremental_sync <- function() {
    old_local <- automerge::am_get_heads(local_doc)
    old_master <- automerge::am_get_heads(master_state$doc)

    repeat {
      msg_up <- automerge::am_sync_encode(local_doc, sync_local)
      msg_down <- automerge::am_sync_encode(master_state$doc, sync_master)
      if (is.null(msg_up) && is.null(msg_down)) {
        break
      }
      if (!is.null(msg_up)) {
        automerge::am_sync_decode(master_state$doc, sync_master, msg_up)
      }
      if (!is.null(msg_down)) {
        automerge::am_sync_decode(local_doc, sync_local, msg_down)
      }
    }

    list(
      pulled = !identical(old_local, automerge::am_get_heads(local_doc)),
      pushed = !identical(old_master, automerge::am_get_heads(master_state$doc))
    )
  }

  # Sync and bump master version if we pushed changes
  sync_and_notify <- function() {
    result <- incremental_sync()
    if (result$pushed) {
      master_state$version <- master_state$version + 1L
      # Persist to disk if a path is configured for this doc_id
      if (exists(doc_id, envir = .master_sync_paths)) {
        writeBin(
          automerge::am_save(master_state$doc),
          .master_sync_paths[[doc_id]]
        )
      }
    }
    result
  }

  # Track known values to suppress feedback loops.
  # When we update a widget from a remote change, the widget fires an input
  # event back to R. By recording the value we just set, the observer can
  # recognise the echo and skip re-syncing it.
  known <- new.env(parent = emptyenv())
  initialized <- FALSE
  resuming <- FALSE

  # Initial sync with master
  shiny::isolate(incremental_sync())

  # After first flush: register JS handler and initialize input state
  session$onFlushed(
    function() {
      # Inject JS message handler that updates any standard Shiny input widget.
      # Uses the input binding's receiveMessage method, which is the same
      # mechanism that updateSliderInput / updateSelectInput etc. use internally.
      shiny::insertUI(
        "head",
        "beforeEnd",
        immediate = TRUE,
        session = session,
        ui = shiny::tags$script(shiny::HTML(paste0(
          "if (!window.__shinysync__) {\n",
          "  window.__shinysync__ = true;\n",
          "  Shiny.addCustomMessageHandler('__shinysync__', function(updates) {\n",
          "    updates.forEach(function(u) {\n",
          "      var el = document.getElementById(u.id);\n",
          "      if (!el) return;\n",
          "      var binding = $(el).data('shiny-input-binding');\n",
          "      if (!binding) return;\n",
          "      binding.receiveMessage(el, {value: u.value, selected: u.value});\n",
          "    });\n",
          "  });\n",
          "}"
        )))
      )

      # Read current input values and merge with master state.
      # onFlushed runs outside a reactive context, so isolate all reads.
      updates <- shiny::isolate({
        all_inputs <- shiny::reactiveValuesToList(session$input)
        input_ids <- filter_input_ids(names(all_inputs), include, exclude,
                                      doc_id)

        inputs_obj <- automerge::am_get(
          local_doc, automerge::AM_ROOT, "inputs"
        )
        written_ids <- character()
        upd <- list()

        for (id in input_ids) {
          val <- all_inputs[[id]]
          if (!is_syncable(val)) {
            next
          }

          # Check if the master document already has a value for this input
          existing <- tryCatch(
            automerge::am_get(local_doc, inputs_obj, id),
            error = function(e) NULL
          )

          if (!is.null(existing)) {
            # Master has a value - adopt it
            assign(id, existing, envir = known)
            if (!identical(existing, val)) {
              upd <- c(upd, list(list(id = id, value = existing)))
            }
          } else {
            # No existing value - write the session default
            automerge::am_put(local_doc, inputs_obj, id, val)
            assign(id, val, envir = known)
            written_ids <- c(written_ids, id)
          }
        }

        if (length(written_ids) > 0L) {
          automerge::am_commit(
            local_doc,
            paste("init:", paste(written_ids, collapse = ", ")),
            time = Sys.time()
          )
          sync_and_notify()
        }

        upd
      })

      # Push any master values that differ from defaults to the widgets
      if (length(updates) > 0L) {
        session$sendCustomMessage("__shinysync__", updates)
      }
      initialized <<- TRUE
    },
    once = TRUE
  )

  # Observe local input changes and propagate to master
  shiny::observe({
    if (replaying()) return()
    all_inputs <- shiny::reactiveValuesToList(session$input)
    if (!initialized || resuming) {
      resuming <<- FALSE
      return()
    }
    input_ids <- filter_input_ids(names(all_inputs), include, exclude, doc_id)

    changed_ids <- character()
    inputs_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "inputs")

    for (id in input_ids) {
      val <- all_inputs[[id]]
      if (!is_syncable(val)) {
        next
      }

      known_val <- if (exists(id, envir = known)) {
        get(id, envir = known)
      } else {
        NULL
      }
      if (identical(val, known_val)) {
        next
      }

      automerge::am_put(local_doc, inputs_obj, id, val)
      assign(id, val, envir = known)
      changed_ids <- c(changed_ids, id)
    }

    if (length(changed_ids) > 0L) {
      msg <- if (length(changed_ids) == 1L) {
        sprintf("%s: %s", changed_ids, as.character(all_inputs[[changed_ids]]))
      } else {
        sprintf(
          "%s: %d inputs",
          paste(changed_ids, collapse = ", "),
          length(changed_ids)
        )
      }
      automerge::am_commit(local_doc, msg, time = Sys.time())
      shiny::isolate(sync_and_notify())
    }
  })

  # Resync known state when replay ends
  shiny::observeEvent(replaying(), {
    if (!replaying()) {
      shiny::isolate({
        incremental_sync()
        inputs_obj <- automerge::am_get(
          local_doc, automerge::AM_ROOT, "inputs"
        )
        updates <- list()
        for (id in ls(known)) {
          val <- tryCatch(
            automerge::am_get(local_doc, inputs_obj, id),
            error = function(e) NULL
          )
          if (is.null(val)) next
          assign(id, val, envir = known)
          updates <- c(updates, list(list(id = id, value = val)))
        }
        if (length(updates) > 0L) {
          session$sendCustomMessage("__shinysync__", updates)
        }
        # Skip one observer cycle: session$input still has stale replay
        # values that haven't been updated by the sendCustomMessage yet.
        resuming <<- TRUE
      })
    }
  }, ignoreInit = TRUE, priority = 10)

  # React to remote changes from other sessions
  shiny::observeEvent(
    master_state$version,
    {
      result <- incremental_sync()
      if (!result$pulled) {
        return()
      }

      inputs_obj <- automerge::am_get(local_doc, automerge::AM_ROOT, "inputs")
      input_ids <- ls(known)

      updates <- list()
      for (id in input_ids) {
        val <- tryCatch(
          automerge::am_get(local_doc, inputs_obj, id),
          error = function(e) NULL
        )
        if (is.null(val)) {
          next
        }

        known_val <- get(id, envir = known)
        if (identical(val, known_val)) {
          next
        }

        assign(id, val, envir = known)
        updates <- c(updates, list(list(id = id, value = val)))
      }

      if (length(updates) > 0L) {
        session$sendCustomMessage("__shinysync__", updates)
      }
    },
    ignoreInit = TRUE
  )

  invisible(replaying)
}
