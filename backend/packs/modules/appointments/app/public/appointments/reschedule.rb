module Appointments
  # Moves an appointment by booking a new one linked to it: the original is locked and turns `rescheduled` FIRST (so it no longer
  # blocks and can move by a few minutes over itself), then Book creates the new one with `rescheduled_from`, all in one savepoint.
  # Any refusal of Book (a taken slot, an archived service, an inactive customer) rolls the original back to its status; a second
  # reschedule of the same appointment waits on the row lock and then finds it already `rescheduled` (InvalidTransition).
  #
  # The new appointment keeps the customer, the services in their order, the notes and the price the customer was quoted (per
  # line, from the original's snapshot); the duration is the catalog's current one, which the engine validates. `source` picks the
  # booking window, like Book. Must run inside a tenant context.
  class Reschedule
    def self.call(...) = new(...).call

    def initialize(appointment:, company:, branch:, starts_at:, professional:, source:, actor: Current.principal, now: Time.current)
      raise ArgumentError, "the branch is not the appointment's branch" unless appointment.branch_id == branch.id

      @appointment = appointment
      @company = company
      @branch = branch
      @starts_at = starts_at
      @choice = professional
      @source = source
      @actor = actor
      @now = now
    end

    def call
      moved = nil
      Transition.call(appointment: @appointment, action: :reschedule, actor: @actor, now: @now) do |original|
        moved = book(original)
        { new_appointment_id: moved.id }
      end
      moved
    end

    private

    # `original` is the row Transition locked, so the snapshot and the notes are the ones being moved.
    def book(original)
      lines = original.services_snapshot.to_a
      Book.call(company: @company, branch: @branch, customer_id: original.customer_id, starts_at: @starts_at, professional: @choice,
                services: Service.where(company_id: @company.id).in_order(lines.map(&:service_id)), source: @source, notes: original.notes,
                actor: @actor, now: @now, rescheduled_from: original,
                price_lines: lines.to_h { [ it.service_id, { price_minor: it.price_minor, currency: it.currency } ] })
    end
  end
end
