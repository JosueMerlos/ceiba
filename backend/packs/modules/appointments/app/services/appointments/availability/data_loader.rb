module Appointments
  module Availability
    # The only place that loads the calculation inputs. It issues a FIXED set of queries whatever the number of days asked
    # for (settings, duration override, weekly hours, absences, blocking appointments) and returns plain values for the pure
    # core. Must run inside a tenant context.
    class DataLoader
      # Every field is a Calculator keyword, so a Loaded splats straight into it.
      Loaded = Data.define(:step_minutes, :min_lead_minutes, :max_advance_days, :duration_minutes, :branch_slots, :professional_slots,
                           :time_offs, :busy)

      # The range runs from local midnight of from_date - 1 to that of to_date + 2: to_date + 1 is the exclusive end of the asked
      # dates and the extra day on each side covers the zone offset at the borders.
      MARGIN_BEFORE_DAYS = 1
      MARGIN_AFTER_DAYS = 2

      def self.call(...) = new(...).call

      def initialize(company:, branch:, service:, professional:, from_date:, to_date:)
        @company = company
        @branch = branch
        @service = service
        @professional = professional
        @zone = ActiveSupport::TimeZone[branch.time_zone]
        @range_from = (from_date - MARGIN_BEFORE_DAYS).in_time_zone(@zone).utc
        @range_to = (to_date + MARGIN_AFTER_DAYS).in_time_zone(@zone).utc
      end

      def call
        branch_slots, professional_slots = weekly_slots
        settings = Modules.settings_for(:appointments, company: @company, branch: @branch)
        Loaded.new(step_minutes: settings.fetch("slot_step_minutes"), min_lead_minutes: settings.fetch("min_lead_time_minutes"),
                   max_advance_days: settings.fetch("max_advance_days"), duration_minutes: override_duration || @service.duration_minutes,
                   branch_slots:, professional_slots:, time_offs:, busy:)
      end

      private

      def override_duration
        BranchServiceOverride.where(company_id: @company.id, service_id: @service.id, branch_id: @branch.id).pick(:duration_minutes)
      end

      # Branch hours and this professional's hours at the branch, in one query.
      def weekly_slots
        rows = WeeklySchedule.where(company_id: @company.id, branch_id: @branch.id)
                             .where("owner_type = 'branch' OR professional_id = ?", @professional.id)
                             .pluck(:owner_type, :weekday, :starts_at_local, :ends_at_local)
        branch_rows, professional_rows = rows.partition { |owner_type, *| owner_type == "branch" }
        [ branch_rows, professional_rows ].map { |owned| owned.map { |_, weekday, from, to| slot(weekday, from, to) } }
      end

      def slot(weekday, from, to) = WeeklySlot.new(weekday:, starts_minute: minutes(from), ends_minute: minutes(to))

      # `time` columns come back as a Time on a dummy date; only the wall-clock minute of the day matters.
      def minutes(time) = (time.hour.hours + time.min.minutes).in_minutes.to_i

      # The `company_id` filters below are defense in depth for non-HTTP callers; the composite FKs already prevent cross-company rows.
      # The absence belongs to the person, so it counts in every branch.
      def time_offs
        intervals(TimeOff.where(company_id: @company.id, professional_id: @professional.id).overlapping(@range_from, @range_to).pluck(:starts_at, :ends_at))
      end

      # One agenda per person: appointments in any branch occupy the professional.
      def busy
        intervals(Appointment.blocking.where(company_id: @company.id, professional_id: @professional.id).overlapping(@range_from, @range_to)
                             .pluck(:blocks_from, :blocks_to))
      end

      # A row whose interval is empty or inverted occupies nothing.
      def intervals(rows) = rows.filter_map { |from, to| Interval.new(starts_at: from, ends_at: to) if from < to }
    end
  end
end
