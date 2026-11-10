module Events
  # Outbox lag: how many events wait and how old the oldest is. If the relay stops, the age grows without bound.
  # Events::OutboxLagAlert subscribes to the `outbox_lag.events` notification and reports to Sentry above the threshold;
  # a key=value log line is also written.
  module OutboxLag
    module_function

    def measure
      CrossTenant.read do
        oldest = OutboxEvent.pending.in_publication_order.limit(1).pick(:occurred_at)
        { pending: OutboxEvent.pending.count, oldest_age_seconds: oldest ? (Time.current - oldest).to_i : 0 }
      end
    end

    def report
      measurement = measure
      ActiveSupport::Notifications.instrument("outbox_lag.events", measurement)
      Rails.logger.info("events.outbox_lag pending=#{measurement[:pending]} oldest_age_seconds=#{measurement[:oldest_age_seconds]}")
      measurement
    end
  end
end
