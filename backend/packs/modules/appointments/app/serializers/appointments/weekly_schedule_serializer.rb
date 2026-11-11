module Appointments
  # Fields match components.schemas.WeeklyScheduleSlot EXACTLY: the hours are local wall-clock "HH:MM".
  class WeeklyScheduleSerializer < Api::Serializer
    attributes :id, :weekday

    attribute(:starts_at_local) { |slot| WeeklySchedule.clock(slot.starts_at_local) }
    attribute(:ends_at_local) { |slot| WeeklySchedule.clock(slot.ends_at_local) }
  end
end
