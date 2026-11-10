require_relative "../../lib/tenant_job_middleware"

# Client (also inside the server: a job that enqueues another) and server. Sidekiq.configure_* runs once per process.
# Specs add the server middleware to Sidekiq::Testing's chain.
Sidekiq.configure_client { |config| config.client_middleware { |chain| chain.add TenantJobMiddleware::Client } }

Sidekiq.configure_server do |config|
  config.client_middleware { |chain| chain.add TenantJobMiddleware::Client }
  config.server_middleware { |chain| chain.add TenantJobMiddleware::Server }
end

# acts_as_tenant installs an Active Job extension that serializes the tenant on enqueue and restores it on perform WITHOUT
# going through Tenancy.with_context (it does not write app.organization_id, so under RLS the job would see Ruby's tenant
# but the database would not). Its methods are removed: Active Job falls back to its own and the middleware above is the only
# path. The active_job_tenant spec pins the reviewed gem version.
%i[serialize deserialize perform_now deserialize_arguments_if_needed].each do |name|
  extension = ActsAsTenant::ActiveJobExtensions
  extension.send(:remove_method, name) if extension.method_defined?(name) || extension.private_method_defined?(name)
end
