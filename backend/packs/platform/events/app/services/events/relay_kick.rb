module Events
  # Disparo del relay tras el commit (optimización de latencia; el cron de 5 s es la red de seguridad).
  #
  # - UN solo disparo por transacción, aunque se publiquen varios eventos: el primero registra un callback after_commit y
  #   los demás ven la marca y no hacen nada. after_rollback la limpia.
  # - Con Redis caído, cada COMMIT esperaría el timeout de conexión. Tras el primer fallo se hace una pausa (BACKOFF) sin
  #   intentar: el fallo es silencioso (se registra un aviso) y el cron cubre el hueco.
  module RelayKick
    BACKOFF = 5.seconds
    PENDING = :events_relay_kick_pending
    FAILED_AT = :events_relay_kick_failed_at

    module_function

    # Llamar dentro de la transacción que insertó el evento.
    def schedule(connection = ApplicationRecord.connection)
      return if state[PENDING] || backing_off?

      state[PENDING] = true
      transaction = connection.current_transaction
      transaction.after_commit { fire }
      transaction.after_rollback { state[PENDING] = false }
    end

    def reset!
      state[PENDING] = false
      state[FAILED_AT] = nil
    end

    def fire
      state[PENDING] = false
      RelayJob.perform_async unless backing_off?
    rescue StandardError => error
      state[FAILED_AT] = Time.current
      Rails.logger.warn("events.kick_relay no pudo encolar el relay (el cron lo cubre): #{error.class}: #{error.message}")
    end

    def backing_off?
      failed_at = state[FAILED_AT]
      failed_at.present? && Time.current < failed_at + BACKOFF
    end

    # Por hilo/fibra: cada worker o request tiene su propia marca.
    def state = ActiveSupport::IsolatedExecutionState
  end
end
