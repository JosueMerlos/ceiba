# Sidekiq en modo "fake" por defecto: los jobs encolados se acumulan en memoria (Sidekiq::Queues) y no tocan Redis.
# Los specs de integración con Redis real (relay concurrente, Redis caído) etiquetan el grupo con `:redis` y corren
# con Sidekiq::Testing desactivado (API nueva de Sidekiq 8: Sidekiq.testing!, sin `require "sidekiq/testing"`).
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
