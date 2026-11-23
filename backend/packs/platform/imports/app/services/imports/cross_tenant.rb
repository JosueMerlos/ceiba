module Imports
  # The ONLY place in the pack that reads import batches of ALL organizations at once: which organizations have
  # expired previews or stuck batches to purge. It only reads; the purge itself runs per organization. A privileged path: the file is in
  # AllowedFiles of Ceiba/TenantBypass (.rubocop.yml) and every change here needs review. With RLS enforced it will need
  # the platform role with BYPASSRLS. Same pattern as Idempotency::CrossTenant.
  module CrossTenant
    def self.run(&) = ActsAsTenant.without_tenant(&)
  end
end
