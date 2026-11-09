module Observability
  # Los campos de tenant y principal que acompañan a cada línea de log (requests y jobs). Nunca PII: solo identificadores.
  #
  # Genérico a propósito: lee Current.context / Current.principal y, si el contexto ya se cerró, el recordado en
  # Observability::LogContext. Hoy el principal es Identity::Principal::User; cuando M0.08 traiga Access::Principal no
  # hay que tocar nada aquí (el tipo sale del nombre de la clase, o de `principal_type` si el principal lo define).
  module LogFields
    KEYS = %i[organization_id company_id branch_id principal_type principal_id].freeze

    module_function

    def current
      context = Current.context
      principal = Current.principal

      {
        organization_id: context&.organization&.id || LogContext.organization_id,
        company_id: context&.company&.id || LogContext.company_id,
        branch_id: context&.branch&.id || LogContext.branch_id,
        principal_type: principal && principal_type(principal),
        principal_id: principal&.id
      }
    end

    def principal_type(principal)
      principal.respond_to?(:principal_type) ? principal.principal_type.to_s : principal.class.name.demodulize.underscore
    end
  end
end
