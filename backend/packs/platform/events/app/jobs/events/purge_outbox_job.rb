module Events
  # System job: purges outbox_events PUBLISHED more than 30 days ago (all organizations).
  class PurgeOutboxJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.outbox
  end
end
