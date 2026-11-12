module Appointments
  module Availability
    # One bookable start: the service itself runs [starts_at, ends_at); `resource_id` is nil when no resource is needed.
    Slot = Data.define(:starts_at, :ends_at, :professional_id, :resource_id)
  end
end
