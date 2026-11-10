# Identity domain errors that the API translates to problem+json (see Api::ErrorRegistry).
#
# - InvalidCredentials and Unauthenticated are 401; InvalidCsrfToken and ForbiddenOrigin are 403. None exposes the
#   exception message, and InvalidCredentials is ONE code for "no such account" and "wrong password".
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Identity::InvalidCredentials, status: :unauthorized, code: "auth.invalid_credentials")
  Api::ErrorRegistry.register(Identity::Unauthenticated, status: :unauthorized, code: "auth.unauthenticated")
  Api::ErrorRegistry.register(Identity::InvalidCsrfToken, status: :forbidden, code: "auth.csrf_invalid")
  Api::ErrorRegistry.register(Identity::ForbiddenOrigin, status: :forbidden, code: "auth.origin_forbidden")
end
