module Events
  # System job: purges processed_events marks older than 30 days (all organizations).
  class PurgeProcessedJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.processed
  end
end
