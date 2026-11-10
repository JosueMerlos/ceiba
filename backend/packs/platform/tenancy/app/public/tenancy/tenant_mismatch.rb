module Tenancy
  # Tried to write (create or destroy) a record whose organization_id is not the active tenant's.
  class TenantMismatch < Error; end
end
