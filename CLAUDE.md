# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Package Overview

shinysync is an R package of collaborative Shiny components built on
Automerge CRDT. It spans three sync architectures:

- **Browser-owned sync** — the
  [`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md)
  htmlwidget (CodeMirror 6 + JS
  `@automerge/automerge-repo`/`automerge-codemirror`) connects the
  browser directly to a sync server.
- **Server-free in-process sync** —
  [`sync_inputs()`](http://shikokuchuo.net/shinysync/reference/sync_inputs.md),
  `textarea_*`, `kanban_*`, `replay_*` keep a per-`doc_id` master
  Automerge document in R and sync each Shiny session to it (no external
  sync server).
- **R-owned WebSocket sync** — the `project_*` family
  ([`project_open()`](http://shikokuchuo.net/shinysync/reference/project_open.md),
  [`project_app()`](http://shikokuchuo.net/shinysync/reference/project_app.md),
  [`project_edit()`](http://shikokuchuo.net/shinysync/reference/project_edit.md))
  browses/edits a project document served by an `autosync` sync server,
  with R owning the sync via
  [`autosync::sync_client()`](http://shikokuchuo.net/autosync/reference/sync_client.md)
  and a `bslib` editor in the browser. Moved here from autosync.

## Development Commands

``` bash
# Run R CMD check
R CMD check .

# Run tests
Rscript -e "testthat::test_local()"

# Run a single test file
Rscript -e "testthat::test_file('tests/testthat/test-editor.R')"

# Document and rebuild NAMESPACE
Rscript -e "devtools::document()"

# Rebuild JavaScript widget (after modifying JS source)
cd inst/build && npm install && npm run build
```

## Architecture

### R Layer

- `R/editor.R` - htmlwidget functions:
  [`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md),
  [`editor_output()`](http://shikokuchuo.net/shinysync/reference/editor-shiny.md),
  [`editor_render()`](http://shikokuchuo.net/shinysync/reference/editor-shiny.md)
  (bridges R and JS via htmlwidgets)
- `R/sync.R`, `R/textarea.R`, `R/kanban.R`, `R/replay.R` - server-free
  in-process collaborative modules
- `R/project.R`, `R/app.R`, `R/edit.R` - the `project_*` family
  (server-backed project browser/editor over `autosync`); `R/utils.R`
  holds their small helpers

### JavaScript Widget

- `inst/htmlwidgets/shinysyncEditor.js` - Bundled widget (output from
  build)
- `inst/htmlwidgets/shinysyncEditor.yaml` - Widget dependency
  configuration
- `inst/build/` - Source and build tooling (esbuild bundles CodeMirror +
  Automerge)

### Key Dependencies

- R Imports: automerge, autosync, bslib, htmlwidgets, later, shiny,
  tools
- JS: @automerge/automerge-repo, @automerge/automerge-codemirror,
  codemirror

## Document Structure

The Automerge document must have a “text” field of type Automerge text.
In Shiny, editor content is available at `input$<outputId>_content`.
