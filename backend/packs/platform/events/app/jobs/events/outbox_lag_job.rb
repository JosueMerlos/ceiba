module Events
  # System job: measures and reports the outbox lag (Events::OutboxLag).
  class OutboxLagJob
    include Sidekiq::Job

    sidekiq_options queue: "default", tenant: false

    def perform = OutboxLag.report
  end
end
