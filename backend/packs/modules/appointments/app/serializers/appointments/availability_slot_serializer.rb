module Appointments
  # Fields match components.schemas.AvailabilitySlot EXACTLY: the instants are UTC.
  class AvailabilitySlotSerializer < Api::Serializer
    attributes starts_at: :iso8601, ends_at: :iso8601
  end
end
