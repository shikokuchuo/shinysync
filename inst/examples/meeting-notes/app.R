# Collaborative Meeting Notes App
#
# Run with: shiny::runApp(system.file("examples/meeting-notes", package = "autoedit"))
#
# Open multiple browser windows to see real-time collaboration in action.

library(shiny)
library(autoedit)

rooms <- c(
  "Daily Standup" = "standup",
  "Sprint Planning" = "planning",
  "Retrospective" = "retrospective",
  "Brainstorming" = "brainstorm"
)

room_labels <- setNames(names(rooms), rooms)

room_templates <- list(
  standup = "# Daily Standup\n\n## What I did yesterday\n- \n\n## What I'm doing today\n- \n\n## Blockers\n- \n",
  planning = "# Sprint Planning\n\n## Goals\n- \n\n## User Stories\n- \n\n## Capacity\n- \n",
  retrospective = "# Retrospective\n\n## What went well\n- \n\n## What could be improved\n- \n\n## Action items\n- \n",
  brainstorm = "# Brainstorming Session\n\n## Ideas\n- \n\n## Discussion Notes\n- \n"
)

ui <- fluidPage(
  tags$head(
    tags$style(HTML(
      "
      .notes-container {
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 0;
      }
      .notes-container textarea {
        font-family: 'SF Mono', Consolas, 'Liberation Mono', Menlo, monospace;
        font-size: 14px;
        line-height: 1.5;
        border: none;
        resize: none;
      }
      .room-header {
        background: #f8f9fa;
        padding: 10px 15px;
        border-bottom: 1px solid #ddd;
        border-radius: 4px 4px 0 0;
      }
      .sync-indicator {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #28a745;
        margin-right: 8px;
      }
    "
    )),
    tags$script(HTML(
      "
      Shiny.addCustomMessageHandler('toggle_panel', function(msg) {
        if (msg.show) {
          $('#' + msg.id).show();
        } else {
          $('#' + msg.id).hide();
        }
      });
    "
    ))
  ),

  titlePanel("Collaborative Meeting Notes"),

  fluidRow(
    column(
      width = 3,
      wellPanel(
        h4("Select Room"),
        radioButtons(
          "room",
          label = NULL,
          choices = rooms,
          selected = "standup"
        ),
        hr(),
        p(
          class = "text-muted",
          tags$span(class = "sync-indicator"),
          "Sync active"
        ),
        p(
          class = "text-muted small",
          "Open multiple browser windows to collaborate in real-time."
        ),
        hr(),
        downloadButton("export", "Export as Markdown", class = "btn-sm")
      )
    ),

    column(
      width = 9,
      div(
        class = "notes-container",
        div(
          class = "room-header",
          h5(
            style = "margin: 0;",
            textOutput("room_title", inline = TRUE)
          )
        ),
        div(
          id = "standup-panel",
          textarea_ui(
            "notes_standup",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your standup notes..."
          )
        ),
        div(
          id = "planning-panel",
          style = "display: none;",
          textarea_ui(
            "notes_planning",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your planning notes..."
          )
        ),
        div(
          id = "retrospective-panel",
          style = "display: none;",
          textarea_ui(
            "notes_retrospective",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your retrospective notes..."
          )
        ),
        div(
          id = "brainstorm-panel",
          style = "display: none;",
          textarea_ui(
            "notes_brainstorm",
            label = NULL,
            width = "100%",
            height = "500px",
            placeholder = "Start typing your ideas..."
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  text_standup <- textarea_server(
    "notes_standup",
    doc_id = "standup",
    initial_text = room_templates$standup
  )

  text_planning <- textarea_server(
    "notes_planning",
    doc_id = "planning",
    initial_text = room_templates$planning
  )

  text_retrospective <- textarea_server(
    "notes_retrospective",
    doc_id = "retrospective",
    initial_text = room_templates$retrospective
  )

  text_brainstorm <- textarea_server(
    "notes_brainstorm",
    doc_id = "brainstorm",
    initial_text = room_templates$brainstorm
  )

  observeEvent(input$room, {
    all_rooms <- c("standup", "planning", "retrospective", "brainstorm")
    for (room in all_rooms) {
      session$sendCustomMessage(
        "toggle_panel",
        list(
          id = paste0(room, "-panel"),
          show = room == input$room
        )
      )
    }
  })

  output$room_title <- renderText({
    room_labels[input$room]
  })

  current_text <- reactive({
    switch(
      input$room,
      "standup" = text_standup(),
      "planning" = text_planning(),
      "retrospective" = text_retrospective(),
      "brainstorm" = text_brainstorm(),
      ""
    )
  })

  output$export <- downloadHandler(
    filename = function() {
      paste0(input$room, "-notes-", Sys.Date(), ".md")
    },
    content = function(file) {
      writeLines(current_text(), file)
    }
  )
}

shinyApp(ui, server)
