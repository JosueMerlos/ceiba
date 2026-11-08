module Events
  # Publica el outbox (Events::Relay). Lo programa sidekiq-cron cada 5 s y se dispara también tras el commit de cada
  # evento. Es un job del SISTEMA: cruza organizaciones, así que declara `tenant: false` (sin él el middleware lo rechaza).
  #
  # Sin reintentos de Sidekiq: el cron lo vuelve a lanzar en 5 s y un reintento acumulado solo apilaría relays. El fallo
  # no se pierde: se reporta al error reporter de Rails (Sentry lo recoge cuando exista), queda en outbox_events
  # (attempts, last_error) y el lag crece hasta disparar la alerta (M0.13).
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
