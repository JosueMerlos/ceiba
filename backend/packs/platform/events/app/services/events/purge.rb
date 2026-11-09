module Events
  # Retención del outbox: 30 días. Se borra por lotes (sin una transacción gigante ni bloqueos largos).
  #
  # Un evento pendiente NUNCA se purga, por antiguo que sea (purgeable exige published_at). Una marca de processed_events
  # más vieja que la retención deja de proteger contra duplicados: por eso la retención es mayor que cualquier ventana de
  # reintentos de Sidekiq (que son de ~21 días como máximo).
  module Purge
    RETENTION = 30.days
    BATCH_SIZE = 1_000

    module_function

    def outbox(now: Time.current) = delete_in_batches(OutboxEvent) { OutboxEvent.purgeable(now - RETENTION) }

    def processed(now: Time.current) = delete_in_batches(ProcessedEvent) { ProcessedEvent.older_than(now - RETENTION) }

    # El alcance se construye DENTRO del bloque privilegiado: el filtro de tenant se aplica al construir la relación.
    def delete_in_batches(model)
      total = 0
      CrossTenant.read do
        loop do
          deleted = model.where(id: yield.limit(BATCH_SIZE).select(:id)).delete_all
          total += deleted
          break if deleted < BATCH_SIZE
        end
      end
      total
    end
  end
end
