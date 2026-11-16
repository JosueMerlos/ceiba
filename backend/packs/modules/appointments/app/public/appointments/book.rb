module Appointments
  # The only creator of appointments. Books a concrete professional at an exact start and leaves the agenda consistent however many
  # requests race for it: advisory locks serialize the people and the resource kind involved, the engine is asked again AFTER the
  # locks (it must still offer that exact start, with the professional and the resource it assigns), and the exclusion constraints
  # are the last barrier. The appointment, its service lines, the event and the audit record share one savepoint, so a caller that
  # rescues a conflict can keep using its own transaction. Must run inside a tenant context.
  #
  # The window the engine applies follows the source: the panel (staff) may book inside the lead time or beyond the advance limit, a
  # public booking may not. A conflict is SlotUnavailable (409), whoever loses the race; PersonUnavailable (409) is the same
  # person overlapping in another company of the group, which the engine does not see; InvalidBooking and
  # Availability::InvalidRequest (422) are requests that were wrong to begin with.
  class Book
    NOTES_MAX_LENGTH = 500
    WINDOW_BY_SOURCE = { "panel" => :staff, "public_booking" => :customer }.freeze
    AUDITED_FIELDS = %w[branch_id professional_id resource_id customer_id starts_at ends_at status source notes rescheduled_from_id].freeze
    RESOURCE_FK = "fk_appointments_resource".freeze
    AUDITED_LINE_FIELDS = %i[service_id position duration_minutes price_minor].freeze

    def self.call(...) = new(...).call

    def initialize(company:, branch:, customer_id:, services:, professional:, starts_at:, source:, notes: nil, actor: Current.principal,
                   now: Time.current, rescheduled_from: nil)
      @company = company
      @branch = branch
      @customer_id = customer_id
      @services = services
      @choice = professional
      @starts_at = starts_at
      @source = source
      @notes = notes.presence
      @actor = actor || Access::Principal::System.new
      @now = now
      @rescheduled_from = rescheduled_from
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        validate_input!
        eligibility = Availability.ensure_eligible!(company: @company, branch: @branch, services: @services, professional: @choice,
                                                    from_date: local_date, to_date: local_date, now: @now)
        lock_person
        lock_resource(eligibility.required_kind)
        slot, plan = revalidate(eligibility)
        ensure_person_free(slot, plan)
        insert(slot, plan).tap { |appointment| publish_and_audit(appointment, plan) }
      end
    rescue ActiveRecord::ExclusionViolation, ActiveRecord::Deadlocked => error
      # Outside the savepoint, which the failed statement already rolled back.
      conflict!(error)
    rescue ActiveRecord::InvalidForeignKey => error
      # Only the resource's composite FK is a lost race (the resource went away or changed branch after the revalidation).
      raise unless violated_constraint(error) == RESOURCE_FK

      conflict!(error)
    end

    private

    # The constraint, the locks and the revalidation make this rare, so a translation here is worth a trace: ids only, no PII.
    def conflict!(error)
      Rails.error.report(error, handled: true, context: { company_id: @company.id, branch_id: @branch.id, professional_id: professional.id,
                                                          starts_at: @starts_at.iso8601 })
      raise SlotUnavailable
    end

    def violated_constraint(error) = error.cause.try(:result)&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)

    def professional = @choice.professional

    def local_date = @starts_at.in_time_zone(@branch.time_zone).to_date

    def validate_input!
      errors = []
      errors << { field: :customer_id, code: :invalid } unless Customers::Lookup.active_id?(id: @customer_id, company: @company)
      errors << { field: :source, code: :invalid } unless Appointment::SOURCES.include?(@source)
      errors << { field: :notes, code: :too_long } if @notes && @notes.length > NOTES_MAX_LENGTH
      errors.concat(starts_at_errors)
      errors << { field: :professional_id, code: :any_not_allowed } if @choice.any?
      raise InvalidBooking, errors if errors.any?
    end

    # A past start is one error here, before the engine's own range check could report it as a different one.
    def starts_at_errors
      return [ { field: :starts_at, code: :blank } ] unless @starts_at.is_a?(Time)
      return [ { field: :starts_at, code: :in_the_past } ] if @starts_at < @now

      @starts_at.sec.zero? && @starts_at.subsec.zero? ? [] : [ { field: :starts_at, code: :not_on_minute } ]
    end

    # Always in this order (person, then resource), so two bookings can never wait on each other. The lock is held until the
    # outermost transaction ends, so whoever waits reads the winner's committed rows.
    # The keys carry the organization so two tenants never contend for (or collide on) the same lock.
    def lock_person = advisory_lock("appointments.person:#{@company.organization_id}:#{professional.user_id || professional.id}")

    def lock_resource(kind) = (advisory_lock("appointments.resource:#{@company.organization_id}:#{@branch.id}:#{kind}") if kind)

    def advisory_lock(name)
      ApplicationRecord.connection.select_value("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", "Appointments::Book lock", [ name ])
    end

    # The engine is the authority on what can be booked now: a stale answer (a cache, a page left open) ends here as a conflict.
    def revalidate(eligibility)
      result = Availability.call(company: @company, branch: @branch, services: @services, professional: @choice, from_date: local_date, to_date: local_date,
                                 now: @now, booking_window: WINDOW_BY_SOURCE.fetch(@source), eligibility:)
      slot = result.slots.find { it.starts_at == @starts_at } || raise(SlotUnavailable)
      [ slot, result.plan ]
    end

    # The engine reads one company's agenda; the same person (user) may have another record elsewhere in the organization, and
    # that agenda counts too, so this is NOT filtered by company.
    def ensure_person_free(slot, plan)
      return unless professional.user_id

      others = Professional.where(user_id: professional.user_id).where.not(id: professional.id).select(:id)
      busy = Appointment.blocking.where(professional_id: others).overlapping(*block_of(slot, plan)).exists?
      raise PersonUnavailable if busy
    end

    def block_of(slot, plan) = [ slot.starts_at - plan.buffer_before_minutes.minutes, slot.ends_at + plan.buffer_after_minutes.minutes ]

    def insert(slot, plan)
      blocks_from, blocks_to = block_of(slot, plan)
      appointment = Appointment.create!(
        company_id: @company.id, branch_id: @branch.id, professional_id: professional.id, resource_id: slot.resource_id, customer_id: @customer_id,
        starts_at: slot.starts_at, ends_at: slot.ends_at, blocks_from:, blocks_to:, status: "scheduled", source: @source, notes: @notes,
        created_by_type: @actor.actor_type, created_by_id: @actor.id, rescheduled_from_id: @rescheduled_from&.id
      )
      # `appointment:` (the record in memory) spares belongs_to its SELECT per line.
      plan.lines.each { |line| AppointmentService.create!(company_id: @company.id, appointment:, **line.to_h) }
      appointment
    end

    def publish_and_audit(appointment, plan)
      Events.publish("appointments.appointment_booked.v1", appointment_id: appointment.id, branch_id: appointment.branch_id,
                                                           professional_id: appointment.professional_id, customer_id: appointment.customer_id,
                                                           resource_id: appointment.resource_id, starts_at: appointment.starts_at, ends_at: appointment.ends_at,
                                                           service_ids: plan.lines.map(&:service_id), source: appointment.source,
                                                           rescheduled_from_id: appointment.rescheduled_from_id,
                                                           metadata: { company_id: @company.id, branch_id: @branch.id })
      Audit.record(action: "appointments.appointment.booked", subject: appointment, after: appointment.attributes.slice(*AUDITED_FIELDS), actor: @actor,
                   metadata: money_snapshot(plan))
    end

    # What was charged, as booked: the lines are immutable but the total is derived, so the audit trail keeps both.
    def money_snapshot(plan)
      { total_price_minor: plan.price_minor, currency: plan.currency,
        services: plan.lines.map { |line| line.to_h.slice(*AUDITED_LINE_FIELDS) } }
    end
  end
end
