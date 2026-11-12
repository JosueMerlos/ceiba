module Appointments
  # Fields match components.schemas.AvailabilitySlot EXACTLY: the instants are UTC. Only ids and instants: no names, no
  # appointment or customer data, so the anonymous endpoint can use it as is.
  class AvailabilitySlotSerializer < Api::Serializer
    attributes :professional_id, :resource_id
    attributes starts_at: :iso8601, ends_at: :iso8601
  end
end
