module Imports
  # Scheduled tasks of the pack (sidekiq-cron), loaded when the Sidekiq process boots. Hourly, so an unconfirmed preview
  # outlives its 24 hours by one hour at most.
  module Schedule
    JOBS = {
      "imports_purge_expired" => { "class" => "Imports::PurgeExpiredJob", "cron" => "23 * * * *", "description" => "Vence importaciones sin confirmar y cierra las atascadas" }
    }.freeze

    module_function

    def jobs = JOBS

    def load! = Sidekiq::Cron::Job.load_from_hash(JOBS.deep_dup)
  end
end
