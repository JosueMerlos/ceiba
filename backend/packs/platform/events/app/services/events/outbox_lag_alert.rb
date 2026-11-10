module Events
  # Outbox lag alert. Hooks into the `outbox_lag.events` notification that Events::OutboxLag.report emits every minute
  # (Events::OutboxLagJob): if the oldest pending event exceeds the threshold, it is reported via Rails.error (picked up
  # by Sentry) as Events::OutboxLagExceeded.
  #
  # Threshold: OUTBOX_LAG_ALERT_SECONDS, 300 (5 min) by default. While the backlog lasts there is one report per minute,
  # all in the same Sentry issue.
  module OutboxLagAlert
    DEFAULT_THRESHOLD_SECONDS = 300

    module_function

    def call(measurement)
      return unless measurement[:pending].to_i.positive? && measurement[:oldest_age_seconds].to_i > threshold_seconds

      Rails.error.report(
        OutboxLagExceeded.new, handled: true, severity: :error,
        context: measurement.slice(:pending, :oldest_age_seconds).merge(threshold_seconds:)
      )
    end

    def threshold_seconds = Integer(ENV.fetch("OUTBOX_LAG_ALERT_SECONDS", DEFAULT_THRESHOLD_SECONDS))
  end
end
