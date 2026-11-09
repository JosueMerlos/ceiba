module Idempotency
  # Borra las idempotency_keys vencidas de todas las organizaciones. Job del sistema (sin organización).
  class PurgeExpiredJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.expired
  end
end
