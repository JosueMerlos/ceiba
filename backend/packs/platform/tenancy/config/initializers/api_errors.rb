# Errores de dominio de tenancy que la API traduce a problem+json (ver Api::ErrorRegistry).
#
# - ProvisioningFailed: validación de la provisión (422) o conflicto de slug (409); `errors[]` desglosa sección.campo.
# - InconsistentContext: la ruta mezcla entidades que no encajan (empresa de otra organización...). Es 404 y NO 403,
#   para no revelar que la otra entidad existe (07-api-contract). El mensaje no sale: nombra entidades.
# - TenantMismatch / TenantIsImmutable NO se registran a propósito: solo ocurren si el servidor intentó escribir en
#   otro tenant, es decir, un BUG. Se responden 500 genérico (07: "500: solo bugs") y se investigan por el log.
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(
    Tenancy::ProvisioningFailed,
    status: ->(error) { error.code == :slug_taken ? :conflict : :unprocessable_content },
    code: ->(error) { "tenancy.#{error.code}" },
    errors: lambda { |error|
      error.details.flat_map do |section, fields|
        fields.flat_map { |field, messages| Array(messages).map { |message| { field: "#{section}.#{field}", code: "invalid", message: } } }
      end
    }
  )
  Api::ErrorRegistry.register(Tenancy::InconsistentContext, status: :not_found, code: "tenancy.inconsistent_context")
end
