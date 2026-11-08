module Tenancy
  # Se intentó escribir (crear o destruir) un registro cuyo organization_id no es el del tenant activo.
  class TenantMismatch < Error; end
end
