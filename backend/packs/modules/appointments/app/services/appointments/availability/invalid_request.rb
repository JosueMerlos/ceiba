module Appointments
  module Availability
    # The request cannot be answered as asked (an inactive professional, a service nobody provides, a bad range).
    class InvalidRequest < FieldErrors; end
  end
end
