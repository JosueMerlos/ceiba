# Sidekiq en modo "fake" por defecto: los jobs encolados se acumulan en memoria (Sidekiq::Queues) y no tocan Redis.
# Los specs de integración con Redis real (relay concurrente, Redis caído) etiquetan el grupo con `:redis` y corren
# con Sidekiq::Testing desactivado (API nueva de Sidekiq 8: Sidekiq.testing!, sin `require "sidekiq/testing"`).
require "sidekiq/api"

Sidekiq.testing!(:fake)

RSpec.configure do |config|
  config.before { Sidekiq::Job.clear_all }

  config.around(:each, :redis) do |example|
    Sidekiq.testing!(:disable)
    Sidekiq.redis(&:flushdb)
    example.run
  ensure
    Sidekiq.testing!(:fake)
  end
end

# `drain`/`perform_one` ejecutan los jobs de prueba por la cadena de middleware de servidor de Sidekiq::Testing: se añade
# el mismo middleware de tenant que en producción (packs/platform/tenancy/config/initializers/sidekiq_tenant.rb).
Sidekiq::Testing.server_middleware { |chain| chain.add TenantJobMiddleware::Server }
