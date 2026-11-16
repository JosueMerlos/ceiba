module Appointments
  # The cancellation request itself is wrong (a reason missing or outside the list).
  class InvalidCancellation < FieldErrors; end
end
