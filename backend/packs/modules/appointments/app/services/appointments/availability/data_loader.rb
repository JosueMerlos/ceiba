module Appointments
  module Availability
    # The only place that loads the calculation inputs. It issues a FIXED set of queries whatever the number of days, services,
    # professionals or resources asked for, and returns plain values for the pure core. Must run inside a tenant context.
    class DataLoader
      # Every field but the plan's own is a Calculator keyword, so a Loaded splats straight into it (the plan too).
      Loaded = Data.define(:step_minutes, :min_lead_minutes, :max_advance_days, :plan, :branch_slots, :professionals, :resources,
                           :load_by_day)

      # The range runs from local midnight of from_date - 1 to that of to_date + 2: to_date + 1 is the exclusive end of the asked
      # dates and the extra day on each side covers the zone offset at the borders.
      MARGIN_BEFORE_DAYS = 1
      MARGIN_AFTER_DAYS = 2

      def self.call(...) = new(...).call

      # `requirements` is the [[service_id, kind]] list eligibility already read, so it is not read twice.
      def initialize(company:, branch:, services:, professional:, from_date:, to_date:, requirements:)
        @company = company
        @branch = branch
        @services = services
        @professional = professional
        @requirements = requirements
        @zone = ActiveSupport::TimeZone[branch.time_zone]
        @range_from = (from_date - MARGIN_BEFORE_DAYS).in_time_zone(@zone).utc
        @range_to = (to_date + MARGIN_AFTER_DAYS).in_time_zone(@zone).utc
      end

      def call
        settings = Modules.settings_for(:appointments, company: @company, branch: @branch)
        plan = service_plan
        professional_ids = eligible_professional_ids
        kind_by_resource = resources_for(plan.required_kind)
        resource_ids = kind_by_resource.keys
        weekly = weekly_slots(professional_ids, resource_ids)
        busy_rows = busy_appointments(:professional_id, professional_ids)

        Loaded.new(step_minutes: settings.fetch("slot_step_minutes"), min_lead_minutes: settings.fetch("min_lead_time_minutes"),
                   max_advance_days: settings.fetch("max_advance_days"), plan:, branch_slots: weekly.fetch(:branch),
                   professionals: owners(professional_ids, weekly[:professional], time_offs(:professional_id, professional_ids), busy_rows),
                   resources: owners(resource_ids, weekly[:resource], time_offs(:resource_id, resource_ids), busy_appointments(:resource_id, resource_ids))
                                .map { |own| own.merge(kind: kind_by_resource.fetch(own[:id])) },
                   load_by_day: load_by_day(busy_rows))
      end

      private

      def service_ids = @services.map(&:id)

      def service_plan
        overrides = BranchServiceOverride.where(company_id: @company.id, branch_id: @branch.id, service_id: service_ids)
                                         .pluck(:service_id, :duration_minutes, :price_minor)
                                         .to_h { |id, duration, price| [ id, { duration_minutes: duration, price_minor: price } ] }
        kinds = @requirements.group_by(&:first)
        items = @services.map do |service|
          ServicePlan::Item.new(id: service.id, duration_minutes: service.duration_minutes, buffer_before_minutes: service.buffer_before_minutes,
                                buffer_after_minutes: service.buffer_after_minutes, price_minor: service.price_minor,
                                required_kinds: kinds.fetch(service.id, []).map(&:last))
        end
        ServicePlan.call(services: items, overrides:, currency: @company.currency)
      end

      # A concrete professional was already checked by the eligibility step; with any, the active ones assigned to the branch who
      # provide EVERY requested service (one query).
      def eligible_professional_ids
        return [ @professional.professional.id ] unless @professional.any?

        provided = ProfessionalService.where(company_id: @company.id, service_id: service_ids)
                                      .group(:professional_id).having("COUNT(DISTINCT service_id) = ?", service_ids.uniq.size).select(:professional_id)
        Professional.active.assigned_to(@branch).where(id: provided).order(:id).pluck(:id)
      end

      # { resource id => kind } of the resources of this branch that can be offered for the required kind; none when no kind is
      # required.
      def resources_for(kind)
        return {} unless kind

        Resource.active.where(company_id: @company.id, branch_id: @branch.id, kind:).order(:id).pluck(:id, :kind).to_h
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

      # Blocking appointments of the owners (professionals or resources). One agenda per person: appointments in any branch occupy
      # the professional. Rows of [owner id, blocks_from, blocks_to, starts_at], grouped by owner id.
      def busy_appointments(column, ids)
        return {} if ids.empty?

        Appointment.blocking.where(company_id: @company.id, column => ids).overlapping(@range_from, @range_to)
                   .pluck(column, :blocks_from, :blocks_to, :starts_at).group_by(&:first)
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
