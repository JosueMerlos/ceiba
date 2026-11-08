# El tenant es la ORGANIZACIÓN (ADR-0003) y es obligatorio: toda consulta a una tabla tenant sin organización activa
# lanza ActsAsTenant::Errors::NoTenantSet en lugar de devolver filas de todos los clientes (barrera 1,
# docs/architecture/03-multi-tenancy.md). Solo Tenancy.with_context fija el tenant.
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
