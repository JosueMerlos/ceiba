module Events
  # Entrega un evento a UN suscriptor. Lo encola el relay con el organization_id en el payload; el middleware de Sidekiq
  # (TenantJobMiddleware) lo ejecuta dentro de Tenancy.with_context, o sea, en una transacción y con el tenant del evento.
  #
  # Idempotencia: processed_events tiene UNIQUE (event_id, subscriber). Se inserta la marca ANTES de invocar al
  # suscriptor y en la misma transacción: si el suscriptor lanza, se revierte todo (marca incluida) y Sidekiq reintenta;
  # si la marca ya existía, la entrega es un duplicado y no hace nada. Dos entregas simultáneas: la segunda espera al
  # COMMIT de la primera y recibe RecordNotUnique.
  #
  # Pendiente de M0.09: verificar que el módulo del suscriptor esté activo para la empresa del evento.
  class DeliverJob
    include Sidekiq::Job

    sidekiq_options queue: "critical"

    def perform(event_id, subscriber)
      record = OutboxEvent.find(event_id)
      subscription = Subscriptions.find(record.name, subscriber) || raise(UnknownSubscriber.new(record.name, subscriber))
      return unless first_delivery?(record, subscriber)

      subscription.handler.call(record.to_event)
    end

    private

    # El savepoint permite capturar la violación de unicidad sin abortar la transacción del contexto.
    def first_delivery?(record, subscriber)
      ProcessedEvent.transaction(requires_new: true) { ProcessedEvent.create!(event_id: record.id, subscriber:, processed_at: Time.current) }
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end
