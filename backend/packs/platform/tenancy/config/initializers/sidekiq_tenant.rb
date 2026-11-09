require_relative "../../lib/tenant_job_middleware"

# Cliente (también dentro del servidor: un job que encola otro) y servidor. Sidekiq.configure_* se ejecuta una vez por
# proceso. Los specs añaden el middleware de servidor a la cadena de Sidekiq::Testing (spec/support/sidekiq_testing.rb).
Sidekiq.configure_client { |config| config.client_middleware { |chain| chain.add TenantJobMiddleware::Client } }

Sidekiq.configure_server do |config|
  config.client_middleware { |chain| chain.add TenantJobMiddleware::Client }
  config.server_middleware { |chain| chain.add TenantJobMiddleware::Server }
end

# acts_as_tenant instala una extensión de Active Job que serializa el tenant al encolar y lo restaura al ejecutar SIN
# pasar por Tenancy.with_context (no escribe app.organization_id, así que con RLS el job vería el tenant de Ruby pero la
# base no). Se retiran sus métodos: Active Job vuelve a sus implementaciones y el único camino es el middleware de arriba.
# El spec de config/active_job_tenant_spec.rb fija la versión de la gema revisada.
%i[serialize deserialize perform_now deserialize_arguments_if_needed].each do |name|
  extension = ActsAsTenant::ActiveJobExtensions
  extension.send(:remove_method, name) if extension.method_defined?(name) || extension.private_method_defined?(name)
end
