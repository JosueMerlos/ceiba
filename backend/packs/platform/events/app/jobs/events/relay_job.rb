module Events
  # Publishes the outbox (Events::Relay). Scheduled by sidekiq-cron every 5 s and also triggered after each event's
  # commit. A SYSTEM job: it crosses organizations, so it declares `tenant: false` (the middleware rejects it
  # otherwise).
  #
  # No Sidekiq retries: cron relaunches it in 5 s and a queued retry would only pile up relays. A failure is not lost:
  # it is reported to Rails' error reporter, recorded in outbox_events (attempts, last_error), and the lag grows until
  # the alert fires.
  class RelayJob
    include Sidekiq::Job

    sidekiq_options queue: "critical", tenant: false, retry: false

    def perform
      Relay.call
    rescue StandardError => error
      Rails.error.report(error, handled: true, severity: :error, context: { job: self.class.name })
    end
  end
end
