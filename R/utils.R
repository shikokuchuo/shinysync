# Internal helpers for the project_* family

# Wrapper for interactive() to allow mocking in tests.
is_interactive <- function() interactive()

#' Default OIDC issuer URL
#'
#' Returns the `OIDC_ISSUER` environment variable if set and non-empty,
#' otherwise falls back to Google (`"https://accounts.google.com"`). Used to
#' prefill the connect form's issuer field in [project_app()].
#'
#' @return Character string, the OIDC issuer URL.
#'
#' @noRd
oidc_issuer <- function() {
  issuer <- Sys.getenv("OIDC_ISSUER")
  if (nzchar(issuer)) issuer else "https://accounts.google.com"
}
