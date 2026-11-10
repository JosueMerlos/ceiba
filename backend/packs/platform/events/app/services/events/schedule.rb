module Events
  # Scheduled tasks of the pack (sidekiq-cron), loaded when the Sidekiq process boots. `load_from_hash` (without !) adds
  # or updates without deleting other packs' tasks.
  module Schedule
    JOBS = {
      # Every 5 s: 6-field cron (seconds). The sidekiq-cron poll is 1 s (plus Sidekiq's own 0.5-1.5 s jitter) to honor
      # it.
      "events_relay" => { "class" => "Events::RelayJob", "cron" => "*/5 * * * * *", "description" => "Publica el outbox a Sidekiq" },
      "events_outbox_lag" => { "class" => "Events::OutboxLagJob", "cron" => "* * * * *", "description" => "Mide el lag del outbox" },
      # Overnight (UTC), staggered.
      "events_purge_outbox" => { "class" => "Events::PurgeOutboxJob", "cron" => "17 3 * * *", "description" => "Purga outbox_events publicados > 30 días" },
      "events_purge_processed" => { "class" => "Events::PurgeProcessedJob", "cron" => "27 3 * * *", "description" => "Purga processed_events > 30 días" }
    }.freeze

    module_function

    def jobs = JOBS

    def load!
      Sidekiq::Cron::Job.load_from_hash(JOBS.deep_dup)
    end
  end
end
