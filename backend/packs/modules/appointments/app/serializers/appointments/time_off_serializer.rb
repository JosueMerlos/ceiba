module Appointments
  # Fields match components.schemas.TimeOff EXACTLY: the interval is UTC.
  class TimeOffSerializer < Api::Serializer
    attributes :id, :professional_id, :resource_id, :reason, starts_at: :iso8601, ends_at: :iso8601, created_at: :iso8601
  end
end
