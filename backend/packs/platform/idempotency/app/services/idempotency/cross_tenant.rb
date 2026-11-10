module Idempotency
  # The ONLY place in the pack that operates on idempotency_keys of ALL organizations at once (purge of expired keys). A
  # privileged path: the file is in AllowedFiles of Ceiba/TenantBypass (.rubocop.yml) and every change here needs
  # review. With RLS enforced it will need the platform role with BYPASSRLS. Same pattern as Events::CrossTenant.
  module CrossTenant
    def self.run(&) = ActsAsTenant.without_tenant(&)
  end
end
