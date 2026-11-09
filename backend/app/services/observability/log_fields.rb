module Observability
  # Los campos de tenant y principal que acompañan a cada línea de log (requests y jobs). Nunca PII: solo identificadores.
  #
  # Genérico a propósito: lee Current.context / Current.principal y, si NO hay contexto vivo, el recordado en
  # Observability::LogContext (la línea se escribe cuando el bloque de `Tenancy.with_context` ya terminó). Es UNA fuente por
  # llamada: nunca se mezclan campos de un contexto vivo con restos de otro anterior. Cuando M0.08 traiga Access::Principal
  # no hay que tocar nada aquí: el tipo sale de `principal_type`, de `kind` o del nombre de la clase, y el id puede faltar
  # (el principal del sistema no tiene).
  module LogFields
    KEYS = %i[organization_id company_id branch_id principal_type principal_id].freeze

    module_function

    def current
      principal = Current.principal

      tenant.merge(principal_type: principal && principal_type(principal), principal_id: principal.try(:id))
    end

    def tenant
      context = Current.context
      return { organization_id: context.organization&.id, company_id: context.company&.id, branch_id: context.branch&.id } if context

      { organization_id: LogContext.organization_id, company_id: LogContext.company_id, branch_id: LogContext.branch_id }
    end

    def principal_type(principal)
      (principal.try(:principal_type) || principal.try(:kind) || principal.class.name.demodulize.underscore).to_s
    end
  end
end
