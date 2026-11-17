module Appointments
  # Cancels an appointment recording who cancelled it (`cancelled_by`, set by the caller: the panel is "staff") and why (a code from
  # the closed list the client chooses). The slot is released at once. The customer's cancellation window is not checked here:
  # it limits the customer's own channel, not the staff. Must run inside a tenant context.
  class Cancel
    def self.call(appointment:, reason:, cancelled_by:, actor: Current.principal, now: Time.current)
      raise ArgumentError, "unknown cancelled_by: #{cancelled_by}" unless Appointment::CANCELLED_BY.include?(cancelled_by)

      code = if reason.blank? then :blank
      elsif Appointment::CANCELLATION_REASONS.exclude?(reason) then :invalid
      end
      raise InvalidCancellation, [ { field: :reason, code: } ] if code

      Transition.call(appointment:, action: :cancel, actor:, now:, attributes: { cancelled_by:, cancellation_reason: reason })
    end
  end
end
