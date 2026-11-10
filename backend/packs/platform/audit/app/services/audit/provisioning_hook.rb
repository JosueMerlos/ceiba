module Audit
  # Tenancy::ProvisionOrganization.after_provision hook: audits organization.provisioned inside the provisioning
  # transaction and the new organization's context, so the event is atomic with it.
  # Tenancy does not know Audit; the pack registers this from config.to_prepare. Actor: Current.principal or the system.
  module ProvisioningHook
    KEY = :audit_organization_provisioned

    module_function

    def call(result)
      Audit.record(
        action: "organization.provisioned", subject: result.organization, after: result.organization.attributes,
        metadata: { company_id: result.company.id, branch_id: result.branch.id }
      )
    end

    # Idempotent by `key:`: safe to call on every reload.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
