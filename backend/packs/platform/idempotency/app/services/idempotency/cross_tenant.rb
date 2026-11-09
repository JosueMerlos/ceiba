module Idempotency
  # ÚNICO sitio del pack que opera sobre idempotency_keys de TODAS las organizaciones a la vez (la purga de claves
  # vencidas). Es un camino privilegiado: el archivo está en AllowedFiles de Ceiba/TenantBypass (.rubocop.yml) y cada cambio
  # aquí exige revisión. Con RLS (M4.03) necesitará el rol de plataforma con BYPASSRLS. Mismo patrón que Events::CrossTenant.
  module CrossTenant
    def self.run(&) = ActsAsTenant.without_tenant(&)
  end
end
