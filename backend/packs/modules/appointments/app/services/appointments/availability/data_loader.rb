module Appointments
  module Availability
    # The only place that loads the calculation inputs. It issues a FIXED set of queries whatever the number of days, services,
    # professionals or resources asked for (settings, overrides, resource requirements, eligible professionals, candidate
    # resources, weekly hours, absences, blocking appointments) and returns plain values for the pure core. Must run inside a
    # tenant context.
    class DataLoader
      # Every field but the plan's own is a Calculator keyword, so a Loaded splats straight into it (the plan too).
      Loaded = Data.define(:step_minutes, :min_lead_minutes, :max_advance_days, :plan, :branch_slots, :professionals, :resources,
                           :required_kinds, :load_by_day)

      # The range runs from local midnight of from_date - 1 to that of to_date + 2: to_date + 1 is the exclusive end of the asked
      # dates and the extra day on each side covers the zone offset at the borders.
      MARGIN_BEFORE_DAYS = 1
      MARGIN_AFTER_DAYS = 2

      def self.call(...) = new(...).call

      def initialize(company:, branch:, services:, professional:, from_date:, to_date:)
        @company = company
        @branch = branch
        @services = services
        @professional = professional
        @zone = ActiveSupport::TimeZone[branch.time_zone]
        @range_from = (from_date - MARGIN_BEFORE_DAYS).in_time_zone(@zone).utc
        @range_to = (to_date + MARGIN_AFTER_DAYS).in_time_zone(@zone).utc
      end

      def call
        settings = Modules.settings_for(:appointments, company: @company, branch: @branch)
        plan = service_plan
        professional_ids = eligible_professional_ids
        resource_rows = plan.required_kinds.any? ? candidate_resources(plan.required_kinds) : []
        weekly = weekly_slots(professional_ids, resource_rows.map(&:first))
        busy_rows = busy_appointments(professional_ids)

        Loaded.new(step_minutes: settings.fetch("slot_step_minutes"), min_lead_minutes: settings.fetch("min_lead_time_minutes"),
                   max_advance_days: settings.fetch("max_advance_days"), plan:, branch_slots: weekly.fetch(:branch),
                   professionals: owners(professional_ids, weekly[:professional], time_offs(:professional_id, professional_ids), busy_rows),
                   resources: owners(resource_rows.map(&:first), weekly[:resource], time_offs(:resource_id, resource_rows.map(&:first)), {})
                                .map { |own| own.merge(kind: resource_rows.to_h.fetch(own[:id])) },
                   required_kinds: plan.required_kinds, load_by_day: load_by_day(busy_rows))
      end

      private

      def service_ids = @services.map(&:id)

      def service_plan
        overrides = BranchServiceOverride.where(company_id: @company.id, branch_id: @branch.id, service_id: service_ids)
                                         .pluck(:service_id, :duration_minutes, :price_minor)
                                         .to_h { |id, duration, price| [ id, { duration_minutes: duration, price_minor: price } ] }
        kinds = ServiceResourceRequirement.where(company_id: @company.id, service_id: service_ids).pluck(:service_id, :kind).group_by(&:first)
        items = @services.map do |service|
          ServicePlan::Item.new(id: service.id, duration_minutes: service.duration_minutes, buffer_before_minutes: service.buffer_before_minutes,
                                buffer_after_minutes: service.buffer_after_minutes, price_minor: service.price_minor,
                                required_kinds: kinds.fetch(service.id, []).map(&:last))
        end
        ServicePlan.call(services: items, overrides:, currency: @company.currency)
      end

      # A concrete professional was already checked by the eligibility step; with :any, the active ones assigned to the branch who
      # provide EVERY requested service (one query).
      def eligible_professional_ids
        return [ @professional.id ] unless @professional == :any

        provided = ProfessionalService.where(company_id: @company.id, service_id: service_ids)
                                      .group(:professional_id).having("COUNT(DISTINCT service_id) = ?", service_ids.uniq.size).select(:professional_id)
        assigned = ProfessionalBranchAssignment.where(company_id: @company.id, branch_id: @branch.id).select(:professional_id)
        Professional.active.where(company_id: @company.id, id: assigned).where(id: provided).order(:id).pluck(:id)
      end

      # [[id, kind]] of the resources of this branch that can be offered.
      def candidate_resources(kinds)
        Resource.active.where(company_id: @company.id, branch_id: @branch.id, kind: kinds).order(:id).pluck(:id, :kind)
      end

      # Branch hours plus the hours of each professional and resource at this branch, in one query, as
      # { branch: [WeeklySlot], professional: { id => [WeeklySlot] }, resource: { id => [WeeklySlot] } }.
      def weekly_slots(professional_ids, resource_ids)
        scope = WeeklySchedule.where(company_id: @company.id, branch_id: @branch.id)
        rows = scope.where(owner_type: "branch").or(scope.where(professional_id: professional_ids)).or(scope.where(resource_id: resource_ids))
                    .pluck(:owner_type, :professional_id, :resource_id, :weekday, :starts_at_local, :ends_at_local)
        grouped = { branch: [], professional: Hash.new { |h, k| h[k] = [] }, resource: Hash.new { |h, k| h[k] = [] } }
        rows.each do |owner_type, professional_id, resource_id, weekday, from, to|
          value = WeeklySlot.new(weekday:, starts_minute: minutes(from), ends_minute: minutes(to))
          owner_type == "branch" ? grouped[:branch] << value : grouped.fetch(owner_type.to_sym)[professional_id || resource_id] << value
        end
        grouped
      end

      # `time` columns come back as a Time on a dummy date; only the wall-clock minute of the day matters.
      def minutes(time) = (time.hour.hours + time.min.minutes).in_minutes.to_i

      # The `company_id` filters below are defense in depth for non-HTTP callers; the composite FKs already prevent cross-company rows.
      # The absence belongs to the person or the resource, so it counts in every branch. { owner id => [Interval] }.
      def time_offs(column, ids)
        return {} if ids.empty?

        rows = TimeOff.where(company_id: @company.id, column => ids).overlapping(@range_from, @range_to).pluck(column, :starts_at, :ends_at)
        rows.group_by(&:first).transform_values { |own| intervals(own.map { |_, from, to| [ from, to ] }) }
      end

      # One agenda per person: appointments in any branch occupy the professional. Rows of [professional_id, blocks_from, blocks_to,
      # starts_at].
      def busy_appointments(professional_ids)
        return {} if professional_ids.empty?

        Appointment.blocking.where(company_id: @company.id, professional_id: professional_ids).overlapping(@range_from, @range_to)
                   .pluck(:professional_id, :blocks_from, :blocks_to, :starts_at).group_by(&:first)
      end

      def owners(ids, weekly, time_offs, busy)
        ids.map do |id|
          own_busy = busy.fetch(id, []).map { |_, from, to, _| [ from, to ] }
          { id:, slots: weekly.to_h.fetch(id, []), time_offs: time_offs.fetch(id, []), busy: intervals(own_busy) }
        end
      end

      # Blocking appointments per professional and LOCAL day of their start, whatever branch they are in.
      def load_by_day(busy_rows)
        busy_rows.transform_values { |rows| rows.map { |*, starts_at| starts_at.in_time_zone(@zone).to_date }.tally }
      end

      # A row whose interval is empty or inverted occupies nothing.
      def intervals(rows) = rows.filter_map { |from, to| Interval.new(starts_at: from, ends_at: to) if from < to }
    end
  end
end
