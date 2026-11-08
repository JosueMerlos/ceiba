module Tenancy
  # Se intentó cambiar el organization_id de un registro existente: un registro nunca cambia de tenant.
  class TenantIsImmutable < Error; end
end
