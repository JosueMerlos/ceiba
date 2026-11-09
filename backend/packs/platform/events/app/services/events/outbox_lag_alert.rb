module Events
  # Alerta del lag del outbox (M0.13, docs/architecture/06-events-and-jobs.md). Se engancha a la notificación
  # `outbox_lag.events` que emite Events::OutboxLag.report cada minuto (Events::OutboxLagJob): si el evento pendiente más
  # antiguo supera el umbral, lo reporta con Rails.error (que Sentry recoge) como Events::OutboxLagExceeded.
  #
  # Umbral: OUTBOX_LAG_ALERT_SECONDS, 300 (5 min) por defecto. Mientras dure el atasco habrá un reporte por minuto, todos en la
  # misma incidencia de Sentry.
  module OutboxLagAlert
    DEFAULT_THRESHOLD_SECONDS = 300

    module_function

    def call(measurement)
      return unless measurement[:pending].to_i.positive? && measurement[:oldest_age_seconds].to_i > threshold_seconds

      Rails.error.report(
        OutboxLagExceeded.new, handled: true, severity: :error,
        context: measurement.slice(:pending, :oldest_age_seconds).merge(threshold_seconds:)
      )
    end

    def threshold_seconds = Integer(ENV.fetch("OUTBOX_LAG_ALERT_SECONDS", DEFAULT_THRESHOLD_SECONDS))
  end
end
