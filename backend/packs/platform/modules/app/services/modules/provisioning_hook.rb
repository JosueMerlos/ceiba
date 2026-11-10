module Modules
  # Tenancy::ProvisionOrganization.after_provision hook: enables the default modules (`Modules.default_keys`) in the new
  # company. Runs inside the provisioning transaction and the new organization's context: if anything fails (e.g. a default
  # key no manifest declares) the WHOLE provisioning rolls back. Tenancy does not know modules; this pack hooks in from
  # config.to_prepare.
  module ProvisioningHook
    KEY = :modules_defaults

    module_function

    def call(result)
      Modules.default_keys.each { |key| Enable.call(company: result.company, key:) }
    end

    # Idempotent by `key:`, so it can be called on every reload.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
