# The tenant is the ORGANIZATION and is mandatory: any query to a tenant table without an active organization raises
# ActsAsTenant::Errors::NoTenantSet instead of returning every customer's rows. Only Tenancy.with_context sets the tenant.
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
