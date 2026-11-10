module Events
  # Triggers the relay after commit (a latency optimization; the 5 s cron is the safety net).
  #
  # - ONE trigger per transaction even if several events are published: the first registers an after_commit callback and
  #   the rest see the mark and do nothing. after_rollback clears it.
  # - With Redis down, every COMMIT would wait for the connection timeout. After the first failure it pauses (BACKOFF)
  #   without trying: the failure is silent (a warning is logged) and the cron covers the gap.
  module RelayKick
    BACKOFF = 5.seconds
    PENDING = :events_relay_kick_pending
    FAILED_AT = :events_relay_kick_failed_at

    module_function

    # Call inside the transaction that inserted the event.
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

    # Per thread/fiber: each worker or request has its own mark.
    def state = ActiveSupport::IsolatedExecutionState
  end
end
