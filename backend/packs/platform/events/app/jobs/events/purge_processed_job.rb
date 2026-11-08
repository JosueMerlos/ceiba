module Events
  # Borra de processed_events las marcas de idempotencia de más de 30 días (de todas las organizaciones). Job del sistema.
  class PurgeProcessedJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.processed
  end
end
