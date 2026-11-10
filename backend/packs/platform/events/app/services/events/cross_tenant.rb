module Events
  # The ONLY place in the pack that reads the outbox of ALL organizations at once (relay, purges, lag measurement). A
  # privileged path: the file is in AllowedFiles of Ceiba/TenantBypass (.rubocop.yml) and every change here needs
  # review. With RLS enforced, these reads will need the platform role with BYPASSRLS.
  #
  # It only READS or DELETES outbox data. State writes (published_at, attempts) are done by the caller organization by
  # organization, inside Tenancy.with_context, so they go through the write guard.
  module CrossTenant
    def self.read(&) = ActsAsTenant.without_tenant(&)
  end
end
