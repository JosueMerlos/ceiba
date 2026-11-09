# Estado por request/job (ActiveSupport::CurrentAttributes).
#   context    contexto de tenancy; SOLO Tenancy.with_context lo escribe: nada más debe asignarlo.
#   session    Identity::CurrentSession de la request autenticada; SOLO Api::Authentication#authenticate! la escribe.
#   principal  quién actúa (hoy Identity::Principal::User; M0.08 lo amplía con memberships y permisos).
#   request_id, ip, user_agent  de la request en curso (Api::RequestMetadata); la auditoría los anota (M0.11).
class Current < ActiveSupport::CurrentAttributes
  attribute :context, :session, :principal, :request_id, :ip, :user_agent
end
