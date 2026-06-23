# Edit a synced document live in a Shiny code editor

Opens the text object at `at` within a `sync_doc` handle (from
[`autosync::sync_client()`](http://shikokuchuo.net/autosync/reference/sync_client.md)'s
`$open_doc()`, or
[`project_open()`](http://shikokuchuo.net/shinysync/reference/project_open.md)'s
`$open()`) in a Shiny
[`bslib::input_code_editor()`](https://rstudio.github.io/bslib/reference/input_code_editor.html)
that stays in sync with the live document in both directions, blocks
until the editor closes, then prints a one-line summary.

## Usage

``` r
project_edit(doc, at = "text", ext = NULL, debounce = 300L)
```

## Arguments

- doc:

  A `sync_doc` handle backed by an active connection (from
  [`autosync::sync_client()`](http://shikokuchuo.net/autosync/reference/sync_client.md)'s
  `$open_doc()` or
  [`project_open()`](http://shikokuchuo.net/shinysync/reference/project_open.md)'s
  `$open()`).

- at:

  Character path to the text object within the document. A single string
  addresses a top-level key; a character vector navigates nested objects
  with `[[`. Default `"text"`.

- ext:

  File extension (e.g. `".md"`) used to pick the editor's
  syntax-highlighting language, or `NULL` for plain text.

- debounce:

  Milliseconds to wait after the last keystroke before pushing.

## Value

Invisibly returns `doc`.

## Details

As you type, the minimal diff is written to the live document and pushed
(debounced); when the text changes remotely, the editor updates to the
merged result. There is no **Save** button – every edit is applied live.
It syncs whole-text snapshots, not granular operations, so a remote edit
arriving in the brief window between a keystroke and its debounced push
can be overwritten by that push; a smaller `debounce` narrows the
window. The original's trailing-newline state is preserved.

## Examples

``` r
if (FALSE) { # interactive()
conn <- autosync::sync_client("wss://quarto-hub.com/ws")
doc <- conn$open_doc("4F63WJPDzbHkkfKa66h1Qrr1sC5U")
project_edit(doc, at = "text", ext = ".md")
conn$close()
}
```
