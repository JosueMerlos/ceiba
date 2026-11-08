module Events
  # Hook de Tenancy::ProvisionOrganization.after_provision: publica platform.organization_provisioned.v1. Corre dentro
  # de la transacción de la provisión y del contexto de la organización nueva, así que el evento nace atómico con ella
  # (si otro hook falla, la organización y el evento desaparecen juntos). Tenancy no conoce a Events: el pack se engancha
  # desde config.to_prepare (config/initializers/provisioning_hook.rb).
  module ProvisioningHook
    KEY = :events_organization_provisioned

    module_function

    def call(result)
      Events.publish(
        "platform.organization_provisioned.v1",
        organization_id: result.organization.id, company_id: result.company.id, branch_id: result.branch.id
      )
    end

    # Idempotente por `key:`: se puede llamar en cada recarga.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
