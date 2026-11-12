module Appointments
  module Availability
    # Turns free intervals into bookable slots. Starts sit on a wall-clock grid: the local minute of the day is a multiple of
    # the step (so a 45-minute step still lands on 00:00, 00:45...). Lead time and advance window are measured from `now`.
    module SlotFinder
      MINUTE = 1.minute.to_i
      DAY_MINUTES = 1.day.in_minutes.to_i
      private_constant :MINUTE, :DAY_MINUTES

      module_function

      # Lower bounds round UP and upper bounds DOWN to whole seconds, so a slot never reaches into an absence or a lead window by
      # a fraction of a second.
      def call(free:, duration_minutes:, step_minutes:, time_zone:, now:, min_lead_minutes:, max_advance_days:)
        zone = TZInfo::Timezone.get(time_zone)
        earliest = (now.to_r + min_lead_minutes.minutes.to_i).ceil
        latest = now.to_i + max_advance_days.days.to_i
        duration = duration_minutes.minutes.to_i

        free.intervals.flat_map do |interval|
          first = [ interval.starts_at.to_r.ceil, earliest ].max
          last = [ interval.ends_at.to_i - duration, latest ].min
          candidates(zone, first, last, step_minutes).map do |start|
            Interval.new(starts_at: Time.at(start).utc, ends_at: Time.at(start + duration).utc)
          end
        end
      end

      # Epoch seconds of every grid start in [first, last].
      def candidates(zone, first, last, step)
        starts = []
        current = align(zone, first, step)
        while current <= last
          starts << current
          current = align(zone, current + MINUTE, step)
        end
        starts
      end
      private_class_method :candidates

      # Smallest grid instant >= seconds. Jumps never cross a UTC offset change: after one, the wall clock is re-read, so a
      # nonexistent hour is skipped and a repeated hour yields both of its occurrences.
      def align(zone, seconds, step)
        current = (seconds + MINUTE - 1) / MINUTE * MINUTE
        loop do
          period = zone.period_for_utc(Time.at(current).utc)
          minute = ((current + period.utc_total_offset) / MINUTE) % DAY_MINUTES
          return current if (minute % step).zero?

          jump = [ step - (minute % step), DAY_MINUTES - minute ].min.minutes.to_i
          transition = period.end_transition&.at&.to_i
          current = transition && transition < current + jump ? transition : current + jump
        end
      end
      private_class_method :align
    end
  end
end
