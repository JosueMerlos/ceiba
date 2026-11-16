module Appointments
  # The only writer of an appointment's status. Locks the row (SELECT ... FOR UPDATE), checks the rule of the action against the
  # LOCKED status, and moves it with one UPDATE conditioned on the origin statuses, so a concurrent change can never be
  # overwritten: zero rows is InvalidTransition. The version goes up with it, so a stale edit of the same appointment conflicts.
  # The event and the audit record share the savepoint. Must run inside a tenant context.
  #
  # A block (`follow_up`) runs inside the same savepoint after the UPDATE and receives the locked appointment: whatever it raises
  # rolls the transition back, and the hash it returns is added to the event and to the audit record. Rescheduling books the new
  # appointment there.
  class Transition
    def self.call(...) = new(...).call

    def initialize(appointment:, action:, actor: Current.principal, now: Time.current, attributes: {}, &follow_up)
      @appointment = appointment
      @rule = Transitions.fetch(action)
      @actor = actor || Access::Principal::System.new
      @now = now
      @attributes = attributes.to_h.symbolize_keys
      @follow_up = follow_up
    end

    def call
      unknown = @attributes.keys - @rule.attributes
      raise ArgumentError, "#{@rule.action} does not take #{unknown.join(', ')}" if unknown.any?

      ApplicationRecord.transaction(requires_new: true) do
        # Not `lock!`: `reload` drops the tenant scope, so the row would be found in another organization wherever RLS is off.
        @appointment = Appointment.lock.find(@appointment.id)
        from = @appointment.status
        check!(from)
        move!
        extra = @follow_up ? @follow_up.call(@appointment).to_h : {}
        @appointment = Appointment.find(@appointment.id)
        publish_and_audit(from, extra)
        @appointment
      end
    end

    private

    def check!(from)
      raise InvalidTransition, :not_allowed unless @rule.from.include?(from)
      raise InvalidTransition, :too_early if @rule.not_before_start? && @now < @appointment.starts_at
    end

    def move!
      changes = Appointment.sanitize_sql_for_assignment({ status: @rule.to, updated_at: @now, **@attributes })
      moved = Appointment.where(id: @appointment.id, status: @rule.from).update_all("#{changes}, lock_version = lock_version + 1")
      raise InvalidTransition, :not_allowed unless moved == 1
    end

    def publish_and_audit(from, extra)
      appointment = @appointment
      Events.publish(@rule.event, { appointment_id: appointment.id, branch_id: appointment.branch_id, professional_id: appointment.professional_id,
                                    customer_id: appointment.customer_id, starts_at: appointment.starts_at, ends_at: appointment.ends_at,
                                    from_status: from, **@attributes, **extra },
                     metadata: { company_id: appointment.company_id, branch_id: appointment.branch_id })
      Audit.record(action: "appointments.appointment.#{@rule.to}", subject: appointment, before: { status: from },
                   after: { status: @rule.to, **@attributes, **extra }, actor: @actor)
    end
  end
end
