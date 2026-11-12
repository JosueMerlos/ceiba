module Appointments
  module Availability
    # Pure orchestration of the availability core: open hours (branch and professional) minus absences and blocking
    # appointments, then slots on the grid. Everything comes in as values and goes out as UTC intervals.
    module Calculator
      module_function

      def call(branch_slots:, professional_slots:, time_offs:, busy:, time_zone:, from_date:, to_date:, duration_minutes:, step_minutes:,
               now:, min_lead_minutes:, max_advance_days:)
        branch_open = WeeklyExpander.call(slots: branch_slots, time_zone:, from_date:, to_date:)
        professional_open = WeeklyExpander.call(slots: professional_slots, time_zone:, from_date:, to_date:)
        free = branch_open.intersect(professional_open).subtract(IntervalSet.new(time_offs)).subtract(IntervalSet.new(busy))

        SlotFinder.call(free:, duration_minutes:, step_minutes:, time_zone:, now:, min_lead_minutes:, max_advance_days:)
      end
    end
  end
end
