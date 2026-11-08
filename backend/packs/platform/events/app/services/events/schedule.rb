module Events
  # Tareas programadas del pack (sidekiq-cron). Se cargan al arrancar el proceso de Sidekiq
  # (config/initializers/sidekiq_cron.rb). `load_from_hash` (sin !) añade o actualiza sin borrar las de otros packs.
  module Schedule
    JOBS = {
      # Cada 5 s: cron de 6 campos (segundos). El poll de sidekiq-cron es de 2 s para cumplirlo.
      "events_relay" => { "class" => "Events::RelayJob", "cron" => "*/5 * * * * *", "description" => "Publica el outbox a Sidekiq" },
      "events_outbox_lag" => { "class" => "Events::OutboxLagJob", "cron" => "* * * * *", "description" => "Mide el lag del outbox" },
      # De madrugada (UTC), escalonadas.
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
