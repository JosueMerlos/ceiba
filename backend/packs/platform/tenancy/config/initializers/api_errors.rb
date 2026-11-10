# Tenancy domain errors the API translates to problem+json (see Api::ErrorRegistry).
#
# - ProvisioningFailed: provisioning validation (422) or slug conflict (409); `errors[]` breaks down section.field.
# - InconsistentContext: the route mixes entities that do not fit (company from another organization...). It is 404 and NOT
#   403, so it does not reveal the other entity exists. The message is not exposed: it names entities.
# - TenantMismatch / TenantIsImmutable are deliberately NOT registered: they only happen if the server tried to write to
#   another tenant, i.e. a BUG. They answer a generic 500 (500s mean bugs only) and are investigated through the log.
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
