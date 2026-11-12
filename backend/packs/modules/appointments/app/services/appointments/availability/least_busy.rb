module Appointments
  module Availability
    # Picks, among the candidates free at a start, the one with the fewest blocking appointments on that local day (ties go to
    # the lowest id). `load_by_day` is { professional_id => { Date => count } }; a missing entry is no load.
    module LeastBusy
      module_function

      def call(candidates:, load_by_day:, day:)
        candidates.min_by { |id| [ load_by_day.dig(id, day) || 0, id ] }
      end
    end
  end
end
