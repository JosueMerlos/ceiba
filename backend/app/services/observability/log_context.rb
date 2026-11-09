module Observability
  # Dónde está el tenant "recordado" de la request o el job en curso, para escribirlo en el log y en Sentry DESPUÉS de que
  # el bloque de Tenancy.with_context haya terminado.
  #
  # Por qué existe: la línea de log de una request se escribe al terminar la acción, cuando un `around_action` con
  # `Tenancy.with_context` ya salió y `Current.context` volvió a nil. Y un job que lanza una excepción la propaga fuera del
  # contexto antes de que Sentry la capture. Se rellena en Observability::TenancyHook (cada `with_context`) y en el middleware
  # de jobs; Rails lo reinicia solo al terminar cada request o job (ActiveSupport::CurrentAttributes).
  #
  # Guarda IDs, nunca entidades: el log no debe retener modelos.
  class LogContext < ActiveSupport::CurrentAttributes
    attribute :organization_id, :company_id, :branch_id, :job_class

    # Recuerda el último contexto abierto (en un contexto anidado, el más interno).
    def self.remember(context)
      self.organization_id = context.organization&.id
      self.company_id = context.company&.id
      self.branch_id = context.branch&.id
    end
  end
end
