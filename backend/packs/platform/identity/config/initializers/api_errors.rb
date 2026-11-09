# Errores de dominio de identity que la API traduce a problem+json (ver Api::ErrorRegistry).
#
# - InvalidCredentials y Unauthenticated son 401; InvalidCsrfToken y ForbiddenOrigin son 403. Ninguno expone el mensaje
#   de la excepción, y InvalidCredentials es UN solo code para "no existe la cuenta" y "contraseña errónea".
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Identity::InvalidCredentials, status: :unauthorized, code: "auth.invalid_credentials")
  Api::ErrorRegistry.register(Identity::Unauthenticated, status: :unauthorized, code: "auth.unauthenticated")
  Api::ErrorRegistry.register(Identity::InvalidCsrfToken, status: :forbidden, code: "auth.csrf_invalid")
  Api::ErrorRegistry.register(Identity::ForbiddenOrigin, status: :forbidden, code: "auth.origin_forbidden")
end
