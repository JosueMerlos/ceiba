# Errores de acceso que la API traduce a problem+json (ver Api::ErrorRegistry).
#
# - Pundit::NotAuthorizedError: el recurso es visible pero la acción no está permitida => 403. Lo no visible NUNCA llega aquí:
#   Access::RouteContextResolver lo responde 404 (RecordNotFound) para no revelar que existe.
# - Access::OrganizationSuspended => 403 (el principal es miembro; si no, habría recibido 404).
# - AuthorizationNotPerformedError / PolicyScopingNotPerformedError y Access::UnknownPermission NO se registran a propósito: son
#   bugs del código (una acción sin authorize, un permiso sin declarar) y salen como 500 genérico con el detalle en el log.
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Pundit::NotAuthorizedError, status: :forbidden, code: "access.forbidden")
  Api::ErrorRegistry.register(Access::OrganizationSuspended, status: :forbidden, code: "access.organization_suspended")
end
