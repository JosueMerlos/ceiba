module Events
  # Lag del outbox: cuántos eventos esperan y qué edad tiene el más antiguo. Si el relay se detiene, la edad crece sin
  # parar. La alerta se conecta en M0.13 suscribiéndose a la notificación `outbox_lag.events`; mientras tanto queda una
  # línea de log con formato clave=valor.
  module OutboxLag
    module_function

    def measure
      CrossTenant.read do
        oldest = OutboxEvent.pending.in_publication_order.limit(1).pick(:occurred_at)
        { pending: OutboxEvent.pending.count, oldest_age_seconds: oldest ? (Time.current - oldest).to_i : 0 }
      end
    end

    def report
      measurement = measure
      ActiveSupport::Notifications.instrument("outbox_lag.events", measurement)
      Rails.logger.info("events.outbox_lag pending=#{measurement[:pending]} oldest_age_seconds=#{measurement[:oldest_age_seconds]}")
      measurement
    end
  end
end
