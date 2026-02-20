# Replay module for sync_inputs history

#' Replay timeline UI
#'
#' Creates a timeline control for replaying the history of synchronized inputs
#' recorded by [sync_inputs()].
#'
#' @param id Module ID.
#' @param show_messages Whether to display commit messages below the timeline.
#'   Default is `TRUE`.
#' @param playback_ms Interval in milliseconds between steps during animated
#'   playback. Default is `1000`.
#'
#' @return A Shiny UI element.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     shiny::selectInput("dist", "Distribution",
#'       c("Normal", "Uniform", "Exponential")),
#'     shiny::sliderInput("n", "Observations", 10, 500, 100),
#'     shiny::plotOutput("plot"),
#'     replay_ui("timeline")
#'   )
#'   server <- function(input, output, session) {
#'     replaying <- sync_inputs()
#'     replay_server("timeline", replaying = replaying)
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
replay_ui <- function(id, show_messages = TRUE, playback_ms = 1000) {
  ns <- shiny::NS(id)

  shiny::div(
    style = "padding: 10px 0;",
    # Store config as data attributes for the server to read
    shiny::tags$div(
      id = ns("config"),
      style = "display: none;",
      `data-show-messages` = tolower(as.character(show_messages)),
      `data-playback-ms` = as.character(playback_ms)
    ),
    # Timeline slider
    shiny::sliderInput(
      ns("timeline"),
      label = NULL,
      min = 1L,
      max = 1L,
      value = 1L,
      step = 1L,
      width = "100%"
    ),
    # Controls row
    shiny::div(
      style = "display: flex; align-items: center; gap: 8px; flex-wrap: wrap;",
      shiny::actionButton(ns("first"), "\u23EE",
        class = "btn-sm btn-outline-secondary"
      ),
      shiny::actionButton(ns("prev"), "\u23F4",
        class = "btn-sm btn-outline-secondary"
      ),
      shiny::actionButton(ns("play"), "\u25B6",
        class = "btn-sm btn-outline-primary"
      ),
      shiny::actionButton(ns("next_btn"), "\u23F5",
        class = "btn-sm btn-outline-secondary"
      ),
      shiny::actionButton(ns("last"), "\u23ED",
        class = "btn-sm btn-outline-secondary"
      ),
      shiny::span(
        style = "margin-left: 12px; font-size: 13px; color: #555;",
        shiny::textOutput(ns("step_label"), inline = TRUE)
      )
    ),
    # Commit message display
    if (show_messages) {
      shiny::div(
        style = "margin-top: 6px; font-size: 12px; color: #888; font-family: monospace;",
        shiny::textOutput(ns("commit_msg"))
      )
    }
  )
}

