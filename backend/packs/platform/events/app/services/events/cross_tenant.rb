module Events
  # ÚNICO sitio del pack que lee el outbox de TODAS las organizaciones a la vez (el relay, las purgas y la medición del
  # lag). Es un camino privilegiado: el archivo está en AllowedFiles de Ceiba/TenantBypass (.rubocop.yml) y cada cambio
  # aquí exige revisión. Con RLS (M4.03) estas lecturas necesitarán el rol de plataforma con BYPASSRLS.
  #
  # Solo LEE o BORRA datos del propio outbox. Las escrituras de estado (published_at, attempts) las hace el llamador
  # organización por organización, dentro de Tenancy.with_context, para que pasen por el guard de escritura.
  module CrossTenant
    def self.read(&) = ActsAsTenant.without_tenant(&)
  end
end
