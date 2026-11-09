module Idempotency
  # El endpoint idempotente corrió sin contexto de tenancy: no hay organización a la que atribuir la clave. Es un bug de programación (500); el contexto se abre ANTES (Tenancy.with_context).
  class MissingContext < Error; end
end
