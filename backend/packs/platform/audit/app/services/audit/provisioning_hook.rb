module Audit
  # Hook de Tenancy::ProvisionOrganization.after_provision: audita organization.provisioned. Corre dentro de la transacción
  # de la provisión y del contexto de la organización nueva, así que el evento nace atómico con ella. Tenancy no conoce a
  # Audit: el pack se engancha desde config.to_prepare (config/initializers/provisioning_hook.rb). El actor es el
  # principal que provisiona (Current.principal) o el sistema.
  module ProvisioningHook
    KEY = :audit_organization_provisioned

    module_function

    def call(result)
      Audit.record(
        action: "organization.provisioned", subject: result.organization, after: result.organization.attributes,
        metadata: { company_id: result.company.id, branch_id: result.branch.id }
      )
    end

    # Idempotente por `key:`: se puede llamar en cada recarga.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
