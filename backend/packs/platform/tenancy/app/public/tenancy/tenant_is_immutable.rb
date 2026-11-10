module Tenancy
  # Tried to change an existing record's organization_id: a record never changes tenant.
  class TenantIsImmutable < Error; end
end
