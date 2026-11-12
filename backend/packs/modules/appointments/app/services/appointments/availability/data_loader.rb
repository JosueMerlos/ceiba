module Appointments
  module Availability
    # The only place of the availability engine that touches the database. It issues a FIXED set of queries whatever the
    # number of days asked for (settings, duration override, weekly hours, absences, blocking appointments) and returns plain
    # values for the pure core. Must run inside a tenant context.
    class DataLoader
      Loaded = Data.define(:settings, :duration_minutes, :branch_slots, :professional_slots, :time_offs, :busy)

      # A day on each side of the asked dates covers the zone offset at the borders.
      MARGIN_BEFORE_DAYS = 1
      MARGIN_AFTER_DAYS = 2
      MINUTES_IN_HOUR = 60

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
        slots = weekly_slots
        Loaded.new(settings: Modules.settings_for(:appointments, company: @company, branch: @branch),
                   duration_minutes: override_duration || @service.duration_minutes,
                   branch_slots: slots.fetch("branch", []), professional_slots: slots.fetch("professional", []),
                   time_offs: time_offs, busy: busy)
      end

      private

      def override_duration
        BranchServiceOverride.where(service_id: @service.id, branch_id: @branch.id).pick(:duration_minutes)
      end

      # Branch hours and this professional's hours at the branch, in one query, grouped by owner.
      def weekly_slots
        WeeklySchedule.where(branch_id: @branch.id)
                      .where("owner_type = 'branch' OR professional_id = ?", @professional.id)
                      .pluck(:owner_type, :weekday, :starts_at_local, :ends_at_local)
                      .group_by(&:first)
                      .transform_values { |rows| rows.map { |_, weekday, from, to| slot(weekday, from, to) } }
      end

      def slot(weekday, from, to) = { weekday:, starts_minute: minutes(from), ends_minute: minutes(to) }

      # `time` columns come back as a Time on a dummy date; only the wall-clock minute of the day matters.
      def minutes(time) = (time.hour * MINUTES_IN_HOUR) + time.min

      # The absence belongs to the person, so it counts in every branch.
      def time_offs
        intervals(TimeOff.where(professional_id: @professional.id).overlapping(@range_from, @range_to).pluck(:starts_at, :ends_at))
      end

      # One agenda per person: appointments in any branch occupy the professional.
      def busy
        intervals(Appointment.blocking.where(professional_id: @professional.id).overlapping(@range_from, @range_to)
                             .pluck(:blocks_from, :blocks_to))
      end

      # A row whose interval is empty or inverted occupies nothing.
      def intervals(rows) = rows.filter_map { |from, to| Interval.new(starts_at: from, ends_at: to) if from < to }
    end
  end
end
