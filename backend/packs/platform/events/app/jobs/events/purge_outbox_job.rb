module Events
  # Borra de outbox_events los eventos PUBLICADOS hace más de 30 días (de todas las organizaciones). Job del sistema.
  class PurgeOutboxJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.outbox
  end
end
