module Idempotency
  # Tareas programadas del pack (sidekiq-cron). Se cargan al arrancar el proceso de Sidekiq
  # (config/initializers/sidekiq_cron.rb). `load_from_hash` (sin !) añade o actualiza sin borrar las de otros packs.
  module Schedule
    JOBS = {
      "idempotency_purge_expired" => { "class" => "Idempotency::PurgeExpiredJob", "cron" => "37 3 * * *", "description" => "Purga idempotency_keys vencidas" }
    }.freeze

    module_function

    def jobs = JOBS

    def load! = Sidekiq::Cron::Job.load_from_hash(JOBS.deep_dup)
  end
end
