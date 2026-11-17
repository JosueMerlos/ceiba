module Appointments
  # The booking request itself is wrong (customer, source, notes, start, professional).
  class InvalidBooking < FieldErrors; end
end
