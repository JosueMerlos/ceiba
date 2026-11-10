module Events
  # Outbox retention: 30 days, deleted in batches (no giant transaction or long locks).
  #
  # A pending event is NEVER purged, however old (purgeable requires published_at). A processed_events mark older than
  # the retention stops protecting against duplicates, so the retention exceeds any Sidekiq retry window (~21 days at
  # most).
  module Purge
    RETENTION = 30.days
    BATCH_SIZE = 1_000

    module_function

    def outbox(now: Time.current) = delete_in_batches(OutboxEvent) { OutboxEvent.purgeable(now - RETENTION) }

    def processed(now: Time.current) = delete_in_batches(ProcessedEvent) { ProcessedEvent.older_than(now - RETENTION) }

    # The scope is built INSIDE the privileged block: the tenant filter is applied when the relation is built.
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
