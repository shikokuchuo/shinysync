# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Package Overview

shinysync is an R package providing a real-time collaborative code
editor widget built on CodeMirror 6 and Automerge CRDT. It connects via
WebSocket to automerge-repo compatible sync servers for multi-user
editing with automatic conflict resolution.

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

- `R/editor.R` - Main widget functions:
  [`editor()`](http://shikokuchuo.net/shinysync/reference/editor.md),
  [`editor_output()`](http://shikokuchuo.net/shinysync/reference/editor-shiny.md),
  `render_editor()`
- Uses htmlwidgets to bridge R and JavaScript

### JavaScript Widget

- `inst/htmlwidgets/shinysyncEditor.js` - Bundled widget (output from
  build)
- `inst/htmlwidgets/shinysyncEditor.yaml` - Widget dependency
  configuration
- `inst/build/` - Source and build tooling (esbuild bundles CodeMirror +
  Automerge)

### Key Dependencies

- R: htmlwidgets (required), automerge/autosync/shiny (suggested)
- JS: @automerge/automerge-repo, @automerge/automerge-codemirror,
  codemirror

## Document Structure

The Automerge document must have a “text” field of type Automerge text.
In Shiny, editor content is available at `input$<outputId>_content`.
