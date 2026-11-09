module Events
  # Publica los eventos pendientes del outbox a Sidekiq (docs/architecture/06-events-and-jobs.md).
  #
  # Por lote, en UNA transacción:
  #   1. SELECT ... ORDER BY id LIMIT n FOR UPDATE SKIP LOCKED: dos relays concurrentes toman lotes distintos y nunca el
  #      mismo evento; las filas bloqueadas por otro relay se saltan en lugar de esperar.
  #   2. encola un DeliverJob por (evento, suscriptor), agrupando por organización y cola (push_bulk);
  #   3. marca published_at.
  # Si el paso 2 falla (Redis caído) la transacción se revierte: los eventos siguen pendientes y el siguiente relay los
  # toma; el intento y el error se anotan (attempts, last_error). Si Redis aceptó parte de los jobs y luego falla el
  # COMMIT, el reintento los vuelve a encolar: la entrega es al menos una vez y los suscriptores son idempotentes
  # (processed_events).
  class Relay
    DEFAULT_BATCH_SIZE = 100
    MAX_ERROR_LENGTH = 1_000

    def self.call(batch_size: DEFAULT_BATCH_SIZE) = new(batch_size:).call

    def initialize(batch_size: DEFAULT_BATCH_SIZE)
      @batch_size = batch_size
    end

    # Devuelve cuántos eventos publicó.
    def call
      total = 0
      loop do
        published = relay_batch
        total += published
        break if published < @batch_size
      end
      total
    end

    private

    def relay_batch
      events = []
      ApplicationRecord.transaction(requires_new: true) do
        events = claim
        publish(events) if events.any?
      end
      events.size
    rescue StandardError => error
      record_failure(events, error)
      raise
    end

    def claim
      CrossTenant.read do
        OutboxEvent.pending.in_publication_order.limit(@batch_size).lock("FOR UPDATE SKIP LOCKED").preload(:organization).to_a
      end
    end

    def publish(events)
      enqueue(events)
      per_organization(events) { |ids| OutboxEvent.where(id: ids).update_all(published_at: Time.current) }
    end

    def enqueue(events)
      deliveries = events.flat_map { |event| Subscriptions.for_event(event.name).map { |subscription| [ event, subscription ] } }
      deliveries.group_by { |event, subscription| [ event.organization_id, subscription.queue ] }.each do |(organization_id, queue), pairs|
        Sidekiq::Client.push_bulk(
          "class" => DeliverJob, "queue" => queue, "organization_id" => organization_id,
          "args" => pairs.map { |event, subscription| [ event.id, subscription.subscriber ] }
        )
      end
    end

    # El error se anota fuera de la transacción revertida. Si anotarlo también falla se conserva el error original.
    def record_failure(events, error)
      return if events.empty?

      message = "#{error.class}: #{error.message}".truncate(MAX_ERROR_LENGTH)
      per_organization(events) do |ids|
        OutboxEvent.where(id: ids).update_all([ "attempts = attempts + 1, last_error = ?", message ])
      end
    rescue StandardError => nested
      Rails.logger.error("events.relay no pudo anotar el fallo: #{nested.class}: #{nested.message}")
    end

    # Las escrituras de estado pasan por el guard de tenant: una organización cada vez, dentro de su contexto.
    def per_organization(events)
      events.group_by(&:organization_id).each_value do |group|
        Tenancy.with_context(organization: group.first.organization) { yield group.map(&:id) }
      end
    end
  end
end
