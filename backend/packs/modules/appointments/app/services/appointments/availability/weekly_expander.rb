module Appointments
  module Availability
    # Expands weekly local-time slots into UTC intervals, day by day, in the branch's zone. This is the single place where
    # local wall-clock time becomes UTC.
    #
    # DST: a nonexistent local time (spring gap) is clamped to the transition instant, and an ambiguous one (fall repeat)
    # takes its first occurrence. ActiveSupport::TimeZone#local is avoided on purpose: it shifts a gap time forward an hour.
    module WeeklyExpander
      # Longest gap probed (in 30-minute steps) when looking for the end of a nonexistent local time.
      GAP_PROBE_STEPS = 48
      private_constant :GAP_PROBE_STEPS

      module_function

      # slots: WeeklySlot values.
      def call(slots:, time_zone:, from_date:, to_date:)
        zone = TZInfo::Timezone.get(time_zone)
        by_weekday = slots.group_by(&:weekday)
        intervals = (from_date..to_date).flat_map do |date|
          by_weekday.fetch(date.wday, []).filter_map { |slot| expand_slot(zone, date, slot) }
        end
        IntervalSet.new(intervals)
      end

      def expand_slot(zone, date, slot)
        starts_at = to_utc(zone, date, slot.starts_minute)
        ends_at = to_utc(zone, date, slot.ends_minute)
        Interval.new(starts_at:, ends_at:) if starts_at < ends_at
      end
      private_class_method :expand_slot

      def to_utc(zone, date, minute)
        local = Time.utc(date.year, date.month, date.day) + (minute * 60)
        zone.local_to_utc(local, true)
      rescue TZInfo::PeriodNotFound
        gap_end(zone, local)
      end
      private_class_method :to_utc

      # Instant at which the period that follows the gap begins (the transition itself).
      def gap_end(zone, local)
        probe = (1..GAP_PROBE_STEPS).lazy.map { |step| local + (step * 1800) }.find do |candidate|
          zone.period_for_local(candidate)
        rescue TZInfo::PeriodNotFound
          false
        end
        zone.period_for_local(probe).start_transition.at.to_time.utc
      end
      private_class_method :gap_end
    end
  end
end
