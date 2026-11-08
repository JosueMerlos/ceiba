# Estado por request/job (ActiveSupport::CurrentAttributes). Hoy solo guarda el contexto de tenancy; M0.07 añadirá
# la sesión. SOLO Tenancy.with_context escribe `context`: nada más debe asignarlo.
class Current < ActiveSupport::CurrentAttributes
  attribute :context
end
