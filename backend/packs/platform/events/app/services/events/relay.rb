module Events
  # Publishes pending outbox events to Sidekiq.
  #
  # Per batch, in ONE transaction:
  #   1. SELECT ... ORDER BY id LIMIT n FOR UPDATE SKIP LOCKED: concurrent relays take different batches and never the
  #      same event; rows locked by another relay are skipped, not waited on.
  #   2. enqueue one DeliverJob per (event, subscriber), grouped by organization and queue (push_bulk);
  #   3. mark published_at.
  # If step 2 fails (Redis down) the transaction rolls back: events stay pending and the next relay picks them up; the
  # attempt and error are recorded (attempts, last_error). If Redis accepted some jobs and the COMMIT then fails, the
  # retry enqueues them again: delivery is at-least-once and subscribers are idempotent (processed_events).
  class Relay
    DEFAULT_BATCH_SIZE = 100
    MAX_ERROR_LENGTH = 1_000

    def self.call(batch_size: DEFAULT_BATCH_SIZE) = new(batch_size:).call

    def initialize(batch_size: DEFAULT_BATCH_SIZE)
      @batch_size = batch_size
    end

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

    # The error is recorded outside the rolled-back transaction. If recording it also fails, the original error is kept.
    def record_failure(events, error)
      return if events.empty?

      message = "#{error.class}: #{error.message}".truncate(MAX_ERROR_LENGTH)
      per_organization(events) do |ids|
        OutboxEvent.where(id: ids).update_all([ "attempts = attempts + 1, last_error = ?", message ])
      end
    rescue StandardError => nested
      Rails.logger.error("events.relay no pudo anotar el fallo: #{nested.class}: #{nested.message}")
    end

    # State writes go through the tenant guard: one organization at a time, inside its context.
    def per_organization(events)
      events.group_by(&:organization_id).each_value do |group|
        Tenancy.with_context(organization: group.first.organization) { yield group.map(&:id) }
      end
    end
  end
end
