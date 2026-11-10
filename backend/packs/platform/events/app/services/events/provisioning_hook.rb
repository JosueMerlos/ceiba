module Events
  # Tenancy::ProvisionOrganization.after_provision hook: publishes platform.organization_provisioned.v1. Runs inside the
  # provisioning transaction and the new organization's context, so the event is atomic with it (if another hook fails,
  # the organization and the event vanish together).
  # Tenancy does not know Events; the pack registers this from config.to_prepare.
  module ProvisioningHook
    KEY = :events_organization_provisioned

    module_function

    def call(result)
      Events.publish(
        "platform.organization_provisioned.v1",
        organization_id: result.organization.id, company_id: result.company.id, branch_id: result.branch.id
      )
    end

    # Idempotent by `key:`: safe to call on every reload.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
