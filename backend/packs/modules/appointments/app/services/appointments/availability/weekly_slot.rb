module Appointments
  module Availability
    # One weekly opening in local wall-clock time: weekday 0 = Sunday, minutes counted from local midnight.
    WeeklySlot = Data.define(:weekday, :starts_minute, :ends_minute)
  end
end
