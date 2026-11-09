# Estado por request/job (ActiveSupport::CurrentAttributes).
#   context    contexto de tenancy; SOLO Tenancy.with_context lo escribe: nada más debe asignarlo.
#   session    Identity::CurrentSession de la request autenticada; SOLO Api::Authentication#authenticate! la escribe.
#   principal  quién actúa (hoy Identity::Principal::User; M0.08 lo amplía con memberships y permisos).
class Current < ActiveSupport::CurrentAttributes
  attribute :context, :session, :principal
end
