module Idempotency
  # Scheduled tasks of the pack (sidekiq-cron), loaded when the Sidekiq process boots. `load_from_hash` (without !) adds
  # or updates without deleting other packs' tasks.
  module Schedule
    JOBS = {
      "idempotency_purge_expired" => { "class" => "Idempotency::PurgeExpiredJob", "cron" => "37 3 * * *", "description" => "Purga idempotency_keys vencidas" }
    }.freeze

    module_function

    def jobs = JOBS

    def load! = Sidekiq::Cron::Job.load_from_hash(JOBS.deep_dup)
  end
end
