module Events
  # Delivers an event to ONE subscriber. The relay enqueues it with the organization_id in the payload; the Sidekiq
  # middleware (TenantJobMiddleware) runs it inside Tenancy.with_context, i.e. in a transaction with the event's tenant.
  #
  # Idempotency: processed_events has UNIQUE (event_id, subscriber). The mark is inserted BEFORE invoking the
  # subscriber, in the same transaction: if the subscriber raises, everything (mark included) rolls back and Sidekiq
  # retries; if the mark already existed, the delivery is a duplicate and does nothing. Two simultaneous deliveries: the
  # second waits for the first's COMMIT and gets RecordNotUnique.
  class DeliverJob
    include Sidekiq::Job

    sidekiq_options queue: "critical"

    # A subscriber this process does not know is not fixed by retrying for ~21 days: send it to the dead queue
    # immediately.
    sidekiq_retry_in { |_count, exception| exception.is_a?(UnknownSubscriber) ? :kill : :default }

    def perform(event_id, subscriber)
      record = OutboxEvent.find(event_id)
      subscription = Subscriptions.find(record.name, subscriber) || raise(UnknownSubscriber.new(record.name, subscriber))
      return unless first_delivery?(record, subscriber)

      subscription.handler.call(record.to_event)
    end

    private

    # The savepoint lets us catch the uniqueness violation without aborting the context's transaction.
    def first_delivery?(record, subscriber)
      ProcessedEvent.transaction(requires_new: true) { ProcessedEvent.create!(event_id: record.id, subscriber:, processed_at: Time.current) }
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end
