module Audit
  # Audit.record sin contexto de tenancy: no hay organización a la que atribuir el evento. Es un error de programación
  # (la API no lo traduce: responde 500 genérico); el caso de uso debe correr dentro de Tenancy.with_context.
  class NoContext < Error; end
end