#' Replay timeline server
#'
#' Server logic for the replay timeline module. Reads the change history from
#' the master Automerge document created by [sync_inputs()], reconstructs
#' snapshots at each step, and pushes the values to widgets.
#'
#' @param id Module ID (must match the ID used in [replay_ui()]).
#' @param doc_id Document identifier. Must match the `doc_id` used in
#'   [sync_inputs()]. Default is `"default"`.
#' @param replaying The `reactiveVal` returned by [sync_inputs()].
#' @param show_messages Whether to display commit messages. Default is `TRUE`.
#' @param playback_ms Interval in milliseconds between steps during animated
#'   playback. Default is `1000`.
#'
#' @return Called for side effects. Returns `NULL` invisibly.
#'
#' @examples
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     shiny::selectInput("dist", "Distribution",
#'       c("Normal", "Uniform", "Exponential")),
#'     shiny::sliderInput("n", "Observations", 10, 500, 100),
#'     shiny::plotOutput("plot"),
#'     replay_ui("timeline")
#'   )
#'   server <- function(input, output, session) {
#'     replaying <- sync_inputs()
#'     replay_server("timeline", replaying = replaying)
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
replay_server <- function(
  id,
  doc_id = "default",
  replaying,
  show_messages = TRUE,
  playback_ms = 1000
) {
  shiny::moduleServer(id, function(input, output, session) {
    # Exclude this module's inputs from sync_inputs to prevent feedback loops
    register_sync_exclude(doc_id, session$ns(""))

    master_state <- get_sync_state(doc_id)

    # Reactive: build step index from master doc history
    step_info <- shiny::reactive({
      # Take a dependency on master version so we rebuild when history grows
      master_state$version

      changes <- automerge::am_get_changes(master_state$doc)
      if (length(changes) == 0L) {
        return(list(
          all_changes = list(),
          meaningful_indices = integer(),
          messages = character(),
          timestamps = numeric()
        ))
      }

      # Identify meaningful changes (exclude init commits)
      is_meaningful <- vapply(changes, function(ch) {
        msg <- automerge::am_change_message(ch)
        !is.null(msg) && !startsWith(msg, "init")
      }, logical(1))

      meaningful_indices <- which(is_meaningful)

      messages <- vapply(changes[meaningful_indices], function(ch) {
        automerge::am_change_message(ch) %||% ""
      }, character(1))

      timestamps <- vapply(changes[meaningful_indices], function(ch) {
        as.numeric(automerge::am_change_time(ch))
      }, numeric(1))

      list(
        all_changes = changes,
        meaningful_indices = meaningful_indices,
        messages = messages,
        timestamps = timestamps
      )
    })

    # Track the number of meaningful steps
    n_steps <- shiny::reactive({
      length(step_info()$meaningful_indices)
    })

    # Update slider max when history grows
    shiny::observe({
      n <- n_steps()
      if (n < 1L) return()
      current <- shiny::isolate(input$timeline)
      shiny::updateSliderInput(
        session, "timeline",
        max = n,
        value = if (shiny::isolate(replaying())) current else n
      )
    })

    # Playing state for animated playback
    playing <- shiny::reactiveVal(FALSE)

    shiny::observeEvent(input$play, {
      playing(!playing())
    })

    # Update play button label
    shiny::observe({
      label <- if (playing()) "\u23F8" else "\u25B6"
      shiny::updateActionButton(session, "play", label = label)
    })

    # Playback animation
    shiny::observe({
      if (!playing()) return()
      shiny::invalidateLater(playback_ms)
      step <- shiny::isolate(input$timeline)
      n <- shiny::isolate(n_steps())
      if (step < n) {
        shiny::updateSliderInput(session, "timeline", value = step + 1L)
      } else {
        playing(FALSE)
      }
    })

    # Step buttons
    shiny::observeEvent(input$first, {
      if (n_steps() > 0L) {
        shiny::updateSliderInput(session, "timeline", value = 1L)
      }
    })

    shiny::observeEvent(input$prev, {
      step <- input$timeline
      if (!is.null(step) && step > 1L) {
        shiny::updateSliderInput(session, "timeline", value = step - 1L)
      }
    })

    shiny::observeEvent(input$next_btn, {
      step <- input$timeline
      n <- n_steps()
      if (!is.null(step) && step < n) {
        shiny::updateSliderInput(session, "timeline", value = step + 1L)
      }
    })

    shiny::observeEvent(input$last, {
      n <- n_steps()
      if (n > 0L) {
        shiny::updateSliderInput(session, "timeline", value = n)
      }
    })

    # Step label
    output$step_label <- shiny::renderText({
      step <- input$timeline
      n <- n_steps()
      if (is.null(step) || n == 0L) return("")

      info <- step_info()
      ts <- ""
      if (step <= length(info$timestamps) && info$timestamps[step] > 0) {
        ts <- paste0(
          " \u2014 ",
          format(
            as.POSIXct(info$timestamps[step], origin = "1970-01-01"),
            "%H:%M:%S"
          )
        )
      }
      sprintf("Step %d of %d%s", step, n, ts)
    })

    # Commit message display
    output$commit_msg <- shiny::renderText({
      step <- input$timeline
      n <- n_steps()
      if (is.null(step) || n == 0L) return("")

      info <- step_info()
      if (step <= length(info$messages)) info$messages[step] else ""
    })

    # Reconstruct and push snapshot when slider moves
    shiny::observeEvent(input$timeline, {
      step <- input$timeline
      info <- step_info()
      n <- length(info$meaningful_indices)

      if (is.null(step) || n == 0L) return()

      # Clamp step to valid range
      step <- max(1L, min(step, n))

      at_end <- step == n

      if (at_end) {
        # Resume live sync
        if (shiny::isolate(replaying())) {
          replaying(FALSE)
        }
        return()
      }

      # Entering or continuing replay
      if (!shiny::isolate(replaying())) {
        replaying(TRUE)
      }

      # Reconstruct document at this step
      change_idx <- info$meaningful_indices[step]
      snapshot <- automerge::am_create()
      automerge::am_apply_changes(snapshot, info$all_changes[seq_len(change_idx)])

      # Read inputs from snapshot
      inputs_obj <- tryCatch(
        automerge::am_get(snapshot, automerge::AM_ROOT, "inputs"),
        error = function(e) NULL
      )
      if (is.null(inputs_obj)) return()

      keys <- automerge::am_keys(snapshot, inputs_obj)
      updates <- lapply(keys, function(id) {
        list(
          id = id,
          value = automerge::am_get(snapshot, inputs_obj, id)
        )
      })

      if (length(updates) > 0L) {
        session$sendCustomMessage("__autoedit_sync__", updates)
      }
    })

    invisible(NULL)
  })
}
