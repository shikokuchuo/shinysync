# shinysync (development version)

* New `project_*` family for browsing and editing a project document served by
  an `autosync` (or other automerge-repo) sync server, where R owns the
  WebSocket sync: `project_open()` opens a persistent connection and exposes the
  project's file tree, `project_app()` is a single-window connect/browse/edit
  Shiny gadget, and `project_edit()` live-edits one document's text object in a
  `bslib::input_code_editor()`. Moved here from autosync (where they were
  `amsync_project()`, `amsync_app()` and the `sync_doc` handle's `$edit()`
  method). `autosync` and `bslib` are now hard dependencies.

# shinysync 0.0.1

* Initial release.
